import CoreGraphics

/// Keeps the top center of the expanded surface stationary during scaling, preventing it from flying in from the top-left corner.
public struct IslandSurfaceTransform: Equatable, Sendable {
    public let scaleX: CGFloat
    public let scaleY: CGFloat

    public init(collapsedSize: CGSize, expandedSize: CGSize, isCollapsed: Bool) {
        self.init(
            collapsedSize: collapsedSize,
            expandedSize: expandedSize,
            revealProgress: isCollapsed ? 0 : 1
        )
    }

    public init(
        collapsedSize: CGSize,
        expandedSize: CGSize,
        revealProgress: CGFloat
    ) {
        let progress = min(1, max(0, revealProgress))
        let collapsedScaleX = min(1, max(0, collapsedSize.width / max(1, expandedSize.width)))
        let collapsedScaleY = min(1, max(0, collapsedSize.height / max(1, expandedSize.height)))
        scaleX = collapsedScaleX + (1 - collapsedScaleX) * progress
        scaleY = collapsedScaleY + (1 - collapsedScaleY) * progress
    }

    public func visibleFrame(in expandedSize: CGSize) -> CGRect {
        CGRect(
            x: (expandedSize.width - expandedSize.width * scaleX) / 2,
            y: 0,
            width: expandedSize.width * scaleX,
            height: expandedSize.height * scaleY
        )
    }

    /// Keeps the expanded surface inside the panel frame without scaling its controls or typography.
    public static func fittingSize(contentSize: CGSize, availableSize: CGSize) -> CGSize {
        CGSize(
            width: min(max(0, contentSize.width), max(0, availableSize.width)),
            height: min(max(0, contentSize.height), max(0, availableSize.height))
        )
    }
}
