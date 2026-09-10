import Foundation
import Testing
import ZislaCore
import ZislaKit

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

    @Test @MainActor
    func compactBarPreservesProgressClearanceDuringFullscreenTopologyGaps() throws {
        var lastPhysicalSnapshot: ScreenSnapshot?
        let complete = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )
        _ = SideNoticePresenter.snapshotPreservingPhysicalNotch(
            complete,
            lastPhysicalSnapshot: &lastPhysicalSnapshot
        )
        var gap = complete
        gap.visibleFrame = gap.frame
        gap.safeAreaInsets = ScreenInsets()
        gap.auxiliaryTopLeftArea = nil
        gap.auxiliaryTopRightArea = nil

        let resolved = SideNoticePresenter.snapshotPreservingPhysicalNotch(
            gap,
            lastPhysicalSnapshot: &lastPhysicalSnapshot
        )
        let layout = SideNoticeLayoutEngine()
        let baselineHeight = layout.compactBarFrame(for: resolved).height
        var settings = FeatureSettings()
        settings.collapsedProgressGlowEnabled = true
        let progressNotices = [
            IslandNotice(id: "media-active-left", title: "Music", side: .left),
            IslandNotice(id: "browser-download-left", title: "Download", side: .left),
            IslandNotice(id: "video-download-left", title: "Video", side: .left),
        ]
        for notice in progressNotices {
            let frame = try #require(layout.compactBarFrame(for: resolved, notices: [notice], settings: settings))
            #expect(frame.height == baselineHeight + 2)
        }
        let nonProgressFrame = try #require(layout.compactBarFrame(
            for: resolved,
            notices: [IslandNotice(id: "ai-active-left", title: "AI", side: .left)],
            settings: settings
        ))
        #expect(nonProgressFrame.height == baselineHeight)
        #expect(ScreenLayoutEngine().layout(for: resolved).topology.hasPhysicalNotch)
        let source = try Self.presenterSource()
        #expect(source.contains("lastPhysicalSnapshot: &panels.lastPhysicalSnapshot"))
    }

    @Test @MainActor
    func compactBarDoesNotReusePhysicalNotchAcrossDisplaysOrFrameChanges() {
        var lastPhysicalSnapshot: ScreenSnapshot?
        let complete = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )
        _ = SideNoticePresenter.snapshotPreservingPhysicalNotch(
            complete,
            lastPhysicalSnapshot: &lastPhysicalSnapshot
        )
        var gap = complete
        gap.visibleFrame = gap.frame
        gap.safeAreaInsets = ScreenInsets()
        gap.auxiliaryTopLeftArea = nil
        gap.auxiliaryTopRightArea = nil

        let otherDisplay = ScreenSnapshot(
            displayID: 43,
            frame: gap.frame,
            visibleFrame: gap.visibleFrame,
            safeAreaInsets: gap.safeAreaInsets,
            auxiliaryTopLeftArea: gap.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: gap.auxiliaryTopRightArea
        )
        let otherDisplayResolved = SideNoticePresenter.snapshotPreservingPhysicalNotch(
            otherDisplay,
            lastPhysicalSnapshot: &lastPhysicalSnapshot
        )
        #expect(!ScreenLayoutEngine().layout(for: otherDisplayResolved).topology.hasPhysicalNotch)

        var resized = gap
        resized.frame.size.width += 1
        resized.visibleFrame = resized.frame
        let resizedResolved = SideNoticePresenter.snapshotPreservingPhysicalNotch(
            resized,
            lastPhysicalSnapshot: &lastPhysicalSnapshot
        )
        #expect(!ScreenLayoutEngine().layout(for: resizedResolved).topology.hasPhysicalNotch)
    }

    @Test
    func screenshotFrozenPresentationHidesLiveNoticePanelsUntilRestored() throws {
        let source = try Self.presenterSource()

        #expect(source.contains("if active {\n            hideAllPanels()\n        } else {\n            updatePanels()\n        }"))
        #expect(source.contains("guard !isScreenshotActive, !suppression.hidesNotices else {"))
    }

    @Test
    func screenLockSuppressionIsWiredIndependentlyOfLockScreenInformation() throws {
        let presenterSource = try Self.presenterSource()
        let appSource = try Self.appSource()
        let controllerSource = try Self.lockScreenControllerSource()

        #expect(presenterSource.contains("func setScreenLocked(_ locked: Bool)"))
        #expect(presenterSource.contains("updateSuppression { $0.isScreenLocked = locked }"))
        #expect(appSource.contains("lockScreenOverlayController.onScreenLockedChanged ="))
        #expect(appSource.contains("self?.noticePresenter?.setScreenLocked(locked)"))
        #expect(appSource.contains("isScreenLocked: lockScreenOverlayController.isScreenLocked"))
        #expect(appSource.contains("lockScreenOverlayController.start()"))
        #expect(appSource.components(separatedBy: "lockScreenOverlayController.start()").count == 2)
        #expect(!appSource.contains(".map(\\.lockScreenInfoEnabled)"))
        #expect(appSource.components(separatedBy: "lockScreenOverlayController?.stop()").count == 2)
        #expect(controllerSource.contains("startSessionPolling()"))
        #expect(!controllerSource.contains("guard enabled else {\n            stopSessionPolling()"))
    }

    private static func appSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/ZislaApp.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func presenterSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/SideNoticePresenter.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func lockScreenControllerSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/LockScreenOverlayController.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
