import CoreGraphics
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct CollapsedPetLayoutTests {
    @Test(arguments: IslandEdge.allCases, [CGFloat(182) / 136, CGFloat(137) / 184, 1])
    func pillPetHeightMatchesThicknessAndWidthScalesProportionally(edge: IslandEdge, aspectRatio: CGFloat) throws {
        for thickness: CGFloat in [24, 32, 40] {
            let layout = pillLayout(edge: edge, pillSize: CGSize(width: 180, height: thickness))
            let bar = layout.collapsedFrame
            let container = CollapsedPetLayout.frame(for: layout, petAspectRatio: aspectRatio)
            for side in [PetSide.left, .right] {
                let pet = try #require(CollapsedPetLayout.petFrame(for: layout, petAspectRatio: aspectRatio, side: side))
                #expect(pet.size == CGSize(width: thickness * aspectRatio, height: thickness),
                        "The artwork height must equal the pill thickness and its width must preserve the source ratio")
                #expect(container.contains(pet), "The resized pet must fit inside its panel")
                if edge.isVertical {
                    #expect(abs(pet.midX - bar.midX) < 0.000001)
                    #expect(side == .left ? abs(pet.minY - bar.maxY - 4) < 0.001 : abs(bar.minY - pet.maxY - 4) < 0.001)
                } else {
                    #expect(pet.midY == bar.midY)
                    #expect(side == .left ? abs(bar.minX - pet.maxX - 4) < 0.001 : abs(pet.minX - bar.maxX - 4) < 0.001)
                }
            }
        }
    }

    @Test
    func containerAddsAStablePetSlotOnBothSides() {
        let size = CollapsedPetLayout.containerSize(for: CGSize(width: 240, height: 34))

        #expect(size == CGSize(width: 304, height: 34))
    }

    @Test
    func panelFrameKeepsTheCollapsedIslandCentered() throws {
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
        let pet = try #require(CollapsedPetLayout.petFrame(for: layout, side: .left))
        #expect(pet.size == CGSize(width: 24, height: 24), "Physical notches must preserve the existing pet size")
        #expect(pet.maxY == layout.collapsedFrame.maxY - 3.2,
                "Physical notches must preserve the existing top inset")
        #expect(CollapsedPetLayout.frame(for: layout, petAspectRatio: CGFloat(182) / 136) == frame)
        #expect(CollapsedPetLayout.petFrame(for: layout, petAspectRatio: CGFloat(182) / 136, side: .left) == pet)
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
        #expect(CollapsedPetLayout.containerSize(for: bar.size, edge: edge, style: .pill) == container.size)
    }

    @Test(arguments: IslandEdge.allCases, [
        (ScreenLayoutConfiguration().pillSize, CGFloat(24)),
        (CGSize(width: 180, height: 32), CGFloat(32)),
        (CGSize(width: 180, height: 40), CGFloat(40)),
    ])
    func pillPetFramesStayInsideNegativeCoordinateScreensAtCorners(
        edge: IslandEdge, sizing: (pillSize: CGSize, petSize: CGFloat)
    ) throws {
        for aspectRatio in [CGFloat(182) / 136, CGFloat(137) / 184, 1] {
            for offset in [0.0, 0.5, 1.0] {
                let layout = pillLayout(edge: edge, offset: offset, pillSize: sizing.pillSize)
                let bar = layout.collapsedFrame
                let container = CollapsedPetLayout.frame(for: layout, petAspectRatio: aspectRatio)
                #expect(layout.screenFrame.contains(container))
                #expect(container.contains(bar))
                for side in [PetSide.left, .right] {
                    let pet = try #require(CollapsedPetLayout.petFrame(for: layout, petAspectRatio: aspectRatio, side: side))
                    #expect(layout.screenFrame.contains(pet))
                    #expect(container.contains(pet))
                    #expect(!pet.intersects(bar))
                    #expect(pet.width == sizing.petSize * aspectRatio && pet.height == sizing.petSize)
                }
            }
        }
    }

    @Test(arguments: [IslandEdge.left, .right])
    func widePetStaysVisibleWhenThePillTouchesTheScreenEdge(edge: IslandEdge) throws {
        let screen = ScreenSnapshot(displayID: 9,
            frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1056))
        let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: edge),
            pillSize: CGSize(width: 180, height: 40), edgeInset: 0)).layout(for: screen)
        let ratio = CGFloat(182) / 136
        let container = CollapsedPetLayout.frame(for: layout, petAspectRatio: ratio)
        for side in [PetSide.left, .right] {
            let pet = try #require(CollapsedPetLayout.petFrame(for: layout, petAspectRatio: ratio, side: side))
            #expect(pet.size == CGSize(width: 40 * ratio, height: 40))
            #expect(screen.frame.contains(pet))
            #expect(container.contains(pet))
            #expect(edge == .left ? pet.minX == screen.frame.minX : pet.maxX == screen.frame.maxX)
            #expect(!pet.intersects(layout.collapsedFrame))
        }
    }

    @Test
    func enlargedPetChangesEndsWhenOnlyTheWiderArtworkDoesNotFit() throws {
        let layout = pillLayout(edge: .top, pillSize: CGSize(width: 180, height: 32))
        var bar = layout.collapsedFrame
        bar.origin.x = layout.screenFrame.minX + 40
        #expect(CollapsedPetLayout.petFrame(for: layout, compactBarFrame: bar, side: .left)?.maxX == bar.minX - 4)
        let ratio = CGFloat(182) / 136
        let pet = try #require(CollapsedPetLayout.petFrame(for: layout, compactBarFrame: bar,
            petAspectRatio: ratio, side: .left))
        #expect(abs(pet.minX - bar.maxX - 4) < 0.001)
        #expect(pet.size == CGSize(width: 32 * ratio, height: 32))
        #expect(CollapsedPetLayout.frame(for: layout, compactBarFrame: bar, petAspectRatio: ratio).contains(pet))
    }

    @Test
    func enlargedPetIsOmittedWhenOnlyTheSquareViewportWouldFit() {
        let layout = pillLayout(edge: .top, pillSize: CGSize(width: 180, height: 32))
        let bar = CGRect(x: layout.screenFrame.minX + 40, y: layout.collapsedFrame.minY,
                         width: layout.screenFrame.width - 80, height: 32)
        #expect(CollapsedPetLayout.petFrame(for: layout, compactBarFrame: bar, side: .left) != nil)
        for side in [PetSide.left, .right] {
            #expect(CollapsedPetLayout.petFrame(for: layout, compactBarFrame: bar,
                petAspectRatio: CGFloat(182) / 136, side: side) == nil)
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
            #expect(container.height == bar.height + (bar.width + 8) * 2)
        } else {
            #expect(container.width == bar.width + (bar.height + 8) * 2)
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
            frame: CGRect(x: -100, y: -80, width: 64, height: 64),
            visibleFrame: CGRect(x: -100, y: -80, width: 64, height: 40))
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
        #expect(CollapsedPetLayout.petFrame(for: layout, compactBarFrame: bar,
            petAspectRatio: CGFloat(182) / 136, side: .left) == nil)
    }

    @Test
    func zeroWidthArtworkHasNoPetFrame() {
        let layout = pillLayout(edge: .top)
        #expect(CollapsedPetLayout.petFrame(for: layout, petAspectRatio: 0, side: .left) == nil)
    }

    private func pillLayout(
        edge: IslandEdge, offset: Double = 0.5,
        pillSize: CGSize = ScreenLayoutConfiguration().pillSize
    ) -> ScreenOverlayLayout {
        let screen = ScreenSnapshot(displayID: 9,
            frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1056))
        return ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: edge, offset: offset),
            pillSize: pillSize
        )).layout(for: screen)
    }
}
