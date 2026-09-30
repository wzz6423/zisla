import AppKit
import Foundation
import ZislaCore
import ZislaKit

// Modified for Zisla; source revision and adaptation details are in ThirdPartyLicenses/README.md.
struct MenuBarIconBatteryStatus: Equatable, Sendable {
    let rawPercentage: Int?
    let isPresent: Bool
    let isCharging: Bool
    let isLowPowerMode: Bool
    let isConnectedToPower: Bool

    var percentage: Int {
        guard isPresent else { return 100 }
        return min(100, max(0, rawPercentage ?? 100))
    }
}

enum MenuBarIconWiFiState: Equatable, Sendable {
    case connected
    case notAssociated
    case off
    case unavailable
}

struct MenuBarIconWiFiStatus: Equatable, Sendable {
    let state: MenuBarIconWiFiState
    let rssi: Int?
}

struct MenuBarIconVolumeStatus: Equatable, Sendable {
    let scalar: Double?
    let isMuted: Bool
}

enum MenuBarIconHeadphoneSource: Equatable, Sendable {
    case symbol(String)
    case image(URL)
}

struct MenuBarIconHeadphoneStatus: Equatable, Sendable {
    let device: AudioOutputDevice
    let productID: UInt32?
    let isVolumeMetric: Bool

    var source: MenuBarIconHeadphoneSource {
        if let asset = HeadphoneSystemAssetLocator.system.asset(for: productID) {
            return .image(asset.imageURL)
        }
        let name = device.name.lowercased()
        let candidates: [String]
        if device.isAirPodsMax {
            candidates = ["airpods.max", "headphones"]
        } else if name.contains("airpod") && name.contains("pro") {
            candidates = ["airpods.pro", "airpodspro", "headphones"]
        } else if name.contains("airpod") {
            candidates = ["airpods", "headphones"]
        } else {
            candidates = ["headphones"]
        }
        return .symbol(candidates.first {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        } ?? "headphones")
    }
}

struct MenuBarIconStatus: Equatable, Sendable {
    let battery: MenuBarIconBatteryStatus
    let wifi: MenuBarIconWiFiStatus
    let volume: MenuBarIconVolumeStatus
    let headphones: MenuBarIconHeadphoneStatus?
    let headphoneOptions: SystemMonitorHeadphoneOptions

    init(
        battery: BatterySnapshot?, wifi: MenuBarWiFiState, level: Double?,
        headphones: MenuBarIconHeadphoneStatus? = nil,
        headphoneOptions: SystemMonitorHeadphoneOptions = SystemMonitorHeadphoneOptions()
    ) {
        self.headphones = headphones
        self.headphoneOptions = headphoneOptions.normalized
        self.battery = MenuBarIconBatteryStatus(
            rawPercentage: battery.flatMap { snapshot in
                guard snapshot.level.isFinite else { return nil }
                return Int((min(1, max(0, snapshot.level)) * 100).rounded())
            },
            isPresent: battery != nil,
            isCharging: battery?.isCharging == true,
            isLowPowerMode: battery?.isLowPowerMode == true,
            isConnectedToPower: battery?.isPluggedIn == true
        )
        switch wifi {
        case let .connected(strength) where strength.isFinite:
            self.wifi = MenuBarIconWiFiStatus(
                state: .connected,
                rssi: Int((min(1, max(0, strength)) * 50 - 100).rounded())
            )
        case .disconnected:
            self.wifi = MenuBarIconWiFiStatus(state: .notAssociated, rssi: nil)
        case .off:
            self.wifi = MenuBarIconWiFiStatus(state: .off, rssi: nil)
        case .unavailable, .connected:
            self.wifi = MenuBarIconWiFiStatus(state: .unavailable, rssi: nil)
        }
        volume = MenuBarIconVolumeStatus(
            scalar: level.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil },
            isMuted: false
        )
    }
}

struct MenuBarIconBatteryOptions: Equatable, Sendable {
    let showsPercentage: Bool
    let showsChargingIndicator: Bool
    let usesStatusColors: Bool
    let showsPercentageWhenConnected: Bool
    let criticalThreshold: Int
    let textScale: Double
    let ringStrokeScale: Double

    static let defaultTextScale = 1.8

    init(appearance: SystemMonitorCombinedIconAppearance) {
        let appearance = appearance.normalized
        showsPercentage = appearance.showsBatteryPercentage
        showsChargingIndicator = appearance.showsChargingIndicator
        usesStatusColors = appearance.usesStatusColors
        showsPercentageWhenConnected = appearance.showsPercentageWhenConnected
        criticalThreshold = 20
        textScale = appearance.batteryTextScale
        ringStrokeScale = appearance.ringStrokeStyle.scale
    }
}

struct MenuBarIconConnectionOptions: Equatable, Sendable {
    let wifiScale: Double

    init(appearance: SystemMonitorCombinedIconAppearance) {
        wifiScale = appearance.normalized.wifiScale
    }
}

struct MenuBarIconVolumeOptions: Equatable, Sendable {
    let displayStyle: SystemMonitorMenuBarIndicatorStyle
    let ringStrokeScale: Double

    var dotRadiusScale: Double {
        1 + (ringStrokeScale - 1) * 0.5
    }

    init(appearance: SystemMonitorCombinedIconAppearance) {
        displayStyle = appearance.indicatorStyle
        ringStrokeScale = appearance.ringStrokeStyle.scale
    }
}

enum MenuBarIconBatteryColorRole: Equatable, Sendable {
    case foreground
    case critical
    case lowPower
    case charging
}

enum MenuBarIconBatteryGapContent: Equatable, Sendable {
    case bolt
    case plug
    case percentage
    case empty
}

enum MenuBarIconMappings {
    static func shouldReplaceNetworkIcon(status: MenuBarIconStatus) -> Bool {
        guard status.headphoneOptions.replacesNetworkIcon,
              let headphones = status.headphones,
              headphones.device.isHeadphones,
              headphones.device.isBluetoothAudio else { return false }
        guard status.headphoneOptions.prioritizesNetworkErrors else { return true }
        return status.wifi.state == .connected
    }

    static func wifiBars(rssi: Int?) -> Int {
        guard let rssi else { return 0 }
        switch rssi {
        case (-60)...: return 3
        case -78 ... -61: return 2
        case -88 ... -79: return 1
        default: return 0
        }
    }

    static func volumeSteps(scalar: Double?, isMuted: Bool) -> Int? {
        guard let scalar, scalar.isFinite else { return nil }
        let clamped = min(1, max(0, scalar))
        if isMuted || clamped == 0 { return 0 }
        if clamped <= 0.25 { return 1 }
        if clamped <= 0.50 { return 2 }
        if clamped <= 0.75 { return 3 }
        return 4
    }

    static func batteryColorRole(_ battery: MenuBarIconBatteryStatus, criticalThreshold: Int = 20) -> MenuBarIconBatteryColorRole {
        let threshold = min(100, max(0, criticalThreshold))
        if battery.isLowPowerMode { return .lowPower }
        if battery.percentage < threshold { return .critical }
        if battery.isCharging || battery.isConnectedToPower { return .charging }
        return .foreground
    }

    static func batteryGapContent(_ battery: MenuBarIconBatteryStatus, options: MenuBarIconBatteryOptions) -> MenuBarIconBatteryGapContent {
        guard battery.isPresent, battery.rawPercentage != nil else { return .empty }
        if options.showsChargingIndicator {
            if battery.isCharging { return .bolt }
            let showsPercentageForPower = options.showsPercentageWhenConnected && options.showsPercentage
            if battery.isConnectedToPower, !showsPercentageForPower { return .plug }
        }
        return options.showsPercentage ? .percentage : .empty
    }

    static func batteryProgress(_ battery: MenuBarIconBatteryStatus) -> Double {
        guard battery.isPresent, let percentage = battery.rawPercentage else { return 0 }
        return Double(min(100, max(0, percentage))) / 100
    }
}
