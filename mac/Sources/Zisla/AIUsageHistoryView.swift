import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit

@MainActor
final class AIUsageHistoryController: ObservableObject {
    enum Action { case export, clear }

    @Published private(set) var history = AIUsageHistory()
    @Published private(set) var loadState: AIUsageHistoryState = .idle
    @Published private(set) var action: Action?
    @Published private(set) var statusMessage: String?
    private let read: () async throws -> AIUsageHistory
    private let clear: () async throws -> Void
    private let write: (AIUsageHistory, URL) async throws -> Void
    private var generation: UInt64 = 0
    private var readTask: Task<AIUsageHistory, any Error>?
    private var exportTask: Task<Void, any Error>?
    private var revisionObservation: AnyCancellable?

    convenience init(monitor: AIStateMonitor) {
        self.init(read: { try await monitor.readUsageHistory() }, clear: { try await monitor.clearUsageHistory() },
            write: AIUsageHistoryExporter.write)
        revisionObservation = monitor.$usageHistoryRevision.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in await self?.load() }
        }
    }

    /// Injected actions keep save-panel and database failures testable without opening windows or touching user data.
    init(read: @escaping () async throws -> AIUsageHistory, clear: @escaping () async throws -> Void,
        write: @escaping (AIUsageHistory, URL) async throws -> Void) {
        self.read = read
        self.clear = clear
        self.write = write
    }

    var isBusy: Bool { action != nil }
    var isLoading: Bool { loadState == .loading }

    /// Only the newest request can publish, including when a clear or cancelled window task supersedes a read.
    func load() async {
        guard !isBusy else { return }
        readTask?.cancel()
        generation &+= 1
        let request = generation
        let previousState = loadState
        loadState = .loading
        let read = read
        let work = Task { try await read() }
        readTask = work
        do {
            let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            try Task.checkCancellation()
            guard request == generation else { return }
            history = result
            loadState = .loaded
            statusMessage = nil
        } catch is CancellationError {
            guard request == generation else { return }
            loadState = previousState == .loaded ? .loaded : .idle
        } catch {
            guard request == generation else { return }
            loadState = .failed(error.localizedDescription)
        }
        if request == generation { readTask = nil }
    }

    /// Clears a shared preview or persisted report without allowing a previously loaded snapshot to reappear.
    func clearHistory() async {
        guard !isBusy else { return }
        action = .clear
        let previousState = loadState
        readTask?.cancel()
        readTask = nil
        generation &+= 1
        do {
            try await clear()
            history = AIUsageHistory()
            loadState = .loaded
            statusMessage = AppLocalization.text("已清空 AI 用量历史")
        } catch {
            loadState = previousState == .loading ? (history.usageSamples.isEmpty ? .idle : .loaded) : previousState
            statusMessage = AppLocalization.text("清空失败：%@", error.localizedDescription)
        }
        action = nil
    }

    /// Reads a fresh committed snapshot so reopening settings or changing the selected day cannot truncate the export.
    func export(to destination: URL) async {
        guard !isBusy, !isLoading, !history.usageSamples.isEmpty else { return }
        action = .export
        statusMessage = nil
        let write = write
        let read = read
        let work = Task {
            let snapshot = try await read()
            try Task.checkCancellation()
            history = snapshot
            loadState = .loaded
            guard !snapshot.usageSamples.isEmpty else { return }
            try await write(snapshot, destination)
            try Task.checkCancellation()
        }
        exportTask = work
        do {
            try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            try Task.checkCancellation()
            if !history.usageSamples.isEmpty { statusMessage = AppLocalization.text("已保存到 %@", destination.path) }
        } catch is CancellationError {
            statusMessage = nil
        } catch {
            statusMessage = AppLocalization.text("导出失败：%@", error.localizedDescription)
        }
        exportTask = nil
        action = nil
    }

    func cancelExport() { exportTask?.cancel() }
}

struct AIUsageHistoryPanelPresenter: NSViewRepresentable {
    @ObservedObject var presentationState: SystemMetricsHistoryPanelPresentationState
    let controller: AIUsageHistoryController
    let languageStore: AppLanguageStore

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(requestID: presentationState.requestID, dismiss: presentationState.dismiss,
            controller: controller, languageStore: languageStore, hostWindow: nsView.window)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.dismiss() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private var window: SystemMetricsHistoryPanel?
        private var handledRequestID: UUID?
        private var awaitingDismissal = false

        init(window: SystemMetricsHistoryPanel? = nil) { self.window = window }

        func update(requestID: UUID?, dismiss: @escaping () -> Void, controller: AIUsageHistoryController,
            languageStore: AppLanguageStore, hostWindow: NSWindow?) {
            guard let requestID else { awaitingDismissal = false; self.dismiss(); return }
            if window == nil {
                let window = SystemMetricsHistoryPanel(contentRect: CGRect(x: 0, y: 0, width: 760, height: 640),
                    styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
                window.title = AppLocalization.text("AI 用量历史")
                window.isReleasedWhenClosed = false
                window.hidesOnDeactivate = false
                window.level = .normal
                window.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]
                window.minSize = CGSize(width: 620, height: 480)
                window.contentView = NSHostingView(rootView: AppLanguageEnvironment(languageStore: languageStore,
                    content: AIUsageHistoryContent(controller: controller)))
                self.window = window
            }
            guard let window else { return }
            window.onCancel = { [weak self, weak window] in
                self?.awaitingDismissal = true
                dismiss()
                window?.orderOut(nil)
            }
            let isNewRequest = requestID != handledRequestID
            handledRequestID = requestID
            guard isNewRequest || SystemCleanupPanel.shouldOrderFront(isVisible: window.isVisible,
                isMiniaturized: window.isMiniaturized, isAwaitingDismissalState: awaitingDismissal) else { return }
            WindowPlacement.center(window, on: hostWindow?.screen)
            window.present(over: hostWindow)
        }

        func dismiss() { window?.orderOut(nil); window = nil }
    }
}

struct AIUsageHistorySettingsActions: View {
    @ObservedObject var controller: AIUsageHistoryController
    var showHistory: () -> Void
    @State private var confirmsClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(AppLocalization.text("查看历史记录"), action: showHistory)
                Button(AppLocalization.text("导出")) {
                    if let destination = AIUsageHistoryExporter.chooseDestination() {
                        Task { await controller.export(to: destination) }
                    }
                }
                .disabled(controller.isLoading || controller.isBusy || controller.history.usageSamples.isEmpty)
                .help(AppLocalization.text("把全部 AI 用量历史导出为 xlsx 表格"))
                Button(AppLocalization.text("清空"), role: .destructive) { confirmsClear = true }
                    .disabled(controller.isLoading || controller.isBusy || controller.history.usageSamples.isEmpty)
                Spacer()
                if controller.isLoading || controller.isBusy { ProgressView().controlSize(.small) }
                if controller.action == .export { Button(AppLocalization.text("取消")) { controller.cancelExport() } }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if case let .failed(message) = controller.loadState {
                Text(message).font(.system(size: 11)).foregroundStyle(.red)
                Button(AppLocalization.text("重试")) { Task { await controller.load() } }
            } else if let message = controller.statusMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .task { await controller.load() }
        .confirmationDialog(AppLocalization.text("清空 AI 用量历史？"), isPresented: $confirmsClear, titleVisibility: .visible) {
            Button(AppLocalization.text("清空"), role: .destructive) { Task { await controller.clearHistory() } }
            Button(AppLocalization.text("取消"), role: .cancel) {}
        } message: { Text(AppLocalization.text("删除本机保存的 AI 用量历史，保留任务和日志去重记录。此操作无法撤销。")) }
    }
}

struct AIUsageHistoryContent: View {
    @ObservedObject var controller: AIUsageHistoryController
    var now: () -> Date = { .now }
    @Environment(\.locale) private var locale
    @State private var range: SystemMetricsHistoryRange = .default
    @State private var selectedDate: Date?
    @State private var heatmapYear = Calendar.current.startOfDay(for: Date())
    @State private var confirmsClear = false

    private var domain: ClosedRange<Date> {
        AIUsageHistoryPresentation.domain(history: controller.history, range: range, now: now())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppLocalization.string("AI 用量历史", locale: locale)).font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(AppLocalization.string("清空", locale: locale), role: .destructive) { confirmsClear = true }
                    .disabled(controller.isBusy || controller.isLoading || controller.history.usageSamples.isEmpty)
                Button(AppLocalization.string("导出", locale: locale)) {
                    if let destination = AIUsageHistoryExporter.chooseDestination() {
                        Task { await controller.export(to: destination) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isBusy || controller.isLoading || controller.history.usageSamples.isEmpty)
            }
            .controlSize(.small)
            HStack {
                Text(AppLocalization.string("时间范围", locale: locale)).font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("", selection: $range) {
                    ForEach(SystemMetricsHistoryRange.allCases, id: \.self) { range in
                        Text(AppLocalization.string(range.titleKey, locale: locale)).tag(range)
                    }
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 280)
                Spacer()
                IconButton(symbol: "arrow.clockwise", help: AppLocalization.string("刷新", locale: locale), size: .compact) {
                    Task { await controller.load() }
                }.disabled(controller.isLoading || controller.isBusy)
            }
            Divider()
            if controller.isLoading, controller.history.usageSamples.isEmpty {
                ProgressView(AppLocalization.string("正在读取历史记录", locale: locale)).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if case let .failed(message) = controller.loadState {
                            Text(message).foregroundStyle(.red)
                            Button(AppLocalization.string("重试", locale: locale)) { Task { await controller.load() } }
                        }
                        if range == .day {
                            Button { selectedDate = domain.lowerBound } label: {
                                Text(domain.lowerBound, format: .dateTime.year().month().day())
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: selectedDate == nil ? .regular : .semibold))
                            .foregroundStyle(selectedDate == nil ? Color.primary : Color.accentColor)
                            .accessibilityLabel(AppLocalization.string("日期", locale: locale))
                        } else {
                            UsageTrendChart(series: AIUsageHistoryPresentation.trend(history: controller.history, domain: domain),
                                selectedDate: $selectedDate, domain: domain).frame(height: 180)
                            heatmap
                        }
                        if let selectedDate {
                            DailyModelUsageList(day: AIUsageHistoryPresentation.selectedDay(in: controller.history, date: selectedDate))
                        }
                    }
                    .padding(.horizontal, NSScroller.scrollerWidth(for: .mini, scrollerStyle: .overlay))
                    .padding(.bottom, 4)
                }.thinScrollChrome(scrollerStyle: .overlay)
            }
            HStack {
                Text(controller.statusMessage ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if controller.isBusy || controller.isLoading { ProgressView().controlSize(.small) }
                if controller.action == .export { Button(AppLocalization.string("取消", locale: locale)) { controller.cancelExport() } }
            }.frame(height: 18)
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await controller.load() }
        .onChange(of: domain) { _, domain in
            if let selectedDate, selectedDate < domain.lowerBound || selectedDate >= domain.upperBound {
                self.selectedDate = nil
            }
        }
        .onChange(of: selectedDate) { _, date in if let date { heatmapYear = date } }
        .confirmationDialog(AppLocalization.string("清空 AI 用量历史？", locale: locale), isPresented: $confirmsClear, titleVisibility: .visible) {
            Button(AppLocalization.string("清空", locale: locale), role: .destructive) { Task { await controller.clearHistory() } }
            Button(AppLocalization.string("取消", locale: locale), role: .cancel) {}
        } message: { Text(AppLocalization.string("删除本机保存的 AI 用量历史，保留任务和日志去重记录。此操作无法撤销。", locale: locale)) }
    }

    private var heatmap: some View {
        let year = range == .all ? heatmapYear : nil
        let weeks = AIUsageHistoryPresentation.heatmap(history: controller.history, domain: domain, year: year, now: .now)
        return VStack(alignment: .leading, spacing: 8) {
            if range == .all {
                HStack {
                    Button { shiftHeatmapYear(-1) } label: { Image(systemName: "chevron.left") }
                        .help(AppLocalization.string("上一年", locale: locale))
                        .disabled(!canShiftHeatmapYear(-1))
                    Text(heatmapYear, format: .dateTime.year()).font(.system(size: 11, weight: .medium))
                    Button { shiftHeatmapYear(1) } label: { Image(systemName: "chevron.right") }
                        .help(AppLocalization.string("下一年", locale: locale))
                        .disabled(!canShiftHeatmapYear(1))
                    Spacer()
                }.buttonStyle(.plain)
            }
            if range == .week {
                UsageHeatmap(weeks: weeks, selectedDate: $selectedDate, cellSize: 12, layout: .days)
            } else {
                ScrollView(.horizontal) {
                    UsageHeatmap(weeks: weeks, selectedDate: $selectedDate, cellSize: 12)
                        .padding(.bottom, NSScroller.scrollerWidth(for: .mini, scrollerStyle: .overlay))
                }.thinScrollChrome(visibleWhenScrollable: false, scrollerStyle: .overlay)
            }
        }
    }

    private func canShiftHeatmapYear(_ offset: Int) -> Bool {
        guard let year = Calendar.current.date(byAdding: .year, value: offset, to: heatmapYear),
              let interval = Calendar.current.dateInterval(of: .year, for: year) else { return false }
        return interval.end > domain.lowerBound && interval.start < domain.upperBound
    }

    private func shiftHeatmapYear(_ offset: Int) {
        if let next = Calendar.current.date(byAdding: .year, value: offset, to: heatmapYear) { heatmapYear = next }
    }
}

@MainActor
enum AIUsageHistoryExporter {
    static func chooseDestination(now: Date = Date()) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: AIUsageHistoryExport.fileExtension) ?? .data]
        panel.nameFieldStringValue = AIUsageHistoryExport.defaultFileName(now: now)
        panel.canCreateDirectories = true
        panel.prompt = AppLocalization.text("导出")
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Both workbook generation and atomic writing run away from AppKit, with scoped folder access always released.
    static func write(history: AIUsageHistory, to destination: URL) async throws {
        let work = Task.detached(priority: .utility) {
            let data = try AIUsageHistoryExport.workbookData(history: history)
            try Task.checkCancellation()
            let directory = destination.deletingLastPathComponent()
            let scoped = directory.startAccessingSecurityScopedResource()
            defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
            try data.write(to: destination, options: .atomic)
        }
        try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
}
