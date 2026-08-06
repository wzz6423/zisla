import AppKit
import Combine
import ZislaCore
import ZislaKit
import SwiftUI

@main
enum ZislaMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}

@MainActor
private final class SettingsWindow: NSWindow {
    override func performClose(_ sender: Any?) {
        // Settings window has no close workflow; keep the instance alive so it can be restored from the menu bar.
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var overlayCoordinator: OverlayCoordinator?
    private var lockScreenOverlayController: LockScreenOverlayController?
    private var noticePresenter: SideNoticePresenter?
    private var petController: IslandPetController?
    private var statusItem: NSStatusItem?
    private var monitorStatusItems: [SystemMonitorMenuBarMetric: NSStatusItem] = [:]
    private var monitorStatusItemStyles: [SystemMonitorMenuBarMetric: SystemMonitorMenuBarDisplayStyle] = [:]
    private var monitorStatusTitles: [SystemMonitorMenuBarMetric: String] = [:]
    private var lastMonitorStatusRefreshAt = Date.distantPast
    private var settingsWindowController: NSWindowController?
    private var settingsWindowScreen: NSScreen?
    private var quickNotesEditorController: NSWindowController?
    private var cancellables: Set<AnyCancellable> = []
    private var effectiveAppearanceObservation: NSKeyValueObservation?
    private var currentApplicationIconImage: NSImage?
    private let updateController = UpdateController.shared
    private var expandedSizeUpdateTask: Task<Void, Never>?
    /// Last panel size actually applied to the coordinator; basis for the two-phase
    /// (union → target) resize that keeps the SwiftUI surface spring unclipped.
    private var lastAppliedPanelSize: CGSize?
    /// Panel size saved before voice recording starts; restored when recording ends.
    private var voiceRecordingSavedPanelSize: CGSize?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyAppDataMigration.migrateUserDefaults()
        guard acquireSingleInstance() else {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        WindowPlacement.installTransientWindowPromotion()
        let model = AppModel.shared
        updateController.start(
            automaticallyChecks: model.settingsStore.settings.updateChecksEnabled,
            automaticallyDownloads: model.settingsStore.settings.automaticUpdatesEnabled,
            automaticChannel: FeatureSettingsStore.bundledDefaultUpdateChannel
        )
        model.start()
        configureApplicationIconUpdates(model: model)
        let lockScreenOverlayController = LockScreenOverlayController(model: model)
        lockScreenOverlayController.start()
        self.lockScreenOverlayController = lockScreenOverlayController

        let petController = IslandPetController(model: model)
        self.petController = petController
        petController.start()

        let rootView = IslandRootView(
            model: model,
            petController: petController,
            onPointerEntered: { [weak self] in
                self?.overlayCoordinator?.handlePointer(at: NSEvent.mouseLocation)
            },
            onPointerExited: { [weak self] in
                self?.overlayCoordinator?.handlePointer(at: NSEvent.mouseLocation)
            },
            onPinChanged: { [weak self] pinned in
                self?.overlayCoordinator?.setPinned(pinned)
            },
            onSettingsRequested: { [weak self] in
                self?.showSettings()
            }
        )
        let hostingView = NSHostingView(
            rootView: AppLanguageEnvironment(languageStore: model.languageStore, content: rootView)
        )
        hostingView.sizingOptions = []
        let engine = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            simulatedIslandSize: CGSize(width: 240, height: 34),
            expandedSize: Self.expandedPanelSize(
                module: model.selectedModule,
                isMirrorPresented: model.isMirrorPresented,
                isTeleprompterPresented: model.isTeleprompterPresented,
                dashboardCardCount: model.dashboardCardCount,
                includesPet: model.settingsStore.settings.petEnabled
            ).panelSize,
            horizontalMargin: 12
        ))
        let coordinator = OverlayCoordinator(
            contentView: hostingView,
            layoutEngine: engine,
            persistentContentViewProvider: { [weak petController] layout in
                guard let petController else { return nil }
                let persistentPetView = CollapsedPetView(
                    model: model,
                    petController: petController,
                    isOnPhysicalNotch: layout.topology.hasPhysicalNotch
                )
                let persistentPetHostingView = NSHostingView(
                    rootView: AppLanguageEnvironment(
                        languageStore: model.languageStore,
                        content: persistentPetView
                    )
                )
                persistentPetHostingView.sizingOptions = []
                return persistentPetHostingView
            },
            persistentPanelFrameProvider: { layout in
                CollapsedPetLayout.frame(
                    for: layout,
                    compactBarFrame: Self.collapsedPetCompactBarFrame(
                        for: layout,
                        notices: model.notices.left + model.notices.right,
                        settings: model.settingsStore.settings
                    )
                )
            }
        )
        coordinator.onVisibilityChanged = { [weak self] visible in
            model.isIslandVisible = visible
            self?.noticePresenter?.setIslandExpanded(visible)
            if visible { model.refreshForExpansion() }
        }
        coordinator.onDraggingChanged = { dragging in
            model.isExternalDragging = dragging
        }
        coordinator.onCollapsedSizeChanged = { size in
            model.collapsedIslandSize = size
        }
        coordinator.onActiveDisplayHasPhysicalNotchChanged = { hasPhysicalNotch in
            model.isIslandOnPhysicalNotch = hasPhysicalNotch
        }
        Publishers.CombineLatest(
            Publishers.CombineLatest4(
                model.$selectedModule,
                model.$isMirrorPresented,
                model.$isTeleprompterPresented,
                model.$dashboardCardCount
            ),
            model.settingsStore.$settings
                .map(\.petEnabled)
                .removeDuplicates()
        )
            .map { state, includesPet -> CGSize in
                let (module, isMirrorPresented, isTeleprompterPresented, dashboardCardCount) = state
                return Self.expandedPanelSize(
                    module: module,
                    isMirrorPresented: isMirrorPresented,
                    isTeleprompterPresented: isTeleprompterPresented,
                    dashboardCardCount: dashboardCardCount,
                    includesPet: includesPet
                ).panelSize
            }
            .removeDuplicates()
            .sink { [weak self, weak coordinator] size in
                guard !model.voiceInput.isRecording else { return }
                self?.scheduleExpandedSizeUpdate(size, coordinator: coordinator)
            }
            .store(in: &cancellables)
        model.$isMirrorPresented
            .combineLatest(model.$isTeleprompterPresented)
            .sink { [weak coordinator, weak model] isMirrorPresented, isTeleprompterPresented in
                Task { @MainActor in
                    guard let model else { return }
                    coordinator?.setPinned(isMirrorPresented || isTeleprompterPresented || model.isPinned)
                }
            }
            .store(in: &cancellables)
        overlayCoordinator = coordinator
        coordinator.setPersistentContentVisible(model.settingsStore.settings.petEnabled)
        coordinator.setCollapsedOnTop(model.settingsStore.settings.islandCollapsedOnTop)
        if model.settingsStore.settings.hoverActivationEnabled
            || model.settingsStore.settings.petEnabled {
            coordinator.start()
        }
        if ProcessInfo.processInfo.environment["ZISLA_VISUAL_TEST_SHOW"] == "1" {
            coordinator.start()
            model.isPinned = true
            coordinator.setPinned(true)
        }

        noticePresenter = SideNoticePresenter(
            queue: model.notices,
            media: model.media,
            settingsStore: model.settingsStore,
            languageStore: model.languageStore,
            displayIDs: model.settingsStore.settings.activityNoticeDisplayIDs
        )
        configureMainMenu()
        syncAppStatusItem()
        syncMonitorStatusItems(force: true)

        model.languageStore.$language
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshLocalizedChrome()
            }
            .store(in: &cancellables)

        model.systemMonitor.$snapshot
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.syncMonitorStatusItems() }
            }
            .store(in: &cancellables)

        model.settingsStore.$settings
            .map(\.hoverActivationEnabled)
            .removeDuplicates()
            .sink { [weak self] enabled in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if enabled {
                        self.overlayCoordinator?.start()
                    } else if !model.settingsStore.settings.petEnabled && !model.isPinned {
                        self.overlayCoordinator?.stop()
                    }
                }
            }
            .store(in: &cancellables)

        model.settingsStore.$settings
            .map(\.islandCollapsedOnTop)
            .removeDuplicates()
            .sink { [weak self] onTop in
                Task { @MainActor [weak self] in
                    self?.overlayCoordinator?.setCollapsedOnTop(onTop)
                }
            }
            .store(in: &cancellables)

        model.settingsStore.$settings
            .map(\.islandVisualStyle)
            .removeDuplicates()
            .sink { [weak self] style in
                Task { @MainActor [weak self] in
                    self?.overlayCoordinator?.setKeepsNativeGlassActive(style == .transparent)
                }
            }
            .store(in: &cancellables)

        model.settingsStore.$settings
            .map(\.petEnabled)
            .removeDuplicates()
            .sink { [weak coordinator, weak model] enabled in
                Task { @MainActor in
                    coordinator?.setPersistentContentVisible(enabled)
                    guard let model else { return }
                    if enabled {
                        coordinator?.start()
                    } else if !model.settingsStore.settings.hoverActivationEnabled && !model.isPinned {
                        coordinator?.stop()
                    }
                }
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            model.settingsStore.$settings.map { _ in () }.eraseToAnyPublisher(),
            model.notices.$left.map { _ in () }.eraseToAnyPublisher(),
            model.notices.$right.map { _ in () }.eraseToAnyPublisher()
        )
            .sink { [weak coordinator] _ in
                Task { @MainActor in
                    coordinator?.refreshPersistentPanels()
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            model.$detectedLink.map { $0 != nil },
            model.$isSharingPickerVisible
        )
            .map { detectedLinkVisible, sharingPickerVisible in
                detectedLinkVisible || sharingPickerVisible
            }
            .removeDuplicates()
            .sink { [weak coordinator] visible in
                Task { @MainActor in
                    coordinator?.setTransientInteractionVisible(visible)
                }
            }
            .store(in: &cancellables)

        model.settingsStore.$settings
            .sink { [weak self] settings in
                Task { @MainActor [weak self] in
                    self?.noticePresenter?.setDisplayIDs(settings.activityNoticeDisplayIDs)
                    self?.updateController.configure(
                        automaticallyChecks: settings.updateChecksEnabled,
                        automaticallyDownloads: settings.automaticUpdatesEnabled,
                        automaticChannel: FeatureSettingsStore.bundledDefaultUpdateChannel
                    )
                    self?.syncAppStatusItem()
                    self?.syncMonitorStatusItems(force: true)
                }
            }
            .store(in: &cancellables)

        // Quick Notes and Mail require keyboard input: allow the island panel to become key only
        // while the corresponding module is visible; otherwise keep it non-key to avoid stealing
        // focus from other apps.
        Publishers.CombineLatest(
            model.$selectedModule,
            model.$isIslandVisible
        )
            .sink { [weak coordinator] module, visible in
                Task { @MainActor in
                    coordinator?.setAllowsKeyWindow(
                        visible && (module == .quickNotes || module == .mail)
                    )
                }
            }
            .store(in: &cancellables)

        // Voice recording: expand the island to one row and show live transcription below.
        // Recording starts → save current panel size, switch to compact size, expand the island.
        // Recording ends → restore panel size and collapse the island.
        model.voiceInput.$isRecording
            .removeDuplicates()
            .sink { [weak self] recording in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if recording {
                        let model = AppModel.shared
                        self.voiceRecordingSavedPanelSize = Self.expandedPanelSize(
                            module: model.selectedModule,
                            isMirrorPresented: model.isMirrorPresented,
                            isTeleprompterPresented: model.isTeleprompterPresented,
                            dashboardCardCount: model.dashboardCardCount,
                            includesPet: model.settingsStore.settings.petEnabled
                        ).panelSize
                        // Direct resize (no two-phase): recording swaps layout instantly by design.
                        self.expandedSizeUpdateTask?.cancel()
                        let recordingSize = CGSize(width: 660, height: 76)
                        self.overlayCoordinator?.updateExpandedSize(recordingSize)
                        self.lastAppliedPanelSize = recordingSize
                        self.overlayCoordinator?.setTransientInteractionVisible(true)
                    } else {
                        self.overlayCoordinator?.setTransientInteractionVisible(false)
                        if let saved = self.voiceRecordingSavedPanelSize {
                            self.overlayCoordinator?.updateExpandedSize(saved)
                            self.lastAppliedPanelSize = saved
                            self.voiceRecordingSavedPanelSize = nil
                        }
                    }
                }
            }
            .store(in: &cancellables)

        // While the disk-cleanup panel is visible: keep the island expanded to prevent it from
        // collapsing when the pointer leaves the island area.
        model.$isCleanupPanelVisible
            .removeDuplicates()
            .sink { [weak coordinator] visible in
                Task { @MainActor in
                    coordinator?.setTransientInteractionVisible(visible)
                }
            }
            .store(in: &cancellables)

        // After disk cleanup completes: release the pin and transient interaction hold, triggering island collapse.
        model.$islandCollapseRequested
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak coordinator] _ in
                Task { @MainActor in
                    coordinator?.setPinned(false)
                    coordinator?.setTransientInteractionVisible(false)
                    AppModel.shared.isPinned = false
                    AppModel.shared.islandCollapseRequested = false
                }
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        expandedSizeUpdateTask?.cancel()
        lockScreenOverlayController?.stop()
        AppModel.shared.stop()
        noticePresenter?.stop()
        petController?.stop()
        overlayCoordinator?.stop()
    }

    private func scheduleExpandedSizeUpdate(
        _ size: CGSize,
        coordinator: OverlayCoordinator?
    ) {
        expandedSizeUpdateTask?.cancel()
        expandedSizeUpdateTask = Task { @MainActor [weak self, weak coordinator] in
        // Defer module button event handling to the next run-loop turn before resizing the NSPanel
        // frame, avoiding a spurious "mouse exited" AppKit hit-test triggered mid-click.
        // For rapid module switches, only the last size is applied.
            await Task.yield()
            guard !Task.isCancelled, let coordinator else { return }
            // Two-phase resize: the panel window itself never animates (see IslandPanel.resize),
            // so first grow it to the union of current and target sizes, giving the SwiftUI
            // surface spring full drawing room in both directions. Once the spring has settled,
            // tighten the panel down to the exact target so pointer tracking stays accurate.
            let current = self?.lastAppliedPanelSize
            let union = CGSize(
                width: max(size.width, current?.width ?? 0),
                height: max(size.height, current?.height ?? 0)
            )
            if union != current {
                coordinator.updateExpandedSize(union)
                self?.lastAppliedPanelSize = union
            }
            if union != size {
                try? await Task.sleep(for: ZislaMotion.surfaceResizeSettleDelay)
                guard !Task.isCancelled else { return }
                coordinator.updateExpandedSize(size)
                self?.lastAppliedPanelSize = size
            }
            self?.expandedSizeUpdateTask = nil
        }
    }

    private static func expandedPanelSize(
        module: IslandModule,
        isMirrorPresented: Bool,
        isTeleprompterPresented: Bool,
        dashboardCardCount: Int,
        includesPet: Bool
    ) -> IslandModuleLayout {
        if isMirrorPresented { return .mirror }
        if isTeleprompterPresented { return .teleprompter }
        let layout = IslandModuleLayout.resolved(
            for: module,
            dashboardCardCount: dashboardCardCount
        )
        return IslandModuleLayout(
            islandSize: layout.islandSize,
            panelSize: ExpandedPetLayout.panelSize(
                for: layout.panelSize,
                includesPet: includesPet
            )
        )
    }

    private static func collapsedPetCompactBarFrame(
        for layout: ScreenOverlayLayout,
        notices: [IslandNotice],
        settings: FeatureSettings
    ) -> CGRect? {
        let presentation = SideNoticeLayoutEngine().presentation(for: notices)
        let extendsForFocusCountdown = notices.contains {
            $0.id.hasPrefix("focus-countdown-") || $0.id.hasPrefix("focus-transition")
        }
        guard presentation.hasCompactContent || extendsForFocusCountdown else { return nil }
        let expandsForDetailedMedia = settings.mediaCompactStyle == .detailed
            && notices.contains { $0.id.hasPrefix("media-active-") }
        let expandsForDetailedMail = settings.mailCompactStyle == .detailed
            && notices.contains { $0.id.hasPrefix("mail-notification-") }
        return SideNoticeLayoutEngine().compactBarFrame(
            for: layout,
            extendsForFocusCountdown: extendsForFocusCountdown,
            expandsForDetailedMedia: expandsForDetailedMedia || expandsForDetailedMail
        )
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let applicationMenuItem = NSMenuItem(title: "zisla", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "zisla")
        let quitItem = applicationMenu.addItem(
            withTitle: localized("退出 zisla"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = .command
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)

        let windowMenuItem = NSMenuItem(title: localized("窗口"), action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: localized("窗口"))
        let minimizeItem = windowMenu.addItem(
            withTitle: localized("最小化"),
            action: #selector(NSWindow.miniaturize(_:)),
            keyEquivalent: "m"
        )
        minimizeItem.keyEquivalentModifierMask = .command
        let closeItem = windowMenu.addItem(
            withTitle: localized("关闭窗口"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeItem.keyEquivalentModifierMask = .command
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func configureApplicationIconUpdates(model: AppModel) {
        model.settingsStore.$settings
            .map(\.appearanceMode)
            .removeDuplicates()
            .sink { [weak self] mode in
                Task { @MainActor [weak self] in
                    self?.syncApplicationIcon(mode: mode)
                }
            }
            .store(in: &cancellables)

        effectiveAppearanceObservation = NSApp.observe(
            \.effectiveAppearance,
            options: [.initial, .new]
        ) { [weak self, weak model] _, _ in
            Task { @MainActor [weak self, weak model] in
                guard let model else { return }
                self?.syncApplicationIcon(mode: model.settingsStore.settings.appearanceMode)
            }
        }
    }

    private func syncApplicationIcon(mode: AppearanceMode) {
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let theme = ApplicationIconTheme.resolve(mode: mode, systemIsDark: systemIsDark)
        let resourceName = theme == .night ? "AppIconNight" : "AppIcon"
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "icns"),
              let image = NSImage(contentsOf: url)
        else { return }
        currentApplicationIconImage = image
        NSApp.applicationIconImage = image
        syncStatusItemImage()
    }

    private func syncStatusItemImage() {
        guard let image = currentApplicationIconImage?.copy() as? NSImage else { return }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        statusItem?.button?.image = image
    }

    private func syncAppStatusItem() {
        guard AppModel.shared.settingsStore.settings.menuBarAppIconEnabled else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.inset.filled", accessibilityDescription: "zisla")
        let menu = NSMenu()
        menu.addItem(withTitle: localized("显示灵动岛"), action: #selector(showIsland), keyEquivalent: "")
        menu.addItem(withTitle: localized("系统监控"), action: #selector(showSystemMonitor), keyEquivalent: "")
        menu.addItem(withTitle: localized("设置..."), action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: localized("检查更新"), action: #selector(checkUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: localized("退出 zisla"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
        syncStatusItemImage()
    }

    private func syncMonitorStatusItems(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastMonitorStatusRefreshAt) >= 2 else { return }
        lastMonitorStatusRefreshAt = now
        let settings = AppModel.shared.settingsStore.settings
        let selected = settings.systemMonitorEnabled ? settings.systemMonitorMenuBarMetrics : []
        for metric in monitorStatusItems.keys.filter({ !selected.contains($0) }) {
            if let item = monitorStatusItems.removeValue(forKey: metric) {
                NSStatusBar.system.removeStatusItem(item)
            }
            monitorStatusItemStyles.removeValue(forKey: metric)
            monitorStatusTitles.removeValue(forKey: metric)
        }
        for metric in SystemMonitorMenuBarMetric.allCases where selected.contains(metric) {
            let item: NSStatusItem
            if let existing = monitorStatusItems[metric] {
                item = existing
            } else {
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.target = self
                item.button?.action = #selector(showSystemMonitor)
                monitorStatusItems[metric] = item
            }
            let style = settings.systemMonitorMenuBarDisplayStyle
            if monitorStatusItemStyles[metric] != style {
                configureMonitorStatusItem(item, metric: metric, style: style)
                monitorStatusItemStyles[metric] = style
                monitorStatusTitles.removeValue(forKey: metric)
                item.button?.toolTip = "\(localized(metric.menuTitle)): \(localized("点击打开系统监控"))"
                if style == .compact {
                    item.length = compactMonitorStatusItemWidth(for: metric)
                }
            }
            let title = monitorStatusTitle(
                for: metric,
                snapshot: AppModel.shared.systemMonitor.snapshot,
                style: style
            )
            if style == .compact {
                if monitorStatusTitles[metric] != title {
                    item.button?.image = compactMonitorStatusImage(value: title, metric: metric)
                }
            } else {
                item.length = NSStatusItem.variableLength
                if monitorStatusTitles[metric] != title {
                    item.button?.title = title
                }
            }
            monitorStatusTitles[metric] = title
        }
    }

    private func configureMonitorStatusItem(
        _ item: NSStatusItem,
        metric: SystemMonitorMenuBarMetric,
        style: SystemMonitorMenuBarDisplayStyle
    ) {
        guard let button = item.button else { return }
        switch style {
        case .detailed:
            button.image = NSImage(
                systemSymbolName: metric.symbolName,
                accessibilityDescription: localized(metric.menuTitle)
            )
            button.imagePosition = .imageLeading
            button.alignment = .natural
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.cell?.wraps = false
        case .compact:
            button.image = nil
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.title = ""
            button.cell?.wraps = false
        }
    }

    private func monitorStatusTitle(
        for metric: SystemMonitorMenuBarMetric,
        snapshot: SystemMetricsSnapshot?,
        style: SystemMonitorMenuBarDisplayStyle
    ) -> String {
        if style == .compact {
            return compactMonitorStatusValue(for: metric, snapshot: snapshot)
        }
        guard let snapshot else { return "\(localized(metric.menuTitle)) --" }
        switch metric {
        case .cpu:
            return "CPU \(percent(snapshot.cpu.usage))"
        case .gpu:
            guard case let .available(gpu) = snapshot.gpu else { return "GPU --" }
            return "GPU \(percent(gpu.usage))"
        case .memory:
            return "RAM \(byteText(snapshot.memory.usedBytes))"
        case .disk:
            guard snapshot.disk.totalBytes > 0 else { return "\(localized("磁盘")) --" }
            let usage = Double(snapshot.disk.usedBytes) / Double(snapshot.disk.totalBytes)
            return "\(localized("磁盘")) \(percent(usage))"
        case .network:
            return "\(localized("网络")) ↓\(rateText(snapshot.network.receiveBytesPerSecond)) ↑\(rateText(snapshot.network.sendBytesPerSecond))"
        case .fan:
            guard case let .available(rpm, _) = snapshot.fan, let first = rpm.first else {
                return "\(localized("风扇")) --"
            }
            return "\(localized("风扇")) \(Int(first.rounded()))"
        }
    }

    private func compactMonitorStatusValue(
        for metric: SystemMonitorMenuBarMetric,
        snapshot: SystemMetricsSnapshot?
    ) -> String {
        guard let snapshot else { return "--" }
        switch metric {
        case .cpu:
            return percent(snapshot.cpu.usage)
        case .gpu:
            guard case let .available(gpu) = snapshot.gpu else { return "--" }
            return percent(gpu.usage)
        case .memory:
            guard snapshot.memory.totalBytes > 0 else { return "--" }
            return percent(Double(snapshot.memory.usedBytes) / Double(snapshot.memory.totalBytes))
        case .disk:
            guard snapshot.disk.totalBytes > 0 else { return "--" }
            return percent(Double(snapshot.disk.usedBytes) / Double(snapshot.disk.totalBytes))
        case .network:
            return "↓\(rateText(snapshot.network.receiveBytesPerSecond))"
        case .fan:
            guard case let .available(rpm, _) = snapshot.fan, let first = rpm.first else {
                return "--"
            }
            return "\(Int(first.rounded()))"
        }
    }

    private func compactMonitorStatusLabel(for metric: SystemMonitorMenuBarMetric) -> String {
        switch metric {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: localized("内存")
        case .disk: localized("磁盘")
        case .network: localized("网络")
        case .fan: localized("风扇")
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, language: AppModel.shared.languageStore.language)
    }

    private func refreshLocalizedChrome() {
        configureMainMenu()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        syncAppStatusItem()
        monitorStatusItemStyles.removeAll()
        monitorStatusTitles.removeAll()
        syncMonitorStatusItems(force: true)
        settingsWindowController?.window?.title = localized("zisla 设置")
        quickNotesEditorController?.window?.title = localized("随记 · 编辑")
    }

    private func compactMonitorStatusItemWidth(for metric: SystemMonitorMenuBarMetric) -> CGFloat {
        switch metric {
        case .cpu, .gpu, .memory, .disk:
            32
        case .network:
            60
        case .fan:
            40
        }
    }

    private func compactMonitorStatusImage(
        value: String,
        metric: SystemMonitorMenuBarMetric
    ) -> NSImage? {
        let size = NSSize(width: compactMonitorStatusItemWidth(for: metric) - 4, height: 22)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }
        representation.size = size

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 2, y: 2)
        (value as NSString).draw(
            in: NSRect(x: 0, y: 10, width: size.width, height: 12),
            withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph,
            ]
        )
        (compactMonitorStatusLabel(for: metric) as NSString).draw(
            in: NSRect(x: 0, y: 1, width: size.width, height: 10),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .semibold),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph,
            ]
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(representation)
        image.isTemplate = true
        image.accessibilityDescription = metric.menuTitle
        return image
    }

    private func percent(_ value: Double) -> String {
        "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }

    private func byteText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    private func rateText(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytesPerSecond)), countStyle: .file) + "/s"
    }

    @objc private func showIsland() {
        overlayCoordinator?.start()
        AppModel.shared.isPinned = true
        overlayCoordinator?.setPinned(true)
        AppModel.shared.refreshForExpansion()
    }

    @objc private func showSystemMonitor() {
        AppModel.shared.selectSystemMonitor()
        overlayCoordinator?.showExpanded(at: NSEvent.mouseLocation)
        AppModel.shared.refreshForExpansion()
    }

    @objc private func showSettings() {
        let targetScreen = WindowPlacement.screenUnderMouse()
        if settingsWindowController == nil {
            let rootView = SettingsView(model: AppModel.shared)
            let window = SettingsWindow(
                contentRect: CGRect(x: 0, y: 0, width: 548, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = localized("zisla 设置")
            window.level = WindowPlacement.modalWindowLevel
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: AppLanguageEnvironment(
                    languageStore: AppModel.shared.languageStore,
                    content: rootView
                )
            )
            window.delegate = self
            let controller = NSWindowController(window: window)
            controller.shouldCascadeWindows = false
            settingsWindowController = controller
        }
        settingsWindowScreen = targetScreen
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        if let window = settingsWindowController?.window {
            WindowPlacement.center(window, on: targetScreen)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? SettingsWindow else { return }
        WindowPlacement.center(window, on: settingsWindowScreen)
    }

    @objc private func checkUpdates() {
        AppModel.shared.checkForUpdates(manual: true)
    }

    /// Opens the Quick Notes full editor: Markdown editing on the left, rich preview (images/tables)
    /// on the right — far more space than the inline island panel. Reuses `AppModel.shared.quickNotes`
    /// and edits the currently selected note.
    func openQuickNotesEditor() {
        let targetScreen = WindowPlacement.screenUnderMouse()
        if quickNotesEditorController == nil {
            let rootView = QuickNoteExpandedView(model: AppModel.shared)
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 860, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = localized("随记 · 编辑")
            window.level = WindowPlacement.modalWindowLevel
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 640, height: 460)
            let hostingView = NSHostingView(
                rootView: AppLanguageEnvironment(
                    languageStore: AppModel.shared.languageStore,
                    content: rootView
                )
            )
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            window.contentView = hostingView
            quickNotesEditorController = NSWindowController(window: window)
        }
        if let window = quickNotesEditorController?.window {
            WindowPlacement.center(window, on: targetScreen)
        }
        quickNotesEditorController?.showWindow(nil)
        quickNotesEditorController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// A menu-bar app can otherwise be launched repeatedly from Xcode or
    /// `swift run`, leaving duplicate event monitors and duplicate side panels.
    private func acquireSingleInstance() -> Bool {
        if ProcessInfo.processInfo.environment["ZISLA_VISUAL_TEST_ALLOW_MULTIPLE"] == "1" {
            return true
        }
        let current = NSRunningApplication.current
        let currentBundleID = Bundle.main.bundleIdentifier
        let currentExecutable = current.executableURL?.standardizedFileURL
        let processName = ProcessInfo.processInfo.processName

        let peer = NSWorkspace.shared.runningApplications.first { application in
            guard application.processIdentifier != current.processIdentifier else { return false }
            if let currentBundleID, application.bundleIdentifier == currentBundleID {
                return true
            }
            if let currentExecutable,
               application.executableURL?.standardizedFileURL == currentExecutable {
                return true
            }
            return application.localizedName == processName || application.localizedName == "zisla"
        }
        guard let peer else { return true }
        peer.activate(options: [.activateAllWindows])
        return false
    }
}
