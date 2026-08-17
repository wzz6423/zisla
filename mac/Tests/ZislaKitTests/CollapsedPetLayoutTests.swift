import CoreGraphics
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct CollapsedPetLayoutTests {
    @Test
    func containerAddsAStablePetSlotOnBothSides() {
        let size = CollapsedPetLayout.containerSize(for: CGSize(width: 240, height: 34))

        #expect(size == CGSize(width: 304, height: 34))
    }

    @Test
    func panelFrameKeepsTheCollapsedIslandCentered() {
        let screen = ScreenSnapshot(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )
        let layout = ScreenLayoutEngine().layout(for: screen)
        let frame = CollapsedPetLayout.frame(for: layout)

        #expect(frame.midX == layout.collapsedFrame.midX)
        #expect(frame.maxY == layout.collapsedFrame.maxY)
        #expect(frame.width == layout.collapsedFrame.width + 64)
    }

    @Test
    func emptyStatePlacesThePetSlotDirectlyBesideTheNotch() {
        let screen = ScreenSnapshot(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )
        let layout = ScreenLayoutEngine().layout(for: screen)
        let frame = CollapsedPetLayout.frame(for: layout)

        #expect(frame.minX == layout.collapsedFrame.minX - CollapsedPetLayout.sideSlotWidth)
        #expect(frame.maxX == layout.collapsedFrame.maxX + CollapsedPetLayout.sideSlotWidth)
    }

    @Test
    func detailedMediaFrameKeepsBothPetSlotsOutsideTheBar() {
        let screen = ScreenSnapshot(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950)
        )
        let layout = ScreenLayoutEngine().layout(for: screen)
        let barFrame = SideNoticeLayoutEngine().compactBarFrame(
            for: layout,
            expandsForDetailedMedia: true
        )
        let petFrame = CollapsedPetLayout.frame(for: layout, compactBarFrame: barFrame)

        #expect(barFrame.width == 380)
        #expect(petFrame.minX == barFrame.minX - CollapsedPetLayout.sideSlotWidth)
        #expect(petFrame.maxX == barFrame.maxX + CollapsedPetLayout.sideSlotWidth)
        #expect(petFrame.minY == barFrame.minY)
        #expect(petFrame.height == barFrame.height)
    }

    @Test
    func aiPriorityKeepsThePetBesideTheNarrowBarWhenDetailedMediaExists() {
        let screen = ScreenSnapshot(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )
        let layout = ScreenLayoutEngine().layout(for: screen)
        let notices = [
            IslandNotice(id: "media-active-left", title: "Music", side: .left),
            IslandNotice(id: "ai-active-codex", title: "Codex", side: .left),
        ]
        var settings = FeatureSettings()
        settings.mediaCompactStyle = .detailed
        settings.compactStatusPriority = CompactStatusPriority.normalized([.aiActivity, .media])
        let barFrame = SideNoticeLayoutEngine().compactBarFrame(
            for: layout,
            notices: notices,
            settings: settings
        )
        let expectedBarFrame = SideNoticeLayoutEngine().compactBarFrame(for: layout)
        #expect(barFrame == expectedBarFrame)

        let petFrame = CollapsedPetLayout.frame(for: layout, compactBarFrame: barFrame)
        #expect(petFrame == CollapsedPetLayout.frame(for: layout, compactBarFrame: expectedBarFrame))
    }
}
