import AppKit
import Combine
import SkyLightWindow
import SwiftUI
import ZislaCore
import ZislaKit

extension ClipboardAssistantController {
    /// The clipboard assistant needs extra horizontal space for the content preview and trailing actions.
    private static let islandRowWidth = ScreenLayoutConfiguration().expandedSize.width + 60

    static func trailingControlsWidth(
        for detection: ClipboardAssistantDetection,
        isLightweightMode: Bool,
        shortcutHint: String?,
        locale: Locale
    ) -> CGFloat {
        let horizontalPadding: CGFloat = 22
        if let addedAt = detection.contextNoteAddedAt {
            let time = addedAt.formatted(.dateTime.month().day().hour().minute().locale(AppModel.shared.languageStore.language.locale))
            return horizontalPadding + (time as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
        }
        guard !isLightweightMode, let action = detection.action else {
            return horizontalPadding + 20
        }
        let title = AppLocalization.string(ClipboardAssistantToastView.actionLabel(action), locale: locale)
        let textWidth = (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        ]).width
        let shortcutWidth = shortcutHint.map {
            6 + ($0 as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            ]).width
        } ?? 0
        return horizontalPadding + 22 + 8 + textWidth + shortcutWidth + 24 + 8 + 19 + 8 + 20
    }
}

/// Presentation state driving the island row's SwiftUI content.
@MainActor
final class ClipboardAssistantPresentation: ObservableObject {
    @Published var detection: ClipboardAssistantDetection?
    @Published var translation: ClipboardTranslationPresentation?
    @Published var translationIsPaused = false
    @Published var translationGeneration = 0
    /// Thumbnail preview shown for copied images.
    @Published var imageThumbnail: NSImage?
    /// Matches the surface to the Dynamic Island appearance selected in Settings.
    @Published var visualStyle: IslandVisualStyle = .transparent
    @Published var notchBackground: IslandNotchBackground = .black
    /// The crown remains the same height as the notch the prompt expands from.
    @Published var islandTopHeight: CGFloat = ScreenLayoutConfiguration().simulatedIslandSize.height
    @Published var physicalNotchWidth: CGFloat = 0
    @Published var layout: ClipboardAssistantController.RowLayout?
    @Published var isFolding = false
    @Published var progressGlowEnabled = true
    /// Toggled from the view so the countdown pauses while the pointer rests on the toast.
    var isHovered = false
}

/// Shows a one-row island prompt after every copy, offering smart next-step actions for the copied
/// content.
@MainActor
final class ClipboardAssistantController: ObservableObject {
    static let windowLevel = NSWindow.Level(rawValue: IslandPanel.onTopLevel.rawValue + 1)

    static func makeWindow(contentView: NSView, frame: CGRect) -> IslandPanel {
        let panel = IslandPanel(
            contentView: contentView,
            frame: frame,
            blocksClicksInTransparentAreas: true
        )
        panel.level = windowLevel
        // Clipboard actions must leave the source application's caret in place.
        panel.avoidsAppActivation = true
        SkyLightOperator.shared.delegateWindow(panel)
        return panel
    }

    static let numberedActionHotkeys: [VoiceInputHotkeyPreset] =
        [18, 19, 20, 21, 23, 22, 26, 28, 25, 29].enumerated().map { index, keyCode in
            VoiceInputHotkeyPreset(
                keyCode: UInt32(keyCode), carbonModifiers: 0x0100,
                keyDisplayName: String((index + 1) % 10)
            )
        }

    let presentation = ClipboardAssistantPresentation()
    let systemTranslation = ClipboardSystemTranslationBridge()
    var screenLayoutConfiguration = ScreenLayoutConfiguration() {
        didSet { updateWindowLayout() }
    }
    /// Lets the main island pause hover activation while this row occupies its trigger area.
    var onPresentationChanged: ((Bool) -> Void)?
    /// Auto-dismiss setting for newly presented assistant prompts.
    var displayDuration: ClipboardAssistantDisplayDuration = .fiveSeconds {
        didSet {
            guard displayDuration != oldValue, presentation.detection != nil else { return }
            presentation.objectWillChange.send()
            pauseDismissal()
            if displayDuration.expiresAfter == nil {
                dismissalTotalDuration = nil
                pausedDismissalRemainingFraction = nil
                cancelDismissTask()
            } else if presentation.isHovered {
                cancelDismissTask()
            } else {
                scheduleDismiss()
            }
        }
    }
    /// Executes a detection action; provided by AppModel.
    var onPerformAction: ((ClipboardAssistantAction) -> Void)?
    /// Compact reminder mode: no buttons, tapping anywhere performs the primary action.
    var isLightweightMode = false {
        didSet {
            guard isLightweightMode != oldValue else { return }
            presentation.objectWillChange.send()
            if isLightweightMode { isExpanded = false }
            updateWindowLayout()
        }
    }

    /// Where the assistant row stands while a screenshot session runs.
    private enum ScreenshotPhase {
        /// No screenshot session.
        case inactive
        /// The display is about to be frozen; the row stays visible at its normal level so the
        /// frozen image includes it.
        case capturing
        /// The selection overlay renders the frozen capture (which already contains the row), so
        /// the row hides to avoid a duplicate on top of the overlay.
        case selecting
        /// The overlay is gone (region picked or cancelled) and the row behaves normally again.
        case restored
    }

    private var screenshotPhase = ScreenshotPhase.inactive
    private var isSystemScreenshotActive = false
    private var isScreenLocked = false
    private var isScreenshotActive: Bool {
        screenshotPhase != .inactive || isSystemScreenshotActive
    }
    private var isSharingAnchorHeld = false

    private var window: NSWindow?
    private var presentationPoint = CGPoint.zero
    var screenAtPoint: @MainActor (CGPoint) -> NSScreen? = { WindowPlacement.screenUnderMouse(point: $0) }
    private var dismissTask: Task<Void, Never>?
    private var presentationGeneration = 0
    private var dismissalGeneration = 0
    private var dismissalDeadline: Date?
    private var dismissalTotalDuration: Double?
    private var pausedDismissalRemainingFraction: Double?
    private var isAwaitingCurrencyConversion = false
    private(set) var translationTask: Task<Void, Never>?
    private var translationCopy: ((String) -> Bool)?
    private var translationSourceIsCurrent: (() -> Bool)?
    private var translationReadingSeconds: Double?
    private var visibleTranslationGeneration: Int?
    private var pendingTranslationAppearance: (
        value: ClipboardTranslationPresentation, rowWidth: CGFloat, locale: Locale
    )?
    private let windowPresenter: @MainActor (ClipboardAssistantController, ClipboardAssistantDetection) -> Void
    private let animateDismissal: @MainActor (NSWindow, TimeInterval, @escaping @MainActor () -> Void) -> Void
    private let dismissSleeper: @Sendable (Duration) async throws -> Void
    private let makeTriggerMonitor: @MainActor () -> any ClipboardAssistantTriggerRegistering
    private let triggerMonitor: any ClipboardAssistantTriggerRegistering
    private let dismissTriggerMonitor: any ClipboardAssistantTriggerRegistering
    private var numberedTriggerMonitors: [any ClipboardAssistantTriggerRegistering] = []
    private var configuredHotkey: VoiceInputHotkeyPreset?
    private var configuredDismissHotkey: VoiceInputHotkeyPreset?
    private var configuredMouseButton: Int?
    private var triggerGeneration = 0
    private var isDismissing = false
    private let gestureMonitor = ClipboardAssistantMouseGestureMonitor()
    @Published private(set) var isMoreActionsPresented = false
    @Published private(set) var isExpanded = false
    @Published private(set) var actionHotkeys: [String: [VoiceInputHotkeyPreset]] = [:]
    @Published private(set) var dismissShortcutFeedbackKey: String?

    init(
        window: NSWindow? = nil,
        windowPresenter: @escaping @MainActor (ClipboardAssistantController, ClipboardAssistantDetection) -> Void = {
            $0.showWindow($1)
        },
        animateDismissal: @escaping @MainActor (NSWindow, TimeInterval, @escaping @MainActor () -> Void) -> Void = { window, duration, completion in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated { completion() } })
        },
        dismissSleeper: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        makeTriggerMonitor: @escaping @MainActor () -> any ClipboardAssistantTriggerRegistering = {
            ClipboardAssistantTriggerMonitor()
        }
    ) {
        self.window = window
        self.windowPresenter = windowPresenter
        self.animateDismissal = animateDismissal
        self.dismissSleeper = dismissSleeper
        self.makeTriggerMonitor = makeTriggerMonitor
        triggerMonitor = makeTriggerMonitor()
        dismissTriggerMonitor = makeTriggerMonitor()
    }

    isolated deinit {
        triggerMonitor.stop()
        dismissTriggerMonitor.stop()
        for monitor in numberedTriggerMonitors { monitor.stop() }
    }

    /// Applies the user-configured quick triggers (hotkey + mouse side button).
    /// Returns `false` when registration for a visible prompt needs input-monitoring permission.
    @discardableResult
    func setTriggers(
        hotkey: VoiceInputHotkeyPreset?,
        mouseButton: Int?,
        dismissHotkey: VoiceInputHotkeyPreset? = nil
    ) -> Bool {
        configuredHotkey = hotkey
        configuredMouseButton = mouseButton
        configuredDismissHotkey = dismissHotkey
        let registered = refreshTriggers()
        updateWindowLayout()
        return registered
    }

    func shortcutHint(for action: ClipboardAssistantAction) -> String? {
        guard let hotkeys = actionHotkeys[action.identifier] else { return nil }
        return hotkeys.map { $0.isModifierOnly ? "\($0.settingsDisplayName) ×2" : $0.settingsDisplayName }
            .joined(separator: " / ")
    }

    @discardableResult
    private func refreshTriggers() -> Bool {
        triggerGeneration &+= 1
        let generation = triggerGeneration
        triggerMonitor.stop()
        dismissTriggerMonitor.stop()
        for monitor in numberedTriggerMonitors { monitor.stop() }
        numberedTriggerMonitors.removeAll()
        actionHotkeys = [:]
        dismissShortcutFeedbackKey = nil
        guard !isDismissing, !isScreenshotActive, !isSharingAnchorHeld,
              let detection = presentation.detection else { return true }

        var hasPermission = true
        if let configuredDismissHotkey {
            hasPermission = dismissTriggerMonitor.apply(hotkey: configuredDismissHotkey, mouseButton: nil) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.triggerGeneration == generation else { return }
                    self.dismiss()
                }
            }
            if dismissTriggerMonitor.registeredHotkey == nil {
                dismissShortcutFeedbackKey = "关闭弹窗快捷键未能启用，请检查快捷键冲突或输入监控权限"
            }
        }
        guard presentation.translation == nil, let primary = detection.action else { return hasPermission }
        let registeredDismissHotkey = dismissTriggerMonitor.registeredHotkey
        var primaryHotkey = configuredHotkey
        if let configuredHotkey, registeredDismissHotkey?.conflicts(with: configuredHotkey) == true {
            primaryHotkey = nil
            dismissShortcutFeedbackKey = "关闭弹窗快捷键与动作快捷键相同，当前优先关闭弹窗"
        }

        let primaryHasPermission = triggerMonitor.apply(
            hotkey: primaryHotkey, mouseButton: configuredMouseButton
        ) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.triggerGeneration == generation else { return }
                self.performCurrentAction()
            }
        }
        if let registered = triggerMonitor.registeredHotkey {
            actionHotkeys[primary.identifier] = [registered]
        }
        hasPermission = hasPermission && primaryHasPermission
        guard let configuredHotkey else { return hasPermission }

        for (action, hotkey) in zip(detection.actions, Self.numberedActionHotkeys) {
            if registeredDismissHotkey?.conflicts(with: hotkey) == true {
                dismissShortcutFeedbackKey = "关闭弹窗快捷键与动作快捷键相同，当前优先关闭弹窗"
                continue
            }
            // A custom primary shortcut keeps its meaning even when its registration fails.
            guard !hotkey.conflicts(with: configuredHotkey) else { continue }
            let monitor = makeTriggerMonitor()
            monitor.apply(hotkey: hotkey, mouseButton: nil) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.triggerGeneration == generation else { return }
                    self.perform(action)
                }
            }
            if let registered = monitor.registeredHotkey {
                actionHotkeys[action.identifier, default: []].append(registered)
            }
            numberedTriggerMonitors.append(monitor)
        }
        return hasPermission
    }

    /// Enables the hold-left + right-click quick copy gesture. Returns `false` when either the
    /// input-monitoring or the accessibility permission is missing.
    @discardableResult
    func setMouseGesture(
        enabled: Bool,
        onQuickCopy: @escaping () -> Void
    ) -> Bool {
        guard enabled else {
            gestureMonitor.stop()
            return true
        }
        return gestureMonitor.start(onCopy: onQuickCopy)
    }

    var isMouseGestureActive: Bool { gestureMonitor.isActive }

    /// Returns the elapsed dismissal fraction so the collapsed glow fills from left to right.
    func dismissalProgress(at date: Date = .now) -> Double? {
        guard let remaining = dismissalRemainingFraction(at: date) else { return nil }
        return CollapsedProgress.elapsedFraction(fromRemaining: remaining)
    }

    var windowForFrameUpdate: NSWindow? { window }

    /// Anchor for system sharing launched from the assistant row.
    var sharingAnchorView: NSView? { window?.contentView }

    func setMoreActionsPresented(_ presented: Bool) {
        guard isMoreActionsPresented != presented else { return }
        isMoreActionsPresented = presented
    }

    func setScreenLocked(_ locked: Bool) {
        guard isScreenLocked != locked else { return }
        isScreenLocked = locked
        if locked {
            dismiss(animated: false)
        }
    }

    /// A screenshot session keeps the prompt long enough for the frozen capture, then restores it
    /// after the selection overlay leaves.
    func setScreenshotActive(_ active: Bool) {
        setScreenshotPhase(active ? .capturing : .inactive)
    }

    /// Native screenshot selection is live rather than frozen, so the assistant must leave the
    /// screen before it can cover the system selection or markup UI.
    func setSystemScreenshotActive(_ active: Bool) {
        guard isSystemScreenshotActive != active else { return }
        isSystemScreenshotActive = active
        if active {
            presentation.isHovered = false
            setMoreActionsPresented(false)
        }
        applyScreenshotPhase()
        updateScreenshotDismissal()
    }

    /// The selection overlay already contains the frozen row, so hide the live window to avoid a
    /// duplicate outside the selected region.
    func setScreenshotSelectionActive(_ active: Bool) {
        guard screenshotPhase != .inactive else { return }
        if active { setMoreActionsPresented(false) }
        setScreenshotPhase(active ? .selecting : .restored)
    }

    private func setScreenshotPhase(_ phase: ScreenshotPhase) {
        guard screenshotPhase != phase else { return }
        screenshotPhase = phase
        // The pointer moves onto the selection overlay, so hover must not outlive the capture.
        if phase == .capturing {
            presentation.isHovered = false
        }
        applyScreenshotPhase()
        updateScreenshotDismissal()
    }

    private func updateScreenshotDismissal() {
        presentation.translationIsPaused = isScreenshotActive
        if isScreenshotActive, presentation.translation != nil {
            translationReadingSeconds = nil
            pendingTranslationAppearance = nil
            dismissalTotalDuration = nil
            pausedDismissalRemainingFraction = nil
        }
        if screenshotPhase == .capturing || screenshotPhase == .selecting || isSystemScreenshotActive {
            cancelDismissTask()
        } else {
            scheduleDismiss()
        }
    }

    private func applyScreenshotPhase() {
        refreshTriggers()
        guard let window else { return }
        let hidesLiveWindow = screenshotPhase == .selecting || isSystemScreenshotActive
        window.ignoresMouseEvents = hidesLiveWindow
        window.level = Self.windowLevel
        guard presentation.detection != nil else { return }
        if hidesLiveWindow {
            if window.isVisible {
                window.orderOut(nil)
            }
        } else if screenshotPhase == .restored || screenshotPhase == .inactive {
            if !window.isVisible {
                if let layout = presentation.layout {
                    window.setFrame(layout.frame, display: false)
                }
                window.alphaValue = 1
                window.orderFrontRegardless()
            }
        }
    }

    @discardableResult
    func present(_ detection: ClipboardAssistantDetection, visualStyle: IslandVisualStyle,
                 at point: CGPoint = NSEvent.mouseLocation) -> Int? {
        setMoreActionsPresented(false)
        guard !isScreenshotActive, !isScreenLocked else { return nil }
        presentationPoint = point
        isDismissing = false
        isExpanded = false
        presentation.isFolding = false
        cancelTranslation()
        isSharingAnchorHeld = false
        cancelDismissTask()
        isAwaitingCurrencyConversion = if case .currencyExpression? = detection.detail { true } else { false }
        dismissalTotalDuration = isAwaitingCurrencyConversion ? nil : displayDuration.expiresAfter
        pausedDismissalRemainingFraction = dismissalTotalDuration.map { _ in 1 }
        presentationGeneration &+= 1
        let generation = presentationGeneration
        presentation.isHovered = false
        presentation.visualStyle = visualStyle
        presentation.detection = detection
        presentation.imageThumbnail = Self.thumbnail(for: detection)
        refreshTriggers()
        windowPresenter(self, detection)
        onPresentationChanged?(true)
        scheduleDismiss()
        if detection.kind == .meeting {
            Task { @MainActor [weak self] in
                self?.performPendingCalendarDraft(for: generation)
            }
        }
        return generation
    }

    func performPendingCalendarDraft(for generation: Int) {
        guard presentationGeneration == generation, !isScreenshotActive,
              let action = presentation.detection?.actions.first(where: {
                  if case .editCalendarEvent = $0 { return true }
                  return false
              }) else { return }
        perform(action)
    }

    func dismiss(animated: Bool = true) {
        isDismissing = true
        presentation.isFolding = animated && presentation.layout?.style == .pill
        if !presentation.isFolding { isExpanded = false }
        refreshTriggers()
        cancelTranslation(keepingPresentation: presentation.isFolding)
        setMoreActionsPresented(false)
        isSharingAnchorHeld = false
        cancelDismissTask()
        dismissalDeadline = nil
        dismissalTotalDuration = nil
        pausedDismissalRemainingFraction = nil
        presentationGeneration &+= 1
        let generation = presentationGeneration
        guard let window, window.isVisible else {
            presentation.layout = nil
            presentation.detection = nil
            presentation.translation = nil
            presentation.isFolding = false
            isExpanded = false
            onPresentationChanged?(false)
            return
        }
        guard animated else {
            window.orderOut(nil)
            window.alphaValue = 1
            presentation.layout = nil
            presentation.detection = nil
            presentation.translation = nil
            presentation.isFolding = false
            isExpanded = false
            onPresentationChanged?(false)
            return
        }
        animateDismissal(window, presentation.isFolding ? 0.26 : 0.18) { [weak self] in
            guard let self else { return }
            guard self.presentationGeneration == generation else { return }
            self.window?.orderOut(nil)
            self.window?.alphaValue = 1
            self.presentation.layout = nil
            self.presentation.detection = nil
            self.presentation.translation = nil
            self.presentation.isFolding = false
            self.isExpanded = false
            self.onPresentationChanged?(false)
        }
    }

    /// Fires the given action and dismisses after completion; sharing keeps the anchor until its picker closes.
    func perform(_ action: ClipboardAssistantAction) {
        guard !isDismissing, !isScreenshotActive,
              presentation.translation == nil, !isSharingAnchorHeld,
              presentation.detection?.actions.contains(action) == true else { return }
        setMoreActionsPresented(false)
        let generation = presentationGeneration
        if case .share = action {
            isSharingAnchorHeld = true
            refreshTriggers()
            pauseDismissal()
            cancelDismissTask()
        }
        onPerformAction?(action)
        guard !isSharingAnchorHeld else { return }
        guard presentationGeneration == generation else { return }
        dismiss()
    }

    /// Fires the current detection's primary action (quick trigger or lightweight-mode tap).
    func performCurrentAction() {
        guard let action = presentation.detection?.action else { return }
        perform(action)
    }

    func translate(
        _ text: String,
        targetLanguage: String,
        service: ClipboardTranslationService = .live(),
        isSourceCurrent: @escaping () -> Bool = { true },
        copyResult: @escaping (String) -> Bool
    ) {
        guard let detection = presentation.detection, !isScreenshotActive, !isScreenLocked,
              isSourceCurrent() else { return }
        cancelTranslation()
        cancelDismissTask()
        isExpanded = false
        presentationGeneration &+= 1
        let generation = presentationGeneration
        presentation.translationGeneration = generation
        dismissalTotalDuration = nil
        pausedDismissalRemainingFraction = nil
        presentation.translation = .loading
        refreshTriggers()
        translationCopy = copyResult
        translationSourceIsCurrent = isSourceCurrent
        windowPresenter(self, detection)
        let systemTranslation = systemTranslation
        var additionalProviders: [ClipboardTranslationService.Provider] = []
        if #available(macOS 15.0, *) {
            additionalProviders.append { text, language in
                try await systemTranslation.translate(text, targetLanguage: language)
            }
        }
        translationTask = Task { @MainActor [weak self] in
            let translation: ClipboardTranslationPresentation
            do {
                let result = try await service.translate(
                    text, targetLanguage: targetLanguage, additionalProviders: additionalProviders
                )
                translation = .result(text: result, copied: nil)
            } catch {
                translation = .failed
            }
            guard let self, self.presentationGeneration == generation else { return }
            guard isSourceCurrent() else {
                self.dismiss(animated: false)
                return
            }
            self.presentation.translation = translation
            self.updateWindowLayout()
        }
    }

    func translationWindowDidAppear(for generation: Int) {
        guard presentationGeneration == generation, presentation.translation != nil else { return }
        visibleTranslationGeneration = generation
        if let pending = pendingTranslationAppearance {
            translationDidAppear(pending.value, for: generation, rowWidth: pending.rowWidth, locale: pending.locale)
        }
    }

    func translationDidAppear(
        _ translation: ClipboardTranslationPresentation,
        for generation: Int,
        rowWidth: CGFloat,
        locale: Locale
    ) {
        guard presentationGeneration == generation, presentation.translation == translation,
              translationReadingSeconds == nil else { return }
        guard !isScreenshotActive else { return }
        guard visibleTranslationGeneration == generation else {
            pendingTranslationAppearance = (translation, rowWidth, locale)
            return
        }
        guard translationSourceIsCurrent?() != false else {
            dismiss(animated: false)
            return
        }
        pendingTranslationAppearance = nil
        // SwiftUI may mount a result while the panel is still fading in. Flush its display only
        // after both the row and the window's current reveal have completed.
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.displayIfNeeded()
        switch translation {
        case .loading: return
        case .result(let text, let copied):
            if copied == nil {
                presentation.translation = .result(text: text, copied: translationCopy?(text) == true)
            }
            translationCopy = nil
        case .failed:
            translationCopy = nil
        }
        translationSourceIsCurrent = nil
        translationReadingSeconds = ClipboardTranslationPresentation.readingSeconds(
            for: translation.rowText(locale: locale), rowWidth: rowWidth
        )
        pausedDismissalRemainingFraction = 1
        if !presentation.isHovered { scheduleDismiss() }
    }

    private func cancelTranslation(keepingPresentation: Bool = false) {
        translationTask?.cancel()
        translationTask = nil
        systemTranslation.cancel()
        translationCopy = nil
        translationSourceIsCurrent = nil
        translationReadingSeconds = nil
        visibleTranslationGeneration = nil
        pendingTranslationAppearance = nil
        if !keepingPresentation { presentation.translation = nil }
    }

    func setHovered(_ hovered: Bool) {
        guard presentation.isHovered != hovered else { return }
        presentation.isHovered = hovered
        if hovered {
            pauseDismissal()
            cancelDismissTask()
        } else {
            scheduleDismiss()
        }
    }

    private func scheduleDismiss() {
        cancelDismissTask()
        guard presentation.detection != nil else { return }
        guard !isScreenshotActive else { return }
        guard !isSharingAnchorHeld else { return }
        guard !isAwaitingCurrencyConversion else { return }
        if presentation.translation != nil, translationReadingSeconds == nil { return }
        guard let configuredSeconds = displayDuration.expiresAfter else {
            dismissalTotalDuration = nil
            pausedDismissalRemainingFraction = nil
            dismissTask = nil
            return
        }
        let seconds = max(configuredSeconds, translationReadingSeconds ?? 0)
        dismissalTotalDuration = seconds
        let remainingFraction = pausedDismissalRemainingFraction ?? 1
        let remaining = seconds * remainingFraction
        guard remaining > 0 else {
            dismiss()
            return
        }
        pausedDismissalRemainingFraction = nil
        dismissalDeadline = Date().addingTimeInterval(remaining)
        let presentationGeneration = self.presentationGeneration
        let dismissalGeneration = self.dismissalGeneration
        let dismissSleeper = self.dismissSleeper
        let dismissIfCurrent: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            guard self.presentationGeneration == presentationGeneration,
                  self.dismissalGeneration == dismissalGeneration else { return }
            if self.presentation.isHovered { return }
            self.dismiss()
        }
        dismissTask = Task.detached {
            do {
                try await dismissSleeper(.seconds(remaining))
            } catch {
                return
            }
            await dismissIfCurrent()
        }
    }

    private func cancelDismissTask() {
        dismissTask?.cancel()
        dismissTask = nil
        dismissalDeadline = nil
        dismissalGeneration &+= 1
    }

    private func pauseDismissal() {
        guard dismissalDeadline != nil else { return }
        pausedDismissalRemainingFraction = dismissalRemainingFraction()
        dismissalDeadline = nil
    }

    private func dismissalRemainingFraction(at date: Date = .now) -> Double? {
        if let deadline = dismissalDeadline {
            return CollapsedProgress.remainingFraction(
                until: deadline,
                totalDuration: dismissalTotalDuration,
                at: date
            )
        }
        return pausedDismissalRemainingFraction
    }

    static func thumbnail(for detection: ClipboardAssistantDetection) -> NSImage? {
        for action in detection.actions {
            if case let .saveImage(data) = action {
                return NSImage(data: data)
            }
        }
        return nil
    }

    private func showWindow(_ detection: ClipboardAssistantDetection) {
        guard let layout = rowLayout(for: detection) else { return }
        presentation.islandTopHeight = layout.rowHeight
        let frame = layout.frame
        let window: NSWindow
        if let existing = self.window {
            window = existing
        } else {
            let hostingView = NSHostingView(
                rootView: AppLanguageEnvironment(
                    languageStore: AppModel.shared.languageStore,
                    content: ClipboardAssistantToastView(
                        presentation: presentation,
                        controller: self
                    )
                )
            )
            hostingView.sizingOptions = []
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            window = Self.makeWindow(contentView: hostingView, frame: frame)
            self.window = window
        }
        window.setFrame(frame, display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        let generation = presentationGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.translationWindowDidAppear(for: generation) }
        })
    }

    struct RowLayout: Equatable {
        let frame: CGRect
        let collapsedFrame: CGRect
        let expandedFrame: CGRect
        let rowHeight: CGFloat
        let style: IslandLayoutStyle
        let edge: IslandEdge
        let placementMode: IslandPlacementMode

        var collapsedFrameInSurface: CGRect {
            CGRect(x: collapsedFrame.minX - frame.minX, y: frame.maxY - collapsedFrame.maxY,
                   width: collapsedFrame.width, height: collapsedFrame.height)
        }
    }

    func rowLayout(for detection: ClipboardAssistantDetection) -> RowLayout? {
        guard let screen = screenAtPoint(presentationPoint) else { return nil }
        let snapshot = ScreenSnapshot(screen: screen) ?? ScreenSnapshot(
            displayID: 0, frame: screen.frame, visibleFrame: screen.frame
        )
        return rowLayout(for: detection, on: snapshot)
    }

    func rowLayout(
        for detection: ClipboardAssistantDetection,
        on screen: ScreenSnapshot,
        locale: Locale = AppLocalization.currentLanguage.locale
    ) -> RowLayout {
        var configuration = screenLayoutConfiguration
        let initial = ScreenLayoutEngine(configuration: configuration).layout(for: screen)
        let rowHeight = initial.style == .pill
            ? (initial.edge.isVertical ? initial.collapsedFrame.width : initial.collapsedFrame.height)
            : initial.topology.hasPhysicalNotch
                ? SideNoticeLayoutEngine().compactWingHeight(
                    for: screen, progressGlowEnabled: presentation.progressGlowEnabled
                )
                : initial.collapsedFrame.height
        let notchWidth = initial.style == .pill
            ? initial.centerOcclusionWidth
            : initial.topology.hasPhysicalNotch ? initial.collapsedFrame.width : 0
        let shortcut = detection.action.flatMap { shortcutHint(for: $0) }
        let controlsWidth = initial.style == .pill && configuration.placement.mode == .custom
            ? ClipboardAssistantToastView.compactControlsWidth(
                detection, isLightweightMode: isLightweightMode, shortcutHint: shortcut, locale: locale
            )
            : Self.trailingControlsWidth(
                for: detection, isLightweightMode: isLightweightMode, shortcutHint: shortcut, locale: locale
            )
        let translation = presentation.translation
        let expandsTranslation = translation != nil
            && (translation != .loading || configuration.placement.mode == .camera)
        let compactLength: CGFloat
        if initial.style == .pill && configuration.placement.mode == .custom {
            compactLength = translation != nil
                ? ClipboardTranslationResultView.compactLength(
                    text: ClipboardTranslationPresentation.loading.rowText(locale: locale),
                    edge: initial.edge
                )
                : ClipboardAssistantToastView.compactLength(
                    detection: detection, thickness: rowHeight, edge: initial.edge,
                    isLightweightMode: isLightweightMode, controlsWidth: controlsWidth, locale: locale
                )
            configuration.compactStatusLength = compactLength
        } else {
            compactLength = translation != nil
                ? initial.collapsedFrame.width
                    + (initial.style == .notch && notchWidth > 0 ? SideNoticeLayoutEngine.compactStatusWingWidth * 2 : 0)
                : ClipboardAssistantToastView.requiredRowWidth(
                    baseWidth: Self.islandRowWidth, maximumWidth: max(320, screen.frame.width - 48),
                    notchWidth: notchWidth, trailingControlsWidth: controlsWidth
                )
            configuration.pillSize.width = compactLength
        }
        let detailWidth = max(Self.islandRowWidth, initial.edge.isVertical ? 0 : compactLength)
        let detailHeight = rowHeight + min(
            ClipboardAssistantToastView.estimatedContentHeight(detection.fullContent ?? "", width: detailWidth), 220
        )
        configuration.expandedSize = translation != nil
            ? CGSize(width: max(240, initial.edge.isVertical ? 0 : compactLength),
                     height: rowHeight + VoiceRecordingIslandGeometry.transcriptRowHeight)
            : CGSize(width: detailWidth, height: detailHeight)
        let resolved: RowLayout
        if initial.style == .pill {
            let layout = ScreenLayoutEngine(configuration: configuration).layout(for: screen)
            presentation.physicalNotchWidth = configuration.placement.mode == .camera ? layout.centerOcclusionWidth : 0
            let expanded = isExpanded || expandsTranslation
            resolved = RowLayout(
                frame: expanded ? layout.expandedFrame : layout.collapsedFrame,
                collapsedFrame: layout.collapsedFrame, expandedFrame: layout.expandedFrame,
                rowHeight: rowHeight, style: .pill, edge: layout.edge,
                placementMode: configuration.placement.mode
            )
        } else {
            presentation.physicalNotchWidth = notchWidth
            let collapsed = CGRect(
                x: initial.collapsedFrame.midX - compactLength / 2,
                y: initial.collapsedFrame.maxY - rowHeight, width: compactLength, height: rowHeight
            )
            let height = min(configuration.expandedSize.height, max(rowHeight, screen.visibleFrame.height - 80))
            let expanded = CGRect(x: collapsed.minX, y: collapsed.maxY - height,
                                  width: collapsed.width, height: height)
            let frame = translation != nil || isExpanded ? expanded : collapsed
            resolved = RowLayout(frame: frame, collapsedFrame: collapsed, expandedFrame: expanded,
                                 rowHeight: rowHeight, style: .notch, edge: .top, placementMode: .camera)
        }
        presentation.islandTopHeight = resolved.rowHeight
        presentation.layout = resolved
        return resolved
    }

    func toggleExpansion(_ detection: ClipboardAssistantDetection) {
        guard !isDismissing, !isScreenshotActive, !isSharingAnchorHeld,
              presentation.translation == nil, presentation.detection == detection,
              ClipboardAssistantToastView.canExpand(detection, isLightweightMode: isLightweightMode) else { return }
        isExpanded.toggle()
        updateWindowLayout()
    }

    private func updateWindowLayout() {
        guard !isDismissing, let detection = presentation.detection,
              let layout = rowLayout(for: detection) else { return }
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(layout.frame, display: false)
        }
    }

    /// The result gets the full reading duration; obsolete requests cannot replace a newer prompt.
    func updateDetection(_ detection: ClipboardAssistantDetection, for generation: Int) {
        guard presentationGeneration == generation,
              let current = presentation.detection, current != detection else { return }
        isAwaitingCurrencyConversion = false
        dismissalTotalDuration = displayDuration.expiresAfter
        pausedDismissalRemainingFraction = dismissalTotalDuration.map { _ in 1 }
        presentation.detection = detection
        isExpanded = false
        refreshTriggers()
        if !presentation.isHovered { scheduleDismiss() }
        updateWindowLayout()
    }

}

/// Dynamic Island-styled row: thumbnail or kind icon (color swatch for colors), preview lines,
/// an optional expandable full-content view, and the offered actions. All visible strings are
/// rendered through the app localization so they follow the user's interface language.
struct ClipboardAssistantToastView: View {
    @ObservedObject var presentation: ClipboardAssistantPresentation
    @ObservedObject var controller: ClipboardAssistantController

    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    private var isExpanded: Bool { controller.isExpanded }

    private var rowHeight: CGFloat {
        max(1, presentation.islandTopHeight)
    }

    private var detailIsVisible: Bool {
        rowHeight >= 30
    }

    private var controlVerticalPadding: CGFloat {
        min(6, max(2, (rowHeight - 14) / 2))
    }

    var body: some View {
        GeometryReader { geometry in
            if let translation = presentation.translation {
                ClipboardTranslationResultView(
                    translation: translation,
                    presentation: presentation,
                    controller: controller,
                    size: geometry.size
                )
                .id(presentation.translationGeneration)
                .id(presentation.translationIsPaused)
            } else if let detection = presentation.detection {
                let style = presentation.layout?.style ?? .notch
                let edge = presentation.layout?.edge ?? .top
                let collapsed = presentation.layout?.collapsedFrameInSurface
                    ?? CGRect(x: 0, y: 0, width: geometry.size.width,
                              height: min(geometry.size.height, presentation.islandTopHeight))
                IslandSurface(
                    isCollapsed: !isExpanded || presentation.isFolding,
                    collapsedSize: collapsed.size,
                    expandedSize: geometry.size,
                    visualStyle: presentation.visualStyle,
                    notchBackground: presentation.notchBackground,
                    collapsedTopCornerRadius: 0,
                    bottomCornerRadius: VoiceRecordingIslandGeometry.bottomCornerRadius,
                    layoutStyle: style, collapsedFrame: style == .pill ? collapsed : nil, edge: edge
                ) {
                    if isExpanded {
                        VStack(spacing: 0) {
                            toastHeader(detection)
                            if let content = expandableContent(detection) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 14)
                                expandedContentView(content)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    } else {
                        toastHeader(detection)
                            .frame(width: collapsed.width, height: collapsed.height)
                            .position(x: collapsed.midX, y: collapsed.midY)
                    }
                }
                .overlay {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isDismissalProgressActive)) { context in
                        if !isExpanded, presentation.progressGlowEnabled,
                           let progress = controller.dismissalProgress(at: context.date) {
                            Group {
                                if style == .pill {
                                    CollapsedProgressGlow(progress: progress, layoutStyle: .pill)
                                } else {
                                    CollapsedProgressGlow(progress: progress)
                                        .clipShape(IslandSilhouette(
                                            topCornerRadius: 0,
                                            bottomCornerRadius: VoiceRecordingIslandGeometry.bottomCornerRadius
                                        ))
                                }
                            }
                                .frame(width: collapsed.width, height: collapsed.height)
                                .position(x: collapsed.midX, y: collapsed.midY)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: edge == .bottom ? .bottom : .top)))
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: presentation.detection)
            }
        }
        .ignoresSafeArea(edges: .top)
        .environment(\.colorScheme, .dark)
        .background {
            if #available(macOS 15.0, *) {
                ClipboardSystemTranslationView(bridge: controller.systemTranslation)
            }
        }
    }

    private var isDismissalProgressActive: Bool {
        presentation.progressGlowEnabled
            && !isExpanded
            && controller.dismissalProgress(at: .now) != nil
    }

    // MARK: Header row

    @ViewBuilder
    private func toastHeader(_ detection: ClipboardAssistantDetection) -> some View {
        Group {
            if isCompactSideHeader {
                verticalHeader(detection)
            } else if presentation.physicalNotchWidth > 0 {
                physicalNotchHeader(detection)
            } else {
                continuousHeader(detection)
                    .padding(.horizontal, 14)
            }
        }
        .frame(height: isCompactSideHeader ? nil : rowHeight)
        .contentShape(Rectangle())
        .contextMenu {
            actionMenuItems(detection.actions)
        }
        .onHover { hovering in
            controller.setHovered(hovering)
        }
    }

    private var isCompactSideHeader: Bool {
        !isExpanded && presentation.layout?.style == .pill && presentation.layout?.edge.isVertical == true
    }

    private func verticalHeader(_ detection: ClipboardAssistantDetection) -> some View {
        GeometryReader { geometry in
            let controls = Self.verticalControlsLength(detection, isLightweightMode: controller.isLightweightMode)
            VStack(spacing: 6) {
                headerContent(detection, verticalTextHeight: max(0, geometry.size.height - 16 - 26 - controls - 12))
                verticalControls(detection)
            }
            .padding(.vertical, 8)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture {
                if controller.isLightweightMode { controller.performCurrentAction() }
            }
        }
    }

    private func verticalControls(_ detection: ClipboardAssistantDetection) -> some View {
        VStack(spacing: 6) {
            if controller.isLightweightMode {
                Image(systemName: "sparkle")
                    .font(.system(size: 10))
                    .frame(height: 20)
            } else {
                if Self.canExpand(detection, isLightweightMode: controller.isLightweightMode) {
                    Button { controller.toggleExpansion(detection) } label: {
                        Image(systemName: "chevron.down.circle").frame(width: 24, height: 22)
                    }
                    .help(loc("展开完整内容"))
                }
                if let primary = detection.action {
                    Button { controller.perform(primary) } label: {
                        Image(systemName: primary.kind?.symbolName ?? "arrow.up.right.square")
                            .frame(width: 24, height: 22)
                    }
                    .help(actionTitleWithShortcut(primary))
                    .accessibilityLabel(actionTitleWithShortcut(primary))
                    Button { controller.setMoreActionsPresented(!controller.isMoreActionsPresented) } label: {
                        Image(systemName: "ellipsis.circle").frame(width: 24, height: 22)
                    }
                    .help(loc("更多操作"))
                    .popover(isPresented: Binding(get: { controller.isMoreActionsPresented },
                                                 set: { controller.setMoreActionsPresented($0) }),
                             arrowEdge: Self.verticalMoreActionsPopoverArrowEdge(
                                for: presentation.layout?.edge ?? .top,
                                layoutDirection: layoutDirection
                             )) {
                        moreActionsPopover(for: detection)
                    }
                }
                Button { controller.dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 9)).frame(width: 24, height: 20)
                }
                .help(loc("关闭"))
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
    }

    private func continuousHeader(_ detection: ClipboardAssistantDetection) -> some View {
        HStack(spacing: 10) {
            headerContent(detection)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailingControls(detection)
        }
    }

    private func physicalNotchHeader(_ detection: ClipboardAssistantDetection) -> some View {
        GeometryReader { geometry in
            let sideWidth = Self.physicalNotchSideWidth(
                totalWidth: geometry.size.width,
                notchWidth: presentation.physicalNotchWidth
            )
            let centerWidth = max(0, geometry.size.width - sideWidth * 2)
            HStack(spacing: 0) {
                headerContent(detection)
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
                    .frame(width: sideWidth, height: rowHeight, alignment: .leading)
                    .clipped()

                Spacer(minLength: 0)
                    .frame(width: centerWidth)

                trailingControls(detection)
                    .padding(.leading, 8)
                    .padding(.trailing, 14)
                    .frame(width: sideWidth, height: rowHeight, alignment: .trailing)
                    .clipped()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    static func compactControlsWidth(
        _ detection: ClipboardAssistantDetection, isLightweightMode: Bool,
        shortcutHint: String?, locale: Locale
    ) -> CGFloat {
        if isLightweightMode { return 20 }
        var width: CGFloat = 20
        if let action = detection.action {
            let title = AppLocalization.string(actionLabel(action), locale: locale)
            width += (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width
                + 24 + 19 + 16
            if let shortcutHint {
                width += 6 + (shortcutHint as NSString).size(withAttributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium)
                ]).width
            }
        }
        if canExpand(detection, isLightweightMode: isLightweightMode) { width += 30 }
        return width
    }

    static func verticalControlsLength(
        _ detection: ClipboardAssistantDetection, isLightweightMode: Bool
    ) -> CGFloat {
        if isLightweightMode { return 20 }
        var length: CGFloat = 20
        if detection.action != nil { length += 56 }
        if canExpand(detection, isLightweightMode: isLightweightMode) { length += 28 }
        return length
    }

    static func verticalMoreActionsPopoverArrowEdge(
        for edge: IslandEdge, layoutDirection: LayoutDirection
    ) -> Edge {
        (edge == .left) == (layoutDirection == .leftToRight) ? .leading : .trailing
    }

    static func compactLength(
        detection: ClipboardAssistantDetection, thickness: CGFloat, edge: IslandEdge,
        isLightweightMode: Bool, controlsWidth: CGFloat, locale: Locale
    ) -> CGFloat {
        let title = AppLocalization.string(detection.title, locale: locale)
        if edge.isVertical {
            let textLength = min(168, CGFloat(title.filter { !$0.isWhitespace }.count) * 14)
            return 16 + 26 + 12 + textLength
                + verticalControlsLength(detection, isLightweightMode: isLightweightMode)
        }
        let titleWidth = (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ]).width
        let detailWidth = thickness >= 30 ? detailText(detection.detail, locale: locale).map {
            ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 9.5)]).width
        } ?? 0 : 0
        let accessoryWidth: CGFloat = detection.actions.contains {
            if case .saveImage = $0 { return true }
            return false
        } ? 38 : 26
        return 28 + accessoryWidth + 20 + ceil(max(titleWidth, detailWidth)) + controlsWidth
    }

    nonisolated static func physicalNotchSideWidth(totalWidth: CGFloat, notchWidth: CGFloat) -> CGFloat {
        let totalWidth = max(0, totalWidth)
        let reservedCenterWidth = min(max(0, notchWidth), totalWidth)
        return (totalWidth - reservedCenterWidth) / 2
    }

    nonisolated static func requiredRowWidth(
        baseWidth: CGFloat,
        maximumWidth: CGFloat,
        notchWidth: CGFloat,
        trailingControlsWidth: CGFloat
    ) -> CGFloat {
        let baseWidth = max(0, baseWidth)
        let maximumWidth = max(0, maximumWidth)
        let minimumWidth = notchWidth > 0
            ? max(0, notchWidth) + max(0, trailingControlsWidth) * 2
            : baseWidth
        return min(maximumWidth, max(baseWidth, minimumWidth))
    }

    @ViewBuilder
    private func headerContent(_ detection: ClipboardAssistantDetection, verticalTextHeight: CGFloat? = nil) -> some View {
        if let dragText = Self.dragText(for: detection) {
            headerContentBody(detection, verticalTextHeight: verticalTextHeight)
                .onDrag { NSItemProvider(object: dragText as NSString) }
        } else {
            headerContentBody(detection, verticalTextHeight: verticalTextHeight)
        }
    }

    private func headerContentBody(_ detection: ClipboardAssistantDetection, verticalTextHeight: CGFloat?) -> some View {
        let layout = verticalTextHeight != nil
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            leadingAccessory(detection)

            if let verticalTextHeight {
                VerticalStatusText(text: loc(detection.title), availableHeight: verticalTextHeight)
            } else {
                Group {
                    if detection.contextNoteAddedAt != nil {
                        MarqueeText(detection.title, font: .system(size: 12), textColor: .white.opacity(0.92),
                                    fontWeight: .medium, scrollDirection: layoutDirection == .rightToLeft ? .right : .left)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(detection.title)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLocalization.text(detection.title))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                                .fitsSingleLine()
                                .truncationMode(.middle)
                            if detailIsVisible, let detailText = Self.detailText(detection.detail, locale: locale) {
                                Text(detailText)
                                    .font(.system(size: 9.5, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .fitsSingleLine()
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard controller.isLightweightMode || detection.contextNoteAddedAt != nil else { return }
            controller.performCurrentAction()
        }
    }

    nonisolated static func dragText(for detection: ClipboardAssistantDetection) -> String? {
        guard [.text, .nonSystemLanguageText, .code, .shellCommand, .math].contains(detection.kind),
              let content = detection.fullContent,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return content
    }

    @ViewBuilder
    private func leadingAccessory(_ detection: ClipboardAssistantDetection) -> some View {
        if let thumbnail = presentation.imageThumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: isCompactSideHeader ? max(0, min(26, rowHeight - 6)) : 38,
                       height: max(16, min(28, rowHeight - 6)))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        } else if let components = detection.colorComponents {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(red: components.red, green: components.green, blue: components.blue))
                .frame(width: 26, height: max(16, min(26, rowHeight - 6)))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        } else if let emoji = detection.emoji {
            Text(emoji)
                .font(.system(size: max(16, min(22, rowHeight - 8))))
                .frame(width: 26, height: max(16, min(26, rowHeight - 6)))
        } else {
            Image(systemName: detection.contextNoteAddedAt == nil ? detection.kind.symbolName : "note.text")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 26, height: max(16, min(26, rowHeight - 6)))
        }
    }

    private func trailingControls(_ detection: ClipboardAssistantDetection) -> some View {
        HStack(spacing: 8) {
            if let addedAt = detection.contextNoteAddedAt {
                Text(addedAt, format: .dateTime.month().day().hour().minute())
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .help(addedAt.formatted(.dateTime.year().month().day().hour().minute().second().locale(locale)))
                    .accessibilityLabel(loc("添加时间") + " " + addedAt.formatted(.dateTime.year().month().day().hour().minute().locale(locale)))
            } else if controller.isLightweightMode {
                // Lightweight mode keeps the toast minimal: no buttons at all.
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 20, height: max(16, min(20, rowHeight - 4)))
            } else {
                if Self.canExpand(detection, isLightweightMode: controller.isLightweightMode) {
                    Button {
                        controller.toggleExpansion(detection)
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 22, height: max(16, min(22, rowHeight - 4)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? loc("收起") : loc("展开完整内容"))
                }
                if let primary = detection.action {
                    Button {
                        controller.perform(primary)
                    } label: {
                        HStack(spacing: 6) {
                            Text(loc(Self.actionLabel(primary)))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.95))
                            if let shortcut = controller.shortcutHint(for: primary) {
                                Text(shortcut)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, controlVerticalPadding)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .help(actionTitleWithShortcut(primary))
                }
                if detection.action != nil {
                    Button {
                        controller.setMoreActionsPresented(!controller.isMoreActionsPresented)
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 19, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(loc("更多操作"))
                    .popover(isPresented: Binding(
                        get: { controller.isMoreActionsPresented },
                        set: { controller.setMoreActionsPresented($0) }
                    ), arrowEdge: .top) {
                        moreActionsPopover(for: detection)
                    }
                }
                Button {
                    controller.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 20, height: max(16, min(20, rowHeight - 4)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(loc("关闭"))
            }
        }
    }

    private func menuActions(for detection: ClipboardAssistantDetection) -> [ClipboardAssistantAction] {
        detection.secondaryActions.isEmpty
            ? [detection.action].compactMap { $0 }
            : detection.secondaryActions
    }

    @ViewBuilder
    private func moreActionsPopover(for detection: ClipboardAssistantDetection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(menuActions(for: detection), id: \.identifier) { action in
                if case .blockSourceApp = action {
                    Divider()
                    moreActionButton(action, role: .destructive)
                } else {
                    moreActionButton(action)
                }
            }
        }
        .padding(6)
        .frame(minWidth: 190)
    }

    private func moreActionButton(
        _ action: ClipboardAssistantAction,
        role: ButtonRole? = nil
    ) -> some View {
        Button(role: role) {
            controller.setMoreActionsPresented(false)
            controller.perform(action)
        } label: {
            HStack {
                Text(actionTitle(action))
                Spacer(minLength: 12)
                if let shortcut = controller.shortcutHint(for: action) {
                    Text(shortcut)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actionMenuItems(_ actions: [ClipboardAssistantAction]) -> some View {
        ForEach(actions, id: \.identifier) { action in
            if case .blockSourceApp = action {
                Divider()
                Button(role: .destructive) {
                    controller.perform(action)
                } label: {
                    Text(actionTitleWithShortcut(action))
                }
            } else {
                Button(actionTitleWithShortcut(action)) {
                    controller.perform(action)
                }
            }
        }
    }

    private func actionTitleWithShortcut(_ action: ClipboardAssistantAction) -> String {
        let title = actionTitle(action)
        guard let shortcut = controller.shortcutHint(for: action) else { return title }
        return "\(title) (\(shortcut))"
    }

    // MARK: Expanded content

    static func canExpand(_ detection: ClipboardAssistantDetection, isLightweightMode: Bool) -> Bool {
        guard ![.url, .text, .nonSystemLanguageText, .code, .shellCommand, .math, .conversion].contains(detection.kind) else {
            return false
        }
        guard !isLightweightMode, let content = detection.fullContent else { return false }
        return content.count > 40 || content.contains("\n")
    }

    private func expandableContent(_ detection: ClipboardAssistantDetection) -> String? {
        Self.canExpand(detection, isLightweightMode: controller.isLightweightMode) ? detection.fullContent : nil
    }

    static func estimatedContentHeight(_ content: String, width: CGFloat) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let textWidth = max(1, width - 40)
        var totalLines: CGFloat = 0
        for line in content.components(separatedBy: "\n") {
            let lineWidth = (line as NSString).size(withAttributes: [.font: font]).width
            totalLines += max(1, ceil(lineWidth / textWidth))
        }
        return totalLines * 13 + 24
    }

    private func expandedContentView(_ content: String) -> some View {
        ScrollView(.vertical) {
            Text(content)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(height: isExpanded ? nil : 0)
    }

    // MARK: Localized strings

    private func loc(_ key: String) -> String {
        AppLocalization.string(key, locale: locale)
    }

    /// Locale-aware rendering of the structured detection detail.
    static func detailText(_ detail: ClipboardAssistantDetail?, locale: Locale) -> String? {
        switch detail {
        case .characterCount(let count):
            AppLocalization.format("%ld 个字符", locale: locale, [count])
        case .characterAndWordCount(let characters, let words):
            AppLocalization.format("%ld 个字符 · %ld 个词", locale: locale, [characters, words])
        case .chineseCharacterCount(let count):
            AppLocalization.format("%ld 个字", locale: locale, [count])
        case .codeLines(let lines):
            AppLocalization.format("%ld 行", locale: locale, [lines])
        case .imageSize(let wide, let high, let bytes):
            "\(wide) × \(high) · " + byteCountText(bytes)
        case .fileSize(let bytes):
            byteCountText(bytes)
        case .mathExpression(let expression):
            expression + " ="
        case .currencyExpression(_, let amountText, let source, let target):
            "\(amountText) \(source) → \(target)"
        case .currencyRate(let source, let target, let rate):
            "1 \(source) = \(ClipboardAssistantDetector.formatNumber(rate)) \(target)"
        case .rgb(let red, let green, let blue, let hex):
            String(format: "R%.0f G%.0f B%.0f · #%@", red * 255, green * 255, blue * 255, hex)
        case .path(let path):
            path
        case nil:
            nil
        }
    }

    private static func byteCountText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Localization key for each executable action.
    static func actionLabel(_ action: ClipboardAssistantAction) -> String {
        switch action {
        case .openURL: "打开链接"
        case .openService(let service, _): service.localizedTitleKey
        case .openDownload: "下载"
        case .revealInFinder: "在 Finder 中显示"
        case .openFolder: "打开文件夹"
        case .showContextNote: "查看便签"
        case .copyContextNote: "复制"
        case .deleteContextNote: "删除"
        case .search: "搜索"
        case .translate: "翻译"
        case .autoTranslate: "自动翻译"
        case .composeMail: "写邮件"
        case .copyText: "复制结果"
        case .copyFullExpression: "复制完整算式"
        case .copyEmoji: "复制 Emoji"
        case .compress: "压缩为 ZIP"
        case .share: "系统共享"
        case .callPhone: "拨打电话"
        case .blockSourceApp: "不再显示来自 %@ 的复制"
        case .addToQuickNote: "发送到随记"
        case .sendToTeleprompter: "发送到提词器"
        case .saveImage: "保存图片"
        case .saveText: "保存文本"
        case .runShellCommand: "前台执行"
        case .runShellCommandInBackground: "后台执行"
        case .createCalendarEvent, .editCalendarEvent: "新建日程"
        case .openApp: "打开应用"
        }
    }

    private func actionTitle(_ action: ClipboardAssistantAction) -> String {
        if case .blockSourceApp(_, let appName) = action {
            return AppLocalization.format("不再显示来自 %@ 的复制", locale: locale, [appName])
        }
        return loc(Self.actionLabel(action))
    }
}


/// Fires the assistant's primary action from user-configured quick triggers:
/// - Ordinary hotkey combos register through Carbon (no permission needed).
/// - Modifier-only hotkeys use a listen-only event tap with double-tap detection, so ordinary
///   modifier usage (copy/paste chords) never fires the action accidentally.
/// - Mouse side buttons always require the input-monitoring permission.
@MainActor
protocol ClipboardAssistantTriggerRegistering: AnyObject {
    var registeredHotkey: VoiceInputHotkeyPreset? { get }
    @discardableResult
    func apply(hotkey: VoiceInputHotkeyPreset?, mouseButton: Int?, onTrigger: @escaping () -> Void) -> Bool
    func stop()
}

@MainActor
final class ClipboardAssistantTriggerMonitor: ClipboardAssistantTriggerRegistering {
    private(set) var registeredHotkey: VoiceInputHotkeyPreset?
    private var configuredMouseButton: Int?
    private let registerHotkey: (VoiceInputHotkeyPreset, @escaping () -> Void)
        -> (GlobalHotkeyRegistrationResult, () -> Void)
    private var unregisterHotkey: (() -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierKeyCode: UInt32?
    private var lastModifierReleaseAt: TimeInterval = 0
    private var onTrigger: (() -> Void)?
    private static let doubleTapWindow: TimeInterval = 0.45

    init(
        registerHotkey: @escaping (VoiceInputHotkeyPreset, @escaping () -> Void)
            -> (GlobalHotkeyRegistrationResult, () -> Void) = { hotkey, onTrigger in
                let manager = GlobalHotkeyManager()
                let result = manager.register(hotkey: hotkey, onKeyDown: onTrigger, onKeyUp: {})
                return (result, { manager.unregister() })
            }
    ) {
        self.registerHotkey = registerHotkey
    }

    /// Applies both triggers. Returns `false` when any configured trigger needs the
    /// input-monitoring permission that is not granted yet.
    @discardableResult
    func apply(
        hotkey: VoiceInputHotkeyPreset?,
        mouseButton: Int?,
        onTrigger: @escaping () -> Void
    ) -> Bool {
        stop()
        configuredMouseButton = mouseButton

        var needsInputMonitoring = false
        if let hotkey {
            if hotkey.isModifierOnly {
                if GlobalHotkeyManager.hasInputMonitoringAccess {
                    modifierKeyCode = hotkey.keyCode
                    ensureEventTap()
                    if eventTap != nil { registeredHotkey = hotkey }
                } else {
                    needsInputMonitoring = true
                }
            } else {
                let (result, unregister) = registerHotkey(hotkey, onTrigger)
                unregisterHotkey = unregister
                if result == .registered { registeredHotkey = hotkey }
                needsInputMonitoring = result == .inputMonitoringPermissionRequired
            }
        }
        if mouseButton != nil {
            if GlobalHotkeyManager.hasInputMonitoringAccess {
                ensureEventTap()
            } else {
                needsInputMonitoring = true
            }
        }
        self.onTrigger = onTrigger
        return !needsInputMonitoring
    }

    func stop() {
        unregisterHotkey?()
        unregisterHotkey = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        modifierKeyCode = nil
        lastModifierReleaseAt = 0
        registeredHotkey = nil
        configuredMouseButton = nil
        onTrigger = nil
    }

    /// One shared listen-only tap covers both flagsChanged (modifier double-tap) and
    /// otherMouseDown (side button); the handler filters events by the current configuration.
    private func ensureEventTap() {
        guard eventTap == nil else { return }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << CGEventType.flagsChanged.rawValue
                | CGEventMask(1) << CGEventType.otherMouseDown.rawValue,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<ClipboardAssistantTriggerMonitor>
                    .fromOpaque(userInfo).takeUnretainedValue()
                MainActor.assumeIsolated {
                    monitor.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    private func handle(type: CGEventType, event: CGEvent) {
        guard !GlobalHotkeyManager.isRecordingHotkeys else {
            lastModifierReleaseAt = 0
            return
        }
        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .otherMouseDown:
            let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            guard buttonNumber == configuredMouseButton else { return }
            onTrigger?()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        default:
            break
        }
    }

    /// Double-tap detection for modifier-only hotkeys: only completed press-release cycles count.
    private func handleFlagsChanged(_ event: CGEvent) {
        guard let targetKeyCode = modifierKeyCode else { return }
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == targetKeyCode else { return }
        let stillPressed = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
        guard !stillPressed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let interval = now - lastModifierReleaseAt
        if interval > 0.03, interval <= Self.doubleTapWindow {
            lastModifierReleaseAt = 0
            onTrigger?()
        } else {
            lastModifierReleaseAt = now
        }
    }
}

/// Optional hold-left-mouse + right-click quick copy gesture: listens globally for a
/// right mouse-down while the left button is held, then simulates ⌘C so the selection lands in
/// the pasteboard and the assistant picks it up. Requires input monitoring (listening) and
/// accessibility (posting keystrokes) permissions.
@MainActor
final class ClipboardAssistantMouseGestureMonitor {
    private(set) var isActive = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onCopy: (() -> Void)?
    private var commandCCopyTask: Task<Void, Never>?
    private var copyGeneration = 0

    /// Starts listening; returns `false` when the required permissions are missing.
    @discardableResult
    func start(onCopy: @escaping () -> Void) -> Bool {
        stop()
        guard GlobalHotkeyManager.hasInputMonitoringAccess,
              AccessibilityPermission.isTrusted else {
            return false
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << CGEventType.otherMouseDown.rawValue,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<ClipboardAssistantMouseGestureMonitor>
                    .fromOpaque(userInfo).takeUnretainedValue()
                MainActor.assumeIsolated {
                    monitor.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        self.onCopy = onCopy
        isActive = true
        return true
    }

    func stop() {
        copyGeneration &+= 1
        commandCCopyTask?.cancel()
        commandCCopyTask = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        onCopy = nil
        isActive = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        guard isActive else { return }
        switch type {
        case .otherMouseDown:
            // Right mouse down (CGEvent button 1) while the left button stays held.
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            guard buttonNumber == Int64(CGMouseButton.right.rawValue) else { return }
            guard CGEventSource.buttonState(.combinedSessionState, button: .left) else { return }
            postCommandC()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        default:
            break
        }
    }

    /// Defers ⌘C until the target app has processed the click without letting a stopped monitor post later.
    private func postCommandC() {
        commandCCopyTask?.cancel()
        let generation = copyGeneration
        commandCCopyTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  self.isActive,
                  self.copyGeneration == generation else {
                return
            }
            let keyC: CGKeyCode = 8 // kVK_ANSI_C
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyC, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: keyC, keyDown: false)
            else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            do {
                try await Task.sleep(for: .milliseconds(30))
            } catch {
                up.post(tap: .cghidEventTap)
                return
            }
            up.post(tap: .cghidEventTap)
            guard !Task.isCancelled,
                  self.isActive,
                  self.copyGeneration == generation else {
                return
            }
            self.commandCCopyTask = nil
            self.onCopy?()
        }
    }
}
