import Foundation

/// Renders Markdown source text to a styled HTML string for display in a `WKWebView` (`MarkdownWebView`).
/// Unlike `MarkdownRenderer`'s `AttributedString`, HTML correctly renders **images** and
/// **GFM pipe tables**, and preserves rich-text structures such as code blocks, blockquotes,
/// and lists — meeting the Quick Notes requirement to display images, tables, and other content.
///
/// Depends only on Foundation (no SwiftUI), so it can compile in a Command Line Tools–only environment.
public enum MarkdownHTMLRenderer {
    /// Rendering entry point: returns a complete HTML document (including `<style>`). Empty input produces a placeholder.
    public static func html(from source: String) -> String {
        let body = bodyHTML(from: source)
        // Final step: rewrite `<img src="local-path">` to base64 data URLs,
        // working around WKWebView's `loadHTMLString` not granting file:// read access.
        return MarkdownImageInliner.inlineLocalImages(in: document(wrapping: body))
    }

    /// Migrates a historical Markdown note to an editable HTML fragment for the rich-text editor's initial load.
    public static func bodyHTML(from source: String) -> String {
        let blocks = MarkdownParser.parse(source)
        return blocks.isEmpty
            ? "<div><br></div>"
            : blocks.map(renderBlock).joined(separator: "\n")
    }

    /// Preserves the native structure of a Notes `body`, reusing the Markdown preview's dark style and local image inlining.
    public static func html(fromNotesHTML body: String) -> String {
        MarkdownImageInliner.inlineLocalImages(in: document(wrapping: body))
    }

    // MARK: - Block rendering

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

    // MARK: - Inline formatting

    /// Inline formatting: processes inline code, images, links, bold, italic, and strikethrough
    /// on already-escaped text, in order. Extracts inline code placeholders first to prevent
    /// `*`/`_` inside them from being mishandled by later rules.
    private static func inline(_ text: String) -> String {
        var result = escapeHTML(text)

        // 1. Inline code `code` → placeholder (protects inner content)
        var codeStore: [(token: String, html: String)] = []
        result = replace(result, pattern: "`([^`]+)`") { match, _ in
            let token = "%%ZISLACODE\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))%%"
            codeStore.append((token, "<code>\(match[1])</code>"))
            return token
        }

        // 2. Image ![alt](url)
        result = replace(result, pattern: "!\\[([^\\[]*)\\]\\(([^\\)]+)\\)") { match, _ in
            let alt = match[1]
            let url = match[2].trimmingCharacters(in: .whitespaces)
            return "<img src=\"\(attributeEscape(url))\" alt=\"\(attributeEscape(alt))\">"
        }

        // 3. Link [text](url)
        result = replace(result, pattern: "\\[([^\\[]+)\\]\\(([^\\)]+)\\)") { match, _ in
            let title = match[1]
            let url = match[2].trimmingCharacters(in: .whitespaces)
            return "<a href=\"\(attributeEscape(url))\">\(title)</a>"
        }

        // 4. Bold **x** / __x__
        result = replace(result, pattern: "\\*\\*([^*]+)\\*\\*") { match, _ in "<strong>\(match[1])</strong>" }
        result = replace(result, pattern: "__([^_]+)__") { match, _ in "<strong>\(match[1])</strong>" }

        // 5. Italic *x* / _x_
        result = replace(result, pattern: "\\*([^*]+)\\*") { match, _ in "<em>\(match[1])</em>" }
        result = replace(result, pattern: "_([^_]+)_") { match, _ in "<em>\(match[1])</em>" }

        // 6. Strikethrough ~~x~~
        result = replace(result, pattern: "~~([^~]+)~~") { match, _ in "<del>\(match[1])</del>" }

        // Restore inline code placeholders
        for code in codeStore.reversed() {
            result = result.replacingOccurrences(of: code.token, with: code.html)
        }
        return result
    }

    // MARK: - Utilities

    /// Escapes `&` `<` `>` in HTML text nodes.
    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Escapes `"` `&` `<` in HTML attribute values. First normalizes existing `&amp;` to ensure
    /// idempotence on text that was already processed by `escapeHTML` (avoids `&` → `&amp;amp;`).
    private static func attributeEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Regex replacement (reversed iteration keeps original `NSRange` values valid).
    /// `handler` receives a `groups` array and the full match; `groups[0]` is the full match, `groups[1]` onward are capture groups.
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

    // MARK: - Document shell

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
