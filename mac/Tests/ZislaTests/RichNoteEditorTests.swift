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
        #expect(result["fontSize"] as? String == "14px")
        #expect((result["horizontalDelta"] as? Double ?? 0) > 0)
        #expect((result["blockGap"] as? Double ?? .infinity) < 20)
    }

    @Test
    func preservesHeadingAndBodyFontSizesBeforeSavingEditedHTML() async throws {
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
            (() => ({
              heading: getComputedStyle(document.querySelector('#editor > h1 span')).fontSize,
              body: getComputedStyle(document.querySelector('#editor > div span')).fontSize
            }))()
            """
        ) as? [String: Any])

        #expect(computedSizes["heading"] as? String == "23px")
        #expect(computedSizes["body"] as? String == "14px")
        #expect(savedHTML.contains("<h1><span>标题</span></h1>") == true)
        #expect(savedHTML.contains("font-size: 14px") == true)
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
        #expect(result["firstBody"] as? String == "14px")
        #expect(result["firstBodyInline"] as? String == "14px")
        #expect(result["secondBody"] as? String == "14px")
        #expect(result["secondBodyInline"] as? String == "14px")
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

        #expect(sizes == ["23px", "14px", "14px", "14px", "14px", "11px", "9px"])
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
        #expect(RichNoteEditor.newNoteHTML.contains("font-size: 14px"))
    }

    @Test
    func writesAnExplicitBodyFontSizeForUnstyledText() async throws {
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
                coloredBodySize: getComputedStyle(editor.children[2].firstElementChild).fontSize,
                coloredBodyInlineFontSize: editor.children[2].firstElementChild.style.fontSize,
                coloredBodyColor: editor.children[2].firstElementChild.style.color,
                html: editor.innerHTML
              };
            })()
            """
        ) as? [String: Any])

        #expect(result["headingSize"] as? String == "23px")
        #expect(result["firstBodySize"] as? String == "14px")
        #expect(result["firstBodyInlineFontSize"] as? String == "14px")
        #expect(result["coloredBodySize"] as? String == "14px")
        #expect(result["coloredBodyInlineFontSize"] as? String == "14px")
        #expect(result["coloredBodyColor"] as? String == "red")
        #expect(savedHTML.contains("<h1>标题</h1>") == true)
        #expect(savedHTML.contains("原正文变更") == true)
        #expect(savedHTML.contains("font-size: 14px") == true)
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
        #expect((result["html"] as? String)?.contains("font-size: 14px") == true)
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
