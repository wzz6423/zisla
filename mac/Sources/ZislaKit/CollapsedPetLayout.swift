import CoreGraphics
import ZislaCore

public enum CollapsedPetLayout {
    public static let maximumPetSize: CGFloat = 24
    public static let outerGap: CGFloat = 4
    public static let sideSlotWidth = maximumPetSize + outerGap * 2

    public static func containerSize(
        for compactBarSize: CGSize,
        edge: IslandEdge = .top,
        style: IslandLayoutStyle = .notch,
        petAspectRatio: CGFloat = 1
    ) -> CGSize {
        let thickness = edge.isVertical ? compactBarSize.width : compactBarSize.height
        let height = min(thickness, maximumPetSize)
        let petWidth = height * petAspectRatio
        let slotWidth = style == .pill ? (edge.isVertical ? height : petWidth) + outerGap * 2 : sideSlotWidth
        return CGSize(
            width: (style == .pill && edge.isVertical ? max(compactBarSize.width, petWidth) : compactBarSize.width)
                + (edge.isVertical ? 0 : slotWidth * 2),
            height: compactBarSize.height + (edge.isVertical ? slotWidth * 2 : 0)
        )
    }

    public static func frame(
        for layout: ScreenOverlayLayout,
        compactBarFrame: CGRect? = nil,
        petAspectRatio: CGFloat = 1
    ) -> CGRect {
        let compactBarFrame = compactBarFrame ?? layout.collapsedFrame
        let edge = layout.style == .pill ? layout.edge : .top
        var size = containerSize(for: compactBarFrame.size, edge: edge, style: layout.style, petAspectRatio: petAspectRatio)
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
        petAspectRatio: CGFloat = 1,
        side: PetSide
    ) -> CGRect? {
        let bar = compactBarFrame ?? layout.collapsedFrame
        let isVertical = layout.style == .pill && layout.edge.isVertical
        let thickness = isVertical ? bar.width : bar.height
        let inset = min(4, max(2, thickness * 0.1))
        let height = layout.style == .pill ? min(thickness, maximumPetSize)
            : min(maximumPetSize, max(0, thickness - inset * 2))
        let width = layout.style == .pill ? height * petAspectRatio : height
        guard height > 0, width > 0 else { return nil }
        let centerOffset = outerGap + (layout.style == .pill ? (isVertical ? height : width) : maximumPetSize) / 2
        func candidate(for side: PetSide) -> CGRect {
            if isVertical {
                return CGRect(
                    x: min(layout.screenFrame.maxX - width, max(layout.screenFrame.minX, bar.midX - width / 2)),
                    y: (side == .left ? bar.maxY + centerOffset : bar.minY - centerOffset) - height / 2,
                    width: width,
                    height: height
                )
            }
            return CGRect(
                x: (side == .left ? bar.minX - centerOffset : bar.maxX + centerOffset) - width / 2,
                y: layout.style == .pill ? bar.midY - height / 2 : bar.maxY - inset - height,
                width: width,
                height: height
            )
        }
        let preferred = candidate(for: side)
        guard layout.style == .pill else { return preferred }
        if layout.screenFrame.contains(preferred) { return preferred }
        let opposite = candidate(for: side == .left ? .right : .left)
        return layout.screenFrame.contains(opposite) ? opposite : nil
    }
}
