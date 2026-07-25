import Foundation
import SwiftUI

/// 把 Markdown 源文本渲染为单个 `AttributedString`，供灵动岛预览区 `Text` 直接显示。
///
/// 块级结构由 `MarkdownParser` 提供；行内格式（粗体/斜体/行内代码/链接/删除线）
/// 交给 Foundation 的 `AttributedString(markdown:)`，因此无需自己写正则替换，
/// 也不会误伤代码块内容。
///
/// 仅使用 SwiftUI 的 `Font`/`Color` 类型，不依赖 SwiftUI 属性包装宏，因此可在
/// 仅安装 Command Line Tools 的环境下编译。
public enum MarkdownRenderer {
    /// 基础正文字号；灵动岛内紧凑布局的下限。
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

    /// 行内格式：用 Foundation 解析粗体/斜体/行内代码/链接/删除线，
    /// 解析失败时回退为纯文本。
    private static func inline(_ text: String, font: Font) -> AttributedString {
        var attr: AttributedString
        if let parsed = try? AttributedString(markdown: text) {
            attr = parsed
        } else {
            attr = AttributedString(text)
        }
        attr.font = font
        return attr
    }
}
