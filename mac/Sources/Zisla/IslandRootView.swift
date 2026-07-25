import AppKit
import ZislaCore
import ZislaKit
import SwiftUI

struct IslandRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var petController: IslandPetController
    @ObservedObject private var settingsStore: FeatureSettingsStore
    @ObservedObject private var voiceInput: VoiceInputController
    var onPointerEntered: () -> Void
    var onPointerExited: () -> Void
    var onPinChanged: (Bool) -> Void
    var onSettingsRequested: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var dropState = IslandDropState()

    init(
        model: AppModel,
        petController: IslandPetController,
        onPointerEntered: @escaping () -> Void,
        onPointerExited: @escaping () -> Void,
        onPinChanged: @escaping (Bool) -> Void,
        onSettingsRequested: @escaping () -> Void
    ) {
        _model = ObservedObject(wrappedValue: model)
        _petController = ObservedObject(wrappedValue: petController)
        _settingsStore = ObservedObject(wrappedValue: model.settingsStore)
        _voiceInput = ObservedObject(wrappedValue: model.voiceInput)
        self.onPointerEntered = onPointerEntered
        self.onPointerExited = onPointerExited
        self.onPinChanged = onPinChanged
        self.onSettingsRequested = onSettingsRequested
    }

    var body: some View {
        ZStack(alignment: .top) {
            if showsTransferHints {
                HStack(spacing: 0) {
                    transferShoulder(
                        symbol: "square.and.arrow.up",
                        title: "共享",
                        detail: hintDetail,
                        color: .cyan,
                        targeted: dropState.shareTargeted
                    ) {
                        shareDetectedLink()
                    }
                    .onDrop(
                        of: TransferDropDelegate.supportedTypes,
                        delegate: TransferDropDelegate(isTargeted: $dropState.shareTargeted) {
                            model.share($0)
                        }
                    )
                    .contextMenu {
                        Button("粘贴并共享") {
                            model.shareFromPasteboard()
                        }
                        .keyboardShortcut("v", modifiers: .command)
                    }
                    .onPasteCommand(of: TransferDropDelegate.supportedContentTypes) { _ in
                        model.shareFromPasteboard()
                    }

                    Spacer(minLength: layout.islandSize.width - 16)

                    transferShoulder(
                        symbol: "tray.and.arrow.down.fill",
                        title: "中转",
                        detail: hintDetail,
                        color: .green,
                        targeted: dropState.shelfTargeted
                    ) {
                        model.prepareDetectedLink()
                    }
                    .onDrop(
                        of: TransferDropDelegate.supportedTypes,
                        delegate: TransferDropDelegate(isTargeted: $dropState.shelfTargeted) {
                            model.receiveTransferItems($0)
                        }
                    )
                }
                .frame(width: layout.panelSize.width)
                .padding(.top, 62)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(0)
            }

            IslandSurface(
                isCollapsed: isIslandCollapsed,
                collapsedSize: model.collapsedIslandSize,
                expandedSize: layout.islandSize
            ) {
                ZStack(alignment: petAlignment) {
                    VStack(spacing: 0) {
                        if voiceInput.isRecording {
                            // 语音录音紧凑模式：跳过标题栏与工具栏，仅显示一行转写。
                            Spacer().frame(height: 34)
                            VoiceTranscriptionView(voiceInput: voiceInput)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 6)
                        } else if !isIslandCollapsed {
                            // Black crown chrome always uses dark labels/icons.
                            NowPlayingHeader(model: model)
                                .padding(.horizontal, 14)
                                .padding(.top, contentTopInset)
                                .padding(.bottom, 4)
                                .environment(\.colorScheme, .dark)

                            toolRail
                                .padding(.horizontal, 12)
                                .padding(.bottom, 7)
                                .environment(\.colorScheme, .dark)

                            Group {
                                if let activeModule {
                                    switch activeModule {
                                    case .shelf:
                                        ShelfModuleView(model: model)
                                    case .clipboard:
                                        ClipboardHistoryModuleView(model: model)
                                    case .aiMonitor:
                                        AIProgressModuleView(model: model)
                                    case .download:
                                        DownloadModuleView(model: model)
                                    case .agenda:
                                        AgendaModuleView(model: model, calendar: model.calendar)
                                    case .mail:
                                        MailModuleView(model: model)
                                    case .quickNotes:
                                        QuickNoteModuleView(model: model)
                                    case .toolbox:
                                        ToolboxModuleView(model: model)
                                    case .system:
                                        SystemMonitorView(service: model.systemMonitor)
                                    case .lockScreen:
                                        LockScreenModuleView(model: model)
                                    }
                                } else {
                                    ContentUnavailableView {
                                        Label("没有启用模块", systemImage: "rectangle.slash")
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(
                                UnevenRoundedRectangle(
                                    cornerRadii: .init(
                                        topLeading: 0,
                                        bottomLeading: IslandSurfaceGeometry.moduleOuterBottomCornerRadius,
                                        bottomTrailing: IslandSurfaceGeometry.moduleOuterBottomCornerRadius,
                                        topTrailing: 0
                                    ),
                                    style: .continuous
                                )
                            )
                            .padding(.horizontal, IslandSurfaceGeometry.moduleInset)
                            .padding(.bottom, IslandSurfaceGeometry.moduleInset)
                            .id(activeModule?.rawValue)
                            .transition(reduceMotion ? .identity : .opacity)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: activeModule)
                            // 下方模块落在烟灰磨砂玻璃上：切到深色模式，浅色文字保证可读
                            // （与底部烟灰玻璃、MarkdownWebView 的白字 HTML 保持一致）。
                            .environment(\.colorScheme, .dark)
                        }
                    }

                    if !isIslandCollapsed {
                        uptimeIndicator
                        expandedPetOverlay
                    } else {
                        collapsedPetOverlay
                            .frame(
                                width: model.collapsedIslandSize.width,
                                height: model.collapsedIslandSize.height
                            )
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .top
                            )
                    }
                }
                .frame(width: layout.islandSize.width, height: layout.islandSize.height)
            }
            .frame(width: layout.islandSize.width, height: layout.islandSize.height)
            .environment(\.colorScheme, .dark)
            .contentShape(IslandSilhouette())
            .onHover { hovering in
                if hovering { onPointerEntered() } else { onPointerExited() }
            }
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .ignoresSafeArea(edges: .top)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: showsTransferHints)
    }

    private var toolRail: some View {
        HStack(spacing: 8) {
            ModuleSelector(model: model)
            Spacer(minLength: 8)
            if settingsStore.settings.systemMonitorEnabled {
                NavMonitorStrip(monitor: model.systemMonitor) {
                    model.selectedModule = .system
                }
            }
            IconButton(
                symbol: model.isPinned ? "pin.fill" : "pin",
                help: model.isPinned ? "取消固定" : "固定灵动岛",
                isActive: model.isPinned
            ) {
                model.isPinned.toggle()
                onPinChanged(model.isPinned)
            }
            IconButton(symbol: "arrow.down.circle", help: "检查更新") {
                model.checkForUpdates(manual: true)
            }
            IconButton(symbol: "gearshape.fill", help: "设置") {
                onSettingsRequested()
            }
        }
        .frame(height: 30)
    }

    private var isIslandCollapsed: Bool {
        !model.isIslandVisible || voiceInput.isRecording
    }

    // 展开态宠物布局常量 —— 所有模块页面共享，修改此处即可调整全局避让。
    // contentTopInset 保证内容顶部始终比宠物底边多 8pt。
    private let petExpandedSize: CGFloat = 30
    private let petExpandedTopInset: CGFloat = 8
    private var contentTopInset: CGFloat { petExpandedTopInset + petExpandedSize + 8 }

    @ViewBuilder
    private var expandedPetOverlay: some View {
        if model.settingsStore.settings.petEnabled,
           let sprite = petController.sprite {
            IslandPetView(
                sprite: sprite,
                behavior: petController.behavior,
                side: model.settingsStore.settings.petSide,
                size: petExpandedSize
            )
            .padding(.top, petExpandedTopInset)
            .padding(
                model.settingsStore.settings.petSide == .right ? .trailing : .leading,
                12
            )
        }
    }

    private var uptimeIndicator: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            Text(SystemUptime.displayText(for: ProcessInfo.processInfo.systemUptime))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .monospacedDigit()
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: uptimeAlignment)
                .padding(.top, 12)
                .padding(hasRightExpandedPet ? .leading : .trailing, 14)
        }
        .allowsHitTesting(false)
    }

    private var hasRightExpandedPet: Bool {
        model.settingsStore.settings.petEnabled
            && model.settingsStore.settings.petSide == .right
    }

    private var uptimeAlignment: Alignment {
        hasRightExpandedPet ? .topLeading : .topTrailing
    }

    private var collapsedPetOverlay: some View {
        GeometryReader { proxy in
            if model.settingsStore.settings.petEnabled,
               let sprite = petController.sprite {
                let horizontalInset = min(12, max(2, proxy.size.width * 0.1))
                let verticalInset = min(4, max(2, proxy.size.height * 0.1))
                let size = max(
                    0,
                    min(
                        24,
                        proxy.size.width - horizontalInset * 2,
                        proxy.size.height - verticalInset * 2
                    )
                )
                IslandPetView(
                    sprite: sprite,
                    behavior: petController.behavior,
                    side: .left,
                    size: size
                )
                .padding(.leading, horizontalInset)
                .padding(.top, verticalInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var petAlignment: Alignment {
        model.settingsStore.settings.petSide == .right ? .topTrailing : .topLeading
    }

    private var showsTransferHints: Bool {
        !model.isIslandVisible && (model.isExternalDragging || model.detectedLink != nil)
    }

    private var hintDetail: String {
        model.detectedLink == nil ? "接收中" : "已识别链接"
    }

    private var enabledModules: [IslandModule] {
        IslandModule.allCases.filter {
            $0.isEnabled(in: model.settingsStore.settings) && $0 != .lockScreen
        }
    }

    private var activeModule: IslandModule? {
        enabledModules.first(where: { $0 == model.selectedModule }) ?? enabledModules.first
    }

    private var layout: IslandModuleLayout {
        if voiceInput.isRecording {
            return .voiceRecording
        }
        return activeModule?.layout ?? .standard
    }

    private func shareDetectedLink() {
        if let url = model.detectedLink {
            model.share([.link(url)])
        } else {
            model.shareFromPasteboard()
        }
    }

    private func transferShoulder(
        symbol: String,
        title: String,
        detail: String,
        color: Color,
        targeted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                    Text(detail)
                        .font(.islandMicro())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(targeted ? color : .primary)
            .frame(width: 108, height: 52)
            .background(shoulderBackground(targeted: targeted))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(color.opacity(targeted ? 0.9 : 0.24), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(color.opacity(targeted ? 1 : 0.34))
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .help("\(title)：\(detail)")
    }

    private func shoulderBackground(targeted: Bool) -> Color {
        Color.black.opacity(targeted ? 0.96 : 0.86)
    }
}

/// 语音录音时的实时转写视图：红色脉冲圆点 + 实时识别文字。
private struct VoiceTranscriptionView: View {
    @ObservedObject var voiceInput: VoiceInputController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.zislaError)
                .frame(width: 7, height: 7)
                .scaleEffect(pulse ? 1.3 : 1.0)
                .opacity(pulse ? 0.7 : 1.0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear { pulse = !reduceMotion }
                .onChange(of: reduceMotion) { _, isReduced in
                    pulse = !isReduced
                }

            Text(transcriptOrPlaceholder)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if voiceInput.errorDescription != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.zislaWarning)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcriptOrPlaceholder: String {
        if let error = voiceInput.errorDescription { return error }
        let text = voiceInput.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "正在聆听…" : text
    }
}

@MainActor
private final class IslandDropState: ObservableObject {
    @Published var shareTargeted = false
    @Published var shelfTargeted = false
}

/// 导航栏内的紧凑监控条：每个指标上行显示百分比、下行显示标签（CPU/GPU/RAM/Disk），
/// 仅在系统监控启用时出现，点按切换到系统监控模块。占用最小水平空间，
/// 比例超过阈值时百分比自动转橙/红。
private struct NavMonitorStrip: View {
    @ObservedObject var monitor: SystemMonitorService
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                metricCell(label: "CPU", ratio: cpuRatio)
                metricCell(label: "GPU", ratio: gpuRatio)
                metricCell(label: "RAM", ratio: memRatio)
                metricCell(label: "Disk", ratio: diskRatio)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Color.fillControl)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("系统监控实时读数 — 点按查看详情")
    }

    private func metricCell(label: String, ratio: Double?) -> some View {
        VStack(spacing: 0) {
            Text(percent(ratio))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(tint(ratio))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            Text(label)
                .font(.islandMicro())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    // MARK: - Ratios

    private var cpuRatio: Double? {
        monitor.snapshot?.cpu.usage
    }

    private var gpuRatio: Double? {
        if case let .available(metrics) = monitor.snapshot?.gpu {
            return metrics.usage
        }
        return nil
    }

    private var memRatio: Double? {
        guard let mem = monitor.snapshot?.memory, mem.totalBytes > 0 else { return nil }
        return Double(mem.usedBytes) / Double(mem.totalBytes)
    }

    private var diskRatio: Double? {
        guard let disk = monitor.snapshot?.disk, disk.totalBytes > 0 else { return nil }
        return Double(disk.usedBytes) / Double(disk.totalBytes)
    }

    // MARK: - Formatters

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func tint(_ ratio: Double?) -> Color {
        guard let ratio else { return .secondary }
        if ratio > 0.9 { return .zislaError }
        if ratio > 0.75 { return .zislaWarning }
        return .primary
    }
}

private struct ModuleSelector: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleModules) { module in
                Button {
                    model.selectedModule = module
                } label: {
                    IconButtonLabel(
                        symbol: module.symbol,
                        isActive: model.selectedModule == module,
                        dimmedWhenInactive: true
                    )
                }
                .buttonStyle(.plain)
                .help(module.title)
            }
        }
    }

    private var visibleModules: [IslandModule] {
        IslandModule.allCases.filter { $0.isEnabled(in: model.settingsStore.settings) && $0 != .lockScreen }
    }
}

private extension IslandModule {
    func isEnabled(in settings: FeatureSettings) -> Bool {
        switch self {
        case .shelf: settings.fileShelfEnabled
        case .clipboard: settings.clipboardHistoryEnabled
        case .aiMonitor: settings.aiProgressEnabled
        case .download: settings.downloaderEnabled
        case .agenda: settings.calendarEnabled || settings.weatherEnabled
        case .mail: settings.mailEnabled
        case .quickNotes: settings.quickNotesEnabled
        case .toolbox: settings.toolboxEnabled
        case .system: settings.systemMonitorEnabled
        case .lockScreen: settings.lockScreenInfoEnabled
        }
    }
}
