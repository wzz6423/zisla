import Foundation

/// 把 Markdown 源文本渲染为带样式的 HTML 字符串，供 `WKWebView`（`MarkdownWebView`）
/// 显示。相比 `MarkdownRenderer` 的 `AttributedString`，HTML 能真正渲染**图片**与
/// **GFM 管道表格**，并保留代码块、引用、列表等富文本结构——满足随记「展示图片、
/// 表格等各种内容」的需求。
///
/// 仅依赖 Foundation（无 SwiftUI），因此可在只装 Command Line Tools 的环境下编译。
public enum MarkdownHTMLRenderer {
    /// 渲染入口：返回完整 HTML 文档（含 `<style>`）。空输入给出占位提示。
    public static func html(from source: String) -> String {
        let blocks = MarkdownParser.parse(source)
        let body = blocks.isEmpty
            ? "<p class=\"empty\">（空笔记）</p>"
            : blocks.map(renderBlock).joined(separator: "\n")
        // 最后一步：把 `<img src="本地路径">` 改写为 base64 data URL，
        // 绕开 WKWebView `loadHTMLString` 不授予 file:// 读取权限的限制。
        return MarkdownImageInliner.inlineLocalImages(in: document(wrapping: body))
    }

    /// 保留备忘录 `body` 的原生结构，并复用 Markdown 预览的深色样式与本地图片内联能力。
    public static func html(fromNotesHTML body: String) -> String {
        MarkdownImageInliner.inlineLocalImages(in: document(wrapping: body))
    }

    // MARK: - 块渲染

    private static func renderBlock(_ block: MarkdownBlock) -> String {
        switch block {
        case let .heading(level, text):
            let clamped = min(max(level, 1), 6)
            return "<h\(clamped)>\(inline(text))</h\(clamped)>"
        case let .paragraph(text):
            return "<p>\(inline(text))</p>"
        case let .bulletList(items):
            return "<ul>" + items.map { "<li>\(inline($0))</li>" }.joined() + "</ul>"
        case let .orderedList(items):
            return "<ol>" + items.map { "<li>\(inline($0))</li>" }.joined() + "</ol>"
        case let .blockquote(text):
            return "<blockquote>\(inline(text))</blockquote>"
        case let .codeBlock(_, content):
            return "<pre><code>\(escapeHTML(content))</code></pre>"
        case .horizontalRule:
            return "<hr>"
        case let .image(url, alt):
            return "<figure><img src=\"\(attributeEscape(url))\" alt=\"\(attributeEscape(alt))\"></figure>"
        case let .table(header, rows):
            let head = "<thead><tr>" + header.map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead>"
            let bodyRows = rows.map { row in
                "<tr>" + row.map { "<td>\(inline($0))</td>" }.joined() + "</tr>"
            }.joined()
            return "<table>\(head)<tbody>\(bodyRows)</tbody></table>"
        }
    }

    // MARK: - 行内格式

    /// 行内格式：在已转义的文本上依次处理行内代码、图片、链接、粗体、斜体、删除线。
    /// 先抽出行内代码占位，避免其中的 `*`/`_` 被后续规则误处理。
    private static func inline(_ text: String) -> String {
        var result = escapeHTML(text)

        // 1. 行内代码 `code` → 占位（保护内部内容）
        var codeStore: [String] = []
        result = replace(result, pattern: "`([^`]+)`") { match, _ in
            let code = escapeHTML(match[1])
            let token = "%%CODE\(codeStore.count)%%"
            codeStore.append("<code>\(code)</code>")
            return token
        }

        // 2. 图片 ![alt](url)
        result = replace(result, pattern: "!\\[([^\\[]*)\\]\\(([^\\)]+)\\)") { match, _ in
            let alt = match[1]
            let url = match[2].trimmingCharacters(in: .whitespaces)
            return "<img src=\"\(attributeEscape(url))\" alt=\"\(attributeEscape(alt))\">"
        }

        // 3. 链接 [text](url)
        result = replace(result, pattern: "\\[([^\\[]+)\\]\\(([^\\)]+)\\)") { match, _ in
            let title = match[1]
            let url = match[2].trimmingCharacters(in: .whitespaces)
            return "<a href=\"\(attributeEscape(url))\">\(title)</a>"
        }

        // 4. 粗体 **x** / __x__
        result = replace(result, pattern: "\\*\\*([^*]+)\\*\\*") { match, _ in "<strong>\(match[1])</strong>" }
        result = replace(result, pattern: "__([^_]+)__") { match, _ in "<strong>\(match[1])</strong>" }

        // 5. 斜体 *x* / _x_
        result = replace(result, pattern: "\\*([^*]+)\\*") { match, _ in "<em>\(match[1])</em>" }
        result = replace(result, pattern: "_([^_]+)_") { match, _ in "<em>\(match[1])</em>" }

        // 6. 删除线 ~~x~~
        result = replace(result, pattern: "~~([^~]+)~~") { match, _ in "<del>\(match[1])</del>" }

        // 还原行内代码
        for (index, code) in codeStore.enumerated().reversed() {
            result = result.replacingOccurrences(of: "%%CODE\(index)%%", with: code)
        }
        return result
    }

    // MARK: - 工具

    /// 转义 HTML 文本节点中的 `&` `<` `>`。
    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// 转义 HTML 属性值中的 `"` `&` `<`。先归一化已存在的 `&amp;`，保证对
    /// 经过 `escapeHTML` 预转义的文本幂等（避免 `&` → `&amp;amp;`）。
    private static func attributeEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// 正则替换（从后往前，保证原始 `NSRange` 始终有效）。
    /// `handler` 接收 `groups` 数组与整段匹配，`groups[0]` 为整段，`groups[1]` 起为捕获组。
    private static func replace(
        _ string: String,
        pattern: String,
        _ handler: ([String], String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let ns = string as NSString
        let matches = regex.matches(in: string, range: NSRange(string.startIndex..., in: string))
        var result = string
        for match in matches.reversed() {
            let whole = ns.substring(with: match.range)
            var groups: [String] = [whole]
            for i in 1..<match.numberOfRanges {
                let range = match.range(at: i)
                groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
            }
            let replacement = handler(groups, whole)
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    // MARK: - 文档外壳

    private static func document(wrapping body: String) -> String {
        let style = """
        <style>
          :root { color-scheme: dark; }
          body {
            background: transparent;
            color: rgba(255,255,255,0.92);
            font: 13px -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
            line-height: 1.55;
            margin: 0;
            padding: 12px;
          }
          h1 { font-size: 20px; margin: 10px 0 6px; }
          h2 { font-size: 17px; margin: 9px 0 5px; }
          h3 { font-size: 15px; margin: 8px 0 4px; }
          h4, h5, h6 { font-size: 13px; margin: 7px 0 4px; }
          p { margin: 5px 0; }
          a { color: #4aa3ff; text-decoration: none; }
          a:hover { text-decoration: underline; }
          code {
            background: rgba(255,255,255,0.12);
            padding: 1px 4px;
            border-radius: 4px;
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 12px;
          }
          pre {
            background: rgba(255,255,255,0.08);
            padding: 10px;
            border-radius: 8px;
            overflow: auto;
          }
          pre code { background: none; padding: 0; }
          blockquote {
            border-left: 3px solid rgba(255,255,255,0.3);
            margin: 6px 0;
            padding: 2px 0 2px 10px;
            color: rgba(255,255,255,0.6);
          }
          table {
            border-collapse: collapse;
            width: 100%;
            margin: 6px 0;
            font-size: 12px;
          }
          th, td {
            border: 1px solid rgba(255,255,255,0.18);
            padding: 5px 8px;
            text-align: left;
            vertical-align: top;
          }
          th { background: rgba(255,255,255,0.1); font-weight: 600; }
          img {
            max-width: 100%;
            border-radius: 8px;
            margin: 4px 0;
          }
          figure { margin: 6px 0; }
          hr { border: none; border-top: 1px solid rgba(255,255,255,0.15); margin: 8px 0; }
          ul, ol { padding-left: 20px; margin: 5px 0; }
          .empty { color: rgba(255,255,255,0.4); font-style: italic; }
        </style>
        """
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(style)
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}
