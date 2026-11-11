import AppKit
import Combine
import CoreImage
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ImageToolsExtractionTests {
    private let service = ImageProcessingService(executableURL: nil)

    @Test(arguments: [ScreenshotExtractionMode.foreground, .background])
    func automaticBatchUsesScreenshotMasksAndKeepsTransparentPNGAndComparisonSources(mode: ScreenshotExtractionMode) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let second = fixture.root.appendingPathComponent("second.png")
        try Fixture.write(Fixture.image(width: 12, height: 8, alpha: 128), to: second)
        let original = try Data(contentsOf: second)
        let model = ImageToolsModel()
        model.inputs = [fixture.input, second]
        let operations = Operations()
        let pending = model.startExtraction(service: service, mode: mode, extractImage: { source, operation in
            #expect(!isMainThread(), "Extraction must run outside the UI thread")
            #expect(operation.mode == mode)
            #expect(operation.imageSize == CGSize(width: source.width, height: source.height))
            #expect(operation.regions.isEmpty)
            await operations.append(operation)
            return try masked(source, background: mode == .background)
        })
        let task = try #require(pending)
        await task.value
        let batch = try #require(model.batch)
        #expect(batch.failures.isEmpty && batch.items.count == 2)
        #expect(model.completed == 2 && model.total == 2 && !model.isProcessing)
        let requests = await operations.values
        #expect(requests.count == 2 && requests[0] !== requests[1])
        model.cancel()
        try requests[0].checkCancellation()
        try requests[1].checkCancellation()
        requests[0].cancel()
        try requests[1].checkCancellation()
        for item in batch.items {
            #expect(try Data(contentsOf: item.sourceURL) == Data(contentsOf: item.inputURL))
            let output = try #require(item.outputs.first)
            #expect(output.format == .png && output.summary.frameCount == 1)
            #expect(output.summary.width == item.summary.width && output.summary.height == item.summary.height)
            let source = try await service.loadRasterImage(item.sourceURL)
            let result = try await service.loadRasterImage(output.url)
            let keptX = mode == .foreground ? 2 : source.width - 2
            let removedX = mode == .foreground ? source.width - 2 : 2
            let kept = try pixel(result, x: keptX, y: 2)
            let expected = try pixel(source, x: keptX, y: 2)
            #expect(abs(kept.alphaComponent - expected.alphaComponent) < 0.01)
            #expect(abs(kept.redComponent - expected.redComponent) < 0.02)
            #expect(abs(kept.greenComponent - expected.greenComponent) < 0.02)
            #expect(try pixel(result, x: removedX, y: 2).alphaComponent == 0)
            #expect(try FileManager.default.contentsOfDirectory(at: output.url.deletingLastPathComponent(),
                includingPropertiesForKeys: nil).count == 2, "Only the comparison source and finished PNG should remain")
        }
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
        #expect(try Data(contentsOf: second) == original)
        let directory = batch.directoryURL
        model.discardResults()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test(arguments: [2, 5, 6, 8])
    func extractionReceivesNormalizedOrientationAndExportsNormalizedPixels(orientation: Int) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let image = try Fixture.image()
        try Fixture.write(image, to: fixture.input, properties: [kCGImagePropertyOrientation: orientation])
        let original = try Data(contentsOf: fixture.input)
        let expected = try #require(CIContext().createCGImage(
            CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation)),
            from: CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation)).extent))
        let model = ImageToolsModel()
        model.inputs = [fixture.input]
        let pending = model.startExtraction(service: service, mode: .foreground, extractImage: { source, operation async throws -> CGImage? in
            #expect(source.width == expected.width && source.height == expected.height)
            #expect(operation.imageSize == CGSize(width: expected.width, height: expected.height))
            #expect(try Fixture.bytes(source) == Fixture.bytes(expected))
            return source
        })
        let task = try #require(pending)
        await task.value
        let output = try #require(model.batch?.items.first?.outputs.first)
        let result = try await service.loadRasterImage(output.url)
        #expect(try Fixture.bytes(result) == Fixture.bytes(expected))
        let source = try #require(CGImageSourceCreateWithURL(output.url as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect(try Data(contentsOf: fixture.input) == original)
        model.discardResults()
    }

    @Test(arguments: ["no region", "transparent", "wrong size", "dependency"])
    func failedImageContinuesBatchWithoutPublishingAnInvalidOutput(failure: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let second = fixture.root.appendingPathComponent("second.png")
        try Fixture.write(Fixture.image(width: 12, height: 8), to: second)
        let model = ImageToolsModel()
        model.inputs = [fixture.input, second]
        let pending = model.startExtraction(service: service, mode: .foreground, extractImage: { source, _ in
            guard source.width == 16 else { return try masked(source) }
            switch failure {
            case "no region": return nil
            case "transparent": return try Fixture.image(alpha: 0)
            case "wrong size": return try Fixture.image(width: 15, height: 10)
            default: throw NSError(domain: "ExtractionFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Vision unavailable"])
            }
        })
        let task = try #require(pending)
        await task.value
        let batch = try #require(model.batch)
        #expect(batch.items.map(\.inputURL) == [second])
        #expect(batch.failures.count == 1 && batch.failures.first?.inputURL == fixture.input)
        let message = try #require(batch.failures.first?.message)
        if ["no region", "transparent"].contains(failure) {
            #expect(message == AppLocalization.text("未找到可提取区域"))
        } else {
            let reason = failure == "wrong size" ? ScreenshotExtractionError.maskSizeMismatch.localizedDescription : "Vision unavailable"
            #expect(message == AppLocalization.text("提取失败：%@", reason))
        }
        #expect(model.completed == 2 && !model.isProcessing)
        #expect(!FileManager.default.fileExists(atPath: batch.directoryURL.appendingPathComponent("0").path))
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
        model.discardResults()
    }

    @Test(arguments: ["missing", "corrupt", "resource", "animation"])
    func invalidOrAnimatedInputsFailBeforeTheExtractionDependencyRuns(kind: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let input = fixture.root.appendingPathComponent("invalid.png")
        switch kind {
        case "corrupt": try Data("invalid image".utf8).write(to: input)
        case "resource": try Fixture.write(Fixture.image(width: 150_001, height: 1), to: input)
        case "animation":
            let destination = try #require(CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 2, nil))
            for _ in 0..<2 {
                CGImageDestinationAddImage(destination, try Fixture.image(),
                    [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: 0.1]] as CFDictionary)
            }
            #expect(CGImageDestinationFinalize(destination))
        default: break
        }
        let original = kind == "missing" ? nil : try Data(contentsOf: input)
        let model = ImageToolsModel()
        model.inputs = [input]
        let pending = model.startExtraction(service: service, mode: .foreground, extractImage: { _, _ in
            Issue.record("Rejected input must not start a Vision request")
            return nil
        })
        let task = try #require(pending)
        await task.value
        let batch = try #require(model.batch)
        #expect(batch.items.isEmpty && batch.failures.count == 1)
        #expect(batch.failures.first?.inputURL == input)
        #expect(try FileManager.default.contentsOfDirectory(atPath: batch.directoryURL.path).isEmpty)
        if kind == "animation" {
            #expect(batch.failures.first?.message == ImageProcessingError.rasterEditingAnimationUnsupported.localizedDescription)
        }
        if kind == "resource" { #expect(batch.failures.first?.message == ImageProcessingError.resourceLimit.localizedDescription) }
        if let original { #expect(try Data(contentsOf: input) == original) }
        model.discardResults()
    }

    @Test
    func emptyInputsAndUnselectedLassoUseExistingFailureMessages() async throws {
        let model = ImageToolsModel()
        await model.startExtraction(service: service, mode: .foreground)?.value
        #expect(model.batch == nil && !model.isProcessing)
        #expect(model.message == ImageProcessingError.emptyInput.localizedDescription)
        let fixture = try Fixture()
        defer { fixture.remove() }
        model.inputs = [fixture.input]
        await model.startExtraction(service: service, mode: .lasso)?.value
        let batch = try #require(model.batch)
        #expect(batch.items.isEmpty && batch.failures.first?.message == AppLocalization.text("未找到可提取区域"))
        model.discardResults()
    }

    @Test(arguments: [false, true])
    func cancellationStopsTheActiveRequestAndDiscardsLateSuccessOrFailure(lateFailure: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let staged = StagedDirectories()
        let service = fixture.stagedService(staged)
        let input = try fixture.svg()
        let original = try Data(contentsOf: input)
        let gate = Gate()
        let model = ImageToolsModel()
        model.inputs = [input]
        let pending = model.startExtraction(service: service, mode: .foreground, extractImage: { image, operation in
            try await gate.extract(image, operation: operation, lateFailure: lateFailure)
        })
        let task = try #require(pending)
        let request = try #require(await gate.waitUntilStarted())
        #expect(model.startExtraction(service: service, mode: .background) == nil)
        model.cancel()
        #expect(throws: CancellationError.self) { try request.checkCancellation() }
        await gate.finish()
        await task.value
        #expect(!model.isProcessing && model.batch == nil)
        #expect(model.inputs == [input] && model.message == AppLocalization.text("已取消"))
        let directories = await staged.values
        #expect(directories.count >= 2)
        for directory in directories { #expect(!FileManager.default.fileExists(atPath: directory.path)) }
        #expect(try Data(contentsOf: input) == original)
        let replacementPending = model.startExtraction(service: service, mode: .background,
            extractImage: { image, _ in try masked(image, background: true) })
        let replacement = try #require(replacementPending)
        await replacement.value
        #expect(model.batch?.items.count == 1 && model.batch?.failures.isEmpty == true)
        model.discardResults()
    }

    @Test
    func cancelingReturnedTaskStopsRequestAndDiscardsLateSuccess() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let gate = Gate()
        let model = ImageToolsModel()
        model.inputs = [fixture.input]
        let pending = model.startExtraction(service: service, mode: .foreground, extractImage: { image, operation in
            try await gate.extract(image, operation: operation)
        })
        let task = try #require(pending)
        let request = try #require(await gate.waitUntilStarted())
        task.cancel()
        await gate.finishCheckingCancellation()
        await task.value
        #expect(throws: CancellationError.self) { try request.checkCancellation() }
        #expect(!model.isProcessing && model.batch == nil && model.message == AppLocalization.text("已取消"))
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
    }

    @Test
    func dependencyCancellationAbortsBatchAndCleansStaging() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let staged = StagedDirectories()
        let model = ImageToolsModel()
        model.inputs = [try fixture.svg()]
        await model.startExtraction(service: fixture.stagedService(staged), mode: .foreground,
            extractImage: { _, _ in throw CancellationError() })?.value
        #expect(model.batch == nil && !model.isProcessing && model.message == AppLocalization.text("已取消"))
        for directory in await staged.values { #expect(!FileManager.default.fileExists(atPath: directory.path)) }
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
    }

    @Test
    func releasingModelCancelsItsRequestWithoutRetainingItOrLeakingStaging() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let staged = StagedDirectories()
        let service = fixture.stagedService(staged)
        let input = try fixture.svg()
        let gate = Gate()
        var model: ImageToolsModel? = ImageToolsModel()
        model?.inputs = [input]
        let pending = model?.startExtraction(service: service, mode: .foreground, extractImage: { image, operation in
            try await gate.extract(image, operation: operation)
        })
        let task = try #require(pending)
        let request = try #require(await gate.waitUntilStarted())
        weak let released = model
        model = nil
        #expect(released == nil, "Pending extraction must not retain the image tools model")
        #expect(throws: CancellationError.self) { try request.checkCancellation() }
        await gate.finish()
        await task.value
        let directories = await staged.values
        #expect(directories.count >= 2)
        for directory in directories { #expect(!FileManager.default.fileExists(atPath: directory.path)) }
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
    }

    @Test
    func cancellationFromLastProgressUpdateDiscardsAnAlreadyProducedPNG() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let staged = StagedDirectories()
        let service = fixture.stagedService(staged)
        let model = ImageToolsModel()
        model.inputs = [try fixture.svg()]
        let subscription = model.$completed.sink { completed in
            if completed == 1 { model.cancel() }
        }
        defer { subscription.cancel() }
        let pending = model.startExtraction(service: service, mode: .foreground,
            extractImage: { source, _ in try masked(source) })
        let task = try #require(pending)
        await task.value
        #expect(model.batch == nil && !model.isProcessing && model.message == AppLocalization.text("已取消"))
        #expect(model.completed == 1)
        for directory in await staged.values { #expect(!FileManager.default.fileExists(atPath: directory.path)) }
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
    }

    @Test
    func freeSelectionReusesScreenshotEditorAndExportsTransparentPNGWithoutChangingOriginal() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        model.inputs = [fixture.input]
        await model.prepareEditor(fixture.input, service: service)?.value
        let input = try #require(model.editorInput)
        let session = ImageToolsEditorSession(image: input.image, initialTool: .extraction)
        session.model.selectExtractionMode(.lasso)
        let points = [CGPoint(x: 1, y: 1), CGPoint(x: 7, y: 1), CGPoint(x: 7, y: 6), CGPoint(x: 1, y: 6)]
        let task = try #require(session.model.updateExtractionRegion(points, isComplete: true))
        await task.value
        let extracted = try #require(session.apply())
        #expect(extracted.width == 16 && extracted.height == 10)
        #expect(try pixel(extracted, x: 3, y: 3).alphaComponent == 1)
        #expect(try pixel(extracted, x: 12, y: 8).alphaComponent == 0)
        await model.recordEdit(extracted, for: fixture.input)?.value
        model.startEdited(service: service)
        for await busy in model.$isProcessing.values { if !busy { break } }
        let item = try #require(model.batch?.items.first)
        let output = try #require(item.outputs.first)
        let actual = try await service.loadRasterImage(output.url)
        #expect(try Fixture.bytes(actual) == Fixture.bytes(extracted))
        #expect(try Data(contentsOf: item.sourceURL) == fixture.original)
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
        model.discardResults()
        model.discardEdits()
    }

    @Test
    func completedExtractionUsesExistingIndividualBatchAndZIPExport() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        model.inputs = [fixture.input]
        await model.startExtraction(service: service, mode: .foreground, extractImage: { source, _ in try masked(source) })?.value
        let items = try #require(model.batch?.items)
        let output = try #require(items.first?.outputs.first)
        let bytes = try Data(contentsOf: output.url)
        let export = fixture.root.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        model.exportImages(items, to: export, smallestOnly: false)
        for await busy in model.$isProcessing.values { if !busy { break } }
        #expect(try Data(contentsOf: export.appendingPathComponent("source-png.png")) == bytes)
        let archive = fixture.root.appendingPathComponent("images.zip")
        model.exportZIP(items, to: archive)
        for await busy in model.$isProcessing.values { if !busy { break } }
        let result = try await AIAgentProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-p", archive.path, "images/source-png.png"], workingDirectoryURL: fixture.root)
        #expect(result.status == 0 && result.standardOutput == bytes)
        #expect(try Data(contentsOf: fixture.input) == fixture.original)
        model.discardResults()
    }

    private actor Operations {
        var values: [ScreenshotExtractionOperation] = []
        func append(_ operation: ScreenshotExtractionOperation) { values.append(operation) }
    }

    private actor StagedDirectories {
        var values: Set<URL> = []
        func append(_ directory: URL) { values.insert(directory) }
    }

    private actor Gate {
        private var operation: ScreenshotExtractionOperation?
        private let started = AsyncStream<Void>.makeStream()
        private let resume = AsyncStream<Void>.makeStream()

        func extract(_ image: CGImage, operation: ScreenshotExtractionOperation, lateFailure: Bool = false) async throws -> CGImage? {
            self.operation = operation
            started.continuation.yield()
            for await _ in resume.stream { break }
            if lateFailure { throw NSError(domain: "ExtractionFixture", code: 2) }
            return try masked(image)
        }

        func waitUntilStarted() async -> ScreenshotExtractionOperation? {
            for await _ in started.stream { break }
            return operation
        }

        func finishCheckingCancellation() {
            do { try operation?.checkCancellation(); Issue.record("Task cancellation must stop the active request") }
            catch { #expect(error is CancellationError) }
            finish()
        }

        func finish() {
            resume.continuation.yield()
            resume.continuation.finish()
            started.continuation.finish()
        }
    }

    private struct Fixture: Sendable {
        let root: URL
        let input: URL
        let original: Data

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-image-extraction-test-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            input = root.appendingPathComponent("source.png")
            try Self.write(Self.image(), to: input)
            original = try Data(contentsOf: input)
        }

        func svg() throws -> URL {
            let input = root.appendingPathComponent("source.svg")
            try Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="10"><rect width="16" height="10" fill="#a05060"/></svg>"##.utf8).write(to: input)
            return input
        }

        func stagedService(_ directories: StagedDirectories) -> ImageProcessingService {
            let bytes = original
            return ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, arguments, work, _ in
                if arguments[0] == "-a" {
                    await directories.append(work.lastPathComponent == "0" ? work.deletingLastPathComponent() : work)
                    return AIAgentProcessOutput(status: 0,
                        standardOutput: Data("width: 16\nheight: 10\nvips-loader: svgload\n".utf8), standardError: "", didTimeout: false)
                }
                if arguments[0] == "autorot" { try Data("normalized".utf8).write(to: URL(fileURLWithPath: arguments[2])) }
                if arguments[0] == "pngsave" { try bytes.write(to: URL(fileURLWithPath: arguments[2])) }
                return AIAgentProcessOutput(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
            }
        }

        static func image(width: Int = 16, height: Int = 10, alpha: UInt8 = 255) throws -> CGImage {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let index = (y * width + x) * 4
                    bytes[index] = UInt8((x % 16 * 12 + 20) * Int(alpha) / 255)
                    bytes[index + 1] = UInt8((y % 10 * 18 + 20) * Int(alpha) / 255)
                    bytes[index + 2] = UInt8(80 * Int(alpha) / 255)
                    bytes[index + 3] = alpha
                }
            }
            let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
            return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        }

        static func write(_ image: CGImage, to url: URL, properties: [CFString: Any] = [:]) throws {
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))
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

private func isMainThread() -> Bool { Thread.isMainThread }

private func pixel(_ image: CGImage, x: Int, y: Int) throws -> NSColor {
    let color = try #require(NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y))
    return try #require(color.usingColorSpace(.deviceRGB))
}

private func masked(_ source: CGImage, background: Bool = false) throws -> CGImage {
    let half = CGFloat(source.width / 2)
    let height = CGFloat(source.height)
    let regions = [[CGPoint(x: 0, y: 0), CGPoint(x: half, y: 0), CGPoint(x: half, y: height), CGPoint(x: 0, y: height)]]
    var mask = try #require(try ScreenshotImageExtraction.lassoMask(regions: regions,
        imageSize: CGSize(width: source.width, height: source.height), pixelWidth: source.width, pixelHeight: source.height))
    if background {
        let inverted = CIImage(cgImage: mask).applyingFilter("CIColorInvert")
        mask = try #require(CIContext().createCGImage(inverted, from: inverted.extent,
            format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()))
    }
    return try ScreenshotImageExtraction.applying(mask: mask, to: source)
}
