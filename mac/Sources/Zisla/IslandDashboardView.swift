import SwiftUI
import ZislaCore
import ZislaKit

struct IslandDashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var pomodoro: PomodoroService
    @ObservedObject private var aiMonitor: AIStateMonitor
    @ObservedObject private var browserDownloads: BrowserDownloadMonitor

    init(model: AppModel) {
        _model = ObservedObject(wrappedValue: model)
        _pomodoro = ObservedObject(wrappedValue: model.pomodoro)
        _aiMonitor = ObservedObject(wrappedValue: model.aiMonitor)
        _browserDownloads = ObservedObject(wrappedValue: model.browserDownloads)
    }

    var body: some View {
        Group {
            if activeCardCount > 0 {
                dynamicCards
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
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
            if activeAITask != nil {
                aiCard.transition(cardTransition)
            }
            if isDownloadActive {
                transferCard.transition(cardTransition)
            }
            ForEach(browserDownloads.snapshots) { snapshot in
                browserDownloadCard(snapshot).transition(cardTransition)
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
            title: pomodoro.mode == .focus ? "专注倒计时" : "休息倒计时",
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
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var aiCard: some View {
        dashboardCard(symbol: "sparkles", title: "AI 工作", tint: Color.zislaInfo) {
            if let task = activeAITask {
                HStack(spacing: 7) {
                    AIMascotView(
                        identity: AIMascotIdentity(provider: task.provider, taskID: task.id),
                        size: 24
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)

                        if let progress = task.progress {
                            ProgressView(value: progress)
                                .tint(ProviderBrand.color(for: task.provider))
                        } else {
                            Text(aiStatusText(for: task.status))
                                .font(.islandMicro())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let progress = task.progress {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.islandMicro(weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var transferCard: some View {
        dashboardCard(symbol: "arrow.down.circle", title: "下载进度", tint: Color.zislaInfo) {
            switch model.downloadState {
            case .preparing:
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("正在准备下载")
                        .font(.system(size: 10, weight: .medium))
                }
            case let .downloading(fraction, speed, eta):
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Spacer(minLength: 4)
                        Text([speed, eta.isEmpty ? nil : "剩余 \(eta)"].compactMap { $0 }.joined(separator: " · "))
                            .font(.islandMicro(design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    ProgressView(value: fraction)
                        .tint(Color.zislaInfo)
                }
            case .idle, .completed, .failed:
                EmptyView()
            }
        }
    }

    private func browserDownloadCard(_ snapshot: BrowserDownloadSnapshot) -> some View {
        dashboardCard(symbol: "arrow.down.circle", title: "浏览器下载", tint: Color.zislaInfo) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(snapshot.agent?.displayName ?? "未知浏览器")
                        .font(.islandMicro(weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(snapshot.fileName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
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
            "浏览器下载：\(snapshot.agent?.displayName ?? "未知浏览器")，\(snapshot.fileName)，\(snapshot.progressText)"
        )
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
                .lineLimit(1)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    }

    private var activeAITask: AIProgressTask? {
        guard model.settingsStore.settings.aiProgressEnabled else { return nil }
        return aiMonitor.state.tasks
            .filter(\.status.isActive)
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    private var isPomodoroActive: Bool {
        pomodoro.phase != .idle
    }

    private var isDownloadActive: Bool {
        switch model.downloadState {
        case .preparing, .downloading: true
        case .idle, .completed, .failed: false
        }
    }

    private var activeCardCount: Int {
        [
            isPomodoroActive,
            activeAITask != nil,
            isDownloadActive,
        ].filter { $0 }.count + browserDownloads.snapshots.count
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

    private func aiStatusText(for status: AIProgressStatus) -> String {
        switch status {
        case .queued: "等待运行"
        case .running: "正在运行"
        case .blocked: "等待操作"
        case .error, .failed: "需要处理"
        case .succeeded: "已完成"
        }
    }

}
