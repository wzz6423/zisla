import Foundation
import IOKit.ps
import Testing

@testable import ZislaKit

struct BatteryMonitorTests {
    @Test
    func parsesPowerSourceStatusAndTime() throws {
        let snapshot = try #require(BatteryMonitor.snapshot(from: powerSource(
            level: 75,
            charging: false,
            state: kIOPSBatteryPowerValue as String,
            timeToEmpty: 120
        )))

        #expect(snapshot.level == 0.75)
        #expect(!snapshot.isCharging)
        #expect(!snapshot.isPluggedIn)
        #expect(snapshot.timeRemainingMinutes == 120)
    }

    @Test
    func rejectsUnknownTimeSentinels() throws {
        let snapshot = try #require(BatteryMonitor.snapshot(from: powerSource(
            level: 50,
            charging: false,
            timeToEmpty: 65_535
        )))

        #expect(snapshot.timeRemainingMinutes == nil)
    }

    @Test
    func parsesModernAppleSiliconRegistryMetrics() throws {
        let registry: [String: Any] = [
            "Temperature": 3_450,
            "InstantAmperage": -1_500,
            "Voltage": 12_500,
            "CycleCount": 123,
            "AdapterDetails": ["Watts": 94],
            "PowerTelemetryData": [
                "SystemPowerIn": 65_000,
                "SystemLoad": 45_000,
            ],
            "BatteryData": [
                "RemainingCapacity": 4_695,
                "NominalChargeCapacity": 6_376,
                "FullChargeCapacity": 6_224,
                "DesignCapacity": 6_249,
            ],
            // These are normalized percentages on current Apple Silicon Macs.
            "CurrentCapacity": 80,
            "MaxCapacity": 100,
        ]

        let snapshot = try #require(BatteryMonitor.snapshot(
            from: powerSource(
                level: 80,
                charging: true,
                state: kIOPSACPowerValue as String,
                timeToFull: 35
            ),
            registry: registry,
            isLowPowerMode: true
        ))

        #expect(snapshot.level == 0.8)
        #expect(snapshot.currentCapacityMAh == 4_695)
        #expect(snapshot.maxCapacityMAh == 6_224)
        #expect(snapshot.designCapacityMAh == 6_249)
        #expect(snapshot.healthPercent == 100)
        #expect(snapshot.cycleCount == 123)
        #expect(snapshot.temperatureCelsius == 34.5)
        #expect(snapshot.currentMilliamps == -1_500)
        #expect(snapshot.voltageVolts == 12.5)
        #expect(snapshot.adapterWatts == 65)
        #expect(snapshot.adapterRatedWatts == 94)
        #expect(snapshot.systemLoadWatts == 45)
        #expect(snapshot.batteryFlowWatts == 20)
        #expect(snapshot.powerWatts == 20)
        #expect(snapshot.isLowPowerMode)
    }

    @Test
    func prefersFullChargeCapacityForHealth() throws {
        let snapshot = try #require(BatteryMonitor.snapshot(
            from: powerSource(level: 80),
            registry: [
                "BatteryData": [
                    "FullChargeCapacity": 4_800,
                    "NominalChargeCapacity": 5_200,
                    "DesignCapacity": 6_000,
                ],
            ]
        ))

        #expect(snapshot.maxCapacityMAh == 4_800)
        #expect(snapshot.healthPercent == 80)
    }

    @Test
    func fallsBackToLegacyIntegerCapacityFields() throws {
        let registry: [String: Any] = [
            "CurrentCapacity": 4_200,
            "MaxCapacity": 5_000,
            "DesignCapacity": 6_000,
        ]
        let snapshot = try #require(BatteryMonitor.snapshot(
            from: powerSource(level: 70),
            registry: registry
        ))

        #expect(snapshot.currentCapacityMAh == 4_200)
        #expect(snapshot.maxCapacityMAh == 5_000)
        #expect(snapshot.designCapacityMAh == 6_000)
        #expect(snapshot.healthPercent == 83)
    }

    @Test
    func doesNotLabelNormalizedPercentagesAsMilliampHours() throws {
        let snapshot = try #require(BatteryMonitor.snapshot(
            from: powerSource(level: 80),
            registry: ["CurrentCapacity": 80, "MaxCapacity": 100]
        ))

        #expect(snapshot.currentCapacityMAh == nil)
        #expect(snapshot.maxCapacityMAh == nil)
        #expect(snapshot.healthPercent == nil)
    }

    @Test
    func derivesBatteryDischargeFromPowerTelemetry() throws {
        let snapshot = try #require(BatteryMonitor.snapshot(
            from: powerSource(level: 60, state: kIOPSBatteryPowerValue as String),
            registry: [
                "PowerTelemetryData": [
                    "SystemPowerIn": 0,
                    "SystemLoad": 28_000,
                ],
            ]
        ))

        #expect(snapshot.adapterWatts == 0)
        #expect(snapshot.systemLoadWatts == 28)
        #expect(snapshot.batteryFlowWatts == -28)
        #expect(snapshot.powerWatts == 28)
    }

    @Test
    func rejectsNonBatteryPowerSources() {
        let description: [String: Any] = [
            kIOPSTypeKey as String: "UPS",
            kIOPSCurrentCapacityKey as String: 50,
            kIOPSMaxCapacityKey as String: 100,
        ]
        #expect(BatteryMonitor.snapshot(from: description) == nil)
    }

    @Test
    func clampsLevelAndOnlyShowsBoltWhileCharging() {
        let held = BatterySnapshot(
            level: 1.4,
            isCharging: false,
            isPluggedIn: true,
            isCharged: false,
            timeRemainingMinutes: nil
        )
        let charging = BatterySnapshot(
            level: 0.5,
            isCharging: true,
            isPluggedIn: true,
            isCharged: false,
            timeRemainingMinutes: nil
        )

        #expect(held.level == 1)
        #expect(held.symbolName == "battery.100percent")
        #expect(charging.symbolName == "battery.100percent.bolt")
    }

    @Test @MainActor
    func recordsTimestampWhenExternalPowerDisconnects() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var clock = Date(timeIntervalSince1970: 2_000_000)
        let monitor = BatteryMonitor(defaults: defaults, now: { clock })

        let pluggedIn = BatterySnapshot(
            level: 0.8,
            isCharging: false,
            isPluggedIn: true,
            isCharged: false,
            timeRemainingMinutes: nil
        )
        monitor.detectStateTransitions(from: nil, to: pluggedIn)
        #expect(monitor.lastUnpluggedAt == nil)

        clock = Date(timeIntervalSince1970: 2_000_200)
        let onBattery = BatterySnapshot(
            level: 0.8,
            isCharging: false,
            isPluggedIn: false,
            isCharged: false,
            timeRemainingMinutes: 240
        )
        monitor.detectStateTransitions(from: pluggedIn, to: onBattery)
        #expect(monitor.lastUnpluggedAt == clock)
    }

    @Test @MainActor
    func persistsTimestampsAcrossInstances() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let clock = Date(timeIntervalSince1970: 3_000_000)
        let first = BatteryMonitor(defaults: defaults, now: { clock })

        let plugged = BatterySnapshot(
            level: 1.0,
            isCharging: false,
            isPluggedIn: true,
            isCharged: true,
            timeRemainingMinutes: nil
        )
        let onBattery = BatterySnapshot(
            level: 1.0,
            isCharging: false,
            isPluggedIn: false,
            isCharged: false,
            timeRemainingMinutes: 300
        )
        first.detectStateTransitions(from: plugged, to: onBattery)

        let second = BatteryMonitor(defaults: defaults, now: { Date() })
        #expect(second.lastUnpluggedAt == clock)
    }

    @Test @MainActor
    func usesPersistedObservedStateToDetectTransitionsAfterRestart() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var clock = Date(timeIntervalSince1970: 3_100_000)
        let first = BatteryMonitor(defaults: defaults, now: { clock })
        let plugged = BatterySnapshot(
            level: 0.8,
            isCharging: false,
            isPluggedIn: true,
            isCharged: false,
            timeRemainingMinutes: nil
        )
        first.detectStateTransitions(from: nil, to: plugged)

        let second = BatteryMonitor(defaults: defaults, now: { clock })
        clock = Date(timeIntervalSince1970: 3_100_200)
        let onBattery = BatterySnapshot(
            level: 0.99,
            isCharging: false,
            isPluggedIn: false,
            isCharged: false,
            timeRemainingMinutes: 180
        )
        second.detectStateTransitions(from: nil, to: onBattery)
        #expect(second.lastUnpluggedAt == clock)
    }

    @Test @MainActor
    func handlesFirstRunWithoutStoredTimestamps() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let monitor = BatteryMonitor(defaults: defaults, now: Date.init)

        #expect(monitor.lastUnpluggedAt == nil)

        let onBattery = BatterySnapshot(
            level: 0.6,
            isCharging: false,
            isPluggedIn: false,
            isCharged: false,
            timeRemainingMinutes: 180
        )
        monitor.detectStateTransitions(from: nil, to: onBattery)

        #expect(monitor.lastUnpluggedAt == nil)
    }

    @Test @MainActor
    func ignoresInvalidPersistedDateStrings() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("2024-13-45T99:99:99Z", forKey: "zisla.battery.last-unplugged-at")

        let monitor = BatteryMonitor(defaults: defaults, now: Date.init)

        #expect(monitor.lastUnpluggedAt == nil)
    }

    @Test @MainActor
    func doesNotRecordUnpluggedWhenAlreadyOnBattery() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var clock = Date(timeIntervalSince1970: 5_000_000)
        let monitor = BatteryMonitor(defaults: defaults, now: { clock })

        let onBattery1 = BatterySnapshot(
            level: 0.7,
            isCharging: false,
            isPluggedIn: false,
            isCharged: false,
            timeRemainingMinutes: 120
        )
        monitor.detectStateTransitions(from: nil, to: onBattery1)
        let firstTimestamp = monitor.lastUnpluggedAt

        clock = Date(timeIntervalSince1970: 5_000_300)
        let onBattery2 = BatterySnapshot(
            level: 0.65,
            isCharging: false,
            isPluggedIn: false,
            isCharged: false,
            timeRemainingMinutes: 110
        )
        monitor.detectStateTransitions(from: onBattery1, to: onBattery2)

        #expect(monitor.lastUnpluggedAt == firstTimestamp)
    }

    @Test @MainActor
    func handlesNilSnapshotGracefully() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let monitor = BatteryMonitor(defaults: defaults, now: Date.init)

        let charging = BatterySnapshot(
            level: 0.8,
            isCharging: true,
            isPluggedIn: true,
            isCharged: false,
            timeRemainingMinutes: 20
        )
        monitor.detectStateTransitions(from: nil, to: charging)
        monitor.detectStateTransitions(from: charging, to: nil)

        #expect(monitor.lastUnpluggedAt == nil)
    }

    private func powerSource(
        level: Int,
        charging: Bool = false,
        state: String = kIOPSBatteryPowerValue as String,
        timeToEmpty: Int? = nil,
        timeToFull: Int? = nil
    ) -> [String: Any] {
        var description: [String: Any] = [
            kIOPSTypeKey as String: kIOPSInternalBatteryType as String,
            kIOPSCurrentCapacityKey as String: level,
            kIOPSMaxCapacityKey as String: 100,
            kIOPSIsChargingKey as String: charging,
            kIOPSIsChargedKey as String: false,
            kIOPSPowerSourceStateKey as String: state,
        ]
        if let timeToEmpty {
            description[kIOPSTimeToEmptyKey as String] = timeToEmpty
        }
        if let timeToFull {
            description[kIOPSTimeToFullChargeKey as String] = timeToFull
        }
        return description
    }
}
