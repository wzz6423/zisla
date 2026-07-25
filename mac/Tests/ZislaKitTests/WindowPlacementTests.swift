import AppKit
import CoreGraphics
import Testing

@testable import ZislaKit

struct WindowPlacementTests {
    @Test
    func centersWindowInVisibleScreenFrame() {
        let windowFrame = CGRect(x: 0, y: 0, width: 548, height: 510)
        let screenFrame = CGRect(x: 1_440, y: -120, width: 1_920, height: 1_080)

        #expect(
            WindowPlacement.centeredFrame(for: windowFrame, in: screenFrame)
                == CGRect(x: 2_126, y: 165, width: 548, height: 510)
        )
    }

    @Test
    func centeredFramePreservesWindowSizeOnNegativeDisplayCoordinates() {
        let windowFrame = CGRect(x: 90, y: 40, width: 420, height: 180)
        let screenFrame = CGRect(x: -1_920, y: -180, width: 1_920, height: 1_055)

        let centered = WindowPlacement.centeredFrame(for: windowFrame, in: screenFrame)

        #expect(centered.size == windowFrame.size)
        #expect(centered.midX == screenFrame.midX)
        #expect(centered.midY == screenFrame.midY)
    }

    @Test @MainActor
    func centersWindowOnRequestedScreenVisibleFrame() throws {
        let screen = try #require(NSScreen.screens.first)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        WindowPlacement.center(window, on: screen)

        #expect(abs(window.frame.midX - screen.visibleFrame.midX) <= 1)
        #expect(abs(window.frame.midY - screen.visibleFrame.midY) <= 1)
    }

    /// 授权锚点宿主应落在指定屏幕可见区域中心、保持不可见的极小尺寸且可成为 key，
    /// 这样系统权限面板才会跟随到该屏幕。测试仅验证定位逻辑，不触发激活/前置的系统副作用，
    /// 也不 mock 系统弹窗本身。
    @Test @MainActor
    func authorizationPromptHostUsesRequestedScreen() throws {
        let screen = try #require(NSScreen.screens.first)
        let host = try #require(WindowPlacement.makeAuthorizationPromptHost(on: screen))

        #expect(host.canBecomeKey)
        #expect(host.frame.width > 0 && host.frame.width <= 2)
        #expect(host.frame.height > 0 && host.frame.height <= 2)
        #expect(abs(host.frame.midX - screen.visibleFrame.midX) <= 1)
        #expect(abs(host.frame.midY - screen.visibleFrame.midY) <= 1)
    }
}
