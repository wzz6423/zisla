import AppKit
import Combine
import ZislaCore
import ZislaKit
import SwiftUI

@objc private protocol EditingActionTarget {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}

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
final class SettingsWindow: NSWindow {
    override func becomeKey() {
        level = WindowPlacement.modalWindowLevel
        super.becomeKey()
    }

    override func resignKey() {
        super.resignKey()
        level = .normal
    }

    override func performClose(_ sender: Any?) {
        close()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let action = Self.editingAction(for: event),
              let firstResponder,
              NSApp.sendAction(action, to: firstResponder, from: self)
        else {
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    fileprivate static func editingAction(for event: NSEvent) -> Selector? {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased()

        return switch (key, modifiers) {
        case ("a", .command): #selector(NSResponder.selectAll(_:))
        case ("c", .command): #selector(NSText.copy(_:))
        case ("v", .command): #selector(NSText.paste(_:))
        case ("x", .command): #selector(NSText.cut(_:))
        case ("z", .command): #selector(EditingActionTarget.undo(_:))
        case ("z", [.command, .shift]): #selector(EditingActionTarget.redo(_:))
        default: nil
        }
    }
}

@MainActor
final class QuickNotesEditorWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let action = SettingsWindow.editingAction(for: event),
              let firstResponder,
              NSApp.sendAction(action, to: firstResponder, from: self)
        else {
            return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

enum ScreenshotModalSession {
    @MainActor
    static func dismissForSelectionPresentation(
        modalWindow: NSWindow? = NSApp.modalWindow,
        abortModal: () -> Void = { NSApp.abortModal() }
    ) {
        guard modalWindow != nil else { return }
        abortModal()
    }
}

struct ScreenshotModalWindowSnapshot {
    let image: CGImage
    let screenFrame: CGRect

    @MainActor
    static func capture(from modalWindow: NSWindow? = NSApp.modalWindow) -> Self? {
        guard let modalWindow,
              modalWindow.isVisible,
              let contentView = modalWindow.contentView
        else {
            return nil
        }

        let snapshotView = contentView.superview ?? contentView
        guard let bitmap = snapshotView.bitmapImageRepForCachingDisplay(in: snapshotView.bounds) else {
            return nil
        }
        snapshotView.cacheDisplay(in: snapshotView.bounds, to: bitmap)
        guard let image = bitmap.cgImage else { return nil }

        return Self(
            image: image,
            screenFrame: modalWindow.frame
        )
    }

    func composited(
        over capture: (image: NSImage, cgImage: CGImage),
        on screen: NSScreen
    ) -> (image: NSImage, cgImage: CGImage) {
        guard screen.frame.contains(screenFrame),
              capture.cgImage.width > 0,
              capture.cgImage.height > 0,
              screen.frame.width > 0,
              screen.frame.height > 0
        else {
            return capture
        }

        let modalFrame = Self.localTopLeftFrame(for: screenFrame, on: screen.frame)
        guard let compositedImage = Self.composite(
            image,
            in: modalFrame,
            over: capture.cgImage,
            screenSize: screen.frame.size
        ) else {
            return capture
        }

        return (
            NSImage(cgImage: compositedImage, size: screen.frame.size),
            compositedImage
        )
    }

    static func composite(
        _ modalImage: CGImage,
        in modalFrame: CGRect,
        over captureImage: CGImage,
        screenSize: CGSize
    ) -> CGImage? {
        guard captureImage.width > 0,
              captureImage.height > 0,
              screenSize.width > 0,
              screenSize.height > 0
        else {
            return nil
        }

        let scaleX = CGFloat(captureImage.width) / screenSize.width
        let scaleY = CGFloat(captureImage.height) / screenSize.height
        let drawFrame = CGRect(
            x: modalFrame.minX * scaleX,
            y: modalFrame.minY * scaleY,
            width: modalFrame.width * scaleX,
            height: modalFrame.height * scaleY
        )
        guard let context = CGContext(
            data: nil,
            width: captureImage.width,
            height: captureImage.height,
            bitsPerComponent: 8,
            bytesPerRow: captureImage.width * 4,
            space: captureImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(
            captureImage,
            in: CGRect(x: 0, y: 0, width: captureImage.width, height: captureImage.height)
        )
        context.draw(modalImage, in: drawFrame)
        return context.makeImage()
    }

    static func localTopLeftFrame(for modalFrame: CGRect, on screenFrame: CGRect) -> CGRect {
        let normalized = modalFrame.standardized
        return CGRect(
            x: normalized.minX - screenFrame.minX,
            y: screenFrame.maxY - normalized.maxY,
            width: normalized.width,
            height: normalized.height
        )
    }
}

enum SystemMonitorMemoryPresentation {
    static func usageRatio(usedBytes: UInt64, totalBytes: UInt64) -> Double? {
        guard totalBytes > 0 else { return nil }
        return SystemMonitorMath.memoryPressureRatio(
            usedBytes: usedBytes,
            totalBytes: totalBytes
        )
    }

    static func usageText(usedBytes: UInt64, totalBytes: UInt64) -> String {
        guard let ratio = usageRatio(usedBytes: usedBytes, totalBytes: totalBytes) else {
            return "--"
        }
        return "\(Int((ratio * 100).rounded()))%"
    }
}

enum SystemMonitorMenuBarPresentation {
    static func label(for metric: SystemMonitorMenuBarMetric) -> String {
        switch metric {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .network: "Network"
        case .fan: "Fans"
        }
    }

    static func detailedFanValue(_ rpm: [Double]) -> String? {
        let readings = fanReadings(rpm)
        return readings.isEmpty ? nil : readings.joined(separator: "  ")
    }

    static func compactFanRows(_ rpm: [Double]) -> [String] {
        let readings = fanReadings(rpm)
        guard !readings.isEmpty else { return [] }

        var rows = ["", ""]
        for (index, reading) in readings.enumerated() {
            let rowIndex = index % 2
            rows[rowIndex] += rows[rowIndex].isEmpty ? reading : "   \(reading)"
        }
        return rows.filter { !$0.isEmpty }
    }

    private static func fanReadings(_ rpm: [Double]) -> [String] {
        rpm.enumerated().map { index, speed in
            let label = switch index {
            case 0: "L"
            case 1: "R"
            default: "F\(index + 1)"
            }
            return "\(label) \(Int(speed.rounded()))"
        }
    }
}

enum PersistentPetNoticePolicy {
    static func notices(
        _ notices: [IslandNotice],
        isVoiceRecording: Bool,
        voiceDisplayID: UInt32?,
        displayID: UInt32
    ) -> [IslandNotice] {
        if isVoiceRecording { return [] }
        guard let voiceDisplayID, voiceDisplayID != displayID else { return notices }
        return notices.filter { !$0.id.hasPrefix("voice-processing-") }
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
    private var screenshotSelectionController: ScreenshotSelectionController?
    private var screenshotEditorController: ScreenshotEditorWindowController?
    private var additionalScreenshotEditors: [ScreenshotEditorWindowController] = []
    private var screenshotHotkeyManager = GlobalHotkeyManager()
    private var screenshotPinHotkeyManager = GlobalHotkeyManager()
    private var pendingScreenshotPin = false
    private var isScreenshotSessionActive = false
    private var screenshotSnapTargetProcessTracker = ScreenshotSnapTargetProcessTracker()
    private var lastExternalScreenshotApplication: NSRunningApplication?
    private var systemScreenshotMonitor: SystemScreenshotMonitor?
    private var cancellables: Set<AnyCancellable> = []
    private var effectiveAppearanceObservation: NSKeyValueObservation?
    private var currentApplicationIconImage: NSImage?
    private var expandedSizeUpdateTask: Task<Void, Never>?
    /// Last panel size actually applied to the coordinator; basis for the two-phase
    /// (union → target) resize that keeps the SwiftUI surface spring unclipped.
    private var lastAppliedPanelSize: CGSize?
    /// Panel size saved before voice recording starts; restored when recording ends.
    private var voiceRecordingSavedPanelSize: CGSize?
    /// Module panel size waiting for the post-recording fold to finish before it is applied.
    private var pendingVoiceRecordingPanelRestore: CGSize?
    /// Display where the last voice recording happened; scopes the post-recording processing indicator.
    private var voiceRecordingDisplayID: UInt32?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyAppDataMigration.migrateUserDefaults()
        guard acquireSingleInstance() else {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        WindowPlacement.installTransientWindowPromotion()
        let model = AppModel.shared
        model.start()
        configureApplicationIconUpdates(model: model)
        let lockScreenOverlayController = LockScreenOverlayController(model: model)
        self.lockScreenOverlayController = lockScreenOverlayController
        if model.settingsStore.settings.lockScreenInfoEnabled {
            lockScreenOverlayController.start()
        }

        let petController = IslandPetController(model: model)
        self.petController = petController
        if model.settingsStore.settings.petEnabled {
            petController.start()
        }

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
            onTransientInteractionChanged: { [weak self] visible in
                self?.overlayCoordinator?.setTransientInteractionVisible(visible)
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
                batteryDynamicHeight: model.batteryModuleDynamicHeight,
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
            persistentPanelFrameProvider: { [weak self] layout in
                let notices = PersistentPetNoticePolicy.notices(
                    model.notices.left + model.notices.right,
                    isVoiceRecording: model.voiceInput.isCapturingInput,
                    voiceDisplayID: self?.voiceRecordingDisplayID,
                    displayID: layout.displayID
                )
                return CollapsedPetLayout.frame(
                    for: layout,
                    compactBarFrame: SideNoticeLayoutEngine().compactBarFrame(
                        for: layout,
                        notices: notices,
                        settings: model.settingsStore.settings
                    )
                )
            }
        )
        coordinator.onVisibilityChanged = { [weak self] visible in
            model.isIslandVisible = visible
            self?.noticePresenter?.setIslandExpanded(visible)
            if visible {
                self?.flushVoiceRecordingPanelRestore()
                model.clipboardAssistant.dismiss(animated: false)
                model.refreshForExpansion()
            }
        }
        coordinator.onDraggingChanged = { dragging in
            model.isExternalDragging = dragging
            if dragging, model.settingsStore.settings.fileShelfEnabled {
                model.selectModule(.shelf)
            }
        }
        coordinator.onCollapsedSizeChanged = { size in
            model.collapsedIslandSize = size
        }
        coordinator.onActiveDisplayHasPhysicalNotchChanged = { hasPhysicalNotch in
            model.isIslandOnPhysicalNotch = hasPhysicalNotch
        }
        Publishers.CombineLatest3(
            Publishers.CombineLatest4(
                model.$selectedModule,
                model.$isMirrorPresented,
                model.$isTeleprompterPresented,
                model.$dashboardCardCount
            ),
            model.settingsStore.$settings
                .map(\.petEnabled)
                .removeDuplicates(),
            model.$batteryModuleDynamicHeight
        )
            .map { state, includesPet, batteryHeight -> CGSize in
                let (module, isMirrorPresented, isTeleprompterPresented, dashboardCardCount) = state
                return Self.expandedPanelSize(
                    module: module,
                    isMirrorPresented: isMirrorPresented,
                    isTeleprompterPresented: isTeleprompterPresented,
                    dashboardCardCount: dashboardCardCount,
                    batteryDynamicHeight: batteryHeight,
                    includesPet: includesPet
                ).panelSize
            }
            .removeDuplicates()
            .sink { [weak self, weak coordinator] size in
                guard !model.voiceInput.isCapturingInput else { return }
                self?.scheduleExpandedSizeUpdate(size, coordinator: coordinator)
            }
            .store(in: &cancellables)
        model.$isMirrorPresented
            .combineLatest(model.$isTeleprompterPresented)
            .sink { [weak coordinator, weak model] isMirrorPresented, isTeleprompterPresented in
                Task { @MainActor in
                    guard let model else { return }
                    if isTeleprompterPresented {
                        coordinator?.start()
                        coordinator?.selectActiveDisplay(
                            at: model.teleprompterPresentationPoint ?? NSEvent.mouseLocation
                        )
                    }
                    coordinator?.setPinned(isMirrorPresented || isTeleprompterPresented || model.isPinned)
                }
            }
            .store(in: &cancellables)
        overlayCoordinator = coordinator
        model.onVoiceInputWillStart = { [weak coordinator] in
            guard let coordinator, coordinator.isRunning else { return }
            coordinator.setVoiceRecording(true, at: NSEvent.mouseLocation)
        }
        model.clipboardAssistant.onPresentationChanged = { [weak self, weak coordinator] visible in
            coordinator?.setHoverActivationSuspended(visible)
            self?.noticePresenter?.setClipboardAssistantVisible(visible)
        }
        coordinator.setPersistentContentVisible(model.settingsStore.settings.petEnabled)
        coordinator.setCollapsedOnTop(model.settingsStore.settings.islandCollapsedOnTop)
        if model.settingsStore.settings.hoverActivationEnabled
            || model.settingsStore.settings.petEnabled {
            coordinator.start()
        }
        // Mount the island content now so the first reveal animates instead of snapping in.
        coordinator.prewarmPanel()
        if ProcessInfo.processInfo.environment["ZISLA_VISUAL_TEST_SHOW"] == "1" {
            coordinator.start()
            model.isPinned = true
            coordinator.setPinned(true)
        }
        noticePresenter = SideNoticePresenter(
            queue: model.notices,
            media: model.media,
            browserDownloads: model.browserDownloads,
            settingsStore: model.settingsStore,
            languageStore: model.languageStore,
            displayIDs: model.settingsStore.settings.activityNoticeDisplayIDs
        )
        configureMainMenu()
        registerScreenshotHotkeys()
        startSystemScreenshotMonitoring()
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
            .map(\.screenshotEnabled)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.registerScreenshotHotkeys()
                }
            }
            .store(in: &cancellables)

        model.settingsStore.$settings
            .map { ($0.screenshotHotkey, $0.screenshotPinHotkey) }
            .removeDuplicates { $0 == $1 }
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.registerScreenshotHotkeys()
                }
            }
            .store(in: &cancellables)

        model.$voiceInputInputMonitoringAccessGranted
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.registerScreenshotHotkeys()
                }
            }
            .store(in: &cancellables)

        model.settingsStore.$settings
            .map(\.lockScreenInfoEnabled)
            .removeDuplicates()
            .sink { [weak self] enabled in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if enabled {
                        self.lockScreenOverlayController?.start()
                    } else {
                        self.lockScreenOverlayController?.stop()
                    }
                }
            }
            .store(in: &cancellables)

        model.settingsStore.$settings
            .map(\.petEnabled)
            .removeDuplicates()
            .sink { [weak self, weak coordinator, weak model] enabled in
                Task { @MainActor [weak self] in
                    coordinator?.setPersistentContentVisible(enabled)
                    guard let model else { return }
                    if enabled {
                        self?.petController?.start()
                        coordinator?.start()
                    } else {
                        self?.petController?.stop()
                        if !model.settingsStore.settings.hoverActivationEnabled && !model.isPinned {
                            coordinator?.stop()
                        }
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

        model.$isSharingPickerVisible
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
                    self?.syncAppStatusItem()
                    self?.syncMonitorStatusItems(force: true)
                }
            }
            .store(in: &cancellables)

        // Allow the island panel to become the keyboard focus only when a text input interface is visible, preventing it from stealing focus from the frontmost app in other cases.
        Publishers.CombineLatest3(
            model.$selectedModule,
            model.$isIslandVisible,
            model.$isTeleprompterPresented
        )
            .sink { [weak coordinator] module, visible, isTeleprompterPresented in
                Task { @MainActor in
                    coordinator?.setAllowsKeyWindow(
                        visible && (
                            module == .quickNotes
                                || module == .mail
                                || isTeleprompterPresented
                        )
                    )
                }
            }
            .store(in: &cancellables)

        // Voice recording: expand the island to one row and show live transcription below.
        // Capture starts → save current panel size, switch to compact size, expand the island.
        // Capture ends → restore panel size and collapse the island.
        // Driven by the combined capture flag rather than `$isRecording`: the surface has to be on
        // screen from the keypress, and the dictation engine needs up to a second to start recording.
        model.voiceInput.isCapturingInputPublisher
            .sink { [weak self] recording in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if recording {
                        self.noticePresenter?.setVoiceRecording(true)
                        let model = AppModel.shared
                        self.voiceRecordingSavedPanelSize = Self.expandedPanelSize(
                            module: model.selectedModule,
                            isMirrorPresented: model.isMirrorPresented,
                            isTeleprompterPresented: model.isTeleprompterPresented,
                            dashboardCardCount: model.dashboardCardCount,
                            batteryDynamicHeight: model.batteryModuleDynamicHeight,
                            includesPet: model.settingsStore.settings.petEnabled
                        ).panelSize
                        // Direct resize (no two-phase): recording swaps layout instantly by design.
                        self.expandedSizeUpdateTask?.cancel()
                        self.pendingVoiceRecordingPanelRestore = nil
                        self.overlayCoordinator?.setVoiceRecording(true)
                        // Read the collapsed pill metrics only after `setVoiceRecording` resolved the
                        // active display: before the island has ever been presented they still hold
                        // the launch defaults, which sizes the first take's surface wrong.
                        let recordingSize = IslandModuleLayout.voiceRecording
                            .matchingWidth(model.collapsedOverflowWidth)
                            .panelSize
                        self.overlayCoordinator?.updateExpandedSize(recordingSize)
                        self.lastAppliedPanelSize = recordingSize
                        // Scope the post-recording processing indicator to the display where
                        // dictation happened.
                        let voiceDisplayID = self.overlayCoordinator?.activeDisplayID
                        self.voiceRecordingDisplayID = voiceDisplayID
                        self.noticePresenter?.setVoiceProcessingDisplayID(voiceDisplayID)
                    } else {
                        let model = AppModel.shared
                        self.overlayCoordinator?.setVoiceRecording(false)
                        if let saved = self.voiceRecordingSavedPanelSize {
                            self.voiceRecordingSavedPanelSize = nil
                            self.scheduleVoiceRecordingPanelRestore(saved)
                        }
                        self.overlayCoordinator?.setPinned(model.isPinned)
                        self.noticePresenter?.setVoiceRecording(false)
                    }
                }
            }
            .store(in: &cancellables)

        // Disk-cleanup panels should remain above the collapsed island without becoming a global topmost window.
        model.$islandCollapseRequested
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak coordinator] _ in
                Task { @MainActor in
                    coordinator?.collapseImmediately()
                    AppModel.shared.isPinned = false
                    AppModel.shared.islandCollapseRequested = false
                }
            }
            .store(in: &cancellables)

        // Clipboard assistant actions that land in an island module run while the island is still
        // collapsed; expanding here spares the user from hovering the notch themselves.
        model.$islandExpansionRequested
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak coordinator] _ in
                Task { @MainActor in
                    coordinator?.showExpanded(at: NSEvent.mouseLocation)
                    AppModel.shared.refreshForExpansion()
                    AppModel.shared.islandExpansionRequested = false
                }
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        expandedSizeUpdateTask?.cancel()
        lockScreenOverlayController?.stop()
        systemScreenshotMonitor?.stop()
        systemScreenshotMonitor = nil
        AppModel.shared.stop()
        screenshotHotkeyManager.unregister()
        screenshotPinHotkeyManager.unregister()
        setScreenshotSessionActive(false)
        screenshotSelectionController?.cancel()
        screenshotEditorController?.close()
        let editorsToClose = additionalScreenshotEditors
        editorsToClose.forEach { $0.close() }
        screenshotEditorController = nil
        additionalScreenshotEditors.removeAll()
        noticePresenter?.stop()
        petController?.stop()
        overlayCoordinator?.stop()
    }

    /// Holds the island panel at its recording size until the recycle fold has folded the pill back
    /// into the notch.
    ///
    /// The module panel is wider than the recording surface and reserves a pet slot on one side, so
    /// restoring it re-offsets the surface from the panel center. That offset is compensated by the
    /// reveal mask's collapsed center offset — but the two run on different clocks (`surfaceResize`
    /// for the layout, `islandRecycle` for the fold), so applying it while the fold is on screen
    /// drags the pill sideways before it reaches the notch.
    private func scheduleVoiceRecordingPanelRestore(_ size: CGSize) {
        pendingVoiceRecordingPanelRestore = size
        expandedSizeUpdateTask?.cancel()
        expandedSizeUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: ZislaMotion.islandRecycleSettleDelay)
            guard !Task.isCancelled, let self else { return }
            self.expandedSizeUpdateTask = nil
            self.flushVoiceRecordingPanelRestore()
        }
    }

    /// Applies the deferred size early: whatever just expanded the island needs the full panel frame
    /// now, and there is no fold left to protect.
    private func flushVoiceRecordingPanelRestore() {
        guard let size = pendingVoiceRecordingPanelRestore else { return }
        pendingVoiceRecordingPanelRestore = nil
        overlayCoordinator?.updateExpandedSize(size)
        lastAppliedPanelSize = size
    }

    private func scheduleExpandedSizeUpdate(
        _ size: CGSize,
        coordinator: OverlayCoordinator?
    ) {
        expandedSizeUpdateTask?.cancel()
        pendingVoiceRecordingPanelRestore = nil
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
        batteryDynamicHeight: CGFloat,
        includesPet: Bool
    ) -> IslandModuleLayout {
        if isMirrorPresented { return .mirror }
        if isTeleprompterPresented { return .teleprompter }
        let layout = IslandModuleLayout.resolved(
            for: module,
            dashboardCardCount: dashboardCardCount,
            batteryDynamicHeight: batteryDynamicHeight
        )
        return IslandModuleLayout(
            islandSize: layout.islandSize,
            panelSize: ExpandedPetLayout.panelSize(
                for: layout.panelSize,
                includesPet: includesPet
            )
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
        let screenshotItem = applicationMenu.insertItem(
            withTitle: localized("截图"),
            action: #selector(startScreenshot),
            keyEquivalent: "",
            at: 0
        )
        screenshotItem.target = self
        let pinItem = applicationMenu.insertItem(
            withTitle: localized("钉图"),
            action: #selector(startPinnedScreenshot),
            keyEquivalent: "",
            at: 1
        )
        pinItem.target = self
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
        menu.addItem(withTitle: localized("截图"), action: #selector(startScreenshot), keyEquivalent: "")
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
                item.button?.toolTip = "\(SystemMonitorMenuBarPresentation.label(for: metric)): \(localized("点击打开系统监控"))"
            }
            let title = monitorStatusTitle(
                for: metric,
                snapshot: AppModel.shared.systemMonitor.snapshot,
                style: style
            )
            if style == .compact {
                let itemWidth = compactMonitorStatusItemWidth(for: metric, value: title)
                item.length = itemWidth
                if monitorStatusTitles[metric] != title {
                    item.button?.image = compactMonitorStatusImage(
                        value: title,
                        metric: metric,
                        itemWidth: itemWidth
                    )
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
                accessibilityDescription: SystemMonitorMenuBarPresentation.label(for: metric)
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
        let label = SystemMonitorMenuBarPresentation.label(for: metric)
        guard let snapshot else { return "\(label) --" }
        switch metric {
        case .cpu:
            return "\(label) \(percent(snapshot.cpu.usage))"
        case .gpu:
            guard case let .available(gpu) = snapshot.gpu else { return "\(label) --" }
            return "\(label) \(percent(gpu.usage))"
        case .memory:
            let usage = SystemMonitorMemoryPresentation.usageText(
                usedBytes: snapshot.memory.usedBytes,
                totalBytes: snapshot.memory.totalBytes
            )
            return "\(label) \(usage)"
        case .disk:
            guard snapshot.disk.totalBytes > 0 else { return "\(label) --" }
            let usage = Double(snapshot.disk.usedBytes) / Double(snapshot.disk.totalBytes)
            return "\(label) \(percent(usage))"
        case .network:
            return "\(label) ↓\(rateText(snapshot.network.receiveBytesPerSecond)) ↑\(rateText(snapshot.network.sendBytesPerSecond))"
        case .fan:
            guard case let .available(rpm, _) = snapshot.fan,
                  let value = SystemMonitorMenuBarPresentation.detailedFanValue(rpm)
            else { return "\(label) --" }
            return "\(label) \(value)"
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
            return SystemMonitorMemoryPresentation.usageText(
                usedBytes: snapshot.memory.usedBytes,
                totalBytes: snapshot.memory.totalBytes
            )
        case .disk:
            guard snapshot.disk.totalBytes > 0 else { return "--" }
            return percent(Double(snapshot.disk.usedBytes) / Double(snapshot.disk.totalBytes))
        case .network:
            return "↓\(rateText(snapshot.network.receiveBytesPerSecond))"
        case .fan:
            guard case let .available(rpm, _) = snapshot.fan else { return "--" }
            let rows = SystemMonitorMenuBarPresentation.compactFanRows(rpm)
            return rows.isEmpty ? "--" : rows.joined(separator: "\n")
        }
    }

    private func compactMonitorStatusLabel(for metric: SystemMonitorMenuBarMetric) -> String {
        SystemMonitorMenuBarPresentation.label(for: metric)
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

    private func compactMonitorStatusItemWidth(
        for metric: SystemMonitorMenuBarMetric,
        value: String
    ) -> CGFloat {
        let valueFont = metric == .fan
            ? NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
            : NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let valueWidth = value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { ($0 as NSString).size(withAttributes: [.font: valueFont]).width }
            .max() ?? 0

        if metric == .fan {
            return max(40, ceil(valueWidth) + 8)
        }

        let labelWidth = (compactMonitorStatusLabel(for: metric) as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: 8, weight: .semibold)]
        ).width
        let minimumWidth: CGFloat
        switch metric {
        case .cpu, .gpu, .memory, .disk:
            minimumWidth = 32
        case .network:
            minimumWidth = 60
        case .fan:
            minimumWidth = 40
        }
        return max(minimumWidth, ceil(max(valueWidth, labelWidth)) + 8)
    }

    private func compactMonitorStatusImage(
        value: String,
        metric: SystemMonitorMenuBarMetric,
        itemWidth: CGFloat
    ) -> NSImage? {
        let size = NSSize(width: itemWidth - 4, height: 22)
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

        if metric == .fan {
            let rows = value.split(separator: "\n", omittingEmptySubsequences: false)
            let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
            for (index, row) in rows.prefix(2).enumerated() {
                let y: CGFloat = rows.count == 1 && value == "--" ? 6 : (index == 0 ? 11 : 1)
                (row as NSString).draw(
                    in: NSRect(x: 0, y: y, width: size.width, height: 10),
                    withAttributes: [
                        .font: font,
                        .foregroundColor: NSColor.black,
                        .paragraphStyle: paragraph,
                    ]
                )
            }
        } else {
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
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(representation)
        image.isTemplate = true
        image.accessibilityDescription = SystemMonitorMenuBarPresentation.label(for: metric)
        return image
    }

    private func percent(_ value: Double) -> String {
        "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }

    private func rateText(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytesPerSecond)), countStyle: .file) + "/s"
    }

    @objc private func showIsland() {
        let model = AppModel.shared
        guard !model.voiceInput.isRecording, !model.voiceInput.isPreparing else { return }
        overlayCoordinator?.start()
        model.isPinned = true
        overlayCoordinator?.setPinned(true)
        model.refreshForExpansion()
    }

    @objc private func startScreenshot() {
        guard AppModel.shared.settingsStore.settings.screenshotEnabled else { return }
        beginScreenshot(pinAfterCapture: false)
    }

    @objc private func startPinnedScreenshot() {
        let editors = [screenshotEditorController].compactMap { $0 } + additionalScreenshotEditors
        if let editor = editors.last(where: { !$0.isPinnedPresentation }) ?? editors.last {
            editor.togglePinned()
            return
        }
        if screenshotSelectionController != nil {
            pendingScreenshotPin = true
            return
        }
        guard AppModel.shared.settingsStore.settings.screenshotEnabled else { return }
        beginScreenshot(pinAfterCapture: true)
    }

    private func beginScreenshot(pinAfterCapture: Bool) {
        guard AppModel.shared.settingsStore.settings.screenshotEnabled else { return }
        guard screenshotSelectionController == nil else { return }
        let editors = [screenshotEditorController].compactMap { $0 } + additionalScreenshotEditors
        if editors.contains(where: { !$0.isPinnedPresentation }) {
            return
        }
        pendingScreenshotPin = pinAfterCapture
        let currentProcess = ProcessInfo.processInfo.processIdentifier
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.processIdentifier != currentProcess {
            lastExternalScreenshotApplication = frontmostApplication
        }
        let capturedApplication = frontmostApplication?.processIdentifier == currentProcess
            ? lastExternalScreenshotApplication
            : frontmostApplication
        let capturedProcessIdentifier = screenshotSnapTargetProcessTracker.target(
            frontmost: frontmostApplication?.processIdentifier,
            currentProcess: currentProcess
        )
        let screens = NSScreen.screens
        let preferredScreen = WindowPlacement.screenUnderMouse()
        let captureScreens: [NSScreen]
        if let preferredScreen {
            captureScreens = [preferredScreen] + screens.filter { $0 !== preferredScreen }
        } else {
            captureScreens = screens
        }
        guard !captureScreens.isEmpty else {
            pendingScreenshotPin = false
            return
        }

        let modalWindowSnapshot = ScreenshotModalWindowSnapshot.capture()
        ScreenshotModalSession.dismissForSelectionPresentation()
        setScreenshotSessionActive(true)
        setScreenshotLiveCaptureActive(true)

        let controller = ScreenshotSelectionController(
            capturedProcessIdentifier: capturedProcessIdentifier,
            captureScreen: { screen in
                let capture = try await ScreenshotCaptureService.capture(screen: screen)
                return modalWindowSnapshot?.composited(over: capture, on: screen) ?? capture
            }
        )
        screenshotSelectionController = controller
        controller.onSelectionWillPresent = { [weak self, weak controller] in
            guard let self, let controller, self.screenshotSelectionController === controller else { return }
            self.setScreenshotLiveCaptureActive(false)
            AppModel.shared.clipboardAssistant.setScreenshotSelectionActive(true)
            self.setScreenshotFrozenPresentationActive(true)
            await Task.yield()
        }
        controller.onCaptured = { [weak self] result in
            guard let self else { return }
            self.screenshotSelectionController = nil
            let shouldPin = self.pendingScreenshotPin
            self.pendingScreenshotPin = false
            var editor: ScreenshotEditorWindowController!
            editor = ScreenshotEditorWindowController(
                image: result.image,
                screenImage: result.screenImage,
                screenCGImage: result.screenCGImage,
                screen: result.screen,
                captureRect: result.selectionRect,
                capturedApplication: capturedApplication,
                onClose: { [weak self] in
                    guard let self else { return }
                    if self.screenshotEditorController === editor {
                        self.screenshotEditorController = nil
                    } else {
                        self.additionalScreenshotEditors.removeAll { $0 === editor }
                    }
                    self.endScreenshotSessionIfNeeded()
                },
                pinnedToolbarVisible: AppModel.shared.settingsStore.settings.screenshotPinnedToolbarVisible
            )
            if self.screenshotEditorController == nil {
                self.screenshotEditorController = editor
            } else {
                self.additionalScreenshotEditors.append(editor)
            }
            editor.present()
            if shouldPin {
                editor.setPinned(true)
            }
        }
        controller.onCancelled = { [weak self] in
            guard let self else { return }
            self.screenshotSelectionController = nil
            self.setScreenshotLiveCaptureActive(false)
            AppModel.shared.clipboardAssistant.setScreenshotSelectionActive(false)
            self.pendingScreenshotPin = false
            self.endScreenshotSessionIfNeeded()
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.screenshotSelectionController === controller else { return }
            await controller.start(on: captureScreens)
        }
    }

    private func setScreenshotSessionActive(_ active: Bool) {
        AppModel.shared.clipboardAssistant.setScreenshotActive(active)
        guard isScreenshotSessionActive != active else { return }
        isScreenshotSessionActive = active
        if !active {
            setScreenshotLiveCaptureActive(false)
            setScreenshotFrozenPresentationActive(false)
        }
    }

    private func setScreenshotLiveCaptureActive(_ active: Bool) {
        overlayCoordinator?.setScreenshotCaptureInProgress(active)
    }

    private func setScreenshotFrozenPresentationActive(_ active: Bool) {
        overlayCoordinator?.setScreenshotActive(active)
        noticePresenter?.setScreenshotActive(active)
    }

    private func endScreenshotSessionIfNeeded() {
        guard screenshotSelectionController == nil,
              screenshotEditorController == nil,
              additionalScreenshotEditors.isEmpty
        else { return }
        setScreenshotSessionActive(false)
    }

    private func registerScreenshotHotkeys() {
        let settings = AppModel.shared.settingsStore.settings
        screenshotHotkeyManager.unregister()
        screenshotPinHotkeyManager.unregister()
        guard settings.screenshotEnabled else { return }
        let captureResult = screenshotHotkeyManager.register(
            hotkey: settings.screenshotHotkey,
            onKeyDown: { [weak self] in self?.startScreenshot() },
            onKeyUp: {}
        )
        reportScreenshotHotkeyRegistration(captureResult, actionName: "截图")

        guard !settings.screenshotHotkey.conflicts(with: settings.screenshotPinHotkey) else {
            AppModel.shared.transientMessage = "截图与钉图快捷键冲突，钉图快捷键未启用"
            return
        }
        let pinResult = screenshotPinHotkeyManager.register(
            hotkey: settings.screenshotPinHotkey,
            onKeyDown: { [weak self] in self?.startPinnedScreenshot() },
            onKeyUp: {}
        )
        reportScreenshotHotkeyRegistration(pinResult, actionName: "钉图")
    }

    private func reportScreenshotHotkeyRegistration(
        _ result: GlobalHotkeyRegistrationResult,
        actionName: String
    ) {
        switch result {
        case .registered:
            break
        case .inputMonitoringPermissionRequired:
            AppModel.shared.transientMessage = "\(actionName)快捷键需要输入监控权限"
        case .registrationFailed:
            AppModel.shared.transientMessage = "\(actionName)快捷键与系统或其他应用冲突，未能启用"
        }
    }

    private func startSystemScreenshotMonitoring() {
        let monitor = SystemScreenshotMonitor()
        monitor.onSystemScreenshotStateChanged = { isActive in
            AppModel.shared.clipboardAssistant.setSystemScreenshotActive(isActive)
        }
        monitor.start()
        systemScreenshotMonitor = monitor
    }

    @objc private func showSystemMonitor() {
        let model = AppModel.shared
        guard !model.voiceInput.isRecording, !model.voiceInput.isPreparing else { return }
        model.selectSystemMonitor()
        overlayCoordinator?.showExpanded(at: NSEvent.mouseLocation)
        model.refreshForExpansion()
    }

    @objc private func showSettings() {
        let targetScreen = WindowPlacement.screenUnderMouse()
        if settingsWindowController == nil {
            let rootView = SettingsView(model: AppModel.shared)
            let window = SettingsWindow(
                contentRect: CGRect(x: 0, y: 0, width: 640, height: 640),
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

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? SettingsWindow != nil else { return }
        settingsWindowController = nil
        settingsWindowScreen = nil
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
            let window = QuickNotesEditorWindow(
                contentRect: CGRect(x: 0, y: 0, width: 860, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = localized("随记 · 编辑")
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
        let applicationName = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String ?? processName

        let peer = NSWorkspace.shared.runningApplications.first { application in
            guard application.processIdentifier != current.processIdentifier else { return false }
            if let currentBundleID, application.bundleIdentifier == currentBundleID {
                return true
            }
            if let currentExecutable,
               application.executableURL?.standardizedFileURL == currentExecutable {
                return true
            }
            return application.localizedName == applicationName
        }
        guard let peer else { return true }
        peer.activate(options: [.activateAllWindows])
        return false
    }
}
