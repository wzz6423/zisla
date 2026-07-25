import AppKit

@MainActor
private final class AuthorizationPromptHostWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 提供需要显示在当前工作屏幕上的窗口定位。
public enum WindowPlacement {
    /// 返回包含指针的屏幕；指针暂时不在任何屏幕时使用系统主屏或首个屏幕。
    @MainActor
    public static func screenUnderMouse(
        point: CGPoint = NSEvent.mouseLocation,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? screens.first
    }

    /// 计算窗口在屏幕可见区域内的居中位置。
    public static func centeredFrame(for windowFrame: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - windowFrame.width / 2,
            y: screenFrame.midY - windowFrame.height / 2,
            width: windowFrame.width,
            height: windowFrame.height
        )
    }

    /// 将窗口放到指定屏幕；未指定时使用鼠标所在屏幕。
    @MainActor
    public static func center(_ window: NSWindow, on screen: NSScreen? = nil) {
        guard let targetScreen = screen ?? screenUnderMouse() else { return }
        let frame = centeredFrame(for: window.frame, in: targetScreen.visibleFrame)
        window.setFrame(frame, display: true)
    }

    /// 为系统授权面板提供当前鼠标所在屏幕上的 key window 宿主，
    /// 激活应用并前置该宿主，使系统权限面板跟随到该屏幕。
    @MainActor
    public static func authorizationPromptHost(on screen: NSScreen? = nil) -> NSWindow? {
        guard let host = makeAuthorizationPromptHost(on: screen) else { return nil }
        NSApp.activate(ignoringOtherApps: true)
        host.makeKeyAndOrderFront(nil)
        return host
    }

    /// 构建并居中授权锚点宿主，但不激活或前置；将系统副作用与可测试的定位逻辑分离。
    @MainActor
    static func makeAuthorizationPromptHost(on screen: NSScreen? = nil) -> NSWindow? {
        guard let targetScreen = screen ?? screenUnderMouse() else { return nil }

        let host = AuthorizationPromptHostWindow(
            contentRect: CGRect(x: 0, y: 0, width: 2, height: 2),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // 该宿主由代码创建并持有强引用，其生命周期完全交给 ARC 管理。
        // NSWindow.isReleasedWhenClosed 默认为 true，会在 close() 时由 AppKit
        // 额外 release 一次；与 ARC 的强引用叠加会造成过度释放，授权流程调用
        // close() 后必崩溃。显式置为 false 可避免这一崩溃。
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
