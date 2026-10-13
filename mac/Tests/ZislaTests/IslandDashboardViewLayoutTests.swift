 import Foundation
import Testing

@testable import Zisla

struct IslandDashboardViewLayoutTests {
    @Test
    func dashboardCapsHeightAtKeyboardSurfaceHeight() {
        let layout = IslandModuleLayout.resolved(for: .dashboard, dashboardCardCount: 100)

        #expect(layout.islandSize.height == IslandModuleLayout.keyboardSound.islandSize.height)
        #expect(layout.panelSize.height == IslandModuleLayout.keyboardSound.panelSize.height)
    }

}
