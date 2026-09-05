import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import ZislaCore
import ZislaKit

private final class TransparentWKWebView: WKWebView {
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc func undo(_ sender: Any?) {
        evaluateJavaScript("window.zisla?.exec('undo');", completionHandler: nil)
    }

    @objc func redo(_ sender: Any?) {
        evaluateJavaScript("window.zisla?.exec('redo');", completionHandler: nil)
    }
}

struct RichNoteEditorCommand: Identifiable, Equatable {
    enum Operation: Equatable {
        case bold
        case italic
        case underline
        case strikethrough
        case heading(Int)
        case paragraph
        case monospaced
        case quote
        case bulletList
        case numberedList
        case checklist
        case indent
        case outdent
        case clearFormatting
        case textColor(String)
        case createLink(String)
        case removeLink
        case insertImage(dataURL: String, alt: String)
        case insertTable(rows: Int, columns: Int)
        case addTableRow
        case removeTableRow
        case addTableColumn
        case removeTableColumn
        case removeTable
    }

    let id = UUID()
    let operation: Operation
}

struct RichNoteEditor: NSViewRepresentable {
    let html: String
    let command: RichNoteEditorCommand?
    let isEditable: Bool
    let onChange: (String, String) -> Void

    static var newNoteHTML: String { "<h1>\(AppLocalization.text("新随记"))</h1><div><br></div>" }

    static func editableHTML(for content: NotesAppBridge.NoteContent?) -> String {
        guard let content, !content.bodyHTML.isEmpty else { return "<div><br></div>" }
        return content.bodyHTML
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, isEditable: isEditable)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(context.coordinator, name: "richNoteChanged")

        let webView = TransparentWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        // WebKit exposes this transparency switch through KVC without advertising its selector.
        webView.setValue(false, forKey: "drawsBackground")

        context.coordinator.attach(webView)
        context.coordinator.setHTML(html)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.setHTML(html)
        context.coordinator.setEditable(isEditable)
        if let command {
            context.coordinator.perform(command)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "richNoteChanged")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let onChange: (String, String) -> Void
        private weak var webView: WKWebView?
        private var loadedHTML: String?
        private var isReady = false
        private var lastCommandID: UUID?
        private var isEditable: Bool

        init(onChange: @escaping (String, String) -> Void, isEditable: Bool) {
            self.onChange = onChange
            self.isEditable = isEditable
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
        }

        func setHTML(_ html: String) {
            guard loadedHTML != html else { return }
            loadedHTML = html
            guard let webView else { return }
            if isReady {
                webView.evaluateJavaScript("window.zisla.setHTML(\(RichNoteEditor.javaScriptLiteral(html)));") { _, error in
                    if let error {
                        print("Failed to set HTML: \(error)")
                    }
                }
            } else {
                webView.loadHTMLString(
                    RichNoteEditor.document(initialHTML: html, isEditable: isEditable),
                    baseURL: nil
                )
            }
        }

        func setEditable(_ isEditable: Bool) {
            guard self.isEditable != isEditable else { return }
            self.isEditable = isEditable
            guard isReady, let webView else { return }
            webView.evaluateJavaScript("window.zisla.setEditable(\(isEditable));") { _, error in
                if let error {
                    print("Failed to set editable: \(error)")
                }
            }
        }

        func perform(_ command: RichNoteEditorCommand) {
            guard isEditable else { return }
            guard lastCommandID != command.id else { return }
            lastCommandID = command.id
            guard isReady, let webView else { return }
            webView.evaluateJavaScript(javaScript(for: command.operation)) { _, error in
                if let error {
                    print("Failed to perform command: \(error)")
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            if let loadedHTML {
                webView.evaluateJavaScript("window.zisla.setHTML(\(RichNoteEditor.javaScriptLiteral(loadedHTML)));") { _, error in
                    if let error {
                        print("Failed to set initial HTML: \(error)")
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "richNoteChanged",
                  let payload = message.body as? [String: Any],
                  let html = payload["html"] as? String
            else { return }
            loadedHTML = html
            onChange(html, payload["plainText"] as? String ?? "")
        }

        private func javaScript(for operation: RichNoteEditorCommand.Operation) -> String {
            switch operation {
            case .bold: "window.zisla.exec('bold');"
            case .italic: "window.zisla.exec('italic');"
            case .underline: "window.zisla.exec('underline');"
            case .strikethrough: "window.zisla.exec('strikeThrough');"
            case .heading(let level): "window.zisla.block('h\(min(max(level, 1), 6))');"
            case .paragraph: "window.zisla.block('div');"
            case .monospaced: "window.zisla.block('pre');"
            case .quote: "window.zisla.block('blockquote');"
            case .bulletList: "window.zisla.exec('insertUnorderedList');"
            case .numberedList: "window.zisla.exec('insertOrderedList');"
            case .checklist: "window.zisla.checklist();"
            case .indent: "window.zisla.exec('indent');"
            case .outdent: "window.zisla.exec('outdent');"
            case .clearFormatting: "window.zisla.exec('removeFormat');"
            case .textColor(let color): "window.zisla.exec('foreColor', \(RichNoteEditor.javaScriptLiteral(color)));"
            case .createLink(let url): "window.zisla.link(\(RichNoteEditor.javaScriptLiteral(url)));"
            case .removeLink: "window.zisla.exec('unlink');"
            case let .insertImage(dataURL, alt):
                "window.zisla.image(\(RichNoteEditor.javaScriptLiteral(dataURL)), \(RichNoteEditor.javaScriptLiteral(alt)));"
            case let .insertTable(rows, columns): "window.zisla.table(\(rows), \(columns));"
            case .addTableRow: "window.zisla.tableAction('addRow');"
            case .removeTableRow: "window.zisla.tableAction('removeRow');"
            case .addTableColumn: "window.zisla.tableAction('addColumn');"
            case .removeTableColumn: "window.zisla.tableAction('removeColumn');"
            case .removeTable: "window.zisla.tableAction('removeTable');"
            }
        }
    }

    private static func javaScriptLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let result = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return result
    }

    private static func document(initialHTML: String, isEditable: Bool) -> String {
        let initial = javaScriptLiteral(initialHTML)
        let scriptNonce = UUID().uuidString
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(scriptNonce)'; style-src 'unsafe-inline'; img-src data: blob:; media-src data: blob:; font-src data:; connect-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'">
        <style>
          :root { color-scheme: dark; background: transparent !important; }
          html, body { margin: 0; min-height: 100%; background: transparent !important; }
          body {
            color: rgba(255,255,255,0.92);
            font: 14px -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
            line-height: 1.55;
          }
          #editor { box-sizing: border-box; min-height: 100vh; outline: none; padding: 4px 14px 20px; background: transparent !important; caret-color: transparent; }
          #editor > div, #editor > p, #editor li, #editor blockquote, #editor td, #editor th { white-space: pre-wrap; }
          #editor [style*="font-size: 11px"] { font-size: inherit !important; }
          #caret { background: rgba(255,255,255,0.92); border-radius: 0.5px; display: none; height: 14px; left: 0; pointer-events: none; position: fixed; top: 0; transform: translate3d(-9999px, -9999px, 0); width: 1px; z-index: 1; }
          #caret.is-visible { animation: caret-blink 1s steps(1, end) infinite; display: block; }
          @keyframes caret-blink { 50% { opacity: 0; } }
          @media (prefers-reduced-motion: reduce) { #caret.is-visible { animation: none; } }
          #editor > :first-child { margin-top: 0; }
          h1 { font-size: 23px; margin: 4px 0; }
          h1 + div, h1 + p { margin-top: 3px; }
          h2 { font-size: 19px; margin: 11px 0 6px; }
          h3 { font-size: 16px; margin: 10px 0 5px; }
          h4, h5, h6 { font-size: 14px; margin: 8px 0 4px; }
          div, p { margin: 5px 0; }
          a { color: #4aa3ff; text-decoration: none; }
          a:hover { text-decoration: underline; }
          code, pre { font-family: ui-monospace, "SF Mono", Menlo, monospace; }
          code { background: rgba(255,255,255,0.12); padding: 1px 4px; border-radius: 3px; }
          pre { background: rgba(255,255,255,0.08); border-radius: 6px; padding: 10px; white-space: pre-wrap; }
          blockquote { border-left: 3px solid rgba(255,255,255,0.3); color: rgba(255,255,255,0.65); margin: 7px 0; padding: 2px 0 2px 10px; }
          ul, ol { margin: 5px 0; padding-left: 24px; }
          ul.checklist { list-style: none; padding-left: 2px; }
          ul.checklist input { margin: 0 7px 0 0; vertical-align: middle; }
          table { border-collapse: collapse; margin: 8px 0; width: 100%; }
          th, td { border: 1px solid rgba(255,255,255,0.2); min-width: 72px; padding: 5px 8px; text-align: left; vertical-align: top; }
          th { background: rgba(255,255,255,0.1); font-weight: 600; }
          figure { margin: 8px 0; }
          img { border-radius: 6px; display: block; height: auto; margin: 5px 0; max-width: 100%; }
          hr { border: 0; border-top: 1px solid rgba(255,255,255,0.2); margin: 10px 0; }
          ::selection { background: rgba(74,163,255,0.42); }
        </style>
        </head>
        <body>
        <div id="editor" contenteditable="\(isEditable)" spellcheck="\(isEditable)" role="textbox" aria-multiline="true"></div>
        <script nonce="\(scriptNonce)">
        (() => {
          const l10n = {
            tableHeader: \(javaScriptLiteral(AppLocalization.text("标题"))),
            imageAlt: \(javaScriptLiteral(AppLocalization.text("图片"))),
          };
          const editor = document.getElementById('editor');
          const caret = document.createElement('div');
          caret.id = 'caret';
          caret.setAttribute('aria-hidden', 'true');
          document.body.append(caret);
          const continuationStyle = document.createElement('style');
          document.head.append(continuationStyle);
          let sendTimer;

          const escapeHTML = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
          const emit = () => window.webkit?.messageHandlers?.richNoteChanged?.postMessage({ html: editor.innerHTML, plainText: editor.innerText });
          const scheduleEmit = () => {
            updateListContinuationStyle();
            clearTimeout(sendTimer);
            sendTimer = setTimeout(emit, 80);
          };
          const hideCaret = () => caret.classList.remove('is-visible');
          const updateCaret = () => {
            const selection = window.getSelection();
            if (!editor.isContentEditable || !selection?.rangeCount || !selection.isCollapsed) return hideCaret();
            const range = selection.getRangeAt(0);
            if (range.startContainer === editor || !editor.contains(range.startContainer)) return hideCaret();
            let rect = [...range.getClientRects()].find(candidate => candidate.height > 0);
            if (!rect) {
              const boundingRect = range.getBoundingClientRect();
              const startElement = range.startContainer.nodeType === Node.ELEMENT_NODE ? range.startContainer : range.startContainer.parentElement;
              rect = boundingRect.height > 0 ? boundingRect : startElement?.getBoundingClientRect();
              if (!rect?.height) return hideCaret();
            }
            const height = Math.min(Math.max(rect.height * 0.72, 14), 20);
            caret.style.height = `${height}px`;
            caret.style.transform = `translate3d(${rect.left}px, ${rect.top + (rect.height - height) / 2 - 4}px, 0)`;
            caret.classList.add('is-visible');
          };
          const scheduleCaretUpdate = () => requestAnimationFrame(updateCaret);
          const isEmptyBlock = node => node?.matches?.('div, p') && !node.textContent.trim() && [...node.children].every(child => child.tagName === 'BR' || !child.textContent.trim());
          const sanitize = value => {
            const template = document.createElement('template');
            template.innerHTML = value || '';
            // Preserve passive Notes markup while removing elements that can execute or navigate outside the editor.
            template.content.querySelectorAll('script, base, iframe, frame, object, embed, form, meta, link').forEach(node => node.remove());
            template.content.querySelectorAll('*').forEach(node => {
              [...node.attributes].forEach(attribute => {
                const name = attribute.name.toLowerCase();
                const value = attribute.value.trim().toLowerCase();
                if (name.startsWith('on') || name === 'srcdoc' || ((name === 'href' || name === 'src') && value.startsWith('javascript:'))) {
                  node.removeAttribute(attribute.name);
                }
              });
            });
            while (isEmptyBlock(template.content.firstElementChild)) template.content.firstElementChild.remove();
            const title = template.content.querySelector('h1');
            while (isEmptyBlock(title?.nextElementSibling)) title.nextElementSibling.remove();
            return template.innerHTML;
          };
          const updateListContinuationStyle = () => {
            let followsOrderedList = false;
            const positions = [];
            [...editor.children].forEach((node, index) => {
              if (node.tagName === 'OL') {
                followsOrderedList = true;
                return;
              }
              if (!followsOrderedList) return;
              if (isEmptyBlock(node)) {
                followsOrderedList = false;
                return;
              }
              if (node.matches('div, p')) {
                positions.push(index + 1);
                return;
              }
              followsOrderedList = false;
            });
            continuationStyle.textContent = positions
              .map(position => `#editor > :nth-child(${position}) { padding-left: 16px; }`)
              .join('\\n');
          };
          const selectionCell = () => {
            const selection = window.getSelection();
            if (!selection?.rangeCount) return null;
            let node = selection.anchorNode;
            if (node?.nodeType === Node.TEXT_NODE) node = node.parentElement;
            return node?.closest?.('td, th') || null;
          };
          const insertHTML = html => {
            if (!editor.isContentEditable) return;
            editor.focus();
            document.execCommand('insertHTML', false, html);
            scheduleEmit();
          };
          const insertImage = (dataURL, alt) => insertHTML(`<figure><img src="${escapeHTML(dataURL)}" alt="${escapeHTML(alt)}"></figure><div><br></div>`);

          window.zisla = {
            setHTML: value => {
              editor.innerHTML = sanitize(value);
              if (!editor.innerHTML.trim()) editor.innerHTML = '<div><br></div>';
              updateListContinuationStyle();
              scheduleCaretUpdate();
            },
            setEditable: value => {
              editor.contentEditable = Boolean(value).toString();
              editor.spellcheck = Boolean(value);
              scheduleCaretUpdate();
            },
            exec: (command, value) => {
              if (!editor.isContentEditable) return;
              editor.focus();
              document.execCommand(command, false, value ?? null);
              scheduleEmit();
            },
            block: tag => {
              if (!editor.isContentEditable) return;
              editor.focus();
              document.execCommand('formatBlock', false, tag);
              scheduleEmit();
            },
            checklist: () => insertHTML('<ul class="checklist"><li><input type="checkbox"> <span>待办事项</span></li></ul><div><br></div>'),
            image: insertImage,
            link: value => {
              const url = String(value || '').trim();
              if (!url) return;
              editor.focus();
              const selection = window.getSelection();
              if (selection?.rangeCount && !selection.isCollapsed) {
                document.execCommand('createLink', false, url);
                scheduleEmit();
              } else {
                insertHTML(`<a href="${escapeHTML(url)}">${escapeHTML(url)}</a>`);
              }
            },
            table: (rows, columns) => {
              const rowCount = Math.min(Math.max(Number(rows) || 2, 1), 12);
              const columnCount = Math.min(Math.max(Number(columns) || 2, 1), 12);
              let html = '<table><tbody>';
              for (let row = 0; row < rowCount; row += 1) {
                html += '<tr>';
                for (let column = 0; column < columnCount; column += 1) {
                  html += row === 0 ? `<th>${l10n.tableHeader} ${column + 1}</th>` : `<td><br></td>`;
                }
                html += '</tr>';
              }
              insertHTML(`${html}</tbody></table><div><br></div>`);
            },
            tableAction: action => {
              if (!editor.isContentEditable) return;
              const cell = selectionCell();
              const row = cell?.parentElement;
              const table = row?.closest('table');
              if (!cell || !row || !table) return;
              const column = cell.cellIndex;
              if (action === 'addRow') {
                const newRow = table.insertRow(row.rowIndex + 1);
                for (let index = 0; index < row.cells.length; index += 1) newRow.insertCell().innerHTML = '<br>';
              } else if (action === 'removeRow') {
                table.deleteRow(row.rowIndex);
                if (!table.rows.length) table.remove();
              } else if (action === 'addColumn') {
                [...table.rows].forEach(currentRow => currentRow.insertCell(column + 1).innerHTML = '<br>');
              } else if (action === 'removeColumn') {
                [...table.rows].forEach(currentRow => {
                  if (currentRow.cells.length > column) currentRow.deleteCell(column);
                });
                if (![...table.rows].some(currentRow => currentRow.cells.length)) table.remove();
              } else if (action === 'removeTable') {
                table.remove();
              }
              scheduleEmit();
            }
          };

          editor.addEventListener('input', () => {
            if (editor.isContentEditable) {
              scheduleEmit();
              scheduleCaretUpdate();
            }
          });
          editor.addEventListener('change', () => {
            if (editor.isContentEditable) scheduleEmit();
          });
          editor.addEventListener('click', event => {
            if (event.target.closest('a')) event.preventDefault();
            if (event.target.matches('input[type="checkbox"]')) {
              if (editor.isContentEditable) scheduleEmit();
              else event.preventDefault();
            }
            scheduleCaretUpdate();
          });
          editor.addEventListener('focus', scheduleCaretUpdate);
          editor.addEventListener('blur', hideCaret);
          editor.addEventListener('keydown', scheduleCaretUpdate);
          document.addEventListener('selectionchange', scheduleCaretUpdate);
          window.addEventListener('resize', scheduleCaretUpdate);
          window.addEventListener('scroll', scheduleCaretUpdate, true);
          editor.addEventListener('paste', async event => {
            if (!editor.isContentEditable) return;
            const images = [...(event.clipboardData?.items || [])].filter(item => item.type.startsWith('image/'));
            if (!images.length) return;
            event.preventDefault();
            for (const item of images) {
              const file = item.getAsFile();
              if (!file) continue;
              const dataURL = await new Promise(resolve => {
                const reader = new FileReader();
                reader.onload = () => resolve(reader.result);
                reader.readAsDataURL(file);
              });
              insertImage(dataURL, file.name || l10n.imageAlt);
            }
          });
          editor.addEventListener('dragover', event => event.preventDefault());
          editor.addEventListener('drop', async event => {
            if (!editor.isContentEditable) return;
            const images = [...(event.dataTransfer?.files || [])].filter(file => file.type.startsWith('image/'));
            if (!images.length) return;
            event.preventDefault();
            for (const file of images) {
              const dataURL = await new Promise(resolve => {
                const reader = new FileReader();
                reader.onload = () => resolve(reader.result);
                reader.readAsDataURL(file);
              });
              insertImage(dataURL, file.name || l10n.imageAlt);
            }
          });
          window.zisla.setHTML(\(initial));
          window.zisla.setEditable(\(isEditable));
        })();
        </script>
        </body>
        </html>
        """
    }
}

struct RichNoteToolbar: View {
    @Binding var command: RichNoteEditorCommand?

    @State private var textColor = Color.primary
    @State private var isTextColorPickerPresented = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                formatMenu
                separator
                toolButton("bold", help: AppLocalization.text("粗体")) { send(.bold) }
                toolButton("italic", help: AppLocalization.text("斜体")) { send(.italic) }
                toolButton("underline", help: AppLocalization.text("下划线")) { send(.underline) }
                toolButton("strikethrough", help: AppLocalization.text("删除线")) { send(.strikethrough) }
                textColorButton
                separator
                listMenu
                toolButton("increase.indent", help: AppLocalization.text("增加缩进")) { send(.indent) }
                toolButton("decrease.indent", help: AppLocalization.text("减少缩进")) { send(.outdent) }
                separator
                toolButton("link", help: AppLocalization.text("添加链接"), action: promptForLink)
                toolButton("photo", help: AppLocalization.text("插入图片"), action: chooseImage)
                tableMenu
            }
            .padding(.horizontal, 1)
        }
    }

    private var formatMenu: some View {
        Menu {
            Button(AppLocalization.text("标题")) { send(.heading(1)) }
            Button(AppLocalization.text("小标题")) { send(.heading(2)) }
            Button(AppLocalization.text("小节标题")) { send(.heading(3)) }
            Button(AppLocalization.text("正文")) { send(.paragraph) }
            Button(AppLocalization.text("等宽")) { send(.monospaced) }
            Button(AppLocalization.text("引用")) { send(.quote) }
            Divider()
            Button(AppLocalization.text("清除格式")) { send(.clearFormatting) }
        } label: {
            Image(systemName: "textformat.size")
                .frame(width: 16, height: 16)
        }
        .menuStyle(.borderlessButton)
        .help(AppLocalization.text("文字样式"))
    }

    private var listMenu: some View {
        Menu {
            Button(AppLocalization.text("项目符号")) { send(.bulletList) }
            Button(AppLocalization.text("编号列表")) { send(.numberedList) }
            Button(AppLocalization.text("清单")) { send(.checklist) }
        } label: {
            Image(systemName: "list.bullet")
                .frame(width: 16, height: 16)
        }
        .menuStyle(.borderlessButton)
        .help(AppLocalization.text("列表"))
    }

    private var tableMenu: some View {
        Menu {
            Button(AppLocalization.text("插入 2 × 2 表格")) { send(.insertTable(rows: 2, columns: 2)) }
            Button(AppLocalization.text("插入 3 × 3 表格")) { send(.insertTable(rows: 3, columns: 3)) }
            Divider()
            Button(AppLocalization.text("在下方添加行")) { send(.addTableRow) }
            Button(AppLocalization.text("删除当前行")) { send(.removeTableRow) }
            Button(AppLocalization.text("在右侧添加列")) { send(.addTableColumn) }
            Button(AppLocalization.text("删除当前列")) { send(.removeTableColumn) }
            Divider()
            Button(AppLocalization.text("删除表格"), role: .destructive) { send(.removeTable) }
        } label: {
            Image(systemName: "tablecells")
                .frame(width: 16, height: 16)
        }
        .menuStyle(.borderlessButton)
        .help(AppLocalization.text("表格"))
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.dividerSubtle)
            .frame(width: 1, height: 16)
    }

    private var textColorButton: some View {
        Button {
            isTextColorPickerPresented.toggle()
        } label: {
            Image(systemName: "paintpalette")
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help(AppLocalization.text("文字颜色"))
        .popover(isPresented: $isTextColorPickerPresented, arrowEdge: .bottom) {
            ColorPicker("文字颜色", selection: $textColor, supportsOpacity: false)
                .labelsHidden()
                .padding(12)
                .onChange(of: textColor) { _, color in
                    send(.textColor(Self.hex(for: color)))
                }
        }
    }

    private func toolButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func send(_ operation: RichNoteEditorCommand.Operation) {
        command = RichNoteEditorCommand(operation: operation)
    }

    private func promptForLink() {
        let alert = NSAlert()
        alert.messageText = AppLocalization.text("添加链接")
        alert.informativeText = AppLocalization.text("选中文本后会将其设为链接。")
        alert.addButton(withTitle: AppLocalization.text("添加"))
        alert.addButton(withTitle: AppLocalization.text("取消"))

        let field = NSTextField(string: NSPasteboard.general.string(forType: .string) ?? "")
        field.placeholderString = "https://example.com"
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        WindowPlacement.prepareModal(alert.window)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if URL(string: value)?.scheme == nil {
            value = "https://\(value)"
        }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" || scheme == "mailto"
        else {
            showError(AppLocalization.text("链接地址无效"))
            return
        }
        send(.createLink(url.absoluteString))
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = AppLocalization.text("插入图片")
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        WindowPlacement.prepareModal(panel)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 12 * 1024 * 1024 else {
                showError(AppLocalization.text("图片不能超过 12 MB"))
                return
            }
            let type = UTType(filenameExtension: url.pathExtension) ?? .image
            let mimeType = type.preferredMIMEType ?? "image/png"
            let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
            send(.insertImage(dataURL: dataURL, alt: url.deletingPathExtension().lastPathComponent))
        } catch {
            showError(AppLocalization.text("无法读取图片：%@", error.localizedDescription))
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        WindowPlacement.prepareModal(alert.window)
        alert.runModal()
    }

    private static func hex(for color: Color) -> String {
        guard let components = NSColor(color).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(
            format: "#%02X%02X%02X",
            Int((components.redComponent * 255).rounded()),
            Int((components.greenComponent * 255).rounded()),
            Int((components.blueComponent * 255).rounded())
        )
    }
}

struct ReadOnlyNoteMetadata: View {
    let content: NotesAppBridge.NoteContent
    let showNote: () -> Void
    let showAttachment: (NotesAppBridge.NoteAttachment) -> Void
    let wordCount: Int
    var showsWordCount = true

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if content.isPasswordProtected {
                        IconButton(symbol: "lock.fill", help: AppLocalization.text("在备忘录中解锁"), size: .compact, action: showNote)
                        Text(AppLocalization.text("已锁定"))
                            .font(.islandMicro(weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(content.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.islandMicro(weight: .semibold))
                            .foregroundStyle(Color.zislaInfo)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.fillControl)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    ForEach(content.attachments) { attachment in
                        Button {
                            showAttachment(attachment)
                        } label: {
                            Label(attachment.displayName, systemImage: attachmentSymbol(for: attachment))
                                .font(.islandMicro(weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.fillControl)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(AppLocalization.text("在备忘录中打开"))
                    }
                }
                .padding(.horizontal, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsWordCount {
                Text(AppLocalization.text("%ld 字", wordCount))
                    .font(.islandMicro())
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func attachmentSymbol(for attachment: NotesAppBridge.NoteAttachment) -> String {
        switch (attachment.displayName as NSString).pathExtension.lowercased() {
        case "m4a", "mp3", "wav", "aac", "aiff", "caf": return "waveform"
        case "pdf": return "doc.viewfinder"
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo"
        case "mov", "mp4", "m4v": return "film"
        default: return "paperclip"
        }
    }
}

private extension NotesAppBridge.NoteAttachment {
    var displayName: String {
        if !name.isEmpty { return name }
        if let url = URL(string: url), !url.lastPathComponent.isEmpty { return url.lastPathComponent }
        return "附件"
    }
}

struct LockedNotePlaceholder: View {
    let showNote: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
            Text(AppLocalization.text("已锁定"))
                .font(.system(size: 12, weight: .semibold))
            IconButton(symbol: "arrow.up.right.square", help: AppLocalization.text("在备忘录中解锁"), action: showNote)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
