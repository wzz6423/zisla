import AppKit
import ZislaCore

public struct CompactPillStatusPresentation: Equatable, Sendable {
    public struct VerticalTextRow: Equatable, Sendable {
        public let text: String
        public let rotatesClockwise: Bool
    }

    public let priority: CompactStatusPriority?
    public let notice: IslandNotice
    public let text: String
    public let aiCount: Int
    public let showsWaveform: Bool
    public var isMedia: Bool { priority == .media && notice.id.hasPrefix("media-active-") }

    public init(priority: CompactStatusPriority?, notice: IslandNotice, text: String,
         aiCount: Int = 0, showsWaveform: Bool = false) {
        self.priority = priority
        self.notice = notice
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aiCount = aiCount
        self.showsWaveform = showsWaveform
    }

    public func length(thickness: CGFloat, edge: IslandEdge, text: String? = nil) -> CGFloat {
        let text = (text ?? self.text).trimmingCharacters(in: .whitespacesAndNewlines)
        let visualLength = showsWaveform ? thickness * 2 + 6 : thickness
        guard !text.isEmpty else { return visualLength }
        let textLength: CGFloat
        if edge.isVertical {
            textLength = CGFloat(Self.verticalTextRows(text, availableWidth: thickness, availableHeight: 168).count) * 14
        } else {
            textLength = ceil((text as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium)
            ]).width)
        }
        return visualLength + 6 + min(168, textLength)
    }

    public static func verticalTextRows(_ text: String, availableWidth: CGFloat, availableHeight: CGFloat) -> [VerticalTextRow] {
        guard availableWidth.isFinite, availableWidth > 0,
              availableHeight.isFinite, availableHeight >= 14 else { return [] }
        let brackets = "()（）[]［］【】{}｛｝〈〉《》「」『』〔〕〖〗〘〙〚〛"
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        var rows: [VerticalTextRow] = []
        var run = ""
        func append(_ value: String) {
            rows.append(VerticalTextRow(text: value,
                rotatesClockwise: value.count == 1 && brackets.contains(value)))
        }
        func width(_ value: String) -> CGFloat {
            ceil((value as NSString).size(withAttributes: [.font: font]).width)
        }
        func flushRun() {
            guard !run.isEmpty else { return }
            if width(run) <= availableWidth {
                append(run)
            } else {
                var chunk = ""
                for character in run {
                    let value = String(character)
                    if brackets.contains(value) {
                        if !chunk.isEmpty { append(chunk); chunk = "" }
                        append(value)
                    } else {
                        if !chunk.isEmpty, width(chunk + value) > availableWidth {
                            append(chunk)
                            chunk = ""
                        }
                        chunk += value
                    }
                }
                if !chunk.isEmpty { append(chunk) }
            }
            run = ""
        }
        for character in text where !character.isWhitespace {
            let horizontal = character.isNumber || character.unicodeScalars.allSatisfy {
                CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
            }
            if horizontal {
                run.append(character)
            } else {
                flushRun()
                append(String(character))
            }
        }
        flushRun()
        let capacity = Int(min(CGFloat(rows.count), availableHeight / 14))
        guard rows.count > capacity else { return rows }
        return Array(rows.prefix(capacity - 1)) + [VerticalTextRow(text: "…", rotatesClockwise: false)]
    }
}
