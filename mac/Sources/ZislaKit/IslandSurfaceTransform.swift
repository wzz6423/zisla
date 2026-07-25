import CoreGraphics

/// 让展开面在缩放期间保持顶部中心不动，避免视觉上从左上角飞入。
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
}
