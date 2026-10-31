import CoreGraphics
import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct IslandPlacementLayoutTests {
    private let screen = ScreenSnapshot(
        displayID: 42,
        frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1056)
    )

    @Test(arguments: IslandEdge.allCases)
    func eachEdgeKeepsThePillInsideAndExpandsInward(edge: IslandEdge) {
        let engine = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            expandedSize: CGSize(width: 480, height: 680),
            layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: edge, offset: 0.25)
        ))
        let layout = engine.layout(for: screen)
        let pill = layout.collapsedFrame
        let expanded = layout.expandedFrame
        #expect(layout.style == .pill)
        #expect(layout.edge == edge)
        #expect(screen.frame.insetBy(dx: 8, dy: 8).contains(expanded))
        #expect(expanded.contains(pill))
        #expect(pill.size == CGSize(width: 24, height: 24))
        #expect(expanded.size == CGSize(width: 480, height: 680))
        switch edge {
        case .top:
            #expect(pill.maxY == screen.frame.maxY - 8)
            #expect(expanded.maxY == pill.maxY)
            #expect(pill.midX == screen.frame.minX + screen.frame.width * 0.25)
        case .bottom:
            #expect(pill.minY == screen.frame.minY + 8)
            #expect(expanded.minY == pill.minY)
            #expect(pill.midX == screen.frame.minX + screen.frame.width * 0.25)
        case .left:
            #expect(pill.minX == screen.frame.minX + 8)
            #expect(expanded.minX == pill.minX)
            #expect(pill.midY == screen.frame.minY + screen.frame.height * 0.25)
        case .right:
            #expect(pill.maxX == screen.frame.maxX - 8)
            #expect(expanded.maxX == pill.maxX)
            #expect(pill.midY == screen.frame.minY + screen.frame.height * 0.25)
        }
        #expect(layout.triggerFrame == pill)
        #expect(layout.containsTrigger(CGPoint(x: pill.midX, y: pill.midY)))
        #expect(!layout.containsTrigger(CGPoint(x: screen.frame.midX, y: screen.frame.midY)))
        #expect(layout.transferDragTriggerFrame.contains(pill))
    }

    @Test(arguments: IslandEdge.allCases)
    func cornerAnchorsMatchBothLocalCoordinateSystems(edge: IslandEdge) {
        for offset: Double in [0, 1] {
            let engine = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
                expandedSize: CGSize(width: 480, height: 680),
                layoutStyle: .pill,
                placement: IslandPlacement(mode: .custom, edge: edge, offset: offset)
            ))
            let layout = engine.layout(for: screen)
            #expect(layout.collapsedFrame.size == CGSize(width: 24, height: 24))
            let local = layout.collapsedFrameInExpanded
            let flipped = layout.collapsedFrameInExpandedTopLeading
            #expect(local.offsetBy(dx: layout.expandedFrame.minX, dy: layout.expandedFrame.minY) == layout.collapsedFrame)
            #expect(flipped.minX == local.minX)
            #expect(flipped.minY == layout.expandedFrame.height - local.maxY)
            #expect(CGRect(origin: .zero, size: layout.expandedFrame.size).contains(local))
            #expect(CGRect(origin: .zero, size: layout.expandedFrame.size).contains(flipped))
        }
    }

    @Test(arguments: [IslandEdge.left, .right], [Double(0.25), 0.75])
    func sideExpansionKeepsTheNearestVerticalEndFixedAcrossModuleSizes(edge: IslandEdge, offset: Double) {
        var configuration = ScreenLayoutConfiguration(
            expandedSize: CGSize(width: 480, height: 180),
            layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: edge, offset: offset)
        )
        let initial = ScreenLayoutEngine(configuration: configuration).layout(for: screen)
        for height: CGFloat in [180, 340, 680, 340] {
            configuration.expandedSize.height = height
            let layout = ScreenLayoutEngine(configuration: configuration).layout(for: screen)
            let pill = layout.collapsedFrame
            #expect(pill == initial.collapsedFrame)
            #expect(layout.expandedFrame.height == height)
            #expect(layout.placementBounds.contains(layout.expandedFrame))
            #expect(layout.expandedFrame.contains(pill))
            #expect(layout.transferDragTriggerFrame == initial.transferDragTriggerFrame)
            if offset > 0.5 {
                #expect(layout.expandedFrame.maxY == pill.maxY,
                        "An upper-side island must expand down from its fixed top")
                #expect(layout.collapsedFrameInExpandedTopLeading.minY == 0)
            } else {
                #expect(layout.expandedFrame.minY == pill.minY,
                        "A lower-side island must expand up from its fixed bottom")
                #expect(layout.collapsedFrameInExpanded.minY == 0)
            }
        }
    }

    @Test(arguments: [IslandEdge.left, .right])
    func sideExpansionLimitsHeightWithoutMovingTheFixedEndOnEachScreen(edge: IslandEdge) {
        let other = ScreenSnapshot(displayID: 8,
            frame: CGRect(x: 100, y: 880, width: 1440, height: 900),
            visibleFrame: CGRect(x: 100, y: 880, width: 1440, height: 876))
        for snapshot in [screen, other] {
            for offset in [0.0, 0.25, 0.499, 0.5, 0.501, 0.75, 1.0] {
                let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
                    expandedSize: CGSize(width: 480, height: 10_000),
                    layoutStyle: .pill,
                    placement: IslandPlacement(mode: .custom, edge: edge, offset: offset)
                )).layout(for: snapshot)
                let pill = layout.collapsedFrame
                let bounds = layout.placementBounds
                #expect(bounds.contains(layout.expandedFrame))
                #expect(layout.expandedFrame.contains(pill))
                if offset >= 0.5 {
                    #expect(layout.expandedFrame.maxY == pill.maxY)
                    #expect(layout.expandedFrame.minY == bounds.minY)
                } else {
                    #expect(layout.expandedFrame.minY == pill.minY)
                    #expect(layout.expandedFrame.maxY == bounds.maxY)
                }
            }
        }
    }

    @Test(arguments: [IslandEdge.left, .right], [Double(0.25), 0.75])
    func sideDragTriggerRetainsItsCenteredReach(edge: IslandEdge, offset: Double) {
        let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: edge, offset: offset)
        )).layout(for: screen)
        #expect(layout.transferDragTriggerFrame.midY == layout.collapsedFrame.midY)
        #expect(layout.transferDragTriggerFrame.height == 320)
        #expect(layout.transferDragTriggerFrame.contains(layout.collapsedFrame))
    }

    @Test
    func nearestEdgeUsesScreenCoordinatesAndStableTies() {
        let engine = ScreenLayoutEngine()
        let expectations: [(CGPoint, IslandEdge, Double)] = [
            (CGPoint(x: -1800, y: 870), .top, 0.0625),
            (CGPoint(x: -1800, y: -195), .bottom, 0.0625),
            (CGPoint(x: -1900, y: 340), .left, 0.5),
            (CGPoint(x: -10, y: 340), .right, 0.5),
        ]
        for (point, edge, offset) in expectations {
            let placement = engine.placement(nearest: point, on: screen)
            #expect(placement.mode == .custom)
            #expect(placement.edge == edge)
            #expect(placement.offset == offset)
        }
        let center = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        #expect(engine.placement(nearest: center, on: screen).edge == .top)
        #expect(engine.placement(nearest: center, on: screen, preferredEdge: .bottom).edge == .bottom)
        let outside = engine.placement(nearest: CGPoint(x: 200, y: 1000), on: screen, preferredEdge: .right)
        #expect(outside.edge == .right)
        #expect(outside.offset == 1)
    }

    @Test
    func zeroAreaPlacementKeepsAFiniteCenterOffset() {
        let snapshot = ScreenSnapshot(displayID: 1,
            frame: CGRect(x: -90, y: 20, width: 0, height: 0),
            visibleFrame: CGRect(x: -90, y: 20, width: 0, height: 0))
        let engine = ScreenLayoutEngine()
        for edge in IslandEdge.allCases {
            let placement = engine.placement(nearest: CGPoint(x: -90, y: 20), on: snapshot, preferredEdge: edge)
            #expect(placement.edge == edge)
            #expect(placement.offset == 0.5)
        }
    }

    @Test
    func normalizedOffsetsFollowEachDisplayAfterResizingAndReordering() {
        let other = ScreenSnapshot(displayID: 8,
            frame: CGRect(x: 0, y: 0, width: 1280, height: 720),
            visibleFrame: CGRect(x: 0, y: 0, width: 1280, height: 696))
        let engine = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: .left, offset: 0.75)
        ))
        for screens in [[screen, other], [other, screen]] {
            let layouts = engine.layouts(for: screens)
            for (snapshot, layout) in zip(screens, layouts) {
                #expect(layout.displayID == snapshot.displayID)
                #expect(layout.collapsedFrame.midY == snapshot.frame.minY + snapshot.frame.height * 0.75)
                #expect(layout.collapsedFrame.minX == snapshot.frame.minX + 8)
            }
        }
    }

    @Test
    func configuredDimensionsAndInvalidValuesCannotEscapeTheScreen() {
        let small = ScreenSnapshot(displayID: 1,
            frame: CGRect(x: 10, y: 20, width: 100, height: 80),
            visibleFrame: CGRect(x: 10, y: 20, width: 100, height: 60))
        for size in [CGSize(width: 240, height: 48), CGSize(width: CGFloat.nan, height: CGFloat.infinity)] {
            for edge in IslandEdge.allCases {
                let engine = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
                    expandedSize: CGSize(width: 1000, height: 1000),
                    layoutStyle: .pill,
                    placement: IslandPlacement(mode: .custom, edge: edge, offset: 1),
                    pillSize: size,
                    edgeInset: .nan
                ))
                let layout = engine.layout(for: small)
                #expect(small.frame.contains(layout.collapsedFrame))
                #expect(small.frame.contains(layout.expandedFrame))
                #expect(layout.expandedFrame.contains(layout.collapsedFrame))
                #expect(layout.expandedFrame.width.isFinite)
                #expect(layout.expandedFrame.height.isFinite)
            }
        }
    }

    @Test
    func softwareDimensionsAreIndependentOfMenuBarDepth() {
        let engine = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: .right),
            pillSize: CGSize(width: 220, height: 44),
            edgeInset: 16
        ))
        let layout = engine.layout(for: screen)
        #expect(layout.collapsedFrame.size == CGSize(width: 44, height: 44))
        #expect(layout.collapsedFrame.maxX == screen.frame.maxX - 16)
        #expect(layout.centerOcclusionWidth == 0)
    }

    @Test(arguments: [CGFloat(34), CGFloat(44)])
    func cameraModeCentersWithinTheMenuBarAndIgnoresCustomOffsets(menuBarHeight: CGFloat) {
        var snapshot = screen
        snapshot.visibleFrame.size.height = snapshot.frame.height - menuBarHeight
        let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            layoutStyle: .pill,
            placement: IslandPlacement(mode: .camera, edge: .right, offset: 0.1),
            pillSize: CGSize(width: 180, height: 64),
            edgeInset: 48
        )).layout(for: snapshot)

        #expect(layout.style == .pill)
        #expect(layout.edge == .top)
        #expect(layout.collapsedFrame.midX == snapshot.frame.midX)
        #expect(layout.collapsedFrame.midY == snapshot.frame.maxY - menuBarHeight / 2)
        #expect(layout.collapsedFrame.height == min(32, menuBarHeight - 4))
        #expect(layout.collapsedFrame.maxY <= snapshot.frame.maxY - 2)
        #expect(layout.collapsedFrame.minY >= snapshot.visibleFrame.maxY + 2)
        #expect(layout.expandedFrame.maxY == layout.collapsedFrame.maxY)
        #expect(layout.expandedFrame.contains(layout.collapsedFrame))
        #expect(layout.centerOcclusionWidth == 0)
    }

    @Test
    func cameraIdlePillDoesNotInflateToTheReservedScreenRegion() {
        let snapshot = ScreenSnapshot(displayID: 4,
            frame: CGRect(x: -1512, y: 200, width: 1512, height: 982),
            visibleFrame: CGRect(x: -1512, y: 200, width: 1512, height: 938),
            safeAreaInsets: ScreenInsets(top: 44),
            auxiliaryTopLeftArea: CGRect(x: -1512, y: 1138, width: 656, height: 44),
            auxiliaryTopRightArea: CGRect(x: -656, y: 1138, width: 656, height: 44))
        let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            layoutStyle: .pill,
            pillSize: CGSize(width: 180, height: 32)
        )).layout(for: snapshot)
        #expect(layout.collapsedFrame.midX == -756)
        #expect(layout.collapsedFrame.midY == 1160)
        #expect(layout.collapsedFrame.width == 180)
        #expect(layout.centerOcclusionWidth == 180)
        #expect(layout.physicalOcclusionFrame == CGRect(x: -856, y: 1138, width: 200, height: 44))
        #expect(!layout.topology.hasPhysicalNotch, "A software pill retains its capsule style even around a reserved camera region")
    }

    @Test(arguments: [CGFloat(16), CGFloat(200)])
    func cameraContentReservesVisibleWingsOnlyWhilePresent(reservedWidth: CGFloat) throws {
        let halfScreen: CGFloat = 756
        let snapshot = ScreenSnapshot(displayID: 4,
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 938),
            safeAreaInsets: ScreenInsets(top: 44),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 938, width: halfScreen - reservedWidth / 2, height: 44),
            auxiliaryTopRightArea: CGRect(x: halfScreen + reservedWidth / 2, y: 938,
                                         width: halfScreen - reservedWidth / 2, height: 44))
        let settings = FeatureSettings(islandLayoutStyle: .pill)
        let engine = SideNoticeLayoutEngine()
        let configuration = settings.islandScreenConfiguration
        let idle = ScreenLayoutEngine(configuration: configuration).layout(for: snapshot)
        #expect(idle.collapsedFrame.width == configuration.pillSize.width)
        #expect(engine.compactBarFrame(for: snapshot, notices: [], settings: settings) == nil)
        for notice in [IslandNotice(id: "media-active-test", title: "Music"),
                       IslandNotice(id: "ai-active-test", title: "Codex")] {
            let sizing = try #require(engine.compactBarSizing(for: [notice], settings: settings))
            var activeConfiguration = configuration
            activeConfiguration.compactStatusLength = sizing.customPillLength
            let active = ScreenLayoutEngine(configuration: activeConfiguration).layout(for: snapshot)
            #expect(active.collapsedFrame.width == max(configuration.pillSize.width, reservedWidth + 80))
            #expect((active.collapsedFrame.width - active.centerOcclusionWidth) / 2 >= 40)
            #expect(active.collapsedFrame.midX == idle.collapsedFrame.midX)
            #expect(active.collapsedFrame.midY == idle.collapsedFrame.midY)
            #expect(active.triggerFrame == active.collapsedFrame)
            #expect(active.expandedFrame.contains(active.collapsedFrame))
            #expect(engine.compactBarFrame(for: snapshot, notices: [notice], settings: settings) == active.collapsedFrame)
            #expect(engine.compactBarFrame(for: idle, notices: [notice], settings: settings) == active.collapsedFrame)
            #expect(engine.compactBarFrame(for: active, notices: [notice], settings: settings) == active.collapsedFrame)
        }
        #expect(ScreenLayoutEngine(configuration: configuration).layout(for: snapshot) == idle)
    }

    @Test
    func cameraCenterTracksEveryScreenIndependentOfItsOrigin() {
        let snapshots = [
            ScreenSnapshot(displayID: 1,
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 866)),
            ScreenSnapshot(displayID: 2,
                frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080),
                visibleFrame: CGRect(x: -1920, y: -180, width: 1920, height: 1036)),
            ScreenSnapshot(displayID: 3,
                frame: CGRect(x: 160, y: 900, width: 1280, height: 720),
                visibleFrame: CGRect(x: 160, y: 900, width: 1280, height: 696)),
        ]
        let engine = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(layoutStyle: .pill))
        for (snapshot, layout) in zip(snapshots, engine.layouts(for: snapshots)) {
            #expect(layout.displayID == snapshot.displayID)
            #expect(layout.collapsedFrame.midX == snapshot.frame.midX)
            #expect(layout.collapsedFrame.midY == snapshot.frame.maxY - snapshot.topBarHeight / 2)
        }
    }

    @Test
    func cameraGeometryIgnoresTheSavedCustomEdgeInset() {
        var configuration = ScreenLayoutConfiguration(layoutStyle: .pill, edgeInset: 0)
        let zeroInset = ScreenLayoutEngine(configuration: configuration).layout(for: screen)
        configuration.edgeInset = 48
        #expect(ScreenLayoutEngine(configuration: configuration).layout(for: screen) == zeroInset)
        #expect(zeroInset.placementBounds == screen.frame.insetBy(dx: 2, dy: 2))
    }

    @Test(arguments: IslandEdge.allCases)
    func invalidExternalDimensionsRecoverAVisibleFinitePill(edge: IslandEdge) {
        let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: edge),
            pillSize: CGSize(width: CGFloat.nan, height: CGFloat.infinity), edgeInset: .nan
        )).layout(for: screen)
        #expect(layout.collapsedFrame.size == CGSize(width: 24, height: 24))
        #expect(layout.placementBounds == screen.frame.insetBy(dx: 8, dy: 8))
    }

    @Test
    func fullscreenCameraUsesSafeAreaThenSystemMenuBarAndFiniteSoftwareFallback() {
        let frame = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let snapshots: [(ScreenSnapshot, CGFloat)] = [
            (ScreenSnapshot(displayID: 1, frame: frame, visibleFrame: frame,
                            safeAreaInsets: ScreenInsets(top: 44), menuBarHeightFallback: 24), 44),
            (ScreenSnapshot(displayID: 2, frame: frame, visibleFrame: frame,
                            menuBarHeightFallback: 34), 34),
            (ScreenSnapshot(displayID: 3, frame: frame, visibleFrame: frame), 24),
        ]
        let engine = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(layoutStyle: .pill))
        for (snapshot, menuBarHeight) in snapshots {
            let layout = engine.layout(for: snapshot)
            #expect(layout.collapsedFrame.midY == frame.maxY - menuBarHeight / 2)
            #expect(layout.collapsedFrame.height == min(24, menuBarHeight - 4))
            #expect(layout.collapsedFrame.width == 80)
            #expect(layout.physicalOcclusionFrame == nil)
            #expect(layout.centerOcclusionWidth == 0, "Safe area alone cannot measure a camera cutout")
        }
    }

    @Test
    func cameraAndCustomGeometryStayInsideSmallScreenBounds() {
        for size in [CGSize(width: 100, height: 80), CGSize(width: 12, height: 12), CGSize(width: 1, height: 1)] {
            let snapshot = ScreenSnapshot(displayID: 1,
                frame: CGRect(x: -90, y: -20, width: size.width, height: size.height),
                visibleFrame: CGRect(x: -90, y: -20, width: size.width, height: size.height),
                menuBarHeightFallback: 44)
            for mode in IslandPlacementMode.allCases {
                for edge in IslandEdge.allCases {
                    let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
                        expandedSize: CGSize(width: 480, height: 680),
                        layoutStyle: .pill,
                        placement: IslandPlacement(mode: mode, edge: edge, offset: 1),
                        edgeInset: 48
                    )).layout(for: snapshot)
                    for frame in [layout.collapsedFrame, layout.expandedFrame, layout.transferDragTriggerFrame] {
                        #expect(frame.width >= 0 && frame.height >= 0)
                        #expect(frame.minX >= snapshot.frame.minX && frame.maxX <= snapshot.frame.maxX)
                        #expect(frame.minY >= snapshot.frame.minY && frame.maxY <= snapshot.frame.maxY)
                    }
                }
            }
        }
    }

    @Test
    func onlyIntersectingCustomTopPlacementAvoidsTheKnownOcclusion() {
        let snapshot = ScreenSnapshot(displayID: 4,
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 938),
            safeAreaInsets: ScreenInsets(top: 44),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 938, width: 656, height: 44),
            auxiliaryTopRightArea: CGRect(x: 856, y: 938, width: 656, height: 44))
        var configuration = ScreenLayoutConfiguration(layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: .top, offset: 0.5))
        let center = ScreenLayoutEngine(configuration: configuration).layout(for: snapshot)
        #expect(center.collapsedFrame.maxY == 930)
        #expect(center.centerOcclusionWidth == 0)
        configuration.placement.offset = 0.1
        let beside = ScreenLayoutEngine(configuration: configuration).layout(for: snapshot)
        #expect(beside.collapsedFrame.maxY == 974)
        #expect(beside.centerOcclusionWidth == 0)
        #expect(center.expandedFrame.maxY == center.collapsedFrame.maxY)
        configuration.placement.offset = 0.5
        configuration.edgeInset = 0
        let touching = ScreenLayoutEngine(configuration: configuration).layout(for: snapshot)
        #expect(touching.collapsedFrame.maxY == 938)
        #expect(touching.centerOcclusionWidth == 0)
    }

    @Test
    func defaultNotchIgnoresAllPillConfiguration() {
        let original = ScreenLayoutEngine().layout(for: screen)
        let configured = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            layoutStyle: .notch,
            placement: IslandPlacement(mode: .custom, edge: .bottom, offset: 0),
            pillSize: CGSize(width: 360, height: 60),
            edgeInset: 48
        )).layout(for: screen)
        #expect(original == configured)
        #expect(configured.style == .notch)
        #expect(configured.edge == .top)
        #expect(configured.collapsedFrame.maxY == screen.frame.maxY)
    }

    @Test(arguments: IslandEdge.allCases)
    func naturalPillUsesOneAnchorForNoticesHoverExpansionAndPets(edge: IslandEdge) throws {
        let notices = [IslandNotice(id: "media-active-left", title: "Music", side: .left)]
        var settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom, edge: edge), islandEdgeInset: 16)
        settings.mediaCompactStyle = .detailed
        for offset in [0.0, 0.5, 1.0] {
            settings.islandPlacement.offset = offset
            var configuration = settings.islandScreenConfiguration
            configuration.expandedSize = CGSize(width: 480, height: 680)
            configuration.expandsForDetailedStatus = true
            configuration.compactStatusLength = 82
            let layout = ScreenLayoutEngine(configuration: configuration).layout(for: screen)
            let frame = layout.collapsedFrame
            let bounds = screen.frame.insetBy(dx: 16, dy: 16)
            #expect(bounds.contains(frame))
            #expect(layout.placementBounds == bounds)
            #expect(edge.isVertical ? frame.height == 82 : frame.width == 82)
            #expect(layout.triggerFrame == frame)
            #expect(layout.expandedFrame.contains(frame))
            #expect(layout.transferDragTriggerFrame.contains(frame))
            let tip = edge.isVertical
                ? CGPoint(x: frame.midX, y: frame.maxY - 1)
                : CGPoint(x: frame.minX + 1, y: frame.midY)
            #expect(layout.containsTrigger(tip))
            let engine = SideNoticeLayoutEngine()
            #expect(engine.compactBarFrame(for: layout) == frame)
            #expect(engine.compactBarFrame(for: screen, notices: notices, settings: settings) == frame)
            #expect(engine.compactBarFrame(for: layout, notices: notices, settings: settings) == frame)
            let container = CollapsedPetLayout.frame(for: layout, compactBarFrame: frame)
            #expect(container.contains(frame))
            let pet = try #require(CollapsedPetLayout.petFrame(for: layout, compactBarFrame: frame, side: .right))
            #expect(container.contains(pet))
            #expect(!pet.intersects(frame))
        }
    }

    @Test
    func detailedCameraKeepsTheMenuBarCenterAndKnownOcclusionWings() {
        let snapshot = ScreenSnapshot(displayID: 4,
            frame: CGRect(x: -1512, y: 200, width: 1512, height: 982),
            visibleFrame: CGRect(x: -1512, y: 200, width: 1512, height: 938),
            safeAreaInsets: ScreenInsets(top: 44),
            auxiliaryTopLeftArea: CGRect(x: -1512, y: 1138, width: 656, height: 44),
            auxiliaryTopRightArea: CGRect(x: -656, y: 1138, width: 656, height: 44))
        let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            layoutStyle: .pill, expandsForDetailedStatus: true
        )).layout(for: snapshot)
        #expect(layout.collapsedFrame.midX == snapshot.frame.midX)
        #expect(layout.collapsedFrame.midY == 1160)
        #expect(layout.collapsedFrame.width == 520)
        #expect(layout.centerOcclusionWidth == 200)
        #expect(layout.triggerFrame == layout.collapsedFrame)
        #expect(layout.expandedFrame.contains(layout.collapsedFrame))
    }

    @Test
    func customTopChecksOcclusionAfterNaturalLengthening() throws {
        let snapshot = ScreenSnapshot(displayID: 4,
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 938),
            safeAreaInsets: ScreenInsets(top: 44),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 938, width: 656, height: 44),
            auxiliaryTopRightArea: CGRect(x: 856, y: 938, width: 656, height: 44))
        var configuration = ScreenLayoutConfiguration(layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: .top, offset: 540.0 / 1512))
        let compact = ScreenLayoutEngine(configuration: configuration).layout(for: snapshot)
        #expect(compact.collapsedFrame.maxY == 974)
        configuration.compactStatusLength = 380
        let detailed = ScreenLayoutEngine(configuration: configuration).layout(for: snapshot)
        #expect(detailed.collapsedFrame.width == 380)
        #expect(detailed.collapsedFrame.maxY == 930)
        #expect(!detailed.collapsedFrame.intersects(try #require(detailed.physicalOcclusionFrame)))
        #expect(detailed.expandedFrame.contains(detailed.collapsedFrame))
    }

    @Test
    func detailedStatusConfigurationDoesNotChangeDefaultNotchGeometry() {
        let original = ScreenLayoutEngine().layout(for: screen)
        let detailed = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            expandsForDetailedStatus: true
        )).layout(for: screen)
        #expect(original == detailed)
    }

    @Test
    func compactStatusSizingUsesSelectedPriorityAndProcessingOverrides() throws {
        let engine = SideNoticeLayoutEngine()
        var settings = FeatureSettings()
        settings.mediaCompactStyle = .detailed
        settings.mailCompactStyle = .detailed
        let media = IslandNotice(id: "media-active-left", title: "Music", side: .left)
        let mail = IslandNotice(id: "mail-notification-message", title: "Mail", side: .left)
        #expect(try #require(engine.compactBarSizing(for: [media], settings: settings)).expandsForDetailedStatus)
        #expect(try #require(engine.compactBarSizing(for: [mail], settings: settings)).expandsForDetailedStatus)
        #expect(engine.compactBarSizing(for: [], settings: settings) == nil)
        settings.compactStatusPriority = CompactStatusPriority.normalized([.aiActivity, .media])
        let ai = IslandNotice(id: "ai-active-codex", title: "Codex", side: .left)
        #expect(!(try #require(engine.compactBarSizing(for: [media, ai], settings: settings))).expandsForDetailedStatus)
        let processing = IslandNotice(id: "voice-processing-request", title: "Processing", side: .left)
        #expect(!(try #require(engine.compactBarSizing(for: [media, processing], settings: settings))).expandsForDetailedStatus)
    }

    @Test(arguments: IslandEdge.allCases)
    func naturalCustomPillsFollowSelectedContentWithoutACenterGap(edge: IslandEdge) throws {
        var settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom, edge: edge))
        settings.mediaCompactStyle = .detailed
        let engine = SideNoticeLayoutEngine()
        let scenarios: [(IslandNotice, String, Bool, Int)] = [
            (IslandNotice(id: "ai-active-codex", title: "Codex", side: .left), "1", false, 1),
            (IslandNotice(id: "media-active-left", title: "Music", side: .left), "", true, 0),
            (IslandNotice(id: "browser-download-task", title: "Download", side: .left, progress: 0.25), "25%", false, 1),
            (IslandNotice(id: "video-download-task", title: "Download", side: .left, progress: 0.25), "25%", false, 1),
            (IslandNotice(id: "focus-countdown-left", title: "Focus", detail: "00:25:00", side: .left), "00:25:00", false, 2),
            (IslandNotice(id: "toolbox-reminder-awake", title: "Keep awake", detail: "亮屏", side: .left), "亮屏", false, 2),
            (IslandNotice(id: "voice-processing-request", title: "Processing", side: .left), "", false, 0),
        ]
        for (notice, text, waveform, verticalRows) in scenarios {
            let sizing = try #require(engine.compactBarSizing(for: [notice], settings: settings))
            let presentation = try #require(sizing.customPillPresentation)
            #expect(presentation.text == text)
            #expect(presentation.showsWaveform == waveform)
            let length = sizing.customPillLength
            let visualLength: CGFloat = waveform ? 82 : 44
            if text.isEmpty {
                #expect(length == visualLength)
            } else if edge.isVertical {
                #expect(length == visualLength + 6 + CGFloat(verticalRows) * 14)
            } else {
                #expect(length > visualLength + 6)
                #expect(length < visualLength + 100)
            }
            var configuration = settings.islandScreenConfiguration
            configuration.compactStatusLength = length
            configuration.expandsForDetailedStatus = sizing.expandsForDetailedStatus
            let layout = ScreenLayoutEngine(configuration: configuration).layout(for: screen)
            #expect(layout.collapsedFrame.size == (edge.isVertical
                ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)))
            #expect(layout.placementBounds.contains(layout.collapsedFrame),
                    "A thicker activity pill must remain inside the same screen margin on every edge")
            #expect(layout.centerOcclusionWidth == 0)
            #expect(layout.triggerFrame == layout.collapsedFrame)
            #expect(layout.expandedFrame.contains(layout.collapsedFrame))
            #expect(engine.compactBarFrame(for: screen, notices: [notice], settings: settings) == layout.collapsedFrame)
            #expect(engine.compactBarFrame(for: layout, notices: [notice], settings: settings) == layout.collapsedFrame)
        }
        settings.mediaVisualizationStyle = .glow
        let music = IslandNotice(id: "media-active-left", title: "Music", side: .left)
        let glow = try #require(engine.compactBarFrame(for: screen, notices: [music], settings: settings))
        #expect(glow.size == (edge.isVertical ? CGSize(width: 32, height: 44) : CGSize(width: 44, height: 32)))
    }

    @Test
    func naturalCustomLengthDoesNotChangeCameraOrNotchDimensions() {
        for style in IslandLayoutStyle.allCases {
            var configuration = ScreenLayoutConfiguration(layoutStyle: style)
            let original = ScreenLayoutEngine(configuration: configuration).layout(for: screen)
            configuration.compactStatusLength = 32
            let resized = ScreenLayoutEngine(configuration: configuration).layout(for: screen)
            #expect(resized.collapsedFrame == original.collapsedFrame)
            #expect(resized.expandedFrame == original.expandedFrame)
        }
    }

    @Test(arguments: IslandEdge.allCases)
    func invalidNaturalLengthKeepsFinitePillsInsideThePlacementBounds(edge: IslandEdge) {
        for length in [CGFloat.nan, .infinity, -.infinity, -100, 0, 10000] {
            let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
                layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: edge),
                compactStatusLength: length
            )).layout(for: screen)
            #expect(layout.placementBounds.contains(layout.collapsedFrame))
            #expect(layout.collapsedFrame.width.isFinite && layout.collapsedFrame.height.isFinite)
            #expect(layout.collapsedFrame.width >= 24 && layout.collapsedFrame.height >= 24)
            #expect(layout.expandedFrame.contains(layout.collapsedFrame))
        }
    }

    @Test(arguments: IslandEdge.allCases)
    func everyCompactPriorityKeepsItsTextBesideTheSelectedIcon(edge: IslandEdge) throws {
        let scenarios: [(CompactStatusPriority, IslandNotice, String)] = [
            (.transient, IslandNotice(id: "focus-transition-test", title: "Focus", detail: "已开启"), "已开启"),
            (.updateAvailable, IslandNotice(id: "update-available-test", title: "Update", detail: "1.2.3"), "1.2.3"),
            (.mail, IslandNotice(id: "mail-notification-test", title: "Alice", detail: "Meeting"), "Alice Meeting"),
            (.videoDownload, IslandNotice(id: "video-download-test", title: "Download", progress: 0.42), "42%"),
            (.browserDownload, IslandNotice(id: "browser-download-test", title: "Download", progress: 0.75), "75%"),
            (.focusCountdown, IslandNotice(id: "focus-countdown-test", title: "Focus", detail: "00:05:00"), "00:05:00"),
            (.toolboxReminder, IslandNotice(id: "toolbox-reminder-test", title: "Keep awake", detail: "亮屏"), "亮屏"),
            (.aiActivity, IslandNotice(id: "ai-active-test", title: "Codex"), "1"),
            (.media, IslandNotice(id: "media-active-test", title: "Track", detail: "Artist",
                metadata: ["compactLyric": "正在唱的歌词"]), "正在唱的歌词"),
            (.focusMode, IslandNotice(id: "focus-mode-test", title: "Focus", detail: "工作"), "工作"),
        ]
        let engine = SideNoticeLayoutEngine()
        for (priority, notice, text) in scenarios {
            var settings = FeatureSettings(islandLayoutStyle: .pill,
                islandPlacement: IslandPlacement(mode: .custom, edge: edge))
            settings.mediaCompactStyle = .detailed
            settings.mediaShowLyricsAndInfo = true
            settings.mailCompactStyle = .detailed
            let sizing = try #require(engine.compactBarSizing(for: [notice], settings: settings))
            let presentation = try #require(sizing.customPillPresentation)
            #expect(presentation.priority == priority)
            #expect(presentation.notice == notice)
            #expect(presentation.text == text)
            #expect(presentation.isMedia == (priority == .media))
            let base: CGFloat = priority == .media ? 82 : 44
            #expect(sizing.customPillLength > base)
            #expect(sizing.customPillLength <= base + 174)
        }
    }

    @Test
    func lyricsAndMailInformationFollowTheirSettingsAndNeverUseArtistAsALyric() throws {
        var settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom))
        let engine = SideNoticeLayoutEngine()
        var music = IslandNotice(id: "media-active-test", title: "Track", detail: "Artist",
            metadata: ["compactLyric": "Lyrics"])
        for style in [MediaCompactStyle.compact, .detailed] {
            for enabled in [false, true] {
                settings.mediaCompactStyle = style
                settings.mediaShowLyricsAndInfo = enabled
                let sizing = try #require(engine.compactBarSizing(for: [music], settings: settings))
                #expect(sizing.customPillPresentation?.text == (style == .detailed && enabled ? "Lyrics" : ""))
            }
        }
        music.metadata = nil
        settings.mediaCompactStyle = .detailed
        let noLyrics = try #require(engine.compactBarSizing(for: [music], settings: settings))
        #expect(noLyrics.customPillPresentation?.text == "")
        #expect(noLyrics.customPillLength == 82)
        settings.mediaVisualizationStyle = .glow
        #expect(try #require(engine.compactBarSizing(for: [music], settings: settings)).customPillLength == 44)
        let background = IslandNotice(id: "background-sound-test", title: "Rain", detail: "White noise")
        settings.mediaVisualizationStyle = .waveform
        let backgroundPresentation = try #require(engine.compactBarSizing(for: [background], settings: settings)).customPillPresentation
        #expect(backgroundPresentation?.isMedia == false)
        #expect(backgroundPresentation?.showsWaveform == false)

        let older = IslandNotice(id: "mail-notification-old", title: "Alice", detail: "Old",
            createdAt: Date(timeIntervalSince1970: 1))
        let newest = IslandNotice(id: "mail-notification-new", title: "Bob", detail: "New",
            createdAt: Date(timeIntervalSince1970: 2))
        settings.mailCompactStyle = .detailed
        let detailedMail = try #require(engine.compactBarSizing(for: [older, newest], settings: settings))
        #expect(detailedMail.customPillPresentation?.notice == newest)
        #expect(detailedMail.customPillPresentation?.text == "Bob New")
        settings.mailCompactStyle = .compact
        let compactMail = try #require(engine.compactBarSizing(for: [older, newest], settings: settings))
        #expect(compactMail.customPillPresentation?.text == "")
        #expect(compactMail.customPillLength == 44)
    }

    @Test
    func processingAndUrgentTransitionsOverrideConfiguredPriorities() throws {
        var settings = FeatureSettings(islandLayoutStyle: .pill)
        settings.compactStatusPriority = CompactStatusPriority.normalized([.media, .aiActivity, .transient])
        let engine = SideNoticeLayoutEngine()
        let music = IslandNotice(id: "media-active-test", title: "Music")
        let ai = IslandNotice(id: "ai-active-test", title: "Codex")
        let transition = IslandNotice(id: "focus-transition-test", title: "Focus", detail: "已关闭")
        let urgent = try #require(engine.compactBarSizing(for: [music, ai, transition], settings: settings))
        #expect(urgent.customPillPresentation?.priority == .transient)
        #expect(urgent.customPillPresentation?.text == "已关闭")
        let processing = IslandNotice(id: "voice-processing-test", title: "Voice", detail: "处理中")
        let pending = try #require(engine.compactBarSizing(for: [music, transition, processing], settings: settings))
        #expect(pending.customPillPresentation?.priority == nil)
        #expect(pending.customPillPresentation?.notice == processing)
        #expect(pending.customPillPresentation?.text == "处理中")
        #expect(!pending.expandsForDetailedStatus && !pending.progressGlowEnabled)
        #expect(engine.compactBarSizing(for: [IslandNotice(title: "Ordinary")], settings: settings) == nil)
    }

    @Test(arguments: [1, 12, 999, 1000])
    func aiCountIsAccurateAndItsVisibleTextIsBounded(count: Int) throws {
        let notices = (0..<count).map { IslandNotice(id: "ai-active-\($0)", title: "Agent") }
        let sizing = try #require(SideNoticeLayoutEngine().compactBarSizing(
            for: notices, settings: FeatureSettings(islandLayoutStyle: .pill)))
        #expect(sizing.customPillPresentation?.aiCount == count)
        #expect(sizing.customPillPresentation?.text == (count > 999 ? "999+" : String(count)))
        #expect(sizing.customPillLength > 30 && sizing.customPillLength < 82)
    }

    @Test(arguments: IslandEdge.allCases)
    func whitespaceAndLongTextHaveBoundedNaturalLengths(edge: IslandEdge) throws {
        let engine = SideNoticeLayoutEngine()
        let settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom, edge: edge))
        let empty = IslandNotice(id: "toolbox-reminder-empty", title: "Keep awake", detail: " \n\t ")
        let compact = try #require(engine.compactBarSizing(for: [empty], settings: settings))
        #expect(compact.customPillPresentation?.text == "")
        #expect(compact.customPillLength == 44)
        let long = IslandNotice(id: "toolbox-reminder-long", title: "Keep awake", detail: String(repeating: "长", count: 1000))
        let bounded = try #require(engine.compactBarSizing(for: [long], settings: settings))
        #expect(bounded.customPillLength == 218)
        #expect(bounded.customPillPresentation?.text.count == 1000)
        let short = IslandNotice(id: "toolbox-reminder-short", title: "Keep awake", detail: " 亮 屏 ")
        let shortSizing = try #require(engine.compactBarSizing(for: [short], settings: settings))
        #expect(shortSizing.customPillPresentation?.text == "亮 屏")
        if edge.isVertical { #expect(shortSizing.customPillLength == 78) }
    }

    @Test
    func headphoneTextPreservesDeviceIdentityWhenBatteryDataIsMissing() throws {
        let engine = SideNoticeLayoutEngine()
        let settings = FeatureSettings(islandLayoutStyle: .pill)
        for levels: [NoticeBatteryLevel]? in [nil, [], [NoticeBatteryLevel(label: "L", level: nil)]] {
            let notice = IslandNotice(id: "headphone-test", title: "AirPods", detail: "Connected", style: .headphone,
                batteryLevels: levels)
            let sizing = try #require(engine.compactBarSizing(for: [notice], settings: settings))
            #expect(sizing.customPillPresentation?.text == "AirPods Connected")
        }
        let notice = IslandNotice(id: "headphone-test", title: "AirPods", detail: "Connected", style: .headphone,
            batteryLevels: [NoticeBatteryLevel(label: "L", level: 42), NoticeBatteryLevel(label: "R", level: 64)])
        let sizing = try #require(engine.compactBarSizing(for: [notice], settings: settings))
        #expect(sizing.customPillPresentation?.text == "AirPods L 42% R 64%")
    }

    @Test
    func downloadTextUsesFiniteProgressAndPreservesDetailWhenProgressIsUnavailable() throws {
        let engine = SideNoticeLayoutEngine()
        for prefix in ["video-download-", "browser-download-"] {
            for progress: Double? in [nil, .nan, .infinity, -.infinity] {
                var notice = IslandNotice(id: prefix + "test", title: "Download", detail: "Preparing")
                notice.progress = progress
                let sizing = try #require(engine.compactBarSizing(for: [notice], settings: FeatureSettings()))
                #expect(sizing.customPillPresentation?.text == "Preparing")
            }
            for (progress, text) in [(-1.0, "0%"), (0.0, "0%"), (0.25, "25%"), (1.0, "100%"), (2.0, "100%")] {
                var notice = IslandNotice(id: prefix + "test", title: "Download", detail: "Preparing")
                notice.progress = progress
                #expect(try #require(engine.compactBarSizing(for: [notice], settings: FeatureSettings())).customPillPresentation?.text == text)
            }
        }
    }

    @Test(arguments: IslandEdge.allCases)
    func liveLyricsUpdateOnlyTheMeasuredLengthAndKeepTheStoredPresentation(edge: IslandEdge) throws {
        var settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom, edge: edge))
        settings.mediaCompactStyle = .detailed
        settings.mediaShowLyricsAndInfo = true
        let notice = IslandNotice(id: "media-active-test", title: "Track", metadata: ["compactLyric": "旧歌词"])
        let sizing = try #require(SideNoticeLayoutEngine().compactBarSizing(for: [notice], settings: settings))
        let presentation = try #require(sizing.customPillPresentation)
        let originalLength = presentation.length(thickness: 32, edge: edge)
        let liveLength = presentation.length(thickness: 32, edge: edge, text: "正在播放的新歌词")
        #expect(liveLength > originalLength)
        #expect(presentation.length(thickness: 32, edge: edge, text: " \n ") == 82)
        #expect(presentation.text == "旧歌词")
        #expect(presentation.notice == notice)
        #expect(presentation.length(thickness: 32, edge: edge) == originalLength)
    }

    @Test(arguments: IslandEdge.allCases)
    func naturalContentKeepsCornerOffsetsWhenResizingAnIdleLayout(edge: IslandEdge) throws {
        let engine = SideNoticeLayoutEngine()
        let notices = [
            IslandNotice(id: "toolbox-reminder-empty", title: "Keep awake"),
            IslandNotice(id: "media-active-test", title: "Track"),
            IslandNotice(id: "toolbox-reminder-long", title: "Keep awake", detail: String(repeating: "长", count: 100)),
        ]
        for offset in [0.0, 1.0] {
            let settings = FeatureSettings(islandLayoutStyle: .pill,
                islandPlacement: IslandPlacement(mode: .custom, edge: edge, offset: offset))
            let idle = ScreenLayoutEngine(configuration: settings.islandScreenConfiguration).layout(for: screen)
            for notice in notices {
                let sizing = try #require(engine.compactBarSizing(for: [notice], settings: settings))
                var configuration = settings.islandScreenConfiguration
                configuration.compactStatusLength = sizing.customPillLength
                let layout = ScreenLayoutEngine(configuration: configuration).layout(for: screen)
                let frame = layout.collapsedFrame
                let bounds = layout.placementBounds
                if edge.isVertical {
                    #expect(offset == 0 ? frame.minY == bounds.minY : frame.maxY == bounds.maxY)
                } else {
                    #expect(offset == 0 ? frame.minX == bounds.minX : frame.maxX == bounds.maxX)
                }
                #expect(engine.compactBarFrame(for: screen, notices: [notice], settings: settings) == frame)
                #expect(engine.compactBarFrame(for: idle, notices: [notice], settings: settings) == frame)
            }
        }
    }

    @Test
    func shorteningCustomTopContentRestoresTheEdgeAfterOcclusionAvoidance() throws {
        let snapshot = ScreenSnapshot(displayID: 4,
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 938),
            safeAreaInsets: ScreenInsets(top: 44),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 938, width: 656, height: 44),
            auxiliaryTopRightArea: CGRect(x: 856, y: 938, width: 656, height: 44))
        var settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom, edge: .top, offset: 550.0 / 1512))
        settings.mediaCompactStyle = .detailed
        settings.mediaShowLyricsAndInfo = true
        let music = IslandNotice(id: "media-active-test", title: "Track", metadata: ["compactLyric": String(repeating: "长", count: 100)])
        let engine = SideNoticeLayoutEngine()
        var configuration = settings.islandScreenConfiguration
        configuration.compactStatusLength = try #require(engine.compactBarSizing(for: [music], settings: settings)).customPillLength
        let long = ScreenLayoutEngine(configuration: configuration).layout(for: snapshot)
        #expect(long.collapsedFrame.width == 256)
        #expect(long.collapsedFrame.maxY == 930)
        let short = IslandNotice(id: "toolbox-reminder-test", title: "Keep awake")
        let snapshotFrame = try #require(engine.compactBarFrame(for: snapshot, notices: [short], settings: settings))
        #expect(snapshotFrame.maxY == 974)
        #expect(engine.compactBarFrame(for: long, notices: [short], settings: settings) == snapshotFrame)
    }

    @Test
    func cameraNoticeFramesMatchTheirActualAnchorWithAndWithoutKnownOcclusion() throws {
        let notched = ScreenSnapshot(displayID: 4,
            frame: CGRect(x: -1512, y: 200, width: 1512, height: 982),
            visibleFrame: CGRect(x: -1512, y: 200, width: 1512, height: 938),
            safeAreaInsets: ScreenInsets(top: 44),
            auxiliaryTopLeftArea: CGRect(x: -1512, y: 1138, width: 656, height: 44),
            auxiliaryTopRightArea: CGRect(x: -656, y: 1138, width: 656, height: 44))
        let engine = SideNoticeLayoutEngine()
        var settings = FeatureSettings(islandLayoutStyle: .pill)
        let music = IslandNotice(id: "media-active-test", title: "Track")
        for snapshot in [screen, notched] {
            for style in [MediaCompactStyle.compact, .detailed] {
                settings.mediaCompactStyle = style
                let idle = ScreenLayoutEngine(configuration: settings.islandScreenConfiguration).layout(for: snapshot)
                var configuration = settings.islandScreenConfiguration
                configuration.expandsForDetailedStatus = style == .detailed
                configuration.compactStatusLength = try #require(
                    engine.compactBarSizing(for: [music], settings: settings)
                ).customPillLength
                let actual = ScreenLayoutEngine(configuration: configuration).layout(for: snapshot)
                #expect(engine.compactBarFrame(for: snapshot, notices: [music], settings: settings) == actual.collapsedFrame)
                #expect(engine.compactBarFrame(for: idle, notices: [music], settings: settings) == actual.collapsedFrame)
                #expect(engine.compactBarFrame(for: actual, notices: [music], settings: settings) == actual.collapsedFrame)
                #expect(actual.collapsedFrame.midY == snapshot.frame.maxY - snapshot.topBarHeight / 2)
            }
        }
    }

    @Test(arguments: IslandEdge.allCases)
    func waveformLyricsReserveBothGapsAndTheFullTextBudget(edge: IslandEdge) throws {
        var settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom, edge: edge))
        settings.mediaCompactStyle = .detailed
        settings.mediaShowLyricsAndInfo = true
        let notice = IslandNotice(id: "media-active-test", title: "Track",
            metadata: ["compactLyric": String(repeating: "长", count: 100)])
        let engine = SideNoticeLayoutEngine()
        let waveform = try #require(engine.compactBarSizing(for: [notice], settings: settings))
        let waveformLength: CGFloat = 32 + 6 + 168 + 6 + 32 + 12
        #expect(waveform.customPillLength == waveformLength)
        settings.mediaVisualizationStyle = .glow
        let glow = try #require(engine.compactBarSizing(for: [notice], settings: settings))
        let glowLength: CGFloat = 32 + 6 + 168 + 12
        let waveformSlot: CGFloat = 32 + 6
        #expect(glow.customPillLength == glowLength)
        #expect(waveform.customPillLength - glow.customPillLength == waveformSlot)
    }

    @Test(arguments: IslandEdge.allCases)
    func savedSettingsReachTheSameLayoutWithoutLosingDimensionsOrInsets(edge: IslandEdge) {
        let settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom, edge: edge, offset: 0.25),
            islandPillWidth: 220, islandPillHeight: 44, islandEdgeInset: 16)
        let configuration = settings.islandScreenConfiguration
        #expect(configuration.layoutStyle == .pill)
        #expect(configuration.placement == settings.islandPlacement)
        #expect(configuration.pillSize == CGSize(width: 80, height: 24))
        #expect(configuration.edgeInset == 16)
        #expect(!configuration.expandsForDetailedStatus && configuration.compactStatusLength == nil)
        let layout = ScreenLayoutEngine(configuration: configuration).layout(for: screen)
        #expect(layout.edge == edge)
        #expect(layout.collapsedFrame.size == CGSize(width: 24, height: 24))
        #expect(layout.placementBounds == screen.frame.insetBy(dx: 16, dy: 16))
    }

    @Test(arguments: IslandEdge.allCases)
    func ordinaryNoticesFollowEveryPillEdgeWithoutOverlappingAtCorners(edge: IslandEdge) {
        let other = ScreenSnapshot(displayID: 8,
            frame: CGRect(x: 100, y: 880, width: 1440, height: 900),
            visibleFrame: CGRect(x: 100, y: 880, width: 1440, height: 876))
        let engine = SideNoticeLayoutEngine()
        for snapshot in [screen, other] {
            for offset in [0.0, 0.5, 1.0] {
                let configuration = ScreenLayoutConfiguration(layoutStyle: .pill,
                    placement: IslandPlacement(mode: .custom, edge: edge, offset: offset),
                    compactStatusLength: 32)
                let anchor = ScreenLayoutEngine(configuration: configuration).layout(for: snapshot).collapsedFrame
                let bounds = snapshot.frame.insetBy(dx: 8, dy: 8)
                for leftCount in 1...3 {
                    for rightCount in 1...3 {
                        let left = engine.presentation(for: (0..<leftCount).map {
                            IslandNotice(id: "ordinary-left-\($0)", title: "Left", side: .left)
                        }, compactWingsEnabled: false)
                        let right = engine.presentation(for: (0..<rightCount).map {
                            IslandNotice(id: "ordinary-right-\($0)", title: "Right", side: .right)
                        }, compactWingsEnabled: false)
                        let leftFrame = engine.frame(side: .left, presentation: left, screen: snapshot, configuration: configuration)
                        let rightFrame = engine.frame(side: .right, presentation: right, screen: snapshot, configuration: configuration)
                        #expect(bounds.contains(leftFrame) && bounds.contains(rightFrame))
                        #expect(!leftFrame.intersects(rightFrame))
                        #expect(!leftFrame.intersects(anchor) && !rightFrame.intersects(anchor))
                        #expect(leftFrame.size == left.panelSize && rightFrame.size == right.panelSize)
                        for frame in [leftFrame, rightFrame] {
                            switch edge {
                            case .top: #expect(frame.maxY == anchor.minY - 4)
                            case .bottom: #expect(frame.minY == anchor.maxY + 4)
                            case .left: #expect(frame.minX == anchor.maxX + 4)
                            case .right: #expect(frame.maxX == anchor.minX - 4)
                            }
                        }
                        if edge.isVertical { #expect(leftFrame.minY > rightFrame.maxY) }
                        else { #expect(leftFrame.maxX < rightFrame.minX) }
                    }
                }
            }
        }
    }

    @Test
    func ordinaryNoticesKeepLegacyFramesWhenPillSettingsAreInactive() {
        let notched = ScreenSnapshot(displayID: 4,
            frame: CGRect(x: -1512, y: 200, width: 1512, height: 982),
            visibleFrame: CGRect(x: -1512, y: 200, width: 1512, height: 938),
            safeAreaInsets: ScreenInsets(top: 44),
            auxiliaryTopLeftArea: CGRect(x: -1512, y: 1138, width: 656, height: 44),
            auxiliaryTopRightArea: CGRect(x: -656, y: 1138, width: 656, height: 44))
        let engine = SideNoticeLayoutEngine()
        for snapshot in [screen, notched] {
            for side in [NoticeSide.left, .right] {
                let ordinary = IslandNotice(id: "ordinary", title: "Detail", side: side)
                let ai = IslandNotice(id: "ai-active-test", title: "Codex", side: side)
                for notices in [[ordinary], [ordinary, ai], [ai], []] {
                    let presentation = engine.presentation(for: notices)
                    let original = engine.frame(side: side, presentation: presentation, screen: snapshot)
                    let configured = engine.frame(side: side, presentation: presentation, screen: snapshot,
                        configuration: ScreenLayoutConfiguration(layoutStyle: .notch,
                            placement: IslandPlacement(mode: .custom, edge: .bottom, offset: 0),
                            pillSize: CGSize(width: 400, height: 64), edgeInset: 48, compactStatusLength: 32))
                    #expect(original == configured)
                }
            }
        }
    }

    @Test
    func cameraOrdinaryNoticesStayBelowTheActualMenuBarPill() {
        let engine = SideNoticeLayoutEngine()
        var configuration = ScreenLayoutConfiguration(layoutStyle: .pill,
            placement: IslandPlacement(mode: .camera, edge: .right, offset: 0), edgeInset: 48)
        let notched = ScreenSnapshot(displayID: 4,
            frame: CGRect(x: -1512, y: 200, width: 1512, height: 982),
            visibleFrame: CGRect(x: -1512, y: 200, width: 1512, height: 938),
            safeAreaInsets: ScreenInsets(top: 44),
            auxiliaryTopLeftArea: CGRect(x: -1512, y: 1138, width: 656, height: 44),
            auxiliaryTopRightArea: CGRect(x: -656, y: 1138, width: 656, height: 44))
        for snapshot in [screen, notched] {
            for detailed in [false, true] {
                configuration.expandsForDetailedStatus = detailed
                let anchor = ScreenLayoutEngine(configuration: configuration).layout(for: snapshot).collapsedFrame
                for side in [NoticeSide.left, .right] {
                    let presentation = engine.presentation(for: [IslandNotice(title: "Ordinary", side: side)], compactWingsEnabled: false)
                    let frame = engine.frame(side: side, presentation: presentation, screen: snapshot, configuration: configuration)
                    #expect(frame.maxY == anchor.minY - 4)
                    #expect(frame.size == presentation.panelSize)
                    #expect(!frame.intersects(anchor))
                }
            }
        }
        let compactOnly = engine.presentation(for: [IslandNotice(id: "ai-active-test", title: "Codex")])
        #expect(engine.frame(side: .left, presentation: compactOnly, screen: screen, configuration: configuration) == .zero)
        let empty = engine.presentation(for: [], compactWingsEnabled: false)
        #expect(engine.frame(side: .right, presentation: empty, screen: screen, configuration: configuration) == .zero)
    }

    @Test(arguments: IslandEdge.allCases)
    func ordinaryPillNoticesFitSmallScreensAndOmitUnavailableInwardSpace(edge: IslandEdge) {
        let engine = SideNoticeLayoutEngine()
        for size in [CGSize(width: 500, height: 300), CGSize(width: 80, height: 80), CGSize(width: 12, height: 12), .zero] {
            let snapshot = ScreenSnapshot(displayID: 1,
                frame: CGRect(x: -100, y: -80, width: size.width, height: size.height),
                visibleFrame: CGRect(x: -100, y: -80, width: size.width, height: size.height))
            let configuration = ScreenLayoutConfiguration(layoutStyle: .pill,
                placement: IslandPlacement(mode: .custom, edge: edge), compactStatusLength: 32)
            let anchor = ScreenLayoutEngine(configuration: configuration).layout(for: snapshot).collapsedFrame
            let presentation = engine.presentation(for: (0..<10).map { IslandNotice(id: "ordinary-\($0)", title: "Detail") },
                compactWingsEnabled: false)
            let left = engine.frame(side: .left, presentation: presentation, screen: snapshot, configuration: configuration)
            let right = engine.frame(side: .right, presentation: presentation, screen: snapshot, configuration: configuration)
            if left != .zero && right != .zero { #expect(!left.intersects(right)) }
            for frame in [left, right] {
                #expect(frame.width.isFinite && frame.height.isFinite)
                if size.width <= 16 || size.height <= 16 {
                    #expect(frame == .zero)
                } else {
                    #expect(snapshot.frame.contains(frame))
                    #expect(frame.width > 0 && frame.height > 0)
                    #expect(frame.width <= 252 && frame.height <= presentation.panelSize.height)
                    if edge.isVertical { #expect(frame.height <= 174) }
                    #expect(!frame.intersects(anchor))
                }
            }
        }
    }

    @Test
    @MainActor
    func ordinaryLayoutCapacityUsesTheQueuesExistingDefault() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let capacity = SideNoticeQueue.defaultCapacityPerSide
        #expect(capacity == 3)
        for side in [NoticeSide.left, .right] {
            for index in 0...capacity {
                queue.enqueue(IslandNotice(id: "ordinary-\(side.rawValue)-\(index)", title: "Detail", side: side), expiresAfter: nil)
            }
        }
        #expect(queue.left.count == capacity && queue.right.count == capacity)
        #expect(queue.left.first?.id == "ordinary-left-1")
        #expect(queue.right.first?.id == "ordinary-right-1")
    }

    @Test(arguments: [IslandEdge.left, .right])
    func oversizedVerticalPillKeepsOrdinaryNoticesWithinTheOppositeScreenMargin(edge: IslandEdge) {
        let snapshot = ScreenSnapshot(displayID: 1,
            frame: CGRect(x: -100, y: -80, width: 80, height: 80),
            visibleFrame: CGRect(x: -100, y: -80, width: 80, height: 80))
        let configuration = ScreenLayoutConfiguration(layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: edge),
            pillSize: CGSize(width: 180, height: 64), compactStatusLength: 64)
        let engine = SideNoticeLayoutEngine()
        let presentation = engine.presentation(for: [IslandNotice(title: "Detail")], compactWingsEnabled: false)
        #expect(engine.frame(side: .left, presentation: presentation, screen: snapshot, configuration: configuration) == .zero)
        #expect(engine.frame(side: .right, presentation: presentation, screen: snapshot, configuration: configuration) == .zero)
    }
}
