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
        var position = CGPoint(
            x: selection.minX + max(handleOffset, clampedRadius(radius, in: selection.size)),
            y: min(max(selection.minY, bounds.minY + halfSize), bounds.maxY - halfSize)
        )
        for x in [position.x, selection.midX - handleOffset, selection.maxX + handleOffset, selection.minX - handleOffset] {
            position.x = min(max(x, bounds.minX + halfSize), bounds.maxX - halfSize)
            let frame = CGRect(x: position.x - halfSize, y: position.y - halfSize, width: handleSize, height: handleSize)
            if !ScreenshotSelectionHandle.allCases.contains(where: { frame.contains(ScreenshotSelectionGeometry.position(of: $0, in: selection)) }) {
                return position
            }
        }
        return position
    }
}
