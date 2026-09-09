import Foundation
import Testing

@testable import Zisla

struct SideNoticePresenterWindowLifecycleTests {
    @Test @MainActor
    func contentRefreshDoesNotRefrontVisibleNoticePanels() {
        #expect(!SideNoticePresenter.shouldOrderPanelFront(
            isVisible: true,
            rejoiningActiveSpace: false,
            presentsNewCompactStatus: false
        ))
        #expect(SideNoticePresenter.shouldOrderPanelFront(
            isVisible: false,
            rejoiningActiveSpace: false,
            presentsNewCompactStatus: false
        ))
        #expect(SideNoticePresenter.shouldOrderPanelFront(
            isVisible: true,
            rejoiningActiveSpace: true,
            presentsNewCompactStatus: false
        ))
        #expect(SideNoticePresenter.shouldOrderPanelFront(
            isVisible: true,
            rejoiningActiveSpace: false,
            presentsNewCompactStatus: true
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

    @Test
    func noticePanelsUseTheSharedFullscreenWindowBridge() throws {
        let source = try Self.presenterSource()

        #expect(source.contains("SkyLightOperator.shared.delegateWindow(panel)"))
    }

    @Test
    func compactBarKeepsTheLastKnownNotchInsetDuringTopologyGaps() throws {
        let source = try Self.presenterSource()

        #expect(source.contains("if topology.hasPhysicalNotch {"))
        #expect(source.contains("displayState.compactBarCenterInset = topology.anchorFrame.width"))
        #expect(!source.contains("topology.hasPhysicalNotch\n            ? topology.anchorFrame.width\n            : 0"))
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
