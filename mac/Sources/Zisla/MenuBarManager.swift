import AppKit
import ApplicationServices
import Combine
import ZislaCore
import ZislaKit

@MainActor
final class MenuBarManager: NSObject {
    private let store: FeatureSettingsStore
    private let makeItem: @MainActor () -> NSStatusItem
    private let displayWidths: @MainActor () -> [CGFloat]
    private var arrow: NSStatusItem?
    private var divider: NSStatusItem?
    private var moving = false
    private var subscriptions: Set<AnyCancellable> = []

    init(store: FeatureSettingsStore, displayWidths: @escaping @MainActor () -> [CGFloat] = { NSScreen.screens.map(\.frame.width) },
         makeItem: @escaping @MainActor () -> NSStatusItem = {
             NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
         }) {
        self.store = store
        self.makeItem = makeItem
        self.displayWidths = displayWidths
    }

    func start() {
        store.$settings.map(\.menuBarManagementMode).removeDuplicates()
            .sink { [weak self] mode in self?.apply(mode) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    func refresh() {
        apply(store.settings.menuBarManagementMode)
    }

    private func apply(_ mode: MenuBarManagementMode) {
        guard mode != .disabled else {
            divider?.length = NSStatusItem.squareLength
            divider?.isVisible = false
            arrow?.isVisible = false
            return
        }
        if arrow == nil {
            // AppKit inserts new items toward the application menus. Create the arrow on the clock side.
            let arrow = makeItem()
            arrow.autosaveName = "ZislaMenuBarManagementArrow"
            arrow.button?.target = self
            arrow.button?.action = #selector(toggle)
            self.arrow = arrow
            let divider = makeItem()
            divider.autosaveName = Self.dividerID
            divider.button?.setAccessibilityIdentifier(Self.dividerID)
            divider.button?.target = self
            divider.button?.action = #selector(toggle)
            self.divider = divider
        }
        let label = AppLocalization.text(mode == .collapsed ? "展开" : "收起图标")
        let image = NSImage(systemSymbolName: mode == .collapsed ? "chevron.backward" : "chevron.forward",
                            accessibilityDescription: label)
        arrow?.button?.image = image
        arrow?.button?.toolTip = label
        arrow?.button?.setAccessibilityLabel(label)
        arrow?.isVisible = true
        divider?.button?.title = mode == .expanded ? Self.dividerMark : ""
        divider?.button?.setAccessibilityLabel(AppLocalization.text("菜单栏图标"))
        divider?.length = Self.dividerLength(mode: mode, widths: displayWidths(),
                                             modernMenuBar: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27)
        divider?.isVisible = true
    }

    @objc private func toggle() {
        let mode = store.settings.menuBarManagementMode
        guard mode != .disabled else { return }
        store.settings.menuBarManagementMode = mode == .collapsed ? .expanded : .collapsed
    }

    static func dividerLength(mode: MenuBarManagementMode, widths: [CGFloat], modernMenuBar: Bool) -> CGFloat {
        guard mode == .collapsed, let narrowest = widths.min(), let widest = widths.max() else {
            return NSStatusItem.squareLength
        }
        // A single item at or above half a display's width loses its slot on macOS 27.
        return modernMenuBar ? max(1, floor(narrowest / 2) - 22) : min(10_000, widest + 22)
    }

    nonisolated private static let dividerID = "ZislaMenuBarManagementDivider"
    nonisolated private static let dividerMark = "│"

    struct Layout {
        let divider: CGRect
        let bar: CGRect
        let rightToLeft: Bool

        func onHiddenSide(_ frame: CGRect) -> Bool? {
            guard !frame.isEmpty, !divider.isEmpty,
                  bar.contains(CGPoint(x: frame.midX, y: frame.midY)),
                  bar.contains(CGPoint(x: divider.midX, y: divider.midY)),
                  !frame.intersects(divider) else { return nil }
            return rightToLeft ? frame.midX > divider.midX : frame.midX < divider.midX
        }

        func dropPoint(hidden: Bool) -> CGPoint {
            let x = hidden != rightToLeft ? divider.minX + 1 : divider.maxX - 1
            return CGPoint(x: x, y: divider.midY)
        }
    }

    func layout() async -> Layout? {
        guard store.settings.menuBarManagementMode == .expanded, let button = divider?.button else { return nil }
        let label = AppLocalization.text("菜单栏图标")
        // MenuBarAgent can leave a local stub window. Let our main thread answer the AX request for the hosted button.
        let accessible = await Task.detached(priority: .userInitiated) {
            let ownApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(ownApp, 0.15)
            return MenuBarIcon.children(of: ownApp).first {
                (MenuBarIcon.attribute(kAXIdentifierAttribute, of: $0) as? String) == Self.dividerID ||
                    (MenuBarIcon.attribute(kAXTitleAttribute, of: $0) as? String) == Self.dividerMark ||
                    (MenuBarIcon.attribute(kAXDescriptionAttribute, of: $0) as? String) == label
            }.flatMap(AccessibilityGeometry.frame)
        }.value
        guard !Task.isCancelled, store.settings.menuBarManagementMode == .expanded,
              let primary = NSScreen.screens.first else { return nil }
        let localFrame = button.window.flatMap { window -> CGRect? in
            guard !window.frame.isEmpty else { return nil }
            let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            return CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        }
        for frame in [accessible, localFrame].compactMap({ $0 }) where !frame.isEmpty {
            for screen in NSScreen.screens {
                let bar = CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY,
                                 width: screen.frame.width, height: max(screen.safeAreaInsets.top, NSStatusBar.system.thickness))
                if bar.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                    return Layout(divider: frame, bar: bar, rightToLeft: NSApp.userInterfaceLayoutDirection == .rightToLeft)
                }
            }
        }
        return nil
    }

    func move(_ icon: MenuBarIcon, hidden: Bool) async -> Bool {
        guard !moving, !icon.isFixed, AccessibilityPermission.isTrusted else { return false }
        moving = true
        defer { moving = false }
        return await Self.arrange(hidden: hidden) {
            guard let layout = await self.layout(), let frame = AccessibilityGeometry.frame(of: icon.id) else { return nil }
            return (layout, frame)
        } drag: { start, end in
            await self.drag(icon, from: start, to: end)
        }
    }

    static func arrange(hidden: Bool, placement: () async -> (Layout, CGRect)?,
                        drag: (CGPoint, CGPoint) async -> Bool,
                        settle: () async throws -> Void = { try await Task.sleep(for: .milliseconds(50)) }) async -> Bool {
        guard let (layout, frame) = await placement(), let side = layout.onHiddenSide(frame) else { return false }
        if side == hidden { return true }
        guard await drag(CGPoint(x: frame.midX, y: frame.midY), layout.dropPoint(hidden: hidden)) else { return false }
        // WindowServer may publish the reordered frames several run-loop turns after the drop.
        for _ in 0..<8 {
            do { try await settle() } catch { return false }
            guard let (updatedLayout, updatedFrame) = await placement() else { return false }
            if updatedLayout.onHiddenSide(updatedFrame) == hidden { return true }
        }
        return false
    }

    private func drag(_ icon: MenuBarIcon, from start: CGPoint, to end: CGPoint) async -> Bool {
        guard NSEvent.pressedMouseButtons == 0, icon.isAt(start) else { return false }
        let previousPointer = CGEvent(source: nil)?.location
        let drop = await Self.postDrag(from: start, to: end, while: {
            self.store.settings.menuBarManagementMode == .expanded && AccessibilityPermission.isTrusted
        })
        if let drop, let previousPointer, let pointer = CGEvent(source: nil)?.location,
           hypot(pointer.x - drop.x, pointer.y - drop.y) < 2 {
            CGWarpMouseCursorPosition(previousPointer)
        }
        return drop == end
    }

    static func postDrag(from start: CGPoint, to end: CGPoint, while allowed: () -> Bool,
                         post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
                         pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(40)) }) async -> CGPoint? {
        guard allowed(), !Task.isCancelled, let source = CGEventSource(stateID: .combinedSessionState) else { return nil }
        source.localEventsSuppressionInterval = 0
        func event(_ type: CGEventType, at point: CGPoint) -> CGEvent? {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = .maskCommand
            event?.setIntegerValueField(.mouseEventClickState, value: 1)
            return event
        }
        let threshold = CGPoint(x: start.x + (end.x > start.x ? 5 : -5), y: start.y)
        guard let down = event(.leftMouseDown, at: start), let begin = event(.leftMouseDragged, at: threshold),
              let drag = event(.leftMouseDragged, at: end), let up = event(.leftMouseUp, at: end) else { return nil }
        var drop = start
        post(down)
        // Always balance the mouse-down, including when the page closes or access changes mid-drag.
        defer {
            up.location = drop
            post(up)
        }
        do {
            for event in [begin, drag] {
                try await pause()
                guard allowed(), !Task.isCancelled else { return start }
                post(event)
            }
            try await pause()
            if allowed() && !Task.isCancelled { drop = end }
        } catch { return start }
        return drop
    }
}
