import CoreGraphics

public enum CollapsedPetLayout {
    public static let maximumPetSize: CGFloat = 24
    public static let outerGap: CGFloat = 4
    public static let sideSlotWidth = maximumPetSize + outerGap * 2

    public static func containerSize(
        for compactBarSize: CGSize
    ) -> CGSize {
        return CGSize(
            width: compactBarSize.width + sideSlotWidth * 2,
            height: compactBarSize.height
        )
    }

    public static func frame(
        for layout: ScreenOverlayLayout,
        compactBarFrame: CGRect? = nil
    ) -> CGRect {
        let compactBarFrame = compactBarFrame ?? layout.collapsedFrame
        let size = containerSize(for: compactBarFrame.size)
        return CGRect(
            x: compactBarFrame.midX - size.width / 2,
            y: compactBarFrame.minY,
            width: size.width,
            height: size.height
        )
    }
}
