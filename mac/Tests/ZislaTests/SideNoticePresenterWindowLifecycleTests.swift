import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct SideNoticePresenterWindowLifecycleTests {
    @Test @MainActor
    func resultSweepPreservesExternalHeadphoneContentClearance() throws {
        let screen = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: 1_512, y: -120, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 1_512, y: -120, width: 1_440, height: 900),
            menuBarHeightFallback: 24)
        let layout = SideNoticeLayoutEngine()
        let notice = IslandNotice(id: "headphone-connection", title: "AirPods Pro", side: .left, style: .headphone)
        let idle = layout.compactBarFrame(for: screen)
        let frame = try #require(layout.compactBarFrame(for: screen, notices: [notice], settings: FeatureSettings()))
        for isSweeping in [false, true] {
            let presented = try #require(SideNoticePresenter.resultSweepFrame(statusFrame: frame,
                idleFrame: idle, hasPhysicalNotch: false, isSweeping: isSweeping))
            #expect(presented == frame)
            #expect(presented.height == 36)
            #expect(presented.maxY == screen.frame.maxY)
        }
        #expect(idle.height == 24)
    }

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

}
