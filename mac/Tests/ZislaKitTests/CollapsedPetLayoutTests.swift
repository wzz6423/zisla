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

    @Test(arguments: [IslandEdge.left, .right])
    func sidePillsReservePetSlotsAlongTheirHeight(edge: IslandEdge) {
        let layout = pillLayout(edge: edge)
        let bar = layout.collapsedFrame
        let container = CollapsedPetLayout.frame(for: layout)
        #expect(container.width == bar.width)
        #expect(container.height == bar.height + 64)
        #expect(container.midX == bar.midX)
        #expect(container.midY == bar.midY)
        #expect(container.minY == bar.minY - CollapsedPetLayout.sideSlotWidth)
        #expect(container.maxY == bar.maxY + CollapsedPetLayout.sideSlotWidth)
        #expect(CollapsedPetLayout.containerSize(for: bar.size, edge: edge) == container.size)
    }

    @Test(arguments: IslandEdge.allCases)
    func pillPetFramesStayInsideNegativeCoordinateScreensAtCorners(edge: IslandEdge) throws {
        for offset in [0.0, 0.5, 1.0] {
            let layout = pillLayout(edge: edge, offset: offset)
            let bar = layout.collapsedFrame
            let container = CollapsedPetLayout.frame(for: layout)
            #expect(layout.screenFrame.contains(container))
            #expect(container.contains(bar))
            for side in [PetSide.left, .right] {
                let pet = try #require(CollapsedPetLayout.petFrame(for: layout, side: side))
                #expect(layout.screenFrame.contains(pet))
                #expect(container.contains(pet))
                #expect(!pet.intersects(bar))
                #expect(pet.width == 24 && pet.height == 24)
            }
        }
    }

    @Test(arguments: IslandEdge.allCases)
    func petSideSelectsTheMatchingLongAxisEnd(edge: IslandEdge) throws {
        let layout = pillLayout(edge: edge)
        let left = try #require(CollapsedPetLayout.petFrame(for: layout, side: .left))
        let right = try #require(CollapsedPetLayout.petFrame(for: layout, side: .right))
        if edge.isVertical {
            #expect(left.minY > layout.collapsedFrame.maxY)
            #expect(right.maxY < layout.collapsedFrame.minY)
            #expect(left.midX == layout.collapsedFrame.midX)
            #expect(right.midX == layout.collapsedFrame.midX)
        } else {
            #expect(left.maxX < layout.collapsedFrame.minX)
            #expect(right.minX > layout.collapsedFrame.maxX)
        }
    }

    @Test(arguments: IslandEdge.allCases)
    func detailedStatusPetContainerFollowsTheActualBar(edge: IslandEdge) throws {
        let layout = pillLayout(edge: edge)
        let bar = SideNoticeLayoutEngine().compactBarFrame(for: layout, expandsForDetailedMedia: true)
        let container = CollapsedPetLayout.frame(for: layout, compactBarFrame: bar)
        if edge.isVertical {
            #expect(container.width == bar.width)
            #expect(container.height == bar.height + 64)
        } else {
            #expect(container.width == bar.width + 64)
            #expect(container.height == bar.height)
        }
        #expect(container.contains(bar))
        let pet = try #require(CollapsedPetLayout.petFrame(for: layout, compactBarFrame: bar, side: .right))
        #expect(container.contains(pet))
        #expect(!pet.intersects(bar))
    }

    @Test
    func crampedScreenOmitsPetsWhenNeitherEndHasSpace() {
        let screen = ScreenSnapshot(displayID: 1,
            frame: CGRect(x: -100, y: -80, width: 100, height: 80),
            visibleFrame: CGRect(x: -100, y: -80, width: 100, height: 56))
        for edge in IslandEdge.allCases {
            let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
                layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: edge)
            )).layout(for: screen)
            #expect(screen.frame.contains(CollapsedPetLayout.frame(for: layout)))
            #expect(CollapsedPetLayout.petFrame(for: layout, side: .left) == nil)
            #expect(CollapsedPetLayout.petFrame(for: layout, side: .right) == nil)
        }
    }

    @Test
    func zeroThicknessHasNoPetFrame() {
        let layout = pillLayout(edge: .left)
        var bar = layout.collapsedFrame
        bar.size.width = 0
        #expect(CollapsedPetLayout.petFrame(for: layout, compactBarFrame: bar, side: .left) == nil)
    }

    private func pillLayout(edge: IslandEdge, offset: Double = 0.5) -> ScreenOverlayLayout {
        let screen = ScreenSnapshot(displayID: 9,
            frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1056))
        return ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: edge, offset: offset)
        )).layout(for: screen)
    }
}
