import AppKit
import Combine
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
        func reject(_ error: Error) { continuation?.resume(throwing: error); continuation = nil }
    }

    private func fixture(capture: ScreenRecordingService = ScreenRecordingService(),
                         outputDirectoryStore: ScreenRecordingOutputDirectoryStore = ScreenRecordingOutputDirectoryStore(),
                         aiCompletion: ((ScreenRecordingProject, String, AIModelConfigurationReference?) async throws -> String)? = nil,
                         preview: ((ScreenRecordingProject, URL, Double) async throws -> CGImage)? = nil) throws -> (ScreenRecordingStudioModel, URL, ScreenRecordingProject) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-studio-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let store = ScreenRecordingProjectStore(root: root)
        let directory = try store.createDirectory()
        try Data([1]).write(to: directory.appendingPathComponent("screen.mp4"))
        let project = ScreenRecordingProject(name: "Demo", videoFile: "screen.mp4", duration: 10, width: 64, height: 48)
        try store.save(project, in: directory)
        let model = ScreenRecordingStudioModel(capture: capture, projectStore: store, outputDirectoryStore: outputDirectoryStore,
            renderPreview: preview ?? { _, _, _ in throw ScreenRecordingExportError.cannotRender }, aiCompletion: aiCompletion)
        model.install(project, directory: directory)
        return (model, root, project)
    }

    private func captureService(_ session: RecordingStudioTestSession,
                                sources: @escaping () async throws -> [RecordingCaptureSource] = { [] }) -> ScreenRecordingService {
        ScreenRecordingService(dependencies: .init(
            loadSources: sources, loadDevices: { .init() }, requestPermission: { _ in true },
            makeSession: { _, directory, _ in session.directory = directory; return session },
            makeCameraPreview: { _, _ in fatalError("Camera preview is disabled in these tests") },
            now: { 10 }, scheduleTick: { _ in {} }))
    }

    @Test func timelineSeekingUsesOutputTimeAcrossReorderedRepeatedAndRetimedSegments() throws {
        let (model, root, original) = try fixture()
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.update { $0.edits.segments = [.init(start: 4, end: 6, speed: 2),
            .init(start: 1, end: 2, speed: 0.5), .init(start: 4, end: 6, speed: 2)] }
        let edited = try #require(model.project)

        model.seekTimeline(to: 3.25)
        #expect(model.currentTime == 4.5)
        #expect(model.playbackTime == 3.25, "Repeated source media must keep the selected output occurrence")
        model.seekTimeline(to: 1.5)
        #expect(model.currentTime == 1.25)
        #expect(model.playbackTime == 1.5)
        model.seek(to: 5)
        #expect(model.playbackTime == 0.5)
        model.seekTimeline(to: -1)
        #expect(model.currentTime == 4 && model.playbackTime == 0)
        model.seekTimeline(to: 100)
        #expect(model.currentTime == 6 && model.playbackTime == 4)
        model.seekTimeline(to: .nan)
        #expect(model.currentTime == 6 && model.playbackTime == 4)
        #expect(model.project == edited, "Seeking must not modify project edits")

        model.install(original, directory: try #require(model.directory))
        #expect(model.currentTime == 0 && model.playbackTime == 0)
        model.update { $0.edits.segments = [] }
        model.seekTimeline(to: 1)
        #expect(model.currentTime == 0 && model.playbackTime == 0)
    }

    @Test func editingUndoAndRedoKeepThePlayheadWithinTheUpdatedTimeline() throws {
        let (model, root, _) = try fixture()
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.seekTimeline(to: 8)

        model.update { $0.edits.segments = [.init(start: 2, end: 6, speed: 2)] }

        #expect(model.playbackTime == 2 && model.currentTime == 6,
                "Trimming must clamp the output playhead and show the matching source frame")
        model.undo()
        #expect(model.playbackTime == 2 && model.currentTime == 2,
                "Undo must remap the selected output position to the restored source")
        model.redo()
        #expect(model.playbackTime == 2 && model.currentTime == 6,
                "Redo must remap the selected output position to the edited source")
    }

    @Test func deletingEverySegmentStopsSourcePlaybackAndResetsTheOutputPlayhead() throws {
        let (model, root, _) = try fixture()
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.seekTimeline(to: 8)
        model.playSource()
        #expect(model.isShowingSourcePlayback)

        model.update { $0.edits.segments = [] }

        #expect(model.playbackTime == 0 && model.currentTime == 8)
        #expect(!model.isShowingSourcePlayback && !model.isShowingTimelinePlayback)
        #expect(model.project?.edits.segments.isEmpty == true)
    }

    @Test func reopeningAnEditedProjectPreviewsItsFirstOutputFrame() async throws {
        let sourcePreview = try image(red: 1, blue: 0, width: 3)
        let editedPreview = try image(red: 0, blue: 1, width: 7)
        let (model, root, original) = try fixture(preview: { _, _, time in
            time == 4 ? editedPreview : sourcePreview
        })
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        let directory = try #require(model.directory)
        var edited = original
        edited.edits.segments = [.init(start: 4, end: 6, speed: 2),
                                 .init(start: 1, end: 2, speed: 0.5),
                                 .init(start: 4, end: 6)]
        try model.projectStore.save(edited, in: directory)
        let reopened = try model.projectStore.load(from: directory)
        model.seekTimeline(to: 8)
        model.playSource()

        model.install(reopened, directory: directory)
        await model.previewTask?.value

        #expect(model.currentTime == 4 && model.playbackTime == 0,
                "Reopening must map the output start to the first edited source range")
        #expect(model.preview?.size.width == 7, "The paused preview must use the first output frame")
        #expect(model.project == edited && !model.isDirty && !model.canUndo && !model.canRedo)
        #expect(!model.isShowingSourcePlayback && !model.isShowingTimelinePlayback)

        var empty = original
        empty.edits.segments = []
        for project in [original, empty] {
            model.install(project, directory: directory)
            await model.previewTask?.value
            #expect(model.currentTime == 0 && model.playbackTime == 0)
            #expect(model.preview?.size.width == 3)
        }
    }

    @Test func losingTheSelectedDisplayClearsItsRegionBeforeChoosingAnotherDisplay() async throws {
        let session = RecordingStudioTestSession()
        let source = RecordingCaptureSource(id: 2, name: "Second Display", mode: .display,
            frame: .init(x: 0, y: 0, width: 800, height: 600))
        let (model, root, _) = try fixture(capture: captureService(session, sources: { [source] }))
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.configuration = .init(mode: .region, sourceID: 1, region: .init(x: 10, y: 20, width: 100, height: 80))

        await model.loadSources()

        #expect(model.configuration.sourceID == 2)
        #expect(model.configuration.region == nil, "A region belongs to its original display")
    }

    @Test func cancelledSourceRefreshPreservesTheSelectionAndPreviousError() async throws {
        let session = RecordingStudioTestSession()
        let (model, root, _) = try fixture(capture: captureService(session, sources: { throw CancellationError() }))
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.previewTask?.value
        let previousError = try #require(model.errorMessage)
        let configuration = RecordingCaptureConfiguration(mode: .region, sourceID: 1,
            region: .init(x: 10, y: 20, width: 100, height: 80))
        model.configuration = configuration

        await model.loadSources()

        #expect(model.configuration == configuration)
        #expect(model.errorMessage == previousError)
    }

    @Test func sourceRefreshCannotChangeTheConfigurationOfAnActiveRecording() async throws {
        let gate = Gate<[RecordingCaptureSource]>()
        let session = RecordingStudioTestSession()
        let (model, root, _) = try fixture(capture: captureService(session, sources: { try await gate.wait() }))
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.configuration.sourceID = 1
        let configuration = model.configuration
        let refresh = Task { await model.loadSources() }
        await gate.waitUntilEntered()
        model.start()
        await model.operationTask?.value
        #expect(model.capture.phase == .recording)

        gate.resolve([.init(id: 2, name: "Second Display", mode: .display,
            frame: .init(x: 0, y: 0, width: 800, height: 600))])
        await refresh.value

        #expect(model.configuration == configuration)
        model.cancelOperation()
        for await cancelling in model.$isCancelling.values {
            if !cancelling { break }
        }
    }

    @Test func newRecordingClearsThePreviousAttemptError() async throws {
        let session = RecordingStudioTestSession()
        let (model, root, _) = try fixture(capture: captureService(session))
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        await model.previewTask?.value
        #expect(model.errorMessage != nil)

        model.start()
        await model.operationTask?.value

        #expect(model.capture.phase == .recording)
        #expect(model.errorMessage == nil, "An earlier failure must not appear on an active recording")
        model.cancelOperation()
        for await cancelling in model.$isCancelling.values {
            if !cancelling { break }
        }
    }

    @Test(arguments: [true, false], [0.0, 0.1, 0.35, 0.5])
    func stopAutomaticallySavesCapturedMediaAndReopensTheProject(cameraRound: Bool, cameraCornerRadius: Double) async throws {
        let session = RecordingStudioTestSession()
        let preview = try image(red: 1, blue: 0, width: 3)
        let (model, root, _) = try fixture(capture: captureService(session), preview: { _, _, _ in preview })
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.recordingCameraRound = !cameraRound
        model.start()
        await model.operationTask?.value
        #expect(model.capture.phase == .recording)
        model.recordingCameraRound = cameraRound
        model.recordingCameraAspectRatio = .widescreen
        model.recordingCameraCornerRadius = cameraCornerRadius

        model.stop()
        await model.operationTask?.value
        await model.previewTask?.value

        let directory = try #require(model.directory)
        let project = try #require(model.project)
        #expect(project.edits.cameraRound == cameraRound)
        #expect(project.edits.cameraAspectRatio == .widescreen)
        #expect(project.edits.cameraCornerRadius == cameraCornerRadius)
        #expect(directory.path == session.directory?.path)
        #expect(directory.deletingLastPathComponent().path == root.path)
        #expect(!model.isDirty)
        #expect(model.errorMessage == nil)
        #expect(try model.projectStore.load(from: directory) == project)
        #expect(try model.projectStore.recentDirectories().count == 2)
    }

    @Test func failedStopSavePreservesMediaAndEditsAndKeepsTheSaveErrorUntilRecovery() async throws {
        let session = RecordingStudioTestSession()
        session.beforeStop = { directory in
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(ScreenRecordingProjectStore.manifestName), withIntermediateDirectories: false)
        }
        let gate = Gate<CGImage>()
        let initialPreview = try image(red: 1, blue: 0, width: 3)
        let (model, root, _) = try fixture(capture: captureService(session), preview: { project, _, _ in
            if project.name == "Demo" { return initialPreview }
            return try await gate.wait()
        })
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.start()
        await model.operationTask?.value
        model.stop()
        await model.operationTask?.value

        let project = try #require(model.project)
        let directory = try #require(model.directory)
        let failure = try #require(model.errorMessage)
        await gate.waitUntilEntered()
        gate.reject(ScreenRecordingExportError.cannotRender)
        await model.previewTask?.value
        #expect(model.errorMessage == failure)
        #expect(model.isDirty)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(project.videoFile).path))
        #expect(!model.prepareToClose())
        #expect(model.project == project)

        try FileManager.default.removeItem(at: directory.appendingPathComponent(ScreenRecordingProjectStore.manifestName))
        model.saveProject()
        #expect(!model.isDirty)
        #expect(model.errorMessage == nil)
        #expect(try model.projectStore.load(from: directory) == project)
    }

    @Test func cancellationAfterCaptureAcceptsItsResultKeepsThePreviousProjectAndRemovesOnlyTheAttempt() async throws {
        let session = RecordingStudioTestSession()
        let capture = captureService(session)
        let (model, root, original) = try fixture(capture: capture)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        let originalDirectory = try #require(model.directory)
        let observer = capture.$phase.sink { phase in
            if phase == .idle, model.isStopping { model.cancelOperation() }
        }
        defer { observer.cancel() }
        model.start()
        await model.operationTask?.value
        let attempt = try #require(session.directory)

        model.stop()
        await model.operationTask?.value
        for await cancelling in model.$isCancelling.values {
            if !cancelling { break }
        }

        #expect(model.project == original)
        #expect(model.directory == originalDirectory)
        #expect(!model.isDirty)
        #expect(!FileManager.default.fileExists(atPath: attempt.path))
        #expect(try model.projectStore.load(from: originalDirectory) == original)
        #expect(try model.projectStore.recentDirectories().count == 1)
    }

    @Test func outputDirectoryChangesOnlyAffectNewProjectsAndPersistAcrossModels() throws {
        let suite = "zisla-studio-directory-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (model, root, original) = try fixture(outputDirectoryStore: ScreenRecordingOutputDirectoryStore(defaults: defaults))
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        let directory = try #require(model.directory)
        let custom = root.appendingPathComponent("custom", isDirectory: true)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: false)

        try model.setRecordingOutputDirectory(custom)
        #expect(model.recordingOutputDirectory.path == custom.path)
        #expect(model.projectStore.root.path == custom.path)
        #expect(model.directory == directory)
        #expect(model.project == original)
        try model.save()
        #expect(try model.projectStore.load(from: directory) == original)
        let restored = ScreenRecordingStudioModel(outputDirectoryStore: ScreenRecordingOutputDirectoryStore(defaults: defaults))
        defer { restored.shutdown() }
        #expect(restored.recordingOutputDirectory.path == custom.path)
    }

    @Test(arguments: ["录屏 2026/10/24 09:18", "录屏\\folder: title\n", String(repeating: "😀", count: 512),
                      "e" + String(repeating: "\u{301}", count: 512)])
    func suggestedSaveNamesAreSingleLegalFileComponents(_ name: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-file-name-test-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for suffix in ["mp4", "gif", "srt", ScreenRecordingProjectStore.projectExtension] {
            let fileName = ScreenRecordingStudioModel.fileName(name, extension: suffix)
            let url = root.appendingPathComponent(fileName)
            #expect(fileName.utf8.count <= 255)
            #expect(url.deletingLastPathComponent().path == root.path)
            #expect(!fileName.contains(":"))
            #expect(!fileName.contains("\\"))
            #expect(!fileName.contains("\n"))
            try Data([1]).write(to: url)
            #expect(try Data(contentsOf: url) == Data([1]))
        }
    }

    @Test func unavailableCustomDirectoryFailsWithoutReplacingThePreviousProjectOrFallingBack() async throws {
        let suite = "zisla-studio-directory-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = RecordingStudioTestSession()
        let (model, root, original) = try fixture(capture: captureService(session),
            outputDirectoryStore: ScreenRecordingOutputDirectoryStore(defaults: defaults))
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        let originalDirectory = try #require(model.directory)
        let custom = root.appendingPathComponent("custom", isDirectory: true)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: false)
        try model.setRecordingOutputDirectory(custom)
        try FileManager.default.removeItem(at: custom)
        try Data([7]).write(to: custom)
        var presentationStates: [Bool] = []
        model.showWindow = { presentationStates.append(model.isRecording) }

        model.start()
        await model.operationTask?.value

        #expect(session.directory == nil)
        #expect(model.project == original)
        #expect(model.directory == originalDirectory)
        #expect(model.recordingOutputDirectory.path == custom.path)
        #expect(model.errorMessage != nil)
        #expect(!model.isRecording)
        #expect(presentationStates.last == false, "Restore capture controls after resetting the failed attempt")
        #expect(try Data(contentsOf: custom) == Data([7]))
        #expect(try model.projectStore.load(from: originalDirectory) == original)
    }

    @Test func outputDirectoryCannotChangeDuringAnActiveRecording() async throws {
        let suite = "zisla-studio-directory-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = RecordingStudioTestSession()
        let (model, root, _) = try fixture(capture: captureService(session),
            outputDirectoryStore: ScreenRecordingOutputDirectoryStore(defaults: defaults))
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        let custom = root.appendingPathComponent("custom", isDirectory: true)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: false)
        model.start()
        await model.operationTask?.value

        try model.setRecordingOutputDirectory(custom)

        #expect(model.recordingOutputDirectory.path == root.path)
        #expect(defaults.data(forKey: "screen-recording-directory-bookmark") == nil)
        var presentationStates: [Bool] = []
        model.showWindow = { presentationStates.append(model.isRecording) }
        model.cancelOperation()
        for await cancelling in model.$isCancelling.values {
            if !cancelling { break }
        }
        #expect(presentationStates.last == false, "Restore camera preview after cancellation has finished")
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

@MainActor
private final class RecordingStudioTestSession: ScreenRecordingCaptureSession {
    var directory: URL?
    var beforeStop: ((URL) throws -> Void)?

    func useCameraPreview(_ preview: any ScreenRecordingCameraPreviewSession) {}

    func start() async throws -> Double {
        let directory = try #require(directory)
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("screen.mp4"))
        return 10
    }

    func setPaused(_ paused: Bool, atHostTime time: Double) async {}

    func stop(atHostTime time: Double) async throws -> ScreenRecordingResult {
        let directory = try #require(directory)
        try beforeStop?(directory)
        return ScreenRecordingResult(videoFile: "screen.mp4", duration: 2, width: 64, height: 48)
    }

    func cancel() async -> Error? { nil }
}
