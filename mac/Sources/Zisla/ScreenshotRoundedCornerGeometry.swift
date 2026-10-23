import CoreGraphics

enum ScreenshotRoundedCornerGeometry {
    static let handleOffset: CGFloat = 18
    static let handleSize: CGFloat = 16

    static func maximumRadius(for size: CGSize) -> CGFloat {
        guard size.width.isFinite, size.height.isFinite else { return 0 }
        return max(0, min(size.width, size.height) / 2)
    }

    static func clampedRadius(_ radius: CGFloat, in size: CGSize) -> CGFloat {
        guard radius.isFinite else { return 0 }
        return min(max(radius, 0), maximumRadius(for: size))
    }

    static func handlePosition(in selection: CGRect, radius: CGFloat, within bounds: CGRect) -> CGPoint {
        let halfSize = handleSize / 2
        let above = selection.minY - handleOffset
        let y = above - halfSize >= bounds.minY ? above : selection.minY + handleOffset
        var position = CGPoint(
            x: min(max(selection.minX + clampedRadius(radius, in: selection.size), bounds.minX + halfSize), bounds.maxX - halfSize),
            y: min(y, bounds.maxY - halfSize)
        )
        let frame = CGRect(x: position.x - halfSize, y: position.y - halfSize, width: handleSize, height: handleSize)
        if ScreenshotSelectionHandle.allCases.contains(where: { frame.contains(ScreenshotSelectionGeometry.position(of: $0, in: selection)) }) {
            if selection.maxX + handleOffset + halfSize <= bounds.maxX {
                position.x = selection.maxX + handleOffset
            } else if selection.minX - handleOffset - halfSize >= bounds.minX {
                position.x = selection.minX - handleOffset
            } else {
                position.x = selection.minX + handleOffset
            }
        }
        return position
    }
}
