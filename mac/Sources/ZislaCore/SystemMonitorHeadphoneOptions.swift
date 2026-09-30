import Foundation

public struct SystemMonitorHeadphoneOptions: Equatable, Codable, Sendable {
    public var replacesNetworkIcon: Bool
    public var prioritizesNetworkErrors: Bool
    public var usesVolumeColor: Bool
    public var showsBatteryLevels: Bool
    public var symbolScale: Double

    public static let symbolScaleRange: ClosedRange<Double> = 1...1.8

    public init(
        replacesNetworkIcon: Bool = false,
        prioritizesNetworkErrors: Bool = true,
        usesVolumeColor: Bool = false,
        showsBatteryLevels: Bool = true,
        symbolScale: Double = 1.6
    ) {
        self.replacesNetworkIcon = replacesNetworkIcon
        self.prioritizesNetworkErrors = prioritizesNetworkErrors
        self.usesVolumeColor = usesVolumeColor
        self.showsBatteryLevels = showsBatteryLevels
        self.symbolScale = symbolScale.isFinite
            ? min(Self.symbolScaleRange.upperBound, max(Self.symbolScaleRange.lowerBound, symbolScale))
            : 1.6
    }

    public var normalized: Self {
        Self(
            replacesNetworkIcon: replacesNetworkIcon,
            prioritizesNetworkErrors: prioritizesNetworkErrors,
            usesVolumeColor: usesVolumeColor,
            showsBatteryLevels: showsBatteryLevels,
            symbolScale: symbolScale
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        self.init(
            replacesNetworkIcon: try container.decodeIfPresent(Bool.self, forKey: .replacesNetworkIcon) ?? defaults.replacesNetworkIcon,
            prioritizesNetworkErrors: try container.decodeIfPresent(Bool.self, forKey: .prioritizesNetworkErrors) ?? defaults.prioritizesNetworkErrors,
            usesVolumeColor: try container.decodeIfPresent(Bool.self, forKey: .usesVolumeColor) ?? defaults.usesVolumeColor,
            showsBatteryLevels: try container.decodeIfPresent(Bool.self, forKey: .showsBatteryLevels) ?? defaults.showsBatteryLevels,
            symbolScale: try container.decodeIfPresent(Double.self, forKey: .symbolScale) ?? defaults.symbolScale
        )
    }
}
