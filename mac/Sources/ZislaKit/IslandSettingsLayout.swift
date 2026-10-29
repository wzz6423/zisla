import CoreGraphics
import ZislaCore

extension FeatureSettings {
    public var islandScreenConfiguration: ScreenLayoutConfiguration {
        ScreenLayoutConfiguration(
            layoutStyle: islandLayoutStyle,
            placement: islandPlacement,
            pillSize: CGSize(width: islandPillWidth, height: islandPillHeight),
            edgeInset: islandEdgeInset
        )
    }
}
