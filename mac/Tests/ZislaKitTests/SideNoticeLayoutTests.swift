import CoreGraphics
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct SideNoticeLayoutTests {
    @Test
    func alwaysVisibleActivityAndFocusCannotBeDismissed() {
        let activity = IslandNotice(id: "ai-active-codex", title: "运行中", side: .left)
        let focus = IslandNotice(id: "focus-mode-left", title: "专注", side: .left)

        #expect(CompactStatusVisibilityPolicy.mustRemainVisible(
            notices: [activity],
            activityDuration: .always,
            focusDuration: .threeSeconds
        ))
        #expect(CompactStatusVisibilityPolicy.mustRemainVisible(
            notices: [focus],
            activityDuration: .threeSeconds,
            focusDuration: .always
        ))
        #expect(!CompactStatusVisibilityPolicy.mustRemainVisible(
            notices: [activity, focus],
            activityDuration: .threeSeconds,
            focusDuration: .threeSeconds
        ))
    }

    private let engine = SideNoticeLayoutEngine()

    @Test
    func activeAINoticesCollapseIntoOneCompactWing() {
        let notices = [
            IslandNotice(id: "ai-active-codex-1", title: "Codex", side: .left),
            IslandNotice(id: "ai-active-codex-2", title: "Codex", side: .left),
            IslandNotice(id: "ai-active-claude", title: "Claude", side: .left),
        ]

        let presentation = engine.presentation(for: notices)

        #expect(presentation.activeAICount == 3)
        #expect(presentation.ordinaryNotices.isEmpty)
        #expect(presentation.panelSize == CGSize(width: 40, height: 34))
    }

    @Test
    func toolboxReminderUsesACompactWingWithoutOccupyingNoticeCapacity() {
        let reminder = IslandNotice(
            id: "toolbox-reminder-left",
            title: "专注 24:59",
            detail: "24:59",
            side: .left
        )

        let presentation = engine.presentation(for: [reminder])

        #expect(presentation.activeToolboxNotice == reminder)
        #expect(presentation.ordinaryNotices.isEmpty)
        #expect(presentation.panelSize == CGSize(width: 40, height: 34))
    }

    @Test
    func browserDownloadUsesCompactWingWithoutOccupyingNoticeCapacity() {
        let download = IslandNotice(
            id: "browser-download-left",
            title: "report.pdf",
            detail: "72%",
            side: .left,
            appBundleIdentifier: "com.google.Chrome"
        )

        let presentation = engine.presentation(for: [download])

        #expect(presentation.activeBrowserDownloadNotice == download)
        #expect(presentation.ordinaryNotices.isEmpty)
        #expect(presentation.hasCompactContent)
        #expect(presentation.panelSize == CGSize(width: 40, height: 34))
    }

    /// Compact state uses CompactStatusBarView only; with wings disabled it must not fall back to ordinary notice rows.
    @Test
    func browserDownloadIsNeverTreatedAsOrdinaryNotice() {
        let download = IslandNotice(
            id: "browser-download-right",
            title: "report.pdf",
            detail: "72%",
            side: .right
        )

        let presentation = engine.presentation(for: [download], compactWingsEnabled: false)

        #expect(presentation.activeBrowserDownloadNotice == nil)
        #expect(presentation.ordinaryNotices.isEmpty)
        #expect(presentation.panelSize == .zero)
    }

    @Test
    func videoDownloadUsesCompactWingWithoutOccupyingNoticeCapacity() {
        let download = IslandNotice(
            id: "video-download-left",
            title: "YouTube",
            detail: "72%",
            side: .left,
            appBundleIdentifier: "youtube"
        )

        let presentation = engine.presentation(for: [download])

        #expect(presentation.activeVideoDownloadNotice == download)
        #expect(presentation.ordinaryNotices.isEmpty)
        #expect(presentation.hasCompactContent)
        #expect(presentation.panelSize == CGSize(width: 40, height: 34))
    }

    /// Compact state uses CompactStatusBarView only; with wings disabled it must not fall back to ordinary notice rows.
    @Test
    func videoDownloadIsNeverTreatedAsOrdinaryNotice() {
        let download = IslandNotice(
            id: "video-download-right",
            title: "YouTube",
            detail: "72%",
            side: .right
        )

        let presentation = engine.presentation(for: [download], compactWingsEnabled: false)

        #expect(presentation.activeVideoDownloadNotice == nil)
        #expect(presentation.ordinaryNotices.isEmpty)
        #expect(presentation.panelSize == .zero)
    }

    /// Both download notice kinds can coexist in the queue; each presentation field must resolve.
    @Test
    func videoAndBrowserDownloadNoticesCoexistInPresentation() {
        let video = IslandNotice(id: "video-download-left", title: "YouTube", detail: "40%", side: .left)
        let browser = IslandNotice(id: "browser-download-left", title: "a.pdf", detail: "80%", side: .left)

        let presentation = engine.presentation(for: [video, browser])

        #expect(presentation.activeVideoDownloadNotice == video)
        #expect(presentation.activeBrowserDownloadNotice == browser)
        #expect(presentation.ordinaryNotices.isEmpty)
    }

    @Test
    func focusModeUsesCompactStatusWithoutOccupyingNoticeCapacity() {
        let focusMode = IslandNotice(
            id: "focus-mode-left",
            title: "工作",
            side: .left,
            style: .status,
            symbolName: "briefcase.fill"
        )

        let presentation = engine.presentation(for: [focusMode])

        #expect(presentation.activeFocusModeNotice == focusMode)
        #expect(presentation.ordinaryNotices.isEmpty)
        #expect(presentation.panelSize == CGSize(width: 40, height: 34))
    }

    @Test
    func mailNotificationUsesCompactStatusWithoutFallingBackToPopup() {
        let mail = IslandNotice(
            id: "mail-notification-batch-left",
            title: "季度计划",
            detail: "Alice",
            side: .left,
            style: .status,
            symbolName: "envelope.fill"
        )

        let presentation = engine.presentation(for: [mail])
        let disabledPresentation = engine.presentation(for: [mail], compactWingsEnabled: false)

        #expect(presentation.activeMailNotice == mail)
        #expect(presentation.ordinaryNotices.isEmpty)
        #expect(presentation.hasCompactContent)
        #expect(presentation.panelSize == CGSize(width: 40, height: 34))
        #expect(disabledPresentation.activeMailNotice == nil)
        #expect(disabledPresentation.ordinaryNotices.isEmpty)
        #expect(disabledPresentation.panelSize == .zero)
    }

    @Test
    func updateAvailabilityUsesTheCompactBarWithoutOccupyingOrdinaryCapacity() {
        let update = IslandNotice(
            id: "update-available-cli-claude-left",
            title: "Claude",
            side: .left,
            style: .status,
            symbolName: "sparkles"
        )

        let presentation = engine.presentation(for: [update])

        #expect(presentation.activeUpdateNotice == update)
        #expect(presentation.ordinaryNotices.isEmpty)
        #expect(presentation.hasCompactContent)
        #expect(presentation.panelSize == CGSize(width: 40, height: 34))
    }

    @Test
    func transientFocusAndHeadphoneNoticesDoNotRenderAsOrdinaryRows() {
        let focusTransition = IslandNotice(
            id: "focus-transition",
            title: "工作",
            side: .left,
            style: .status
        )
        let headphone = IslandNotice(
            id: "headphone-connection-test",
            title: "AirPods",
            side: .right,
            style: .headphone
        )

        let presentation = engine.presentation(for: [focusTransition, headphone])

        #expect(presentation.ordinaryNotices.isEmpty)
    }

    @Test
    func focusCountdownUsesCompactContentAlongsideMediaAndAI() {
        let media = IslandNotice(id: "media-active-left", title: "正在播放", side: .left)
        let countdown = IslandNotice(
            id: "focus-countdown-left",
            title: "专注倒计时",
            detail: "00:29:28",
            side: .left
        )
        let ai = IslandNotice(id: "ai-active-codex", title: "Codex", side: .left)

        let presentation = engine.presentation(for: [media, countdown, ai])

        #expect(presentation.activeMediaNotice == media)
        #expect(presentation.activeFocusCountdownNotice == countdown)
        #expect(presentation.activeAICount == 1)
        #expect(presentation.ordinaryNotices.isEmpty)
        #expect(presentation.panelSize == CGSize(width: 40, height: 34))
        #expect(!presentation.shouldExtendCompactBarForFocusCountdown)
    }

    @Test
    func mixedNoticesReserveOneAIWingWithoutOverlappingOrdinaryRows() {
        let ordinary = [
            IslandNotice(id: "download", title: "下载完成", side: .left),
            IslandNotice(id: "share", title: "已分享", side: .left),
        ]
        let notices = [
            IslandNotice(id: "ai-active-codex", title: "Codex", side: .left),
            ordinary[0],
            IslandNotice(id: "ai-active-claude", title: "Claude", side: .left),
            ordinary[1],
        ]

        let presentation = engine.presentation(for: notices)

        #expect(presentation.activeAICount == 2)
        #expect(presentation.ordinaryNotices == ordinary)
        #expect(presentation.panelSize == CGSize(width: 252, height: 154))
    }

    @Test
    func physicalNotchUsesOneContinuousFullNavigationBar() {
        let screen = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )
        let frame = engine.compactBarFrame(for: screen, extendsForFocusCountdown: true)
        let anchor = ScreenLayoutEngine().layout(for: screen).topology.anchorFrame

        #expect(frame == CGRect(x: 636, y: anchor.minY, width: 240, height: anchor.height))
        #expect(frame.maxY == screen.frame.maxY)
        #expect(frame.minY == screen.frame.maxY - frame.height)
        #expect(frame.height == ScreenLayoutEngine().layout(for: screen).topology.anchorFrame.height)
    }

    @Test
    func compactBarFlushesAnUnreservedFullscreenTopEdge() {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            menuBarHeightFallback: 24
        )

        #expect(engine.compactBarFrame(for: screen) == CGRect(x: 600, y: 876, width: 240, height: 24))
        #expect(engine.compactBarFrame(for: screen).maxY == screen.frame.maxY)
    }

    @Test
    func physicalNotchCompactBarUsesTheFullNavigationBar() {
        let screen = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 946),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )

        let frame = engine.compactBarFrame(for: screen, extendsForFocusCountdown: true)
        let anchor = ScreenLayoutEngine().layout(for: screen).topology.anchorFrame
        let expectedHeight = max(anchor.height, screen.topBarHeight - 1)

        #expect(
            frame == CGRect(
                x: 636,
                y: screen.frame.maxY - expectedHeight,
                width: 240,
                height: expectedHeight
            )
        )
        #expect(frame.maxY == screen.frame.maxY)
        #expect(frame.height >= anchor.height)
        #expect(engine.compactWingHeight(for: screen) == frame.height)
    }

    @Test
    func compactBarContourMatchesPhysicalNotchDirection() {
        let contour = CompactBarContourMetrics(size: CGSize(width: 176, height: 32))

        #expect(contour.topInset == 14)
        #expect(contour.bottomInset == 0)
        #expect(contour.topWidth == 148)
        #expect(contour.bottomWidth == 176)
        #expect(contour.topWidth < contour.bottomWidth)
    }

    @Test
    func screenWithoutNotchHidesCompactWings() {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )
        let presentation = engine.presentation(
            for: [
            IslandNotice(id: "ai-active-codex", title: "Codex", side: .left)
            ],
            compactWingsEnabled: false
        )

        #expect(presentation.panelSize == .zero)
        #expect(engine.frame(side: .left, presentation: presentation, screen: screen) == .zero)
        #expect(engine.frame(side: .right, presentation: presentation, screen: screen) == .zero)
    }

    @Test
    func mediaNoticeUsesCompactWingAndIsHiddenWithoutPhysicalNotch() {
        let physical = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )
        let media = IslandNotice(
            id: "media-active-left",
            title: "QQ音乐",
            detail: "Track",
            side: .left
        )
        let physicalPresentation = engine.presentation(for: [media])
        #expect(physicalPresentation.activeMediaNotice == media)
        #expect(physicalPresentation.panelSize == CGSize(width: 40, height: 34))
        let anchor = ScreenLayoutEngine().layout(for: physical).topology.anchorFrame
        #expect(engine.compactWingHeight(for: physical) == anchor.height)
        #expect(
            engine.compactBarFrame(for: physical)
                == CGRect(x: 676, y: anchor.minY, width: 160, height: anchor.height)
        )

        let external = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )
        let externalPresentation = engine.presentation(
            for: [media],
            compactWingsEnabled: engine.supportsCompactWings(for: external),
            compactWingHeight: engine.compactWingHeight(for: external)
        )
        #expect(externalPresentation.panelSize == .zero)
        #expect(
            engine.compactBarFrame(for: external)
                == CGRect(x: 600, y: 875, width: 240, height: 25)
        )
    }

    @Test
    func focusCountdownIsTheOnlyCompactStatusThatExtendsTheBar() {
        let screen = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )

        let countdown = IslandNotice(
            id: "focus-countdown-left",
            title: "专注倒计时",
            detail: "01:00:00",
            side: .left
        )
        let ai = IslandNotice(id: "ai-active-codex", title: "Codex", side: .left)
        let countdownPresentation = engine.presentation(for: [countdown, ai])
        let aiPresentation = engine.presentation(for: [ai])

        #expect(countdownPresentation.shouldExtendCompactBarForFocusCountdown)
        #expect(!aiPresentation.shouldExtendCompactBarForFocusCountdown)
        #expect(engine.compactBarFrame(for: screen).width == 160)
        #expect(
            engine.compactBarFrame(
                for: screen,
                extendsForFocusCountdown: countdownPresentation.shouldExtendCompactBarForFocusCountdown
            ).width == 240
        )
    }

    @Test
    func voiceProcessingKeepsTheCompactBarShortAndMovesThePetBesideIt() throws {
        let screen = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )
        let layout = ScreenLayoutEngine().layout(for: screen)
        let notices = [
            IslandNotice(
                id: "voice-processing-left",
                title: "正在整理语音",
                side: .left,
                style: .status
            )
        ]
        let settings = FeatureSettings()

        let barFrame = try #require(
            engine.compactBarFrame(for: screen, notices: notices, settings: settings)
        )
        let petAnchorFrame = try #require(
            engine.compactBarFrame(for: layout, notices: notices, settings: settings)
        )
        let petFrame = CollapsedPetLayout.frame(for: layout, compactBarFrame: petAnchorFrame)

        #expect(barFrame == petAnchorFrame)
        #expect(barFrame == engine.compactBarFrame(for: screen))
        #expect(barFrame.width == 160)
        #expect(petFrame.minX == barFrame.minX - CollapsedPetLayout.sideSlotWidth)
    }

    @Test
    func detailedMediaStyleWidensTheCompactBarOnBothTopologies() {
        let notched = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )
        let simulated = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            menuBarHeightFallback: 24
        )
        let notchWidth = ScreenLayoutEngine().layout(for: notched).topology.anchorFrame.width

        let notchedDetailed = engine.compactBarFrame(for: notched, expandsForDetailedMedia: true)
        #expect(notchedDetailed.width == notchWidth + 320)
        #expect(notchedDetailed.maxY == notched.frame.maxY)
        // When detailed and countdown-extended states conflict, detailed wins so extensions do not stack.
        #expect(
            engine.compactBarFrame(
                for: notched,
                extendsForFocusCountdown: true,
                expandsForDetailedMedia: true
            ).width == notchedDetailed.width
        )

        let simulatedDetailed = engine.compactBarFrame(for: simulated, expandsForDetailedMedia: true)
        #expect(simulatedDetailed.width == 380)
        #expect(simulatedDetailed.minX == 530)
        #expect(simulatedDetailed.maxX == 910)
        #expect(simulatedDetailed.midX == simulated.frame.midX)
        #expect(simulatedDetailed.maxY == simulated.frame.maxY)
        #expect(
            engine.compactBarFrame(
                for: ScreenLayoutEngine().layout(for: simulated),
                expandsForDetailedMedia: true
            ).width == 380
        )
        // Compact state keeps the original narrow bar; new parameters must not affect it.
        #expect(engine.compactBarFrame(for: simulated).width == 240)
    }

    @Test
    func detailedMediaOnlyExpandsWhenItIsTheVisibleCompactStatus() {
        let media = IslandNotice(id: "media-active-left", title: "QQ音乐", side: .left)
        let ai = IslandNotice(id: "ai-active-codex", title: "Codex", side: .left)

        #expect(engine.presentation(for: [media]).displaysMediaInCompactBar)
        #expect(!engine.presentation(for: [media, ai]).displaysMediaInCompactBar)
    }

    @Test
    func backgroundSoundUsesTheDefaultCompactBarInDetailedMediaMode() throws {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            menuBarHeightFallback: 24
        )
        let backgroundSound = IslandNotice(
            id: "background-sound-left",
            title: "棕色噪声",
            side: .left
        )
        var settings = FeatureSettings()
        settings.mediaCompactStyle = .detailed

        let frame = try #require(
            engine.compactBarFrame(
                for: screen,
                notices: [backgroundSound],
                settings: settings
            )
        )

        #expect(frame == engine.compactBarFrame(for: screen))
    }

    @Test
    func musicStillUsesTheDetailedCompactBarWhenDetailedModeIsSelected() throws {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            menuBarHeightFallback: 24
        )
        let media = IslandNotice(id: "media-active-left", title: "QQ音乐", side: .left)
        var settings = FeatureSettings()
        settings.mediaCompactStyle = .detailed

        let frame = try #require(
            engine.compactBarFrame(for: screen, notices: [media], settings: settings)
        )

        #expect(frame.width == 380)
    }

    @Test
    func oppositeSideReservesAnIdenticalCompactWing() {
        let screen = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )
        let compactHeight = engine.compactWingHeight(for: screen)
        let right = engine.presentation(
            for: [IslandNotice(id: "ai-active-codex", title: "Codex", side: .right)],
            compactWingHeight: compactHeight
        )
        let left = engine.presentation(
            for: [],
            compactWingHeight: compactHeight,
            reserveCompactWing: true
        )

        #expect(right.panelSize == CGSize(width: 40, height: compactHeight))
        #expect(left.compactPlaceholder)
        #expect(left.panelSize == right.panelSize)
        let anchor = ScreenLayoutEngine().layout(for: screen).topology.anchorFrame
        let leftFrame = engine.frame(side: .left, presentation: left, screen: screen)
        let rightFrame = engine.frame(side: .right, presentation: right, screen: screen)
        #expect(leftFrame.width == rightFrame.width)
        #expect(leftFrame.minY == rightFrame.minY)
        #expect(leftFrame.maxX == anchor.minX)
        #expect(anchor.maxX == rightFrame.minX)
    }

    @Test
    func ordinaryNoticesAppearAboveTheIsland() {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )
        let presentation = engine.presentation(for: [
            IslandNotice(id: "download", title: "下载完成", side: .right)
        ])
        let anchor = ScreenLayoutEngine().layout(for: screen).topology.anchorFrame

        #expect(presentation.panelSize == CGSize(width: 252, height: 54))
        let frame = engine.frame(side: .right, presentation: presentation, screen: screen)
        // The overlay sits directly above the island's bottom edge.
        #expect(frame == CGRect(x: 840, y: anchor.minY - 54 - 4, width: 252, height: 54))
        #expect(frame.maxY == anchor.minY - 4)
    }
}
