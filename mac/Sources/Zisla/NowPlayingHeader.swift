import AppKit
import ZislaCore
import ZislaKit
import SwiftUI

struct NowPlayingHeader: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var media: NowPlayingService
    @ObservedObject private var aiMonitor: AIStateMonitor
    @StateObject private var scrubState = MediaScrubState()

    init(model: AppModel) {
        _model = ObservedObject(wrappedValue: model)
        _media = ObservedObject(wrappedValue: model.media)
        _aiMonitor = ObservedObject(wrappedValue: model.aiMonitor)
    }

    var body: some View {
        Group {
            if model.settingsStore.settings.mediaEnabled, let item = media.snapshot {
                playingContent(item)
            } else {
                idleContent
            }
        }
        .frame(height: 72)
    }

    private func playingContent(_ item: NowPlayingSnapshot) -> some View {
        let track = MediaScrubTrack(item)
        return Group {
            if model.settingsStore.settings.mediaShowLyricsAndInfo {
                detailedPlayingContent(item)
            } else {
                compactPlayingContent(item)
            }
        }
        .onChange(of: track, initial: true) { _, newValue in
            scrubState.trackDidChange(to: newValue)
        }
    }

    /// 展示歌词与歌曲信息：左侧图标，右侧纵向排列「歌名 · 歌手」（上）与歌词（下）；
    /// 歌词置于歌名与歌手下方、进度条上方。最右侧保留音浪与播放控制。
    /// 歌名·歌手 / 歌词过长时自动水平滚动（见 `MarqueeText`）。
    private func detailedPlayingContent(_ item: NowPlayingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                artwork(item)

                // 歌名·歌手（上）+ 歌词（下），纵向紧贴图标右侧
                VStack(alignment: .leading, spacing: 3) {
                    MarqueeText(
                        Self.titleArtistText(item),
                        font: .system(size: 13, weight: .semibold),
                        textColor: .primary
                    )
                    .layoutPriority(2)
                    .help("打开播放软件")
                    .contentShape(Rectangle())
                    .onTapGesture(perform: openSourceApplication)

                    currentLyrics(item)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MediaWaveformView(
                    artworkData: item.artworkData,
                    width: 34,
                    height: 28,
                    isActive: item.isPlaying && model.isIslandVisible
                )

                if item.supportsControls {
                    controls(item)
                }
            }

            progressBar(item)
        }
    }

    /// 播放进度条：左侧当前时间、中间进度、右侧总时长；播放时实时推进，
    /// 并支持点击或拖动调整进度。
    private func progressBar(_ item: NowPlayingSnapshot) -> some View {
        let track = MediaScrubTrack(item)
        return TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = item.duration ?? 0
            let elapsed = scrubState.time
                ?? item.elapsedTime(at: context.date)
                ?? item.elapsedTime ?? 0
            let fraction = duration > 0 ? min(1, max(0, CGFloat(elapsed / duration))) : 0
            HStack(spacing: 8) {
                Text(timeText(elapsed))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()

                GeometryReader { geo in
                    // 轨道固定 2pt；容器高度给圆点（9pt）与拖动手势，避免 Capsule 被圆点撑粗。
                    let trackHeight: CGFloat = 2
                    let thumbDiameter = min(CGFloat(9), geo.size.width)
                    let thumbCenter = min(
                        max(thumbDiameter / 2, geo.size.width * fraction),
                        geo.size.width - thumbDiameter / 2
                    )
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.25))
                            .frame(height: trackHeight)
                        Capsule()
                            .fill(Color.accentColor)
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
                                scrubState.scrubIfNeeded(for: track)
                                let ratio = max(0, min(1, Double(value.location.x / geo.size.width)))
                                scrubState.update(time: ratio * duration, for: track)
                            }
                            .onEnded { value in
                                guard duration > 0, geo.size.width > 0 else { return }
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
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }

    /// 简略模式：仅图标与音浪（加播放控制），不展示歌名、歌手与歌词，
    /// 紧凑居中，不撑满宽度以免中间留出大段空白。
    private func compactPlayingContent(_ item: NowPlayingSnapshot) -> some View {
        HStack(spacing: 10) {
            artwork(item)
            MediaWaveformView(
                artworkData: item.artworkData,
                width: 34,
                height: 28,
                isActive: item.isPlaying && model.isIslandVisible
            )
            if item.supportsControls {
                controls(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func controls(_ item: NowPlayingSnapshot) -> some View {
        HStack(spacing: 2) {
            if item.supportsPlaybackModeControl, let playbackMode = item.playbackMode {
                if item.playbackModeIsApproximate {
                    IconButton(
                        symbol: playbackMode.symbol,
                        help: "切换播放模式",
                        isActive: playbackMode != .sequential,
                        size: .compact
                    ) {
                        _ = media.cyclePlaybackMode()
                    }
                } else {
                    PlaybackModeMenu(mode: playbackMode) { mode in
                        _ = media.setPlaybackMode(mode)
                    }
                }
            }
            if item.favoriteControl != nil, item.isFavorite != nil {
                IconButton(
                    symbol: item.isFavorite == true ? "heart.fill" : "heart",
                    help: item.isFavorite == true ? "取消收藏" : "添加收藏",
                    isActive: item.isFavorite == true,
                    activeColor: Color(red: 1, green: 106.0 / 255, blue: 106.0 / 255),
                    size: .compact
                ) {
                    _ = media.toggleFavorite()
                }
            }
            IconButton(symbol: "backward.fill", help: "上一首", size: .compact) {
                _ = media.send(.previous)
            }
            IconButton(
                symbol: item.isPlaying ? "pause.fill" : "play.fill",
                help: item.isPlaying ? "暂停" : "播放",
                size: .compact
            ) {
                _ = media.send(.togglePlayPause)
            }
            IconButton(symbol: "forward.fill", help: "下一首", size: .compact) {
                _ = media.send(.next)
            }
        }
    }

    /// 将歌名与歌手合并为一行「歌名 · 歌手」；歌手为空或与歌名相同时只显示歌名。
    nonisolated private static func titleArtistText(_ item: NowPlayingSnapshot) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = item.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if artist.isEmpty || artist.compare(title, options: .caseInsensitive) == .orderedSame {
            return title
        }
        return "\(title) · \(artist)"
    }

    /// 使用系统 MediaRemote 返回的节目名和演员，去重后展示。
    nonisolated private static func videoSecondaryText(_ item: NowPlayingSnapshot) -> String {
        let album = item.album?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = item.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts: [String]
        if album.isEmpty {
            parts = artist.isEmpty ? [] : [artist]
        } else if artist.isEmpty
            || artist.compare(album, options: .caseInsensitive) == .orderedSame {
            parts = [album]
        } else {
            parts = [album, artist]
        }
        guard !parts.isEmpty else { return "视频正在播放" }
        return parts.joined(separator: " · ")
    }

    private func currentLyricText(_ item: NowPlayingSnapshot, date: Date) -> String {
        if item.isVideo {
            return Self.videoSecondaryText(item)
        }
        let elapsed = item.elapsedTime(at: date) ?? 0
        return if let lyrics = item.lyrics {
            lyrics.currentLine(at: elapsed) ?? "歌词即将开始"
        } else {
            "暂无同步歌词"
        }
    }

    /// 当前歌词行，过长时水平滚动（跑马灯）。点击跳转到播放软件。
    /// 不论灵动岛是否展开，只要正在播放就随进度推进歌词（收起态也滚动）。
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

    @ViewBuilder
    private func lyricMarquee(_ text: String) -> some View {
        MarqueeText(
            text,
            font: .system(size: 10.5, weight: .medium),
            textColor: .secondary
        )
        .help("打开播放软件")
        .contentShape(Rectangle())
        .onTapGesture(perform: openSourceApplication)
    }

    private var idleContent: some View {
        HStack(spacing: 12) {
            if let task = activeAITask {
                aiStatusContent(task)
            } else if let weather = model.weather, model.settingsStore.settings.weatherEnabled {
                weatherContent(weather)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .semibold))
                    Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            Spacer()
            Text(Date.now, format: .dateTime.hour().minute())
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private func aiStatusContent(_ task: AIProgressTask) -> some View {
        HStack(spacing: 8) {
            AIMascotView(
                identity: AIMascotIdentity(provider: task.provider, taskID: task.id),
                size: 30
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text("\(task.provider.rawValue.uppercased()) \(statusText(for: task.status))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let progress = task.progress {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                if let detail = task.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.islandMicro())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
        }
    }

    private var activeAITask: AIProgressTask? {
        guard model.settingsStore.settings.aiProgressEnabled else { return nil }
        return aiMonitor.state.tasks
            .filter(\.status.isActive)
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    private func statusText(for status: AIProgressStatus) -> String {
        switch status {
        case .queued: "等待运行"
        case .running: "正在运行"
        case .blocked: "等待操作"
        case .error: "遇到错误"
        case .succeeded: "已完成"
        case .failed: "执行失败"
        }
    }

    private func weatherContent(_ weather: WeatherSnapshot) -> some View {
        HStack(spacing: 7) {
            Image(systemName: weather.condition.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(weather.temperature, specifier: "%.0f")°")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text([weather.locationName, weather.condition.summary]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func artwork(_ item: NowPlayingSnapshot) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = item.artworkData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.19, green: 0.22, blue: 0.26))
                    Image(systemName: item.isVideo ? "play.rectangle.fill" : "music.note")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(red: 0.54, green: 0.92, blue: 0.68))
                }
                .frame(width: 54, height: 54)
            }

            if let iconData = item.sourceIconData,
               let icon = NSImage(data: iconData) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .padding(3)
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("打开播放软件")
        .contentShape(Rectangle())
        .onTapGesture(perform: openSourceApplication)
    }

    private func openSourceApplication() {
        _ = media.openSourceApplication()
    }

    private func timeText(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

}

@MainActor
final class MediaScrubState: ObservableObject {
    @Published var time: Double?
    private var currentTrack: MediaScrubTrack?
    private var editingTrack: MediaScrubTrack?
    private var invalidated = false

    func trackDidChange(to track: MediaScrubTrack) {
        guard currentTrack != track else { return }
        currentTrack = track
        time = nil
        if editingTrack != nil { invalidated = true }
    }

    func begin(for track: MediaScrubTrack) {
        editingTrack = track
        invalidated = currentTrack != track
        time = nil
    }

    func scrubIfNeeded(for track: MediaScrubTrack) {
        guard editingTrack == track, !invalidated else {
            begin(for: track)
            return
        }
    }

    func update(time: Double, for track: MediaScrubTrack) {
        guard editingTrack == track, !invalidated else { return }
        self.time = time
    }

    func finish(for track: MediaScrubTrack) -> Double? {
        defer {
            editingTrack = nil
            invalidated = false
            time = nil
        }
        guard editingTrack == track, currentTrack == track, !invalidated else { return nil }
        return time
    }
}

struct MediaScrubTrack: Equatable {
    var title: String
    var artist: String
    var duration: Double?
    var sourcePID: pid_t?

    init(_ item: NowPlayingSnapshot) {
        title = item.title
        artist = item.artist
        duration = item.duration
        sourcePID = item.sourcePID
    }
}

struct PlaybackModeMenu: View {
    var mode: NowPlayingPlaybackMode
    var onSelect: (NowPlayingPlaybackMode) -> Void

    var body: some View {
        Menu {
            ForEach(NowPlayingPlaybackMode.allCases, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    Label(option.title, systemImage: option.symbol)
                }
            }
        } label: {
            IconButtonLabel(symbol: mode.symbol, isActive: mode != .sequential, size: .compact)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("播放模式：\(mode.title)")
    }
}

extension NowPlayingPlaybackMode {
    var title: String {
        switch self {
        case .sequential: "顺序播放"
        case .repeatOne: "单曲循环"
        case .random: "随机播放"
        }
    }

    var symbol: String {
        switch self {
        case .sequential: "list.number"
        case .repeatOne: "repeat.1"
        case .random: "shuffle"
        }
    }
}
