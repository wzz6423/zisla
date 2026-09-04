import Combine
import CoreFoundation
import Foundation
import IOKit
import IOKit.ps

/// Battery status snapshot. `BatteryMonitor.snapshot` is nil on desktop Macs with no built-in battery.
public struct BatterySnapshot: Equatable, Sendable {
    /// Remaining charge as a fraction, 0...1.
    public var level: Double
    public var isCharging: Bool
    /// Whether external power is connected, including charge-hold states.
    public var isPluggedIn: Bool
    public var isCharged: Bool
    /// Minutes remaining when discharging, or minutes to full when charging.
    public var timeRemainingMinutes: Int?
    public var temperatureCelsius: Double?
    /// Signed milliamps: positive while charging and negative while discharging.
    public var currentMilliamps: Double?
    public var voltageVolts: Double?
    /// Absolute battery power in watts.
    public var powerWatts: Double?
    public var designCapacityMAh: Int?
    public var maxCapacityMAh: Int?
    public var currentCapacityMAh: Int?
    public var healthPercent: Int?
    public var cycleCount: Int?
    public var isLowPowerMode: Bool
    /// Instantaneous power entering from the adapter, not its rated ceiling.
    public var adapterWatts: Double?
    public var adapterRatedWatts: Double?
    public var systemLoadWatts: Double?
    /// Positive when charging the battery and negative when the battery supplies the system.
    public var batteryFlowWatts: Double?

    public init(
        level: Double,
        isCharging: Bool,
        isPluggedIn: Bool,
        isCharged: Bool,
        timeRemainingMinutes: Int?,
        temperatureCelsius: Double? = nil,
        currentMilliamps: Double? = nil,
        voltageVolts: Double? = nil,
        powerWatts: Double? = nil,
        designCapacityMAh: Int? = nil,
        maxCapacityMAh: Int? = nil,
        currentCapacityMAh: Int? = nil,
        healthPercent: Int? = nil,
        cycleCount: Int? = nil,
        isLowPowerMode: Bool = false,
        adapterWatts: Double? = nil,
        adapterRatedWatts: Double? = nil,
        systemLoadWatts: Double? = nil,
        batteryFlowWatts: Double? = nil
    ) {
        self.level = min(max(level, 0), 1)
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.isCharged = isCharged
        self.timeRemainingMinutes = timeRemainingMinutes
        self.temperatureCelsius = temperatureCelsius
        self.currentMilliamps = currentMilliamps
        self.voltageVolts = voltageVolts
        self.powerWatts = powerWatts
        self.designCapacityMAh = designCapacityMAh
        self.maxCapacityMAh = maxCapacityMAh
        self.currentCapacityMAh = currentCapacityMAh
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.isLowPowerMode = isLowPowerMode
        self.adapterWatts = adapterWatts
        self.adapterRatedWatts = adapterRatedWatts
        self.systemLoadWatts = systemLoadWatts
        self.batteryFlowWatts = batteryFlowWatts
    }

    public var percentInt: Int {
        Int((level * 100).rounded())
    }

    public var symbolName: String {
        if isCharging {
            return "battery.100percent.bolt"
        }
        switch percentInt {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// Combines IOPowerSources status with AppleSmartBattery registry metrics.
@MainActor
public final class BatteryMonitor: ObservableObject {
    @Published public private(set) var snapshot: BatterySnapshot?

    /// Timestamp when the battery last reached fully charged state.
    @Published public private(set) var lastFullyChargedAt: Date?
    /// Timestamp when external power was last disconnected.
    @Published public private(set) var lastUnpluggedAt: Date?

    private var runLoopSource: CFRunLoopSource?
    private let defaults: UserDefaults
    private let now: () -> Date
    private var lastObservedIsCharged: Bool?
    private var lastObservedIsPluggedIn: Bool?

    private enum HistoryKey {
        static let lastFullyChargedAt = "zisla.battery.last-fully-charged-at"
        static let lastUnpluggedAt = "zisla.battery.last-unplugged-at"
        static let lastObservedIsCharged = "zisla.battery.last-observed-is-charged"
        static let lastObservedIsPluggedIn = "zisla.battery.last-observed-is-plugged-in"
    }

    public init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.now = now
        self.lastFullyChargedAt = Self.loadDate(defaults, forKey: HistoryKey.lastFullyChargedAt)
        self.lastUnpluggedAt = Self.loadDate(defaults, forKey: HistoryKey.lastUnpluggedAt)
        self.lastObservedIsCharged = defaults.object(forKey: HistoryKey.lastObservedIsCharged) as? Bool
        self.lastObservedIsPluggedIn = defaults.object(forKey: HistoryKey.lastObservedIsPluggedIn) as? Bool
    }

    public func start() {
        refresh()
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let unmanaged = IOPSNotificationCreateRunLoopSource({ rawContext in
            guard let rawContext else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(rawContext)
                .takeUnretainedValue()
            Task { @MainActor in monitor.refresh() }
        }, context) else { return }
        let source = unmanaged.takeRetainedValue()
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    public func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
    }

    public func refresh() {
        let previous = snapshot
        let current = Self.currentSnapshot()
        detectStateTransitions(from: previous, to: current)
        snapshot = current
    }

    func detectStateTransitions(from previous: BatterySnapshot?, to current: BatterySnapshot?) {
        guard let current else { return }

        let previousIsCharged = previous?.isCharged ?? lastObservedIsCharged
        let previousIsPluggedIn = previous?.isPluggedIn ?? lastObservedIsPluggedIn

        if current.isCharged, previousIsCharged == false {
            let date = now()
            lastFullyChargedAt = date
            storeDate(date, forKey: HistoryKey.lastFullyChargedAt)
        }

        if !current.isPluggedIn, previousIsPluggedIn == true {
            let date = now()
            lastUnpluggedAt = date
            storeDate(date, forKey: HistoryKey.lastUnpluggedAt)
        }

        lastObservedIsCharged = current.isCharged
        lastObservedIsPluggedIn = current.isPluggedIn
        defaults.set(current.isCharged, forKey: HistoryKey.lastObservedIsCharged)
        defaults.set(current.isPluggedIn, forKey: HistoryKey.lastObservedIsPluggedIn)
    }

    nonisolated static func currentSnapshot() -> BatterySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }
        let registry = smartBatteryProperties() ?? [:]
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any]
            else {
                continue
            }
            if var snapshot = snapshot(
                from: description,
                registry: registry,
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
            ) {
                snapshot.temperatureCelsius = snapshot.temperatureCelsius
                    ?? AppleSMCSensorReader.batteryTemperatureCelsius()
                return snapshot
            }
        }
        return nil
    }

    /// Pure parser kept separate from IOKit reads so cross-generation fixtures are testable.
    nonisolated static func snapshot(
        from powerSource: [String: Any],
        registry: [String: Any] = [:],
        isLowPowerMode: Bool = false
    ) -> BatterySnapshot? {
        if let type = stringValue(powerSource[kIOPSTypeKey as String]),
           type != kIOPSInternalBatteryType as String {
            return nil
        }
        guard let current = doubleValue(powerSource[kIOPSCurrentCapacityKey as String]),
              let maximum = doubleValue(powerSource[kIOPSMaxCapacityKey as String]),
              maximum > 0
        else {
            return nil
        }

        let level = min(max(current / maximum, 0), 1)
        let isCharging = boolValue(powerSource[kIOPSIsChargingKey as String])
            ?? boolValue(registry["IsCharging"])
            ?? false
        let isCharged = boolValue(powerSource[kIOPSIsChargedKey as String])
            ?? boolValue(registry["FullyCharged"])
            ?? false
        let state = stringValue(powerSource[kIOPSPowerSourceStateKey as String])
        let isPluggedIn = state.map { $0 == kIOPSACPowerValue as String }
            ?? boolValue(registry["ExternalConnected"])
            ?? false

        let rawTime = isCharging
            ? intValue(powerSource[kIOPSTimeToFullChargeKey as String])
            : intValue(powerSource[kIOPSTimeToEmptyKey as String])
        let timeRemaining = rawTime.flatMap { (1..<65_535).contains($0) ? $0 : nil }

        let batteryData = dictionaryValue(registry["BatteryData"])
        let currentCapacity = firstPositive([
            intValue(registry["AppleRawCurrentCapacity"]),
            intValue(registry["AbsoluteCapacity"]),
            intValue(batteryData?["RemainingCapacity"]),
            legacyCapacity(registry["CurrentCapacity"]),
        ])
        let maxCapacity = firstPositive([
            intValue(registry["AppleRawMaxCapacity"]),
            intValue(registry["FullChargeCapacity"]),
            intValue(batteryData?["FullChargeCapacity"]),
            intValue(registry["NominalChargeCapacity"]),
            intValue(batteryData?["NominalChargeCapacity"]),
            legacyCapacity(registry["MaxCapacity"]),
        ])
        let designCapacity = firstPositive([
            intValue(registry["DesignCapacity"]),
            intValue(batteryData?["DesignCapacity"]),
        ])
        let healthPercent: Int? = if let maxCapacity, let designCapacity, designCapacity > 0 {
            min(100, max(0, Int((Double(maxCapacity) / Double(designCapacity) * 100).rounded())))
        } else {
            nil
        }

        let temperature = normalizedTemperature(doubleValue(registry["Temperature"]))
        let currentMilliamps = doubleValue(registry["InstantAmperage"])
            ?? doubleValue(registry["Amperage"])
        let voltageMillivolts = doubleValue(registry["Voltage"])
            ?? doubleValue(registry["AppleRawBatteryVoltage"])
        let voltage = voltageMillivolts.flatMap { $0 > 0 ? $0 / 1_000 : nil }
        let electricalFlow: Double? = if let currentMilliamps, let voltage {
            currentMilliamps * voltage / 1_000
        } else {
            nil
        }

        let telemetry = dictionaryValue(registry["PowerTelemetryData"])
        let adapterInput = milliwattsValue(telemetry?["SystemPowerIn"])
        let systemLoad = milliwattsValue(telemetry?["SystemLoad"])
        let telemetryFlow: Double? = if let adapterInput, let systemLoad {
            adapterInput - systemLoad
        } else {
            nil
        }
        let batteryFlow = telemetryFlow ?? electricalFlow
        let adapterDetails = dictionaryValue(registry["AdapterDetails"])
        let adapterRated = positiveDouble(adapterDetails?["Watts"])

        return BatterySnapshot(
            level: level,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isCharged: isCharged,
            timeRemainingMinutes: timeRemaining,
            temperatureCelsius: temperature,
            currentMilliamps: currentMilliamps,
            voltageVolts: voltage,
            powerWatts: batteryFlow.map(abs),
            designCapacityMAh: designCapacity,
            maxCapacityMAh: maxCapacity,
            currentCapacityMAh: currentCapacity,
            healthPercent: healthPercent,
            cycleCount: firstNonNegative([intValue(registry["CycleCount"])]),
            isLowPowerMode: isLowPowerMode,
            adapterWatts: adapterInput,
            adapterRatedWatts: adapterRated,
            systemLoadWatts: systemLoad,
            batteryFlowWatts: batteryFlow
        )
    }

    nonisolated private static func smartBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &unmanaged,
            kCFAllocatorDefault,
            0
        ) == kIOReturnSuccess,
            let properties = unmanaged?.takeRetainedValue() as? [String: Any]
        else {
            return nil
        }
        return properties
    }

    nonisolated private static func dictionaryValue(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    nonisolated private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        return (value as? NSNumber)?.boolValue
    }

    nonisolated private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        return value as? Double
    }

    nonisolated private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        return value as? Int
    }

    nonisolated private static func positiveDouble(_ value: Any?) -> Double? {
        doubleValue(value).flatMap { $0 > 0 ? $0 : nil }
    }

    nonisolated private static func legacyCapacity(_ value: Any?) -> Int? {
        intValue(value).flatMap { $0 > 100 ? $0 : nil }
    }

    nonisolated private static func firstPositive(_ values: [Int?]) -> Int? {
        values.compactMap { $0 }.first { $0 > 0 }
    }

    nonisolated private static func firstNonNegative(_ values: [Int?]) -> Int? {
        values.compactMap { $0 }.first { $0 >= 0 }
    }

    nonisolated private static func normalizedTemperature(_ rawValue: Double?) -> Double? {
        guard let rawValue else { return nil }
        let celsius = rawValue > 200 ? rawValue / 100 : rawValue
        return (-20...100).contains(celsius) ? celsius : nil
    }

    nonisolated private static func milliwattsValue(_ value: Any?) -> Double? {
        doubleValue(value).flatMap { $0 >= 0 ? $0 / 1_000 : nil }
    }

    private static func loadDate(_ defaults: UserDefaults, forKey key: String) -> Date? {
        guard let value = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(value) == CFNumberGetTypeID()
        else {
            return nil
        }
        let timestamp = value.doubleValue
        guard timestamp.isFinite, timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func storeDate(_ date: Date?, forKey key: String) {
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
