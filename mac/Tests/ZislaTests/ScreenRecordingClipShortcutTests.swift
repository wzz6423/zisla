import AppKit
import Testing
import ZislaCore
@testable import Zisla

@Suite(.serialized) @MainActor
struct ScreenRecordingClipShortcutTests {
    @Test
    func commandCopyDoesNotDuplicateUntilCommandPasteAndOneUndoRestoresTheProject() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
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
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
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
            renderPreview: { _, _, _ in throw ScreenRecordingExportError.cannotRender },
            presentExportPanel: { _, _ in })
        defer { model.shutdown(); fixture.remove() }
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

    private func makeWindow(_ model: ScreenRecordingStudioModel?) -> ScreenRecordingStudioWindow {
        let window = ScreenRecordingStudioWindow(contentRect: CGRect(x: -100_000, y: -100_000, width: 400, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.studioModel = model
        window.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        return window
    }

    private func key(_ characters: String, window: NSWindow, modifiers: NSEvent.ModifierFlags = .command) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: characters.lowercased() == "c" ? 8 : 9))
    }

    private final class TextActionProbe: NSTextView {
        var actions: [String] = []
        override func copy(_ sender: Any?) { actions.append("copy") }
        override func paste(_ sender: Any?) { actions.append("paste") }
    }
}
