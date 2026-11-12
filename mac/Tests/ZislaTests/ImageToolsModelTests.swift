import Combine
import Foundation
import Testing
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

    private func finished(_ model: ImageToolsModel) async {
        for await busy in model.$isProcessing.values { if !busy { break } }
    }

    private struct Fixture: Sendable {
        let root: URL
        let image: URL
        let bytes: Data
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
