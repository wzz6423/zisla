import AppKit
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

/// 历史窗口复用清理面板的窗口约定：普通窗口控件、关闭按钮回落到状态对象，不抢焦点层级。
@Suite(.serialized)
struct SystemMetricsHistoryPanelTests {
    @Test @MainActor
    func usesStandardWindowControlsAndRoutesClose() {
        let presentationState = SystemMetricsHistoryPanelPresentationState()
        let historyWindow = SystemMetricsHistoryPanel(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let window: NSWindow = historyWindow
        var cancelCount = 0
        presentationState.present()
        historyWindow.onCancel = {
            cancelCount += 1
            presentationState.dismiss()
        }

        #expect(!(window is NSPanel))
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.standardWindowButton(.closeButton) != nil)
        #expect(window.standardWindowButton(.miniaturizeButton) != nil)

        window.performClose(nil)
        #expect(cancelCount == 1)
        #expect(!presentationState.isPresented)
    }

    @Test @MainActor
    func staysAtNormalLevelWhenKeyStatusChanges() {
        let window = SystemMetricsHistoryPanel(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.level = .normal

        window.becomeKey()
        #expect(window.level == .normal)

        window.resignKey()
        #expect(window.level == .normal)
    }
}
