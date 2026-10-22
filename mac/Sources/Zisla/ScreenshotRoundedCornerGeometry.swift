import CoreGraphics

enum ScreenshotRoundedCornerGeometry {
    static let handleOffset: CGFloat = 18

    static func maximumRadius(for size: CGSize) -> CGFloat {
        guard size.width.isFinite, size.height.isFinite else { return 0 }
        return max(0, min(size.width, size.height) / 2)
    }

    static func clampedRadius(_ radius: CGFloat, in size: CGSize) -> CGFloat {
        guard radius.isFinite else { return 0 }
        return min(max(radius, 0), maximumRadius(for: size))
    }

    static func handlePosition(in selection: CGRect, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: selection.minX + clampedRadius(radius, in: selection.size),
            y: selection.minY - handleOffset
        )
    }
}
