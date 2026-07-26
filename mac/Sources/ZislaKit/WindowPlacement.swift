import AppKit

@MainActor
private final class AuthorizationPromptHostWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class TransientWindowLevelPromoter: NSObject {
    @objc func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        WindowPlacement.promoteTransientWindowIfNeeded(window)
    }
}

/// Provides window positioning for windows that should appear on the current working screen.
public enum WindowPlacement {
    @MainActor
    private static var transientWindowLevelPromoter: TransientWindowLevelPromoter?

    /// Modal windows must stay above the Dynamic Island's status-bar-level panel.
    @MainActor
    public static var modalWindowLevel: NSWindow.Level {
        .popUpMenu
    }

    /// SwiftUI may create its own alert or confirmation window after the presenting view appears.
    /// Observe it once so those transient windows follow the same ordering rule as AppKit modals.
    @MainActor
    public static func installTransientWindowPromotion() {
        guard transientWindowLevelPromoter == nil else { return }
        let promoter = TransientWindowLevelPromoter()
        NotificationCenter.default.addObserver(
            promoter,
            selector: #selector(TransientWindowLevelPromoter.windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        transientWindowLevelPromoter = promoter
    }

    @MainActor
    static func promoteTransientWindowIfNeeded(_ window: NSWindow) {
        guard !(window is IslandPanel), window.level.rawValue < modalWindowLevel.rawValue else { return }
        window.level = modalWindowLevel
    }

    /// Returns the screen containing the pointer; falls back to the main screen or first screen
    /// when the pointer is temporarily outside all screens.
    @MainActor
    public static func screenUnderMouse(
        point: CGPoint = NSEvent.mouseLocation,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? screens.first
    }

    /// Computes the centered position of a window within a screen's visible area.
    public static func centeredFrame(for windowFrame: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - windowFrame.width / 2,
            y: screenFrame.midY - windowFrame.height / 2,
            width: windowFrame.width,
            height: windowFrame.height
        )
    }

    /// Centers a window on the given screen; defaults to the screen under the mouse when omitted.
    @MainActor
    public static func center(_ window: NSWindow, on screen: NSScreen? = nil) {
        guard let targetScreen = screen ?? screenUnderMouse() else { return }
        let frame = centeredFrame(for: window.frame, in: targetScreen.visibleFrame)
        window.setFrame(frame, display: true)
    }

    /// Prepares an AppKit modal before `runModal()` so the island cannot intercept its controls.
    @MainActor
    public static func prepareModal(_ window: NSWindow, on screen: NSScreen? = nil) {
        window.level = modalWindowLevel
        center(window, on: screen)
    }

    /// Provides a key-window host on the screen under the mouse for system authorization panels.
    /// Activates the app and brings the host to the front so the system permission panel follows to that screen.
    @MainActor
    public static func authorizationPromptHost(on screen: NSScreen? = nil) -> NSWindow? {
        guard let host = makeAuthorizationPromptHost(on: screen) else { return nil }
        NSApp.activate(ignoringOtherApps: true)
        host.makeKeyAndOrderFront(nil)
        return host
    }

    /// Builds and centers the authorization anchor host without activating or ordering it front;
    /// separates system side-effects from the testable positioning logic.
    @MainActor
    static func makeAuthorizationPromptHost(on screen: NSScreen? = nil) -> NSWindow? {
        guard let targetScreen = screen ?? screenUnderMouse() else { return nil }

        let host = AuthorizationPromptHostWindow(
            contentRect: CGRect(x: 0, y: 0, width: 2, height: 2),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // This host is created and strongly retained in code; its lifetime is fully managed by ARC.
        // NSWindow.isReleasedWhenClosed defaults to true, causing AppKit to issue an extra release
        // on close() — combined with ARC's strong reference this results in an over-release and a
        // guaranteed crash after the authorization flow calls close(). Setting it to false prevents this.
        host.isReleasedWhenClosed = false
        host.isOpaque = false
        host.backgroundColor = .clear
        host.hasShadow = false
        host.ignoresMouseEvents = true
        host.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]

        center(host, on: targetScreen)
        return host
    }
}
