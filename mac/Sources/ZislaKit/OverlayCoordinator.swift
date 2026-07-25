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

    public var isVisible: Bool {
        reducer.state.visibility != .hidden
    }

    private let contentView: NSView
    private var layoutEngine: ScreenLayoutEngine
    private let collapseDelay: Duration
    private var reducer = IslandPresentationReducer()
    private var pointerMonitor: PointerEdgeMonitor?
    private var panel: IslandPanel?
    private var collapseTask: Task<Void, Never>?
    private var panelCollapseTask: Task<Void, Never>?
    private var pointerRevalidationTask: Task<Void, Never>?
    private var collapseGeneration = CollapseGenerationTracker()
    private var panelCollapseGeneration = CollapseGenerationTracker()
    private var isPointerInside = false
    private var stopsAfterTransientReveal = false
    private var allowsKeyWindow = false
    private var isExternalDragging = false
    private var isTransientInteractionVisible = false

    public init(
        contentView: NSView,
        layoutEngine: ScreenLayoutEngine = ScreenLayoutEngine(),
        collapseDelay: Duration = .milliseconds(450)
    ) {
        self.contentView = contentView
        self.layoutEngine = layoutEngine
        self.collapseDelay = collapseDelay
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
        NotificationCenter.default.addObserver(
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
            NotificationCenter.default.removeObserver(
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
            panel.resize(to: layout.expandedFrame)
            panel.ignoresMouseEvents = !isExpanded
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
        // 展开区仅在「已展开」时用于保持打开；折叠态下鼠标进入展开区不触发展开，
        // 只有悬停在刘海/岛身触发区（triggerFrame）才会展开。
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

    /// 展开面板但不固定（不修改 isPinned）。适用于菜单栏等外部入口：
    /// 面板展开供查阅，鼠标离开后按正常规则折叠。
    public func showExpanded() {
        showExpanded(at: NSEvent.mouseLocation)
    }

    /// 展开面板到指定坐标所在的屏幕，用于菜单栏等跨屏入口。
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
                presentCurrentLayout()
                // 收起态的 panel 会复用；这里同步的是展示状态而非 NSPanel 生命周期。
                onVisibilityChanged?(true)
            case .collapse:
                // 宿主视图在固定的展开尺寸内完成中心遮罩动画；收起时只关闭命中，
                // 避免修改可见 NSPanel 的 frame 触发窗口服务器重建合成层。
                onVisibilityChanged?(false)
                panel?.ignoresMouseEvents = true
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
        // 跨屏重定位后不能让旧屏幕的延迟收起任务提前隐藏共享面板。
        cancelPendingPanelCollapse()
        onCollapsedSizeChanged?(layout.collapsedFrame.size)
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
        panel.present(
            at: targetFrame,
            from: layout.collapsedFrame,
            animated: !panel.isVisible
        )
        panel.ignoresMouseEvents = !isExpanded
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
        guard isVisible else { return }
        presentCurrentLayout()
    }
}
