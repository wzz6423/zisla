import AppKit
import SwiftUI
import Testing
import WebKit
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite(.serialized) @MainActor
struct TextEditingCommandTests {
    @Test
    func ordinaryStudioAIInstructionSupportsSelectAllUndoAndRedo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-text-commands-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ScreenRecordingStudioModel(projectStore: ScreenRecordingProjectStore(root: root))
        defer { model.shutdown() }
        model.aiInstruction = "111"
        let host = NSHostingView(rootView: ScreenRecordingAIView(model: model))
        host.frame = CGRect(x: 0, y: 0, width: 340, height: 240)
        let window = makeWindow()
        window.contentView = host
        defer { window.close() }
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let editor = try #require(descendants(NSTextView.self, in: host).first)
        #expect(window.makeFirstResponder(editor))
        let stop = startMonitor()
        defer { stop() }

        try send("a", to: window)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 3))
        editor.insertText("新的指令\n222", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        #expect(model.aiInstruction == "新的指令\n222")
        try send("z", to: window)
        #expect(editor.string == "111" && model.aiInstruction == "111")
        try send("z", to: window, modifiers: [.command, .shift])
        #expect(editor.string == "新的指令\n222" && model.aiInstruction == "新的指令\n222")
        #expect(model.project == nil && !model.canUndo && !model.canRedo)
        #expect(!window.isVisible, "The contract test must not present a real application window")
    }

    @Test
    func ordinaryTextFieldsUseTheirNativeFieldEditorForEditingCommands() throws {
        let window = makeWindow()
        defer { window.close() }
        let field = NSTextField(string: "111")
        field.frame = CGRect(x: 10, y: 10, width: 220, height: 24)
        window.contentView = field
        #expect(window.makeFirstResponder(field))
        let editor = try #require(window.firstResponder as? NSTextView)
        let stop = startMonitor()
        defer { stop() }

        try send("a", to: window)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 3))
        editor.insertText("Field 222", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        try send("z", to: window)
        #expect(editor.string == "111")
        try send("z", to: window, modifiers: [.command, .shift])
        #expect(editor.string == "Field 222")
        #expect(window.makeFirstResponder(nil))
        #expect(field.stringValue == "Field 222")
    }

    @Test(arguments: [WindowKind.settings, .notes, .island])
    func legacyWindowsUndoNativeTextWithoutSendingUnsupportedUndoSelectors(_ kind: WindowKind) throws {
        let window = makeWindow(kind)
        defer { window.close() }
        let editor = textView(in: window, value: "111")
        editor.insertText("222", replacementRange: NSRange(location: 0, length: 3))
        editor.breakUndoCoalescing()

        #expect(window.performKeyEquivalent(with: try key("z", in: window)))
        #expect(editor.string == "111")
        #expect(window.performKeyEquivalent(with: try key("z", in: window, modifiers: [.command, .shift])))
        #expect(editor.string == "222")
    }

    @Test
    func copyCutAndPastePreserveTheSelectedRangeAndUseNativeTextSerialization() throws {
        let window = makeWindow()
        defer { window.close() }
        let editor = IsolatedPasteboardTextView(frame: window.contentLayoutRect)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.string = "前缀|选中\n111|后缀"
        window.contentView = editor
        #expect(window.makeFirstResponder(editor))
        defer { editor.pasteboard.releaseGlobally() }
        let stop = startMonitor()
        defer { stop() }
        let selected = (editor.string as NSString).range(of: "选中\n111")
        editor.setSelectedRange(selected)
        let plainTextType = try #require(editor.writablePasteboardTypes.first)

        try send("c", to: window)
        #expect(editor.pasteboard.string(forType: plainTextType) == "选中\n111")
        #expect(editor.string == "前缀|选中\n111|后缀")
        try send("x", to: window)
        #expect(editor.string == "前缀||后缀")
        #expect(editor.pasteboard.string(forType: plainTextType) == "选中\n111")
        editor.pasteboard.clearContents()
        #expect(editor.pasteboard.setString("替换😀\n222", forType: plainTextType))
        try send("v", to: window)
        #expect(editor.string == "前缀|替换😀\n222|后缀")
        editor.pasteboard.clearContents()
        try send("v", to: window)
        #expect(editor.string == "前缀|替换😀\n222|后缀", "Empty clipboard data must not erase an input")
    }

    @Test(arguments: [NSEvent.ModifierFlags.capsLock, .numericPad, .function, [.capsLock, .numericPad, .function]])
    func incidentalFlagsAndUppercaseKeysStillSelectTheCompleteUnicodeText(_ flags: NSEvent.ModifierFlags) throws {
        let window = makeWindow()
        defer { window.close() }
        let value = "你好👩🏽‍💻\n111"
        let editor = textView(in: window, value: value)
        #expect(TextEditingCommands.handle(try key("A", in: window, modifiers: flags.union(.command))) == nil)
        #expect(editor.selectedRange() == NSRange(location: 0, length: (value as NSString).length))
    }

    @Test(arguments: [NSEvent.ModifierFlags(), .shift, .option, .control,
                      [.command, .option], [.command, .control], [.command, .shift]])
    func differentShortcutsPassThroughWithoutChangingTheInput(_ flags: NSEvent.ModifierFlags) throws {
        let window = makeWindow()
        defer { window.close() }
        let editor = textView(in: window, value: "111")
        let selection = editor.selectedRange()
        let event = try key("a", in: window, modifiers: flags)
        #expect(TextEditingCommands.handle(event) === event)
        #expect(editor.string == "111" && editor.selectedRange() == selection)
    }

    @Test
    func missingWindowsAndUnknownKeysPassThrough() throws {
        let window = makeWindow()
        defer { window.close() }
        let editor = textView(in: window, value: "111")
        for value in ["", "s", "q"] {
            let event = try key(value, in: window)
            #expect(TextEditingCommands.handle(event) === event)
        }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a",
            isARepeat: false, keyCode: 0))
        #expect(event.window == nil)
        #expect(TextEditingCommands.handle(event) === event)
        #expect(editor.string == "111")
    }

    @Test(arguments: ["empty", "disabled", "read-only", "read-only-redo", "missing-manager"])
    func unavailableTextHistoryCannotUndoTheProject(_ mode: String) throws {
        let window = ScreenshotEditorWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var projectRevision = 2
        window.onUndo = { projectRevision = 1 }
        window.onRedo = { projectRevision = 3 }
        let editor = mode == "missing-manager" ? NoUndoManagerTextView() : NSTextView()
        editor.allowsUndo = mode != "disabled"
        editor.string = "111"
        window.contentView = editor
        #expect(window.makeFirstResponder(editor))
        if mode == "read-only" || mode == "read-only-redo" {
            editor.insertText("222", replacementRange: NSRange(location: 0, length: 3))
            editor.breakUndoCoalescing()
            if mode == "read-only-redo" { editor.undoManager?.undo() }
            editor.isEditable = false
        }
        let value = editor.string
        let changes = TextChangeProbe()
        editor.delegate = changes

        for modifiers in [NSEvent.ModifierFlags.command, [.command, .shift]] {
            let event = try key("z", in: window, modifiers: modifiers)
            if let unhandled = TextEditingCommands.handle(event) {
                _ = window.performKeyEquivalent(with: unhandled)
            }
            #expect(editor.string == value && projectRevision == 2)
            #expect(!changes.didChange, "Unavailable text history must not emit a false edit notification")
        }
    }

    @Test
    func noTextFocusPreservesProjectUndoAndRedo() throws {
        let window = ScreenshotEditorWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var projectRevision = 2
        window.onUndo = { projectRevision = 1 }
        window.onRedo = { projectRevision = 2 }
        #expect(window.makeFirstResponder(nil))
        let undo = try key("z", in: window)
        #expect(TextEditingCommands.handle(undo) === undo)
        #expect(window.performKeyEquivalent(with: undo))
        #expect(projectRevision == 1)
        let redo = try key("z", in: window, modifiers: [.command, .shift])
        #expect(TextEditingCommands.handle(redo) === redo)
        #expect(window.performKeyEquivalent(with: redo))
        #expect(projectRevision == 2)
    }

    @Test
    func shortcutRecordingKeepsCommandKeysInsteadOfEditingText() throws {
        let window = makeWindow(.settings)
        defer { window.close() }
        let recorder = HotkeyRecorderButton(hotkey: nil, locale: Locale(identifier: "en"))
        window.contentView = recorder
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        recorder.mouseDown(with: click)
        defer { recorder.stopRecording() }
        #expect(recorder.isRecording)
        var recorded: VoiceInputHotkeyPreset?
        recorder.onRecord = { recorded = $0 }
        let event = try key("a", in: window)

        #expect(TextEditingCommands.handle(event) === event)
        #expect(window.performKeyEquivalent(with: event))
        #expect(recorded?.keyCode == 0 && recorded?.carbonModifiers == 0x0100)
        #expect(!recorder.isRecording)
    }

    @Test
    func hiddenRichNoteEditorKeepsItsExistingUndoAndRedoCommands() async throws {
        let host = NSHostingView(rootView: RichNoteEditor(html: "<div>初始内容</div>", command: nil,
            isEditable: true, onChange: { _, _ in }).frame(width: 320, height: 240))
        let window = makeWindow(.notes)
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        var readyView: WKWebView?
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if let candidate = descendants(WKWebView.self, in: host).first,
               (try? await candidate.evaluateJavaScript("Boolean(window.zisla?.exec)")) as? Bool == true {
                readyView = candidate
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let webView = try #require(readyView, "The local rich-note editor must finish loading in its hidden host")
        #expect(window.makeFirstResponder(webView))
        _ = try await webView.evaluateJavaScript("""
            (() => {
              const editor = document.getElementById('editor');
              editor.focus();
              const range = document.createRange();
              range.selectNodeContents(editor);
              range.collapse(false);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              window.zisla.exec('insertText', '变更');
            })();
            """)
        #expect(try await webView.evaluateJavaScript("document.getElementById('editor').innerText") as? String == "初始内容变更")
        let undo = try key("z", in: window)
        #expect(TextEditingCommands.handle(undo) === undo)
        #expect(window.performKeyEquivalent(with: undo))
        #expect(try await webView.evaluateJavaScript("document.getElementById('editor').innerText") as? String == "初始内容")
        #expect(window.performKeyEquivalent(with: try key("z", in: window, modifiers: [.command, .shift])))
        #expect(try await webView.evaluateJavaScript("document.getElementById('editor').innerText") as? String == "初始内容变更")
        #expect(!window.isVisible)
    }

    @Test(arguments: ["c", "v", "x", "z"])
    func unsupportedActionsOnANonEditingResponderPassThroughSafely(_ value: String) throws {
        let window = makeWindow(.notes)
        defer { window.close() }
        let view = NonEditingView(frame: window.contentLayoutRect)
        window.contentView = view
        #expect(window.makeFirstResponder(view))
        let event = try key(value, in: window)
        #expect(TextEditingCommands.handle(event) === event)
        #expect(!window.performKeyEquivalent(with: event))
    }

    @Test
    func monitorStopsWhenTerminationHappensBeforeTheApplicationModelStarts() throws {
        let window = makeWindow()
        defer { window.close() }
        let editor = textView(in: window, value: "111")
        let delegate = AppDelegate()
        delegate.configureTextEditingCommands()
        defer { delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        try send("a", to: window)
        #expect(editor.selectedRange().length == 3)

        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        try send("a", to: window)
        #expect(editor.selectedRange() == NSRange(location: 3, length: 0), "Terminated monitors must stop consuming events")
    }

    enum WindowKind { case ordinary, settings, notes, island }

    private func makeWindow(_ kind: WindowKind = .ordinary) -> NSWindow {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 340, height: 240)
        let window: NSWindow = switch kind {
        case .ordinary: NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        case .settings: SettingsWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        case .notes: QuickNotesEditorWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        case .island: IslandPanel(contentView: NSView(frame: frame), frame: frame)
        }
        window.isReleasedWhenClosed = false
        return window
    }

    private func textView(in window: NSWindow, value: String) -> NSTextView {
        let editor = NSTextView(frame: window.contentLayoutRect)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.string = value
        window.contentView = editor
        #expect(window.makeFirstResponder(editor))
        return editor
    }

    private func startMonitor() -> () -> Void {
        let delegate = AppDelegate()
        delegate.configureTextEditingCommands()
        return { delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
    }

    private func send(_ value: String, to window: NSWindow, modifiers: NSEvent.ModifierFlags = .command) throws {
        NSApplication.shared.sendEvent(try key(value, in: window, modifiers: modifiers))
    }

    private func key(_ value: String, in window: NSWindow, modifiers: NSEvent.ModifierFlags = .command) throws -> NSEvent {
        let code: UInt16 = switch value.lowercased() {
        case "z": 6
        case "c": 8
        case "v": 9
        case "x": 7
        default: 0
        }
        return try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: value,
            charactersIgnoringModifiers: value, isARepeat: false, keyCode: code))
    }

    private func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(type, in: $0) }
    }
}

private final class NoUndoManagerTextView: NSTextView {
    override var undoManager: UndoManager? { nil }
}

private final class NonEditingView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

private final class TextChangeProbe: NSObject, NSTextViewDelegate {
    var didChange = false
    func textDidChange(_ notification: Notification) { didChange = true }
}

private final class IsolatedPasteboardTextView: NSTextView {
    let pasteboard = NSPasteboard.withUniqueName()

    // Keep native text serialization while isolating tests from the user's system pasteboard.
    override func copy(_ sender: Any?) {
        pasteboard.declareTypes(writablePasteboardTypes, owner: nil)
        _ = writeSelection(to: pasteboard, types: writablePasteboardTypes)
    }

    override func cut(_ sender: Any?) {
        copy(sender)
        deleteBackward(sender)
    }

    override func paste(_ sender: Any?) {
        if let type = pasteboard.availableType(from: readablePasteboardTypes) {
            _ = readSelection(from: pasteboard, type: type)
        }
    }
}
