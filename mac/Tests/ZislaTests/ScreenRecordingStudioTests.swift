import AppKit
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct ScreenRecordingStudioTests {
    @MainActor
    private final class Gate<Value: Sendable> {
        private var continuation: CheckedContinuation<Value, Error>?
        private var entered = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async throws -> Value {
            entered = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }

        func waitUntilEntered() async {
            if entered { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func resolve(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
    }

    private func fixture(aiCompletion: ((ScreenRecordingProject, String, AIModelConfigurationReference?) async throws -> String)? = nil,
                         preview: ((ScreenRecordingProject, URL, Double) async throws -> CGImage)? = nil) throws -> (ScreenRecordingStudioModel, URL, ScreenRecordingProject) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-studio-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let store = ScreenRecordingProjectStore(root: root)
        let directory = try store.createDirectory()
        try Data([1]).write(to: directory.appendingPathComponent("screen.mp4"))
        let project = ScreenRecordingProject(name: "Demo", videoFile: "screen.mp4", duration: 10, width: 64, height: 48)
        try store.save(project, in: directory)
        let model = ScreenRecordingStudioModel(projectStore: store,
            renderPreview: preview ?? { _, _, _ in throw ScreenRecordingExportError.cannotRender }, aiCompletion: aiCompletion)
        model.install(project, directory: directory)
        return (model, root, project)
    }

    @Test func editsUndoRedoSaveAndInvalidChangesKeepTheOriginalProject() throws {
        let (model, root, original) = try fixture()
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.split(at: 4)
        #expect(model.project?.edits.segments.count == 2)
        #expect(model.isDirty)
        model.undo()
        #expect(model.project == original)
        model.redo()
        let split = try #require(model.project)
        model.update { $0.edits.segments[0].speed = 0 }
        #expect(model.project == split)
        model.cut(start: 2, end: 7)
        #expect(model.project?.edits.segments.map { [$0.start, $0.end] } == [[0, 2], [7, 10]])
        try model.save()
        #expect(!model.isDirty)
        let directory = try #require(model.directory)
        #expect(try model.projectStore.load(from: directory) == model.project)
        #expect(model.prepareToClose())
        model.cut(start: 0, end: 10)
        #expect(model.project?.edits.segments.isEmpty == true)
        #expect(model.project?.outputDuration == 0)
        #expect(model.prepareToClose())
    }

    @Test func captionsFollowRepeatedReorderedAndSlowSegments() throws {
        var project = ScreenRecordingProject(name: "Demo", videoFile: "screen.mp4", duration: 10, width: 64, height: 48)
        project.edits.segments = [.init(start: 6, end: 8, speed: 0.5), .init(start: 0, end: 4, speed: 2),
                                 .init(start: 6, end: 8)]
        project.captions = [.init(start: 1, end: 3, text: "first"), .init(start: 5, end: 7, text: "second")]
        let captions = ScreenRecordingStudioModel.outputCaptions(project)
        #expect(captions.map(\.text) == ["second", "first", "second"])
        #expect(captions.map(\.start) == [0, 4.5, 6])
        #expect(captions.map(\.end) == [2, 5.5, 7])
        project.edits.segments = []
        #expect(ScreenRecordingStudioModel.outputCaptions(project).isEmpty)
    }

    @Test func aiProposalRequiresExplicitApplyAndSupportsUndo() async throws {
        let gate = Gate<String>()
        let (model, root, original) = try fixture(aiCompletion: { _, _, _ in try await gate.wait() })
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.aiInstruction = "remove the middle"
        model.requestAIEdit()
        await gate.waitUntilEntered()
        #expect(model.isBusy)
        #expect(!model.prepareToClose())
        model.update { $0.name = "must not edit while busy" }
        #expect(model.project == original)
        gate.resolve(#"{"version":1,"operations":[{"type":"cut","start":2,"end":4}]}"#)
        await model.operationTask?.value
        #expect(!model.isBusy)
        #expect(model.project == original)
        #expect(model.pendingAIProject?.outputDuration == 8)
        model.applyAIEdit()
        #expect(model.project?.outputDuration == 8)
        #expect(model.isDirty)
        #expect(model.pendingAIProject == nil)
        model.undo()
        #expect(model.project == original)
    }

    @Test(arguments: ["edit", "undo", "redo", "install"])
    func projectChangesDiscardUnappliedAIProposals(_ change: String) async throws {
        let (model, root, original) = try fixture(aiCompletion: { _, _, _ in
            #"{"version":1,"operations":[{"type":"cut","start":2,"end":4}]}"#
        })
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        if change == "undo" || change == "redo" { model.split(at: 5) }
        if change == "redo" { model.undo() }
        model.aiInstruction = "remove the middle"
        model.requestAIEdit()
        await model.operationTask?.value
        #expect(model.pendingAIProject != nil)

        switch change {
        case "edit": model.update { $0.name = "Updated" }
        case "undo": model.undo()
        case "redo": model.redo()
        default: model.install(original, directory: try #require(model.directory))
        }

        let current = model.project
        #expect(model.pendingAIProject == nil, "\(change) must discard the previous proposal")
        model.applyAIEdit()
        #expect(model.project == current, "A stale proposal must not overwrite \(change)")
    }

    @Test func failedSaveKeepsUnsavedEditsAndPreventsClosingUntilRecovery() throws {
        let (model, root, original) = try fixture()
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        let directory = try #require(model.directory)
        let manifest = directory.appendingPathComponent(ScreenRecordingProjectStore.manifestName)
        let saved = try Data(contentsOf: manifest)
        let media = directory.appendingPathComponent(original.videoFile)
        try FileManager.default.removeItem(at: media)
        model.split(at: 4)
        let edited = try #require(model.project)

        model.saveProject()
        #expect(model.isDirty)
        #expect(model.project == edited)
        #expect(model.errorMessage != nil)
        #expect(try Data(contentsOf: manifest) == saved)
        #expect(!model.prepareToClose())
        #expect(model.isDirty)
        #expect(model.project == edited)

        try Data([1]).write(to: media)
        #expect(model.prepareToClose())
        #expect(!model.isDirty)
        #expect(try model.projectStore.load(from: directory) == edited)
    }

    @Test func cancelledAILateResponseCannotChangeProjectOrCreateProposal() async throws {
        let gate = Gate<String>()
        let (model, root, original) = try fixture(aiCompletion: { _, _, _ in try await gate.wait() })
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.aiInstruction = "remove all"
        model.requestAIEdit()
        await gate.waitUntilEntered()
        model.cancelOperation()
        gate.resolve(#"{"version":1,"operations":[{"type":"cut","start":0,"end":10}]}"#)
        await model.operationTask?.value
        #expect(!model.isBusy)
        #expect(model.project == original)
        #expect(model.pendingAIProject == nil)
        #expect(model.prepareToClose())
    }

    @Test func malformedAIResponseKeepsEditsAndRestoresEditableState() async throws {
        let (model, root, original) = try fixture(aiCompletion: { _, _, _ in "invalid response" })
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.aiInstruction = "edit"
        model.requestAIEdit()
        await model.operationTask?.value
        #expect(model.canEdit)
        #expect(model.project == original)
        #expect(model.pendingAIProject == nil)
        #expect(model.errorMessage != nil)
    }

    @Test func latePreviewCannotReplaceTheLatestSeek() async throws {
        let first = Gate<CGImage>()
        let second = Gate<CGImage>()
        let red = try image(red: 1, blue: 0, width: 3)
        let blue = try image(red: 0, blue: 1, width: 7)
        let (model, root, _) = try fixture(preview: { _, _, time in
            if time == 0 { return try await first.wait() }
            return try await second.wait()
        })
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await first.waitUntilEntered()
        let firstTask = model.previewTask
        model.seek(to: 1)
        await second.waitUntilEntered()
        second.resolve(blue)
        await model.previewTask?.value
        #expect(model.preview?.size.width == 7)
        first.resolve(red)
        await firstTask?.value
        #expect(model.preview?.size.width == 7)
        #expect(model.currentTime == 1)
    }

    @Test func regionGeometryClipsReverseDragsAndRejectsInvalidOrTinyAreas() {
        let size = CGSize(width: 1_920, height: 1_080)
        let forward = ScreenRecordingRegionGeometry.selection(from: .init(x: 100, y: 50), to: .init(x: 300, y: 250), size: size)
        let reversed = ScreenRecordingRegionGeometry.selection(from: .init(x: 300, y: 250), to: .init(x: 100, y: 50), size: size)
        #expect(forward == .init(x: 100, y: 50, width: 200, height: 200))
        #expect(reversed == forward)
        #expect(ScreenRecordingRegionGeometry.selection(from: .init(x: -50, y: -25), to: .init(x: 300, y: 250), size: size)
            == .init(x: 0, y: 0, width: 300, height: 250))
        #expect(ScreenRecordingRegionGeometry.selection(from: .zero, to: .init(x: 1, y: 10), size: size) == nil)
        #expect(ScreenRecordingRegionGeometry.selection(from: .zero, to: .init(x: CGFloat.infinity, y: 10), size: size) == nil)
        #expect(ScreenRecordingRegionGeometry.selection(from: .zero, to: .init(x: 10, y: 10), size: .zero) == nil)
    }

    private func image(red: CGFloat, blue: CGFloat, width: Int) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: 2, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 2))
        return try #require(context.makeImage())
    }
}
