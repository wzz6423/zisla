import AppKit
import ZislaCore

struct CollapseGenerationTracker: Equatable, Sendable {
    private var value: UInt64 = 0

    mutating func advance() -> UInt64 {
        value &+= 1
        return value
    }

    func isCurrent(_ candidate: UInt64) -> Bool {
        candidate == value
    }
}

@MainActor
public final class OverlayCoordinator: NSObject {
    public private(set) var layouts: [ScreenOverlayLayout] = []
    public private(set) var activeDisplayID: CGDirectDisplayID?
    public private(set) var isRunning = false
    public var onVisibilityChanged: (@MainActor (Bool) -> Void)?
    public var onDraggingChanged: (@MainActor (Bool) -> Void)?
    public var onCollapsedSizeChanged: (@MainActor (CGSize) -> Void)?
    public var onActiveDisplayHasPhysicalNotchChanged: (@MainActor (Bool) -> Void)?
    public private(set) var persistentPanelDisplayIDs: Set<CGDirectDisplayID> = []

    public var isVisible: Bool {
        reducer.state.visibility != .hidden
    }

    private let contentView: NSView
    private let persistentContentViewProvider: ((ScreenOverlayLayout) -> NSView?)?
    private let persistentPanelFrameProvider: ((ScreenOverlayLayout) -> CGRect)?
    private var layoutEngine: ScreenLayoutEngine
    private let collapseDelay: Duration
    private let pointerEntryGrace: Duration
    private var reducer = IslandPresentationReducer()
    private var pointerMonitor: PointerEdgeMonitor?
    private var panel: IslandPanel?
    private var persistentPanels: [CGDirectDisplayID: IslandPanel] = [:]
    private var collapseTask: Task<Void, Never>?
    private var panelCollapseTask: Task<Void, Never>?
    private var pointerRevalidationTask: Task<Void, Never>?
    private var pointerEntryGraceTask: Task<Void, Never>?
    private var collapseGeneration = CollapseGenerationTracker()
    private var panelCollapseGeneration = CollapseGenerationTracker()
    private var pointerEntryGraceGeneration = CollapseGenerationTracker()
    private var isPointerInside = false
    private var awaitsPointerEntry = false
    private var stopsAfterTransientReveal = false
    private var isPinned = false
    private var allowsKeyWindow = false
    private var keepsNativeGlassActive = false
    private var isExternalDragging = false
    private var isTransientInteractionVisible = false
    private var isVoiceRecording = false
    private var isHoverActivationSuspended = false
    private var isScreenshotCaptureInProgress = false
    private var isScreenshotActive = false
    private var collapsedOnTop = true
    private var isPersistentContentVisible = true
    internal var applicationActivationHandler: () -> Void = {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// - Parameters:
    ///   - collapseDelay: Grace period between the pointer leaving the island and the fold. Zero by
    ///     design: the island belongs to the pointer, so it recycles the moment the pointer is gone
    ///     — the fold animation is what softens the exit, not a wait. Tests raise it to pin the
    ///     island open.
    ///   - pointerEntryGrace: How long an externally triggered reveal (menu bar, hotkey) stays open
    ///     while the pointer is still somewhere else. Without it the first pointer sample, which
    ///     lands outside the island, would fold it before the pointer could travel there.
    public init(
        contentView: NSView,
        layoutEngine: ScreenLayoutEngine = ScreenLayoutEngine(),
        collapseDelay: Duration = .zero,
        pointerEntryGrace: Duration = .seconds(2),
        persistentContentViewProvider: ((ScreenOverlayLayout) -> NSView?)? = nil,
        persistentPanelFrameProvider: ((ScreenOverlayLayout) -> CGRect)? = nil
    ) {
        self.contentView = contentView
        self.layoutEngine = layoutEngine
        self.collapseDelay = collapseDelay
        self.pointerEntryGrace = pointerEntryGrace
        self.persistentContentViewProvider = persistentContentViewProvider
        self.persistentPanelFrameProvider = persistentPanelFrameProvider
        super.init()
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        refreshScreens()

        let monitor = PointerEdgeMonitor { [weak self] point, interaction in
            self?.handlePointer(at: point, interaction: interaction)
        }
        pointerMonitor = monitor
        monitor.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
    }

    public func stop() {
        if isRunning {
            NotificationCenter.default.removeObserver(
                self,
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
            NSWorkspace.shared.notificationCenter.removeObserver(
                self,
                name: NSWorkspace.activeSpaceDidChangeNotification,
                object: NSWorkspace.shared
            )
            isRunning = false
        }
        pointerMonitor?.stop()
        pointerMonitor = nil
        cancelScheduledCollapse()
        cancelPendingPanelCollapse()
        cancelPointerRevalidation()
        endPointerEntryGrace()
        let wasVisible = panel?.isVisible == true
        panel?.keepsNativeGlassActive = false
        panel?.allowsKeyWindow = false
        panel?.orderOut(nil)
        hidePersistentPanels()
        if wasVisible { onVisibilityChanged?(false) }
        reducer = IslandPresentationReducer()
        activeDisplayID = nil
        isPointerInside = false
        stopsAfterTransientReveal = false
        isPinned = false
        if isExternalDragging { onDraggingChanged?(false) }
        isExternalDragging = false
        isTransientInteractionVisible = false
        isVoiceRecording = false
        isHoverActivationSuspended = false
        isScreenshotCaptureInProgress = false
        isScreenshotActive = false
    }

    public func refreshScreens() {
        updateScreens(NSScreen.screens.compactMap(ScreenSnapshot.init(screen:)))
    }

    /// Builds the island panel and lays out its content ahead of the first presentation.
    ///
    /// Creating the panel on first use makes that presentation the hosting view's *initial* render:
    /// SwiftUI has no previous state to animate from, so the surface snaps in fully revealed at
    /// whatever size the layout engine happened to hold instead of growing out of the collapsed pill.
    /// Mounting it collapsed up front gives every later reveal a baseline to animate from.
    public func prewarmPanel() {
        guard isRunning, panel == nil else { return }
        ensureActiveDisplay()
        guard let layout = layout(for: activeDisplayID) else { return }
        onCollapsedSizeChanged?(layout.collapsedFrame.size)
        onActiveDisplayHasPhysicalNotchChanged?(layout.topology.hasPhysicalNotch)
        let panel = IslandPanel(
            contentView: contentView,
            frame: layout.expandedFrame,
            blocksClicksInTransparentAreas: true
        )
        panel.ignoresMouseEvents = true
        panel.contentView?.layoutSubtreeIfNeeded()
        self.panel = panel
    }

    public func updateScreens(
        _ snapshots: [ScreenSnapshot],
        repositionVisiblePanel: Bool = true,
        refreshPersistentPanels: Bool = true
    ) {
        layouts = layoutEngine.layouts(for: snapshots)
        guard !layouts.isEmpty else {
            cancelScheduledCollapse()
            cancelPendingPanelCollapse()
            panel?.orderOut(nil)
            reducer = IslandPresentationReducer()
            activeDisplayID = nil
            isPointerInside = false
            hidePersistentPanels()
            return
        }

        if let activeDisplayID,
            !layouts.contains(where: { $0.displayID == activeDisplayID })
        {
            self.activeDisplayID =
                preferredLayout(at: NSEvent.mouseLocation)?.displayID
                ?? layouts.first?.displayID
        }

        if isVisible, repositionVisiblePanel {
            if activeDisplayID == nil {
                activeDisplayID =
                    preferredLayout(at: NSEvent.mouseLocation)?.displayID
                    ?? layouts.first?.displayID
            }
            presentCurrentLayout()
        }
        if refreshPersistentPanels {
            updatePersistentPanels()
        }
    }

    public func updateExpandedSize(_ size: CGSize) {
        guard layoutEngine.configuration.expandedSize != size else { return }
        layoutEngine.configuration.expandedSize = size
        updateScreens(
            NSScreen.screens.compactMap(ScreenSnapshot.init(screen:)),
            repositionVisiblePanel: false,
            refreshPersistentPanels: false
        )
        guard isVisible else { return }
        if activeDisplayID == nil { ensureActiveDisplay() }
        guard let layout = layout(for: activeDisplayID) else { return }
        let isExpanded = reducer.state.visibility == .expanded
            || reducer.state.visibility == .pinned
        if let panel {
            cancelPendingPanelCollapse()
            onCollapsedSizeChanged?(layout.collapsedFrame.size)
            onActiveDisplayHasPhysicalNotchChanged?(layout.topology.hasPhysicalNotch)
            panel.resize(to: layout.expandedFrame)
            applyPanelInteractionPolicy()
            applyPanelFocusPolicy()
            applyPanelLevel()
            if isExpanded { schedulePointerRevalidation() }
        } else {
            presentCurrentLayout()
        }
    }

    public func handlePointer(at point: CGPoint) {
        guard isRunning,
              !isVoiceRecording,
              !isHoverActivationSuspended,
              !isScreenshotCaptureInProgress
        else { return }
        if let triggerLayout = layoutEngine.layout(containing: point, in: layouts) {
            let changedDisplay = activeDisplayID != triggerLayout.displayID
            activeDisplayID = triggerLayout.displayID
            if changedDisplay, isVisible {
                presentCurrentLayout()
            }
            endPointerEntryGrace()
            setPointerInside(true)
            return
        }

        guard isVisible,
            let activeLayout = layout(for: activeDisplayID)
        else {
            return
        }
        // The expanded region is only used to keep the panel open when already expanded;
        // hovering over the expanded region in the collapsed state does not trigger expansion —
        // only hovering over the notch/island trigger area (triggerFrame) does.
        let isExpanded = reducer.state.visibility == .expanded
            || reducer.state.visibility == .pinned
        let isInside = isExpanded && contains(point, in: activeLayout.expandedFrame)
        if isInside {
            endPointerEntryGrace()
        } else if awaitsPointerEntry {
            // An external reveal is still waiting for the pointer to arrive; folding now would
            // dismiss the island the instant it appeared.
            return
        }
        setPointerInside(isInside)
    }

    public func setPinned(_ pinned: Bool) {
        guard !pinned || !isVoiceRecording else { return }
        isPinned = pinned
        if pinned {
            stopsAfterTransientReveal = false
            ensureActiveDisplay()
            endPointerEntryGrace()
        }
        process(reducer.send(.setPinned(pinned)))
        applyPanelFocusPolicy()
        if pinned { focusKeyboardInputSurfaceIfNeeded() }
    }

    /// Expands the panel without pinning it (does not modify isPinned). Intended for external
    /// entry points such as the menu bar: the panel expands for inspection and collapses
    /// normally once the pointer leaves.
    public func showExpanded() {
        showExpanded(at: NSEvent.mouseLocation)
    }

    /// Expands the panel on the screen containing the given point; used for cross-screen entry
    /// points such as the menu bar.
    public func showExpanded(at point: CGPoint) {
        guard !isVoiceRecording else { return }
        if !isRunning {
            start()
            stopsAfterTransientReveal = true
        }
        selectActiveDisplay(at: point)
        ensureActiveDisplay()
        // Only a reveal that starts away from the island needs the grace; when the pointer already
        // covers it the normal exit rules apply from the first sample.
        if let expandedFrame = layout(for: activeDisplayID)?.expandedFrame,
            contains(point, in: expandedFrame)
        {
            endPointerEntryGrace()
        } else {
            beginPointerEntryGrace()
        }
        isPointerInside = true
        process(reducer.send(.pointerEntered))
    }

    public func setDragging(_ dragging: Bool) {
        guard !isVoiceRecording || !dragging else { return }
        guard dragging != isExternalDragging else { return }
        isExternalDragging = dragging
        onDraggingChanged?(dragging)
        updateInteractionHold()
    }

    public func setTransientInteractionVisible(_ visible: Bool) {
        guard !isVoiceRecording || !visible else { return }
        guard visible != isTransientInteractionVisible else { return }
        isTransientInteractionVisible = visible
        updateInteractionHold()
    }

    /// Pauses hover expansion while another top-level prompt occupies the island trigger area.
    public func setHoverActivationSuspended(_ suspended: Bool) {
        guard isHoverActivationSuspended != suspended else { return }
        isHoverActivationSuspended = suspended
        if suspended {
            endPointerEntryGrace()
            if isPointerInside {
                isPointerInside = false
                process(reducer.send(.pointerExited))
            }
            panel?.orderOut(nil)
            hidePersistentPanels()
        } else if isRunning, reducer.state.visibility != .hidden {
            presentCurrentLayout()
        } else {
            updatePersistentPanels()
        }
    }

    /// Keeps every island window below screenshot selection and editor windows.
    public func setScreenshotActive(_ active: Bool) {
        guard isScreenshotActive != active else { return }
        isScreenshotActive = active
        applyPanelLevel()
        applyPersistentPanelLevels()
    }

    /// Holds the current island presentation until the screen capture has produced its frozen frame.
    public func setScreenshotCaptureInProgress(_ active: Bool) {
        guard isScreenshotCaptureInProgress != active else { return }
        isScreenshotCaptureInProgress = active
        if active {
            cancelScheduledCollapse()
            cancelPointerRevalidation()
            cancelPendingPanelCollapse()
        } else {
            handlePointer(at: NSEvent.mouseLocation)
        }
    }

    /// Immediately folds the island for a foreground panel that must not be obscured by it.
    public func collapseImmediately() {
        guard !isVoiceRecording, !isExternalDragging else { return }
        cancelScheduledCollapse()
        cancelPointerRevalidation()
        endPointerEntryGrace()
        isPinned = false
        process(reducer.send(.collapseImmediately))
    }

    public func setVoiceRecording(_ recording: Bool) {
        setVoiceRecording(recording, at: NSEvent.mouseLocation)
    }

    public func setVoiceRecording(_ recording: Bool, at point: CGPoint) {
        guard recording != isVoiceRecording else { return }
        let wasRecording = isVoiceRecording
        isVoiceRecording = recording

        if recording, !wasRecording {
            selectActiveDisplay(at: point)
            updateInteractionHold()
            endPointerEntryGrace()
            isPinned = false
            process(reducer.send(.setPinned(false)))
            isPointerInside = false
            process(reducer.send(.pointerExited))
            if isVisible {
                presentCurrentLayout()
            }
        } else {
            updateInteractionHold()
        }

        if !recording {
            cancelScheduledCollapse()
            process(reducer.send(.collapseDelayElapsed))
        }
        applyPanelFocusPolicy()
        applyPanelInteractionPolicy()
    }

    public func setAllowsKeyWindow(_ allows: Bool) {
        allowsKeyWindow = allows
        applyPanelFocusPolicy()
        if allows { focusKeyboardInputSurfaceIfNeeded() }
    }

    /// Records whether the island shows the transparent style's native glass surface, which the
    /// panel keeps rendering on its own — no focus is taken for it.
    public func setKeepsNativeGlassActive(_ keepsActive: Bool) {
        guard keepsNativeGlassActive != keepsActive else { return }
        keepsNativeGlassActive = keepsActive
        applyPanelFocusPolicy()
    }

    /// Sets the stacking level of the collapsed Dynamic Island.
    ///
    /// When on top, it shares the menu-bar level, floating above all other windows. When at the
    /// bottom, it drops to the normal window level and is covered by other windows and menu-bar
    /// icons. The expanded state always returns to the on-top level; otherwise the panel can be
    /// obscured by other windows and become uninteractable.
    public func setCollapsedOnTop(_ onTop: Bool) {
        guard collapsedOnTop != onTop else { return }
        collapsedOnTop = onTop
        applyPanelLevel()
        applyPersistentPanelLevels()
    }

    public func setPersistentContentVisible(_ visible: Bool) {
        guard isPersistentContentVisible != visible else { return }
        isPersistentContentVisible = visible
        updatePersistentPanels()
    }

    /// Repositions the transparent persistent-content panels after their external anchor changes.
    public func refreshPersistentPanels() {
        updatePersistentPanels()
    }

    private func applyPanelLevel() {
        guard let panel else { return }
        let isExpanded = reducer.state.visibility == .expanded
            || reducer.state.visibility == .pinned
        let target = isScreenshotActive
            ? IslandPanel.onBottomLevel
            : ((isExpanded || collapsedOnTop)
            ? IslandPanel.onTopLevel
            : IslandPanel.onBottomLevel)
        guard panel.level != target else { return }
        panel.level = target
    }

    private func applyPersistentPanelLevels() {
        let target = isScreenshotActive
            ? IslandPanel.onBottomLevel
            : IslandPanel.onTopLevel
        for panel in persistentPanels.values where panel.level != target {
            panel.level = target
        }
    }

    private func applyPanelFocusPolicy() {
        guard let panel else { return }
        let isExpanded = reducer.state.visibility == .expanded
            || reducer.state.visibility == .pinned
        let allowsInteraction = isExpanded && !isVoiceRecording
        // The recording surface is glass too, and it must never pull focus from the target app.
        let showsGlassSurface = isExpanded || isVoiceRecording
        // Pinned panels may also become key windows so input focus works correctly.
        let shouldAllowKeyWindow = allowsKeyWindow && allowsInteraction

        panel.isPinned = isPinned
        panel.avoidsAppActivation = isVoiceRecording
        panel.allowsKeyWindow = shouldAllowKeyWindow
        panel.keepsNativeGlassActive = keepsNativeGlassActive && showsGlassSurface

        if panel.isKeyWindow, isVoiceRecording || !panel.canBecomeKey {
            panel.resignKey()
        }
    }

    /// Hands the caret to the island only when the user has parked it open on purpose *and* the app
    /// reports a text-input surface (quick notes, mail, teleprompter). Automatic reveals — track
    /// changes, notices, repositioning — are never pinned, so they cannot reach this and cannot pull
    /// the caret out of whatever the user is typing in.
    private func focusKeyboardInputSurfaceIfNeeded() {
        guard isPinned, allowsKeyWindow, let panel, panel.isVisible, !panel.isKeyWindow else {
            return
        }
        panel.takeKeyboardFocus()
    }

    private func applyPanelInteractionPolicy() {
        guard let panel else { return }
        let isExpanded = reducer.state.visibility == .expanded
            || reducer.state.visibility == .pinned
        panel.ignoresMouseEvents = !isExpanded || isVoiceRecording
    }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        process(reducer.send(inside ? .pointerEntered : .pointerExited))
    }

    private func handlePointer(
        at point: CGPoint,
        interaction: PointerEdgeMonitor.Interaction
    ) {
        guard !isVoiceRecording else { return }
        switch interaction {
        case .dragging(let hasSupportedPayload):
            guard hasSupportedPayload else {
                if isExternalDragging { setDragging(false) }
                return
            }
            if let triggerLayout = layoutEngine.transferDragLayout(
                containing: point,
                hasSupportedPayload: true,
                in: layouts
            ) {
                let changedDisplay = activeDisplayID != triggerLayout.displayID
                activeDisplayID = triggerLayout.displayID
                if changedDisplay, isVisible {
                    presentCurrentLayout()
                }
                if !isExternalDragging { setDragging(true) }
            }
        case .dragEnded:
            if isExternalDragging { setDragging(false) }
            handlePointer(at: point)
        case .moved:
            if isExternalDragging { setDragging(false) }
            handlePointer(at: point)
        }
    }

    private func updateInteractionHold() {
        let held = isExternalDragging || isTransientInteractionVisible || isVoiceRecording
        if held { ensureActiveDisplay() }
        process(reducer.send(.setDragging(held)))
    }

    private func process(_ effects: [IslandPresentationReducer.Effect]) {
        for effect in effects {
            switch effect {
            case .show:
                cancelPendingPanelCollapse()
                presentCurrentLayout()
                onVisibilityChanged?(true)
            case .collapse:
                // The host view completes the center-mask animation within the fixed expanded size; on collapse
                // only the hit-testing is disabled — avoids touching the visible NSPanel's frame, which would
                // trigger window-server compositing layer rebuilds.
                onVisibilityChanged?(false)
                panel?.ignoresMouseEvents = true
                applyPanelFocusPolicy()
                applyPanelLevel()
                updatePersistentPanels()
                if stopsAfterTransientReveal { schedulePanelDismiss() }
            case .hide:
                cancelPendingPanelCollapse()
                panel?.ignoresMouseEvents = true
                applyPanelFocusPolicy()
                panel?.dismiss(to: layout(for: activeDisplayID)?.collapsedFrame)
                onVisibilityChanged?(false)
            case .scheduleCollapse:
                scheduleCollapse()
            case .cancelScheduledCollapse:
                cancelScheduledCollapse()
            }
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        guard collapseDelay != .zero else {
            process(reducer.send(.collapseDelayElapsed))
            return
        }
        let token = collapseGeneration.advance()
        let delay = collapseDelay
        collapseTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard let self, collapseGeneration.isCurrent(token) else { return }
            collapseTask = nil
            process(reducer.send(.collapseDelayElapsed))
        }
    }

    private func cancelScheduledCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
        _ = collapseGeneration.advance()
    }

    private func schedulePanelDismiss() {
        panelCollapseTask?.cancel()
        let token = panelCollapseGeneration.advance()
        panelCollapseTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(190))
            } catch {
                return
            }
            guard let self,
                !Task.isCancelled,
                panelCollapseGeneration.isCurrent(token)
            else { return }
            self.panelCollapseTask = nil
            self.stop()
        }
    }

    private func cancelPendingPanelCollapse() {
        panelCollapseTask?.cancel()
        panelCollapseTask = nil
        _ = panelCollapseGeneration.advance()
    }

    private func schedulePointerRevalidation() {
        pointerRevalidationTask?.cancel()
        pointerRevalidationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled,
                reducer.state.visibility == .expanded || reducer.state.visibility == .pinned
            else { return }
            pointerRevalidationTask = nil
            handlePointer(at: NSEvent.mouseLocation)
        }
    }

    private func cancelPointerRevalidation() {
        pointerRevalidationTask?.cancel()
        pointerRevalidationTask = nil
    }

    /// Holds an externally revealed island open until the pointer reaches it. The pointer sits at
    /// the menu bar when the reveal happens, so the very next pointer sample is an "outside" one
    /// and, with no collapse delay left to absorb it, would fold the island immediately.
    private func beginPointerEntryGrace() {
        awaitsPointerEntry = true
        pointerEntryGraceTask?.cancel()
        let token = pointerEntryGraceGeneration.advance()
        let grace = pointerEntryGrace
        pointerEntryGraceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: grace)
            } catch {
                return
            }
            guard let self,
                !Task.isCancelled,
                pointerEntryGraceGeneration.isCurrent(token),
                awaitsPointerEntry
            else { return }
            pointerEntryGraceTask = nil
            awaitsPointerEntry = false
            // The pointer never travelled to the island: fold it exactly like a normal exit.
            setPointerInside(false)
        }
    }

    private func endPointerEntryGrace() {
        guard awaitsPointerEntry || pointerEntryGraceTask != nil else { return }
        awaitsPointerEntry = false
        pointerEntryGraceTask?.cancel()
        pointerEntryGraceTask = nil
        _ = pointerEntryGraceGeneration.advance()
    }

    private func ensureActiveDisplay() {
        guard activeDisplayID == nil else { return }
        activeDisplayID =
            preferredLayout(at: NSEvent.mouseLocation)?.displayID
            ?? layouts.first?.displayID
    }

    public func selectActiveDisplay(at point: CGPoint) {
        activeDisplayID = preferredLayout(at: point)?.displayID ?? activeDisplayID
        if let layout = layout(for: activeDisplayID) {
            // Compact surfaces size themselves from the collapsed pill, so its metrics must land
            // before the caller reads them — not later, when the panel is finally presented.
            onCollapsedSizeChanged?(layout.collapsedFrame.size)
            onActiveDisplayHasPhysicalNotchChanged?(layout.topology.hasPhysicalNotch)
        }
    }

    private func preferredLayout(at point: CGPoint) -> ScreenOverlayLayout? {
        layoutEngine.screenLayout(containing: point, in: layouts)
    }

    private func layout(for displayID: CGDirectDisplayID?) -> ScreenOverlayLayout? {
        guard let displayID else { return nil }
        return layouts.first { $0.displayID == displayID }
    }

    private func presentCurrentLayout() {
        guard let layout = layout(for: activeDisplayID) else { return }
        // After repositioning to a different screen, don't let a pending collapse task on the old screen prematurely hide the shared panel.
        cancelPendingPanelCollapse()
        onCollapsedSizeChanged?(layout.collapsedFrame.size)
        onActiveDisplayHasPhysicalNotchChanged?(layout.topology.hasPhysicalNotch)
        let targetFrame = layout.expandedFrame
        let panel: IslandPanel
        if let existingPanel = self.panel {
            panel = existingPanel
        } else {
            panel = IslandPanel(
                contentView: contentView,
                frame: targetFrame,
                blocksClicksInTransparentAreas: true
            )
            self.panel = panel
        }
        panel.applicationActivationHandler = applicationActivationHandler
        applyPanelFocusPolicy()
        panel.present(
            at: targetFrame,
            from: layout.collapsedFrame,
            animated: !panel.isVisible
        )
        applyPanelInteractionPolicy()
        applyPanelLevel()
        updatePersistentPanels()
    }

    private func updatePersistentPanels(forcePresent: Bool = false) {
        guard !isVoiceRecording,
            isPersistentContentVisible,
            let persistentContentViewProvider,
            let persistentPanelFrameProvider
        else {
            hidePersistentPanels()
            return
        }

        let interactiveDisplayID: CGDirectDisplayID?
        switch reducer.state.visibility {
        case .expanded, .pinned:
            interactiveDisplayID = activeDisplayID
        case .hidden, .collapsed:
            interactiveDisplayID = nil
        }
        var visibleDisplayIDs: Set<CGDirectDisplayID> = []
        for layout in layouts {
            guard layout.displayID != interactiveDisplayID else {
                persistentPanels[layout.displayID]?.orderOut(nil)
                continue
            }
            let panel: IslandPanel
            let isNewPanel: Bool
            if let existingPanel = persistentPanels[layout.displayID] {
                panel = existingPanel
                isNewPanel = false
            } else {
                guard let contentView = persistentContentViewProvider(layout) else { continue }
                panel = IslandPanel(
                    contentView: contentView,
                    frame: persistentPanelFrameProvider(layout)
                )
                persistentPanels[layout.displayID] = panel
                isNewPanel = true
            }
            panel.allowsKeyWindow = false
            panel.ignoresMouseEvents = true
            panel.applicationActivationHandler = applicationActivationHandler
            panel.level = isScreenshotActive
                ? IslandPanel.onBottomLevel
                : IslandPanel.onTopLevel

            let targetFrame = persistentPanelFrameProvider(layout)
            // Present only new, previously hidden, resized, or explicitly refronted panels.
            let needsPresent = isNewPanel || !panel.isVisible || panel.frame != targetFrame || forcePresent
            if needsPresent {
                panel.present(at: targetFrame, animated: false)
            }
            visibleDisplayIDs.insert(layout.displayID)
        }

        persistentPanels.forEach { displayID, panel in
            if !visibleDisplayIDs.contains(displayID) {
                panel.orderOut(nil)
            }
        }
        persistentPanelDisplayIDs = visibleDisplayIDs
    }

    private func hidePersistentPanels() {
        for panel in persistentPanels.values {
            panel.orderOut(nil)
        }
        persistentPanelDisplayIDs.removeAll()
    }

    private func contains(_ point: CGPoint, in frame: CGRect) -> Bool {
        frame.contains(point)
    }

    @objc
    private func screenParametersDidChange(_ notification: Notification) {
        refreshScreens()
    }

    @objc
    private func activeSpaceDidChange(_ notification: Notification) {
        if isVisible {
            presentCurrentLayout()
        } else {
            updatePersistentPanels(forcePresent: true)
        }
    }
}
