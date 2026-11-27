import CoreGraphics
import ZislaCore

extension FeatureSettings {
    public var islandScreenConfiguration: ScreenLayoutConfiguration {
        ScreenLayoutConfiguration(
            layoutStyle: islandLayoutStyle,
            placement: islandPlacement,
            pillSize: CGSize(width: islandPillWidth, height: islandPillHeight),
            edgeInset: islandEdgeInset,
            displaySettings: islandDisplaySettings
        )
    }

    public func islandSettings(for screen: ScreenSnapshot, displayCount: Int) -> FeatureSettings? {
        guard let configuration = ScreenLayoutEngine(configuration: islandScreenConfiguration)
            .configuration(for: screen, displayCount: displayCount) else { return nil }
        var settings = self
        settings.islandLayoutStyle = configuration.layoutStyle
        settings.islandPlacement = configuration.placement
        return settings
    }

    public func islandSettings(for layout: ScreenOverlayLayout) -> FeatureSettings {
        var settings = self
        settings.islandLayoutStyle = layout.style
        settings.islandPlacement = layout.placement
        return settings
    }
}
