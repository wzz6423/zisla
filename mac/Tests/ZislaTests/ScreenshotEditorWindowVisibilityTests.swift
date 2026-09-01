import AppKit
import Testing

@testable import Zisla

@MainActor
struct ScreenshotEditorWindowVisibilityTests {
    @Test
    func hiddenWindowIsNotActivatedBySyntheticMouseEvents() throws {
        let view = ScreenshotPointerInteractionNSView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.alphaValue = 0

        // 窗口初始不可见
        #expect(!window.isVisible)

        // 模拟鼠标事件
        let event = try #require(mouseEvent(
            type: .leftMouseDown,
            location: CGPoint(x: 80, y: 50),
            window: window,
            eventNumber: 1
        ))

        view.mouseDown(with: event)

        // 验证隐藏窗口不会被激活
        #expect(!window.isVisible)
        #expect(!window.isKeyWindow)
    }

    @Test
    func visibleWindowCanBeActivatedByMouseEvents() throws {
        let view = ScreenshotPointerInteractionNSView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.alphaValue = 0
        window.orderFront(nil)

        // 窗口现在可见
        #expect(window.isVisible)

        let event = try #require(mouseEvent(
            type: .leftMouseDown,
            location: CGPoint(x: 80, y: 50),
            window: window,
            eventNumber: 1
        ))

        view.mouseDown(with: event)

        // 可见窗口可以被激活
        #expect(window.isVisible)
    }
}

@MainActor
private func mouseEvent(
    type: NSEvent.EventType,
    location: CGPoint,
    window: NSWindow,
    eventNumber: Int
) -> NSEvent? {
    NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: eventNumber,
        clickCount: 1,
        pressure: 1
    )
}
