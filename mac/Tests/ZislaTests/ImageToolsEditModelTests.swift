import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ImageToolsEditModelTests {
    private let service = ImageProcessingService(executableURL: nil)

    @Test
    func editorLoadsFullResolutionAndExistingEditWithoutChangingOriginals() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        model.inputs = [fixture.input]
        let prepare = try #require(model.prepareEditor(fixture.input, service: service))
        await prepare.value
        let loaded = try #require(model.editorInput)
        #expect(loaded.inputURL == fixture.input)
        #expect(loaded.image.size == NSSize(width: 1600, height: 3))
        let image = try Fixture.image(width: 40, height: 20, red: 200, alpha: 128)
        await model.recordEdit(image, for: fixture.input)?.value
        #expect(model.editorInput?.image === loaded.image && !model.isProcessing)
        await model.prepareEditor(fixture.input, service: service)?.value
        let reopened = try #require(model.editorInput?.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(reopened.width == 40 && reopened.height == 20)
        #expect(try Fixture.bytes(reopened) == Fixture.bytes(image))
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
        model.discardEdits()
    }

    @Test
    func canceledEditorLoadCannotPresentAnImageOrEraseCurrentInputs() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let started = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish(); resume.continuation.finish() }
        let image = try Fixture.image()
        let canceled = CancellationProbe()
        let model = ImageToolsModel()
        model.inputs = [fixture.input]
        let pending = model.prepareEditor(fixture.input, service: service, loadImage: { _ in
            #expect(!Self.isOnMainThread(), "Full-resolution image decoding must stay outside the UI thread")
            return await withTaskCancellationHandler {
                started.continuation.yield()
                for await _ in resume.stream { break }
                return image
            } onCancel: { canceled.cancel() }
        })
        let task = try #require(pending)
        for await _ in started.stream { break }
        model.cancel()
        #expect(canceled.value, "Canceling the editor must cancel its active image decoder")
        #expect(model.prepareEditor(fixture.input, service: service) == nil)
        resume.continuation.yield()
        await task.value
        #expect(!model.isProcessing && model.editorInput == nil)
        #expect(model.message == AppLocalization.text("已取消"))
        #expect(model.inputs == [fixture.input])
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
    }

    @Test
    func invalidEditorInputLeavesNoPresentationOrCachedEdits() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        await model.prepareEditor(fixture.root.appendingPathComponent("missing.png"), service: service)?.value
        #expect(model.editorInput == nil && model.editedImageURLs.isEmpty)
        #expect(!model.isProcessing && model.message != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == [fixture.input.lastPathComponent])
    }

    @Test
    func replacingAnEditRemovesItsOldFileAndInvalidatesThePreviousBatch() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        let image = try Fixture.image()
        await model.recordEdit(image, for: fixture.input)?.value
        let first = try #require(model.editedImageURLs[fixture.input])
        let directory = first.deletingLastPathComponent()
        #expect(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int == 0o700)
        model.startEdited(service: service)
        await finished(model)
        let previousBatch = try #require(model.batch?.directoryURL)
        let replacement = try Fixture.image(red: 220)
        await model.recordEdit(replacement, for: fixture.input)?.value
        let second = try #require(model.editedImageURLs[fixture.input])
        #expect(second != first)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: previousBatch.path) && model.batch == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [second.lastPathComponent])
        let actual = try await service.loadRasterImage(second)
        #expect(try Fixture.bytes(actual) == Fixture.bytes(replacement))
        model.discardEdits()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
    }

    @Test
    func editedBatchOnlyContainsEditedInputsAndKeepsTransparentPixelsAndComparisonSources() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let second = fixture.root.appendingPathComponent("second.png")
        let unedited = fixture.root.appendingPathComponent("unedited.png")
        try fixture.original.write(to: second)
        try fixture.original.write(to: unedited)
        let image = try Fixture.image(red: 110, alpha: 128)
        let model = ImageToolsModel()
        model.inputs = [fixture.input, second, unedited]
        for input in [fixture.input, second] { await model.recordEdit(image, for: input)?.value }
        model.startEdited(service: service)
        await finished(model)
        let batch = try #require(model.batch)
        #expect(batch.failures.isEmpty && batch.items.count == 2)
        #expect(Set(batch.items.map(\.inputURL)) == [fixture.input, second])
        for item in batch.items {
            #expect(try Data(contentsOf: item.sourceURL) == fixture.original)
            let output = try #require(item.outputs.first)
            #expect(output.format == .png && output.summary.frameCount == 1)
            let actual = try await service.loadRasterImage(output.url)
            #expect(try Fixture.bytes(actual) == Fixture.bytes(image))
        }
        for input in model.inputs { #expect(try Data(contentsOf: input) == fixture.original) }
        model.discardResults()
        model.discardEdits()
    }

    @Test
    func missingEditsAndFailedReopenedCacheReportFailureWithoutModifyingOriginals() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        model.startEdited(service: service)
        #expect(model.batch == nil && !model.isProcessing && model.message == AppLocalization.text("请先编辑需要处理的图片"))
        let image = try Fixture.image()
        await model.recordEdit(image, for: fixture.input)?.value
        let cache = try #require(model.editedImageURLs[fixture.input])
        try FileManager.default.removeItem(at: cache)
        model.startEdited(service: service)
        await finished(model)
        let batch = try #require(model.batch)
        #expect(batch.items.isEmpty && batch.failures.count == 1)
        #expect(batch.failures.first?.inputURL == fixture.input)
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
        model.discardResults()
        model.discardEdits()
    }

    @Test
    func cancelingOrRejectingAnEditLeavesNoPartialPNG() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        let image = try Fixture.unreadImage(width: 40, height: 20)
        let task = try #require(model.recordEdit(image, for: fixture.input))
        #expect(model.recordEdit(image, for: fixture.input) == nil)
        model.discardEdits()
        model.cancel()
        await task.value
        #expect(model.editedImageURLs.isEmpty && !model.isProcessing)
        #expect(model.message == AppLocalization.text("已取消"))
        let oversized = try Fixture.image(width: 150_001, height: 1)
        await model.recordEdit(oversized, for: fixture.input)?.value
        #expect(model.editedImageURLs.isEmpty && model.message == ImageProcessingError.resourceLimit.localizedDescription)
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
        await model.recordEdit(try Fixture.image(), for: fixture.input)?.value
        #expect(model.editedImageURLs[fixture.input] != nil && model.message == nil,
                "A successful edit must clear a previous failed attempt")
        model.discardEdits()
    }

    @Test(arguments: [(150_001, 1), (1, 150_001), (16_001, 16_001)])
    func excessiveEditsAreRejectedBeforeReadingTheirPixelProvider(size: (Int, Int)) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        let image = try Fixture.unreadImage(width: size.0, height: size.1)
        await model.recordEdit(image, for: fixture.input)?.value
        #expect(model.editedImageURLs.isEmpty && !model.isProcessing)
        #expect(model.message == ImageProcessingError.resourceLimit.localizedDescription)
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
        model.discardEdits()
    }

    @Test
    func busyEditorLoadsKeepTheirCachedFilesUntilTheDecoderCompletes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        let image = try Fixture.image()
        await model.recordEdit(image, for: fixture.input)?.value
        let cache = try #require(model.editedImageURLs[fixture.input])
        let started = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish(); resume.continuation.finish() }
        let pending = model.prepareEditor(fixture.input, service: service, loadImage: { _ in
            started.continuation.yield()
            for await _ in resume.stream { break }
            return image
        })
        let task = try #require(pending)
        for await _ in started.stream { break }
        model.discardEdits()
        model.startEdited(service: service)
        #expect(model.isProcessing && model.editedImageURLs[fixture.input] == cache)
        #expect(FileManager.default.fileExists(atPath: cache.path))
        resume.continuation.yield()
        await task.value
        #expect(!model.isProcessing && model.editorInput != nil && model.batch == nil)
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
        model.discardEdits()
    }

    @Test
    func missingCacheDirectoryIsRecreatedWhenTheUserRetriesAnEdit() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        let image = try Fixture.image()
        await model.recordEdit(image, for: fixture.input)?.value
        let cache = try #require(model.editedImageURLs[fixture.input])
        let directory = cache.deletingLastPathComponent()
        try FileManager.default.removeItem(at: directory)
        let retry = try #require(model.recordEdit(image, for: fixture.input))
        #expect(await retry.value)
        let output = try #require(model.editedImageURLs[fixture.input])
        #expect(!model.isProcessing && output != cache && model.message == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [output.lastPathComponent])
        let actual = try await service.loadRasterImage(output)
        #expect(try Fixture.bytes(actual) == Fixture.bytes(image))
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
        model.discardEdits()
    }

    @Test(arguments: [false, true])
    func editorInputStaysAvailableUntilThePNGIsCommitted(cancel: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        await model.prepareEditor(fixture.input, service: service)?.value
        let loaded = try #require(model.editorInput)
        let gate = PixelGate()
        defer { gate.finish() }
        let save = try #require(model.recordEdit(try Fixture.gatedImage(gate), for: fixture.input))
        await gate.waitUntilStarted()
        #expect(model.editorInput?.image === loaded.image && model.isProcessing)
        #expect(model.editedImageURLs.isEmpty)
        if cancel { save.cancel() }
        gate.finish()
        let succeeded = await save.value
        #expect(succeeded == !cancel && !model.isProcessing)
        if cancel {
            #expect(model.editorInput?.image === loaded.image && model.editedImageURLs.isEmpty)
            #expect(model.message == AppLocalization.text("已取消"))
        } else {
            #expect(model.editorInput?.image === loaded.image && model.editedImageURLs[fixture.input] != nil)
        }
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
        model.discardEdits()
    }

    @Test(arguments: ["destination", "finalize", "directory"])
    func failedPNGSaveKeepsTheEditorOldEditAndExportableBatchForRetry(failure: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        await model.recordEdit(try Fixture.image(), for: fixture.input)?.value
        let previous = try #require(model.editedImageURLs[fixture.input])
        let previousBytes = try Data(contentsOf: previous)
        model.startEdited(service: service)
        await finished(model)
        let batch = try #require(model.batch)
        await model.prepareEditor(fixture.input, service: service)?.value
        let loaded = try #require(model.editorInput)
        let directory = previous.deletingLastPathComponent()
        let replacement = try Fixture.image(red: 230, alpha: 128)
        let save: Task<Bool, Never>?
        if failure == "directory" {
            try FileManager.default.moveItem(at: directory, to: fixture.root.appendingPathComponent("old-edits"))
            try Data("blocked directory".utf8).write(to: directory)
            save = model.recordEdit(replacement, for: fixture.input)
        } else if failure == "finalize" {
            save = model.recordEdit(try Fixture.invalidPixelImage(), for: fixture.input)
        } else {
            let pending = try #require(model.recordEdit(replacement, for: fixture.input))
            try FileManager.default.moveItem(at: directory, to: fixture.root.appendingPathComponent("old-edits"))
            try Data("blocked destination".utf8).write(to: directory)
            save = pending
        }
        if let save { #expect(!(await save.value)) }
        else { #expect(failure == "directory") }
        #expect(!model.isProcessing && model.editorInput?.image === loaded.image)
        #expect(model.editedImageURLs[fixture.input] == previous && model.batch?.directoryURL == batch.directoryURL)
        #expect(model.batch?.items == batch.items)
        #expect(model.message != nil && FileManager.default.fileExists(atPath: batch.directoryURL.path))
        if failure != "finalize" {
            #expect(try String(contentsOf: directory, encoding: .utf8).hasPrefix("blocked"))
            try FileManager.default.removeItem(at: directory)
            try FileManager.default.moveItem(at: fixture.root.appendingPathComponent("old-edits"), to: directory)
        }
        #expect(try Data(contentsOf: previous) == previousBytes)
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(remainingFiles == [previous.lastPathComponent])
        let retry = try #require(model.recordEdit(replacement, for: fixture.input))
        #expect(await retry.value)
        let saved = try #require(model.editedImageURLs[fixture.input])
        #expect(model.editorInput?.image === loaded.image && model.batch == nil && saved != previous && model.message == nil)
        #expect(!FileManager.default.fileExists(atPath: previous.path))
        #expect(!FileManager.default.fileExists(atPath: batch.directoryURL.path))
        let actual = try await service.loadRasterImage(saved)
        #expect(try Fixture.bytes(actual) == Fixture.bytes(replacement))
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
        model.discardEdits()
    }

    @Test(arguments: [false, true])
    func cancelingOrReleasingAnInFlightEncoderCannotPublishOrRetainANewPNG(releaseModel: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var model: ImageToolsModel? = ImageToolsModel()
        await model?.recordEdit(try Fixture.image(), for: fixture.input)?.value
        let cache = try #require(model?.editedImageURLs[fixture.input])
        let directory = cache.deletingLastPathComponent()
        let gate = PixelGate()
        defer { gate.finish() }
        let pending = model?.recordEdit(try Fixture.gatedImage(gate), for: fixture.input)
        let task = try #require(pending)
        await gate.waitUntilStarted()
        if releaseModel { model = nil } else { model?.cancel() }
        gate.finish()
        await task.value
        if releaseModel {
            #expect(!FileManager.default.fileExists(atPath: directory.path))
        } else {
            #expect(model?.editedImageURLs[fixture.input] == cache && model?.isProcessing == false)
            #expect(model?.message == AppLocalization.text("已取消"))
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [cache.lastPathComponent])
            model?.discardEdits()
        }
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
    }

    @Test
    func releasingTheModelRemovesOwnedEditFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var model: ImageToolsModel? = ImageToolsModel()
        let image = try Fixture.image()
        await model?.recordEdit(image, for: fixture.input)?.value
        let directory = try #require(model?.editedImageURLs[fixture.input]?.deletingLastPathComponent())
        weak let released = model
        model = nil
        #expect(released == nil && !FileManager.default.fileExists(atPath: directory.path))
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
    }

    private func finished(_ model: ImageToolsModel) async {
        for await busy in model.$isProcessing.values { if !busy { break } }
    }

    private nonisolated static func isOnMainThread() -> Bool { Thread.isMainThread }

    private final class CancellationProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var canceled = false
        var value: Bool { lock.withLock { canceled } }
        func cancel() { lock.withLock { canceled = true } }
    }

    private final class PixelGate: @unchecked Sendable {
        private let condition = NSCondition()
        private var released = false
        private let started = AsyncStream<Void>.makeStream()

        func waitUntilStarted() async { for await _ in started.stream { break } }

        func read(_ buffer: UnsafeMutableRawPointer, count: Int) -> Int {
            condition.lock()
            started.continuation.yield()
            while !released { condition.wait() }
            condition.unlock()
            buffer.initializeMemory(as: UInt8.self, repeating: 200, count: count)
            return count
        }

        func finish() {
            condition.lock()
            released = true
            condition.broadcast()
            condition.unlock()
            started.continuation.finish()
        }
    }

    private struct Fixture {
        let root: URL
        let input: URL
        let original: Data

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-edit-model-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            input = root.appendingPathComponent("source.png")
            let image = try Self.image(width: 1600, height: 3)
            let destination = try #require(CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
            original = try Data(contentsOf: input)
        }

        static func image(width: Int = 40, height: Int = 20, red: UInt8 = 80, alpha: UInt8 = 255) throws -> CGImage {
            let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.setFillColor(red: CGFloat(red) / 255, green: 0.4, blue: 0.8, alpha: CGFloat(alpha) / 255)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return try #require(context.makeImage())
        }

        static func unreadImage(width: Int, height: Int) throws -> CGImage {
            var callbacks = CGDataProviderDirectCallbacks(version: 0, getBytePointer: nil, releaseBytePointer: nil,
                getBytesAtPosition: { _, buffer, _, count in
                    Issue.record("Rejected or pre-canceled edits must not read their pixels")
                    buffer.initializeMemory(as: UInt8.self, repeating: 0, count: count)
                    return count
                }, releaseInfo: nil)
            let provider = try #require(CGDataProvider(directInfo: nil, size: Int64(width * height * 4), callbacks: &callbacks))
            return try providerImage(provider, width: width, height: height)
        }

        static func invalidPixelImage() throws -> CGImage {
            var callbacks = CGDataProviderDirectCallbacks(version: 0, getBytePointer: nil, releaseBytePointer: nil,
                getBytesAtPosition: { _, _, _, _ in 0 }, releaseInfo: nil)
            let provider = try #require(CGDataProvider(directInfo: nil, size: 40 * 20 * 4, callbacks: &callbacks))
            return try providerImage(provider, width: 40, height: 20)
        }

        static func gatedImage(_ gate: PixelGate) throws -> CGImage {
            let info = Unmanaged.passRetained(gate).toOpaque()
            var callbacks = CGDataProviderDirectCallbacks(version: 0, getBytePointer: nil, releaseBytePointer: nil,
                getBytesAtPosition: { info, buffer, _, count in
                    Unmanaged<PixelGate>.fromOpaque(info!).takeUnretainedValue().read(buffer, count: count)
                }, releaseInfo: { info in Unmanaged<PixelGate>.fromOpaque(info!).release() })
            let provider = try #require(CGDataProvider(directInfo: info, size: 40 * 20 * 4, callbacks: &callbacks))
            return try providerImage(provider, width: 40, height: 20)
        }

        private static func providerImage(_ provider: CGDataProvider, width: Int, height: Int) throws -> CGImage {
            try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        }

        static func bytes(_ image: CGImage) throws -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return bytes
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
