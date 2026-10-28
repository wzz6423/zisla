import AppKit
import AVFoundation
import CoreImage
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@Suite(.serialized) @MainActor
struct ScreenRecordingClipShortcutTests {
    @Test
    func commandCopyDoesNotDuplicateUntilCommandPasteAndOneUndoRestoresTheProject() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        model.install(fixture.project(), directory: fixture.directory)
        let window = makeWindow(model)
        defer { window.close() }
        let original = model.project
        let clip = try #require(model.selectedTimelineClip)
        #expect(window.performKeyEquivalent(with: try key("c", window: window)))
        #expect(model.project == original && model.canPasteTimelineClip && !model.canUndo && !model.isDirty)
        model.seekTimeline(to: 1)
        #expect(window.performKeyEquivalent(with: try key("v", window: window)))
        let pasted = try #require(model.selectedTimelineClip)
        #expect(pasted.id != clip.id && pasted.start == 1 && pasted.trackID == clip.trackID)
        #expect(model.timeline?.clips.count == 2 && model.timeline?.assets.count == 1)
        model.undo()
        #expect(model.project == original && !model.canUndo && model.canRedo)
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) } && !window.isVisible)
    }

    @Test(arguments: [false, true])
    func nativeTextAndFieldEditorsKeepTheirCopyPasteActionsWithoutCopyingAClip(_ fieldEditor: Bool) throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        model.install(fixture.project(), directory: fixture.directory)
        let window = makeWindow(model)
        defer { window.close() }
        let editor = TextActionProbe(frame: CGRect(x: 0, y: 0, width: 200, height: 60))
        editor.string = fieldEditor ? "1.25" : "Annotation text"
        editor.isFieldEditor = fieldEditor
        window.contentView?.addSubview(editor)
        try #require(window.makeFirstResponder(editor))
        let project = model.project
        #expect(window.performKeyEquivalent(with: try key("c", window: window)))
        #expect(window.performKeyEquivalent(with: try key("v", window: window)))
        #expect(editor.actions == ["copy", "paste"])
        #expect(model.project == project && !model.canPasteTimelineClip && !model.canUndo)
        editor.isEditable = false
        editor.isSelectable = true
        #expect(window.performKeyEquivalent(with: try key("c", window: window)))
        #expect(editor.actions == ["copy", "paste", "copy"] && !model.canPasteTimelineClip)
    }

    @Test
    func shortcutsIgnoreOtherWindowsModifiedKeysMissingSelectionsAndEditingLocks() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = ScreenRecordingStudioModel(projectStore: fixture.store,
            outputDirectoryStore: try outputDirectoryStore(for: fixture),
            renderPreview: { _, _, _ in throw ScreenRecordingExportError.cannotRender },
            presentExportPanel: { _, _ in })
        defer { model.shutdown(); remove(fixture) }
        model.install(fixture.project(), directory: fixture.directory)
        let window = makeWindow(model)
        let other = makeWindow(nil)
        defer { window.close(); other.close() }
        let original = model.project
        _ = window.performKeyEquivalent(with: try key("c", window: other))
        for modifiers in [NSEvent.ModifierFlags(), [.command, .shift], [.command, .option]] {
            _ = window.performKeyEquivalent(with: try key("c", window: window, modifiers: modifiers))
        }
        #expect(!model.canPasteTimelineClip && model.project == original)
        model.selectTimelineTrack(try #require(model.timeline?.tracks.first?.id))
        _ = window.performKeyEquivalent(with: try key("c", window: window))
        #expect(!model.canPasteTimelineClip)
        model.selectTimelineClip(try #require(model.timeline?.clips.first?.id))
        #expect(window.performKeyEquivalent(with: try key("C", window: window, modifiers: [.command, .capsLock])))
        model.export()
        #expect(model.isChoosingFile)
        _ = window.performKeyEquivalent(with: try key("v", window: window))
        #expect(model.project == original && !model.canUndo && !model.canPasteTimelineClip)
    }

    @Test(arguments: [false, true])
    func spacePlaysAndPausesTheEditedTimelineWithoutChangingTheProject(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        _ = try await fixture.createVideo()
        var project = fixture.project()
        if multitrack { project.timeline = .migrating(project) }
        model.install(project, directory: fixture.directory)
        let window = makeWindow(model)
        defer { window.close() }
        model.seekTimeline(to: 0.5)
        let selection = model.selectedTimelineClipID
        let files = try fixture.files()

        #expect(window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        await model.operationTask?.value
        let player = try #require(model.activePlayer)
        #expect(model.isShowingTimelinePlayback && !model.isShowingSourcePlayback && !model.isBusy)
        #expect(player.currentItem?.videoComposition?.customVideoCompositorClass ==
            (multitrack ? RecordingMultitrackPlaybackCompositor.self : RecordingPlaybackCompositor.self))
        #expect(player.currentTime().seconds >= 0.49)
        #expect(window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        #expect(!model.isShowingTimelinePlayback && player.rate == 0)
        #expect(model.project == project && model.selectedTimelineClipID == selection && !model.canUndo && !model.isDirty)
        #expect(try fixture.files() == files)
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) } && !window.isVisible)
    }

    @Test
    func repeatedSpaceDoesNotStartOrTogglePlaybackAndBusyPlaybackCannotBeStartedAgain() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        _ = try await fixture.createVideo()
        let project = fixture.project()
        model.install(project, directory: fixture.directory)
        let window = makeWindow(model)
        defer { window.close() }
        let repeated = try key(" ", window: window, modifiers: [], repeated: true)
        #expect(window.performKeyEquivalent(with: repeated))
        #expect(!model.isShowingTimelinePlayback && !model.isBusy && model.operationTask == nil)

        #expect(window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        let operation = try #require(model.operationTask)
        #expect(model.isBusy)
        #expect(!window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        await operation.value
        let player = try #require(model.activePlayer)
        #expect(model.isShowingTimelinePlayback && !model.isBusy)
        #expect(window.performKeyEquivalent(with: repeated))
        #expect(model.isShowingTimelinePlayback && model.activePlayer === player)
        #expect(window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        #expect(!model.isShowingTimelinePlayback && player.rate == 0)
        #expect(window.performKeyEquivalent(with: repeated))
        #expect(!model.isShowingTimelinePlayback && !model.isBusy && model.operationTask == nil)
        #expect(model.project == project && !model.canUndo && !model.isDirty)
    }

    @Test(arguments: [false, true])
    func textAndFieldEditorsReceiveSpacesWithoutStartingPlayback(_ fieldEditor: Bool) throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        let project = fixture.project()
        model.install(project, directory: fixture.directory)
        let window = makeWindow(model)
        defer { window.close() }
        let editor = TextActionProbe(frame: CGRect(x: 0, y: 0, width: 200, height: 60))
        editor.string = fieldEditor ? "Inspector text" : "Canvas text"
        editor.isFieldEditor = fieldEditor
        window.contentView?.addSubview(editor)
        try #require(window.makeFirstResponder(editor))
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        let original = editor.string
        for repeated in [false, true] {
            let event = try key(" ", window: window, modifiers: [], repeated: repeated)
            #expect(!window.performKeyEquivalent(with: event))
            window.sendEvent(event)
        }
        #expect(editor.string == original + "  ")
        #expect(window.firstResponder === editor && editor.actions.isEmpty)
        #expect(!model.isShowingTimelinePlayback && !model.isBusy && model.operationTask == nil)
        #expect(model.project == project && !model.canUndo && !model.isDirty)
    }

    @Test
    func spaceIgnoresOtherWindowsAndModifiersAndRequiresAnExportableProject() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        let window = makeWindow(model)
        let other = makeWindow(nil)
        defer { window.close(); other.close() }
        #expect(!window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        #expect(!other.performKeyEquivalent(with: try key(" ", window: other, modifiers: [])))
        #expect(model.project == nil && !model.isBusy && model.operationTask == nil)

        var empty = fixture.project()
        empty.timeline = .init(assets: [], tracks: [], clips: [])
        model.install(empty, directory: fixture.directory)
        #expect(model.canEdit && !model.canExport)
        #expect(!window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        #expect(model.project == empty && !model.isBusy && model.operationTask == nil)

        let project = fixture.project()
        model.install(project, directory: fixture.directory)
        #expect(!window.performKeyEquivalent(with: try key(" ", window: other, modifiers: [])))
        for characters in ["", "c", "\r", "\t", "\u{1b}"] {
            #expect(!window.performKeyEquivalent(with: try key(characters, window: window, modifiers: [])))
        }
        let modifiedKeys: [NSEvent.ModifierFlags] = [.command, .option, .shift, .control, .function, .numericPad, [.command, .shift]]
        for modifiers in modifiedKeys {
            #expect(!window.performKeyEquivalent(with: try key(" ", window: window, modifiers: modifiers)))
        }
        #expect(model.project == project && !model.isShowingTimelinePlayback && !model.isBusy && model.operationTask == nil)
        #expect(!model.canUndo && !model.isDirty)
    }

    @Test(arguments: [false, true])
    func spaceRestartsAtZeroAfterSeekingToTheEndWithoutRequiringASelectedClip(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        _ = try await fixture.createVideo()
        var project = fixture.project()
        if multitrack { project.timeline = .migrating(project) }
        model.install(project, directory: fixture.directory)
        model.selectTimelineTrack(try #require(model.timeline?.tracks.first?.id))
        model.seekTimeline(to: project.outputDuration)
        let window = makeWindow(model)
        defer { window.close() }
        #expect(model.selectedTimelineClipID == nil && model.playbackTime == project.outputDuration)
        #expect(window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        await model.operationTask?.value
        #expect(model.isShowingTimelinePlayback && model.playbackTime < 0.25)
        #expect(try #require(model.activePlayer).currentTime().seconds < 0.25)
        #expect(window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        #expect(!model.isShowingTimelinePlayback && model.project == project && !model.canUndo && !model.isDirty)
    }

    @Test
    func spaceKeepsTheExportDialogLockedAndCancellationAllowsPlaybackAgain() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        var finish: ((URL?) -> Void)?
        let model = ScreenRecordingStudioModel(projectStore: fixture.store,
            outputDirectoryStore: try outputDirectoryStore(for: fixture),
            renderPreview: { _, _, _ in throw ScreenRecordingExportError.cannotRender },
            presentExportPanel: { _, completion in finish = completion })
        defer { model.shutdown(); remove(fixture) }
        _ = try await fixture.createVideo()
        let project = fixture.project()
        model.install(project, directory: fixture.directory)
        let window = makeWindow(model)
        defer { window.close() }
        model.export()
        #expect(model.isChoosingFile && !model.canExport)
        #expect(!window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        #expect(!model.isShowingTimelinePlayback && model.operationTask == nil && model.project == project)
        let completion = try #require(finish)
        completion(nil)
        #expect(!model.isChoosingFile && model.canExport)
        #expect(window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        let operation = try #require(model.operationTask)
        model.cancelOperation()
        await operation.value
        #expect(!model.isBusy && !model.isShowingTimelinePlayback && model.operationTask == nil)
        #expect(model.project == project && !model.canUndo && !model.isDirty)
        #expect(window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        await model.operationTask?.value
        #expect(model.isShowingTimelinePlayback)
        #expect(window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        #expect(!model.isShowingTimelinePlayback)
    }

    @Test
    func spaceCommitsPendingCanvasTextOnceAndPlaybackDoesNotAddAnUndoEntry() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        _ = try await fixture.createVideo()
        let project = fixture.project()
        model.install(project, directory: fixture.directory)
        let window = makeWindow(model)
        defer { window.close() }
        model.commitPendingCanvasText = { [weak model] in
            model?.commitPendingCanvasText = nil
            model?.update { $0.name = "Committed canvas text" }
        }
        #expect(window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        await model.operationTask?.value
        #expect(model.isShowingTimelinePlayback && model.project?.name == "Committed canvas text")
        #expect(window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        model.undo()
        #expect(model.project == project && !model.canUndo && model.canRedo)
    }

    @Test(arguments: [false, true])
    func spaceKeepsSheetAndModalSessionsFromStartingPlayback(_ sheet: Bool) throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        let project = fixture.project()
        model.install(project, directory: fixture.directory)
        let window = makeWindow(model)
        let dialog = makeWindow(nil)
        defer { window.close(); dialog.close() }
        let dialogFrame = dialog.frame
        if sheet {
            window.beginSheet(dialog)
            defer { window.endSheet(dialog); dialog.orderOut(nil) }
            try #require(window.attachedSheet === dialog)
            #expect(!window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        } else {
            let session = NSApplication.shared.beginModalSession(for: dialog)
            defer { NSApplication.shared.endModalSession(session); dialog.orderOut(nil) }
            dialog.orderOut(nil)
            dialog.setFrame(dialogFrame, display: false)
            try #require(NSApplication.shared.modalWindow === dialog)
            #expect(!window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        }
        #expect(model.project == project && !model.isShowingTimelinePlayback && !model.isBusy && model.operationTask == nil)
        #expect(!model.canUndo && !model.isDirty)
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) && !$0.frame.intersects(dialog.frame) })
    }

    @Test(arguments: [false, true])
    func nativeWindowDispatchTogglesTheComposedTimelineAndIgnoresRepeatedKeyDown(_ sourcePlayback: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        _ = try await fixture.createVideo()
        var project = fixture.project()
        project.timeline = .migrating(project)
        model.install(project, directory: fixture.directory)
        model.seekTimeline(to: 0.5)
        if sourcePlayback { model.playSource() }
        let source = try #require(model.player)
        let window = makeWindow(model)
        defer { window.close() }
        let responder = ForwardingKeyView(frame: .init(x: 0, y: 0, width: 100, height: 100))
        window.contentView?.addSubview(responder)
        try #require(window.makeFirstResponder(responder))
        let space = try key(" ", window: window, modifiers: [])
        let repeated = try key(" ", window: window, modifiers: [], repeated: true)
        window.sendEvent(space)
        let operation = try #require(model.operationTask, "Native key dispatch must start composed timeline playback")
        window.sendEvent(repeated)
        #expect(model.isBusy)
        await operation.value
        let player = try #require(model.activePlayer)
        #expect(model.isShowingTimelinePlayback && !model.isShowingSourcePlayback && source.rate == 0)
        #expect(player !== source && player.currentItem?.videoComposition?.customVideoCompositorClass ==
            RecordingMultitrackPlaybackCompositor.self)
        window.sendEvent(repeated)
        #expect(model.isShowingTimelinePlayback && model.activePlayer === player)
        window.sendEvent(space)
        #expect(!model.isShowingTimelinePlayback && player.rate == 0)
        window.sendEvent(repeated)
        #expect(!model.isShowingTimelinePlayback && !model.isBusy && model.operationTask == nil)
        #expect(!responder.keys.isEmpty && window.firstResponder === responder)
        #expect(model.project == project && !model.canUndo && !model.isDirty)
        #expect(!window.isVisible && !window.isKeyWindow)
    }

    @Test
    func nativeDispatchLeavesModifiedSpaceEnterEscapeAndAnEmptyProjectAlone() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        let window = makeWindow(model)
        defer { window.close() }
        let responder = ForwardingKeyView(frame: .init(x: 0, y: 0, width: 100, height: 100))
        window.contentView?.addSubview(responder)
        try #require(window.makeFirstResponder(responder))
        window.sendEvent(try key(" ", window: window, modifiers: []))
        #expect(model.project == nil && model.operationTask == nil)
        let project = fixture.project()
        model.install(project, directory: fixture.directory)
        let modifiers: [NSEvent.ModifierFlags] = [.command, .option, .shift, .control, .function, .numericPad]
        for modifiers in modifiers {
            window.sendEvent(try key(" ", window: window, modifiers: modifiers))
        }
        let other = makeWindow(nil)
        defer { other.close() }
        window.keyDown(with: try key(" ", window: other, modifiers: []))
        for characters in ["\r", "\u{1b}"] {
            window.sendEvent(try key(characters, window: window, modifiers: []))
        }
        #expect(model.project == project && !model.isShowingTimelinePlayback && !model.isBusy && model.operationTask == nil)
        #expect(window.firstResponder === responder && !responder.keys.isEmpty && !model.isDirty && !model.canUndo)
    }

    @Test(arguments: [NSEvent.ModifierFlags.capsLock, .init(rawValue: 0x100)])
    func nonKeyModifierFlagsDoNotChangeTheMeaningOfASpace(_ flags: NSEvent.ModifierFlags) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        _ = try await fixture.createVideo()
        let project = fixture.project()
        model.install(project, directory: fixture.directory)
        let window = makeWindow(model)
        defer { window.close() }
        #expect(window.performKeyEquivalent(with: try key(" ", window: window, modifiers: flags)))
        await model.operationTask?.value
        #expect(model.isShowingTimelinePlayback)
        #expect(window.performKeyEquivalent(with: try key(" ", window: window, modifiers: flags)))
        #expect(!model.isShowingTimelinePlayback && model.project == project && !model.canUndo && !model.isDirty)
    }

    @Test(arguments: [false, true], [false, true])
    func spaceCannotTogglePlaybackDuringRecordingOrWhileRecordingIsPaused(_ paused: Bool, _ playing: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let session = RecordingSession()
        let capture = ScreenRecordingService(dependencies: .init(
            loadSources: { [] }, loadDevices: { .init() }, requestPermission: { _ in true },
            makeSession: { _, _, _ in session },
            makeCameraPreview: { _, _ in fatalError("Camera preview is disabled in shortcut tests") },
            now: { 10 }, scheduleTick: { _ in {} }))
        let model = try makeModel(fixture, capture: capture)
        defer { model.shutdown(); remove(fixture) }
        _ = try await fixture.createVideo()
        let project = fixture.project()
        model.install(project, directory: fixture.directory)
        if playing { model.playTimeline(); await model.operationTask?.value }
        let playback = model.activePlayer
        try await capture.start(configuration: .init(systemAudio: false, microphone: false, camera: false), directory: fixture.directory)
        if paused { await capture.togglePause() }
        let phase = capture.phase
        let window = makeWindow(model)
        defer { window.close() }
        #expect(model.isRecording && !model.canExport)
        #expect(!window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        window.sendEvent(try key(" ", window: window, modifiers: []))
        #expect(capture.phase == phase && model.isShowingTimelinePlayback == playing && !model.isBusy && model.operationTask == nil)
        #expect(model.activePlayer === playback)
        #expect(model.project == project && !model.canUndo && !model.isDirty)
        await capture.cancel()
        #expect(session.cancelled && capture.phase == .idle && model.canExport)
    }

    @Test
    func aRealFieldEditorReceivesSpacesThroughTheWindowWithoutStartingPlayback() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        let project = fixture.project()
        model.install(project, directory: fixture.directory)
        let window = makeWindow(model)
        defer { window.close() }
        let field = NSTextField(string: "Inspector value")
        field.frame = .init(x: 0, y: 0, width: 200, height: 30)
        window.contentView?.addSubview(field)
        try #require(window.makeFirstResponder(field))
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(editor.isFieldEditor)
        editor.setSelectedRange(.init(location: editor.string.utf16.count, length: 0))
        let event = try key(" ", window: window, modifiers: [])
        #expect(!window.performKeyEquivalent(with: event))
        window.sendEvent(event)
        #expect(editor.string == "Inspector value " && window.firstResponder === editor)
        #expect(model.project == project && !model.isShowingTimelinePlayback && !model.isBusy && model.operationTask == nil)
    }

    @Test
    func anUnhandledSpaceFromANoneditableTextResponderKeepsTextFocusAndDoesNotPlay() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        let project = fixture.project()
        model.install(project, directory: fixture.directory)
        let window = makeWindow(model)
        defer { window.close() }
        let editor = UnhandledTextView(frame: .init(x: 0, y: 0, width: 200, height: 60))
        editor.isEditable = false
        editor.isSelectable = true
        editor.string = "Readonly text"
        window.contentView?.addSubview(editor)
        try #require(window.makeFirstResponder(editor))
        window.sendEvent(try key(" ", window: window, modifiers: []))
        #expect(editor.string == "Readonly text" && window.firstResponder === editor)
        #expect(model.project == project && !model.isShowingTimelinePlayback && !model.isBusy && model.operationTask == nil)
    }

    @Test
    func missingMediaFailsPlaybackWithoutChangingTheProjectAndSpaceRetriesAfterRestoration() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try makeModel(fixture)
        defer { model.shutdown(); remove(fixture) }
        let media = try await fixture.createVideo()
        let unavailable = fixture.directory.appendingPathComponent("unavailable.mp4")
        let project = fixture.project()
        model.install(project, directory: fixture.directory)
        let files = try fixture.files()
        try FileManager.default.moveItem(at: media, to: unavailable)
        let window = makeWindow(model)
        defer { window.close() }
        window.sendEvent(try key(" ", window: window, modifiers: []))
        await model.operationTask?.value
        #expect(model.errorMessage != nil && !model.isBusy && !model.isShowingTimelinePlayback && model.canExport)
        #expect(model.project == project && !model.canUndo && !model.isDirty && model.operationTask == nil)
        try FileManager.default.moveItem(at: unavailable, to: media)
        window.sendEvent(try key(" ", window: window, modifiers: []))
        await model.operationTask?.value
        #expect(model.isShowingTimelinePlayback && !model.isBusy)
        window.sendEvent(try key(" ", window: window, modifiers: []))
        #expect(!model.isShowingTimelinePlayback && model.project == project && !model.canUndo && !model.isDirty)
        #expect(try fixture.files() == files)
    }

    @Test
    func activeExportRejectsSpaceWithoutPausingTheTimelineAndCancellationRestoresTheShortcut() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let gate = ExportGate()
        let exporter = ScreenRecordingExporter { checkpoint in
            if checkpoint == .beforeRead { gate.waitForRelease() }
        }
        let model = try makeModel(fixture, exporter: exporter)
        defer { model.shutdown(); remove(fixture) }
        _ = try await fixture.createVideo()
        let project = fixture.project()
        model.install(project, directory: fixture.directory)
        model.playTimeline()
        await model.operationTask?.value
        let player = try #require(model.activePlayer)
        let destination = fixture.root.appendingPathComponent("result.mp4")
        let task = Task {
            try await exporter.export(project: project, directory: fixture.directory, to: destination,
                configuration: .init(format: .mp4, resolution: .source, frameRate: 8))
        }
        defer { task.cancel(); gate.release() }
        for await _ in gate.entered.stream { break }
        try #require(exporter.isExporting && !model.canExport)
        let window = makeWindow(model)
        defer { window.close() }
        #expect(!window.performKeyEquivalent(with: try key(" ", window: window, modifiers: [])))
        window.sendEvent(try key(" ", window: window, modifiers: []))
        #expect(model.isShowingTimelinePlayback && model.activePlayer === player && model.operationTask == nil)
        exporter.cancel()
        gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!exporter.isExporting && model.canExport && !FileManager.default.fileExists(atPath: destination.path))
        window.sendEvent(try key(" ", window: window, modifiers: []))
        #expect(!model.isShowingTimelinePlayback && player.rate == 0 && model.project == project && !model.canUndo && !model.isDirty)
    }

    private func makeModel(_ fixture: RecordingMultitrackTestFixture,
                           capture: ScreenRecordingService = ScreenRecordingService(),
                           exporter: ScreenRecordingExporter = ScreenRecordingExporter()) throws -> ScreenRecordingStudioModel {
        let image = try #require(CIContext().createCGImage(CIImage(color: .black), from: CGRect(x: 0, y: 0, width: 64, height: 48)))
        return ScreenRecordingStudioModel(capture: capture, exporter: exporter, projectStore: fixture.store,
            outputDirectoryStore: try outputDirectoryStore(for: fixture), renderPreview: { _, _, _ in image })
    }

    private func outputDirectoryStore(for fixture: RecordingMultitrackTestFixture) throws -> ScreenRecordingOutputDirectoryStore {
        let defaults = try #require(UserDefaults(suiteName: fixture.root.lastPathComponent))
        defaults.set(fixture.root.path, forKey: "screen-recording-directory-path")
        return ScreenRecordingOutputDirectoryStore(defaults: defaults)
    }

    private func remove(_ fixture: RecordingMultitrackTestFixture) {
        UserDefaults(suiteName: fixture.root.lastPathComponent)?.removePersistentDomain(forName: fixture.root.lastPathComponent)
        fixture.remove()
    }

    private func makeWindow(_ model: ScreenRecordingStudioModel?) -> ScreenRecordingStudioWindow {
        let window = ScreenRecordingStudioWindow(contentRect: CGRect(x: -100_000, y: -100_000, width: 400, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.studioModel = model
        window.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        return window
    }

    private func key(_ characters: String, window: NSWindow, modifiers: NSEvent.ModifierFlags = .command,
                     repeated: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: repeated, keyCode: [" ": 49, "c": 8, "\r": 36, "\u{1b}": 53, "\t": 48][characters.lowercased()] ?? 9))
    }

    private final class ForwardingKeyView: NSView {
        var keys: [String] = []
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            keys.append(event.charactersIgnoringModifiers ?? "")
            super.keyDown(with: event)
        }
    }

    private final class UnhandledTextView: NSTextView {
        override func keyDown(with event: NSEvent) { nextResponder?.keyDown(with: event) }
    }

    private final class ExportGate: @unchecked Sendable {
        let entered = AsyncStream<Void>.makeStream()
        private let semaphore = DispatchSemaphore(value: 0)
        func waitForRelease() { entered.continuation.yield(()); semaphore.wait() }
        func release() { semaphore.signal() }
    }

    private final class RecordingSession: ScreenRecordingCaptureSession {
        var cancelled = false
        func useCameraPreview(_ preview: any ScreenRecordingCameraPreviewSession) {}
        func start() async throws -> Double { 10 }
        func setPaused(_ paused: Bool, atHostTime time: Double) async {}
        func stop(atHostTime time: Double) async throws -> ScreenRecordingResult {
            .init(videoFile: "screen.mp4", duration: 2, width: 64, height: 48)
        }
        func cancel() async -> Error? { cancelled = true; return nil }
    }

    private final class TextActionProbe: NSTextView {
        var actions: [String] = []
        override func copy(_ sender: Any?) { actions.append("copy") }
        override func paste(_ sender: Any?) { actions.append("paste") }
    }
}
