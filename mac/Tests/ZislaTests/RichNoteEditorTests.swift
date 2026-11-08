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
    func overflowingNoteKeepsThinScrollbarsWithoutWritingBackOnScroll() async throws {
        var changes = 0
        let hosting = NSHostingView(rootView: RichNoteEditor(
            html: "<div style='height: 1200px'><b>Fixture note</b></div>", command: nil,
            isEditable: true, onChange: { _, _ in changes += 1 }
        ))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        let webView = try await waitForWebView(in: hosting)
        try await waitUntilEditorIsReady(in: webView)
        let result = try #require(await webView.evaluateJavaScript("""
            (() => {
              const root = document.documentElement;
              const bar = getComputedStyle(root, '::-webkit-scrollbar');
              window.scrollTo(0, 150);
              return { width: bar.width, offset: window.scrollY,
                       text: document.querySelector('#editor b').textContent };
            })()
            """) as? [String: Any])
        #expect(result["width"] as? String == "3px")
        #expect(result["offset"] as? Double == 150)
        #expect(result["text"] as? String == "Fixture note")
        #expect(changes == 0, "Scrollbar styling and scrolling must not modify the Notes document")
        #expect(!window.isVisible)
    }

    @Test
    func inputMethodReportsIslandWindowLevelWithoutChangingPanelOrdering() async throws {
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(html: "<div><br></div>", command: nil, isEditable: true, onChange: { _, _ in })
                .frame(width: 320, height: 240)
        )
        let panel = IslandPanel(
            contentView: hostingView,
            frame: CGRect(x: 0, y: 0, width: 320, height: 240)
        )
        defer { panel.contentView = nil }
        let webView = try await waitForWebView(in: hostingView)
        let inputClient = try #require(webView as? NSTextInputClient)

        #expect(inputClient.windowLevel?() == NSWindow.Level.statusBar.rawValue)
        #expect(panel.level == .statusBar)
        #expect(!panel.isVisible)
        #expect(!panel.isKeyWindow)
    }

    @Test
    func inputMethodTracksExpandedEditorWindowLevel() async throws {
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(html: "<div>输入</div>", command: nil, isEditable: true, onChange: { _, _ in })
                .frame(width: 320, height: 240)
        )
        let window = QuickNotesEditorWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        defer { window.contentView = nil }
        let webView = try await waitForWebView(in: hostingView)
        try await waitUntilEditorIsReady(in: webView)
        _ = try await webView.evaluateJavaScript("document.getElementById('editor').focus()")
        #expect(window.makeFirstResponder(webView))
        for _ in 0..<100 {
            if webView.inputContext != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let inputClient = try #require(webView.inputContext?.client)
        #expect(inputClient as AnyObject === webView)

        for level: NSWindow.Level in [.normal, .floating, .popUpMenu] {
            window.level = level
            #expect(inputClient.windowLevel?() == level.rawValue)
            #expect(window.level == level)
        }
        #expect(!window.isVisible)
        #expect(!window.isKeyWindow)
    }

    @Test
    func inputMethodUsesNormalLevelAfterEditorDetachesFromWindow() async throws {
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(html: "<div><br></div>", command: nil, isEditable: true, onChange: { _, _ in })
                .frame(width: 320, height: 240)
        )
        let panel = IslandPanel(
            contentView: hostingView,
            frame: CGRect(x: 0, y: 0, width: 320, height: 240)
        )
        defer { panel.contentView = nil }
        let webView = try await waitForWebView(in: hostingView)
        let inputClient = try #require(webView as? NSTextInputClient)
        panel.contentView = nil

        #expect(webView.window == nil)
        #expect(inputClient.windowLevel?() == NSWindow.Level.normal.rawValue)
    }

    @Test(arguments: [true, false])
    func copyCommitsSelectionBeforeIslandHandoff(isEditable: Bool) async throws {
        let pasteboard = NSPasteboard(name: .init("dev.wzz.zisla.tests.rich-note.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.setString("previous clipboard", forType: .string))
        var copiedValues: [String?] = []
        var copiedWindow: NSWindow?
        try await withCopyEditor(
            html: "<div>copy me</div>",
            isEditable: isEditable,
            pasteboard: pasteboard,
            onCopy: {
                copiedValues.append(pasteboard.string(forType: .string))
                copiedWindow?.orderOut(nil)
            }
        ) { webView, changes in
            copiedWindow = webView.window
            let result = try await dispatchCopy(in: webView, selection: "range.selectNodeContents(editor); selection.addRange(range);")
            _ = try await waitForChange(in: changes) { _ in true }
            #expect(result["prevented"] as? Bool == true)
            #expect(result["timerCount"] as? Int == 0, "Copy must not wait for a WebKit timer")
            #expect(result["unchanged"] as? Bool == true)
            #expect(pasteboard.string(forType: .html)?.contains("copy me") == true)
        }

        #expect(copiedValues == ["copy me"], "Copied content must be available before the island starts collapsing")
    }

    @Test(arguments: [
        ("<div><b><i>left 复制😀 right</i></b></div>", "const text = editor.querySelector('i').firstChild; range.setStart(text, 5); range.setEnd(text, 9); selection.addRange(range);", "复制😀", "b i"),
        ("<div><a href='https://example.com' style='color: red'>link</a></div>", "range.selectNodeContents(editor.querySelector('a')); selection.addRange(range);", "link", "a[href='https://example.com'][style='color: red']"),
        ("<pre>第一行\n  second\tline 👩‍💻 &amp; &lt;x&gt;</pre>", "range.selectNodeContents(editor); selection.addRange(range);", "第一行\n  second\tline 👩‍💻 & <x>", "pre"),
        ("<figure><img src='data:image/png;base64,AAAA' alt='测试图片'></figure>", "range.selectNode(editor.querySelector('img')); selection.addRange(range);", "", "figure img[src='data:image/png;base64,AAAA']")
    ])
    func copyPreservesSelectedRichContent(html: String, selection: String, plainText: String, selector: String) async throws {
        let pasteboard = NSPasteboard(name: .init("dev.wzz.zisla.tests.rich-note.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var copyCount = 0
        try await withCopyEditor(html: html, pasteboard: pasteboard, onCopy: { copyCount += 1 }) { webView, changes in
            let result = try await dispatchCopy(in: webView, selection: selection)
            _ = try await waitForChange(in: changes) { _ in true }
            #expect(result["prevented"] as? Bool == true)
            #expect(result["unchanged"] as? Bool == true)
            #expect(pasteboard.string(forType: .string) == plainText)
            let copiedHTML = try #require(pasteboard.string(forType: .html))
            let arguments = String(decoding: try JSONSerialization.data(withJSONObject: [copiedHTML, selector]), as: UTF8.self)
            let formattedText = try await webView.evaluateJavaScript("""
                (() => {
                  const [html, selector] = \(arguments);
                  const template = document.createElement('template');
                  template.innerHTML = html;
                  return template.content.querySelector(selector)?.textContent ?? null;
                })();
                """)
            #expect(formattedText as? String == plainText)
            #expect(copyCount == 1)
        }
    }

    @Test(arguments: [
        "",
        "window.getSelection = () => null;",
        "range.selectNodeContents(editor); range.collapse(true); selection.addRange(range);",
        "range.selectNodeContents(document.head); selection.addRange(range);",
        "range.setStartBefore(editor); range.setEndAfter(editor); selection.addRange(range);"
    ])
    func copyWithoutAnEditorSelectionKeepsClipboard(selection: String) async throws {
        let pasteboard = NSPasteboard(name: .init("dev.wzz.zisla.tests.rich-note.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.setString("previous clipboard", forType: .string))
        let version = pasteboard.changeCount
        var copyCount = 0
        try await withCopyEditor(html: "<div>copy me</div>", pasteboard: pasteboard, onCopy: { copyCount += 1 }) { webView, changes in
            let result = try await dispatchCopy(in: webView, selection: selection)
            _ = try await waitForChange(in: changes) { _ in true }
            #expect(result["prevented"] as? Bool == false)
            #expect(result["errors"] as? [String] == [])
            #expect(copyCount == 0)
            #expect(pasteboard.changeCount == version)
            #expect(pasteboard.string(forType: .string) == "previous clipboard")
        }
    }

    @Test
    func copyRejectsInvalidMessagesWithoutClearingClipboard() async throws {
        let pasteboard = NSPasteboard(name: .init("dev.wzz.zisla.tests.rich-note.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.setString("previous clipboard", forType: .string))
        let version = pasteboard.changeCount
        var copyCount = 0
        try await withCopyEditor(html: "<div>copy me</div>", pasteboard: pasteboard, onCopy: { copyCount += 1 }) { webView, changes in
            _ = try await webView.evaluateJavaScript(
                """
                [null, {}, {plainText: 42, html: '<b>text</b>'}, {plainText: 'text'}, {plainText: '', html: ''}]
                  .forEach(payload => window.webkit.messageHandlers.richNoteCopied.postMessage(payload));
                """
            )
            _ = try await dispatchCopy(in: webView, selection: "")
            _ = try await waitForChange(in: changes) { _ in true }
            #expect(copyCount == 0)
            #expect(pasteboard.changeCount == version)
            #expect(pasteboard.string(forType: .string) == "previous clipboard")
        }
    }

    @Test
    func consecutiveCopiesKeepOnlyTheLatestSelection() async throws {
        let pasteboard = NSPasteboard(name: .init("dev.wzz.zisla.tests.rich-note.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var copiedValues: [String?] = []
        try await withCopyEditor(
            html: "<div id='first'>first</div><div id='second'>second</div>",
            pasteboard: pasteboard,
            onCopy: { copiedValues.append(pasteboard.string(forType: .string)) }
        ) { webView, changes in
            _ = try await dispatchCopy(in: webView, selection: """
                range.selectNodeContents(editor.querySelector('#first')); selection.addRange(range);
                editor.dispatchEvent(new ClipboardEvent('copy', { bubbles: true, cancelable: true }));
                selection.removeAllRanges();
                range.selectNodeContents(editor.querySelector('#second')); selection.addRange(range);
                """)
            _ = try await waitForChange(in: changes) { _ in true }
            #expect(copiedValues == ["first", "second"])
            #expect(pasteboard.string(forType: .string) == "second")
            #expect(pasteboard.pasteboardItems?.count == 1)
        }
    }

    @Test
    func failedClipboardWriteDoesNotStartIslandHandoff() async throws {
        let pasteboard = RejectingRichNotePasteboard()
        var copyCount = 0
        try await withCopyEditor(html: "<div>copy me</div>", pasteboard: pasteboard, onCopy: { copyCount += 1 }) { webView, changes in
            let result = try await dispatchCopy(in: webView, selection: "range.selectNodeContents(editor); selection.addRange(range);")
            _ = try await waitForChange(in: changes) { _ in true }
            #expect(result["unchanged"] as? Bool == true)
            #expect(copyCount == 0)
        }
    }

    @Test
    func copyPreservesUnicodeWhenPastedIntoNativeTextView() async throws {
        let pasteboard = NSPasteboard(name: .init("dev.wzz.zisla.tests.rich-note.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        try await withCopyEditor(html: "<div><b><i>复制 👩‍💻 text</i></b></div>", pasteboard: pasteboard, onCopy: {}) { webView, changes in
            _ = try await dispatchCopy(in: webView, selection: "range.selectNodeContents(editor); selection.addRange(range);")
            _ = try await waitForChange(in: changes) { _ in true }
            let target = NSTextView()
            target.isRichText = true
            try #require(target.readSelection(from: pasteboard))
            #expect(target.string.trimmingCharacters(in: .newlines) == "复制 👩‍💻 text")
            let font = try #require(target.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            let traits = NSFontManager.shared.traits(of: font)
            #expect(traits.contains(.boldFontMask))
            #expect(traits.contains(.italicFontMask))
        }
    }

    @Test
    func copyHandlesLongNotesWithoutDeferringTheWrite() async throws {
        let text = String(repeating: "随记 & <code> 👩‍💻\n", count: 10_000)
        let html = "<pre>\(text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;"))</pre>"
        let pasteboard = NSPasteboard(name: .init("dev.wzz.zisla.tests.rich-note.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var copiedText: String?
        try await withCopyEditor(
            html: html,
            pasteboard: pasteboard,
            onCopy: { copiedText = pasteboard.string(forType: .string) }
        ) { webView, changes in
            let result = try await dispatchCopy(in: webView, selection: "range.selectNodeContents(editor); selection.addRange(range);")
            _ = try await waitForChange(in: changes) { _ in true }
            #expect(result["timerCount"] as? Int == 0)
            #expect(copiedText == text)
        }
    }

    @Test
    func keepsSyncedBodyHTMLInsteadOfMigratingMarkdown() {
        let content = NotesAppBridge.NoteContent(
            plainText: "# 标题\n    缩进行",
            bodyHTML: "<pre># 标题\n    缩进行</pre>"
        )

        #expect(RichNoteEditor.editableHTML(for: content) == content.bodyHTML)
    }

    @Test
    func preservesImageOnlyNotesAndImagesImmediatelyAfterTheTitle() async throws {
        let image = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        for title in ["", "<h1>手写笔记</h1>"] {
            try await withCopyEditor(
                html: "\(title)<div><img src=\"\(image)\"></div><div><br></div>",
                pasteboard: RejectingRichNotePasteboard(),
                onCopy: {}
            ) { webView, changes in
                let sources = try #require(await webView.evaluateJavaScript(
                    "[...document.querySelectorAll('#editor img')].map(image => image.getAttribute('src'))"
                ) as? [String])
                #expect(sources == [image], "An image-only paragraph is content, not a disposable blank line")
                #expect(changes.changes.isEmpty, "Reading a handwriting preview must not save the note")
            }
        }
    }

    @Test
    func editsBothSidesOfNativeHandwritingWithoutSavingHTMLOrChangingTheDrawing() async throws {
        let image = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        let content = NotesAppBridge.NoteContent(plainText: "\u{FFFC}", bodyHTML: "<div><img src=\"\(image)\"></div>", requiresNativeTextEditing: true)
        var edits: [NotesNativeTextEdit] = []
        var htmlChanges = 0
        let hosting = NSHostingView(rootView: RichNoteEditor(html: content.bodyHTML, noteID: "native", command: nil,
            isEditable: true, nativeTextContent: content, onNativeTextChange: { id, edit in
                #expect(id == "native")
                edits.append(edit)
            }, onChange: { _, _, _ in htmlChanges += 1 }).frame(width: 320, height: 240))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        let webView = try await waitForWebView(in: hosting)
        try await waitUntilEditorIsReady(in: webView)
        #expect(edits.isEmpty)
        _ = try await webView.evaluateJavaScript("""
            (() => { window.webkit.messageHandlers.richNoteChanged.postMessage({
              html: '<div>invalid native payload</div>', token: window.zisla.documentToken()
            }); return true; })()
            """)
        let result = try #require(await webView.evaluateJavaScript("""
            (() => {
              const editor = document.getElementById('editor');
              const fields = editor.querySelectorAll('[data-zisla-native-text]');
              const drawing = editor.querySelector('[data-zisla-native-content]');
              const original = drawing.innerHTML;
              const select = field => {
                field.focus();
                const range = document.createRange(); range.selectNodeContents(field); range.collapse(false);
                const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
              };
              select(fields[0]); window.zisla.exec('insertText', '标题\\n');
              select(fields[1]); window.zisla.exec('insertText', '\\n结尾 👩‍💻');
              const range = document.createRange(); range.selectNode(drawing);
              const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
              window.zisla.exec('delete'); window.zisla.exec('bold'); window.zisla.block('h1');
              range.setStart(fields[0], 0); range.setEnd(fields[1], fields[1].childNodes.length);
              selection.removeAllRanges(); selection.addRange(range);
              const input = new InputEvent('beforeinput', { bubbles: true, cancelable: true, inputType: 'deleteContentBackward' });
              const cut = new ClipboardEvent('cut', { bubbles: true, cancelable: true });
              const drop = new DragEvent('drop', { bubbles: true, cancelable: true });
              fields[0].dispatchEvent(input); fields[0].dispatchEvent(cut); fields[0].dispatchEvent(drop);
              return { unchanged: drawing.innerHTML === original, readonly: !drawing.isContentEditable,
                       fields: [...fields].map(field => field.isContentEditable), source: drawing.querySelector('img').getAttribute('src'),
                       protectedInput: input.defaultPrevented && cut.defaultPrevented && drop.defaultPrevented };
            })()
            """) as? [String: Any])
        for _ in 0..<100 {
            if !edits.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let edit = try #require(edits.last)
        #expect(edit.prefix == "标题\n")
        #expect(edit.suffix == "\n结尾 👩‍💻")
        #expect(edit.imageSources == [image])
        #expect(edit.updatedPlainText == "标题\n\u{FFFC}\n结尾 👩‍💻")
        #expect(htmlChanges == 0, "Native handwriting must never enter the destructive HTML save path")
        #expect(result["unchanged"] as? Bool == true)
        #expect(result["readonly"] as? Bool == true)
        #expect(result["fields"] as? [Bool] == [true, true])
        #expect(result["source"] as? String == image)
        #expect(result["protectedInput"] as? Bool == true, "Selections across handwriting cannot be cut, replaced, or receive dropped content")
    }

    @Test
    func nativeHandwritingPasteUsesOnlyPlainTextAndKeepsThePreview() async throws {
        let content = NotesAppBridge.NoteContent(plainText: "前面\n\u{FFFC}\n后面", bodyHTML: "<div>前面</div><div><img src='data:image/png;base64,AAAA'></div><div>后面</div>", requiresNativeTextEditing: true)
        var edit: NotesNativeTextEdit?
        let hosting = NSHostingView(rootView: RichNoteEditor(html: content.bodyHTML, noteID: "native", command: nil,
            isEditable: true, nativeTextContent: content, onNativeTextChange: { _, value in edit = value },
            onChange: { _, _, _ in Issue.record("Native paste must not write HTML") }).frame(width: 320, height: 240))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        let webView = try await waitForWebView(in: hosting)
        try await waitUntilEditorIsReady(in: webView)
        let result = try #require(await webView.evaluateJavaScript("""
            (() => {
              const editor = document.getElementById('editor');
              const field = editor.querySelector('[data-zisla-native-text]');
              const fields = editor.querySelectorAll('[data-zisla-native-text]');
              field.focus();
              const range = document.createRange(); range.selectNodeContents(field); range.collapse(false);
              const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
              const data = new DataTransfer(); data.setData('text/plain', '<b>粘贴</b>'); data.setData('text/html', '<img src="https://example.com">');
              const event = new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: data });
              field.dispatchEvent(event);
              window.zisla.setEditable(false);
              const original = field.innerHTML;
              window.zisla.exec('insertText', '不应插入');
              return { prevented: event.defaultPrevented, imageCount: editor.querySelectorAll('img').length,
                       fields: [...fields].map(field => field.isContentEditable), readonly: original === field.innerHTML };
            })()
            """) as? [String: Any])
        for _ in 0..<100 {
            if edit != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try #require(edit).prefix == "前面\n<b>粘贴</b>")
        #expect(result["prevented"] as? Bool == true)
        #expect(result["imageCount"] as? Int == 1)
        #expect(result["fields"] as? [Bool] == [false, false])
        #expect(result["readonly"] as? Bool == true)
    }

    @Test(arguments: [false, true])
    func nativeTextKeepsBlankLinesUnicodeAndLiteralHTMLThroughEditingAndUndo(_ exportsLayoutNewline: Bool) async throws {
        let content = NotesAppBridge.NoteContent(plainText: "\u{FFFC}", bodyHTML: "<img src='data:image/png;base64,AAAA'>", requiresNativeTextEditing: true)
        var edits: [NotesNativeTextEdit] = []
        let hosting = NSHostingView(rootView: RichNoteEditor(html: content.bodyHTML, noteID: "native", command: nil,
            isEditable: true, nativeTextContent: content, onNativeTextChange: { _, edit in edits.append(edit) },
            onChange: { _, _, _ in Issue.record("Native text must not write HTML") }).frame(width: 320, height: 240))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        let webView = try await waitForWebView(in: hosting)
        try await waitUntilEditorIsReady(in: webView)
        for text in ["", "\n", "\n\n", "文字\n", "文字\n\n", "第一行\n\n第三行\n\n", "  <b>&👩‍💻 العربية\t"] {
            let config = String(decoding: try JSONSerialization.data(withJSONObject: ["prefix": text, "suffix": text, "protectedText": "\u{FFFC}"]), as: UTF8.self)
            let count = edits.count
            _ = try await webView.evaluateJavaScript("""
                (() => {
                  window.zisla.setHTML("<img src='data:image/png;base64,AAAA'>", window.zisla.documentToken(), \(config));
                  const fields = document.querySelectorAll('[data-zisla-native-text]');
                  if (\(exportsLayoutNewline)) {
                    const innerText = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'innerText').get;
                    for (const field of fields) {
                      // Older WebKit includes a block's layout newline even when its DOM text is unchanged.
                      Object.defineProperty(field, 'innerText', { get() {
                        const text = innerText.call(this);
                        return this.lastElementChild?.textContent ? text + '\\n' : text;
                      }});
                    }
                  }
                  const field = fields[1]; field.focus();
                  const range = document.createRange(); range.selectNodeContents(field); range.collapse(false);
                  const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
                  window.zisla.exec('insertText', '!');
                })()
                """)
            for _ in 0..<100 {
                if edits.count > count { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let edit = try #require(edits.last)
            #expect(edit.prefix == text, "Editing the suffix must preserve every prefix character: \(String(reflecting: text))")
            #expect(edit.suffix == text + "!", "Native text must round-trip literal text and blank lines")
        }
        let text = try #require(edits.last?.suffix)
        for (command, expected) in [("undo", String(text.dropLast())), ("redo", text)] {
            let count = edits.count
            _ = try await webView.evaluateJavaScript("window.zisla.exec('\(command)');")
            for _ in 0..<100 {
                if edits.count > count { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(try #require(edits.last).suffix == expected, "Undo and redo must save the exact native text")
        }
        let count = edits.count
        _ = try await webView.evaluateJavaScript("""
            document.execCommand('insertLineBreak', false, null);
            window.zisla.exec('insertText', '结尾');
            """)
        for _ in 0..<100 {
            if edits.count > count { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try #require(edits.last).suffix == text + "\n结尾", "A keyboard line break must preserve its text newline")
        for (html, expected) in [
            ("首行<br>次行<br><br>", "首行\n次行\n"),
            ("<div>首行</div>次行", "首行\n次行"),
            ("首行<div>次行</div>", "首行\n次行"),
            ("<div><span>首行<br></span>次行</div>", "首行\n次行"),
            ("<p>首行<br><br></p><p><span>次行 &amp; 👩‍💻</span></p>", "首行\n\n次行 & 👩‍💻"),
            ("<div>首行<div>次行</div>末行</div>", "首行\n次行\n末行"),
        ] {
            let markup = String(decoding: try JSONSerialization.data(withJSONObject: html, options: [.fragmentsAllowed]), as: UTF8.self)
            let count = edits.count
            _ = try await webView.evaluateJavaScript("""
                (() => {
                  const field = document.querySelectorAll('[data-zisla-native-text]')[1];
                  field.innerHTML = \(markup);
                  field.dispatchEvent(new Event('input', { bubbles: true }));
                })()
                """)
            for _ in 0..<100 {
                if edits.count > count { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(try #require(edits.last).suffix == expected, "Editable DOM line boundaries must preserve plain text: \(html)")
        }
    }

    @Test
    func delayedNativeEditsKeepTheirNoteIdentityWhenSwitchingDocuments() async throws {
        let first = NotesAppBridge.NoteContent(plainText: "前面\n\u{FFFC}\n后面", bodyHTML: "<img src='data:image/png;base64,AAAA'>", requiresNativeTextEditing: true)
        let second = NotesAppBridge.NoteContent(plainText: "第二条\u{FFFC}", bodyHTML: first.bodyHTML, requiresNativeTextEditing: true)
        var edits: [(String?, NotesNativeTextEdit)] = []
        let coordinator = RichNoteEditor.Coordinator(onChange: { _, _, _ in Issue.record("Native callbacks must not write HTML") },
            onNativeTextChange: { edits.append(($0, $1)) }, onCopy: nil,
            pasteboard: RejectingRichNotePasteboard(), isEditable: true)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(coordinator, name: "richNoteChanged")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 240), configuration: configuration)
        webView.navigationDelegate = coordinator
        coordinator.attach(webView)
        defer { configuration.userContentController.removeScriptMessageHandler(forName: "richNoteChanged") }
        coordinator.setDocument(noteID: "first", html: first.bodyHTML, nativeTextContent: first)
        try await waitUntilEditorIsReady(in: webView)
        _ = try await webView.evaluateJavaScript("""
            (() => {
              const field = document.querySelectorAll('[data-zisla-native-text]')[1]; field.focus();
              const range = document.createRange(); range.selectNodeContents(field); range.collapse(false);
              const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
              window.zisla.exec('insertText', '更新');
            })()
            """)
        coordinator.setDocument(noteID: "second", html: second.bodyHTML, nativeTextContent: second)
        for _ in 0..<100 {
            if !edits.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let edit = try #require(edits.first)
        #expect(edit.0 == "first")
        #expect(edit.1.originalPlainText == first.plainText)
        #expect(edit.1.suffix == "\n后面更新")
        #expect(try await editorText(in: webView).contains("第二条"))
        coordinator.setDocument(noteID: "first", html: first.bodyHTML, nativeTextContent: first)
        for _ in 0..<100 {
            if try await editorText(in: webView).contains("前面") { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try await editorText(in: webView).contains("前面"), "Notes with the same preview must still reload their own edge text")
    }

    @Test
    func restoresNotesAttachmentPlaceholderAsRenderableImage() throws {
        let content = NotesAppBridge.NoteContent(
            plainText: "正文\n￼\n结尾",
            bodyHTML: "<div><span style=\"font-size: 11px\">正文</span></div><div><span style=\"font-size: 11px\"><br></span></div><div><span style=\"font-size: 11px\">结尾</span></div>",
            attachments: [
                NotesAppBridge.NoteAttachment(
                    id: "attachment-1",
                    name: "截图.png",
                    contentIdentifier: "cid:attachment-1",
                    url: "",
                    dataURL: "data:image/png;base64,AAAA"
                )
            ]
        )

        let html = RichNoteEditor.editableHTML(for: content)

        #expect(html.contains(#"<div><span style="font-size: 11px">正文</span></div>"#))
        #expect(html.contains(#"<figure><img src="data:image/png;base64,AAAA" alt="截图.png"></figure>"#))
        #expect(html.contains(#"<div><span style="font-size: 11px">结尾</span></div>"#))
    }

    @Test
    func replacesNotesContentIdentifierImageWithInlineData() {
        let content = NotesAppBridge.NoteContent(
            plainText: "￼",
            bodyHTML: #"<div><img src="cid:attachment-1@icloud.apple.com" alt="图片"></div>"#,
            attachments: [
                NotesAppBridge.NoteAttachment(
                    id: "attachment-1",
                    name: "图片.png",
                    contentIdentifier: "cid:attachment-1@icloud.apple.com",
                    url: "",
                    dataURL: "data:image/png;base64,AAAA"
                )
            ]
        )

        let html = RichNoteEditor.editableHTML(for: content)

        #expect(html.contains(#"src="data:image/png;base64,AAAA"#))
        #expect(!html.contains("cid:attachment-1@icloud.apple.com"))
        #expect(html.components(separatedBy: "data:image/png;base64,AAAA").count == 2)
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
        #expect(result["fontSize"] as? String == "13px")
        #expect((result["horizontalDelta"] as? Double ?? 0) > 0)
        #expect((result["blockGap"] as? Double ?? .infinity) < 20)
    }

    @Test
    func rendersNativeNotesBodySizeWithoutChangingStoredFontSize() async throws {
        let sourceHTML = "<h1><span style=\"font-size: 11px\">标题</span></h1><div><span style=\"font-size: 11px; color: red\">正文</span></div>"
        let changeCapture = HTMLChangeCapture()
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(
                html: sourceHTML,
                command: nil,
                isEditable: true,
                onChange: { html, _ in changeCapture.html = html }
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
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const editor = document.getElementById('editor');
              const text = editor.querySelector('#editor > div span').firstChild;
              const range = document.createRange();
              range.setStart(text, text.textContent.length);
              range.collapse(true);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              window.zisla.exec('insertText', '变更');
            })();
            """
        )

        let savedHTML = try await waitForCapturedHTML(in: changeCapture)
        let computedSizes = try #require(await webView.evaluateJavaScript(
            """
            (() => {
              const body = document.querySelector('#editor > div span');
              return {
                heading: getComputedStyle(document.querySelector('#editor > h1 span')).fontSize,
                body: getComputedStyle(body).fontSize
              };
            })()
            """
        ) as? [String: Any])

        #expect(computedSizes["heading"] as? String == "23px")
        #expect(computedSizes["body"] as? String == "13px")
        #expect(savedHTML.contains("<h1><span>标题</span></h1>") == true)
        #expect(savedHTML.contains("font-size: 11px") == true)
        #expect(savedHTML.contains("font-size: 13px") == false)
        #expect(savedHTML.contains("color: red") == true)
        #expect(savedHTML.contains("正文变更") == true)
    }

    @Test
    func normalizesDefaultBodyFontBeforeAnyEdit() async throws {
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(
                html: "<h1><span style=\"font-size: 11px\">test</span></h1><div><span style=\"font-size: 11px\">11</span></div><div><span style=\"font-size:11px\">11</span></div>",
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
                heading: getComputedStyle(editor.children[0]).fontSize,
                firstBody: getComputedStyle(editor.children[1].firstElementChild).fontSize,
                firstBodyInline: editor.children[1].firstElementChild.style.fontSize,
                secondBody: getComputedStyle(editor.children[2].firstElementChild).fontSize,
                secondBodyInline: editor.children[2].firstElementChild.style.fontSize
              };
            })()
            """
        ) as? [String: Any])

        #expect(result["heading"] as? String == "23px")
        #expect(result["firstBody"] as? String == "13px")
        #expect(result["firstBodyInline"] as? String == "11px")
        #expect(result["secondBody"] as? String == "13px")
        #expect(result["secondBodyInline"] as? String == "11px")
    }

    @Test
    func normalizesNotesDefaultFontFromStylesheetsInheritanceAndFontTags() async throws {
        let sourceHTML = """
        <style>.notes-import .pt { font-size: 8.25pt !important; }.notes-import .inherited { font-size: 11px !important; }</style>
        <h1><span style="font-size: 11px">标题</span></h1>
        <div class="notes-import"><span class="pt">样式表</span></div>
        <div class="notes-import inherited"><span><b><i>继承</i></b></span></div>
        <div><font style="font-size: 8.25pt !important">字体标签</font></div>
        <div><span class="inline-important" style="font-size: 11px !important">内联优先级</span></div>
        <div><code><span style="font-size: 11px">代码</span></code></div>
        <div><span style="font-size: 9px">刻意小字</span></div>
        """
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(html: sourceHTML, command: nil, isEditable: true, onChange: { _, _ in })
                .frame(width: 320, height: 240)
        )
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let webView = try await waitForWebView(in: hostingView)
        try await waitUntilEditorIsReady(in: webView)
        let sizes = try #require(await webView.evaluateJavaScript(
            "(() => [...document.querySelectorAll('#editor h1, #editor .pt, #editor .inherited span, #editor font, #editor .inline-important, #editor code span, #editor div:last-child span')].map(node => getComputedStyle(node).fontSize))()"
        ) as? [String])

        #expect(sizes == ["23px", "13px", "13px", "11px", "11px", "11px", "9px"])
    }

    @Test
    func startsInitialNavigationForEmptyDocumentWithNoteID() async throws {
        let state = RichNoteEditorDocumentState(noteID: "empty", html: "")
        let hostingView = NSHostingView(rootView: RichNoteEditorDocumentHost(state: state).frame(width: 320, height: 240))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let webView = try await waitForWebView(in: hostingView)
        try await waitUntilEditorIsReady(in: webView)
        let token = try #require(await webView.evaluateJavaScript("window.zisla.documentToken()") as? Int)

        #expect(token == 1)
        #expect(try await editorText(in: webView).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func appliesLatestDocumentWhenItChangesDuringInitialNavigation() async throws {
        let state = RichNoteEditorDocumentState(noteID: "A", html: "<div>A</div>")
        let hostingView = NSHostingView(rootView: RichNoteEditorDocumentHost(state: state).frame(width: 320, height: 240))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let webView = try await waitForWebView(in: hostingView)
        state.noteID = "B"
        state.html = "<div>B</div>"
        try await waitUntilEditorIsReady(in: webView)
        try await waitForEditorText("B", in: webView)
    }

    @Test
    func retriesDocumentInjectionAfterTransientJavaScriptFailure() async throws {
        let state = RichNoteEditorDocumentState(noteID: "note", html: "<div>初始</div>")
        let hostingView = NSHostingView(rootView: RichNoteEditorDocumentHost(state: state).frame(width: 320, height: 240))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let webView = try await waitForWebView(in: hostingView)
        try await waitUntilEditorIsReady(in: webView)
        _ = try await webView.evaluateJavaScript(
            "(() => { const setHTML = window.zisla.setHTML; let shouldFail = true; window.zisla.setHTML = (...args) => { if (shouldFail) { shouldFail = false; throw new Error('transient'); } return setHTML(...args); }; })()"
        )
        state.html = "<div>重试成功</div>"

        try await waitForEditorText("重试成功", in: webView)
    }

    @Test
    func routesDelayedChangeToOriginalNoteAfterDocumentSwitch() async throws {
        let state = RichNoteEditorDocumentState(noteID: "A", html: "<div>A</div>")
        let capture = RichNoteEditorChangeCapture()
        let hostingView = NSHostingView(rootView:
            RichNoteEditorDocumentHost(state: state) { id, html, plainText in
                capture.changes.append((id, html, plainText))
            }
            .frame(width: 320, height: 240)
        )
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let webView = try await waitForWebView(in: hostingView)
        try await waitUntilEditorIsReady(in: webView)
        _ = try await webView.evaluateJavaScript(
            "(() => { const text = document.querySelector('#editor div').firstChild; const range = document.createRange(); range.selectNodeContents(text); range.collapse(false); const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range); window.zisla.exec('insertText', '变更'); })()"
        )
        state.noteID = "B"
        state.html = "<div>B</div>"

        try await waitForEditorText("B", in: webView)
        let change = try await waitForChange(in: capture) { $0.0 == "A" && $0.1.contains("A变更") }
        #expect(change.0 == "A")
        #expect(change.1.contains("A变更"))
        #expect(try await editorText(in: webView) == "B")
    }

    @Test
    func createsNewNoteWithExplicitBodyFontSize() {
        #expect(RichNoteEditor.newNoteHTML.contains("<h1>"))
        #expect(RichNoteEditor.newNoteHTML.contains("font-size: 11px"))
    }

    @Test
    func preservesUnstyledBodyTextWithoutPersistingEditorDisplaySize() async throws {
        let changeCapture = HTMLChangeCapture()
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(
                html: "<h1>标题</h1><div>原正文</div><div><span style=\"color: red\">彩色正文</span></div>",
                command: nil,
                isEditable: true,
                onChange: { html, _ in changeCapture.html = html }
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
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const text = document.querySelector('#editor > div').firstChild.firstChild;
              const range = document.createRange();
              range.setStart(text, text.textContent.length);
              range.collapse(true);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              window.zisla.exec('insertText', '变更');
            })();
            """
        )

        let savedHTML = try await waitForCapturedHTML(in: changeCapture)
        let result = try #require(await webView.evaluateJavaScript(
            """
            (() => {
              const editor = document.getElementById('editor');
              return {
                headingSize: getComputedStyle(editor.querySelector('h1')).fontSize,
                firstBodySize: getComputedStyle(editor.children[1].firstElementChild).fontSize,
                firstBodyInlineFontSize: editor.children[1].firstElementChild.style.fontSize,
                firstBodyUsesEditorDisplayMarker: editor.children[1].firstElementChild.hasAttribute('data-zisla-unstyled-body'),
                coloredBodySize: getComputedStyle(editor.children[2].firstElementChild).fontSize,
                coloredBodyInlineFontSize: editor.children[2].firstElementChild.style.fontSize,
                coloredBodyUsesEditorDisplayMarker: editor.children[2].firstElementChild.hasAttribute('data-zisla-unstyled-body'),
                coloredBodyColor: editor.children[2].firstElementChild.style.color,
                html: editor.innerHTML
              };
            })()
            """
        ) as? [String: Any])

        #expect(result["headingSize"] as? String == "23px")
        #expect(result["firstBodySize"] as? String == "13px")
        #expect(result["firstBodyInlineFontSize"] as? String == "")
        #expect(result["firstBodyUsesEditorDisplayMarker"] as? Bool == true)
        #expect(result["coloredBodySize"] as? String == "13px")
        #expect(result["coloredBodyInlineFontSize"] as? String == "")
        #expect(result["coloredBodyUsesEditorDisplayMarker"] as? Bool == true)
        #expect(result["coloredBodyColor"] as? String == "red")
        #expect(savedHTML.contains("<h1>标题</h1>") == true)
        #expect(savedHTML.contains("原正文变更") == true)
        #expect(savedHTML.contains("font-size") == false)
        #expect(savedHTML.contains("color: red") == true)
    }

    @Test
    func mapsNativeNotesHeadingsWithoutPromotingOrdinaryLargeBoldText() async throws {
        let changeCapture = HTMLChangeCapture()
        let sourceHTML = """
        <div><b><font face=".AppleSystemUIFontBold"><span style="font-size: 21px">一级标题</span></font></b></div>
        <div><b><font face=".AppleSystemUIFontBold"><span style="font-size: 19px">二级标题</span></font></b></div>
        <div><b><font face=".AppleSystemUIFontBold"><span style="font-size: 16px">三级标题</span></font></b></div>
        <div><b><span style="font-size: 21px">普通大号粗体</span></b></div>
        <div><font face=".AppleSystemUIFontBold"><span style="font-size: 16px">强调正文</span></font></div>
        <div>正文</div>
        """
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(
                html: sourceHTML,
                command: nil,
                isEditable: true,
                onChange: { html, _ in changeCapture.html = html }
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
        let display = try #require(await webView.evaluateJavaScript(
            """
            (() => {
              const editor = document.getElementById('editor');
              return {
                tags: [...editor.children].map(node => node.tagName),
                sizes: [...editor.children].slice(0, 4).map(node =>
                  node.matches('div') ? getComputedStyle(node.querySelector('span')).fontSize : getComputedStyle(node).fontSize
                )
              };
            })()
            """
        ) as? [String: Any])

        #expect(display["tags"] as? [String] == ["H1", "H2", "H3", "DIV", "DIV", "DIV"])
        #expect(display["sizes"] as? [String] == ["23px", "19px", "16px", "21px"])
        let emphasizedBody = try #require(await webView.evaluateJavaScript(
            "document.getElementById('editor').children[4].tagName + ':' + document.getElementById('editor').children[4].querySelector('span').style.fontSize"
        ) as? String)
        #expect(emphasizedBody == "DIV:16px")

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const text = document.getElementById('editor').lastElementChild.firstElementChild.firstChild;
              const range = document.createRange();
              range.setStart(text, text.textContent.length);
              range.collapse(true);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              window.zisla.exec('insertText', '变更');
            })();
            """
        )
        let savedHTML = try await waitForCapturedHTML(in: changeCapture)
        let emphasizedBodyAfterEmit = try #require(await webView.evaluateJavaScript(
            "document.getElementById('editor').children[4].tagName + ':' + document.getElementById('editor').children[4].querySelector('span').style.fontSize"
        ) as? String)
        #expect(emphasizedBodyAfterEmit == "DIV:16px")
        #expect(savedHTML.contains("强调正文") == true)
        #expect(savedHTML.contains("<h3>") == true)
        #expect(savedHTML.contains("font-size: 21px") == true)
        #expect(savedHTML.contains("正文变更") == true)
    }

    @Test
    func removesNotesTitleFontSizeWhenPromotingTextToHeading() async throws {
        let changeCapture = HTMLChangeCapture()
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(
                html: "<div><b><span style=\"font-size: 21px\">标题</span></b></div>",
                command: nil,
                isEditable: true,
                onChange: { html, _ in changeCapture.html = html }
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
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const text = document.querySelector('#editor > div span').firstChild;
              const range = document.createRange();
              range.selectNodeContents(text);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              window.zisla.exec('insertText', '标题');
            })();
            """
        )
        let bodyHTML = try await waitForCapturedHTML(in: changeCapture)
        #expect(bodyHTML.contains("font-size: 21px") == true)

        changeCapture.html = nil
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const text = document.querySelector('#editor > div span').firstChild;
              const range = document.createRange();
              range.selectNodeContents(text);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              document.activeElement?.blur();
              window.zisla.block('h1');
            })();
            """
        )

        let savedHTML = try await waitForCapturedHTML(in: changeCapture)
        let headingSize = try #require(await webView.evaluateJavaScript(
            "getComputedStyle(document.querySelector('#editor > h1 span')).fontSize"
        ) as? String)

        #expect(headingSize == "23px")
        #expect(savedHTML.contains("<h1>") == true)
        #expect(savedHTML.contains("font-size: 21px") == false)
    }

    @Test
    @MainActor
    func appliesHeadingCommandAfterEditorLosesFocus() async throws {
        let state = RichNoteEditorCommandState(
            html: "<div><b><span style=\"font-size: 21px\">标题</span></b></div>"
        )
        let hostingView = NSHostingView(rootView:
            RichNoteEditorCommandHost(state: state)
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
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const text = document.querySelector('#editor > div span').firstChild;
              const range = document.createRange();
              range.selectNodeContents(text);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              document.activeElement?.blur();
            })();
            """
        )

        state.command = RichNoteEditorCommand(operation: .heading(1))
        let savedHTML = try await waitForCommandHTML(in: state)

        #expect(savedHTML.contains("<h1>") == true)
        #expect(savedHTML.contains("font-size: 21px") == false)
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
        #expect((result["html"] as? String)?.contains("font-size: 11px") == true)
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
              const text = editor.firstChild.firstElementChild.firstChild;
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

    private func withCopyEditor(
        html: String,
        isEditable: Bool = true,
        pasteboard: any RichNotePasteboard,
        onCopy: @escaping () -> Void,
        body: (WKWebView, RichNoteEditorChangeCapture) async throws -> Void
    ) async throws {
        let changes = RichNoteEditorChangeCapture()
        let hostingView = NSHostingView(rootView:
            RichNoteEditor(
                html: html,
                command: nil,
                isEditable: isEditable,
                onCopy: onCopy,
                pasteboard: pasteboard,
                onChange: { changes.changes.append(($0, $1, $2)) }
            )
            .frame(width: 320, height: 240)
        )
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let webView = try await waitForWebView(in: hostingView)
        try await waitUntilEditorIsReady(in: webView)
        try await body(webView, changes)
    }

    private func dispatchCopy(in webView: WKWebView, selection selectionScript: String) async throws -> [String: Any] {
        try #require(await webView.evaluateJavaScript(
            """
            (() => {
              const editor = document.getElementById('editor');
              const originalHTML = editor.innerHTML;
              const range = document.createRange();
              const selection = window.getSelection();
              selection.removeAllRanges();
              \(selectionScript)
              const event = new ClipboardEvent('copy', { bubbles: true, cancelable: true });
              const schedule = window.setTimeout;
              let timerCount = 0;
              const errors = [];
              const onError = event => errors.push(event.message);
              window.addEventListener('error', onError);
              window.setTimeout = (...args) => { timerCount += 1; return schedule(...args); };
              try { editor.dispatchEvent(event); } finally {
                window.setTimeout = schedule;
                window.removeEventListener('error', onError);
              }
              // This message is a barrier for preceding native copy messages, without a timing assumption.
              window.webkit.messageHandlers.richNoteChanged.postMessage({
                html: editor.innerHTML, plainText: editor.innerText, token: window.zisla.documentToken()
              });
              return { prevented: event.defaultPrevented, timerCount, errors, unchanged: editor.innerHTML === originalHTML };
            })();
            """
        ) as? [String: Any])
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

    private func waitForEditorText(_ expected: String, in webView: WKWebView) async throws {
        for _ in 0..<100 {
            if try await editorText(in: webView) == expected { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw RichNoteEditorTestError.editorTextNotApplied
    }

    private func waitForChange(
        in capture: RichNoteEditorChangeCapture,
        matching predicate: ((String?, String, String)) -> Bool
    ) async throws -> (String?, String, String) {
        for _ in 0..<100 {
            if let change = capture.changes.first(where: predicate) { return change }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw RichNoteEditorTestError.changeNotCaptured
    }

    private func waitForCapturedHTML(in capture: HTMLChangeCapture) async throws -> String {
        for _ in 0..<100 {
            if let html = capture.html { return html }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw RichNoteEditorTestError.changeNotCaptured
    }

    private func waitForCommandHTML(in state: RichNoteEditorCommandState) async throws -> String {
        for _ in 0..<100 {
            if state.html.contains("<h1>") { return state.html }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw RichNoteEditorTestError.changeNotCaptured
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
    case editorTextNotApplied
    case keyEventNotCreated
    case changeNotCaptured
}

private final class HTMLChangeCapture {
    var html: String?
}

private final class RichNoteEditorChangeCapture {
    var changes: [(String?, String, String)] = []
}

private final class RejectingRichNotePasteboard: RichNotePasteboard {
    func clearContents() -> Int { 0 }
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool { false }
}

@MainActor
private final class RichNoteEditorDocumentState: ObservableObject {
    @Published var noteID: String?
    @Published var html: String

    init(noteID: String?, html: String) {
        self.noteID = noteID
        self.html = html
    }
}

private struct RichNoteEditorDocumentHost: View {
    @ObservedObject var state: RichNoteEditorDocumentState
    let onChange: (String?, String, String) -> Void

    init(
        state: RichNoteEditorDocumentState,
        onChange: @escaping (String?, String, String) -> Void = { _, _, _ in }
    ) {
        self.state = state
        self.onChange = onChange
    }

    var body: some View {
        RichNoteEditor(
            html: state.html,
            noteID: state.noteID,
            command: nil,
            isEditable: true,
            onChange: onChange
        )
    }
}

@MainActor
private final class RichNoteEditorCommandState: ObservableObject {
    @Published var html: String
    @Published var command: RichNoteEditorCommand?

    init(html: String) {
        self.html = html
    }
}

private struct RichNoteEditorCommandHost: View {
    @ObservedObject var state: RichNoteEditorCommandState

    var body: some View {
        RichNoteEditor(
            html: state.html,
            command: state.command,
            isEditable: true
        ) { html, _ in
            state.html = html
        }
    }
}
