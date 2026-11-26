import AppKit
import Combine
import Foundation
import Testing
import ZislaCore
@testable import Zisla
@testable import ZislaKit

@MainActor
struct ImageToolsModelTests {
    @Test
    func folderSelectionMergesFilesAndKeepsExistingChoicesOnFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        model.addInputs([fixture.root, fixture.image])
        await finished(model)
        #expect(model.inputs == [fixture.image])
        model.addInputs([fixture.root.appendingPathComponent("missing.png")])
        await finished(model)
        #expect(model.inputs == [fixture.image])
        #expect(model.message != nil)
        let empty = fixture.root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        model.addInputs([empty])
        await finished(model)
        #expect(model.inputs == [fixture.image])
        #expect(model.message != nil)
    }

    @Test
    func cancellationAndDuplicateStartPreserveInputsAndClearBusyState() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        model.inputs = [fixture.image]
        let started = AsyncStream<URL>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish(); resume.continuation.finish() }
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, _, work, _ in
            started.continuation.yield(work.deletingLastPathComponent())
            for await _ in resume.stream { break }
            return AIAgentProcessOutput(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        model.start(service: service, options: .init())
        var directory: URL?
        for await url in started.stream { directory = url; break }
        model.start(service: service, options: .init())
        model.addInputs([fixture.root.appendingPathComponent("missing.png")])
        model.cancel()
        resume.continuation.yield()
        await finished(model)
        #expect(!model.isProcessing)
        #expect(model.batch == nil)
        #expect(model.inputs == [fixture.image])
        #expect(!FileManager.default.fileExists(atPath: try #require(directory).path))
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
    }

    @Test
    func successfulBatchIsRemovedWhenDiscarded() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        model.inputs = [fixture.image]
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, arguments, _, _ in
            if arguments[0] == "autorot" || arguments[0] == "pngsave" {
                try FileManager.default.copyItem(at: fixture.image, to: URL(fileURLWithPath: arguments[2]))
            }
            return AIAgentProcessOutput(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        model.start(service: service, options: .init())
        await finished(model)
        let batch = try #require(model.batch)
        #expect(batch.items.count == 1)
        #expect(model.completed == 1 && model.total == 1)
        #expect(FileManager.default.fileExists(atPath: batch.items[0].outputs[0].url.path))
        model.discardResults()
        #expect(model.batch == nil)
        #expect(!FileManager.default.fileExists(atPath: batch.directoryURL.path))
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
    }

    @Test
    func releasedModelRemovesItsCompletedBatch() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var model: ImageToolsModel? = ImageToolsModel()
        model?.inputs = [fixture.image]
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, arguments, _, _ in
            try FileManager.default.copyItem(at: fixture.image, to: URL(fileURLWithPath: arguments[2]))
            return AIAgentProcessOutput(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        model?.start(service: service, options: .init())
        await finished(try #require(model))
        let directory = try #require(model?.batch?.directoryURL)
        weak let released = model
        model = nil
        #expect(released == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test
    func imageExportReportsSuccessFailureAndCancellationWithoutChangingSources() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let directory = fixture.root.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = ImageToolsModel()
        model.exportImages([fixture.item], to: directory, smallestOnly: true)
        await finished(model)
        let output = directory.appendingPathComponent("source-png.png")
        #expect(try Data(contentsOf: output) == fixture.bytes)
        #expect(model.message != nil)
        model.exportImages([fixture.item], to: directory, smallestOnly: false)
        await finished(model)
        #expect(try Data(contentsOf: output) == fixture.bytes)
        #expect(model.message?.contains("source-png.png") == true)
        try FileManager.default.removeItem(at: output)
        model.exportImages([fixture.item], to: directory, smallestOnly: false)
        model.cancel()
        await finished(model)
        #expect(!model.isProcessing)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
    }

    @Test
    func archiveContainsOnlyExportedImagesUnderAStableFolder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        let destination = fixture.root.appendingPathComponent("export.zip")
        model.exportZIP([fixture.item], to: destination)
        await finished(model)
        let output = try await AIAgentProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
                                                        arguments: ["-p", destination.path, "images/source-png.png"], workingDirectoryURL: fixture.root)
        #expect(output.status == 0)
        #expect(output.standardOutput == fixture.bytes)
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
    }

    @Test(arguments: [false, true])
    func archiveFailureAndCancellationRemovePartialFiles(cancel: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        let destination = fixture.root.appendingPathComponent("export.zip")
        let started = AsyncStream<URL>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish(); resume.continuation.finish() }
        model.exportZIP([fixture.item], to: destination) { folder, staging in
            try? Data("partial archive".utf8).write(to: staging)
            started.continuation.yield(folder.deletingLastPathComponent())
            for await _ in resume.stream { break }
            return cancel ? nil : "disk full"
        }
        var directory: URL?
        for await url in started.stream { directory = url; break }
        model.discardResults()
        #expect((try FileManager.default.attributesOfItem(atPath: try #require(directory).path)[.posixPermissions] as? Int) == 0o700)
        if cancel { model.cancel() }
        resume.continuation.yield()
        await finished(model)
        #expect(!model.isProcessing)
        #expect(model.message != nil)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: try #require(directory).path))
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
    }

    @Test(arguments: [false, true])
    func destinationCreatedDuringArchiveIsNeverOverwritten(link: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        let destination = fixture.root.appendingPathComponent("export.zip")
        model.exportZIP([fixture.item], to: destination) { _, staging in
            do {
                try Data("new archive".utf8).write(to: staging)
                if link {
                    try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: fixture.root.appendingPathComponent("missing"))
                } else { try Data("existing".utf8).write(to: destination) }
                return nil
            } catch { return error.localizedDescription }
        }
        await finished(model)
        if link { #expect(try destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true) }
        else { #expect(try String(contentsOf: destination, encoding: .utf8) == "existing") }
    }

    @Test func shelfInputsKeepSelectionOrderAndReturnOnlyTheirOwnSuccessfulOutputs() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let second = fixture.root.appendingPathComponent("second.png")
        try fixture.bytes.write(to: second)
        let picker = fixture.root.appendingPathComponent("picker.png")
        try fixture.bytes.write(to: picker)
        let shelf = FileShelfStore(storageURL: fixture.root.appendingPathComponent("shelf.json"))
        #expect(shelf.add([fixture.image, second]) == 2)
        let model = ImageToolsModel()
        try model.receiveShelfInputs([second, fixture.image, second], shelf: shelf)
        #expect(model.inputs == [second, fixture.image])
        model.addInputs([picker])
        await finished(model)
        await model.start(service: fixture.copyingService, options: .init())?.value
        let outputs = Array(shelf.items.dropFirst(2))
        #expect(outputs.count == 2)
        #expect(Set(outputs.map(\.displayName)) == ["second-png.png", "source-png.png"])
        #expect(model.batch?.items.count == 3)
        #expect(model.message?.contains(AppLocalization.text("已加入 %ld 个项目", 2)) == true)
        let urls = outputs.map(\.url)
        model.discardResults()
        for url in urls { #expect(try Data(contentsOf: url) == fixture.bytes) }
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
        #expect(FileShelfStore(storageURL: fixture.root.appendingPathComponent("shelf.json")).items == shelf.items)
    }

    @Test func corruptShelfInputProducesAnExplicitPartialResultWithoutChangingEitherSource() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let corrupt = fixture.root.appendingPathComponent("corrupt.png")
        try Data("corrupt".utf8).write(to: corrupt)
        let shelf = FileShelfStore(storageURL: fixture.root.appendingPathComponent("shelf.json"))
        #expect(shelf.add([fixture.image, corrupt]) == 2)
        let model = ImageToolsModel()
        try model.receiveShelfInputs([fixture.image, corrupt], shelf: shelf)
        await model.start(service: fixture.copyingService, options: .init())?.value
        #expect(shelf.items.count == 3)
        #expect(model.batch?.items.count == 1 && model.batch?.failures.count == 1)
        #expect(model.message?.contains(AppLocalization.text("完成 %ld 张图片，失败 %ld 项", 1, 1)) == true)
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
        #expect(try String(contentsOf: corrupt, encoding: .utf8) == "corrupt")
        model.discardResults()
    }

    @Test func failedShelfPersistenceReportsTheFailureAndKeepsProcessingResultsAvailable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let storage = fixture.root.appendingPathComponent("shelf.json")
        let shelf = FileShelfStore(storageURL: storage)
        #expect(shelf.add([fixture.image]) == 1)
        let original = shelf.items
        let model = ImageToolsModel()
        try model.receiveShelfInputs([fixture.image], shelf: shelf)
        try FileManager.default.removeItem(at: storage)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: false)
        await model.start(service: fixture.copyingService, options: .init())?.value
        #expect(shelf.items == original)
        #expect(model.batch?.items.count == 1)
        #expect(model.message?.contains(AppLocalization.text("%ld 个结果未能加入中转站", 1)) == true)
        #expect(FileManager.default.fileExists(atPath: try #require(model.batch?.items.first?.outputs.first?.url.path)))
        model.discardResults()
    }

    @Test func scopeIsAcquiredBeforeReadingReleasedOnFailureAndHeldUntilSelectionChanges() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let hidden = fixture.root.appendingPathComponent("hidden.png")
        let shelf = FileShelfStore(storageURL: fixture.root.appendingPathComponent("shelf.json"))
        let model = ImageToolsModel()
        var acquired: [URL] = []
        var released: [URL] = []
        model.startAccessing = { url in
            acquired.append(url)
            if url == hidden { try! FileManager.default.copyItem(at: fixture.image, to: hidden) }
            return true
        }
        model.stopAccessing = { released.append($0) }
        try model.receiveShelfInputs([hidden, hidden], shelf: shelf)
        #expect(model.inputs == [hidden] && acquired == [hidden] && released.isEmpty)
        let invalid = fixture.root.appendingPathComponent("missing.png")
        #expect(throws: (any Error).self) { try model.receiveShelfInputs([hidden, invalid], shelf: shelf) }
        #expect(model.inputs == [hidden])
        #expect(acquired == [hidden, invalid] && released == [invalid])
        model.inputs = []
        #expect(released == [invalid, hidden])
    }

    @Test func releasedShelfOwnerBalancesScopeAndLeavesNoBatch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let shelf = FileShelfStore(storageURL: fixture.root.appendingPathComponent("shelf.json"))
        var acquired: [URL] = []
        var released: [URL] = []
        var model: ImageToolsModel? = ImageToolsModel()
        model?.startAccessing = { acquired.append($0); return true }
        model?.stopAccessing = { released.append($0) }
        try model?.receiveShelfInputs([fixture.image], shelf: shelf)
        weak var weakModel = model
        model = nil
        #expect(weakModel == nil && acquired == released && released == [fixture.image])
    }

    @Test func closingShelfImageToolsCancelsBeforeResultsReturnAndReleasesScopeAfterWorkerEnds() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let shelf = FileShelfStore(storageURL: fixture.root.appendingPathComponent("shelf.json"))
        #expect(shelf.add([fixture.image]) == 1)
        let model = ImageToolsModel()
        var released: [URL] = []
        model.startAccessing = { _ in true }
        model.stopAccessing = { released.append($0) }
        try model.receiveShelfInputs([fixture.image], shelf: shelf)
        let started = AsyncStream<URL>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish(); resume.continuation.finish() }
        let service = ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, arguments, work, _ in
            started.continuation.yield(work.deletingLastPathComponent())
            for await _ in resume.stream { break }
            try FileManager.default.copyItem(at: fixture.image, to: URL(fileURLWithPath: arguments[2]))
            return .init(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
        }
        let task = try #require(model.start(service: service, options: .init()))
        var directory: URL?
        for await url in started.stream { directory = url; break }
        model.cancel()
        #expect(released.isEmpty)
        resume.continuation.yield()
        await task.value
        await model.cancelAndDiscard().value
        #expect(shelf.items.count == 1 && model.inputs.isEmpty && model.batch == nil)
        #expect(released == [fixture.image])
        #expect(!FileManager.default.fileExists(atPath: try #require(directory).path))
    }

    @Test func cancellationAfterEncodingRejectsACompletedBatchBeforePublishingOrReturningIt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let shelf = FileShelfStore(storageURL: fixture.root.appendingPathComponent("shelf.json"))
        #expect(shelf.add([fixture.image]) == 1)
        let model = ImageToolsModel()
        try model.receiveShelfInputs([fixture.image], shelf: shelf)
        let started = AsyncStream<URL>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish(); resume.continuation.finish() }
        model.beforeReturningResults = { batch in
            started.continuation.yield(batch.directoryURL)
            for await _ in resume.stream { break }
        }
        let task = try #require(model.start(service: fixture.copyingService, options: .init()))
        var directory: URL?
        for await url in started.stream { directory = url; break }
        model.cancel()
        resume.continuation.yield()
        await task.value
        #expect(shelf.items.count == 1 && model.batch == nil)
        #expect(!FileManager.default.fileExists(atPath: try #require(directory).path))
        #expect(model.message == AppLocalization.text("已取消"))
        await model.cancelAndDiscard().value
    }

    @Test func closedOwnerRejectsNewWorkAndAReopenedOwnerRetainsItsOwnSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let shelf = FileShelfStore(storageURL: fixture.root.appendingPathComponent("shelf.json"))
        let model = ImageToolsModel()
        try model.receiveShelfInputs([fixture.image], shelf: shelf)
        let started = AsyncStream<Void>.makeStream()
        let resetStarted = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish(); resetStarted.continuation.finish(); resume.continuation.finish() }
        model.beforeReturningResults = { _ in
            started.continuation.yield()
            for await _ in resume.stream { break }
        }
        let task = try #require(model.start(service: fixture.copyingService, options: .init()))
        for await _ in started.stream { break }
        let reset = Task {
            resetStarted.continuation.yield()
            await model.cancelAndDiscard().value
        }
        for await _ in resetStarted.stream { break }
        #expect(throws: ShelfContextActionError.imageToolsUnavailable) {
            try model.receiveShelfInputs([fixture.image], shelf: shelf)
        }
        #expect(model.start(service: fixture.copyingService, options: .init()) == nil)
        resume.continuation.yield()
        await task.value
        await reset.value
        #expect(throws: ShelfContextActionError.imageToolsUnavailable) {
            try model.receiveShelfInputs([fixture.image], shelf: shelf)
        }
        let reopened = ImageToolsModel()
        try reopened.receiveShelfInputs([fixture.image], shelf: shelf)
        #expect(reopened.inputs == [fixture.image] && model.inputs.isEmpty)
        await reopened.cancelAndDiscard().value
    }

    @Test func normalizedProcessingIdentityRetainsTheOriginalScopeAndShelfOrigin() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let child = fixture.root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let original = child.appendingPathComponent("../source.png")
        let shelf = FileShelfStore(storageURL: fixture.root.appendingPathComponent("shelf.json"))
        let model = ImageToolsModel()
        var acquired: [URL] = []
        var released: [URL] = []
        model.startAccessing = { acquired.append($0); return true }
        model.stopAccessing = { released.append($0) }
        try model.receiveShelfInputs([original], shelf: shelf)
        #expect(acquired == [original] && model.inputs == [original])
        model.addInputs([fixture.image])
        await finished(model)
        #expect(model.inputs == [original])
        await model.start(service: fixture.copyingService, options: .init())?.value
        #expect(shelf.items.count == 1 && shelf.items[0].displayName == "source-png.png")
        #expect(released.isEmpty)
        await model.cancelAndDiscard().value
        #expect(released == [original])
    }

    @Test func closeCancelsEncodingBeforeWaitingForRecognitionAndKeepsScopesUntilBothFinish() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let shelf = FileShelfStore(storageURL: fixture.root.appendingPathComponent("shelf.json"))
        let model = ImageToolsModel()
        var released: [URL] = []
        model.startAccessing = { _ in true }
        model.stopAccessing = { released.append($0) }
        try model.receiveShelfInputs([fixture.image], shelf: shelf)
        let encoded = AsyncStream<Void>.makeStream()
        let resumeEncoding = AsyncStream<Void>.makeStream()
        let resumeRecognition = AsyncStream<Void>.makeStream()
        defer { encoded.continuation.finish(); resumeEncoding.continuation.finish(); resumeRecognition.continuation.finish() }
        model.beforeReturningResults = { _ in
            encoded.continuation.yield()
            for await _ in resumeEncoding.stream { break }
        }
        let task = try #require(model.start(service: fixture.copyingService, options: .init()))
        for await _ in encoded.stream { break }
        let recognition = Task { for await _ in resumeRecognition.stream { break } }
        recognition.cancel()
        let cleanup = model.cancelAndDiscard(after: recognition)
        #expect(throws: ShelfContextActionError.imageToolsUnavailable) {
            try model.receiveShelfInputs([fixture.image], shelf: shelf)
        }
        resumeEncoding.continuation.yield()
        await task.value
        #expect(shelf.items.isEmpty && model.batch == nil)
        resumeRecognition.continuation.yield()
        await cleanup.value
        #expect(released == [fixture.image] && model.inputs.isEmpty)
    }

    @Test func delayedEditorSaveAfterOwnerCloseCannotRecreateItsEditDirectory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let image = try await ImageProcessingService(executableURL: nil).loadRasterImage(fixture.image)
        let model = ImageToolsModel()
        let session = ImageToolsEditorSession(image: NSImage(cgImage: image, size: .init(width: image.width, height: image.height)))
        let entered = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); resume.continuation.finish(); session.close() }
        var edit: Task<Bool, Never>?
        let pending = session.apply { saved in
            entered.continuation.yield()
            for await _ in resume.stream { break }
            edit = model.recordEdit(saved, for: fixture.image)
            if let edit { _ = await edit.value }
        }
        let applying = try #require(pending)
        for await _ in entered.stream { break }
        session.close()
        await model.cancelAndDiscard().value
        resume.continuation.yield()
        #expect(await applying.value == false)
        #expect(edit == nil && model.editedImageURLs.isEmpty && !model.isProcessing)
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
        model.discardEdits()
    }

    @Test(arguments: [false, true])
    func delayedExportPanelReturnAfterOwnerCloseCannotStartAnExport(_ archive: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsModel()
        let directory = fixture.root.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let destination = directory.appendingPathComponent("images.zip")
        let completion: () -> Void = {
            if archive { model.exportZIP([fixture.item], to: destination) }
            else { model.exportImages([fixture.item], to: directory, smallestOnly: false) }
        }
        await model.cancelAndDiscard().value
        completion()
        await finished(model)
        #expect(!model.isProcessing && model.message == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
    }

    private func finished(_ model: ImageToolsModel) async {
        for await busy in model.$isProcessing.values { if !busy { break } }
    }

    private struct Fixture: Sendable {
        let root: URL
        let image: URL
        let bytes: Data
        var copyingService: ImageProcessingService {
            ImageProcessingService(executableURL: URL(fileURLWithPath: "/usr/bin/true")) { _, arguments, _, _ in
                if arguments[0] == "autorot" || arguments[0] == "pngsave" {
                    try FileManager.default.copyItem(at: image, to: URL(fileURLWithPath: arguments[2]))
                }
                return .init(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
            }
        }
        var item: ImageProcessedItem {
            let summary = ImageFileSummary(width: 1, height: 1, frameCount: 1, fileSize: Int64(bytes.count), format: .png, hasMetadata: false)
            return ImageProcessedItem(inputURL: image, sourceURL: image, summary: summary,
                                      outputs: [ImageProcessedOutput(url: image, format: .png, summary: summary)])
        }
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-image-model-test-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            image = root.appendingPathComponent("source.png")
            bytes = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
            try bytes.write(to: image)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
