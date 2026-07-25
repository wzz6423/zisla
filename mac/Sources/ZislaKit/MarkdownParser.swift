import Foundation

/// Markdown 块级解析结果。仅覆盖随记场景常用的子集，刻意不引入第三方依赖。
///
/// 解析器以行为单位扫描，识别：标题、无序/有序列表、引用、围栏代码块、分隔线、
/// 段落、**独立图片行**、**GFM 管道表格**。行内格式（粗体、斜体、行内代码、链接、
/// 删除线、行内图片）交给 `MarkdownHTMLRenderer` / `MarkdownRenderer` 处理，块级解析不触碰。
public enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletList(items: [String])
    case orderedList(items: [String])
    case blockquote(text: String)
    case codeBlock(language: String?, content: String)
    case horizontalRule
    /// 单独成行的图片：`![alt](url)`。
    case image(url: String, alt: String)
    /// GFM 管道表格：首行为表头，随后分隔行，其余为数据行。
    case table(header: [String], rows: [[String]])
}

public enum MarkdownParser {
    /// 将 Markdown 源文本解析为块序列。空输入返回空数组。
    public static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            // 跳过空行（块边界）
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                index += 1
                continue
            }

            // 围栏代码块 ```lang
            if let fence = fenceInfo(line) {
                let (content, next) = collectCodeBlock(lines: lines, from: index + 1, fence: fence.marker)
                blocks.append(.codeBlock(language: fence.language, content: content))
                index = next
                continue
            }

            // 分隔线：--- / *** / ___（至少三个相同字符）
            if isHorizontalRule(line) {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            // 标题 # .. ######
            if let heading = headingInfo(line) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            // 独立图片行：![alt](url)
            if let image = imageInfo(line) {
                blocks.append(.image(url: image.url, alt: image.alt))
                index += 1
                continue
            }

            // GFM 管道表格：当前行为表头、下一行为分隔行
            if let table = collectTableIfPresent(lines: lines, from: index) {
                blocks.append(.table(header: table.header, rows: table.rows))
                index = table.next
                continue
            }

            // 引用 >
            if line.hasPrefix(">") {
                let (text, next) = collectBlockquote(lines: lines, from: index)
                blocks.append(.blockquote(text: text))
                index = next
                continue
            }

            // 无序列表 - / * / +
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

            // 有序列表 1. / 2)
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

            // 段落：连续非空行直到块边界
            let (text, next) = collectParagraph(lines: lines, from: index)
            blocks.append(.paragraph(text: text))
            index = next
        }

        return blocks
    }

    // MARK: - 块收集

    private static func collectParagraph(lines: [String], from start: Int) -> (String, Int) {
        var collected: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            // 遇到下一个块的起始符则停止
            if isBlockStart(line) { break }
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
        // 未闭合的代码块：取到末尾
        return (collected.joined(separator: "\n"), index)
    }

    // MARK: - 行首判定

    /// 当前行是否是某个块级结构的起始（用于段落收集时判断边界）。
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

    // MARK: - 图片

    /// 解析独立图片行 `![alt](url "可选标题")`，非独立图片返回 `nil`。
    private static func imageInfo(_ line: String) -> (url: String, alt: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("!"),
              let open = trimmed.firstIndex(of: "["),
              let close = trimmed.firstIndex(of: "]"),
              open < close,
              trimmed[trimmed.index(after: close)] == "("
        else { return nil }
        // 整行必须只有这一个图片标记（前后可空白），避免误吞正文里的图片。
        let alt = String(trimmed[trimmed.index(after: open)..<close])
        let afterClose = trimmed.index(after: close)
        // inner 从 '(' 开始（包含 '('），这样后续的 startIndex/lastIndex 校验才有意义。
        let inner = trimmed[afterClose...]
        guard let endParen = inner.lastIndex(of: ")"),
              inner[inner.startIndex] == "(",
              inner[inner.index(before: endParen)] != "("
        else { return nil }
        var url = String(inner[inner.index(after: inner.startIndex)..<endParen])
            .trimmingCharacters(in: .whitespaces)
        // 去掉末尾可选的 "标题"
        if let quoteStart = url.firstIndex(of: "\""),
           let quoteEnd = url.lastIndex(of: "\""), quoteStart < quoteEnd {
            url = String(url[..<quoteStart]).trimmingCharacters(in: .whitespaces)
        }
        // 整行若除图片标记外还有其它可见字符，则视为正文而非独立图片。
        let remainder = trimmed
            .replacingOccurrences(of: "![" + alt + "]" + inner, with: "")
            .trimmingCharacters(in: .whitespaces)
        guard remainder.isEmpty else { return nil }
        return (url, alt)
    }

    // MARK: - GFM 表格

    /// 当前行是表格表头且下一行是分隔行时，收集整张表格。
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
            // 空行或不再含 `|` 即表格结束
            if trimmed.isEmpty || !line.contains("|") { break }
            rows.append(splitTableRow(line))
            index += 1
        }
        return (header: header, rows: rows, next: index)
    }

    /// 分隔行：`| --- | :--: | ---: |` 等，每格仅由 `-`、`:`、空格组成。
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

    /// 按 `|` 切分单元格，去掉首尾空列（如 `| a | b |` → ["a","b"]）。
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

    /// 去掉任务列表标记 `[ ]` / `[x]`，保留纯文本。
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
