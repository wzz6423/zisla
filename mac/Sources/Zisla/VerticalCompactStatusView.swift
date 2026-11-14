import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct VerticalStatusText: View {
    let text: String
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    let scrollProgress: Double?
    let scrollsAutomatically: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var automaticScrollProgress: CGFloat = 0

    init(text: String, availableWidth: CGFloat = 24, availableHeight: CGFloat,
         scrollProgress: Double? = nil, scrollsAutomatically: Bool = false) {
        self.text = text
        self.availableWidth = availableWidth
        self.availableHeight = availableHeight
        self.scrollProgress = scrollProgress
        self.scrollsAutomatically = scrollsAutomatically
    }

    var body: some View {
        let usesScrolling = scrollProgress != nil || scrollsAutomatically
        let rows = CompactPillStatusPresentation.verticalTextRows(text, availableWidth: availableWidth,
            availableHeight: usesScrolling ? CGFloat(text.count) * 14 : availableHeight)
        let travel = max(0, CGFloat(rows.count) * 14 - 1 - availableHeight)
        let content = VStack(spacing: 1) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Text(row.text)
                    .font(.system(size: 11, weight: .medium))
                    .rotationEffect(.degrees(row.rotatesClockwise ? 90 : 0))
                    .frame(height: 13)
            }
        }
        Group {
            if usesScrolling {
                content
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: -travel * CGFloat(min(max(scrollProgress ?? Double(automaticScrollProgress), 0), 1)))
                    .frame(width: availableWidth, height: availableHeight, alignment: .top)
                    .clipped()
            } else {
                content
            }
        }
        .task {
            automaticScrollProgress = 0
            guard scrollsAutomatically, !reduceMotion else { return }
            withAnimation(.linear(duration: Double(travel) / TransientNoticeMetrics.pointsPerSecond)) {
                automaticScrollProgress = 1
            }
        }
        .id(AutomaticAnimationIdentity(text: text, width: availableWidth, height: availableHeight,
            scrollsAutomatically: scrollsAutomatically, usesExternalProgress: scrollProgress != nil,
            reduceMotion: reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private struct AutomaticAnimationIdentity: Hashable {
        let text: String
        let width: CGFloat
        let height: CGFloat
        let scrollsAutomatically: Bool
        let usesExternalProgress: Bool
        let reduceMotion: Bool
    }
}

struct CompactPillStatusContent: View {
    let presentation: CompactPillStatusPresentation
    let text: String
    let edge: IslandEdge
    let visualizationStyle: MediaVisualizationStyle
    let item: NowPlayingSnapshot?
    let date: Date
    var leadingInset: CGFloat = CompactPillStatusPresentation.trailingInset
    var onJoinMeeting: (String) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

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
            if !item.isVideo {
                return item.lyrics?.currentLine(at: item.elapsedTime(at: date) ?? 0)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            return MediaTextFormatting.lyricLine(item, lyrics: item.lyrics, date: date)
        }
        return presentation.text
    }

    private var lyricScrollProgress: Double? {
        guard presentation.isMedia, let item, !item.isVideo, let lyrics = item.lyrics else { return nil }
        return lyrics.currentLineProgress(at: item.elapsedTime(at: date) ?? 0, duration: item.duration) ?? 0
    }

    var body: some View {
        Group {
            if presentation.priority == .meeting, let id = presentation.notice.metadata?["eventID"] {
                Button { onJoinMeeting(id) } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLocalization.text("加入会议：%@ · %@", presentation.notice.title, text))
            } else {
                content
            }
        }
        .background {
            if presentation.priority == .focusCountdown {
                CompactPomodoroControlRegion()
            }
        }
    }

    private var content: some View {
        GeometryReader { proxy in
            if presentation.isAccountBalance {
                CompactAIAccountBalanceBar(notice: presentation.notice,
                    height: edge.isVertical ? proxy.size.width : proxy.size.height, edge: edge,
                    leadingInset: leadingInset)
            } else {
            let thickness = edge.isVertical ? proxy.size.width : proxy.size.height
            let iconSize = max(0, thickness - 8)
            let textBudget = max(0, (edge.isVertical ? proxy.size.height : proxy.size.width)
                - iconSize - (presentation.showsWaveform ? iconSize + 6 : 0) - 6
                - CompactPillStatusPresentation.trailingInset - leadingInset
                - (presentation.priority == .focusCountdown
                    ? CompactPillStatusPresentation.pomodoroControlsLength + 6 : 0))
            let identityLength = min(textBudget, presentation.mediaIdentityLength(
                thickness: thickness, edge: edge, text: text, item: item))
            let textLength = max(0, textBudget - identityLength - (identityLength > 0 && !text.isEmpty ? 6 : 0))
            let layout = edge.isVertical
                ? AnyLayout(VStackLayout(spacing: 6))
                : AnyLayout(HStackLayout(spacing: 6))
            layout {
                if presentation.priority == .updateAvailable {
                    ForEach([NoticeSide.left, .right], id: \.self) { side in
                        CompactUpdateWing(notice: presentation.notice, side: side, height: thickness,
                            usesTransparentBackground: true)
                            .frame(width: edge.isVertical ? thickness : iconSize,
                                   height: edge.isVertical ? iconSize : thickness)
                    }
                } else {
                    statusIcon(size: iconSize)
                        .frame(width: edge.isVertical ? thickness : iconSize,
                               height: edge.isVertical ? iconSize : thickness)
                }
                if let item, identityLength > 0 {
                    mediaIdentity(item, length: identityLength, thickness: thickness)
                        .frame(width: edge.isVertical ? thickness : identityLength,
                               height: edge.isVertical ? identityLength : thickness)
                }
                if presentation.showsWaveform, identityLength > 0 {
                    waveform(size: iconSize, thickness: thickness)
                }
                if !text.isEmpty {
                    if edge.isVertical {
                        VerticalStatusText(text: text, availableWidth: thickness, availableHeight: textLength,
                                           scrollProgress: lyricScrollProgress)
                            .frame(width: thickness, height: textLength, alignment: .top)
                    } else {
                        MarqueeText(text, font: .system(size: 11, weight: .medium),
                                    textColor: .white, pointsPerSecond: TransientNoticeMetrics.pointsPerSecond,
                                    repeats: false, scrollProgress: lyricScrollProgress)
                            .frame(width: textLength, height: thickness, alignment: .leading)
                    }
                }
                if presentation.showsWaveform, identityLength == 0 {
                    waveform(size: iconSize, thickness: thickness)
                }
                if presentation.priority == .focusCountdown {
                    CompactPomodoroControls(edge: edge)
                        .frame(width: edge.isVertical ? thickness : CompactPillStatusPresentation.pomodoroControlsLength,
                               height: edge.isVertical ? CompactPillStatusPresentation.pomodoroControlsLength : thickness)
                }
            }
            .padding(edge.isVertical ? .top : .leading, leadingInset)
            .padding(edge.isVertical ? .bottom : .trailing, CompactPillStatusPresentation.trailingInset)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .environment(\.layoutDirection, presentation.priority == .focusCountdown ? .leftToRight : layoutDirection)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: presentation.priority == .focusCountdown ? .contain : .ignore)
        .accessibilityLabel(accessibilityDescription)
        .help(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if presentation.priority == .updateAvailable {
            return AppLocalization.text("%@有可用更新", presentation.notice.title)
        }
        let identity = presentation.showsMediaIdentity && item?.isVideo == false
            ? item.map(MediaTextFormatting.titleArtistText) : nil
        return [identity ?? presentation.notice.title, text].filter { !$0.isEmpty }.joined(separator: " ")
    }

    @ViewBuilder
    private func mediaIdentity(_ item: NowPlayingSnapshot, length: CGFloat, thickness: CGFloat) -> some View {
        if edge.isVertical {
            let artist = item.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let width = artist.isEmpty ? thickness : thickness / 2
            HStack(spacing: 0) {
                VerticalStatusText(text: item.title, availableWidth: width,
                    availableHeight: length, scrollsAutomatically: true)
                    .frame(width: width, height: length, alignment: .top)
                if !artist.isEmpty {
                    VerticalStatusText(text: artist, availableWidth: width,
                        availableHeight: length, scrollsAutomatically: true)
                        .frame(width: width, height: length, alignment: .top)
                        .opacity(0.62)
                }
            }
        } else {
            CompactMediaIdentityText(item: item)
        }
    }

    private func waveform(size: CGFloat, thickness: CGFloat) -> some View {
        MediaWaveformView(artworkData: item?.artworkData ?? presentation.notice.artworkData,
            width: size, height: min(18, size), isActive: item?.isPlaying ?? true)
            .frame(width: edge.isVertical ? thickness : size,
                   height: edge.isVertical ? size : thickness)
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
        } else if presentation.notice.style == .headphone {
            HeadphoneGlyph(
                productID: presentation.notice.headphoneProductID,
                isPresented: !reduceMotion,
                isSingleUnit: presentation.notice.symbolName == "headphones",
                reduceMotion: reduceMotion
            )
            .frame(width: size, height: size)
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
        case .meeting: "video.fill"
        case .focusMode: "moon.fill"
        case .mail: "envelope.fill"
        case .updateAvailable: "arrow.down.app.fill"
        case .toolboxReminder: "display"
        default: "waveform"
        }
    }
}
