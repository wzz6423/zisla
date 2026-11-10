import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ShelfContextActionTests {
    @Test func ordinaryOpenAndRevealAllowFoldersAndResolveMovedBookmarksInOrder() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let item = try fixture.file("original.txt", bytes: Data([7]))
        let moved = fixture.root.appendingPathComponent("renamed.txt")
        try FileManager.default.moveItem(at: item.url, to: moved)
        let folder = fixture.root.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        #expect(fixture.shelf.add([folder]) == 1)
        let directory = try #require(fixture.shelf.items.last)
        var opened: [URL] = []
        try ShelfModuleView.openFileItems([directory, item], in: fixture.shelf) { opened.append($0); return true }
        #expect(opened.map { $0.resolvingSymlinksInPath() } == [folder, moved].map { $0.resolvingSymlinksInPath() })
        let revealed = try ShelfContextActions.fileURLs([item, directory], in: fixture.shelf, requiresRegularFile: false)
        defer { revealed.forEach(fixture.shelf.endAccessing) }
        #expect(revealed.map { $0.resolvingSymlinksInPath() } == [moved, folder].map { $0.resolvingSymlinksInPath() })
        #expect(throws: ShelfContextActionError.unavailableFile(directory.displayName)) {
            try ShelfContextActions.fileURLs([directory], in: fixture.shelf)
        }
        #expect(fixture.shelf.items == [item, directory])
    }

    @Test func ordinaryOpenFailsBeforeSideEffectsForMissingFilesAndKeepsLinksAndText() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.file("missing.txt", bytes: Data([7]))
        try FileManager.default.removeItem(at: file.url)
        var opened: [URL] = []
        #expect(throws: ShelfContextActionError.unavailableFile(file.displayName)) {
            try ShelfModuleView.openFileItems([file], in: fixture.shelf) { opened.append($0); return true }
        }
        #expect(opened.isEmpty)
        #expect(fixture.shelf.add(payloads: [.text("https://example.invalid/"), .text("plain text")]) == 2)
        try ShelfModuleView.openFileItems(Array(fixture.shelf.items.dropFirst()), in: fixture.shelf) { opened.append($0); return true }
        #expect(opened == [URL(string: "https://example.invalid/")!, fixture.shelf.items[2].url])
        #expect(throws: ShelfContextActionError.unavailableFile(fixture.shelf.items[2].displayName)) {
            try ShelfModuleView.openFileItems([fixture.shelf.items[2]], in: fixture.shelf) { _ in false }
        }
    }

    @Test func actionsRejectEmptyOrMixedSelectionsBeforeAnySideEffect() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let image = try fixture.image(width: 24)
        let video = try fixture.file("clip.mp4", bytes: Data([1]))
        let text = FileShelfItem(id: UUID(), url: image.url, addedAt: .distantPast, bookmarkData: Data(), text: "text")
        for action in ShelfContextAction.allCases {
            #expect(!action.supports([]))
            #expect(!action.supports([image, video]))
            #expect(!action.supports([image, text]))
            #expect(fixture.actions.perform(action, items: [], createQuickNote: { _ in
                Issue.record("Empty input must not write a note"); return false
            }, openStudio: { _ in Issue.record("Empty input must not open the studio"); return false }) == nil)
            #expect(!fixture.actions.isProcessing)
        }
        #expect(ShelfContextAction.imagesToPDF.supports([image]))
        #expect(ShelfContextAction.recognizeToQuickNote.supports([image]))
        #expect(ShelfContextAction.editVideo.supports([video]))
        #expect(fixture.shelf.items == [image, video])
    }

    @Test func PDFReturnsToShelfInOrderAndSurvivesStagingCleanup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.image(width: 24)
        let second = try fixture.image(width: 36)
        let originals = try [Data(contentsOf: first.url), Data(contentsOf: second.url)]
        let task = try #require(fixture.perform(.imagesToPDF, items: [second, first]))
        #expect(fixture.actions.isProcessing)
        await task.value
        let result = try #require(fixture.shelf.items.last)
        #expect(fixture.actions.generatedItemID == result.id)
        #expect(result.isManaged && result.url.lastPathComponent == "images.pdf")
        let document = try #require(PDFDocument(url: result.url))
        #expect(document.pageCount == 2)
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).width == 36)
        #expect(document.page(at: 1)?.bounds(for: .mediaBox).width == 24)
        #expect(try [Data(contentsOf: first.url), Data(contentsOf: second.url)] == originals)
        #expect(fixture.shelf.items.prefix(2) == [first, second])
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
        #expect(!fixture.actions.isProcessing && fixture.actions.task == nil)
    }

    @Test func screenshotsRecoverTheirCacheBeforePDFAndNeverChangeStoredPixels() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let png = try Fixture.png(width: 24)
        let metadata = ShelfScreenshotMetadata(source: .init(applicationName: "Synthetic", bundleIdentifier: nil,
            processIdentifier: nil), isLongScreenshot: false, initialCaptureRect: .zero, captureRect: .zero,
            screenFrame: nil, displayIdentifier: nil, pixelWidth: 24, pixelHeight: 12)
        let item = try fixture.shelf.stashScreenshot(png: png, metadata: metadata)
        try FileManager.default.removeItem(at: item.url)
        try await #require(fixture.perform(.imagesToPDF, items: [item])).value
        #expect(fixture.shelf.items.count == 2)
        #expect(fixture.shelf.items[0] == item)
        #expect(try fixture.shelf.screenshotData(id: item.id) == png)
        #expect(try Data(contentsOf: item.url) == png)
    }

    @Test(arguments: ["missing", "directory", "corrupt", "remote"])
    func inaccessibleOrInvalidImagesFailWithoutAddingAnOutput(_ failure: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var item = try fixture.image(width: 24)
        switch failure {
        case "missing": try FileManager.default.removeItem(at: item.url)
        case "directory":
            try FileManager.default.removeItem(at: item.url)
            try FileManager.default.createDirectory(at: item.url, withIntermediateDirectories: false)
        case "remote": item.url = URL(string: "https://example.invalid/image.png")!; item.bookmarkData = Data()
        default: try Data("invalid image".utf8).write(to: item.url)
        }
        let before = fixture.shelf.items
        let task = try #require(fixture.perform(.imagesToPDF, items: [item]))
        await task.value
        #expect(fixture.shelf.items == before)
        #expect(!fixture.actions.isProcessing)
        #expect(fixture.actions.message?.contains(AppLocalization.text("操作失败")) == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
    }

    @Test func failingConversionOrShelfCommitCleansStagingAndAllowsRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let item = try fixture.image(width: 24)
        let before = fixture.shelf.items
        let bytes = try Data(contentsOf: item.url)
        let failedTask = fixture.actions.perform(.imagesToPDF, items: [item], createQuickNote: { _ in false },
            openStudio: { _ in false }, convertImages: { _, output in
                try Data([1]).write(to: output)
                throw CocoaError(.fileWriteOutOfSpace)
            })
        let failed = try #require(failedTask)
        await failed.value
        #expect(fixture.shelf.items == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
        try FileManager.default.removeItem(at: fixture.storage)
        try FileManager.default.createDirectory(at: fixture.storage, withIntermediateDirectories: false)
        try await #require(fixture.perform(.imagesToPDF, items: [item])).value
        #expect(fixture.shelf.items == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
        try FileManager.default.removeItem(at: fixture.storage)
        try await #require(fixture.perform(.imagesToPDF, items: [item])).value
        #expect(fixture.shelf.items.count == 2)
        #expect(try Data(contentsOf: item.url) == bytes)
    }

    @Test func cancellationDuringPDFRejectsLateOutputAndDuplicateClicks() async throws {
        let fixture = try Fixture()
        let gate = Gate()
        defer { fixture.remove() }
        let item = try fixture.image(width: 24)
        let taskTask = fixture.actions.perform(.imagesToPDF, items: [item], createQuickNote: { _ in false },
            openStudio: { _ in false }, convertImages: { _, output in
                gate.pause()
                try Data([1]).write(to: output)
            })
        let task = try #require(taskTask)
        await gate.waitUntilPaused()
        #expect(fixture.perform(.imagesToPDF, items: [item]) == nil)
        fixture.actions.cancel()
        gate.resume()
        await task.value
        #expect(fixture.shelf.items == [item])
        #expect(fixture.actions.generatedItemID == nil)
        #expect(fixture.actions.message == AppLocalization.text("已取消操作"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
        #expect(!fixture.actions.isProcessing)
    }

    @Test func cancelledBeforeTaskStartsHasNoOutputOrExternalRequest() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let item = try fixture.image(width: 24)
        let taskTask = fixture.actions.perform(.imagesToPDF, items: [item], createQuickNote: { _ in false },
            openStudio: { _ in false }, convertImages: { _, _ in Issue.record("Cancelled work must not start conversion") })
        let task = try #require(taskTask)
        fixture.actions.cancel()
        await task.value
        #expect(fixture.shelf.items == [item])
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
        #expect(fixture.actions.message == AppLocalization.text("已取消操作"))
    }

    @Test func OCRUsesExistingFormatterAndCreatesOneOrderedQuickNote() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.image(width: 24)
        let second = try fixture.image(width: 36)
        var note: String?
        let taskTask = fixture.actions.perform(.recognizeToQuickNote, items: [second, first],
            createQuickNote: { note = $0; return true }, openStudio: { _ in false }, recognizeImage: { image, _ in
                #expect(Self.isOffMainThread())
                return [.init(text: "Text \(image.width)", boundingBox: .init(x: 0, y: 0.2, width: 1, height: 0.2))]
            })
        let task = try #require(taskTask)
        await task.value
        #expect(note == "Text 36\n\nText 24")
        #expect(fixture.shelf.items == [first, second])
        #expect(fixture.actions.message == AppLocalization.text("已创建随记"))
    }

    @Test(arguments: ["empty second", "worker failure", "notes denied"])
    func OCRFailureNeverCreatesAPartialNoteAndAllowsRetry(_ failure: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.image(width: 24)
        let second = try fixture.image(width: 36)
        var attempts = 0
        let taskTask = fixture.actions.perform(.recognizeToQuickNote, items: [first, second],
            createQuickNote: { _ in attempts += 1; return false }, openStudio: { _ in false }, recognizeImage: { image, _ in
                if failure == "worker failure" { throw CocoaError(.fileReadCorruptFile) }
                return failure == "empty second" && image.width == 36 ? []
                    : [.init(text: "result", boundingBox: .init(x: 0, y: 0, width: 1, height: 1))]
            })
        let task = try #require(taskTask)
        await task.value
        #expect(attempts == (failure == "notes denied" ? 1 : 0))
        #expect(fixture.shelf.items == [first, second])
        #expect(!fixture.actions.isProcessing)
        #expect(fixture.actions.message?.hasPrefix(AppLocalization.text("操作失败")) == true)
    }

    @Test func cancellingOCRReachesTheVisionOperationAndNeverWritesLateText() async throws {
        let fixture = try Fixture()
        let gate = Gate()
        defer { fixture.remove() }
        let item = try fixture.image(width: 24)
        var written = false
        let taskTask = fixture.actions.perform(.recognizeToQuickNote, items: [item],
            createQuickNote: { _ in written = true; return true }, openStudio: { _ in false }, recognizeImage: { _, operation in
                gate.pause()
                #expect(throws: CancellationError.self) { try operation.checkCancellation() }
                return [.init(text: "late text", boundingBox: .init(x: 0, y: 0, width: 1, height: 1))]
            })
        let task = try #require(taskTask)
        await gate.waitUntilPaused()
        fixture.actions.cancel()
        gate.resume()
        await task.value
        #expect(!written && fixture.shelf.items == [item])
        #expect(fixture.actions.message == AppLocalization.text("已取消操作"))
    }

    @Test func committingNotesDisablesCancellationUntilTheSystemResultArrives() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let item = try fixture.image(width: 24)
        let taskTask = fixture.actions.perform(.recognizeToQuickNote, items: [item], createQuickNote: { _ in
            #expect(fixture.actions.isProcessing && !fixture.actions.isCancellable)
            fixture.actions.cancel()
            return true
        }, openStudio: { _ in false }, recognizeImage: { _, _ in
            [.init(text: "result", boundingBox: .init(x: 0, y: 0, width: 1, height: 1))]
        })
        let task = try #require(taskTask)
        await task.value
        #expect(fixture.actions.message == AppLocalization.text("已创建随记"))
    }

    @Test(arguments: [true, false])
    func videoHandoffPreservesInputOrderAndReportsUnavailableStudio(_ accepts: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.file("first.mp4", bytes: Data([1]))
        let second = try fixture.file("second.mp4", bytes: Data([2]))
        var handedOff: [URL] = []
        let taskTask = fixture.actions.perform(.editVideo, items: [second, first], createQuickNote: { _ in false },
            openStudio: { handedOff = $0; return accepts })
        let task = try #require(taskTask)
        await task.value
        #expect(handedOff.map { $0.resolvingSymlinksInPath() } == [second.url, first.url].map { $0.resolvingSymlinksInPath() })
        #expect(fixture.shelf.items == [first, second])
        #expect(fixture.actions.message == (accepts ? AppLocalization.text("已发送到录屏工作室")
            : AppLocalization.text("操作失败：%@", ShelfContextActionError.studioUnavailable.localizedDescription)))
    }

    private nonisolated static func isOffMainThread() -> Bool { !Thread.isMainThread }

    @MainActor private final class Fixture {
        let root: URL
        let stage: URL
        let storage: URL
        let shelf: FileShelfStore
        let actions: ShelfContextActions

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-action-test-" + UUID().uuidString)
            stage = root.appendingPathComponent("temporary")
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            storage = root.appendingPathComponent("shelf.json")
            shelf = FileShelfStore(storageURL: storage)
            actions = ShelfContextActions(shelf: shelf, temporaryDirectory: stage)
        }

        func image(width: Int) throws -> FileShelfItem {
            try file("image-\(width).png", bytes: ShelfContextActionTests.Fixture.png(width: width))
        }

        func file(_ name: String, bytes: Data) throws -> FileShelfItem {
            let url = root.appendingPathComponent(name)
            try bytes.write(to: url)
            #expect(shelf.add([url]) == 1)
            return try #require(shelf.items.last)
        }

        func perform(_ action: ShelfContextAction, items: [FileShelfItem]) -> Task<Void, Never>? {
            actions.perform(action, items: items, createQuickNote: { _ in false }, openStudio: { _ in false })
        }

        func remove() { actions.cancel(); try? FileManager.default.removeItem(at: root) }

        nonisolated static func png(width: Int) throws -> Data {
            let context = try #require(CGContext(data: nil, width: width, height: 12, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: 12))
            let data = NSMutableData()
            let writer = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(writer, try #require(context.makeImage()), nil)
            #expect(CGImageDestinationFinalize(writer))
            return data as Data
        }
    }

    private final class Gate: @unchecked Sendable {
        private let condition = NSCondition()
        private var paused = false
        private var resumed = false
        private var waiter: CheckedContinuation<Void, Never>?
        func pause() {
            condition.lock()
            paused = true
            waiter?.resume(); waiter = nil
            while !resumed { condition.wait() }
            condition.unlock()
        }
        func waitUntilPaused() async {
            await withCheckedContinuation { continuation in
                condition.lock()
                if paused { continuation.resume() } else { waiter = continuation }
                condition.unlock()
            }
        }
        func resume() { condition.lock(); resumed = true; condition.broadcast(); condition.unlock() }
    }
}
