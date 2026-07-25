import AppKit
import CoreGraphics
import Testing
@testable import ZislaKit

struct OverlayCoordinatorTests {
    @Test @MainActor
    func selectingScreenUnderMenuBarClickReplacesPreviousActiveDisplay() {
        let coordinator = OverlayCoordinator(contentView: NSView())
        coordinator.updateScreens([
            ScreenSnapshot(
                displayID: 1,
                frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
            ),
            ScreenSnapshot(
                displayID: 2,
                frame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
                visibleFrame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_056)
            ),
        ], repositionVisiblePanel: false)

        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.selectActiveDisplay(at: CGPoint(x: 2_400, y: 540))

        #expect(coordinator.activeDisplayID == 2)
    }
}
