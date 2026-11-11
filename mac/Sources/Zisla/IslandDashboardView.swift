import SwiftUI
import ZislaCore
import ZislaKit

struct IslandDashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var pomodoro: PomodoroService
    @ObservedObject private var aiMonitor: AIStateMonitor
    @ObservedObject private var media: NowPlayingService
    @ObservedObject private var browserDownloads: BrowserDownloadMonitor
    @ObservedObject private var notices: SideNoticeQueue

    init(model: AppModel) {
        _model = ObservedObject(wrappedValue: model)
        _pomodoro = ObservedObject(wrappedValue: model.pomodoro)
        _aiMonitor = ObservedObject(wrappedValue: model.aiMonitor)
        _media = ObservedObject(wrappedValue: model.media)
        _browserDownloads = ObservedObject(wrappedValue: model.browserDownloads)
        _notices = ObservedObject(wrappedValue: model.notices)
    }

    var body: some View {
        Group {
            if activeCardCount > 0 {
                ScrollView(.vertical) {
                    dynamicCards
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.visible)
                .thinScrollChrome(visibleWhenScrollable: true)
            }
        }
        .onChange(of: activeCardCount, initial: true) { _, count in
            model.synchronizeDashboardCardCount(count)
        }
    }

    private var dynamicCards: some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            if isPomodoroActive {
                focusCard.transition(cardTransition)
            }
            ForEach(aiWorkSummaries) { summary in
                aiCard(summary).transition(cardTransition)
            }
            if activeMediaItem != nil {
                mediaCard.transition(cardTransition)
            }
            if isDownloadActive {
                transferCard.transition(cardTransition)
            }
            if model.settingsStore.settings.showsBrowserDownloadProgress {
                ForEach(browserDownloads.snapshots) { snapshot in
                    browserDownloadCard(snapshot).transition(cardTransition)
                }
            }
            ForEach(notices.screenRecordingOperations) { notice in
                screenRecordingOperationCard(notice).transition(cardTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // Matches the island's surface resize spring, since card changes also drive panel height.
        .animation(ZislaMotion.surfaceResize, value: activeCardCount)
    }

    private var cardTransition: AnyTransition {
        .scale(scale: 0.92).combined(with: .opacity)
    }

    private var focusCard: some View {
        dashboardCard(
            symbol: "timer",
            title: pomodoro.mode == .focus ? AppLocalization.text("专注倒计时") : AppLocalization.text("休息倒计时"),
            tint: pomodoro.phase == .running ? Color.zislaWarning : .secondary
        ) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(pomodoro.displayClock)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(pomodoroPhaseText)
                    .font(.islandMicro(weight: .semibold))
                    .foregroundStyle(.secondary)
                    .fitsSingleLine()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func aiCard(_ summary: DashboardAIWorkSummary) -> some View {
        dashboardCard(symbol: "sparkles", title: AppLocalization.text("AI 工作"), tint: Color.zislaInfo) {
            DashboardAIWorkContent(summary: summary)
        }
    }

    private var transferCard: some View {
        dashboardCard(symbol: "arrow.down.circle", title: AppLocalization.text("下载进度"), tint: Color.zislaInfo) {
            switch model.downloadState {
            case .preparing:
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(AppLocalization.text("正在准备下载"))
                        .font(.system(size: 10, weight: .medium))
                }
            case let .downloading(fraction, speed, eta):
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Spacer(minLength: 4)
                        Text([speed, eta.isEmpty ? nil : AppLocalization.text("剩余 %@", eta)].compactMap { $0 }.joined(separator: " · "))
                            .font(.islandMicro(design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fitsSingleLine()
                    }
                    ProgressView(value: fraction)
                        .tint(Color.zislaInfo)
                }
            case .idle, .completed, .failed:
                EmptyView()
            }
        }
    }

    private var mediaCard: some View {
        dashboardCard(symbol: "music.note", title: AppLocalization.text("正在播放"), tint: Color.zislaInfo) {
            if let item = activeMediaItem {
                HStack(spacing: 7) {
                    mediaArtwork(item)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.isEmpty ? AppLocalization.text("媒体播放") : item.title)
                            .font(.system(size: 10, weight: .semibold))
                            .fitsSingleLine()
                        Text(mediaSecondaryText(item))
                            .font(.islandMicro())
                            .foregroundStyle(.secondary)
                            .fitsSingleLine()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture { _ = media.openSourceApplication() }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            activeMediaItem.map { AppLocalization.text("正在播放：%@", MediaTextFormatting.titleArtistText($0)) }
                ?? AppLocalization.text("正在播放")
        )
    }

    @ViewBuilder
    private func mediaArtwork(_ item: NowPlayingSnapshot) -> some View {
        if let image = MediaArtworkImageCache.image(
            from: item.artworkData,
            fallback: item.sourceIconData
        ) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .overlay {
                    Image(systemName: item.isVideo ? "play.rectangle.fill" : "music.note")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.zislaInfo)
                }
                .frame(width: 32, height: 32)
        }
    }

    private func mediaSecondaryText(_ item: NowPlayingSnapshot) -> String {
        let text = item.isVideo
            ? MediaTextFormatting.videoSecondaryText(item)
            : item.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "媒体播放" : text
    }

    private func browserDownloadCard(_ snapshot: BrowserDownloadSnapshot) -> some View {
        dashboardCard(
            symbol: snapshot.agent?.symbolName ?? "arrow.down.circle",
            title: snapshot.agent == .airDrop ? "AirDrop" : AppLocalization.text("浏览器下载"),
            tint: Color.zislaInfo
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(snapshot.agent?.displayName ?? AppLocalization.text("未知浏览器"))
                        .font(.islandMicro(weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fitsSingleLine()
                    Text(snapshot.fileName)
                        .font(.system(size: 10, weight: .semibold))
                        .fitsSingleLine()
                        .truncationMode(.middle)
                }

                HStack(spacing: 6) {
                    if let fraction = snapshot.fraction {
                        ProgressView(value: fraction)
                            .tint(snapshot.isFinished ? Color.zislaSuccess : Color.zislaInfo)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text(snapshot.progressText)
                        .font(.islandMicro(weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            snapshot.agent == .airDrop
                ? AppLocalization.text("%@ 下载中 %@：%@", "AirDrop", snapshot.progressText, snapshot.fileName)
                : AppLocalization.text("浏览器下载：%@，%@，%@", snapshot.agent?.displayName ?? AppLocalization.text("未知浏览器"), snapshot.fileName, snapshot.progressText)
        )
    }

    private func screenRecordingOperationCard(_ notice: IslandNotice) -> some View {
        dashboardCard(symbol: notice.symbolName ?? "film", title: notice.title,
                      tint: notice.kind == .error ? Color.zislaError : Color.zislaInfo) {
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.detail ?? "")
                    .font(.system(size: 10, weight: .semibold))
                    .fitsSingleLine()
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if notice.kind == .info {
                        if let progress = notice.progress {
                            ProgressView(value: progress).tint(Color.zislaInfo)
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                    } else {
                        Image(systemName: notice.kind == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(notice.kind == .success ? Color.zislaSuccess : Color.zislaError)
                    }
                    Text(ScreenRecordingOperationNotice.progressText(for: notice))
                        .font(.islandMicro(weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .help([notice.title, notice.detail, ScreenRecordingOperationNotice.progressText(for: notice)]
            .compactMap { $0 }.joined(separator: " · "))
    }

    private func dashboardCard<Content: View>(
        symbol: String,
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.islandMicro(weight: .semibold))
                .foregroundStyle(tint)
                .fitsSingleLine()

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(
            maxWidth: .infinity,
            minHeight: IslandDashboardLayout.cardHeight,
            maxHeight: IslandDashboardLayout.cardHeight,
            alignment: .topLeading
        )
    }

    private var aiWorkSummaries: [DashboardAIWorkSummary] {
        DashboardAIWorkSummary.groups(
            from: aiMonitor.state.tasks,
            enabled: model.settingsStore.settings.aiProgressEnabled
        )
    }

    private var activeMediaItem: NowPlayingSnapshot? {
        guard model.settingsStore.settings.mediaEnabled,
              let snapshot = media.snapshot,
              snapshot.isPlaying
        else { return nil }
        return snapshot
    }

    private var isPomodoroActive: Bool {
        pomodoro.phase != .idle
    }

    private var isDownloadActive: Bool {
        model.hasActiveDownloads
    }

    private var activeCardCount: Int {
        [
            isPomodoroActive,
            activeMediaItem != nil,
            isDownloadActive,
        ].filter { $0 }.count + aiWorkSummaries.count + (
            model.settingsStore.settings.showsBrowserDownloadProgress
                ? browserDownloads.snapshots.count : 0
        ) + notices.screenRecordingOperations.count
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: activeCardCount == 1 ? 1 : 2
        )
    }

    private var pomodoroPhaseText: String {
        switch pomodoro.phase {
        case .running: "进行中"
        case .paused: "已暂停"
        case .idle: "待开始"
        }
    }
}

struct DashboardAIWorkSummary: Identifiable {
    let task: AIProgressTask
    let count: Int

    var identity: AIMascotIdentity {
        AIMascotIdentity(provider: task.provider, taskID: task.id, title: task.title)
    }

    var id: String { identity.displayName }
    var title: String { count == 1 ? task.title : id }
    var progress: Double? { count == 1 ? task.progress : nil }

    func statusText(locale: Locale) -> String {
        let status = AppLocalization.string("正在运行", locale: locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(count) \(status)"
    }

    static func groups(from tasks: [AIProgressTask], enabled: Bool) -> [Self] {
        guard enabled else { return [] }
        let runningTasks = tasks.filter { $0.status == .running }
            .sorted { $0.updatedAt > $1.updatedAt }
        return Dictionary(grouping: runningTasks) {
            AIMascotIdentity(provider: $0.provider, taskID: $0.id, title: $0.title).displayName
        }.values.map { Self(task: $0[0], count: $0.count) }
            .sorted {
                if $0.task.updatedAt == $1.task.updatedAt { return $0.id < $1.id }
                return $0.task.updatedAt > $1.task.updatedAt
            }
    }
}

struct DashboardAIWorkContent: View {
    let summary: DashboardAIWorkSummary
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 7) {
            AIMascotView(identity: summary.identity, size: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(.system(size: 10, weight: .semibold))
                    .fitsSingleLine()

                if let progress = summary.progress {
                    ProgressView(value: progress)
                        .tint(ProviderBrand.color(for: summary.task.provider))
                } else {
                    Text(summary.statusText(locale: locale))
                        .font(.islandMicro())
                        .foregroundStyle(.secondary)
                }
            }

            if let progress = summary.progress {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.islandMicro(weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
