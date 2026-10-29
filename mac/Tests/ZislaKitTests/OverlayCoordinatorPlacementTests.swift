import AppKit
import Testing
import ZislaCore
@testable import ZislaKit

@MainActor
struct OverlayCoordinatorPlacementTests {
    private let screen = ScreenSnapshot(displayID: 7,
        frame: CGRect(x: 20000, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 20000, y: 0, width: 1440, height: 876))

    @Test
    func placementChangesPublishTheCurrentLayoutBeforePresentation() throws {
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content)
        coordinator.screenSnapshotProvider = { [screen] }
        coordinator.updateScreens([screen])
        var changes: [ScreenOverlayLayout?] = []
        var sizes: [CGSize] = []
        coordinator.onActiveLayoutChanged = { changes.append($0) }
        coordinator.onCollapsedSizeChanged = { sizes.append($0) }
        coordinator.selectActiveDisplay(at: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        coordinator.updatePlacement(layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: .left),
            pillSize: CGSize(width: 220, height: 40), edgeInset: 12)
        let layout = try #require(coordinator.activeLayout)
        #expect(layout.edge == .left)
        #expect(layout.collapsedFrame.size == CGSize(width: 40, height: 220))
        #expect(layout.collapsedFrame.minX == screen.frame.minX + 12)
        #expect(changes.count == 2)
        #expect(changes.last! == layout)
        #expect(content.window == nil)
        #expect(!coordinator.isVisible)
        let sizeCount = sizes.count

        coordinator.updatePlacement(layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: .left))
        #expect(changes.count == 2)
        #expect(sizes.count == sizeCount, "An unchanged placement does not restart its collapsed resize")
        coordinator.refreshScreens()
        #expect(changes.count == 2)
        coordinator.stop()
        #expect(changes.last! == nil)
    }

    @Test
    func removingTheActiveDisplayPublishesItsReplacementAndThenNil() {
        let other = ScreenSnapshot(displayID: 8,
            frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1056))
        let coordinator = OverlayCoordinator(contentView: NSView())
        coordinator.updateScreens([screen, other])
        var changes: [CGDirectDisplayID?] = []
        coordinator.onActiveLayoutChanged = { changes.append($0?.displayID) }
        coordinator.selectActiveDisplay(at: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        coordinator.updateScreens([other])
        coordinator.updateScreens([])
        #expect(changes == [7, 8, nil])
        #expect(coordinator.activeLayout == nil)
        coordinator.stop()
    }

    @Test
    func resizingAPrewarmedCollapsedPanelRetainsTheNewEdgeAnchor() throws {
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content)
        coordinator.screenSnapshotProvider = { [screen] }
        coordinator.start()
        defer { coordinator.stop() }
        coordinator.prewarmPanel()
        let panel = try #require(content.window)
        coordinator.updatePlacement(layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: .bottom, offset: 0.1))
        let layout = try #require(coordinator.activeLayout)
        #expect(panel.frame == layout.expandedFrame)
        #expect(panel.frame.minY == layout.collapsedFrame.minY)
        #expect(!coordinator.isVisible)
    }

    @Test
    func aNewPlacementReachesContentBeforeTheVisiblePanelMoves() throws {
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content)
        coordinator.screenSnapshotProvider = { [screen] }
        coordinator.updateScreens([screen])
        coordinator.selectActiveDisplay(at: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        coordinator.setPinned(true)
        defer { coordinator.stop() }
        let panel = try #require(content.window as? IslandPanel)
        let originalFrame = panel.frame
        var frameAtNotification: CGRect?
        var notifiedLayout: ScreenOverlayLayout?
        coordinator.onActiveLayoutChanged = { layout in
            frameAtNotification = panel.frame
            notifiedLayout = layout
        }
        coordinator.updatePlacement(layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: .right))
        #expect(frameAtNotification == originalFrame)
        #expect(notifiedLayout?.edge == .right)
        #expect(panel.frame == notifiedLayout?.expandedFrame)
        #expect(panel.isPinned)
    }

    @Test(arguments: IslandEdge.allCases)
    func naturalStatusUpdatesTheHoverAnchorAndRestoresTheCompactPill(edge: IslandEdge) throws {
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content,
            layoutEngine: ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
                layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: edge)
            )))
        coordinator.screenSnapshotProvider = { [screen] }
        coordinator.start()
        defer { coordinator.stop() }
        coordinator.selectActiveDisplay(at: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        coordinator.prewarmPanel()
        let panel = try #require(content.window as? IslandPanel)
        let compact = try #require(coordinator.activeLayout)
        var sizes: [CGSize] = []
        coordinator.onCollapsedSizeChanged = { sizes.append($0) }
        coordinator.updateCompactStatus(expandsForDetailedStatus: true, compactStatusLength: 220)
        let detailed = try #require(coordinator.activeLayout)
        #expect(detailed.collapsedFrame.size != compact.collapsedFrame.size)
        #expect(sizes.last == detailed.collapsedFrame.size)
        #expect(panel.frame == detailed.expandedFrame)
        let sizeCount = sizes.count
        coordinator.updateCompactStatus(expandsForDetailedStatus: true, compactStatusLength: 220)
        #expect(sizes.count == sizeCount, "An unchanged compact status does not restart its resize")
        let tip = edge.isVertical
            ? CGPoint(x: detailed.collapsedFrame.midX, y: detailed.collapsedFrame.maxY - 1)
            : CGPoint(x: detailed.collapsedFrame.minX + 1, y: detailed.collapsedFrame.midY)
        #expect(!compact.containsTrigger(tip))
        coordinator.handlePointer(at: tip)
        #expect(coordinator.isVisible)
        #expect(!panel.ignoresMouseEvents)
        coordinator.collapseImmediately()
        coordinator.updateCompactStatus(expandsForDetailedStatus: false)
        #expect(coordinator.activeLayout?.collapsedFrame == compact.collapsedFrame)
        #expect(panel.frame == coordinator.activeLayout?.expandedFrame)
        #expect(sizes.last == compact.collapsedFrame.size)
    }

    @Test(arguments: [false, true])
    func selectionSuspensionKeepsRefreshedIslandAndPetWindowsHidden(pinned: Bool) throws {
        let content = NSView()
        var petWindows: [NSView] = []
        let coordinator = OverlayCoordinator(contentView: content,
            persistentContentViewProvider: { _ in
                let pet = NSView()
                petWindows.append(pet)
                return pet
            },
            persistentPanelFrameProvider: { $0.collapsedFrame })
        let other = ScreenSnapshot(displayID: 8,
            frame: screen.frame.offsetBy(dx: 1440, dy: 0),
            visibleFrame: screen.visibleFrame.offsetBy(dx: 1440, dy: 0))
        coordinator.screenSnapshotProvider = { [screen, other] }
        coordinator.start()
        defer { coordinator.stop() }
        coordinator.selectActiveDisplay(at: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        coordinator.prewarmPanel()
        if pinned { coordinator.setPinned(true) }
        let panel = try #require(content.window)
        coordinator.setHoverActivationSuspended(true)
        coordinator.updatePlacement(layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: .left))
        coordinator.updateCompactStatus(expandsForDetailedStatus: true)
        coordinator.refreshPersistentPanels()
        coordinator.refreshScreens()
        #expect(!panel.isVisible)
        #expect(coordinator.persistentPanelDisplayIDs.isEmpty)
        #expect(petWindows.allSatisfy { $0.window?.isVisible == false })
        coordinator.setHoverActivationSuspended(false)
        #expect(panel.isVisible == pinned)
        #expect(coordinator.persistentPanelDisplayIDs == (pinned ? [8] : [7, 8]))
    }

    @Test(arguments: IslandEdge.allCases)
    func popoverArrowGapsRemainInteractiveOnEveryEdge(edge: IslandEdge) {
        let island = CGRect(x: 400, y: 400, width: 200, height: 200)
        let anchor: CGRect
        let popover: CGRect
        let bridge: CGPoint
        let outside: CGPoint
        switch edge {
        case .top:
            anchor = CGRect(x: 470, y: 580, width: 40, height: 20)
            popover = CGRect(x: 440, y: 612, width: 160, height: 100)
            bridge = CGPoint(x: 490, y: 606)
            outside = CGPoint(x: 450, y: 606)
        case .bottom:
            anchor = CGRect(x: 470, y: 400, width: 40, height: 20)
            popover = CGRect(x: 440, y: 288, width: 160, height: 100)
            bridge = CGPoint(x: 490, y: 394)
            outside = CGPoint(x: 450, y: 394)
        case .left:
            anchor = CGRect(x: 400, y: 470, width: 20, height: 40)
            popover = CGRect(x: 288, y: 440, width: 100, height: 160)
            bridge = CGPoint(x: 394, y: 490)
            outside = CGPoint(x: 394, y: 450)
        case .right:
            anchor = CGRect(x: 580, y: 470, width: 20, height: 40)
            popover = CGRect(x: 612, y: 440, width: 100, height: 160)
            bridge = CGPoint(x: 606, y: 490)
            outside = CGPoint(x: 606, y: 450)
        }
        #expect(OverlayCoordinator.containsPopoverAttachment(bridge, island: island, popover: popover, anchor: anchor))
        #expect(!OverlayCoordinator.containsPopoverAttachment(outside, island: island, popover: popover, anchor: anchor))
        let distant = popover.offsetBy(dx: edge == .left ? -100 : edge == .right ? 100 : 0,
                                      dy: edge == .bottom ? -100 : edge == .top ? 100 : 0)
        #expect(!OverlayCoordinator.containsPopoverAttachment(bridge, island: island, popover: distant, anchor: anchor))
    }

    @Test
    func cameraStatusUpdatesDetailsWithoutUsingTheCustomNaturalLength() throws {
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content,
            layoutEngine: ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(layoutStyle: .pill)))
        coordinator.screenSnapshotProvider = { [screen] }
        coordinator.start()
        defer { coordinator.stop() }
        coordinator.selectActiveDisplay(at: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
        let original = try #require(coordinator.activeLayout)
        coordinator.updateCompactStatus(expandsForDetailedStatus: true, compactStatusLength: 32)
        let detailed = try #require(coordinator.activeLayout)
        #expect(detailed.collapsedFrame.width == 380)
        #expect(detailed.collapsedFrame.midX == original.collapsedFrame.midX)
        #expect(detailed.collapsedFrame.midY == original.collapsedFrame.midY)
        coordinator.updateCompactStatus(expandsForDetailedStatus: false, compactStatusLength: 32)
        #expect(coordinator.activeLayout?.collapsedFrame == original.collapsedFrame)
    }
}
