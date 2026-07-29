import CoreGraphics
import Testing
@testable import ZislaKit

/// Regression: IslandDashboardLayout.chromeHeight was missing the module top inset (12pt),
/// causing contentHeight() to underestimate by 12pt and clip the bottom of rendered cards.
///
/// The layout arithmetic must match what IslandRootView actually renders:
///   - contentTopInset (8) + NowPlayingHeader (72+4=76) + toolbar (30) + toolbarBottomInset (7)
///   - **moduleTopInset (12)** + card grid + **moduleBottomInset (12)**
///
/// The old formula only counted moduleBottomInset, so the resolved island height was 12pt short.
struct IslandDashboardLayoutRegressionTests {
    @Test
    func chromeIncludesBothModuleInsets() {
        // chromeHeight must account for the module region's top AND bottom padding (12pt each).
        // The old value was 57 (8 + 30 + 7 + 12); the correct value is 69 (57 + 12).
        let moduleTopInset: CGFloat = 12  // IslandSurfaceGeometry.moduleInset
        let expected = IslandDashboardLayout.contentTopInset
            + IslandDashboardLayout.toolbarHeight
            + IslandDashboardLayout.toolbarBottomInset
            + IslandDashboardLayout.moduleBottomInset
            + moduleTopInset  // ← was missing

        #expect(IslandDashboardLayout.chromeHeight == expected)
        #expect(IslandDashboardLayout.chromeHeight == 69)
    }

    @Test(arguments: [1, 2, 3, 5])
    func contentHeightMatchesRenderedStack(cardCount: Int) {
        // The resolved height must fit the full rendered stack without clipping:
        //   header + toolbar + moduleTopInset + cardGrid + moduleBottomInset.
        let moduleTopInset: CGFloat = 12
        let rendered = IslandDashboardLayout.contentTopInset
            + IslandDashboardLayout.mediaHeaderHeight
            + IslandDashboardLayout.toolbarHeight
            + IslandDashboardLayout.toolbarBottomInset
            + moduleTopInset
            + IslandDashboardLayout.cardGridHeight(forCardCount: cardCount)
            + IslandDashboardLayout.moduleBottomInset

        let resolved = IslandDashboardLayout.contentHeight(cardCount: cardCount)

        // When rendered > crownFloor, the resolved height clamps to max(chrome+header+grid, floor).
        // The chrome+header+grid sum must equal the rendered stack.
        let floor = IslandCrownGeometry.crownFloorHeight
        #expect(resolved == max(rendered, floor))
    }
}
