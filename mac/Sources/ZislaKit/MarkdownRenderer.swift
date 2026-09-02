import Foundation
import SwiftUI

/// Renders a Markdown source string into a single `AttributedString` for direct display
/// in the island preview area's `Text` view.
///
/// Block structure is provided by `MarkdownParser`; inline formatting (bold/italic/inline
/// code/links/strikethrough) is delegated to Foundation's `AttributedString(markdown:)`,
/// so no custom regex substitution is needed and code block content is never mangled.
///
/// Uses only SwiftUI's `Font`/`Color` types and no SwiftUI property-wrapper macros, so
/// it compiles in environments with only Command Line Tools installed.
public enum MarkdownRenderer {
    /// Base body font size; the lower bound for the island's compact layout.
    private static let baseSize: CGFloat = 12

    public static func attributedString(from source: String) -> AttributedString {
        let blocks = MarkdownParser.parse(source)
        guard !blocks.isEmpty else { return AttributedString() }

        var result = AttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            result.append(render(block))
        }
        return result
    }

    private static func render(_ block: MarkdownBlock) -> AttributedString {
        switch block {
        case let .heading(level, text):
            return heading(text: text, level: level)
        case let .paragraph(text):
            return inline(text, font: .system(size: baseSize))
        case let .bulletList(items):
            return list(items: items, marker: "•  ", ordered: false)
        case let .orderedList(items):
            return list(items: items, marker: nil, ordered: true)
        case let .blockquote(text):
            return blockquote(text: text)
        case let .codeBlock(_, content):
            return codeBlock(content: content)
        case let .image(url, alt):
            var attr = AttributedString("🖼 " + (alt.isEmpty ? url : alt))
            attr.font = .system(size: baseSize)
            return attr
        case let .table(header, rows):
            var result = AttributedString()
            var head = AttributedString(header.joined(separator: "  |  "))
            head.font = .system(size: baseSize, weight: .semibold)
            result.append(head)
            for row in rows {
                var line = AttributedString("\n" + row.joined(separator: "  |  "))
                line.font = .system(size: baseSize)
                result.append(line)
            }
            return result
        case .horizontalRule:
            var attr = AttributedString("———————")
            attr.font = .system(size: baseSize - 1)
            attr.foregroundColor = .secondary
            return attr
        }
    }

    private static func heading(text: String, level: Int) -> AttributedString {
        let size: CGFloat
        switch level {
        case 1: size = 16
        case 2: size = 14
        case 3: size = 13
        default: size = baseSize
        }
        var attr = inline(text, font: .system(size: size, weight: .bold))
        if level <= 2 {
            var newline = AttributedString("\n")
            newline.foregroundColor = .clear
            attr.append(newline)
        }
        return attr
    }

    private static func list(items: [String], marker: String?, ordered: Bool) -> AttributedString {
        var result = AttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            let prefix = ordered ? "\(index + 1).  " : (marker ?? "•  ")
            var bullet = AttributedString(prefix)
            bullet.font = .system(size: baseSize)
            bullet.foregroundColor = .secondary
            result.append(bullet)
            result.append(inline(item, font: .system(size: baseSize)))
        }
        return result
    }

    private static func blockquote(text: String) -> AttributedString {
        var bar = AttributedString("▎")
        bar.foregroundColor = .secondary
        var content = inline(text, font: .system(size: baseSize))
        content.foregroundColor = .secondary
        var result = AttributedString()
        result.append(bar)
        result.append(content)
        return result
    }

    private static func codeBlock(content: String) -> AttributedString {
        var attr = AttributedString(content)
        attr.font = .system(size: baseSize - 1, design: .monospaced)
        attr.foregroundColor = .secondary
        return attr
    }

    /// Inline formatting: parse bold/italic/inline code/links/strikethrough via Foundation;
    /// fall back to plain text on parse failure.
    private static func inline(_ text: String, font: Font) -> AttributedString {
        let expandedText = expandIndentationMarkers(in: text)
        var attr: AttributedString
        if let parsed = try? AttributedString(markdown: expandedText) {
            attr = parsed
        } else {
            attr = AttributedString(expandedText)
        }
        attr.font = font
        return attr
    }

    private static func expandIndentationMarkers(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "%%ZISLA_INDENT:([0-9]+)%%") else {
            return text
        }
        let nsText = text as NSString
        var result = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed() {
            guard let count = Int(nsText.substring(with: match.range(at: 1))), count <= 4096 else {
                continue
            }
            result = (result as NSString).replacingCharacters(
                in: match.range,
                with: String(repeating: "\u{00A0}", count: count)
            )
        }
        return result
    }
}
