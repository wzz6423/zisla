import Combine
@preconcurrency import Foundation
import IOKit

public struct BatteryLevelComponent: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case main
        case left
        case right
        case caseBattery

        public var displayName: String {
            switch self {
            case .main: "设备"
            case .left: "左"
            case .right: "右"
            case .caseBattery: "盒"
            }
        }
    }

    public var kind: Kind
    public var level: Double

    public init(kind: Kind, level: Double) {
        self.kind = kind
        self.level = min(max(level, 0), 1)
    }

    public var percentInt: Int {
        Int((level * 100).rounded())
    }
}

public struct NetworkBatteryDevice: Identifiable, Equatable, Sendable {
    public enum Source: String, Equatable, Sendable {
        case bluetooth
        case iDevice

        public var displayName: String {
            switch self {
            case .bluetooth: "蓝牙"
            case .iDevice: "已授权设备"
            }
        }

        public var symbolName: String {
            switch self {
            case .bluetooth: "bluetooth"
            case .iDevice: "iphone"
            }
        }
    }

    public enum DeviceType: String, Equatable, Sendable {
        case iPhone
        case iPad
        case mac
        case appleWatch
        case airPods
        case applePencil
        case androidPhone
        case headphones
        case mouse
        case keyboard
        case trackpad
        case accessory
        case unknown

        public var symbolName: String {
            switch self {
            case .iPhone: "iphone"
            case .iPad: "ipad"
            case .mac: "laptopcomputer"
            case .appleWatch: "applewatch"
            case .airPods: "airpods"
            case .applePencil: "applepencil"
            case .androidPhone: "rectangle.portrait"
            case .headphones: "headphones"
            case .mouse: "computermouse"
            case .keyboard: "keyboard"
            case .trackpad: "rectangle.and.hand.point.up.left"
            case .accessory: "sensor"
            case .unknown: "questionmark.circle"
            }
        }

        public var displayName: String {
            switch self {
            case .iPhone: "iPhone"
            case .iPad: "iPad"
            case .mac: "Mac"
            case .appleWatch: "Apple Watch"
            case .airPods: "AirPods"
            case .applePencil: "Apple Pencil"
            case .androidPhone: "Android"
            case .headphones: "耳机"
            case .mouse: "鼠标"
            case .keyboard: "键盘"
            case .trackpad: "触控板"
            case .accessory: "配件"
            case .unknown: "未知设备"
            }
        }
    }

    public var id: String { identifier }

    public var identifier: String
    public var name: String
    public var deviceType: DeviceType
    public var batteryLevel: Double
    public var isCharging: Bool
    public var lastSeen: Date
    public var source: Source
    public var components: [BatteryLevelComponent]
    public var parentName: String?
    public var connectionDetail: String?

    public init(
        identifier: String,
        name: String,
        deviceType: DeviceType,
        batteryLevel: Double,
        isCharging: Bool,
        lastSeen: Date = Date(),
        source: Source = .bluetooth,
        components: [BatteryLevelComponent] = [],
        parentName: String? = nil,
        connectionDetail: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.deviceType = deviceType
        self.batteryLevel = min(max(batteryLevel, 0), 1)
        self.isCharging = isCharging
        self.lastSeen = lastSeen
        self.source = source
        self.components = components
        self.parentName = parentName
        self.connectionDetail = connectionDetail
    }

    public var batteryPercentInt: Int {
        Int((batteryLevel * 100).rounded())
    }

    public var batterySymbolName: String {
        if isCharging {
            return "battery.100percent.bolt"
        }
        switch batteryPercentInt {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

struct BluetoothBatteryDiscovery: Equatable, Sendable {
    var devices: [NetworkBatteryDevice]
    var targets: [BluetoothBatteryTarget]

    static let empty = BluetoothBatteryDiscovery(devices: [], targets: [])
}

/// Reads battery data exposed by macOS, paired Apple mobile devices, and known BLE accessories.
@MainActor
public final class NetworkBatteryMonitor: NSObject, ObservableObject {
    @Published public private(set) var devices: [NetworkBatteryDevice] = []
    @Published public private(set) var isScanning = false

    nonisolated private static let refreshInterval: Duration = .seconds(60)

    private let accessoryReader: @Sendable () async -> [NetworkBatteryDevice]
    private var localDevices: [NetworkBatteryDevice] = []
    private var refreshLoop: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt = 0
    private var isMonitoring = false

    public override init() {
        accessoryReader = {
            async let discovery = Self.readBluetoothBatteryDiscovery()
            async let mobileDevices = Task.detached(priority: .utility) {
                AppleMobileDeviceBatteryReader.readDevices()
            }.value

            let bluetooth = await discovery
            let scannedDevices = await BluetoothBatteryScanner.collectBatteryDevices(
                targets: bluetooth.targets
            )
            return Self.mergedDevices(
                bluetooth.devices + scannedDevices + (await mobileDevices)
            )
        }
        super.init()
    }

    init(
        accessoryReader: @escaping @Sendable () async -> [NetworkBatteryDevice]
    ) {
        self.accessoryReader = accessoryReader
        super.init()
    }

    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        refresh()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.refreshInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    public func stop() {
        refreshGeneration &+= 1
        refreshLoop?.cancel()
        refreshLoop = nil
        refreshTask?.cancel()
        refreshTask = nil
        isScanning = false
        isMonitoring = false
        rebuildDevices()
    }

    public func refresh() {
        guard refreshTask == nil else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isScanning = true
        let accessoryReader = self.accessoryReader
        refreshTask = Task { [weak self, accessoryReader] in
            let discovered = await accessoryReader()
            guard let self, refreshGeneration == generation else { return }
            defer {
                isScanning = false
                refreshTask = nil
            }
            guard !Task.isCancelled else { return }
            localDevices = discovered
            rebuildDevices()
        }
    }

    nonisolated static func devices(
        fromBluetoothProfile data: Data,
        now: Date = Date()
    ) -> [NetworkBatteryDevice] {
        bluetoothDiscovery(from: data, now: now).devices
    }

    nonisolated static func bluetoothDiscovery(
        from data: Data,
        now: Date = Date()
    ) -> BluetoothBatteryDiscovery {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reports = root["SPBluetoothDataType"] as? [[String: Any]]
        else {
            return .empty
        }

        var devices: [NetworkBatteryDevice] = []
        var targets: [BluetoothBatteryTarget] = []
        for report in reports {
            for (name, details) in bluetoothEntries(report["device_connected"]) {
                let target = bluetoothTarget(name: name, details: details, isConnected: true)
                targets.append(target)
                let levels = bluetoothLevels(in: details)
                guard let primaryLevel = levels.main ?? levels.components.map(\.level).min()
                else { continue }
                devices.append(NetworkBatteryDevice(
                    identifier: "bluetooth:\(target.identifier)",
                    name: name,
                    deviceType: target.deviceType,
                    batteryLevel: primaryLevel,
                    isCharging: bluetoothChargingState(in: details) ?? false,
                    lastSeen: now,
                    source: .bluetooth,
                    components: levels.components,
                    connectionDetail: "已连接"
                ))
            }

            for (name, details) in bluetoothEntries(report["device_not_connected"]) {
                let target = bluetoothTarget(name: name, details: details, isConnected: false)
                if target.supportsAppleHeadphoneAdvertisement {
                    targets.append(target)
                }
            }
        }
        return BluetoothBatteryDiscovery(
            devices: mergedDevices(devices),
            targets: deduplicatedTargets(targets)
        )
    }

    private func rebuildDevices() {
        devices = Self.mergedDevices(localDevices).sorted {
            if $0.source != $1.source { return $0.source == .bluetooth }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    nonisolated static func mergedDevices(
        _ candidates: [NetworkBatteryDevice]
    ) -> [NetworkBatteryDevice] {
        var mergedByKey: [String: NetworkBatteryDevice] = [:]
        var orderedKeys: [String] = []
        for candidate in candidates {
            let key = canonicalDeviceKey(candidate)
            guard let existing = mergedByKey[key] else {
                mergedByKey[key] = candidate
                orderedKeys.append(key)
                continue
            }

            let candidateIsBetter = candidate.components.count > existing.components.count
                || (candidate.components.count == existing.components.count
                    && candidate.lastSeen >= existing.lastSeen)
            let preferred = candidateIsBetter ? candidate : existing
            let other = candidateIsBetter ? existing : candidate
            var combined = preferred
            combined.identifier = existing.identifier
            combined.isCharging = preferred.isCharging || other.isCharging
            combined.lastSeen = max(preferred.lastSeen, other.lastSeen)
            combined.parentName = preferred.parentName ?? other.parentName
            combined.connectionDetail = preferred.connectionDetail ?? other.connectionDetail
            if combined.components.isEmpty { combined.components = other.components }
            mergedByKey[key] = combined
        }
        return orderedKeys.compactMap { mergedByKey[$0] }
    }

    nonisolated private static func readBluetoothBatteryDiscovery() async -> BluetoothBatteryDiscovery {
        do {
            let output = try await AIAgentProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/sbin/system_profiler"),
                arguments: ["SPBluetoothDataType", "-json"],
                timeout: 15
            )
            guard output.status == 0, !output.didTimeout else { return .empty }
            let discovery = bluetoothDiscovery(from: output.standardOutput)
            return BluetoothBatteryDiscovery(
                devices: mergedDevices(
                    discovery.devices + readMagicAccessoryDevices(targets: discovery.targets)
                ),
                targets: discovery.targets
            )
        } catch {
            return .empty
        }
    }

    nonisolated private static func readMagicAccessoryDevices(
        targets: [BluetoothBatteryTarget],
        now: Date = Date()
    ) -> [NetworkBatteryDevice] {
        [
            "AppleDeviceManagementHIDEventService",
            "AppleBluetoothHIDKeyboard",
            "BNBTrackpadDevice",
            "BNBMouseDevice",
        ].flatMap { serviceClass in
            readMagicAccessoryDevices(
                matchingService: serviceClass,
                targets: targets,
                now: now
            )
        }
    }

    nonisolated private static func readMagicAccessoryDevices(
        matchingService serviceClass: String,
        targets: [BluetoothBatteryTarget],
        now: Date
    ) -> [NetworkBatteryDevice] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(serviceClass),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [NetworkBatteryDevice] = []
        while true {
            let object = IOIteratorNext(iterator)
            guard object != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(object) }

            var unmanagedProperties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(
                object,
                &unmanagedProperties,
                kCFAllocatorDefault,
                0
            ) == KERN_SUCCESS,
                let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any],
                let device = magicAccessoryDevice(
                    fromIORegistryProperties: properties,
                    serviceClass: serviceClass,
                    targets: targets,
                    now: now
                )
            else {
                continue
            }
            devices.append(device)
        }
        return devices
    }

    nonisolated static func magicAccessoryDevice(
        fromIORegistryProperties properties: [String: Any],
        serviceClass: String,
        targets: [BluetoothBatteryTarget],
        now: Date = Date()
    ) -> NetworkBatteryDevice? {
        guard let level = percentage(properties["BatteryPercent"]) else { return nil }

        let product = (properties["Product"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard product?.localizedCaseInsensitiveContains("Internal") != true else { return nil }

        let address = normalizedHexIdentifier(properties["DeviceAddress"])
        let matchedTarget = address.flatMap { identifier in
            targets.first { $0.identifier == identifier }
        } ?? product.flatMap { product in
            let normalizedProduct = normalizedName(product)
            return targets.first { normalizedName($0.name) == normalizedProduct }
        }
        let name = matchedTarget?.name ?? product.flatMap { $0.isEmpty ? nil : $0 } ?? serviceClass
        let identifier = address ?? normalizedName(name)
        let statusFlags = (properties["BatteryStatusFlags"] as? NSNumber)?.intValue
            ?? properties["BatteryStatusFlags"] as? Int
        let isCharging = statusFlags.map { $0 > 0 && $0 != 4 } ?? false

        return NetworkBatteryDevice(
            identifier: "bluetooth:\(identifier)",
            name: name,
            deviceType: matchedTarget?.deviceType
                ?? inferredDeviceType(name: name, minorType: nil),
            batteryLevel: level,
            isCharging: isCharging,
            lastSeen: now,
            source: .bluetooth,
            connectionDetail: "已连接"
        )
    }

    nonisolated private static func bluetoothEntries(
        _ rawValue: Any?
    ) -> [(name: String, details: [String: Any])] {
        (rawValue as? [[String: Any]] ?? []).flatMap { entry in
            entry.compactMap { name, rawDetails in
                (rawDetails as? [String: Any]).map { (name, $0) }
            }
        }
    }

    nonisolated private static func bluetoothTarget(
        name: String,
        details: [String: Any],
        isConnected: Bool
    ) -> BluetoothBatteryTarget {
        let deviceType = inferredDeviceType(
            name: name,
            minorType: details["device_minorType"] as? String
        )
        let vendorID = normalizedHexIdentifier(details["device_vendorID"])
        let lowercasedName = name.lowercased()
        let supportsAdvertisement = deviceType == .airPods
            || (vendorID == "004c" && lowercasedName.contains("beats"))
        let address = (details["device_address"] as? String).flatMap {
            let normalized = $0.lowercased().filter(\.isHexDigit)
            return normalized.isEmpty ? nil : normalized
        }
        return BluetoothBatteryTarget(
            identifier: address ?? normalizedName(name),
            name: name,
            deviceType: deviceType,
            isConnected: isConnected,
            supportsAppleHeadphoneAdvertisement: supportsAdvertisement
        )
    }

    nonisolated private static func deduplicatedTargets(
        _ targets: [BluetoothBatteryTarget]
    ) -> [BluetoothBatteryTarget] {
        var result: [String: BluetoothBatteryTarget] = [:]
        var keys: [String] = []
        for target in targets {
            let key = target.identifier
            if let existing = result[key] {
                if !existing.isConnected, target.isConnected { result[key] = target }
            } else {
                result[key] = target
                keys.append(key)
            }
        }
        return keys.compactMap { result[$0] }
    }

    nonisolated private static func canonicalDeviceKey(
        _ device: NetworkBatteryDevice
    ) -> String {
        guard device.source == .bluetooth else { return device.identifier }
        for prefix in ["bluetooth:", "ble:", "apple-headphone:"]
        where device.identifier.hasPrefix(prefix) {
            return "bluetooth:\(device.identifier.dropFirst(prefix.count))"
        }
        return "bluetooth:\(device.identifier)"
    }

    nonisolated private static func normalizedHexIdentifier(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let normalized = value.lowercased().replacingOccurrences(of: "0x", with: "")
            .filter(\.isHexDigit)
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated private static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    nonisolated private static func bluetoothLevels(
        in details: [String: Any]
    ) -> (main: Double?, components: [BatteryLevelComponent]) {
        let main = percentage(details["device_batteryLevelMain"])
        let componentValues: [(BatteryLevelComponent.Kind, Any?)] = [
            (.left, details["device_batteryLevelLeft"]),
            (.right, details["device_batteryLevelRight"]),
            (.caseBattery, details["device_batteryLevelCase"]),
        ]
        let components = componentValues.compactMap { kind, rawValue in
            percentage(rawValue).map { BatteryLevelComponent(kind: kind, level: $0) }
        }
        return (main, components)
    }

    nonisolated private static func percentage(_ value: Any?) -> Double? {
        let percent: Int?
        if let value = value as? NSNumber {
            percent = value.intValue
        } else if let value = value as? String {
            percent = Int(value.filter(\.isNumber))
        } else {
            percent = nil
        }
        return percent.flatMap { (0...100).contains($0) ? Double($0) / 100 : nil }
    }

    nonisolated private static func bluetoothChargingState(in details: [String: Any]) -> Bool? {
        for key in ["device_batteryIsCharging", "device_isCharging", "device_charging"] {
            if let value = details[key] as? Bool { return value }
            if let value = details[key] as? NSNumber { return value.boolValue }
            if let value = details[key] as? String {
                let normalized = value.lowercased()
                if ["yes", "true", "1"].contains(normalized) { return true }
                if ["no", "false", "0"].contains(normalized) { return false }
            }
        }
        return nil
    }

    nonisolated private static func inferredDeviceType(
        name: String,
        minorType: String?
    ) -> NetworkBatteryDevice.DeviceType {
        let value = "\(name) \(minorType ?? "")".lowercased()
        if value.contains("airpod") { return .airPods }
        if value.contains("iphone") { return .iPhone }
        if value.contains("ipad") { return .iPad }
        if value.contains("watch") { return .appleWatch }
        if value.contains("pencil") { return .applePencil }
        if value.contains("trackpad") { return .trackpad }
        if value.contains("keyboard") || value.contains("键盘") { return .keyboard }
        if value.contains("mouse") || value.contains("鼠标") { return .mouse }
        if ["headphone", "earphone", "earbud", "buds", "beats", "耳机"]
            .contains(where: { value.contains($0) }) {
            return .headphones
        }
        if ["android", "pixel", "xiaomi", "oppo", "vivo", "huawei", "honor", "三星", "小米"]
            .contains(where: { value.contains($0) }) {
            return .androidPhone
        }
        return .accessory
    }

}

extension BatteryLevelComponent.Kind: CaseIterable {}
