import AppKit
import ZislaCore

public struct CompactPillStatusPresentation: Equatable, Sendable {
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
            textLength = CGFloat(text.filter { !$0.isWhitespace }.count) * 14
        } else {
            textLength = ceil((text as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium)
            ]).width)
        }
        return visualLength + 6 + min(168, textLength)
    }
}
