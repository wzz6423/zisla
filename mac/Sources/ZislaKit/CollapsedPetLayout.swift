import CoreGraphics
import ZislaCore

public enum CollapsedPetLayout {
    public static let maximumPetSize: CGFloat = 24
    public static let outerGap: CGFloat = 4
    public static let sideSlotWidth = maximumPetSize + outerGap * 2

    public static func containerSize(
        for compactBarSize: CGSize,
        edge: IslandEdge = .top
    ) -> CGSize {
        return CGSize(
            width: compactBarSize.width + (edge.isVertical ? 0 : sideSlotWidth * 2),
            height: compactBarSize.height + (edge.isVertical ? sideSlotWidth * 2 : 0)
        )
    }

    public static func frame(
        for layout: ScreenOverlayLayout,
        compactBarFrame: CGRect? = nil
    ) -> CGRect {
        let compactBarFrame = compactBarFrame ?? layout.collapsedFrame
        let edge = layout.style == .pill ? layout.edge : .top
        var size = containerSize(for: compactBarFrame.size, edge: edge)
        if layout.style == .pill {
            size.width = min(size.width, layout.screenFrame.width)
            size.height = min(size.height, layout.screenFrame.height)
        }
        var frame = CGRect(
            x: compactBarFrame.midX - size.width / 2,
            y: compactBarFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        if layout.style == .pill {
            frame.origin.x = min(layout.screenFrame.maxX - size.width, max(layout.screenFrame.minX, frame.minX))
            frame.origin.y = min(layout.screenFrame.maxY - size.height, max(layout.screenFrame.minY, frame.minY))
        }
        return frame
    }

    public static func petFrame(
        for layout: ScreenOverlayLayout,
        compactBarFrame: CGRect? = nil,
        side: PetSide
    ) -> CGRect? {
        let bar = compactBarFrame ?? layout.collapsedFrame
        let isVertical = layout.style == .pill && layout.edge.isVertical
        let thickness = isVertical ? bar.width : bar.height
        let inset = min(4, max(2, thickness * 0.1))
        let size = min(maximumPetSize, max(0, thickness - inset * 2))
        guard size > 0 else { return nil }
        let centerOffset = outerGap + maximumPetSize / 2
        func candidate(for side: PetSide) -> CGRect {
            if isVertical {
                return CGRect(
                    x: bar.midX - size / 2,
                    y: (side == .left ? bar.maxY + centerOffset : bar.minY - centerOffset) - size / 2,
                    width: size,
                    height: size
                )
            }
            return CGRect(
                x: (side == .left ? bar.minX - centerOffset : bar.maxX + centerOffset) - size / 2,
                y: bar.maxY - inset - size,
                width: size,
                height: size
            )
        }
        let preferred = candidate(for: side)
        guard layout.style == .pill else { return preferred }
        if layout.screenFrame.contains(preferred) { return preferred }
        let opposite = candidate(for: side == .left ? .right : .left)
        return layout.screenFrame.contains(opposite) ? opposite : nil
    }
}
