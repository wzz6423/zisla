import AppKit
import SwiftUI
import ZislaKit

struct SelectableChatMessageText: NSViewRepresentable {
    let content: String
    let onSelectionChanged: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChanged: onSelectionChanged)
    }

    func makeNSView(context: Context) -> SelectableChatMessageNSTextView {
        let view = SelectableChatMessageNSTextView()
        view.delegate = context.coordinator
        view.setContent(content)
        return view
    }

    func updateNSView(_ view: SelectableChatMessageNSTextView, context: Context) {
        context.coordinator.onSelectionChanged = onSelectionChanged
        view.setContent(content)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectionChanged: (String) -> Void

        init(onSelectionChanged: @escaping (String) -> Void) {
            self.onSelectionChanged = onSelectionChanged
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let selected = range.length == 0
                ? ""
                : (textView.string as NSString).substring(with: range)
            onSelectionChanged(selected)
        }
    }
}

final class SelectableChatMessageNSTextView: NSTextView {
    private var renderedSource: String?

    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        drawsBackground = false
        isEditable = false
        isSelectable = true
        isRichText = false
        allowsUndo = false
        font = .systemFont(ofSize: ChatMessageMarkdown.baseSize)
        textColor = .labelColor
        linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .cursor: NSCursor.pointingHand,
        ]
        textContainerInset = .zero
        isHorizontallyResizable = false
        isVerticallyResizable = true
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize }
        // LazyVStack 物化新行会在赋 frame 之前询问高度，此时容器宽度仍是初始 0，
        // 零宽排版会得到每行一字的天文高度，引发首帧跳变；拿到真实宽度后 layout() 会再失效重算。
        guard textContainer.size.width > 0 else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 16)
        }
        layoutManager.ensureLayout(for: textContainer)
        let height = ceil(layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(16, height))
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }

    func setContent(_ value: String) {
        guard renderedSource != value else { return }
        renderedSource = value
        textStorage?.setAttributedString(ChatMessageMarkdown.attributedString(from: value))
        invalidateIntrinsicContentSize()
    }
}

/// Renders an assistant reply the way a coding agent's transcript reads: headings, lists and fenced
/// code keep their structure, while selection stays intact so annotations still work.
///
/// Block splitting is delegated to `MarkdownParser`; only the AppKit styling is defined here, because
/// `MarkdownRenderer` emits SwiftUI fonts that an `NSTextView` cannot consume.
enum ChatMessageMarkdown {
    static let baseSize: CGFloat = 11

    struct ImageReference: Identifiable {
        let id: Int
        let url: URL
        let alt: String
    }

    /// `withAlphaComponent` 会把 catalog 动态色按调用瞬间的外观固化成静态色；构建发生在
    /// `setContent` 而非绘制时，固化结果随系统亮暗漂移且被 renderedSource 缓存永久留存。
    /// 包一层 dynamicProvider 推迟到绘制时按实际外观解析。
    private static let codeChipBackground = NSColor(name: nil) { _ in
        NSColor.quaternaryLabelColor.withAlphaComponent(0.28)
    }

    static func attributedString(from source: String) -> NSAttributedString {
        let blocks = MarkdownParser.parse(source)
        guard !blocks.isEmpty else { return NSAttributedString(string: "") }

        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(render(block))
        }
        return result
    }

    static func imageReferences(in source: String) -> [ImageReference] {
        MarkdownParser.parse(source).enumerated().compactMap { index, block in
            guard case let .image(rawURL, alt) = block,
                  let url = imageURL(from: rawURL) else {
                return nil
            }
            return ImageReference(id: index, url: url, alt: alt)
        }
    }

    private static func render(_ block: MarkdownBlock) -> NSAttributedString {
        switch block {
        case let .heading(level, text):
            let size = switch level {
            case 1: baseSize + 4
            case 2: baseSize + 2
            case 3: baseSize + 1
            default: baseSize
            }
            return inline(text, font: .systemFont(ofSize: size, weight: .semibold))
        case let .paragraph(text):
            return inline(text, font: .systemFont(ofSize: baseSize))
        case let .bulletList(items):
            return list(items, ordered: false)
        case let .orderedList(items):
            return list(items, ordered: true)
        case let .blockquote(text):
            let quoted = NSMutableAttributedString(attributedString: inline(text, font: .systemFont(ofSize: baseSize)))
            quoted.addAttribute(
                .foregroundColor,
                value: NSColor.secondaryLabelColor,
                range: NSRange(location: 0, length: quoted.length)
            )
            let bar = NSAttributedString(
                string: "▎",
                attributes: [
                    .font: NSFont.systemFont(ofSize: baseSize),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
            )
            let result = NSMutableAttributedString(attributedString: bar)
            result.append(quoted)
            return result
        case let .codeBlock(_, content):
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = 8
            style.headIndent = 8
            style.paragraphSpacingBefore = 2
            style.paragraphSpacing = 2
            return NSAttributedString(
                string: content,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: baseSize - 1, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: codeChipBackground,
                    .paragraphStyle: style,
                ]
            )
        case .image:
            return NSAttributedString(string: "")
        case let .table(header, rows):
            let result = NSMutableAttributedString(
                attributedString: inline(
                    header.joined(separator: "  |  "),
                    font: .systemFont(ofSize: baseSize, weight: .semibold)
                )
            )
            for row in rows {
                result.append(NSAttributedString(string: "\n"))
                result.append(inline(row.joined(separator: "  |  "), font: .systemFont(ofSize: baseSize)))
            }
            return result
        case .horizontalRule:
            return NSAttributedString(
                string: "———————",
                attributes: [
                    .font: NSFont.systemFont(ofSize: baseSize - 1),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
            )
        }
    }

    private static func imageURL(from rawURL: String) -> URL? {
        if rawURL.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(rawURL.dropFirst(2)))
        }
        if rawURL.hasPrefix("/") {
            return URL(fileURLWithPath: rawURL)
        }
        return URL(string: rawURL)
    }

    private static func list(_ items: [String], ordered: Bool) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.headIndent = 14
        let result = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(NSAttributedString(
                string: ordered ? "\(index + 1). " : "•  ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: baseSize),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ))
            result.append(inline(item, font: .systemFont(ofSize: baseSize)))
        }
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// Bold / italic / inline code / links / strikethrough come from Foundation's Markdown parser, so
    /// only the presentation intents need mapping onto AppKit fonts.
    private static func inline(_ text: String, font: NSFont) -> NSAttributedString {
        let plain = NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        guard let parsed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return plain
        }

        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.labelColor]
            if intent.contains(.code) {
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize - 0.5, weight: .regular)
                attributes[.backgroundColor] = codeChipBackground
            } else {
                var traits = font.fontDescriptor.symbolicTraits
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
                attributes[.font] = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
            }
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
            }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result.length == 0 ? plain : result
    }
}
