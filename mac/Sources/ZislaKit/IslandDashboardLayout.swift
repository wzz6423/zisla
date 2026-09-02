import CoreGraphics

/// Geometry of the island's solid-black crown and its fade into the frosted glass below.
///
/// The crown adapts to the surface height: surfaces at or above `crownFloorHeight` use
/// the full-size crown; shorter surfaces (such as the empty dashboard) shorten the crown
/// so its gradient completes before the rounded bottom edge.
public enum IslandCrownGeometry: Sendable {
    /// Solid-black section at full size: covers NowPlayingHeader (72pt + padding) and toolbar (30pt).
    public static let crownHeight: CGFloat = 132
    /// Black → frosted blend below the solid section. The transparent style uses the taller
    /// blend, so the floor is derived from it to keep both visual styles fully rendered.
    public static let crownBlendHeight: CGFloat = 64

    /// Shortest expanded surface that still shows the complete crown → glass transition.
    public static var crownFloorHeight: CGFloat { crownHeight + crownBlendHeight }

    /// Minimum solid crown height: must cover the white-text chrome (content inset + media
    /// header + toolbar) to preserve legibility. Below this, text would bleed into the blend.
    public static let minimumSolidHeight: CGFloat = 114

    /// Computes crown heights that fit inside the visible surface while preserving as much
    /// solid chrome and blend as the available height allows.
    public static func crownMetrics(
        forSurfaceHeight surfaceHeight: CGFloat,
        blendHeight: CGFloat
    ) -> (solidHeight: CGFloat, blendHeight: CGFloat) {
        let availableHeight = max(0, surfaceHeight)
        let requestedBlendHeight = max(0, blendHeight)
        let fullHeight = crownHeight + requestedBlendHeight
        guard availableHeight < fullHeight else {
            return (crownHeight, requestedBlendHeight)
        }

        let solidFloor = min(minimumSolidHeight, availableHeight)
        let solidHeight = min(
            crownHeight,
            max(solidFloor, availableHeight - requestedBlendHeight)
        )
        let visibleBlendHeight = min(
            requestedBlendHeight,
            max(0, availableHeight - solidHeight)
        )
        return (solidHeight, visibleBlendHeight)
    }
}

/// Derives the dashboard's expanded height from what `IslandDashboardView` actually renders.
///
/// Kept next to the crown geometry (rather than inline in the view layer) so the height
/// contract is unit-testable: the panel is resized by an AppKit publisher that cannot
/// observe SwiftUI's rendered layout, so this arithmetic must mirror the view exactly.
public enum IslandDashboardLayout: Sendable {
    /// Toolbar row height.
    public static let toolbarHeight: CGFloat = 30
    /// Top inset above the first chrome row (media header when present, otherwise the toolbar).
    public static let contentTopInset: CGFloat = 8
    /// Gap between the toolbar and the module content below it.
    public static let toolbarBottomInset: CGFloat = 7
    /// Inset above the module content, matching `IslandSurfaceGeometry.moduleInset`.
    public static let moduleTopInset: CGFloat = 12
    /// Inset below the module content, matching `IslandSurfaceGeometry.moduleInset`.
    public static let moduleBottomInset: CGFloat = 12
    /// `NowPlayingHeader` renders at a fixed 72pt, plus its 4pt bottom padding.
    public static let mediaHeaderHeight: CGFloat = 76
    /// Fixed activity-card height, including padding and the media artwork row.
    public static let cardHeight: CGFloat = 64
    /// Vertical spacing between card rows in the grid.
    public static let cardRowSpacing: CGFloat = 8
    /// Vertical padding the card grid wrapper adds once, above and below the whole grid.
    public static let cardGridVerticalPadding: CGFloat = 7
    /// Cards are laid out in two columns once more than one is active.
    public static let cardColumnCount = 2

    /// Chrome that is always present: top inset + toolbar + its bottom gap + module insets.
    public static var chromeHeight: CGFloat {
        contentTopInset
            + toolbarHeight
            + toolbarBottomInset
            + moduleTopInset
            + moduleBottomInset
    }

    public static func cardRowCount(forCardCount cardCount: Int) -> Int {
        guard cardCount > 0 else { return 0 }
        return (cardCount + cardColumnCount - 1) / cardColumnCount
    }

    /// Height of the rendered card grid, including the wrapper padding that applies once.
    public static func cardGridHeight(forCardCount cardCount: Int) -> CGFloat {
        let rows = cardRowCount(forCardCount: cardCount)
        guard rows > 0 else { return 0 }
        return cardGridVerticalPadding * 2
            + CGFloat(rows) * cardHeight
            + CGFloat(rows - 1) * cardRowSpacing
    }

    /// Expanded island height for the dashboard. An empty dashboard stops after the fixed
    /// chrome; active cards retain the crown floor so the frosted body stays visible.
    public static func contentHeight(cardCount: Int) -> CGFloat {
        let height = chromeHeight
            + mediaHeaderHeight
            + cardGridHeight(forCardCount: cardCount)
        guard cardCount > 0 else { return height }
        return max(height, IslandCrownGeometry.crownFloorHeight)
    }
}
