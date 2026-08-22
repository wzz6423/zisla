import AppKit
import SwiftUI
import Testing
import WebKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct RichNoteEditorTests {
    @Test
    func acceptsFirstMouseToRestoreEditingFocus() async throws {
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(
                html: "<div>正文</div>",
                command: nil,
                isEditable: true,
                onChange: { _, _ in }
            )
            .frame(width: 320, height: 240)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let webView = try await waitForWebView(in: hostingView)

        #expect(webView.acceptsFirstMouse(for: nil))
    }

    @Test
    func showsCaretOnEmptyLine() async throws {
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(
                html: "<div>正文</div><div><br></div>",
                command: nil,
                isEditable: true,
                onChange: { _, _ in }
            )
            .frame(width: 320, height: 240)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let webView = try await waitForWebView(in: hostingView)
        try await waitUntilEditorIsReady(in: webView)
        // WebView in test host does not receive foreground frames; this only removes requestAnimationFrame throttling.
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const editor = document.getElementById('editor');
              const emptyLine = editor.lastElementChild;
              window.requestAnimationFrame = callback => { callback(performance.now()); return 1; };
              editor.focus();
              const range = document.createRange();
              range.setStart(emptyLine, 0);
              range.collapse(true);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              document.dispatchEvent(new Event('selectionchange'));
            })();
            """
        )
        let isVisible = try await waitForCaret(in: webView)

        #expect(isVisible)
    }

    @Test
    func undoAndRedoKeyboardShortcutsChangeRichNoteContent() async throws {
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(
                html: "<div>初始内容</div>",
                command: nil,
                isEditable: true,
                onChange: { _, _ in }
            )
            .frame(width: 320, height: 240)
        )
        let window = QuickNotesEditorWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        let webView = try await waitForWebView(in: hostingView)
        try await waitUntilEditorIsReady(in: webView)
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const editor = document.getElementById('editor');
              const text = editor.firstChild.firstChild;
              const range = document.createRange();
              range.setStart(text, text.textContent.length);
              range.collapse(true);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              window.zisla.exec('insertText', '变更');
              return editor.innerText;
            })();
            """
        )
        #expect(try await editorText(in: webView) == "初始内容变更")

        #expect(window.performKeyEquivalent(with: try keyEvent(
            characters: "z",
            modifiers: .command,
            window: window
        )))
        #expect(try await editorText(in: webView) == "初始内容")

        #expect(window.performKeyEquivalent(with: try keyEvent(
            characters: "Z",
            modifiers: [.command, .shift],
            window: window
        )))
        #expect(try await editorText(in: webView) == "初始内容变更")
    }

    private func waitForWebView(in view: NSView) async throws -> WKWebView {
        for _ in 0..<100 {
            view.layoutSubtreeIfNeeded()
            if let webView = findWebView(in: view) {
                return webView
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw RichNoteEditorTestError.webViewNotCreated
    }

    private func waitUntilEditorIsReady(in webView: WKWebView) async throws {
        for _ in 0..<100 {
            if try await webView.evaluateJavaScript("Boolean(window.zisla)") as? Bool == true {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw RichNoteEditorTestError.editorNotReady
    }

    private func waitForCaret(in webView: WKWebView) async throws -> Bool {
        for _ in 0..<20 {
            if try await webView.evaluateJavaScript("(() => { const caret = document.getElementById('caret'); const rect = caret.getBoundingClientRect(); return caret.classList.contains('is-visible') && rect.width > 0 && rect.height > 0; })()") as? Bool == true {
                return true
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func editorText(in webView: WKWebView) async throws -> String {
        try #require(await webView.evaluateJavaScript("document.getElementById('editor').innerText") as? String)
    }

    private func keyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags,
        window: NSWindow
    ) throws -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters.lowercased(),
            isARepeat: false,
            keyCode: 6
        ) else {
            throw RichNoteEditorTestError.keyEventNotCreated
        }
        return event
    }

    private func findWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView {
            return webView
        }
        for subview in view.subviews {
            if let webView = findWebView(in: subview) {
                return webView
            }
        }
        return nil
    }
}

private enum RichNoteEditorTestError: Error {
    case webViewNotCreated
    case editorNotReady
    case keyEventNotCreated
}
