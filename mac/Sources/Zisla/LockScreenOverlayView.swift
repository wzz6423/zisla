import AppKit
import Foundation
import ZislaKit
import SwiftUI

@MainActor
struct LockScreenOverlayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var media: NowPlayingService
    @StateObject private var scrubState = MediaScrubState()
    @Environment(\.locale) private var locale
    let kind: LockScreenOverlayKind

    init(model: AppModel, kind: LockScreenOverlayKind) {
        _model = ObservedObject(wrappedValue: model)
        _media = ObservedObject(wrappedValue: model.media)
        self.kind = kind
    }

    var body: some View {
        switch kind {
        case .header:
            header
        case .status:
            status
        case .player:
            player
        }
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let message = model.settingsStore.settings.lockScreenMessage
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lunar = model.settingsStore.settings.lockScreenShowsLunar
                ? LunarCalendar.components(from: context.date)?.yearMonthDayText
                : nil
            VStack(spacing: 5) {
                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 17, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                if let lunar {
                    Text("农历 \(lunar)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var status: some View {
        HStack(spacing: 22) {
            if let battery = model.battery.snapshot {
                statusItem(
                    symbol: battery.symbolName,
                    text: "\(battery.percentInt)% \(batteryDetail(battery))"
                )
            }
            if model.settingsStore.settings.weatherEnabled, let weather = model.weather {
                statusItem(
                    symbol: weather.condition.symbolName,
                    text: "\(Int(weather.temperature.rounded()))° \(weather.condition.summary)"
                )
            }
        }
        .foregroundStyle(.white.opacity(0.92))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var player: some View {
        if model.settingsStore.settings.mediaEnabled, let item = media.snapshot {
            let track = MediaScrubTrack(item)
            VStack(spacing: 11) {
                HStack(spacing: 14) {
                    artwork(for: item)
                    VStack(alignment: .leading, spacing: 3) {
                        MarqueeText(
                            Self.titleArtistText(item),
                            font: .system(size: 14, weight: .semibold),
                            textColor: .white
                        )
                        .layoutPriority(2)
                        currentLyrics(item)
                            .layoutPriority(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
                playbackProgress(for: item)
                if item.supportsControls {
                    controls(for: item)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(glassBackground)
            .onChange(of: track, initial: true) { _, newValue in
                scrubState.trackDidChange(to: newValue)
            }
        }
    }

    /// Pure frosted-glass card: NSVisualEffectView refracts the lock screen wallpaper with no dark underlay;
    /// top highlight stroke simulates a glass edge. Lower alpha makes the wallpaper bleed through more visibly.
    private var glassBackground: some View {
        VisualEffectBackground(alphaValue: 0.55)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.24), location: 0),
                                .init(color: .white.opacity(0.08), location: 0.5),
                                .init(color: .white.opacity(0.03), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
    }

    private func statusItem(symbol: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .medium))
        }
    }

    private func artwork(for item: NowPlayingSnapshot) -> some View {
        Group {
            if let image = MediaArtworkImageCache.image(from: item.artworkData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.12))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func controls(for item: NowPlayingSnapshot) -> some View {
        HStack(spacing: 18) {
            if item.supportsPlaybackModeControl, let playbackMode = item.playbackMode {
                if item.playbackModeIsApproximate {
                    controlButton(
                        symbol: playbackMode.symbol,
                        isActive: playbackMode != .sequential
                    ) {
                        _ = media.cyclePlaybackMode()
                    }
                } else {
                    PlaybackModeMenu(mode: playbackMode) { mode in
                        _ = media.setPlaybackMode(mode)
                    }
                }
            }
            controlButton(symbol: "backward.fill") {
                _ = media.send(.previous)
            }
            controlButton(
                symbol: item.isPlaying ? "pause.fill" : "play.fill"
            ) {
                _ = media.send(.togglePlayPause)
            }
            controlButton(symbol: "forward.fill") {
                _ = media.send(.next)
            }
            controlButton(
                symbol: item.isFavorite == true ? "heart.fill" : "heart",
                isActive: item.isFavorite == true,
                activeColor: Color(red: 1, green: 106.0 / 255, blue: 106.0 / 255)
            ) {
                _ = media.toggleFavorite()
            }
        }
    }

    /// Merges title and artist into a single "title · artist" line; shows only the title when artist is empty or same as title.
    nonisolated private static func titleArtistText(_ item: NowPlayingSnapshot) -> String {
        MediaTextFormatting.titleArtistText(item)
    }

    /// Current lyrics line, scrolling horizontally when too long (marquee); advances with playback progress.
    @ViewBuilder
    private func currentLyrics(_ item: NowPlayingSnapshot) -> some View {
        if item.isPlaying {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                lyricMarquee(currentLyricText(item, date: context.date))
            }
        } else {
            lyricMarquee(currentLyricText(item, date: .now))
        }
    }

    private func lyricMarquee(_ text: String) -> some View {
        MarqueeText(
            text,
            font: .system(size: 11, weight: .medium),
            textColor: .white.opacity(0.60)
        )
    }

    private func currentLyricText(_ item: NowPlayingSnapshot, date: Date) -> String {
        // Prefer lyrics embedded in the snapshot; fall back to NowPlayingService's parsed lyric cache
        // if the snapshot doesn't carry them yet (e.g. lock screen just refreshed, applyLyrics not yet written back).
        MediaTextFormatting.lyricLine(
            item,
            lyrics: item.lyrics ?? media.resolvedLyrics,
            date: date
        )
    }

    /// Playback progress bar: advances in real time while playing; supports tap or drag to seek.
    @ViewBuilder
    private func playbackProgress(for item: NowPlayingSnapshot) -> some View {
        if let duration = item.duration, duration > 0 {
            if item.isPlaying {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    playbackProgressRow(item, duration: duration, at: context.date)
                }
            } else {
                playbackProgressRow(item, duration: duration, at: .now)
            }
        }
    }

    private func playbackProgressRow(
        _ item: NowPlayingSnapshot,
        duration: Double,
        at date: Date
    ) -> some View {
        let elapsed = min(max(
            scrubState.time
                ?? item.elapsedTime(at: date)
                ?? item.elapsedTime ?? 0,
            0
        ), duration)
        let fraction = duration > 0 ? min(1, max(0, CGFloat(elapsed / duration))) : 0
        return HStack(spacing: 8) {
            Text(timeText(elapsed))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .monospacedDigit()
                .fixedSize()

            GeometryReader { geo in
                let trackHeight: CGFloat = 3
                let thumbDiameter = min(CGFloat(9), geo.size.width)
                let thumbCenter = min(
                    max(thumbDiameter / 2, geo.size.width * fraction),
                    geo.size.width - thumbDiameter / 2
                )
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.18))
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(.white.opacity(0.88))
                        .frame(width: max(0, geo.size.width * fraction), height: trackHeight)
                    if duration > 0, thumbDiameter > 0 {
                        Circle()
                            .fill(.white.opacity(0.96))
                            .overlay(
                                Circle()
                                    .stroke(.black.opacity(0.34), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
                            .frame(width: thumbDiameter, height: thumbDiameter)
                            .offset(x: thumbCenter - thumbDiameter / 2)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            guard duration > 0, geo.size.width > 0 else { return }
                            let track = MediaScrubTrack(item)
                            scrubState.scrubIfNeeded(for: track)
                            let ratio = max(0, min(1, Double(value.location.x / geo.size.width)))
                            scrubState.update(time: ratio * duration, for: track)
                        }
                        .onEnded { value in
                            guard duration > 0, geo.size.width > 0 else { return }
                            let track = MediaScrubTrack(item)
                            scrubState.scrubIfNeeded(for: track)
                            let ratio = max(0, min(1, Double(value.location.x / geo.size.width)))
                            scrubState.update(time: ratio * duration, for: track)
                            if let final = scrubState.finish(for: track) {
                                _ = media.seek(to: final)
                            }
                        }
                )
            }
            .frame(height: 9)

            Text(timeText(duration))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .monospacedDigit()
                .fixedSize()
        }
    }

    private func controlButton(
        symbol: String,
        prominent: Bool = false,
        isActive: Bool = false,
        activeColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 17 : 13, weight: .semibold))
                .foregroundStyle(isActive ? (activeColor ?? .white) : .white)
                .frame(width: prominent ? 40 : 30, height: prominent ? 40 : 30)
                .background(
                    Circle().fill(
                        prominent
                            ? .white.opacity(0.20)
                            : (isActive ? (activeColor ?? .white).opacity(0.18) : .clear)
                    )
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    private func batteryDetail(_ battery: BatterySnapshot) -> String {
        BatteryLocalization.detailStatusText(battery, locale: locale)
    }

    private func timeText(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
