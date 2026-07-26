import CoreGraphics
import Testing
@testable import ZislaKit

/// The dashboard is the only module sized from its content, so it is the only one that can
/// shrink inside the island's solid-black crown. These tests pin that floor: without it the
/// island renders as a plain black slab with no frosted glass and no bottom corner radius.
struct IslandDashboardLayoutTests {
    @Test
    func crownFloorCoversTheSolidCrownAndItsBlend() {
        #expect(
            IslandCrownGeometry.crownFloorHeight
                == IslandCrownGeometry.crownHeight + IslandCrownGeometry.crownBlendHeight
        )
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6])
    func activeDashboardHeightNeverSinksInsideTheCrown(cardCount: Int) {
        let height = IslandDashboardLayout.contentHeight(cardCount: cardCount)

        #expect(height >= IslandCrownGeometry.crownFloorHeight)
    }

    @Test
    func oneCardIncludesTheFixedHeader() {
        let height = IslandDashboardLayout.contentHeight(cardCount: 1)

        #expect(
            height
                == IslandDashboardLayout.chromeHeight
                    + IslandDashboardLayout.mediaHeaderHeight
                    + IslandDashboardLayout.cardGridHeight(forCardCount: 1)
        )
    }

    @Test
    func emptyDashboardFitsTheRenderedChromeWithoutAnEmptyBody() {
        let height = IslandDashboardLayout.contentHeight(cardCount: 0)

        #expect(
            height
                == IslandDashboardLayout.chromeHeight
                    + IslandDashboardLayout.mediaHeaderHeight
        )
        #expect(height < IslandCrownGeometry.crownFloorHeight)
    }

    @Test(arguments: [60.0, IslandCrownGeometry.crownBlendHeight])
    func crownStaysFullSizeAboveTheFloor(blendHeight: CGFloat) {
        let activeHeight = IslandDashboardLayout.contentHeight(cardCount: 1)
        let metrics = IslandCrownGeometry.crownMetrics(
            forSurfaceHeight: activeHeight,
            blendHeight: blendHeight
        )

        #expect(metrics.solidHeight == IslandCrownGeometry.crownHeight)
        #expect(metrics.blendHeight == blendHeight)
    }

    @Test(arguments: [0.0, 100.0, IslandCrownGeometry.minimumSolidHeight])
    func crownMetricsNeverExceedTheSurface(surfaceHeight: CGFloat) {
        let metrics = IslandCrownGeometry.crownMetrics(
            forSurfaceHeight: surfaceHeight,
            blendHeight: 60
        )

        #expect(metrics.solidHeight >= 0)
        #expect(metrics.blendHeight >= 0)
        #expect(metrics.solidHeight + metrics.blendHeight <= surfaceHeight)
    }

    /// The compressed crown may not expose white chrome text to the gradient: the solid floor
    /// has to reach at least the bottom of the toolbar. Derived from the layout constants rather
    /// than restated as a literal, so changing either side fails instead of silently drifting.
    @Test
    func minimumSolidCoversTheWhiteTextChrome() {
        let textFloor = IslandDashboardLayout.contentTopInset
            + IslandDashboardLayout.mediaHeaderHeight
            + IslandDashboardLayout.toolbarHeight

        #expect(IslandCrownGeometry.minimumSolidHeight == textFloor)
    }

    /// The empty dashboard is the surface that regressed: its compact content height is shorter
    /// than the fixed crown, so the gradient was clipped before reaching the rounded bottom edge.
    @Test(arguments: [60.0, IslandCrownGeometry.crownBlendHeight])
    func compressedCrownNeverOverrunsTheEmptyDashboard(blendHeight: CGFloat) {
        let surfaceHeight = IslandDashboardLayout.contentHeight(cardCount: 0)
        let metrics = IslandCrownGeometry.crownMetrics(
            forSurfaceHeight: surfaceHeight,
            blendHeight: blendHeight
        )

        #expect(metrics.solidHeight == IslandCrownGeometry.minimumSolidHeight)
        #expect(metrics.solidHeight + metrics.blendHeight == surfaceHeight)
        #expect(metrics.blendHeight > 0)
    }

    @Test
    func gridPaddingIsCountedOnceRatherThanPerRow() {
        // The old formula folded the wrapper's 14pt padding into a 72pt per-row constant, so every
        // extra row over-allocated by 14pt and left dead space under the last card.
        let twoRows = IslandDashboardLayout.cardGridHeight(forCardCount: 3)
        let threeRows = IslandDashboardLayout.cardGridHeight(forCardCount: 5)

        #expect(twoRows == CGFloat(14 + 58 * 2 + 8))
        #expect(threeRows == CGFloat(14 + 58 * 3 + 8 * 2))
        #expect(threeRows - twoRows == IslandDashboardLayout.cardHeight + IslandDashboardLayout.cardRowSpacing)
    }

    @Test
    func cardsWrapIntoTwoColumns() {
        #expect(IslandDashboardLayout.cardRowCount(forCardCount: 0) == 0)
        #expect(IslandDashboardLayout.cardRowCount(forCardCount: 1) == 1)
        #expect(IslandDashboardLayout.cardRowCount(forCardCount: 2) == 1)
        #expect(IslandDashboardLayout.cardRowCount(forCardCount: 3) == 2)
        #expect(IslandDashboardLayout.cardRowCount(forCardCount: 4) == 2)
        #expect(IslandDashboardLayout.cardRowCount(forCardCount: 5) == 3)
    }

    @Test
    func heightGrowsOnceContentExceedsTheFloor() {
        let floor = IslandCrownGeometry.crownFloorHeight
        let fiveCards = IslandDashboardLayout.contentHeight(cardCount: 5)

        #expect(fiveCards > floor)
        #expect(
            fiveCards
                == IslandDashboardLayout.chromeHeight
                    + IslandDashboardLayout.mediaHeaderHeight
                    + IslandDashboardLayout.cardGridHeight(forCardCount: 5)
        )
    }

    @Test
    func chromeMatchesTheRenderedToolbarStack() {
        // 8pt top inset + 30pt toolbar + 7pt gap + 12pt module insets.
        #expect(IslandDashboardLayout.chromeHeight == 69)
    }

    /// The crown chrome (top inset + media header + toolbar + its gap) is laid out above the
    /// module region and cannot compress. If a resolved dashboard height were shorter than that
    /// stack, the chrome would overflow its surface frame and — before the frame was made
    /// top-aligned — get centered, lifting the whole header above the island and sliding it back
    /// down as the resize spring ran.
    @Test(arguments: [0, 1, 2, 3, 4, 5, 6])
    func heightAlwaysFitsTheIncompressibleChrome(cardCount: Int) {
        let fixedChrome = IslandDashboardLayout.contentTopInset
            + IslandDashboardLayout.mediaHeaderHeight
            + IslandDashboardLayout.toolbarHeight
            + IslandDashboardLayout.toolbarBottomInset

        #expect(IslandDashboardLayout.contentHeight(cardCount: cardCount) >= fixedChrome)
    }
}
