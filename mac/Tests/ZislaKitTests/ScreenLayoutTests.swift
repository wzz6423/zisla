import AppKit
import CoreGraphics
import Testing

@testable import ZislaKit

struct ScreenLayoutTests {
    private let engine = ScreenLayoutEngine(
        configuration: ScreenLayoutConfiguration(
            simulatedIslandSize: CGSize(width: 180, height: 32),
            expandedSize: CGSize(width: 420, height: 180),
            horizontalMargin: 12
        )
    )

    @Test
    func physicalNotchUsesAuxiliaryAreaGap() {
        let screen = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )

        let layout = engine.layout(for: screen)
        let expectedFrame = CGRect(
            x: 716,
            y: 950,
            width: 80,
            height: 32
        )

        #expect(screen.id == 42)
        #expect(layout.topology == .physicalNotch(frame: expectedFrame))
        #expect(layout.topology.anchorFrame.height == 32)
        #expect(layout.topology.anchorFrame.maxY == screen.frame.maxY)
        #expect(layout.topology.anchorFrame.minY == 950)
        #expect(layout.triggerFrame == CGRect(x: 692, y: 950, width: 128, height: 32))
        #expect(layout.collapsedFrame == layout.topology.anchorFrame)
        #expect(layout.expandedFrame.maxY == screen.frame.maxY)
    }

    @Test
    func physicalNotchUsesSafeAreaDepthWhenMenuBarIsShorter() {
        let screen = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 958),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )

        let layout = engine.layout(for: screen)
        #expect(screen.topBarHeight == 24)
        #expect(
            layout.topology
                == .physicalNotch(
                    frame: CGRect(x: 716, y: 950, width: 80, height: 32)
                ))
        #expect(layout.topology.anchorFrame.height == 32)
        #expect(layout.topology.anchorFrame.maxY == screen.frame.maxY)
        #expect(layout.topology.anchorFrame.minY == 950)
    }

    @Test
    func physicalNotchStaysCenteredWhenAuxiliaryAreasAreAsymmetric() {
        let screen = ScreenSnapshot(
            displayID: 43,
            frame: CGRect(x: -1_920, y: -180, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: -1_920, y: -180, width: 1_920, height: 1_048),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: -1_920, y: 868, width: 860, height: 32),
            auxiliaryTopRightArea: CGRect(x: -940, y: 868, width: 940, height: 32)
        )

        let layout = engine.layout(for: screen)

        #expect(layout.collapsedFrame.width == 120)
        #expect(layout.collapsedFrame.midX == screen.frame.midX)
        #expect(layout.expandedFrame.midX == screen.frame.midX)
    }

    @Test
    func physicalNotchAndExternalIslandKeepIndependentTopAnchors() throws {
        let notchedScreen = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )
        let externalScreen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 1_512, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 1_512, y: 0, width: 1_440, height: 875)
        )

        let layouts = engine.layouts(for: [notchedScreen, externalScreen])
        let topLeftArea = try #require(notchedScreen.auxiliaryTopLeftArea)

        #expect(layouts[0].collapsedFrame == CGRect(x: 716, y: 950, width: 80, height: 32))
        #expect(layouts[0].collapsedFrame.minY == topLeftArea.minY)
        #expect(layouts[1].collapsedFrame == CGRect(x: 2_142, y: 875, width: 180, height: 25))
        #expect(layouts[1].collapsedFrame.maxY == externalScreen.frame.maxY)
    }

    @Test
    func defaultSimulatedIslandMatchesMenuBarHeight() {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )

        let layout = ScreenLayoutEngine().layout(for: screen)

        #expect(
            layout.topology
                == .simulated(
                    frame: CGRect(x: 600, y: 875, width: 240, height: 25)
                ))
        #expect(layout.triggerFrame == CGRect(x: 600, y: 875, width: 240, height: 25))
    }

    @Test
    func simulatedIslandMatchesEachScreenMenuBarHeight() {
        let compactMenuBar = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )
        let tallMenuBar = ScreenSnapshot(
            displayID: 8,
            frame: CGRect(x: 1_440, y: 0, width: 1_920, height: 900),
            visibleFrame: CGRect(x: 1_440, y: 0, width: 1_920, height: 862)
        )

        let layouts = ScreenLayoutEngine().layouts(for: [compactMenuBar, tallMenuBar])

        #expect(layouts[0].collapsedFrame.height == 25)
        #expect(layouts[0].collapsedFrame.maxY == compactMenuBar.frame.maxY)
        #expect(layouts[1].collapsedFrame.height == 38)
        #expect(layouts[1].collapsedFrame.maxY == tallMenuBar.frame.maxY)
    }

    @Test
    func simulatedIslandFallsBackToConfiguredHeightWhenMenuBarDepthIsUnavailable() {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        let layout = engine.layout(for: screen)

        #expect(
            layout.topology
                == .simulated(
                    frame: CGRect(x: 630, y: 868, width: 180, height: 32)
                ))
    }

    @Test
    func simulatedIslandFlushesAgainstAnUnreservedFullscreenTopEdge() {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            menuBarHeightFallback: 24
        )

        let layout = ScreenLayoutEngine().layout(for: screen)

        #expect(screen.topBarHeight == 24)
        #expect(layout.collapsedFrame == CGRect(x: 600, y: 876, width: 240, height: 24))
        #expect(layout.collapsedFrame.maxY == screen.frame.maxY)
        #expect(layout.expandedFrame.maxY == screen.frame.maxY)
    }

    @Test
    func screenWithoutNotchUsesCenteredSimulatedAnchor() {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )

        let layout = engine.layout(for: screen)

        #expect(
            layout.topology
                == .simulated(
                    frame: CGRect(x: 630, y: 875, width: 180, height: 25)
                ))
        #expect(layout.triggerFrame == CGRect(x: 630, y: 875, width: 180, height: 25))
        #expect(layout.expandedFrame == CGRect(x: 510, y: 720, width: 420, height: 180))
    }

    @Test
    func negativeScreenCoordinatesRemainTopAnchored() {
        let screen = ScreenSnapshot(
            displayID: 99,
            frame: CGRect(x: -1_920, y: -180, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: -1_920, y: -180, width: 1_920, height: 1_055)
        )

        let layout = engine.layout(for: screen)

        #expect(layout.triggerFrame == CGRect(x: -1_050, y: 875, width: 180, height: 25))
        #expect(layout.expandedFrame == CGRect(x: -1_170, y: 720, width: 420, height: 180))
        #expect(layout.triggerFrame.maxY == layout.collapsedFrame.maxY)
        #expect(layout.expandedFrame.maxY == screen.frame.maxY)
    }

    @Test
    func triggerHitTestingCoversOnlyTheIsland() {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )
        let layout = engine.layout(for: screen)

        // Trigger zone is the island body itself (x∈[630,810], y∈[875,900]); below the notch (y<875) does not trigger.
        #expect(layout.containsTrigger(CGPoint(x: 720, y: 900)))
        #expect(layout.containsTrigger(CGPoint(x: 630, y: 875)))
        #expect(!layout.containsTrigger(CGPoint(x: 720, y: 874.99)))
        #expect(!layout.containsTrigger(CGPoint(x: 629.99, y: 875)))
    }

    @Test
    func layoutCollectionKeepsStableDisplayIdentityAcrossReordering() {
        let primary = ScreenSnapshot(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )
        let secondary = ScreenSnapshot(
            displayID: 2,
            frame: CGRect(x: -1_920, y: -180, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: -1_920, y: -180, width: 1_920, height: 1_055)
        )

        let layouts = engine.layouts(for: [secondary, primary])

        #expect(layouts.map(\.displayID) == [2, 1])
        #expect(engine.layout(containing: CGPoint(x: -960, y: 899), in: layouts)?.displayID == 2)
        #expect(engine.layout(containing: CGPoint(x: 720, y: 899), in: layouts)?.displayID == 1)
    }

    @Test
    func screenHitTestingUsesFullFrameOutsideTriggerArea() {
        let primary = ScreenSnapshot(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )
        let secondary = ScreenSnapshot(
            displayID: 2,
            frame: CGRect(x: -1_920, y: -180, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: -1_920, y: -180, width: 1_920, height: 1_055)
        )
        let layouts = engine.layouts(for: [primary, secondary])

        #expect(
            engine.screenLayout(containing: CGPoint(x: -1_000, y: 300), in: layouts)?.displayID == 2
        )
        #expect(
            engine.screenLayout(containing: CGPoint(x: 800, y: 300), in: layouts)?.displayID == 1)
        #expect(engine.screenLayout(containing: CGPoint(x: 2_000, y: 300), in: layouts) == nil)
    }

    @Test
    func collapseGenerationInvalidatesOlderWork() {
        var generation = CollapseGenerationTracker()

        let first = generation.advance()
        let second = generation.advance()

        #expect(!generation.isCurrent(first))
        #expect(generation.isCurrent(second))
    }

    @Test
    func expandedFrameClampsToSmallScreenMargins() {
        let screen = ScreenSnapshot(
            displayID: 3,
            frame: CGRect(x: 100, y: 50, width: 320, height: 200),
            visibleFrame: CGRect(x: 100, y: 50, width: 320, height: 175)
        )

        let layout = engine.layout(for: screen)

        #expect(layout.expandedFrame == CGRect(x: 112, y: 70, width: 296, height: 180))
        #expect(layout.expandedFrame.maxY == screen.frame.maxY)
    }

    @Test
    func moduleSizeChangesKeepTheExpandedFrameTopAndCenterAnchored() {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )
        let moduleSizes = [
            CGSize(width: 860, height: 344),
            CGSize(width: 860, height: 504),
            CGSize(width: 820, height: 474),
            CGSize(width: 660, height: 564),
            CGSize(width: 720, height: 564),
            CGSize(width: 1_060, height: 524),
        ]

        for size in moduleSizes {
            let engine = ScreenLayoutEngine(
                configuration: ScreenLayoutConfiguration(expandedSize: size)
            )
            let frame = engine.layout(for: screen).expandedFrame

            #expect(frame.midX == screen.frame.midX)
            #expect(frame.maxY == screen.frame.maxY)
        }
    }

    @Test
    func transferDragTriggerSitsBelowMenuBar() {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )

        let layout = engine.layout(for: screen)

        #expect(
            layout.transferDragTriggerFrame
                == CGRect(x: 560, y: 827, width: 320, height: 48)
        )
        #expect(layout.transferDragTriggerFrame.maxY == screen.visibleFrame.maxY)
        #expect(layout.containsTransferDragTrigger(CGPoint(x: 720, y: 850)))
        #expect(!layout.containsTrigger(CGPoint(x: 720, y: 850)))
    }

    @Test @MainActor
    func islandPanelKeepsItsTopAnchoredFrameAcrossTheMenuBar() throws {
        let screen = try #require(NSScreen.main)
        let proposed = CGRect(
            x: screen.frame.midX - 210,
            y: screen.frame.maxY - 180,
            width: 420,
            height: 180
        )
        let panel = IslandPanel(contentView: NSView(), frame: proposed)

        #expect(panel.constrainFrameRect(proposed, to: screen) == proposed)
    }

    @Test
    func unsupportedDragCannotActivateTransferTrigger() {
        let screen = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )
        let layouts = engine.layouts(for: [screen])
        let point = CGPoint(x: 720, y: 850)

        #expect(
            engine.transferDragLayout(
                containing: point,
                hasSupportedPayload: false,
                in: layouts
            ) == nil
        )
        #expect(
            engine.transferDragLayout(
                containing: point,
                hasSupportedPayload: true,
                in: layouts
            )?.displayID == 7
        )
    }
}
