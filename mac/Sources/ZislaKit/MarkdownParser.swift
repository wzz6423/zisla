import Foundation

/// Parsed Markdown block-level result. Covers only the subset commonly used in note-taking scenarios; intentionally avoids third-party dependencies.
///
/// The parser scans line by line and recognises: headings, unordered/ordered lists, blockquotes, fenced code blocks, horizontal rules,
/// paragraphs, **standalone image lines**, and **GFM pipe tables**. Inline formatting (bold, italic, inline code, links,
/// strikethrough, inline images) is handled by `MarkdownHTMLRenderer` / `MarkdownRenderer`; the block parser does not touch them.
public enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletList(items: [String])
    case orderedList(items: [String])
    case blockquote(text: String)
    case codeBlock(language: String?, content: String)
    case horizontalRule
    /// Single standalone image line: `![alt](url)`.
    case image(url: String, alt: String)
    /// GFM pipe table: first row is the header, followed by the delimiter row, then data rows.
    case table(header: [String], rows: [[String]])
}

public enum MarkdownParser {
    /// Parses Markdown source text into a sequence of blocks. Returns an empty array for empty input.
    public static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            // Skip blank lines (block boundaries).
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                index += 1
                continue
            }

            // Fenced code block: ```lang
            if let fence = fenceInfo(line) {
                let (content, next) = collectCodeBlock(lines: lines, from: index + 1, fence: fence.marker)
                blocks.append(.codeBlock(language: fence.language, content: content))
                index = next
                continue
            }

            // Horizontal rule: --- / *** / ___ (at least three identical characters).
            if isHorizontalRule(line) {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            // Heading: # .. ######
            if let heading = headingInfo(line) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            // Standalone image line: ![alt](url)
            if let image = imageInfo(line) {
                blocks.append(.image(url: image.url, alt: image.alt))
                index += 1
                continue
            }

            // GFM pipe table: current line is the header, next line is the delimiter row.
            if let table = collectTableIfPresent(lines: lines, from: index) {
                blocks.append(.table(header: table.header, rows: table.rows))
                index = table.next
                continue
            }

            // Blockquote: >
            if line.hasPrefix(">") {
                let (text, next) = collectBlockquote(lines: lines, from: index)
                blocks.append(.blockquote(text: text))
                index = next
                continue
            }

            // Unordered list: - / * / +
            if isBulletItem(line) {
                let (items, next) = collectList(
                    lines: lines,
                    from: index,
                    ordered: false
                )
                blocks.append(.bulletList(items: items))
                index = next
                continue
            }

            // Ordered list: 1. / 2)
            if let _ = orderedItemPrefix(line) {
                let (items, next) = collectList(
                    lines: lines,
                    from: index,
                    ordered: true
                )
                blocks.append(.orderedList(items: items))
                index = next
                continue
            }

            // Paragraph: consecutive non-empty lines until a block boundary.
            let (text, next) = collectParagraph(lines: lines, from: index)
            blocks.append(.paragraph(text: text))
            index = next
        }

        return blocks
    }

    // MARK: - Block collection

    private static func collectParagraph(lines: [String], from start: Int) -> (String, Int) {
        var collected: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            // Stop when the start of the next block is encountered.
            if isBlockStart(line) { break }
            // isBlockStart 只认得出分隔行；表头要结合下一行判断，否则紧跟段落（无空行）的表格
            // 会被吞掉表头、表体退化成裸管道文本。首行交给主循环的表格分支处理。
            if index > start, line.contains("|"),
               index + 1 < lines.count, isTableDelimiter(lines[index + 1]) {
                break
            }
            collected.append(trimmed)
            index += 1
        }
        return (collected.joined(separator: " "), index)
    }

    private static func collectList(
        lines: [String],
        from start: Int,
        ordered: Bool
    ) -> ([String], Int) {
        var items: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            if ordered {
                guard let (marker, rest) = orderedItemPrefix(line) else { break }
                items.append(normalizeListItemText(rest, marker: marker))
            } else {
                guard let (marker, rest) = bulletItemPrefix(line) else { break }
                items.append(normalizeListItemText(rest, marker: marker))
            }
            index += 1
        }
        return (items, index)
    }

    private static func collectBlockquote(lines: [String], from start: Int) -> (String, Int) {
        var collected: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index]
            guard line.hasPrefix(">") else { break }
            var content = String(line.dropFirst())
            if content.hasPrefix(" ") { content.removeFirst() }
            collected.append(content.trimmingCharacters(in: .whitespaces))
            index += 1
        }
        return (collected.joined(separator: " "), index)
    }

    private static func collectCodeBlock(
        lines: [String],
        from start: Int,
        fence: String
    ) -> (String, Int) {
        var collected: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces) == fence {
                return (collected.joined(separator: "\n"), index + 1)
            }
            collected.append(line)
            index += 1
        }
        // Unclosed code block: consume to end of input.
        return (collected.joined(separator: "\n"), index)
    }

    // MARK: - Line-start detection

    /// Returns true if the line is the start of a block-level structure (used to detect paragraph boundaries).
    private static func isBlockStart(_ line: String) -> Bool {
        fenceInfo(line) != nil
            || isHorizontalRule(line)
            || headingInfo(line) != nil
            || imageInfo(line) != nil
            || isTableDelimiter(line)
            || line.hasPrefix(">")
            || isBulletItem(line)
            || orderedItemPrefix(line) != nil
    }

    // MARK: - Image

    /// Parses a standalone image line `![alt](url "optional title")`. Returns `nil` if the line is not a standalone image.
    private static func imageInfo(_ line: String) -> (url: String, alt: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("!"),
              let open = trimmed.firstIndex(of: "["),
              let close = trimmed.firstIndex(of: "]"),
              open < close
        else { return nil }
        // `]` 位于行尾时 index(after:) 即 endIndex，直接下标访问会越界崩溃（如 `![截图]`）。
        let afterClose = trimmed.index(after: close)
        guard afterClose < trimmed.endIndex, trimmed[afterClose] == "(" else { return nil }
        // The entire line must contain only this one image marker (whitespace allowed around it), to avoid swallowing inline images in body text.
        let alt = String(trimmed[trimmed.index(after: open)..<close])
        // `inner` starts at '(' (inclusive) so that subsequent startIndex/lastIndex checks are meaningful.
        let inner = trimmed[afterClose...]
        guard let endParen = inner.lastIndex(of: ")"),
              inner[inner.startIndex] == "(",
              inner[inner.index(before: endParen)] != "("
        else { return nil }
        var url = String(inner[inner.index(after: inner.startIndex)..<endParen])
            .trimmingCharacters(in: .whitespaces)
        // Strip optional trailing "title".
        if let quoteStart = url.firstIndex(of: "\""),
           let quoteEnd = url.lastIndex(of: "\""), quoteStart < quoteEnd {
            url = String(url[..<quoteStart]).trimmingCharacters(in: .whitespaces)
        }
        // If the line contains any visible characters beyond the image marker, treat it as body text rather than a standalone image.
        let remainder = trimmed
            .replacingOccurrences(of: "![" + alt + "]" + inner, with: "")
            .trimmingCharacters(in: .whitespaces)
        guard remainder.isEmpty else { return nil }
        return (url, alt)
    }

    // MARK: - GFM table

    /// Collects a full table when the current line is the header and the next line is the delimiter row.
    private static func collectTableIfPresent(
        lines: [String],
        from start: Int
    ) -> (header: [String], rows: [[String]], next: Int)? {
        guard start + 1 < lines.count,
              lines[start].contains("|"),
              isTableDelimiter(lines[start + 1])
        else { return nil }
        let header = splitTableRow(lines[start])
        guard !header.isEmpty else { return nil }
        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Empty line or no `|` means end of table.
            if trimmed.isEmpty || !line.contains("|") { break }
            rows.append(splitTableRow(line))
            index += 1
        }
        return (header: header, rows: rows, next: index)
    }

    /// Delimiter row: `| --- | :--: | ---: |` etc.; each cell contains only `-`, `:`, and spaces.
    private static func isTableDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        let cells = splitTableRow(trimmed)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell.trimmingCharacters(in: .whitespaces)
            guard !stripped.isEmpty else { return false }
            return stripped.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    /// Splits cells by `|`, dropping leading and trailing empty columns (e.g. `| a | b |` → ["a","b"]).
    private static func splitTableRow(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") { row.removeLast() }
        return row
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func fenceInfo(_ line: String) -> (marker: String, language: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") else { return nil }
        let marker = String(trimmed.prefix(3))
        let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return (marker, language.isEmpty ? nil : language)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.replacingOccurrences(of: " ", with: "")
        guard trimmed.count >= 3 else { return false }
        let first = trimmed.first
        guard first == "-" || first == "*" || first == "_" else { return false }
        return trimmed.allSatisfy { $0 == first }
    }

    private static func headingInfo(_ line: String) -> (level: Int, text: String)? {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0
        while trimmed.hasPrefix("#") {
            level += 1
            trimmed.removeFirst()
            guard level <= 6 else { return nil }
        }
        guard level > 0, trimmed.hasPrefix(" ") else { return nil }
        let text = trimmed.trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func isBulletItem(_ line: String) -> Bool {
        bulletItemPrefix(line) != nil
    }

    private static func bulletItemPrefix(_ line: String) -> (marker: String, rest: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return nil }
        guard first == "-" || first == "*" || first == "+" else { return nil }
        let rest = trimmed.dropFirst()
        guard rest.first == " " || rest.first == "\t" else { return nil }
        return (String(first), String(rest.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    private static func orderedItemPrefix(_ line: String) -> (marker: String, rest: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var digits = ""
        for char in trimmed {
            if char.isNumber {
                digits.append(char)
            } else {
                break
            }
        }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard afterDigits.hasPrefix(".") || afterDigits.hasPrefix(")") else { return nil }
        let delimiter = afterDigits.first!
        let rest = afterDigits.dropFirst()
        guard rest.first == " " || rest.first == "\t" else { return nil }
        let marker = digits + String(delimiter)
        return (marker, String(rest.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    /// Strips task-list markers `[ ]` / `[x]`, keeping plain text.
    private static func normalizeListItemText(_ text: String, marker: String) -> String {
        if text.hasPrefix("[ ] ") || text.hasPrefix("[ ]") {
            return "☐ " + text.replacingOccurrences(of: "^\\[ ?\\]\\s*", with: "", options: .regularExpression)
        }
        if text.lowercased().hasPrefix("[x]") {
            return "☑ " + text.replacingOccurrences(of: "^\\[[xX]\\]\\s*", with: "", options: .regularExpression)
        }
        return text
    }
}
