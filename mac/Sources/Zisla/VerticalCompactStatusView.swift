import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct VerticalStatusText: View {
    let text: String
    let availableWidth: CGFloat
    let availableHeight: CGFloat

    init(text: String, availableWidth: CGFloat = 24, availableHeight: CGFloat) {
        self.text = text
        self.availableWidth = availableWidth
        self.availableHeight = availableHeight
    }

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(CompactPillStatusPresentation.verticalTextRows(text, availableWidth: availableWidth,
                availableHeight: availableHeight).enumerated()), id: \.offset) { _, row in
                Text(row.text)
                    .font(.system(size: 11, weight: .medium))
                    .rotationEffect(.degrees(row.rotatesClockwise ? 90 : 0))
                    .frame(height: 13)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

struct CompactPillStatusContent: View {
    let presentation: CompactPillStatusPresentation
    let text: String
    let edge: IslandEdge
    let visualizationStyle: MediaVisualizationStyle
    let item: NowPlayingSnapshot?

    nonisolated static func transientPresentation(message: String) -> CompactPillStatusPresentation {
        CompactPillStatusPresentation(priority: .transient,
            notice: IslandNotice(id: "app-transient", title: message, symbolName: "exclamationmark.triangle.fill"),
            text: message)
    }

    nonisolated static func displayText(
        for presentation: CompactPillStatusPresentation,
        settings: FeatureSettings,
        item: NowPlayingSnapshot?,
        at date: Date
    ) -> String {
        if presentation.isMedia, settings.mediaCompactStyle == .detailed,
           settings.mediaShowLyricsAndInfo, let item {
            return MediaTextFormatting.lyricLine(item, lyrics: item.lyrics, date: date)
        }
        return presentation.text
    }

    var body: some View {
        GeometryReader { proxy in
            let thickness = edge.isVertical ? proxy.size.width : proxy.size.height
            let iconSize = max(0, thickness - 8)
            let textLength = max(0, (edge.isVertical ? proxy.size.height : proxy.size.width)
                - thickness - (presentation.showsWaveform ? thickness + 6 : 0) - 6)
            let layout = edge.isVertical
                ? AnyLayout(VStackLayout(spacing: 6))
                : AnyLayout(HStackLayout(spacing: 6))
            layout {
                statusIcon(size: iconSize)
                    .frame(width: thickness, height: thickness)
                if !text.isEmpty {
                    if edge.isVertical {
                        VerticalStatusText(text: text, availableWidth: thickness, availableHeight: textLength)
                    } else {
                        MarqueeText(text, font: .system(size: 11, weight: .medium),
                                    textColor: .white, pointsPerSecond: TransientNoticeMetrics.pointsPerSecond,
                                    repeats: false)
                            .frame(width: textLength, height: thickness, alignment: .leading)
                    }
                }
                if presentation.showsWaveform {
                    MediaWaveformView(artworkData: item?.artworkData ?? presentation.notice.artworkData,
                                      width: iconSize, height: min(18, iconSize),
                                      isActive: item?.isPlaying ?? true)
                        .frame(width: thickness, height: thickness)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([presentation.notice.title, text].filter { !$0.isEmpty }.joined(separator: " "))
        .help([presentation.notice.title, text].filter { !$0.isEmpty }.joined(separator: " "))
    }

    @ViewBuilder
    private func statusIcon(size: CGFloat) -> some View {
        if presentation.isMedia {
            CompactMediaArtwork(
                artworkData: item?.artworkData ?? presentation.notice.artworkData,
                sourceIconData: item?.sourceIconData, size: size,
                visualizationStyle: visualizationStyle,
                isActive: item?.isPlaying ?? true
            )
        } else if presentation.priority == .aiActivity {
            AIMascotView(identity: AIMascotIdentity(noticeID: presentation.notice.id), size: size)
        } else if let image = MediaArtworkImageCache.image(from: presentation.notice.artworkData) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: presentation.notice.symbolName ?? defaultSymbol)
                .font(.system(size: size * 0.64, weight: .semibold))
                .frame(width: size, height: size)
        }
    }

    private var defaultSymbol: String {
        switch presentation.priority {
        case .aiActivity: "sparkles"
        case .browserDownload, .videoDownload: "arrow.down.circle.fill"
        case .focusCountdown: "clock"
        case .focusMode: "moon.fill"
        case .mail: "envelope.fill"
        case .updateAvailable: "arrow.down.app.fill"
        case .toolboxReminder: "display"
        default: "waveform"
        }
    }
}
