import CoreGraphics
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct SideNoticeLayoutTests {
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
    func ordinaryNoticesStayBelowTheMenuBar() {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )
        let presentation = engine.presentation(for: [
            IslandNotice(id: "download", title: "下载完成", side: .right)
        ])

        #expect(presentation.panelSize == CGSize(width: 252, height: 54))
        #expect(
            engine.frame(side: .right, presentation: presentation, screen: screen)
                == CGRect(x: 840, y: 817, width: 252, height: 54)
        )
    }
}
