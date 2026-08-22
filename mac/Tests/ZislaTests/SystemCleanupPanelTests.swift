import AppKit
import Testing

@testable import Zisla
import ZislaKit

@Suite(.serialized)
struct SystemCleanupPanelTests {
    @Test @MainActor
    func usesStandardWindowControlsAndRoutesClose() {
        let presentationState = SystemCleanupPanelPresentationState()
        let cleanupWindow = SystemCleanupPanel(
            contentRect: CGRect(x: 0, y: 0, width: 560, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        let window: NSWindow = cleanupWindow
        var cancelCount = 0
        presentationState.present()
        cleanupWindow.onCancel = {
            cancelCount += 1
            presentationState.dismiss()
        }

        #expect(!(window is NSPanel))
        #expect(window.styleMask.contains(.titled))
        #expect(window.standardWindowButton(.closeButton) != nil)
        #expect(window.standardWindowButton(.miniaturizeButton) != nil)

        window.performClose(nil)
        #expect(cancelCount == 1)
        #expect(!presentationState.isPresented)
    }

    @Test @MainActor
    func staysAtNormalLevelWhenKeyStatusChanges() {
        let window = SystemCleanupPanel(
            contentRect: CGRect(x: 0, y: 0, width: 560, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.level = .normal

        window.becomeKey()
        #expect(window.level == .normal)

        window.resignKey()

        #expect(window.level == .normal)
    }

    @Test @MainActor
    func leavesAMiniaturizedWindowMinimizedDuringSubsequentUpdates() {
        #expect(!SystemCleanupPanel.shouldOrderFront(isVisible: false, isMiniaturized: true))
        #expect(!SystemCleanupPanel.shouldOrderFront(isVisible: true, isMiniaturized: false))
        #expect(
            !SystemCleanupPanel.shouldOrderFront(
                isVisible: false,
                isMiniaturized: false,
                isAwaitingDismissalState: true
            )
        )
        #expect(SystemCleanupPanel.shouldOrderFront(isVisible: false, isMiniaturized: false))
    }

    @Test @MainActor
    func cleanupPresentationStateOutlivesTheRequestingModule() {
        let state = SystemCleanupPanelPresentationState()
        var systemModule: SystemMonitorView? = SystemMonitorView(
            service: SystemMonitorService(samplingInterval: 1),
            onCleanupRequested: state.present
        )

        systemModule?.onCleanupRequested()
        systemModule = nil

        #expect(state.isPresented)

        state.dismiss()
        #expect(!state.isPresented)
    }
}
