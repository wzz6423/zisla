import CoreGraphics

public enum CompactStatusBarSwipeRecognizer {
    public static let minimumDistance: CGFloat = 24

    public static func hidesStatusContent(
        startLocation: CGPoint,
        translation: CGSize,
        containerWidth: CGFloat
    ) -> Bool {
        guard containerWidth > 0,
            abs(translation.width) >= minimumDistance,
            abs(translation.width) > abs(translation.height)
        else {
            return false
        }

        let wingWidth = min(48, containerWidth / 2)
        if startLocation.x <= wingWidth, translation.width > 0 { return true }
        if startLocation.x >= containerWidth - wingWidth, translation.width < 0 { return true }
        return false
    }
}
