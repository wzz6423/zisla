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
    private var reducer = IslandPresentationReducer()
    private var pointerMonitor: PointerEdgeMonitor?
    private var panel: IslandPanel?
    private var persistentPanels: [CGDirectDisplayID: IslandPanel] = [:]
    private var collapseTask: Task<Void, Never>?
    private var panelCollapseTask: Task<Void, Never>?
    private var pointerRevalidationTask: Task<Void, Never>?
    private var collapseGeneration = CollapseGenerationTracker()
    private var panelCollapseGeneration = CollapseGenerationTracker()
    private var isPointerInside = false
    private var stopsAfterTransientReveal = false
    private var allowsKeyWindow = false
    private var keepsNativeGlassActive = false
    private var isExternalDragging = false
    private var isTransientInteractionVisible = false
    private var collapsedOnTop = true
    private var isPersistentContentVisible = true

    public init(
        contentView: NSView,
        layoutEngine: ScreenLayoutEngine = ScreenLayoutEngine(),
        collapseDelay: Duration = .milliseconds(450),
        persistentContentViewProvider: ((ScreenOverlayLayout) -> NSView?)? = nil,
        persistentPanelFrameProvider: ((ScreenOverlayLayout) -> CGRect)? = nil
    ) {
        self.contentView = contentView
        self.layoutEngine = layoutEngine
        self.collapseDelay = collapseDelay
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
        let wasVisible = panel?.isVisible == true
        panel?.orderOut(nil)
        hidePersistentPanels()
        if wasVisible { onVisibilityChanged?(false) }
        reducer = IslandPresentationReducer()
        activeDisplayID = nil
        isPointerInside = false
        stopsAfterTransientReveal = false
        if isExternalDragging { onDraggingChanged?(false) }
        isExternalDragging = false
        isTransientInteractionVisible = false
    }

    public func refreshScreens() {
        updateScreens(NSScreen.screens.compactMap(ScreenSnapshot.init(screen:)))
    }

    public func updateScreens(
        _ snapshots: [ScreenSnapshot],
        repositionVisiblePanel: Bool = true
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
        updatePersistentPanels()
    }

    public func updateExpandedSize(_ size: CGSize) {
        guard layoutEngine.configuration.expandedSize != size else { return }
        layoutEngine.configuration.expandedSize = size
        updateScreens(
            NSScreen.screens.compactMap(ScreenSnapshot.init(screen:)),
            repositionVisiblePanel: false
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
            panel.ignoresMouseEvents = !isExpanded
            panel.keepsNativeGlassActive = keepsNativeGlassActive && isExpanded
            applyPanelLevel()
            if isExpanded { schedulePointerRevalidation() }
        } else {
            presentCurrentLayout()
        }
    }

    public func handlePointer(at point: CGPoint) {
        guard isRunning else { return }
        if let triggerLayout = layoutEngine.layout(containing: point, in: layouts) {
            let changedDisplay = activeDisplayID != triggerLayout.displayID
            activeDisplayID = triggerLayout.displayID
            if changedDisplay, isVisible {
                presentCurrentLayout()
            }
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
        setPointerInside(isExpanded && contains(point, in: activeLayout.expandedFrame))
    }

    public func setPinned(_ pinned: Bool) {
        if pinned {
            stopsAfterTransientReveal = false
            ensureActiveDisplay()
        }
        process(reducer.send(.setPinned(pinned)))
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
        if !isRunning {
            start()
            stopsAfterTransientReveal = true
        }
        selectActiveDisplay(at: point)
        ensureActiveDisplay()
        isPointerInside = true
        process(reducer.send(.pointerEntered))
    }

    public func setDragging(_ dragging: Bool) {
        guard dragging != isExternalDragging else { return }
        isExternalDragging = dragging
        onDraggingChanged?(dragging)
        updateInteractionHold()
    }

    public func setTransientInteractionVisible(_ visible: Bool) {
        guard visible != isTransientInteractionVisible else { return }
        isTransientInteractionVisible = visible
        updateInteractionHold()
    }

    public func setAllowsKeyWindow(_ allows: Bool) {
        allowsKeyWindow = allows
        panel?.allowsKeyWindow = allows
    }

    /// The window server subdues NSGlassEffectView in inactive non-activating panels.
    /// This is enabled only while the transparent style's island is expanded.
    public func setKeepsNativeGlassActive(_ keepsActive: Bool) {
        guard keepsNativeGlassActive != keepsActive else { return }
        keepsNativeGlassActive = keepsActive
        applyNativeGlassActivation()
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
        // 动态切换置底选项时，在折叠状态下调整窗口尺寸
        let isCollapsed = reducer.state.visibility == .collapsed
        if isCollapsed, let layout = layout(for: activeDisplayID), let panel {
            if onTop {
                // 恢复到 expandedFrame
                if panel.frame != layout.expandedFrame {
                    panel.resize(to: layout.expandedFrame, animated: false)
                }
            } else {
                // 缩小到 collapsedFrame
                if panel.frame != layout.collapsedFrame {
                    panel.resize(to: layout.collapsedFrame, animated: false)
                }
            }
        }
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
        let target = (isExpanded || collapsedOnTop)
            ? IslandPanel.onTopLevel
            : IslandPanel.onBottomLevel
        guard panel.level != target else { return }
        panel.level = target
    }

    private func applyPersistentPanelLevels() {
        let target = IslandPanel.onTopLevel
        for panel in persistentPanels.values where panel.level != target {
            panel.level = target
        }
    }

    private func applyNativeGlassActivation() {
        let isExpanded = reducer.state.visibility == .expanded
            || reducer.state.visibility == .pinned
        panel?.keepsNativeGlassActive = keepsNativeGlassActive && isExpanded
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
        let held = isExternalDragging || isTransientInteractionVisible
        if held { ensureActiveDisplay() }
        process(reducer.send(.setDragging(held)))
    }

    private func process(_ effects: [IslandPresentationReducer.Effect]) {
        for effect in effects {
            switch effect {
            case .show:
                cancelPendingPanelCollapse()
                // 展开前恢复到 expandedFrame（如果之前因置底被缩小）
                if let layout = layout(for: activeDisplayID), panel?.frame != layout.expandedFrame {
                    panel?.resize(to: layout.expandedFrame, animated: false)
                }
                presentCurrentLayout()
                // The collapsed panel is reused; what's being synced here is display state, not the NSPanel lifecycle.
                onVisibilityChanged?(true)
            case .collapse:
                // The host view completes the center-mask animation within the fixed expanded size; on collapse
                // only the hit-testing is disabled — avoids touching the visible NSPanel's frame, which would
                // trigger window-server compositing layer rebuilds.
                onVisibilityChanged?(false)
                panel?.ignoresMouseEvents = true
                panel?.keepsNativeGlassActive = false
                // 折叠置底时缩小窗口到实际的 collapsedFrame，避免遮挡菜单栏图标
                if !collapsedOnTop, let layout = layout(for: activeDisplayID) {
                    panel?.resize(to: layout.collapsedFrame, animated: false)
                }
                applyPanelLevel()
                updatePersistentPanels()
                if stopsAfterTransientReveal { schedulePanelDismiss() }
            case .hide:
                cancelPendingPanelCollapse()
                panel?.ignoresMouseEvents = true
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

    private func ensureActiveDisplay() {
        guard activeDisplayID == nil else { return }
        activeDisplayID =
            preferredLayout(at: NSEvent.mouseLocation)?.displayID
            ?? layouts.first?.displayID
    }

    func selectActiveDisplay(at point: CGPoint) {
        activeDisplayID = preferredLayout(at: point)?.displayID ?? activeDisplayID
        if let layout = layout(for: activeDisplayID) {
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
        let isExpanded = reducer.state.visibility == .expanded
            || reducer.state.visibility == .pinned
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
            panel.allowsKeyWindow = allowsKeyWindow
            self.panel = panel
        }
        panel.keepsNativeGlassActive = keepsNativeGlassActive && isExpanded
        panel.present(
            at: targetFrame,
            from: layout.collapsedFrame,
            animated: !panel.isVisible
        )
        panel.ignoresMouseEvents = !isExpanded
        applyPanelLevel()
        updatePersistentPanels()
    }

    private func updatePersistentPanels() {
        guard isPersistentContentVisible,
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
            if let existingPanel = persistentPanels[layout.displayID] {
                panel = existingPanel
            } else {
                guard let contentView = persistentContentViewProvider(layout) else { continue }
                panel = IslandPanel(
                    contentView: contentView,
                    frame: persistentPanelFrameProvider(layout)
                )
                persistentPanels[layout.displayID] = panel
            }
            panel.allowsKeyWindow = false
            panel.ignoresMouseEvents = true
            panel.level = IslandPanel.onTopLevel
            panel.present(at: persistentPanelFrameProvider(layout), animated: false)
            visibleDisplayIDs.insert(layout.displayID)
        }

        for (displayID, panel) in persistentPanels where !visibleDisplayIDs.contains(displayID) {
            panel.orderOut(nil)
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
        point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
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
            updatePersistentPanels()
        }
    }
}
