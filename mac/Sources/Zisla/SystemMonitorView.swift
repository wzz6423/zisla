import AppKit
import ZislaKit
import SwiftUI

/// System monitor view.
///
/// Visually matches the Dynamic Island: an asymmetric two-column layout — left "Real-time Performance"
/// (CPU/GPU waveforms) and right "Storage & Network" (RAM/disk/fan/network) — separated by a `Hairline`.
/// Cards uniformly use `Color.fillCard` / `Color.strokeCard` tokens; font sizes are tightened to
/// `islandMicro` ~ 12pt; usage bars use a custom `CapacityBar` instead of `ProgressView` to avoid
/// a dashboard-like dissonance.
struct SystemMonitorView: View {
    @ObservedObject var service: SystemMonitorService
    @State private var isCleanupPresented = false
    @State private var releasedMemoryBytes: UInt64?
    @State private var systemColumnHeight: CGFloat = 0
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                computeColumn
                    .frame(
                        height: systemColumnHeight > 0 ? systemColumnHeight : nil,
                        alignment: .top
                )
                Hairline()
                systemColumn
                    .frame(width: 250)
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .onPreferenceChange(SystemColumnHeightPreferenceKey.self) { height in
            guard systemColumnHeight != height else { return }
            systemColumnHeight = height
        }
        .background(SystemCleanupPanelPresenter(isPresented: $isCleanupPresented, service: service))
        .task { await service.sampleOnce() }
        .onChange(of: isCleanupPresented) { _, newValue in
            AppModel.shared.isCleanupPanelVisible = newValue
        }
    }

    // MARK: - Columns

    /// Left column: real-time waveforms and usage breakdown for CPU and GPU.
    private var computeColumn: some View {
        VStack(spacing: 10) {
            cpuCard
            gpuCard
        }
        .frame(maxWidth: .infinity)
    }

    /// Right column: compact readings for memory / disk / fan / network.
    private var systemColumn: some View {
        VStack(spacing: 10) {
            memoryCard
            diskCard
            fanCard
            networkCard
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SystemColumnHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
    }

    // MARK: - Cards

    private var cpuCard: some View {
        MonitorCard(height: computeCardHeight) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(symbol: "cpu", title: "CPU") {
                    HStack(spacing: 6) {
                        if let temp = temperatureText(service.snapshot?.cpu.temperature) {
                            Text(temp)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(temperatureTint(cpuCelsius))
                                .monospacedDigit()
                        }
                        Text(cpuCoreText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text(service.snapshot?.hardware.cpuName ?? "正在识别芯片")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                MultiLineWaveform(series: cpuWaveSeries, height: 65.5)
                VStack(spacing: 4) {
                    metricRow(color: WaveformPalette.blue, label: "用户", value: percent(cpuUserUsage))
                    metricRow(color: WaveformPalette.red, label: "系统", value: percent(service.snapshot?.cpu.systemFraction))
                    metricRow(color: WaveformPalette.idle, label: "闲置", value: percent(service.snapshot?.cpu.idleFraction))
                }
            }
        }
    }

    private var gpuCard: some View {
        MonitorCard(height: computeCardHeight) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(symbol: "memorychip", title: "GPU") {
                    HStack(spacing: 6) {
                        if let temp = temperatureText(gpuUsage?.temperature) {
                            Text(temp)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(temperatureTint(gpuCelsius))
                                .monospacedDigit()
                        }
                        Text(gpuCoreText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text(service.snapshot?.hardware.gpuName ?? "正在识别图形处理器")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                MultiLineWaveform(series: gpuWaveSeries, height: 65.5)
                VStack(spacing: 4) {
                    metricRow(color: WaveformPalette.blue, label: "利用率", value: gpuUsageText)
                    metricRow(color: WaveformPalette.red, label: "渲染", value: gpuRendererText)
                    metricRow(color: WaveformPalette.teal, label: "Tiler", value: gpuTilerText)
                }
            }
            .help(gpuUsage?.detail ?? gpuUnavailableReason)
        }
    }

    private var memoryCard: some View {
        MonitorCard {
            VStack(alignment: .leading, spacing: 7) {
                CardHeader(symbol: "memorychip", title: "内存") {
                    Text("使用率 \(memoryUsageText)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(capacityTint(memoryUsage))
                        .monospacedDigit()
                }
                usedAvailableRow(
                    used: service.snapshot?.memory.usedBytes,
                    available: service.snapshot?.memory.freeBytes,
                    total: service.snapshot?.memory.totalBytes,
                    format: memoryByteText
                )
                CapacityBar(ratio: memoryUsage, tint: capacityTint(memoryUsage))
                HStack {
                    Text(memoryDetail)
                        .font(.islandMicro())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    miniActionButton("释放", help: "整理系统内存，回收非活跃与压缩页面") {
                        releaseMemory()
                    }
                }
            }
        }
    }

    private var diskCard: some View {
        MonitorCard {
            VStack(alignment: .leading, spacing: 7) {
                CardHeader(symbol: "internaldrive", title: "硬盘") {
                    HStack(spacing: 6) {
                        if let temp = temperatureText(service.snapshot?.disk.temperature) {
                            Text(temp)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(temperatureTint(diskCelsius))
                                .monospacedDigit()
                        }
                        if let usage = diskUsageText {
                            Text("使用率 \(usage)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(capacityTint(diskUsage))
                                .monospacedDigit()
                        }
                    }
                }
                usedAvailableRow(
                    used: service.snapshot?.disk.usedBytes,
                    available: service.snapshot?.disk.freeBytes,
                    total: service.snapshot?.disk.totalBytes,
                    format: byteText
                )
                CapacityBar(ratio: diskUsage, tint: capacityTint(diskUsage))
                HStack {
                    Text("R \(rateText(service.snapshot?.disk.readBytesPerSecond))   W \(rateText(service.snapshot?.disk.writeBytesPerSecond))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    miniActionButton("清理", help: "扫描可清理的缓存、日志与开发产物") {
                        isCleanupPresented = true
                    }
                }
            }
        }
    }

    private var fanCard: some View {
        MonitorCard {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(symbol: "fan", title: "风扇")
                fanContent
            }
        }
    }

    private var networkCard: some View {
        MonitorCard {
            VStack(alignment: .leading, spacing: 7) {
                CardHeader(symbol: "globe", title: "网络") {
                    IconButton(symbol: "arrow.clockwise", help: "通过 ipify 查询公网地址", size: .compact) {
                        Task { await service.refreshPublicIPAddress() }
                    }
                }
                HStack(spacing: 14) {
                    networkRate(symbol: "arrow.down", value: rateText(service.snapshot?.network.receiveBytesPerSecond), color: .zislaInfo)
                    networkRate(symbol: "arrow.up", value: rateText(service.snapshot?.network.sendBytesPerSecond), color: .zislaWarning)
                }
                CopyableAddressRow(label: "内网", value: service.snapshot?.networkIdentity.privateIPv4Address, placeholder: "正在识别")
                CopyableAddressRow(
                    label: "公网",
                    value: service.snapshot?.networkIdentity.publicIPAddress ?? service.publicIPAddress,
                    placeholder: service.isRefreshingPublicIPAddress ? "正在获取" : "暂不可用"
                )
            }
        }
    }

    // MARK: - Derived

    private var cpuUserUsage: Double? {
        guard let cpu = service.snapshot?.cpu else { return nil }
        return cpu.userFraction + cpu.niceFraction
    }

    private var computeCardHeight: CGFloat? {
        guard systemColumnHeight > 0 else { return nil }
        return (systemColumnHeight - 10) / 2
    }

    private var cpuCoreText: String {
        let hardware = service.snapshot?.hardware
        guard let total = hardware?.cpuCoreCount else { return "-- 核" }

        let topology = [
            hardware?.cpuPerformanceCoreCount.map { "\($0) 性能" },
            hardware?.cpuEfficiencyCoreCount.map { "\($0) 能效" },
        ]
        .compactMap { $0 }

        guard !topology.isEmpty else { return "\(total) 核" }
        return "\(total) 核 · " + topology.joined(separator: " · ")
    }

    private var cpuCelsius: Double? {
        if case let .celsius(value) = service.snapshot?.cpu.temperature { return value }
        return nil
    }

    private var diskCelsius: Double? {
        if case let .celsius(value) = service.snapshot?.disk.temperature { return value }
        return nil
    }

    private var gpuCelsius: Double? {
        if case let .celsius(value) = gpuUsage?.temperature { return value }
        return nil
    }

    private var gpuUsage: GPUUsageMetrics? {
        guard case let .available(metrics)? = service.snapshot?.gpu else { return nil }
        return metrics
    }

    private var gpuCoreText: String {
        guard let count = service.snapshot?.hardware.gpuCoreCount else { return "-- 核" }
        return "\(count) 核"
    }

    private var gpuUsageText: String { percent(gpuUsage?.usage) }
    private var gpuRendererText: String { percent(gpuUsage?.rendererUsage) }
    private var gpuTilerText: String { percent(gpuUsage?.tilerUsage) }

    private var cpuWaveSeries: [WaveSeries] {
        [
            WaveSeries(samples: service.history.cpuIdle, color: WaveformPalette.idle),
            WaveSeries(samples: service.history.cpuUser, color: WaveformPalette.blue),
            WaveSeries(samples: service.history.cpuSystem, color: WaveformPalette.red),
        ]
    }

    private var gpuWaveSeries: [WaveSeries] {
        [
            WaveSeries(samples: service.history.gpuUsage, color: WaveformPalette.blue),
            WaveSeries(samples: service.history.gpuRenderer, color: WaveformPalette.red),
            WaveSeries(samples: service.history.gpuTiler, color: WaveformPalette.teal),
        ]
    }

    private var gpuUnavailableReason: String {
        guard case let .unavailable(reason)? = service.snapshot?.gpu else {
            return "GPU 性能统计为只读实验数据，可能随 macOS 更新变化"
        }
        return reason
    }

    private var diskUsage: Double {
        guard let disk = service.snapshot?.disk, disk.totalBytes > 0 else { return 0 }
        return min(1, Double(disk.usedBytes) / Double(disk.totalBytes))
    }

    private var diskUsageText: String? {
        guard let disk = service.snapshot?.disk, disk.totalBytes > 0 else { return nil }
        return percent(diskUsage)
    }

    private var memoryUsage: Double {
        guard let memory = service.snapshot?.memory else { return 0 }
        return SystemMonitorMemoryPresentation.usageRatio(
            usedBytes: memory.usedBytes,
            totalBytes: memory.totalBytes
        ) ?? 0
    }

    private var memoryUsageText: String {
        guard let memory = service.snapshot?.memory else { return "--" }
        return SystemMonitorMemoryPresentation.usageText(
            usedBytes: memory.usedBytes,
            totalBytes: memory.totalBytes
        )
    }

    private var memoryDetail: String {
        if let releasedMemoryBytes {
            return "已整理系统内存 \(memoryByteText(releasedMemoryBytes))"
        }
        return ""
    }

    @ViewBuilder
    private var fanContent: some View {
        switch service.snapshot?.fan {
        case let .available(rpm, _) where rpm.isEmpty:
            noFanLabel
        case let .available(rpm, _):
            HStack(spacing: 16) {
                ForEach(Array(rpm.enumerated()), id: \.offset) { index, value in
                    HStack(spacing: 5) {
                        Image(systemName: "fan.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        if let label = Self.fanPositionLabel(for: index, locale: locale) {
                            Text(label)
                                .font(.islandMicro())
                                .foregroundStyle(.secondary)
                        }
                        Text("\(Int(value.rounded()))")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("RPM")
                            .font(.islandMicro())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .unavailable:
            fanUnavailableLabel
        case .none:
            Text("正在读取风扇状态")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    static func fanPositionLabel(for index: Int, locale: Locale) -> String? {
        switch index {
        case 0: locale.identifier.lowercased().hasPrefix("en") ? "L" : "左"
        case 1: locale.identifier.lowercased().hasPrefix("en") ? "R" : "右"
        default: nil
        }
    }

    private var noFanLabel: some View {
        Text("无风扇")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var fanUnavailableLabel: some View {
        Text("风扇数据不可用")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }

    // MARK: - Pieces

    private func metricRow(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
    }

    private func usedAvailableRow(
        used: UInt64?,
        available: UInt64?,
        total: UInt64?,
        format: (UInt64) -> String = { _ in "--" }
    ) -> some View {
        HStack {
            Text("已用 \(used.map { format($0) } ?? "--") / 可用 \(available.map { format($0) } ?? "--")")
            Spacer(minLength: 0)
            Text("总量 \(total.map { format($0) } ?? "--")")
        }
        .font(.islandMicro())
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private func networkRate(symbol: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private struct CopyableAddressRow: View {
        let label: String
        let value: String?
        let placeholder: String

        var body: some View {
            HStack(spacing: 5) {
                Text(label)
                    .font(.islandMicro())
                    .foregroundStyle(.secondary)
                Text(value.map { $0.isEmpty ? placeholder : $0 } ?? placeholder)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                if let value, !value.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("拷贝")
                }
            }
        }
    }

    private func miniActionButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.fillControl)
            .clipShape(Capsule())
            .help(help)
    }

    private func releaseMemory() {
        Task {
            releasedMemoryBytes = await service.releaseSystemMemoryPressure()
        }
    }

    // MARK: - Semantic tints

    /// Capacity bar defaults to neutral; turns warning/error color only when usage is high, to avoid color dominating the island.
    private func capacityTint(_ ratio: Double) -> Color {
        if ratio > 0.95 { return .zislaError }
        if ratio > 0.85 { return .zislaWarning }
        return Color.primary.opacity(0.7)
    }

    private func temperatureTint(_ celsius: Double?) -> Color {
        guard let celsius else { return .primary }
        if celsius > 90 { return .zislaError }
        if celsius > 75 { return .zislaWarning }
        return .primary
    }

    // MARK: - Formatters

    private func temperatureText(_ metric: TemperatureMetric?) -> String? {
        switch metric {
        case let .celsius(value): "\(value.formatted(.number.precision(.fractionLength(1))))°C"
        case .unavailable, .none: nil
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func byteText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    /// Memory computed in binary GiB with one decimal place; suffix uses GB (consistent with common third-party monitors).
    private func memoryByteText(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1024 / 1024 / 1024)
    }

    private func rateText(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else { return "---" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(max(0, bytesPerSecond)),
            countStyle: .file
        ) + "/s"
    }
}

// MARK: - Cleanup panel presentation

private struct SystemCleanupPanelPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let service: SystemMonitorService

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            presenting: isPresented,
            service: service,
            hostWindow: nsView.window
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    @MainActor
    final class Coordinator {
        private var isPresented: Binding<Bool>
        private var panel: SystemCleanupPanel?

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        func update(presenting: Bool, service: SystemMonitorService, hostWindow: NSWindow?) {
            guard presenting else {
                dismiss()
                return
            }

            let panel = panel ?? makePanel(service: service)
            guard !panel.isVisible else { return }
            WindowPlacement.center(panel, on: hostWindow?.screen)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }

        func dismiss() {
            panel?.orderOut(nil)
            panel = nil
        }

        private func makePanel(service: SystemMonitorService) -> SystemCleanupPanel {
            let panel = SystemCleanupPanel(
                contentRect: CGRect(x: 0, y: 0, width: 560, height: 430),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
        // System authorization temporarily deactivates the app; keep the panel so scanning can resume immediately after authorization.
            panel.hidesOnDeactivate = false
            panel.level = WindowPlacement.modalWindowLevel
            panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
            let hostingView = NSHostingView(
                rootView: AppLanguageEnvironment(
                    languageStore: AppModel.shared.languageStore,
                    content: SystemCleanupSheet(
                        service: service,
                        onDismiss: { [weak self] in
                            self?.isPresented.wrappedValue = false
                            self?.dismiss()
                        },
                        onCleanupCompleted: {
                            AppModel.shared.islandCollapseRequested = true
                        }
                    )
                )
            )
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 18
            hostingView.layer?.cornerCurve = .continuous
            hostingView.layer?.masksToBounds = true
            panel.contentView = hostingView
            panel.onCancel = { [weak self] in
                self?.isPresented.wrappedValue = false
                self?.dismiss()
            }
            self.panel = panel
            return panel
        }
    }
}

@MainActor
private final class SystemCleanupPanel: NSPanel {
    var onCancel: () -> Void = {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}

// MARK: - Card

private struct MonitorCard<Content: View>: View {
    var height: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(10)
            .frame(
                maxWidth: .infinity,
                minHeight: height,
                maxHeight: height,
                alignment: .topLeading
            )
            .background(Color.fillCard)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.strokeCard, lineWidth: 0.5)
            }
    }
}

private struct SystemColumnHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Card header

private struct CardHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            trailing()
        }
    }

    init(symbol: String, title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.trailing = trailing
    }

    init(symbol: String, title: String) where Trailing == EmptyView {
        self.symbol = symbol
        self.title = title
        self.trailing = { EmptyView() }
    }
}

// MARK: - Capacity bar

/// Custom capacity bar replacing the system `ProgressView`, keeping consistent rounded corners and colors inside the island.
private struct CapacityBar: View {
    var ratio: Double
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(1, max(0, ratio))
            let fillWidth = max(2, proxy.size.width * clamped)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.fillControl)
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(tint)
                    .frame(width: fillWidth)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Waveforms

private enum WaveformPalette {
    static let blue = Color(red: 0.31, green: 0.64, blue: 0.87)
    static let red = Color(red: 0.93, green: 0.31, blue: 0.37)
    static let teal = Color(red: 0.25, green: 0.78, blue: 0.78)
    static let idle = Color(red: 0.88, green: 0.88, blue: 0.88)
}

private struct WaveSeries {
    var samples: [Double]
    var color: Color
}

private struct MultiLineWaveform: View {
    var series: [WaveSeries]
    var height: CGFloat = 54

    var body: some View {
        Canvas { context, size in
            for item in series where item.samples.count > 1 {
                let baseline = Array(repeating: 0.0, count: item.samples.count)
                let area = waveArea(top: item.samples, bottom: baseline, size: size)
                context.fill(area, with: .color(item.color.opacity(0.32)))
                context.stroke(waveLine(item.samples, size: size), with: .color(item.color), lineWidth: 1.3)
            }
        }
        .frame(height: height)
        .background(Color.fillControl)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private func waveArea(top: [Double], bottom: [Double], size: CGSize) -> Path {
    guard top.count > 1, top.count == bottom.count else { return Path() }
    var path = waveLine(top, size: size)
    for index in bottom.indices.reversed() {
        let x = size.width * CGFloat(index) / CGFloat(bottom.count - 1)
        let y = size.height * (1 - CGFloat(min(1, max(0, bottom[index]))))
        path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

private func waveLine(_ values: [Double], size: CGSize) -> Path {
    guard values.count > 1 else { return Path() }
    let points: [CGPoint] = values.enumerated().map { index, value in
        let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
        let y = size.height * (1 - CGFloat(min(1, max(0, value))))
        return CGPoint(x: x, y: y)
    }
    var path = Path()
    path.move(to: points[0])
    guard points.count > 2 else {
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
    // Catmull-Rom spline as cubic Béziers: smooth and natural, without the
    // hand-drawn, lopsided wobble of straight segments or overshooting curves.
    for index in 0 ..< points.count - 1 {
        let p0 = points[max(0, index - 1)]
        let p1 = points[index]
        let p2 = points[index + 1]
        let p3 = points[min(points.count - 1, index + 2)]
        let control1 = CGPoint(
            x: p1.x + (p2.x - p0.x) / 6,
            y: p1.y + (p2.y - p0.y) / 6
        )
        let control2 = CGPoint(
            x: p2.x - (p3.x - p1.x) / 6,
            y: p2.y - (p3.y - p1.y) / 6
        )
        path.addCurve(to: p2, control1: control1, control2: control2)
    }
    return path
}

// MARK: - Cleanup sheet (unchanged behavior)

private struct SystemCleanupSheet: View {
    @ObservedObject var service: SystemMonitorService
    let onDismiss: () -> Void
    var onCleanupCompleted: (() -> Void)?
    @State private var candidates: [DiskCleanupCandidate] = []
    @State private var groupedSections: [CleanupKindSection] = []
    @State private var selectedURLs: Set<URL> = []
    @State private var collapsedKinds: Set<DiskCleanupKind> = []
    @State private var isScanning = false
    @State private var isCleaning = false
    @State private var confirmationPresented = false
    @State private var result: DiskCleanupResult?
    @State private var cachedManualReviewCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("清理候选项")
                        .font(.system(size: 16, weight: .semibold))
                    Text("检测可再生缓存与常见临时数据；用户文件、重复文件和安装包仅供人工复核")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    toggleSelectAll()
                } label: {
                    Label(
                        allCandidatesSelected ? "取消全选" : "全选",
                        systemImage: allCandidatesSelected ? "checkmark.square.fill" : "checkmark.square"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(allCandidatesSelected ? "取消所有选择" : "选择全部候选项")
                .accessibilityLabel(allCandidatesSelected ? "取消全选" : "全选")
                .disabled(candidates.isEmpty || isScanning || isCleaning)
                Button {
                    invertSelection()
                } label: {
                    Label("反选", systemImage: "arrow.left.arrow.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("反转当前选择：已选变未选，未选变已选")
                .accessibilityLabel("反选")
                .accessibilityHint("已选中的项取消选中，未选中的项选中")
                .disabled(candidates.isEmpty || isScanning || isCleaning)
                Button {
                    Task { await scan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("重新扫描")
                .accessibilityLabel("重新扫描")
                .disabled(isScanning || isCleaning)
            }

            Group {
                if candidates.isEmpty && isScanning {
                    ProgressView("正在扫描")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if candidates.isEmpty {
                    ContentUnavailableView(
                        "未找到可清理项",
                        systemImage: "checkmark.circle",
                        description: Text("可安全清理的缓存与日志当前为空")
                    )
                } else {
                    List {
                        if isScanning {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在扫描更多项目...")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
                        }
                        ForEach(groupedSections) { section in
                            if isSectionCollapsed(section) {
                                cleanupSectionHeader(section)
                            } else {
                                Section {
                                    ForEach(section.items) { candidate in
                                        Toggle(isOn: selectionBinding(for: candidate.url)) {
                                            HStack(spacing: 9) {
                                                Image(systemName: candidate.kind.symbol)
                                                    .foregroundStyle(candidate.kind.tint)
                                                    .frame(width: 18)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack(spacing: 5) {
                                                        Text(candidate.displayName)
                                                            .font(.system(size: 11, weight: .medium))
                                                            .lineLimit(1)
                                                        Text(candidate.safetyLevel.title)
                                                            .font(.system(size: 9, weight: .medium))
                                                            .foregroundStyle(
                                                                candidate.safetyLevel == .safeToClean
                                                                    ? Color.zislaSuccess
                                                                    : Color.zislaWarning
                                                            )
                                                    }
                                                    if let detail = candidate.detail {
                                                        Text(detail)
                                                            .font(.system(size: 9))
                                                            .foregroundStyle(.secondary)
                                                            .lineLimit(1)
                                                            .help(detail)
                                                    }
                                                    Text(candidate.safetyLevel.reason)
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                                Spacer(minLength: 8)
                                                Text(byteText(candidate.byteSize))
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .toggleStyle(.checkbox)
                                        .disabled(isCleaning)
                                    }
                                } header: {
                                    cleanupSectionHeader(section)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minHeight: 235)

            if let result {
                Label(resultText(result), systemImage: result.failures.isEmpty
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(result.failures.isEmpty ? Color.zislaSuccess : Color.zislaWarning)
            }

            HStack {
                Text("已选 \(selectedURLs.count) / \(candidates.count) 项 · \(byteText(selectedByteSize))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: onDismiss)
                    .buttonStyle(.bordered)
                Button("移入废纸篓", role: .destructive) {
                    confirmationPresented = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedURLs.isEmpty || isCleaning)
            }
        }
        .padding(18)
        .frame(width: 560, height: 430)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task { await scan() }
        .confirmationDialog(
            "将 \(selectedURLs.count) 项移入废纸篓？",
            isPresented: $confirmationPresented,
            titleVisibility: .visible
        ) {
            Button("移入废纸篓", role: .destructive) {
                Task { await cleanSelected() }
            }
        } message: {
            Text(
                cachedManualReviewCount > 0
                    ? "其中 \(cachedManualReviewCount) 项需人工复核。zisla 不会永久删除这些内容。"
                    : "zisla 不会永久删除这些内容。"
            )
        }
    }

    private var selectedByteSize: UInt64 {
        candidates
            .filter { selectedURLs.contains($0.url) }
            .reduce(0) { $0 + $1.byteSize }
    }


    private var allCandidatesSelected: Bool {
        !candidates.isEmpty && candidates.allSatisfy { selectedURLs.contains($0.url) }
    }

    private func makeGroupedSections(from candidates: [DiskCleanupCandidate]) -> [CleanupKindSection] {
        let order = DiskCleanupKind.allCases
        return order.compactMap { kind in
            let items = candidates
                .filter { $0.kind == kind }
                .sorted { $0.byteSize > $1.byteSize }
            guard !items.isEmpty else { return nil }
            let total = items.reduce(UInt64(0)) { $0 + $1.byteSize }
            return CleanupKindSection(kind: kind, items: items, totalBytes: total)
        }
    }

    private func cleanupSectionHeader(_ section: CleanupKindSection) -> some View {
        HStack(spacing: 6) {
            Button {
                toggleSectionCollapsed(section)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSectionCollapsed(section) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 10)
                    Image(systemName: section.kind.symbol)
                        .foregroundStyle(section.kind.tint)
                    Text(section.kind.title)
                        .font(.system(size: 10, weight: .semibold))
                    Text("· \(section.selectedCount(in: selectedURLs))/\(section.items.count) 项")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isSectionCollapsed(section) ? "展开\(section.kind.title)" : "折叠\(section.kind.title)")
            .accessibilityLabel(isSectionCollapsed(section) ? "展开\(section.kind.title)" : "折叠\(section.kind.title)")
            Spacer(minLength: 4)
            Text(byteText(section.totalBytes))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            IconButton(
                symbol: section.allSelected(in: selectedURLs) ? "checkmark.square.fill" : "checkmark.square",
                help: section.allSelected(in: selectedURLs) ? "取消选择\(section.kind.title)" : "全选\(section.kind.title)",
                isActive: section.allSelected(in: selectedURLs),
                size: .compact
            ) {
                toggleSectionSelection(section)
            }
            .disabled(isCleaning)
            IconButton(
                symbol: "arrow.left.arrow.right.square",
                help: "反选\(section.kind.title)",
                size: .compact
            ) {
                invertSelection(in: section)
            }
            .disabled(isCleaning)
        }
        .textCase(nil)
        .padding(.vertical, 1)
    }

    private func toggleSelectAll() {
        if allCandidatesSelected {
            selectedURLs.removeAll()
            cachedManualReviewCount = 0
        } else {
            selectedURLs = Set(candidates.map(\.url))
            cachedManualReviewCount = candidates.count { $0.safetyLevel == .requiresManualReview }
        }
    }

    private func invertSelection() {
        let all = Set(candidates.map(\.url))
        selectedURLs = all.subtracting(selectedURLs)
        cachedManualReviewCount = computeManualReviewCount()
    }

    private func isSectionCollapsed(_ section: CleanupKindSection) -> Bool {
        collapsedKinds.contains(section.kind)
    }

    private func toggleSectionCollapsed(_ section: CleanupKindSection) {
        if collapsedKinds.contains(section.kind) {
            collapsedKinds.remove(section.kind)
        } else {
            collapsedKinds.insert(section.kind)
        }
    }

    private func toggleSectionSelection(_ section: CleanupKindSection) {
        let urls = section.urls
        if urls.isSubset(of: selectedURLs) {
            selectedURLs.subtract(urls)
        } else {
            selectedURLs.formUnion(urls)
        }
        cachedManualReviewCount = computeManualReviewCount()
    }

    private func invertSelection(in section: CleanupKindSection) {
        let urls = section.urls
        let unselected = urls.subtracting(selectedURLs)
        selectedURLs.subtract(urls)
        selectedURLs.formUnion(unselected)
        cachedManualReviewCount = computeManualReviewCount()
    }

    private func selectionBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { selectedURLs.contains(url) },
            set: { selected in
                if selected {
                    selectedURLs.insert(url)
                } else {
                    selectedURLs.remove(url)
                }
                cachedManualReviewCount = computeManualReviewCount()
            }
        )
    }

    private func computeManualReviewCount() -> Int {
        candidates.count {
            selectedURLs.contains($0.url) && $0.safetyLevel == .requiresManualReview
        }
    }

    private func scan() async {
        isScanning = true
        result = nil
        candidates = []
        groupedSections = []
        let scannedCandidates = await service.scanCleanupCandidatesWithProgress { progressCandidates in
            Task { @MainActor in
                let mergedCandidates = SystemDiskCleanup
                    .deduplicateCandidates(candidates + progressCandidates)
                    .sorted { $0.byteSize > $1.byteSize }
                candidates = mergedCandidates
                groupedSections = makeGroupedSections(from: mergedCandidates)
            }
        }
        candidates = scannedCandidates
        groupedSections = makeGroupedSections(from: scannedCandidates)
        selectedURLs = selectedURLs.intersection(Set(candidates.map(\.url)))
        cachedManualReviewCount = computeManualReviewCount()
        isScanning = false
    }

    private func cleanSelected() async {
        isCleaning = true
        let result = await service.trashSelected(Array(selectedURLs))
        self.result = result
        selectedURLs = []
        cachedManualReviewCount = 0
        candidates.removeAll { candidate in
            !result.failures.contains(where: { $0.url == candidate.url })
        }
        groupedSections = makeGroupedSections(from: candidates)
        isCleaning = false
        onCleanupCompleted?()
        onDismiss()
    }

    private func resultText(_ result: DiskCleanupResult) -> String {
        if result.failures.isEmpty {
            return "已移入废纸篓 \(result.successCount) 项；清空废纸篓后可释放 \(byteText(result.freedBytes))"
        }
        return "已处理 \(result.successCount) 项，\(result.failures.count) 项未完成"
    }

    private func byteText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }
}

private struct CleanupKindSection: Identifiable {
    var id: DiskCleanupKind { kind }
    var kind: DiskCleanupKind
    var items: [DiskCleanupCandidate]
    var totalBytes: UInt64

    var urls: Set<URL> {
        Set(items.map(\.url))
    }

    func selectedCount(in selection: Set<URL>) -> Int {
        urls.intersection(selection).count
    }

    func allSelected(in selection: Set<URL>) -> Bool {
        !urls.isEmpty && urls.isSubset(of: selection)
    }
}

private extension DiskCleanupKind {
    var title: String {
        switch self {
        case .appCache: "应用缓存"
        case .cache: "缓存"
        case .log: "日志"
        case .trash: "废纸篓"
        case .developerArtifacts: "开发产物"
        case .temporaryFiles: "临时文件"
        case .packageManagerCache: "包管理缓存"
        case .crashReport: "崩溃报告"
        case .diskImage: "磁盘镜像"
        case .largeFile: "大文件"
        case .duplicateFile: "重复文件"
        }
    }

    var symbol: String {
        switch self {
        case .appCache: "app.badge.checkmark"
        case .cache: "archivebox.fill"
        case .log: "doc.text.fill"
        case .trash: "trash.fill"
        case .developerArtifacts: "hammer.fill"
        case .temporaryFiles: "clock.arrow.circlepath"
        case .packageManagerCache: "shippingbox.fill"
        case .crashReport: "exclamationmark.triangle.fill"
        case .diskImage: "opticaldisc.fill"
        case .largeFile: "doc.zipper.fill"
        case .duplicateFile: "rectangle.stack.fill"
        }
    }

    var tint: Color {
        switch self {
        case .appCache: .green
        case .cache: .cyan
        case .log: .orange
        case .trash: .red
        case .developerArtifacts: .purple
        case .temporaryFiles: .teal
        case .packageManagerCache: .mint
        case .crashReport: .yellow
        case .diskImage: .blue
        case .largeFile: .indigo
        case .duplicateFile: .pink
        }
    }
}
