import AppKit
import ZislaCore

public struct CompactPillStatusPresentation: Equatable, Sendable {
    public static let minimumThickness: CGFloat = 32
    public static let trailingInset: CGFloat = 12
    public static let maximumTextLength: CGFloat = 168
    public static let accountBalanceScrollSpeed: Double = 32
    public static let pomodoroControlsLength: CGFloat = 54

    public struct VerticalTextRow: Equatable, Sendable {
        public let text: String
        public let rotatesClockwise: Bool
    }

    public let priority: CompactStatusPriority?
    public let notice: IslandNotice
    public let text: String
    public let aiCount: Int
    public let showsWaveform: Bool
    public let showsMediaIdentity: Bool
    public var isMedia: Bool { priority == .media && notice.id.hasPrefix("media-active-") }
    public var isAccountBalance: Bool { AIAccountBalanceNoticeController.isBalanceNotice(notice) }
    public var accountBalanceLines: [String] {
        guard isAccountBalance else { return [] }
        return (0..<2).compactMap { notice.metadata?["quotaLine\($0)"] }
    }

    public init(priority: CompactStatusPriority?, notice: IslandNotice, text: String,
         aiCount: Int = 0, showsWaveform: Bool = false, showsMediaIdentity: Bool = false) {
        self.priority = priority
        self.notice = notice
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aiCount = aiCount
        self.showsWaveform = showsWaveform
        self.showsMediaIdentity = showsMediaIdentity
    }

    /// Measures the shared ring and longest summary within existing text-length bounds.
    /// Vertical edges divide the available thickness between quota lines instead of assuming horizontal text.
    public func length(thickness: CGFloat, edge: IslandEdge, text: String? = nil,
        item: NowPlayingSnapshot? = nil, leadingInset: CGFloat = trailingInset) -> CGFloat {
        let text = (text ?? self.text).trimmingCharacters(in: .whitespacesAndNewlines)
        if isAccountBalance {
            let values = accountBalanceLines
            let lineWidth = edge.isVertical
                ? max(1, (thickness - 8 - CGFloat(max(0, values.count - 1)) * 2) / CGFloat(max(1, values.count))) : thickness
            let valueLength = values.map { Self.textLength($0, availableWidth: lineWidth, edge: edge,
                font: NSFont.systemFont(ofSize: values.count > 1 ? 9 : 11, weight: .semibold)) }.max() ?? 0
            return leadingInset + Self.trailingInset + max(0, thickness - 8) + 6 + min(Self.maximumTextLength, valueLength)
        }
        let iconSize = max(0, thickness - 8)
        let visualLength = (showsWaveform || priority == .updateAvailable ? iconSize * 2 + 6 : iconSize)
            + Self.trailingInset + leadingInset
            + (priority == .focusCountdown ? Self.pomodoroControlsLength + 6 : 0)
        let identityLength = mediaIdentityLength(thickness: thickness, edge: edge, text: text, item: item)
        let lyricLength = Self.textLength(text, availableWidth: thickness, edge: edge,
            font: NSFont.systemFont(ofSize: 11, weight: .medium))
        let textLength = identityLength + lyricLength + (identityLength > 0 && !text.isEmpty ? 6 : 0)
        guard textLength > 0 else { return visualLength }
        return visualLength + 6 + min(Self.maximumTextLength, textLength)
    }

    /// Camera wings share a physical gap, so each side must fit the larger of the ring or summary.
    public func accountBalanceSideWidth(thickness: CGFloat) -> CGFloat {
        let valueWidth = accountBalanceLines.map {
            Self.textLength($0, availableWidth: thickness, edge: .top,
                font: NSFont.systemFont(ofSize: accountBalanceLines.count > 1 ? 9 : 11, weight: .semibold))
        }.max() ?? 0
        return max(max(0, thickness - 8), min(Self.maximumTextLength, valueWidth)) + Self.trailingInset * 2
    }

    /// A one-pass summary must reach its tail before either expiry or the next pinned account.
    public func accountBalanceReadingSeconds(thickness: CGFloat, edge: IslandEdge) -> Double {
        let lines = accountBalanceLines
        let font = NSFont.systemFont(ofSize: lines.count > 1 ? 9 : 11, weight: .semibold)
        let verticalWidth = max(1, (thickness - 8 - CGFloat(max(0, lines.count - 1)) * 2) / CGFloat(max(1, lines.count)))
        let travel = lines.map { line -> CGFloat in
            if edge.isVertical {
                let full = CGFloat(Self.verticalTextRows(line, availableWidth: verticalWidth,
                    availableHeight: CGFloat(line.count) * 14).count) * 14 - 1
                return max(0, full)
            }
            return ceil((line as NSString).size(withAttributes: [.font: font]).width)
        }.max() ?? 0
        return Double(travel) / Self.accountBalanceScrollSpeed + 2.4
    }

    public func mediaIdentityLength(thickness: CGFloat, edge: IslandEdge, text: String,
        item: NowPlayingSnapshot?) -> CGFloat {
        guard showsMediaIdentity, let item, !item.isVideo else { return 0 }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = item.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let width = edge.isVertical && !artist.isEmpty ? thickness / 2 : thickness
        let titleLength = Self.textLength(title, availableWidth: width, edge: edge,
            font: NSFont.systemFont(ofSize: 10.5, weight: .regular))
        let artistLength = Self.textLength(artist, availableWidth: width, edge: edge,
            font: NSFont.systemFont(ofSize: 8.5, weight: .regular))
        return min(Self.maximumTextLength / (text.isEmpty ? 1 : 2), max(titleLength, artistLength))
    }

    private static func textLength(_ text: String, availableWidth: CGFloat, edge: IslandEdge,
        font: NSFont) -> CGFloat {
        if edge.isVertical {
            return CGFloat(verticalTextRows(text, availableWidth: availableWidth,
                availableHeight: maximumTextLength).count) * 14
        }
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
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
