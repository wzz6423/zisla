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
        // 设置窗口没有关闭工作流；保留实例以便从菜单栏恢复。
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
    private var quickNotesEditorController: NSWindowController?
    private var cancellables: Set<AnyCancellable> = []
    private let updateController = UpdateController.shared
    private var expandedSizeUpdateTask: Task<Void, Never>?
    /// 语音录音开始前的灵动岛面板尺寸，录音结束后恢复。
    private var voiceRecordingSavedPanelSize: CGSize?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyAppDataMigration.migrateUserDefaults()
        guard acquireSingleInstance() else {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        let model = AppModel.shared
        model.start()
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
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        let engine = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            simulatedIslandSize: CGSize(width: 240, height: 34),
            expandedSize: model.selectedModule.layout.panelSize,
            horizontalMargin: 12
        ))
        let coordinator = OverlayCoordinator(contentView: hostingView, layoutEngine: engine)
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
        model.$selectedModule
            .map(\.layout.panelSize)
            .removeDuplicates()
            .sink { [weak self, weak coordinator] size in
                self?.scheduleExpandedSizeUpdate(size, coordinator: coordinator)
            }
            .store(in: &cancellables)
        overlayCoordinator = coordinator
        if model.settingsStore.settings.hoverActivationEnabled {
            coordinator.start()
        }
        if ProcessInfo.processInfo.environment["ZISLA_VISUAL_TEST_SHOW"] == "1" {
            model.isPinned = true
            coordinator.setPinned(true)
        }

        noticePresenter = SideNoticePresenter(
            queue: model.notices,
            displayIDs: model.settingsStore.settings.activityNoticeDisplayIDs
        )
        updateController.start(
            automaticallyChecks: model.settingsStore.settings.updateChecksEnabled,
            automaticallyDownloads: model.settingsStore.settings.automaticUpdatesEnabled
        )
        configureMainMenu()
        syncAppStatusItem()
        syncMonitorStatusItems(force: true)

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
                    } else if !model.isPinned {
                        self.overlayCoordinator?.stop()
                    }
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
                        automaticallyDownloads: settings.automaticUpdatesEnabled
                    )
                    self?.syncAppStatusItem()
                    self?.syncMonitorStatusItems(force: true)
                }
            }
            .store(in: &cancellables)

        // 「随记」和邮件需要键盘输入：仅在对应模块可见时允许灵动岛面板成为 key 窗口，
        // 其余时间保持非 key，避免抢占其他 App 的焦点。
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

        // 语音录音时：灵动岛展开一行，在下方实时显示转写内容。
        // 录音开始 → 保存当前面板尺寸、切换为紧凑尺寸并展开岛；
        // 录音结束 → 恢复原面板尺寸并收起岛。
        model.voiceInput.$isRecording
            .removeDuplicates()
            .sink { [weak self] recording in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if recording {
                        self.voiceRecordingSavedPanelSize = AppModel.shared.selectedModule.layout.panelSize
                        self.overlayCoordinator?.updateExpandedSize(
                            CGSize(width: 660, height: 76)
                        )
                        self.overlayCoordinator?.setTransientInteractionVisible(true)
                    } else {
                        self.overlayCoordinator?.setTransientInteractionVisible(false)
                        if let saved = self.voiceRecordingSavedPanelSize {
                            self.overlayCoordinator?.updateExpandedSize(saved)
                            self.voiceRecordingSavedPanelSize = nil
                        }
                    }
                }
            }
            .store(in: &cancellables)

        // 磁盘清理弹窗可见时：保持灵动岛展开，避免指针离开岛区域导致提前收起。
        model.$isCleanupPanelVisible
            .removeDuplicates()
            .sink { [weak coordinator] visible in
                Task { @MainActor in
                    coordinator?.setTransientInteractionVisible(visible)
                }
            }
            .store(in: &cancellables)

        // 磁盘清理完成后：取消固定与临时交互保持，触发灵动岛收起。
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
            // 模块按钮的事件处理先提交，下一轮再改 NSPanel frame，避免 AppKit 在点击中途
            // 重建 hover tracking 而误判鼠标已经离开；连续切换只保留最后一个尺寸。
            await Task.yield()
            guard !Task.isCancelled, let coordinator else { return }
            coordinator.updateExpandedSize(size)
            self?.expandedSizeUpdateTask = nil
        }
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let applicationMenuItem = NSMenuItem(title: "zisla", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "zisla")
        let quitItem = applicationMenu.addItem(
            withTitle: "退出 zisla",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = .command
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)

        let windowMenuItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "窗口")
        let minimizeItem = windowMenu.addItem(
            withTitle: "最小化",
            action: #selector(NSWindow.miniaturize(_:)),
            keyEquivalent: "m"
        )
        minimizeItem.keyEquivalentModifierMask = .command
        let closeItem = windowMenu.addItem(
            withTitle: "关闭窗口",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeItem.keyEquivalentModifierMask = .command
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
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
        menu.addItem(withTitle: "显示灵动岛", action: #selector(showIsland), keyEquivalent: "")
        menu.addItem(withTitle: "系统监控", action: #selector(showSystemMonitor), keyEquivalent: "")
        menu.addItem(withTitle: "设置...", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "检查更新", action: #selector(checkUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 zisla", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
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
                item.button?.toolTip = "\(metric.menuTitle)：点击打开系统监控"
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
                accessibilityDescription: metric.menuTitle
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
        guard let snapshot else { return "\(metric.menuTitle) --" }
        switch metric {
        case .cpu:
            return "CPU \(percent(snapshot.cpu.usage))"
        case .gpu:
            guard case let .available(gpu) = snapshot.gpu else { return "GPU --" }
            return "GPU \(percent(gpu.usage))"
        case .memory:
            return "RAM \(byteText(snapshot.memory.usedBytes))"
        case .disk:
            guard snapshot.disk.totalBytes > 0 else { return "磁盘 --" }
            let usage = Double(snapshot.disk.usedBytes) / Double(snapshot.disk.totalBytes)
            return "磁盘 \(percent(usage))"
        case .network:
            return "网络 ↓\(rateText(snapshot.network.receiveBytesPerSecond)) ↑\(rateText(snapshot.network.sendBytesPerSecond))"
        case .fan:
            guard case let .available(rpm, _) = snapshot.fan, let first = rpm.first else {
                return "风扇 --"
            }
            return "风扇 \(Int(first.rounded()))"
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
        case .memory: "MEMORY"
        case .disk: "Disk"
        case .network: "Net"
        case .fan: "Fan"
        }
    }

    private func compactMonitorStatusItemWidth(for metric: SystemMonitorMenuBarMetric) -> CGFloat {
        switch metric {
        case .network:
            68
        default:
            48
        }
    }

    private func compactMonitorStatusImage(
        value: String,
        metric: SystemMonitorMenuBarMetric
    ) -> NSImage? {
        let size = NSSize(width: compactMonitorStatusItemWidth(for: metric) - 6, height: 22)
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
            window.title = "zisla 设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: rootView)
            settingsWindowController = NSWindowController(window: window)
        }
        if let window = settingsWindowController?.window {
            WindowPlacement.center(window, on: targetScreen)
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkUpdates() {
        AppModel.shared.checkForUpdates(manual: true)
    }

    /// 打开「随记」大窗口编辑：左侧 Markdown 编辑、右侧富预览（图片/表格），
    /// 区域远大于灵动岛内嵌面板。复用 `AppModel.shared.quickNotes`，编辑当前选中笔记。
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
            window.title = "随记 · 编辑"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 640, height: 460)
            window.contentView = NSHostingView(rootView: rootView)
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
