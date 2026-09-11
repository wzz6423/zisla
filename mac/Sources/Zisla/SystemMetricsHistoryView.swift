import AppKit
import Charts
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit
import SwiftUI

/// Drives the standalone history window from the island module, mirroring the disk-cleanup panel:
/// the island is a floating panel, so an attached sheet would be misplaced.
final class SystemMetricsHistoryPanelPresentationState: ObservableObject {
    @Published private(set) var isPresented = false

    func present() {
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}

struct SystemMetricsHistoryPanelPresenter: NSViewRepresentable {
    @ObservedObject var presentationState: SystemMetricsHistoryPanelPresentationState
    let service: SystemMonitorService

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            presenting: presentationState.isPresented,
            dismissPresentation: presentationState.dismiss,
            service: service,
            hostWindow: nsView.window
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        private var panel: SystemMetricsHistoryPanel?
        private var dismissPresentation: () -> Void = {}
        private var isAwaitingDismissalState = false

        func update(
            presenting: Bool,
            dismissPresentation: @escaping () -> Void,
            service: SystemMonitorService,
            hostWindow: NSWindow?
        ) {
            self.dismissPresentation = dismissPresentation
            guard presenting else {
                isAwaitingDismissalState = false
                dismiss()
                return
            }

            let panel = panel ?? makePanel(service: service)
            guard SystemCleanupPanel.shouldOrderFront(
                isVisible: panel.isVisible,
                isMiniaturized: panel.isMiniaturized,
                isAwaitingDismissalState: isAwaitingDismissalState
            ) else { return }
            WindowPlacement.center(panel, on: hostWindow?.screen)
            panel.orderFront(nil)
            AppModel.shared.islandCollapseRequested = true
        }

        func dismiss() {
            panel?.orderOut(nil)
            panel = nil
        }

        private func dismissFromPanel() {
            isAwaitingDismissalState = true
            dismissPresentation()
            panel?.orderOut(nil)
        }

        private func makePanel(service: SystemMonitorService) -> SystemMetricsHistoryPanel {
            let panel = SystemMetricsHistoryPanel(
                contentRect: CGRect(x: 0, y: 0, width: 720, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.title = AppLocalization.text("系统历史")
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.level = .normal
            panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
            panel.minSize = CGSize(width: 620, height: 420)
            let dismissPresentation = self.dismissPresentation
            let dismissPanel = { [weak self, weak panel] in
                guard let self else {
                    dismissPresentation()
                    panel?.orderOut(nil)
                    return
                }
                self.dismissFromPanel()
            }
            panel.contentView = NSHostingView(
                rootView: AppLanguageEnvironment(
                    languageStore: AppModel.shared.languageStore,
                    content: SystemMetricsHistoryContent(
                        service: service,
                        onHistoryCleared: {
                            AppModel.shared.islandCollapseRequested = true
                        }
                    )
                )
            )
            panel.onCancel = dismissPanel
            self.panel = panel
            return panel
        }
    }
}

@MainActor
final class SystemMetricsHistoryPanel: NSWindow {
    var onCancel: () -> Void = {}

    override func performClose(_ sender: Any?) {
        onCancel()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}

// MARK: - Content

/// History window: one chart row per category over a selectable time range, plus a spreadsheet export.
struct SystemMetricsHistoryContent: View {
    @ObservedObject var service: SystemMonitorService
    var onHistoryCleared: (() -> Void)?

    @State private var range: SystemMetricsHistoryRange = .default
    @State private var sections: [SystemMetricsChartSection] = []
    @State private var isLoading = true
    @State private var isExporting = false
    @State private var statusMessage: String?
    @State private var clearConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            content
            footer
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: range) { await loadSections() }
        .confirmationDialog(
            AppLocalization.text("清空历史记录？"),
            isPresented: $clearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.text("清空"), role: .destructive) {
                service.clearHistory()
                statusMessage = AppLocalization.text("已清空历史记录")
                onHistoryCleared?()
                Task { await loadSections() }
            }
        } message: {
            Text(AppLocalization.text("删除本机保存的全部历史读数，无法恢复。"))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLocalization.text("系统历史"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(historySummary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(AppLocalization.text("清空")) {
                    clearConfirmationPresented = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(service.historyStats.count == 0 || isExporting)
                Button(AppLocalization.text("导出")) {
                    export()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(service.historyStats.count == 0 || isExporting)
                .help(AppLocalization.text("把全部历史读数导出为 xlsx 表格"))
            }
            HStack(spacing: 10) {
                Text(AppLocalization.text("时间范围"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $range) {
                    ForEach(SystemMetricsHistoryRange.allCases, id: \.self) { value in
                        Text(AppLocalization.text(value.titleKey)).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280)
                Spacer()
                IconButton(
                    symbol: "arrow.clockwise",
                    help: AppLocalization.text("刷新"),
                    size: .compact
                ) {
                    Task { await loadSections() }
                }
                .disabled(isLoading || isExporting)
            }
        }
    }

    private var historySummary: String {
        let stats = service.historyStats
        guard stats.count > 0 else { return AppLocalization.text("暂无历史记录") }
        return SystemMetricsHistoryPresentation.spanText(stats.span)
    }

    // MARK: - Charts

    @ViewBuilder
    private var content: some View {
        if isLoading, sections.isEmpty {
            ProgressView(AppLocalization.text("正在读取历史记录"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sections.isEmpty {
            ContentUnavailableView(
                AppLocalization.text("暂无历史记录"),
                systemImage: "chart.xyaxis.line",
                description: Text(AppLocalization.text("在设置中开启「记录历史」后即可查看趋势"))
            )
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(sections) { section in
                        SystemMetricsChartCard(section: section)
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var footer: some View {
        HStack {
            Text(statusMessage ?? "")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fitsSingleLine()
            Spacer()
            if isExporting {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(height: 16)
    }

    // MARK: - Actions

    private func loadSections() async {
        isLoading = true
        await service.loadHistoryStats()
        sections = await service.historySections(range: range)
        isLoading = false
    }

    private func export() {
        guard let destination = SystemMetricsHistoryExporter.chooseDestination() else { return }
        isExporting = true
        statusMessage = nil
        Task { @MainActor in
            statusMessage = await SystemMetricsHistoryExporter.write(service: service, to: destination)
            isExporting = false
        }
    }
}

// MARK: - Export

/// Shared save flow for the history card and the history window: ask for a destination, then write
/// the workbook off the main thread because a week of samples is a few megabytes of XML.
@MainActor
enum SystemMetricsHistoryExporter {
    static func chooseDestination(now: Date = Date()) -> URL? {
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: SystemMetricsHistoryExport.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = SystemMetricsHistoryExport.defaultFileName(now: now)
        panel.canCreateDirectories = true
        panel.prompt = AppLocalization.text("导出")
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func write(service: SystemMonitorService, to destination: URL) async -> String {
        let data = await service.exportHistoryWorkbook()
        let directory = destination.deletingLastPathComponent()
        let scopedAccess = directory.startAccessingSecurityScopedResource()
        defer { if scopedAccess { directory.stopAccessingSecurityScopedResource() } }
        do {
            try data.write(to: destination, options: .atomic)
            return AppLocalization.text("已保存到 %@", destination.path)
        } catch {
            return AppLocalization.text("导出失败：%@", error.localizedDescription)
        }
    }
}

// MARK: - Chart card

private struct SystemMetricsChartCard: View {
    let section: SystemMetricsChartSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(AppLocalization.text(section.titleKey))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            Chart {
                ForEach(section.series) { series in
                    ForEach(series.points, id: \.date) { point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(by: .value("Series", label(for: series)))
                        .interpolationMethod(.monotone)
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: section.series.map { label(for: $0) },
                range: HistoryChartPalette.colors(count: section.series.count)
            )
            .chartYScale(domain: 0...yMaximum)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(axisText(number))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisDateText(date))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .frame(height: 132)
        }
        .padding(12)
        .background(Color.fillCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.strokeCard, lineWidth: 0.5)
        }
    }

    private func label(for series: SystemMetricsChartSeries) -> String {
        AppLocalization.text(series.titleKey)
    }

    private var symbol: String {
        switch section.id {
        case "cpu": "cpu"
        case "gpu": "memorychip"
        case "memory": "memorychip"
        case "disk": "internaldrive"
        case "fans": "fan"
        default: "globe"
        }
    }

    private var yMaximum: Double {
        let peak = section.series
            .flatMap(\.points)
            .map(\.value)
            .filter(\.isFinite)
            .max() ?? 0
        switch section.unit {
        case .ratio:
            return 1
        case .bytesPerSecond, .rpm:
            return max(1, peak * 1.1)
        }
    }

    private func axisText(_ value: Double) -> String {
        switch section.unit {
        case .ratio:
            return "\(Int((value * 100).rounded()))%"
        case .bytesPerSecond:
            return SystemMetricsHistoryPresentation.rateText(value)
        case .rpm:
            return "\(Int(value.rounded()))"
        }
    }

    private func axisDateText(_ date: Date) -> String {
        switch section.unit {
        case .rpm:
            return date.formatted(.dateTime.hour().minute())
        default:
            return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
        }
    }
}

private enum HistoryChartPalette {
    static func colors(count: Int) -> [Color] {
        let base = WaveformPalette.palette
        guard count > 0 else { return [] }
        return (0..<count).map { base[$0 % base.count] }
    }
}

// MARK: - Presentation helpers

/// Formatting shared by the history window and the module card.
enum SystemMetricsHistoryPresentation {
    /// Compact duration such as "1h 30m", localized by Foundation so no per-language table is needed.
    static func spanText(
        _ span: TimeInterval,
        language: AppLanguage = AppLocalization.currentLanguage
    ) -> String {
        Duration.seconds(max(60, span))
            .formatted(
                .units(
                    allowed: [.days, .hours, .minutes],
                    width: .narrow,
                    maximumUnitCount: 2
                )
                .locale(language.locale)
            )
    }

    static func rateText(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(max(0, bytesPerSecond))) + "/s"
    }
}
