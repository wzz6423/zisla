import AppKit
import ZislaCore
import ZislaKit
import SwiftUI

struct IslandRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var petController: IslandPetController
    @ObservedObject private var settingsStore: FeatureSettingsStore
    @ObservedObject private var voiceInput: VoiceInputController
    @ObservedObject private var backgroundSounds: SystemBackgroundSoundService
    var onPointerEntered: () -> Void
    var onPointerExited: () -> Void
    var onPinChanged: (Bool) -> Void
    var onTransientInteractionChanged: (Bool) -> Void
    var onSettingsRequested: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var dropState = IslandDropState()
    @StateObject private var cleanupPanelPresentation = SystemCleanupPanelPresentationState()

    init(
        model: AppModel,
        petController: IslandPetController,
        onPointerEntered: @escaping () -> Void,
        onPointerExited: @escaping () -> Void,
        onPinChanged: @escaping (Bool) -> Void,
        onTransientInteractionChanged: @escaping (Bool) -> Void,
        onSettingsRequested: @escaping () -> Void
    ) {
        _model = ObservedObject(wrappedValue: model)
        _petController = ObservedObject(wrappedValue: petController)
        _settingsStore = ObservedObject(wrappedValue: model.settingsStore)
        _voiceInput = ObservedObject(wrappedValue: model.voiceInput)
        _backgroundSounds = ObservedObject(wrappedValue: model.backgroundSounds)
        self.onPointerEntered = onPointerEntered
        self.onPointerExited = onPointerExited
        self.onPinChanged = onPinChanged
        self.onTransientInteractionChanged = onTransientInteractionChanged
        self.onSettingsRequested = onSettingsRequested
    }

    var body: some View {
        GeometryReader { proxy in
            let surfaceSize = IslandSurfaceTransform.fittingSize(
                contentSize: layout.panelSize,
                availableSize: proxy.size
            )
            // The slot stays reserved while the island is collapsed: dropping it would shift the
            // surface back to the panel center at the exact frame the recycle fold starts, so the
            // fold would jump sideways before it ever reached the notch.
            let reservesPetSlot = !model.isMirrorPresented
                && !model.isTeleprompterPresented
                && model.settingsStore.settings.petEnabled
            let petSlotWidth = reservesPetSlot
                ? min(
                    ExpandedPetLayout.sideSlotWidth,
                    max(0, proxy.size.width - surfaceSize.width)
                )
                : 0
            let panelSize = CGSize(
                width: surfaceSize.width + petSlotWidth,
                height: surfaceSize.height
            )
            // The reserved slot pushes the surface off the panel center, but the pill still belongs
            // on the notch — the mask converges there instead of on the surface's own middle.
            let collapsedCenterOffsetX = petSlotWidth / 2
                * (settingsStore.settings.petSide == .right ? 1 : -1)
            let voiceRecordingGeometry = VoiceRecordingIslandGeometry(
                collapsedSize: model.collapsedIslandSize,
                availableSize: surfaceSize
            )
            let renderedSurfaceSize = voiceInput.isCapturingInput
                ? voiceRecordingGeometry.surfaceSize
                : surfaceSize

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
                        Button(AppLocalization.text("粘贴并共享")) {
                            model.shareFromPasteboard()
                        }
                        .keyboardShortcut("v", modifiers: .command)
                    }
                    .onPasteCommand(of: TransferDropDelegate.supportedContentTypes) { _ in
                        model.shareFromPasteboard()
                    }

                    Spacer(minLength: max(0, surfaceSize.width - 216))

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
                .frame(width: surfaceSize.width)
                .padding(.top, 62)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(0)
            }

            IslandSurface(
                isCollapsed: isIslandCollapsed,
                collapsedSize: model.collapsedIslandSize,
                expandedSize: renderedSurfaceSize,
                visualStyle: settingsStore.settings.islandVisualStyle,
                notchBackground: settingsStore.settings.islandNotchBackground,
                usesCompactGlassSurface: voiceInput.isCapturingInput,
                collapsedCenterOffsetX: collapsedCenterOffsetX
            ) {
                if model.isMirrorPresented {
                    DeferredMount {
                        CameraMirrorView(onClose: model.dismissMirror)
                            .frame(
                                width: surfaceSize.width,
                                height: surfaceSize.height
                            )
                    }
                } else if model.isTeleprompterPresented {
                    DeferredMount {
                        TeleprompterView(onClose: model.dismissTeleprompter)
                            .frame(
                                width: surfaceSize.width,
                                height: surfaceSize.height
                            )
                    }
                } else {
                    ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        if voiceInput.isCapturingInput {
                            VoiceTranscriptionView(
                                voiceInput: voiceInput,
                                geometry: voiceRecordingGeometry
                            )
                                .frame(height: layout.islandSize.height, alignment: .top)
                        } else if !isIslandCollapsed {
                            // Keep the top shell fixed so module changes replace only the functional area below.
                            NowPlayingHeader(model: model)
                                .padding(.horizontal, 14)
                                .padding(.top, contentTopInset)
                                .padding(.bottom, 4)
                                .environment(\.colorScheme, .dark)

                            toolRail
                                .transaction { transaction in
                                    transaction.animation = nil
                                }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 7)
                                .environment(\.colorScheme, .dark)

                            Group {
                                if let activeModule {
                                    DeferredMount {
                                        switch activeModule {
                                        case .dashboard:
                                            IslandDashboardView(model: model)
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
                                            MailModuleView(
                                                model: model,
                                                onTransientInteractionChanged: onTransientInteractionChanged
                                            )
                                        case .quickNotes:
                                            QuickNoteModuleView(model: model)
                                        case .pdf:
                                            PDFToolsModuleView(model: model)
                                        case .toolbox:
                                            ToolboxModuleView(
                                                model: model,
                                                onTransientInteractionChanged: onTransientInteractionChanged
                                            )
                                        case .system:
                                            SystemMonitorView(
                                                service: model.systemMonitor,
                                                onCleanupRequested: cleanupPanelPresentation.present
                                            )
                                        case .battery:
                                            BatteryDetailView(
                                                batteryMonitor: model.battery,
                                                networkMonitor: model.networkBattery,
                                                onContentHeightChange: model.setBatteryModuleDynamicHeight
                                            )
                                        case .lockScreen:
                                            LockScreenModuleView(model: model)
                                        case .keyboardSound:
                                            KeyboardSoundModuleView(model: model)
                                        }
                                    }
                                } else {
                                    ContentUnavailableView {
                                        Label(AppLocalization.text("没有启用模块"), systemImage: "rectangle.slash")
                                    }
                                }
                            }
                            .padding(.horizontal, IslandSurfaceGeometry.moduleInset)
                            .padding(.top, IslandSurfaceGeometry.moduleInset)
                            .padding(.bottom, IslandSurfaceGeometry.moduleInset)
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: activeModule == .dashboard ? nil : .infinity,
                                alignment: .top
                            )
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
                            .id(activeModule?.rawValue)
                            .transition(
                                reduceMotion
                                    ? .identity
                                    : .modulePush(direction: model.moduleSwitchDirection)
                            )
                            .animation(reduceMotion ? nil : ZislaMotion.moduleSwitch, value: activeModule)
                            // Lower modules sit on dark frosted glass, so force dark mode for legible light text.
                            .environment(\.colorScheme, .dark)
                        }
                    }

                    if !isIslandCollapsed {
                        uptimeIndicator
                    }
                    }
                    // Must be top-aligned: module pages carry incompressible minimum heights, so
                    // while the panel is still at the previous module's smaller size this stack is
                    // taller than `surfaceSize`. Default centering would push the whole chrome above
                    // the surface (-87pt for dashboard → mail) and slide it back down as the resize
                    // spring runs — read as the page dropping in from the top. Top alignment keeps
                    // the crown at y=0 and lets only the module region below overflow into the mask.
                    .frame(width: surfaceSize.width, height: surfaceSize.height, alignment: .top)
                }
            }
            .frame(width: surfaceSize.width, height: surfaceSize.height)
            .frame(
                width: panelSize.width,
                height: surfaceSize.height,
                alignment: islandSurfaceAlignment
            )
            // Springs the surface between module layout sizes; the NSPanel itself snaps
            // (two-phase, see scheduleExpandedSizeUpdate) while all visible motion is drawn here.
            // With the top-aligned frame above, this resize only moves the island's bottom edge.
            .animation(reduceMotion ? nil : ZislaMotion.surfaceResize, value: surfaceSize)
            .environment(\.colorScheme, .dark)
            .environment(\.islandVisualStyle, settingsStore.settings.islandVisualStyle)
            .contentShape(IslandSilhouette())
            .onHover { hovering in
                if hovering { onPointerEntered() } else { onPointerExited() }
            }
            .opacity(hidesIslandSurface ? 0 : 1)
            .zIndex(1)

            if petSlotWidth == ExpandedPetLayout.sideSlotWidth, !isIslandCollapsed {
                expandedPetOverlay
                    .frame(
                        width: panelSize.width,
                        height: surfaceSize.height,
                        alignment: expandedPetAlignment
                    )
                    .zIndex(2)
            }

            }
            // Only the recycle is animated: the surface and everything mounted inside it dissolve
            // while the mask folds back into the notch, instead of blinking out the moment the
            // pointer leaves. Reveals keep snapping to full opacity so the pill never ghosts.
            .animation(
                reduceMotion || !hidesIslandSurface ? nil : ZislaMotion.islandRecycleFade,
                value: hidesIslandSurface
            )
            .frame(
                width: panelSize.width,
                height: surfaceSize.height,
                alignment: .top
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(
            SystemCleanupPanelPresenter(
                presentationState: cleanupPanelPresentation,
                service: model.systemMonitor
            )
        )
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
                    model.selectModule(.system)
                }
            }
            BackgroundSoundControl(
                service: backgroundSounds,
                selectedSound: settingsStore.settings.systemBackgroundSound,
                onToggle: model.toggleBackgroundSound,
                onSelect: model.selectBackgroundSound
            )
            IconButton(
                symbol: model.isPinned ? "pin.fill" : "pin",
                help: model.isPinned ? AppLocalization.text("取消固定") : AppLocalization.text("固定灵动岛"),
                isActive: model.isPinned
            ) {
                model.isPinned.toggle()
                onPinChanged(model.isPinned)
            }
            IconButton(symbol: "gearshape.fill", help: AppLocalization.text("设置")) {
                onSettingsRequested()
            }
        }
        .frame(height: 30)
    }

    private var isIslandCollapsed: Bool {
        (!model.isIslandVisible && !model.isMirrorPresented && !model.isTeleprompterPresented)
            || (voiceInput.isCapturingInput && !model.isMirrorPresented && !model.isTeleprompterPresented)
    }

    private var hidesIslandSurface: Bool {
        !model.isIslandVisible
            && !voiceInput.isCapturingInput
            && !model.isMirrorPresented
            && !model.isTeleprompterPresented
    }

    private var contentTopInset: CGFloat { ExpandedPetLayout.contentTopInset }

    @ViewBuilder
    private var expandedPetOverlay: some View {
        if model.settingsStore.settings.petEnabled,
           let sprite = petController.sprite {
            IslandPetView(
                sprite: sprite,
                behavior: petController.behavior,
                side: model.settingsStore.settings.petSide,
                size: ExpandedPetLayout.size
            )
            .padding(.top, ExpandedPetLayout.topInset)
            .padding(
                model.settingsStore.settings.petSide == .right ? .trailing : .leading,
                ExpandedPetLayout.outerInset
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
                .padding(.top, 4)
                .padding(.trailing, 14)
        }
        .allowsHitTesting(false)
    }

    private var uptimeAlignment: Alignment {
        .topTrailing
    }

    private var expandedPetAlignment: Alignment {
        model.settingsStore.settings.petSide == .right ? .topTrailing : .topLeading
    }

    /// Matches `reservesPetSlot`: the surface keeps hugging the same panel edge while collapsed, so
    /// the recycle fold starts exactly where the expanded surface stood.
    private var islandSurfaceAlignment: Alignment {
        guard model.settingsStore.settings.petEnabled,
              !model.isMirrorPresented,
              !model.isTeleprompterPresented else {
            return .top
        }
        return model.settingsStore.settings.petSide == .right ? .topLeading : .topTrailing
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
        if model.isMirrorPresented {
            return .mirror
        }
        if model.isTeleprompterPresented {
            return .teleprompter
        }
        if voiceInput.isCapturingInput {
            // The recording surface matches the collapsed capsule's overflow width and extends downward by one row.
            return IslandModuleLayout.voiceRecording
                .matchingWidth(model.collapsedOverflowWidth)
        }
        guard let activeModule else { return .standard }
        return IslandModuleLayout.resolved(
            for: activeModule,
            dashboardCardCount: model.dashboardCardCount,
            batteryDynamicHeight: model.batteryModuleDynamicHeight
        )
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
        .buttonStyle(PressableStyle(hoverScale: 1.02, pressedScale: 0.97))
        .help("\(title)：\(detail)")
    }

    private func shoulderBackground(targeted: Bool) -> Color {
        Color.black.opacity(targeted ? 0.96 : 0.86)
    }
}

enum ExpandedPetLayout {
    static let size: CGFloat = 30
    static let topInset: CGFloat = 8
    static let contentTopInset: CGFloat = 8
    static let outerInset: CGFloat = 6
    static let islandGap: CGFloat = 8
    static let sideSlotWidth = size + outerInset + islandGap

    static func panelSize(for surfaceSize: CGSize, includesPet: Bool) -> CGSize {
        guard includesPet else { return surfaceSize }
        return CGSize(width: surfaceSize.width + sideSlotWidth, height: surfaceSize.height)
    }
}

struct CollapsedPetView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var petController: IslandPetController
    var isOnPhysicalNotch: Bool

    var body: some View {
        GeometryReader { proxy in
            if model.settingsStore.settings.petEnabled,
               let sprite = petController.sprite {
                let horizontalInset = CollapsedPetLayout.outerGap
                let verticalInset = min(4, max(2, proxy.size.height * 0.1))
                let size = max(
                    0,
                    min(
                        CollapsedPetLayout.maximumPetSize,
                        proxy.size.width - horizontalInset * 2,
                        proxy.size.height - verticalInset * 2
                    )
                )
                let side = model.settingsStore.settings.petSide
                IslandPetView(
                    sprite: sprite,
                    behavior: petController.behavior,
                    side: side,
                    size: size
                )
                .padding(
                    side == .right ? .trailing : .leading,
                    horizontalInset
                )
                .padding(.top, verticalInset)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: side == .right ? .topTrailing : .topLeading
                )
            }
        }
    }

}

private struct VoiceTranscriptionView: View {
    @ObservedObject var voiceInput: VoiceInputController
    let geometry: VoiceRecordingIslandGeometry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(voiceInput.isRecording ? Color.zislaError : .white.opacity(0.45))
                    .accessibilityLabel(voiceInput.isRecording ? AppLocalization.text("正在录音") : AppLocalization.text("正在准备录音"))

                Spacer(minLength: 12)

                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolEffect(
                        .variableColor.iterative,
                        options: .repeating,
                        isActive: !reduceMotion
                    )
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(
                width: geometry.topRowFrame.width,
                height: geometry.topRowFrame.height
            )

            MarqueeText(
                transcriptOrPlaceholder,
                font: .system(size: 10.5),
                textColor: .white.opacity(0.72),
                fontWeight: .medium,
                repeats: false,
                scrollProgress: 1,
                clipsOverflowWhenStatic: true
            )
                .padding(.horizontal, 12)
                .frame(
                    width: geometry.transcriptRowFrame.width,
                    height: geometry.transcriptRowFrame.height,
                    alignment: .leading
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var transcriptOrPlaceholder: String {
        if let error = voiceInput.errorDescription { return error }
        // Only a live take may put text here. The surface opens on the keypress, so while the engine
        // spins up the row stays a bare ellipsis rather than claiming to listen.
        guard voiceInput.isRecording else { return "…" }
        let text = voiceInput.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "正在聆听…" : text
    }
}

@MainActor
private final class IslandDropState: ObservableObject {
    @Published var shareTargeted = false
    @Published var shelfTargeted = false
}

private struct BackgroundSoundControl: View {
    @ObservedObject var service: SystemBackgroundSoundService
    let selectedSound: SystemBackgroundSound
    let onToggle: () -> Void
    let onSelect: (SystemBackgroundSound) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 0) {
                    IconButtonLabel(
                        symbol: service.isDownloading(selectedSound)
                            ? "arrow.down.circle"
                            : (service.isPlaying ? "waveform" : "waveform.slash"),
                        isActive: service.isPlaying,
                        activeColor: .mint,
                        size: .compact,
                        // The shared capsule below provides the control surface.
                        showsActiveBackground: false,
                        showsInactiveBackground: false
                    )

                    Text(controlTitle)
                        .font(.islandMicro(weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 2)
                        .padding(.trailing, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .help(toggleHelp)
            .accessibilityLabel(toggleHelp)

            Menu {
                ForEach(service.availableSounds, id: \.self) { sound in
                    if service.downloadState(for: sound) == .queued {
                        Button {} label: {
                            Label(AppLocalization.text("等待下载 %@…", sound.title), systemImage: "clock")
                        }
                        .disabled(true)
                    } else if service.isDownloading(sound) {
                        Button {} label: {
                            Label(AppLocalization.text("正在下载 %@…", sound.title), systemImage: "arrow.down.circle")
                        }
                        .disabled(true)
                    } else if service.isInstalled(sound) {
                        Button {
                            onSelect(sound)
                        } label: {
                            Label(
                                sound.title,
                                systemImage: sound == selectedSound ? "checkmark" : "waveform"
                            )
                        }
                    } else {
                        Button {
                            onSelect(sound)
                        } label: {
                            let title = service.downloadState(for: sound) == nil
                                ? "\(sound.title)（下载）"
                                : "\(sound.title)（重试下载）"
                            Label(title, systemImage: "arrow.down.circle")
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 19, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(AppLocalization.text("选择背景音：%@", selectedSound.title))
            .accessibilityLabel(AppLocalization.text("选择背景音：%@", selectedSound.title))
            .onHover { hovering in
                if hovering { service.refresh() }
            }
        }
        .padding(.leading, 2)
        .padding(.trailing, 6)
        .frame(height: 28)
        .background(
            Capsule()
                .fill(service.isPlaying ? Color.mint.opacity(0.16) : Color.fillControl)
        )
        .animation(ZislaMotion.selection, value: service.isPlaying)
    }

    private var controlTitle: String {
        service.isPlaying ? (service.playingSound?.title ?? "背景音") : "背景音"
    }

    private var isSelectedSoundQueued: Bool {
        service.downloadState(for: selectedSound) == .queued
    }

    private var toggleHelp: String {
        if isSelectedSoundQueued { return AppLocalization.text("背景音等待下载，点击取消") }
        if service.isDownloading(selectedSound) { return AppLocalization.text("正在下载背景音，点击取消") }
        return service.isPlaying ? AppLocalization.text("关闭背景音") : AppLocalization.text("开启背景音")
    }
}

/// Compact navigation-bar monitor showing percentages above CPU, GPU, RAM, and disk labels.
/// It appears only when system monitoring is enabled, opens that module when tapped, and changes percentages
/// to orange or red when they exceed thresholds.
private struct NavMonitorStrip: View {
    @ObservedObject var monitor: SystemMonitorService
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                metricCell(label: "CPU", ratio: cpuRatio)
                metricCell(label: "GPU", ratio: gpuRatio)
                metricCell(label: "RAM", ratio: memRatio)
                metricCell(label: "Disk", ratio: diskRatio)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color.fillControl)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(AppLocalization.text("系统监控实时读数 — 点按查看详情"))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(visibleModules) { module in
                let isSelected = model.selectedModule == module
                Button {
                    model.selectModule(module)
                } label: {
                    IconButtonLabel(
                        symbol: module.symbol,
                        isActive: isSelected,
                        activeColor: .primary,
                        size: .compact,
                        dimmedWhenInactive: true,
                        // The moving focus lens below provides the active surface.
                        showsActiveBackground: false,
                        showsInactiveBackground: false
                    )
                }
                .frame(width: 28, height: 30)
                .buttonStyle(PressableStyle(hoverScale: 1.08))
                .background {
                    if isSelected {
                        MotionFocusLens(cornerRadius: 8)
                            .matchedGeometryEffect(id: "module-selection", in: selectionNamespace)
                    }
                }
                .help(AppLocalization.text(module.title))
            }
        }
        .animation(reduceMotion ? nil : ZislaMotion.selection, value: model.selectedModule)
    }

    private var visibleModules: [IslandModule] {
        IslandModule.allCases.filter { $0.isEnabled(in: model.settingsStore.settings) && $0 != .lockScreen }
    }
}
