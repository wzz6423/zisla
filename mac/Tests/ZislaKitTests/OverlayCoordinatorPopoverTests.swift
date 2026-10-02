import AppKit
import Testing
@testable import ZislaKit

@MainActor
struct OverlayCoordinatorPopoverTests {
    @Test
    func pointerTravelsAcrossTheArrowAndPopoverThenCollapsesOutsideBoth() throws {
        let fixture = try Fixture()
        defer { fixture.coordinator.stop() }
        fixture.register()

        fixture.coordinator.handlePointer(at: fixture.triggerPoint)
        fixture.coordinator.handlePointer(at: fixture.arrowPoint)
        #expect(!fixture.panel.ignoresMouseEvents)
        fixture.coordinator.handlePointer(at: fixture.popoverPoint)
        #expect(!fixture.panel.ignoresMouseEvents)
        #expect(!fixture.panel.isPinned)
        fixture.coordinator.handlePointer(at: fixture.outsidePoint)
        #expect(fixture.panel.ignoresMouseEvents)

        fixture.coordinator.handlePointer(at: fixture.popoverPoint)
        #expect(fixture.panel.ignoresMouseEvents, "A stale popover must not expand a collapsed island")
        fixture.coordinator.handlePointer(at: fixture.triggerPoint)
        fixture.coordinator.handlePointer(at: fixture.popoverPoint)
        #expect(fixture.panel.ignoresMouseEvents, "A previous presentation's region cannot survive collapse")
        fixture.register()
        fixture.coordinator.handlePointer(at: fixture.triggerPoint)
        fixture.coordinator.handlePointer(at: fixture.popoverPoint)
        #expect(fixture.panel.ignoresMouseEvents, "A late layout callback cannot re-register a closed presentation")
    }

    @Test
    func closingOrHidingThePopoverRevalidatesThePointer() throws {
        for unregister in [false, true] {
            let fixture = try Fixture()
            defer { fixture.coordinator.stop() }
            fixture.register()
            fixture.coordinator.handlePointer(at: fixture.popoverPoint)
            if unregister {
                fixture.coordinator.setTransientInteractionWindow(nil, anchor: nil, id: fixture.id)
            } else {
                fixture.popover.fixtureVisible = false
                fixture.register()
            }
            #expect(fixture.panel.ignoresMouseEvents)
        }
    }

    @Test
    func movingThePopoverDropsItsOldFrameAndDoesNotMakeABoundingBox() throws {
        let fixture = try Fixture()
        defer { fixture.coordinator.stop() }
        fixture.register()
        fixture.coordinator.handlePointer(at: fixture.popoverPoint)
        fixture.popover.setFrameOrigin(CGPoint(x: fixture.popover.frame.minX + 400, y: fixture.popover.frame.minY))
        fixture.register()
        #expect(fixture.panel.ignoresMouseEvents)

        fixture.coordinator.handlePointer(at: fixture.triggerPoint)
        fixture.register()
        fixture.coordinator.handlePointer(at: CGPoint(x: fixture.anchorFrame.midX + 200, y: fixture.arrowPoint.y))
        #expect(fixture.panel.ignoresMouseEvents)
    }

    @Test
    func unrelatedWindowAndOtherDisplayNeverKeepTheIslandExpanded() throws {
        let fixture = try Fixture()
        defer { fixture.coordinator.stop() }
        let unrelated = NSView(frame: fixture.anchor.frame)
        let unrelatedWindow = NSWindow(contentRect: fixture.panel.frame, styleMask: .borderless, backing: .buffered, defer: true)
        unrelatedWindow.isReleasedWhenClosed = false
        unrelatedWindow.contentView = unrelated
        defer { unrelatedWindow.close() }
        fixture.coordinator.setTransientInteractionWindow(fixture.popover, anchor: unrelated, id: fixture.id)
        fixture.coordinator.handlePointer(at: fixture.popoverPoint)
        #expect(fixture.panel.ignoresMouseEvents)

        fixture.coordinator.handlePointer(at: fixture.triggerPoint)
        fixture.popover.setFrameOrigin(CGPoint(x: 40_000, y: 100))
        fixture.register()
        fixture.coordinator.handlePointer(at: CGPoint(x: 40_100, y: 200))
        #expect(fixture.panel.ignoresMouseEvents)

        fixture.coordinator.handlePointer(at: fixture.triggerPoint)
        fixture.popover.setFrameOrigin(CGPoint(x: fixture.popoverPoint.x - 146, y: fixture.popoverPoint.y - 100))
        fixture.anchor.setFrameOrigin(CGPoint(x: 5_000, y: 5_000))
        fixture.register()
        fixture.coordinator.handlePointer(at: fixture.popoverPoint)
        #expect(fixture.panel.ignoresMouseEvents, "An anchor moved outside the island cannot leave an active region")
    }

    @Test
    func destroyedPopoverDoesNotLeaveARegionOrRetainTheWindow() throws {
        let fixture = try Fixture()
        defer { fixture.coordinator.stop() }
        weak var weakWindow: PopoverWindowFixture?
        autoreleasepool {
            let window = PopoverWindowFixture(frame: fixture.popover.frame)
            weakWindow = window
            fixture.coordinator.setTransientInteractionWindow(window, anchor: fixture.anchor, id: fixture.id)
            fixture.coordinator.handlePointer(at: fixture.popoverPoint)
        }
        #expect(weakWindow == nil)
        fixture.coordinator.handlePointer(at: fixture.popoverPoint)
        #expect(fixture.panel.ignoresMouseEvents)
    }

    @Test(arguments: [false, true])
    func stoppingOrRemovingTheDisplayClearsTransientWindows(stop: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.coordinator.stop() }
        fixture.register()
        fixture.coordinator.handlePointer(at: fixture.popoverPoint)
        if stop {
            fixture.coordinator.stop()
            fixture.coordinator.start()
        } else {
            fixture.coordinator.updateScreens([], repositionVisiblePanel: false)
        }
        fixture.coordinator.updateScreens([fixture.screen], repositionVisiblePanel: false)
        fixture.coordinator.handlePointer(at: fixture.triggerPoint)
        fixture.coordinator.handlePointer(at: fixture.popoverPoint)
        #expect(fixture.panel.ignoresMouseEvents)
    }

    @Test
    func attachmentBridgeIsLimitedToTheAnchorAndShortVerticalGap() {
        let island = CGRect(x: 100, y: 400, width: 600, height: 200)
        let anchor = CGRect(x: 500, y: 400, width: 50, height: 20)
        let popover = CGRect(x: 400, y: 188, width: 300, height: 200)
        #expect(OverlayCoordinator.containsPopoverAttachment(CGPoint(x: 525, y: 394), island: island, popover: popover, anchor: anchor))
        #expect(!OverlayCoordinator.containsPopoverAttachment(CGPoint(x: 425, y: 394), island: island, popover: popover, anchor: anchor))
        #expect(!OverlayCoordinator.containsPopoverAttachment(CGPoint(x: 525, y: 350), island: island, popover: popover.offsetBy(dx: 0, dy: -100), anchor: anchor))
        #expect(!OverlayCoordinator.containsPopoverAttachment(CGPoint(x: 525, y: 394), island: island, popover: popover.offsetBy(dx: 500, dy: 0), anchor: anchor))
    }

    @Test(arguments: ["pointer", "menuBar", "screenRemoval"])
    func movingToAnotherDisplayInvalidatesThePreviousPresentation(route: String) throws {
        let fixture = try Fixture()
        defer { fixture.coordinator.stop() }
        let other = ScreenSnapshot(displayID: 92,
                                   frame: fixture.screen.frame.offsetBy(dx: 1_440, dy: 0),
                                   visibleFrame: fixture.screen.visibleFrame.offsetBy(dx: 1_440, dy: 0))
        fixture.coordinator.updateScreens([fixture.screen, other], repositionVisiblePanel: false)
        let otherLayout = try #require(fixture.coordinator.layouts.first { $0.displayID == other.displayID })
        let otherTrigger = CGPoint(x: otherLayout.triggerFrame.midX, y: otherLayout.triggerFrame.midY)
        fixture.register()
        fixture.coordinator.handlePointer(at: fixture.popoverPoint)

        switch route {
        case "pointer": fixture.coordinator.handlePointer(at: otherTrigger)
        case "menuBar": fixture.coordinator.showExpanded(at: otherTrigger)
        default:
            fixture.coordinator.updateScreens([other])
            fixture.coordinator.updateScreens([fixture.screen, other], repositionVisiblePanel: false)
        }
        fixture.coordinator.handlePointer(at: fixture.triggerPoint)
        fixture.coordinator.handlePointer(at: fixture.popoverPoint)
        #expect(fixture.panel.ignoresMouseEvents,
                "Returning to a display must not reactivate its previous popover region")
    }

    @Test
    func theFullPopoverFrameRemainsInteractiveBeyondTheIslandRightAndBottomEdges() throws {
        let fixture = try Fixture()
        defer { fixture.coordinator.stop() }
        fixture.popover.setFrameOrigin(CGPoint(x: fixture.panel.frame.maxX - 40,
                                               y: fixture.panel.frame.minY - 200))
        fixture.register()
        let bottomRight = CGPoint(x: fixture.popover.frame.maxX - 1, y: fixture.popover.frame.minY + 1)
        #expect(!fixture.panel.frame.contains(bottomRight))
        fixture.coordinator.handlePointer(at: bottomRight)
        #expect(!fixture.panel.ignoresMouseEvents)
        fixture.coordinator.handlePointer(at: CGPoint(x: bottomRight.x + 2, y: bottomRight.y))
        #expect(fixture.panel.ignoresMouseEvents)
    }

    @MainActor
    private final class Fixture {
        let coordinator: OverlayCoordinator
        let screen: ScreenSnapshot
        let panel: IslandPanel
        let anchor: NSView
        let anchorFrame: CGRect
        let popover: PopoverWindowFixture
        let id = UUID()
        let triggerPoint: CGPoint
        let arrowPoint: CGPoint
        let popoverPoint: CGPoint
        let outsidePoint: CGPoint

        init() throws {
            let content = NSView()
            coordinator = OverlayCoordinator(contentView: content, collapseDelay: .zero)
            coordinator.start()
            screen = ScreenSnapshot(displayID: 91, frame: CGRect(x: 20_000, y: 0, width: 1_440, height: 900),
                                        visibleFrame: CGRect(x: 20_000, y: 0, width: 1_440, height: 876))
            coordinator.updateScreens([screen], repositionVisiblePanel: false)
            let layout = try #require(coordinator.layouts.first)
            triggerPoint = CGPoint(x: layout.triggerFrame.midX, y: layout.triggerFrame.midY)
            coordinator.handlePointer(at: triggerPoint)
            panel = try #require(content.window as? IslandPanel)
            anchor = NSView(frame: CGRect(x: 100, y: 0, width: 60, height: 20))
            content.addSubview(anchor)
            anchorFrame = panel.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            popover = PopoverWindowFixture(frame: CGRect(x: anchorFrame.midX - 146,
                y: layout.expandedFrame.minY - 212, width: 292, height: 200))
            arrowPoint = CGPoint(x: anchorFrame.midX, y: layout.expandedFrame.minY - 6)
            popoverPoint = CGPoint(x: popover.frame.midX, y: popover.frame.midY)
            outsidePoint = CGPoint(x: screen.frame.minX + 10, y: 100)
        }

        func register() {
            coordinator.setTransientInteractionWindow(popover, anchor: anchor, id: id)
        }
    }
}

@MainActor
private final class PopoverWindowFixture: NSWindow {
    var fixtureVisible = true
    override var isVisible: Bool { fixtureVisible }

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
        isReleasedWhenClosed = false
    }
}
