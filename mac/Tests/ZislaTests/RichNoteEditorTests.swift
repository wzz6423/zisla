import AppKit
import SwiftUI
import Testing
import WebKit
import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct RichNoteEditorTests {
    @Test
    func keepsSyncedBodyHTMLInsteadOfMigratingMarkdown() {
        let content = NotesAppBridge.NoteContent(
            plainText: "# 标题\n    缩进行",
            bodyHTML: "<pre># 标题\n    缩进行</pre>"
        )

        #expect(RichNoteEditor.editableHTML(for: content) == content.bodyHTML)
    }

    @Test
    func blocksActiveContentFromSyncedNoteHTML() async throws {
        let maliciousHTML = """
        <div>safe content</div>
        <img src="invalid" onerror="window.zislaCompromised = true">
        <iframe srcdoc="<script>window.top.zislaCompromised = true</script>"></iframe>
        <form action="https://example.com"><input name="secret"></form>
        """
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(
                html: maliciousHTML,
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
        window.alphaValue = 0
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let webView = try await waitForWebView(in: hostingView)
        try await waitUntilEditorIsReady(in: webView)
        let result = try #require(await webView.evaluateJavaScript(
            """
            (() => ({
              compromised: Boolean(window.zislaCompromised),
              activeElementCount: document.getElementById('editor').querySelectorAll('script, iframe, frame, object, embed, form, meta, link').length,
              eventHandlerCount: document.getElementById('editor').querySelectorAll('[onerror], [srcdoc]').length,
              text: document.getElementById('editor').innerText
            }))()
            """
        ) as? [String: Any])

        #expect(result["compromised"] as? Bool == false)
        #expect(result["activeElementCount"] as? Int == 0)
        #expect(result["eventHandlerCount"] as? Int == 0)
        #expect((result["text"] as? String)?.contains("safe content") == true)
    }

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
        window.alphaValue = 0
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
        window.alphaValue = 0
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
    func preservesLeadingWhitespaceWithoutRenderingHTMLFormattingWhitespace() async throws {
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(
                html: """
                <div><span style="font-size: 11px">第一行</span><span style="font-size: 11px"><br></span></div>
                <div><span style="font-size: 11px">    缩进行</span></div>
                """,
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
        window.alphaValue = 0
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let webView = try await waitForWebView(in: hostingView)
        try await waitUntilEditorIsReady(in: webView)
        let result = try #require(await webView.evaluateJavaScript(
            """
            (() => {
              const editor = document.getElementById('editor');
              const firstBlock = editor.children[0];
              const secondBlock = editor.children[1];
              const first = firstBlock.querySelector('span').firstChild;
              const second = secondBlock.querySelector('span').firstChild;
              const firstRange = document.createRange();
              firstRange.setStart(first, 0);
              firstRange.setEnd(first, 1);
              const secondRange = document.createRange();
              const firstNonWhitespace = second.textContent.search(/\\S/);
              secondRange.setStart(second, firstNonWhitespace);
              secondRange.setEnd(second, firstNonWhitespace + 1);
              return {
                editorWhiteSpace: getComputedStyle(editor).whiteSpace,
                blockWhiteSpace: getComputedStyle(secondBlock).whiteSpace,
                fontSize: getComputedStyle(second.parentElement).fontSize,
                horizontalDelta: secondRange.getBoundingClientRect().left - firstRange.getBoundingClientRect().left,
                blockGap: secondBlock.getBoundingClientRect().top - firstBlock.getBoundingClientRect().bottom
              };
            })()
            """
        ) as? [String: Any])

        #expect(result["editorWhiteSpace"] as? String == "normal")
        #expect(result["blockWhiteSpace"] as? String == "pre-wrap")
        #expect(result["fontSize"] as? String == "14px")
        #expect((result["horizontalDelta"] as? Double ?? 0) > 0)
        #expect((result["blockGap"] as? Double ?? .infinity) < 20)
    }

    @Test
    func indentsOrderedListContinuationParagraphsUntilBlankLine() async throws {
        let sourceHTML = """
        <ol><li><span style="font-size: 11px">大数据技术基础</span></li></ol>
        <div><span style="font-size: 11px">作业20%</span></div>
        <div><span style="font-size: 11px">实验20%</span></div>
        <div><span style="font-size: 11px"><br></span></div>
        <div><span style="font-size: 11px">作业1-240162401037</span></div>
        <ol><li><span style="font-size: 11px">算法设计与分析</span></li></ol>
        <div><span style="font-size: 11px">平时20%</span></div>
        """
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(
                html: sourceHTML,
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
        window.alphaValue = 0
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let webView = try await waitForWebView(in: hostingView)
        try await waitUntilEditorIsReady(in: webView)
        let result = try #require(await webView.evaluateJavaScript(
            """
            (() => {
              const editor = document.getElementById('editor');
              return {
                firstDetail: getComputedStyle(editor.children[1]).paddingLeft,
                secondDetail: getComputedStyle(editor.children[2]).paddingLeft,
                blankLine: getComputedStyle(editor.children[3]).paddingLeft,
                separatedHeading: getComputedStyle(editor.children[4]).paddingLeft,
                nextDetail: getComputedStyle(editor.children[6]).paddingLeft,
                html: editor.innerHTML
              };
            })()
            """
        ) as? [String: Any])

        #expect(result["firstDetail"] as? String == "16px")
        #expect(result["secondDetail"] as? String == "16px")
        #expect(result["blankLine"] as? String == "0px")
        #expect(result["separatedHeading"] as? String == "0px")
        #expect(result["nextDetail"] as? String == "16px")
        #expect(result["html"] as? String == sourceHTML)
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
        window.alphaValue = 0
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
