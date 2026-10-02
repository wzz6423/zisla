import Foundation

// Modified for Zisla; source revision and adaptation details are in ThirdPartyLicenses/README.md.
public enum SystemMonitorMenuBarRingStrokeStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case light
    case regular
    case bold

    public var id: String { rawValue }

    public var scale: Double {
        switch self {
        case .light: 1
        case .regular: 1.25
        case .bold: 1.5
        }
    }

    public var menuTitle: String {
        switch self {
        case .light: "纤细"
        case .regular: "标准"
        case .bold: "加粗"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "light", "standard": self = .light
        case "regular", "normal": self = .regular
        case "bold", "heavy": self = .bold
        default: return nil
        }
    }
}

public enum SystemMonitorMenuBarIndicatorStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case dots
    case arc

    public var id: String { rawValue }

    public var menuTitle: String {
        switch self {
        case .dots: "圆点"
        case .arc: "弧线"
        }
    }
}

public struct SystemMonitorCombinedIconAppearance: Equatable, Codable, Sendable {
    public var iconSize: Double
    public var ringStrokeStyle: SystemMonitorMenuBarRingStrokeStyle
    public var indicatorStyle: SystemMonitorMenuBarIndicatorStyle
    public var showsBatteryPercentage: Bool
    public var showsChargingIndicator: Bool
    public var showsPercentageWhenConnected: Bool
    public var usesStatusColors: Bool
    public var batteryTextScale: Double
    public var wifiScale: Double

    public static let iconSizeRange: ClosedRange<Double> = 16...36
    public static let batteryTextScaleRange: ClosedRange<Double> = 1.62...1.98
    public static let wifiScaleRange: ClosedRange<Double> = 1...1.8

    public init(
        iconSize: Double = 26,
        ringStrokeStyle: SystemMonitorMenuBarRingStrokeStyle = .bold,
        indicatorStyle: SystemMonitorMenuBarIndicatorStyle = .dots,
        showsBatteryPercentage: Bool = true,
        showsChargingIndicator: Bool = true,
        showsPercentageWhenConnected: Bool = true,
        usesStatusColors: Bool = true,
        batteryTextScale: Double = SystemMonitorCombinedIconAppearance.batteryTextScaleRange.upperBound,
        wifiScale: Double = 1.55
    ) {
        self.iconSize = Self.clamped(iconSize, range: Self.iconSizeRange, fallback: 26)
        self.ringStrokeStyle = ringStrokeStyle
        self.indicatorStyle = indicatorStyle
        self.showsBatteryPercentage = showsBatteryPercentage
        self.showsChargingIndicator = showsChargingIndicator
        self.showsPercentageWhenConnected = showsPercentageWhenConnected
        self.usesStatusColors = usesStatusColors
        self.batteryTextScale = Self.clamped(batteryTextScale, range: Self.batteryTextScaleRange, fallback: Self.batteryTextScaleRange.upperBound)
        self.wifiScale = Self.clamped(wifiScale, range: Self.wifiScaleRange, fallback: 1.55)
    }

    public var normalized: Self {
        Self(
            iconSize: iconSize,
            ringStrokeStyle: ringStrokeStyle,
            indicatorStyle: indicatorStyle,
            showsBatteryPercentage: showsBatteryPercentage,
            showsChargingIndicator: showsChargingIndicator,
            showsPercentageWhenConnected: showsPercentageWhenConnected,
            usesStatusColors: usesStatusColors,
            batteryTextScale: batteryTextScale,
            wifiScale: wifiScale
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        self.init(
            iconSize: try container.decodeIfPresent(Double.self, forKey: .iconSize) ?? defaults.iconSize,
            ringStrokeStyle: try container.decodeIfPresent(SystemMonitorMenuBarRingStrokeStyle.self, forKey: .ringStrokeStyle) ?? defaults.ringStrokeStyle,
            indicatorStyle: try container.decodeIfPresent(SystemMonitorMenuBarIndicatorStyle.self, forKey: .indicatorStyle) ?? defaults.indicatorStyle,
            showsBatteryPercentage: try container.decodeIfPresent(Bool.self, forKey: .showsBatteryPercentage) ?? defaults.showsBatteryPercentage,
            showsChargingIndicator: try container.decodeIfPresent(Bool.self, forKey: .showsChargingIndicator) ?? defaults.showsChargingIndicator,
            showsPercentageWhenConnected: try container.decodeIfPresent(Bool.self, forKey: .showsPercentageWhenConnected) ?? defaults.showsPercentageWhenConnected,
            usesStatusColors: try container.decodeIfPresent(Bool.self, forKey: .usesStatusColors) ?? defaults.usesStatusColors,
            batteryTextScale: try container.decodeIfPresent(Double.self, forKey: .batteryTextScale) ?? defaults.batteryTextScale,
            wifiScale: try container.decodeIfPresent(Double.self, forKey: .wifiScale) ?? defaults.wifiScale
        )
    }

    private static func clamped(_ value: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}
