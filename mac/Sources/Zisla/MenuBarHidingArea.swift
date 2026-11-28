import AppKit
import ApplicationServices
import ZislaKit

@MainActor
protocol MenuBarIconPlacing {
    func setArea(_ state: MenuBarHidingArea.State)
    func layout() async -> MenuBarHidingArea.Layout?
    func move(_ icon: MenuBarIcon, hidden: Bool, byMovingBoundary: Bool) async -> Bool
}

@MainActor
final class MenuBarHidingArea: MenuBarIconPlacing {
    enum State { case inactive, editing, hiding, compactHiding }

    private var divider: NSStatusItem?
    private var state = State.inactive

    func setArea(_ state: State) {
        self.state = state
        if state == .inactive {
            if let divider {
                divider.length = 1
                NSStatusBar.system.removeStatusItem(divider)
                self.divider = nil
            }
            return
        }
        if divider == nil {
            let item = NSStatusBar.system.statusItem(withLength: 12)
            item.autosaveName = Self.dividerID
            item.button?.setAccessibilityIdentifier(Self.dividerID)
            item.button?.setAccessibilityLabel(Self.dividerID)
            divider = item
        }
        let widths = NSScreen.screens.map(\.frame.width)
        divider?.length = state == .editing ? 12 : Self.hidingWidth(widths: widths, compact: state == .compactHiding)
        divider?.isVisible = true
    }

    static func hidingWidth(widths: [CGFloat], compact: Bool) -> CGFloat {
        guard let small = widths.min(), let large = widths.max() else { return 1 }
        // When a wide slot is discarded on macOS 27, keep the retry below half the narrowest display.
        return compact ? max(1, floor(small / 2) - 22) : min(10_000, large + 22)
    }

    nonisolated static let dividerID = "ZislaHiddenIconBoundary"

    struct Layout {
        let divider: CGRect
        let bar: CGRect
        let rightToLeft: Bool
        var handle: MenuBarIcon?

        func onHiddenSide(_ frame: CGRect) -> Bool? {
            guard !frame.isEmpty, !divider.isEmpty,
                  bar.contains(CGPoint(x: frame.midX, y: frame.midY)),
                  bar.contains(CGPoint(x: divider.midX, y: divider.midY)),
                  !frame.intersects(divider) else { return nil }
            return rightToLeft ? frame.midX > divider.midX : frame.midX < divider.midX
        }

        func dropPoint(hidden: Bool, at slot: CGRect? = nil) -> CGPoint {
            let bounds = slot ?? divider
            let x = hidden != rightToLeft ? bounds.minX + 1 : bounds.maxX - 1
            return CGPoint(x: x, y: bounds.midY)
        }
    }

    func layout() async -> Layout? {
        guard state == .editing, let button = divider?.button else { return nil }
        // MenuBarAgent can leave a local stub window. Let our main thread answer the AX request for the hosted button.
        let accessible = await Task.detached(priority: .userInitiated) { () -> MenuBarIcon? in
            let ownApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(ownApp, 0.15)
            guard let element = MenuBarIcon.children(of: ownApp).first(where: {
                (MenuBarIcon.attribute(kAXIdentifierAttribute, of: $0) as? String) == Self.dividerID ||
                    (MenuBarIcon.attribute(kAXDescriptionAttribute, of: $0) as? String) == Self.dividerID
            }), let frame = AccessibilityGeometry.frame(of: element) else { return nil }
            return MenuBarIcon(element: element, row: .local("boundary", title: Self.dividerID), frame: frame)
        }.value
        guard !Task.isCancelled, state == .editing,
              let primary = NSScreen.screens.first else { return nil }
        let localFrame = button.window.flatMap { window -> CGRect? in
            guard !window.frame.isEmpty else { return nil }
            let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            return CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        }
        for frame in [accessible?.frame, localFrame].compactMap({ $0 }) where !frame.isEmpty {
            for screen in NSScreen.screens {
                let bar = CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY,
                                 width: screen.frame.width, height: max(screen.safeAreaInsets.top, NSStatusBar.system.thickness))
                if bar.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                    return Layout(divider: frame, bar: bar, rightToLeft: NSApp.userInterfaceLayoutDirection == .rightToLeft,
                                  handle: frame == accessible?.frame ? accessible : nil)
                }
            }
        }
        return nil
    }

    func move(_ icon: MenuBarIcon, hidden: Bool, byMovingBoundary: Bool) async -> Bool {
        await Self.arrange(hidden: hidden) {
            guard let layout = await self.layout(), let frame = AccessibilityGeometry.frame(of: icon.element) else { return nil }
            return (layout, frame)
        } drag: { start, end in
            if !byMovingBoundary { return await self.drag(icon, from: start, to: end) }
            // Some owners refuse to move their item. Put our own boundary on the opposite side instead.
            guard let layout = await self.layout(), let handle = layout.handle,
                  let slot = AccessibilityGeometry.frame(of: icon.element), layout.onHiddenSide(slot) != nil else { return false }
            let origin = CGPoint(x: layout.divider.midX, y: layout.divider.midY)
            return await self.drag(handle, from: origin, to: layout.dropPoint(hidden: !hidden, at: slot))
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
        guard NSEvent.pressedMouseButtons == 0, await Task.detached(operation: { icon.isAt(start, unambiguous: icon.unambiguous) }).value else { return false }
        let previousPointer = CGEvent(source: nil)?.location
        let drop = await Self.postDrag(from: start, to: end, while: {
            self.state == .editing && AccessibilityPermission.isTrusted
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
        // Always balance the mouse-down, including when access changes mid-drag.
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
