import Foundation
import Testing

@testable import Zisla

struct SideNoticePresenterWindowLifecycleTests {
    @Test @MainActor
    func contentRefreshDoesNotRefrontVisibleNoticePanels() {
        #expect(!SideNoticePresenter.shouldOrderPanelFront(
            isVisible: true,
            rejoiningActiveSpace: false
        ))
        #expect(SideNoticePresenter.shouldOrderPanelFront(
            isVisible: false,
            rejoiningActiveSpace: false
        ))
        #expect(SideNoticePresenter.shouldOrderPanelFront(
            isVisible: true,
            rejoiningActiveSpace: true
        ))
    }

    @Test
    func noticeUpdatesDoNotRunAfterTheIslandGlassActivationPass() throws {
        let source = try Self.presenterSource()

        #expect(!source.contains("schedulePanelsUpdate"))
        #expect(!source.contains("Task.sleep(for: .milliseconds(16))"))
    }

    @Test
    func noticePanelsAlwaysRejoinFullscreenSpacesWhenPresented() throws {
        let source = try Self.presenterSource()

        #expect(source.contains("panel.orderFrontRegardless()"))
        #expect(!source.contains("panel.orderFront(nil)"))
    }

    private static func presenterSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/SideNoticePresenter.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
