import AppKit
import CoreFoundation
import Foundation
import IOKit.ps
import Testing

@testable import ZislaKit

struct BatteryMonitorTests {
    @Test(arguments: [true, false])
    func systemPowerUsesSystemLoadInsteadOfBatteryFlow(isPluggedIn: Bool) {
        let battery = BatterySnapshot(
            level: 0.8, isCharging: isPluggedIn, isPluggedIn: isPluggedIn,
            isCharged: false, timeRemainingMinutes: nil, powerWatts: 60,
            adapterRatedWatts: 100, systemLoadWatts: 24, batteryFlowWatts: -12
        )
        #expect(battery.systemPowerWatts == 24)
    }

    @Test
    func unknownSystemPowerNeverUsesAdapterRatingOrChargingPower() {
        var battery = BatterySnapshot(
            level: 1, isCharging: false, isPluggedIn: true, isCharged: true,
            timeRemainingMinutes: nil, powerWatts: 0, adapterRatedWatts: 96, batteryFlowWatts: 0
        )
        #expect(battery.systemPowerWatts == nil)
        battery.systemLoadWatts = 0
        #expect(battery.systemPowerWatts == 0)
        battery.isPluggedIn = false
        battery.systemLoadWatts = nil
        battery.powerWatts = nil
        battery.batteryFlowWatts = -12
        #expect(battery.systemPowerWatts == nil)
        battery.batteryFlowWatts = nil
        #expect(battery.systemPowerWatts == nil)
    }

    @Test @MainActor
    func fullyChargedBatteryTrendStillRecordsTheMachinesLoad() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var date = Date(timeIntervalSince1970: 1_000)
        var battery = BatterySnapshot(
            level: 1, isCharging: false, isPluggedIn: true, isCharged: true,
            timeRemainingMinutes: nil, powerWatts: 0, adapterRatedWatts: 96,
            systemLoadWatts: 24, batteryFlowWatts: 0
        )
        let monitor = BatteryMonitor(
            defaults: defaults, now: { date }, notificationCenter: NotificationCenter(),
            snapshotProvider: { battery }, runLoopSourceFactory: { _ in nil }
        )
        monitor.refresh()
        #expect(monitor.trendSamples.first?.systemPowerWatts == 24)
        battery.systemLoadWatts = nil
        date.addTimeInterval(5)
        monitor.refresh()
        #expect(monitor.trendSamples.count == 2)
        #expect(monitor.trendSamples.last?.systemPowerWatts == nil)
    }

    @Test @MainActor
    func recordsBoundedTrendAtSamplingCadence() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var date = Date(timeIntervalSince1970: 1_000)
        let battery = try #require(BatteryMonitor.snapshot(
            from: powerSource(level: 60), registry: [
                "InstantAmperage": -1_000,
                "Voltage": 12_000,
                "PowerTelemetryData": ["SystemPowerIn": 0, "SystemLoad": 12_000],
            ]
        ))
        let monitor = BatteryMonitor(
            defaults: defaults, now: { date }, notificationCenter: NotificationCenter(),
            snapshotProvider: { battery }, runLoopSourceFactory: { _ in nil }
        )
        monitor.refresh()
        date.addTimeInterval(1)
        monitor.refresh()
        #expect(monitor.trendSamples.count == 1)
        for _ in 0..<65 {
            date.addTimeInterval(5)
            monitor.refresh()
        }
        #expect(monitor.trendSamples.count == 60)
        #expect(monitor.trendSamples.first?.date == Date(timeIntervalSince1970: 1_031))
        #expect(monitor.trendSamples.last?.date == date)
        #expect(monitor.trendSamples.allSatisfy { $0.level == 0.6 && $0.systemPowerWatts == 12 })
    }

    @Test(arguments: [-1.0, 16.0, 3_600.0]) @MainActor
    func trendRestartsAcrossTimeDiscontinuities(interval: TimeInterval) throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var date = Date(timeIntervalSince1970: 1_000)
        let battery = try #require(BatteryMonitor.snapshot(from: powerSource(level: 60)))
        let monitor = BatteryMonitor(
            defaults: defaults, now: { date }, notificationCenter: NotificationCenter(),
            snapshotProvider: { battery }, runLoopSourceFactory: { _ in nil }
        )
        monitor.refresh()
        date.addTimeInterval(5)
        monitor.refresh()
        #expect(monitor.trendSamples.count == 2)
        date.addTimeInterval(interval)
        monitor.refresh()
        #expect(monitor.trendSamples.count == 1)
        #expect(monitor.trendSamples.first?.date == date)
    }

    @Test @MainActor
    func missingBatteryAndPowerPreserveGaps() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var date = Date(timeIntervalSince1970: 1_000)
        let available = try #require(BatteryMonitor.snapshot(
            from: powerSource(level: 60), registry: [
                "InstantAmperage": -1_000,
                "Voltage": 12_000,
                "PowerTelemetryData": ["SystemPowerIn": 0, "SystemLoad": 12_000],
            ]
        ))
        var current: BatterySnapshot? = available
        let monitor = BatteryMonitor(
            defaults: defaults, now: { date }, notificationCenter: NotificationCenter(),
            snapshotProvider: { current }, runLoopSourceFactory: { _ in nil }
        )
        monitor.refresh()
        current?.systemLoadWatts = nil
        current?.powerWatts = nil
        current?.batteryFlowWatts = nil
        date.addTimeInterval(1)
        monitor.refresh()
        #expect(monitor.trendSamples.count == 2)
        #expect(monitor.trendSamples.last?.systemPowerWatts == nil)
        current = nil
        monitor.refresh()
        #expect(monitor.trendSamples.isEmpty)
        current = available
        monitor.refresh()
        #expect(monitor.trendSamples.count == 1)
        #expect(monitor.trendSamples.first?.date == date)
    }

    @Test @MainActor
    func trendTimerAndWakeObservationFollowMonitorLifecycle() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let workspaceCenter = BatteryTestNotificationCenter()
        var date = Date(timeIntervalSince1970: 1_000)
        let battery = try #require(BatteryMonitor.snapshot(from: powerSource(level: 60)))
        var timers: [Timer] = []
        var readCount = 0
        var monitor: BatteryMonitor? = BatteryMonitor(
            defaults: defaults, now: { date }, notificationCenter: NotificationCenter(),
            snapshotProvider: { readCount += 1; return battery }, runLoopSourceFactory: { _ in nil },
            workspaceNotificationCenter: workspaceCenter,
            timerFactory: { interval, block in
                let timer = Timer(timeInterval: interval, repeats: true, block: block)
                timers.append(timer)
                return timer
            }
        )
        monitor?.start()
        monitor?.start()
        #expect(timers.count == 1)
        #expect(timers.first?.timeInterval == 5)
        #expect(workspaceCenter.notificationHandlers.count == 1)
        date.addTimeInterval(5)
        timers.first?.fireDate = .distantPast
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        #expect(monitor?.trendSamples.count == 2)
        #expect(readCount == 3)
        date.addTimeInterval(1)
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(monitor?.trendSamples.count == 1)
        #expect(monitor?.trendSamples.first?.date == date)
        let delayedWake = try #require(workspaceCenter.notificationHandlers.first)
        monitor?.stop()
        #expect(timers.first?.isValid == false)
        #expect(monitor?.trendSamples.isEmpty == true)
        #expect(workspaceCenter.removedObserverCount == 1)
        delayedWake(Notification(name: NSWorkspace.didWakeNotification))
        #expect(readCount == 4)
        #expect(monitor?.trendSamples.isEmpty == true)
        monitor?.start()
        #expect(timers.count == 2)
        #expect(workspaceCenter.notificationHandlers.count == 2)
        delayedWake(Notification(name: NSWorkspace.didWakeNotification))
        #expect(readCount == 5)
        weak var retainedMonitor = monitor
        monitor = nil
        #expect(retainedMonitor == nil)
        #expect(timers.last?.isValid == false)
        #expect(workspaceCenter.removedObserverCount == 2)
    }

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

    @Test @MainActor
    func refreshesLowPowerSnapshotOnPowerStateNotification() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = NotificationCenter()
        var current = try #require(BatteryMonitor.snapshot(from: powerSource(level: 100)))
        let monitor = BatteryMonitor(
            defaults: defaults,
            notificationCenter: center,
            snapshotProvider: { current },
            runLoopSourceFactory: { _ in nil }
        )
        defer { monitor.stop() }

        monitor.start()
        #expect(monitor.snapshot?.isLowPowerMode == false)

        current.isLowPowerMode = true
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        #expect(monitor.snapshot?.isLowPowerMode == true)

        current.isLowPowerMode = false
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        #expect(monitor.snapshot?.isLowPowerMode == false)
        #expect(monitor.lastUnpluggedAt == nil)
    }

    @Test @MainActor
    func powerStateObservationSurvivesPowerSourceAndSnapshotFailures() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = NotificationCenter()
        let lowPowerSnapshot = try #require(BatteryMonitor.snapshot(
            from: powerSource(level: 10), isLowPowerMode: true
        ))
        let recoveredSnapshot = try #require(BatteryMonitor.snapshot(from: powerSource(level: 50)))
        var current: BatterySnapshot?
        let monitor = BatteryMonitor(
            defaults: defaults,
            notificationCenter: center,
            snapshotProvider: { current },
            runLoopSourceFactory: { _ in nil }
        )
        defer { monitor.stop() }

        monitor.start()
        #expect(monitor.snapshot == nil)

        current = lowPowerSnapshot
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        #expect(monitor.snapshot == current)

        current = nil
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        #expect(monitor.snapshot == nil)

        current = recoveredSnapshot
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        #expect(monitor.snapshot == current)
        #expect(monitor.lastUnpluggedAt == nil)
    }

    @Test(arguments: [false, true]) @MainActor
    func startingTwiceDoesNotDuplicatePowerStateObservation(initialSourceCreationFails: Bool) throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = BatteryTestNotificationCenter()
        var context = CFRunLoopSourceContext()
        context.info = Unmanaged.passUnretained(center).toOpaque()
        let source = try #require(CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context))
        var current = try #require(BatteryMonitor.snapshot(from: powerSource(level: 100)))
        var readCount = 0
        var sourceCreationCount = 0
        let monitor = BatteryMonitor(
            defaults: defaults,
            notificationCenter: center,
            snapshotProvider: { readCount += 1; return current },
            runLoopSourceFactory: { _ in
                sourceCreationCount += 1
                return initialSourceCreationFails && sourceCreationCount == 1 ? nil : source
            }
        )
        defer { monitor.stop() }

        monitor.start()
        #expect(CFRunLoopContainsSource(CFRunLoopGetMain(), source, .commonModes) == !initialSourceCreationFails)
        current.isLowPowerMode = true
        monitor.start()
        #expect(center.notificationHandlers.count == 1)
        #expect(readCount == 2)
        #expect(sourceCreationCount == (initialSourceCreationFails ? 2 : 1))
        #expect(CFRunLoopContainsSource(CFRunLoopGetMain(), source, .commonModes))
        #expect(monitor.snapshot?.isLowPowerMode == true)

        current.isLowPowerMode = false
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        #expect(readCount == 3)
        #expect(monitor.snapshot?.isLowPowerMode == false)
    }

    @Test(arguments: [false, true]) @MainActor
    func stopAndRestartCleanUpPowerStateObservationAndRunLoopSource(initialSourceCreationFails: Bool) throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = BatteryTestNotificationCenter()
        var context = CFRunLoopSourceContext()
        context.info = Unmanaged.passUnretained(center).toOpaque()
        let source = try #require(CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context))
        var current = try #require(BatteryMonitor.snapshot(from: powerSource(level: 100)))
        var readCount = 0
        var sourceCreationCount = 0
        let monitor = BatteryMonitor(
            defaults: defaults,
            notificationCenter: center,
            snapshotProvider: { readCount += 1; return current },
            runLoopSourceFactory: { _ in
                sourceCreationCount += 1
                return initialSourceCreationFails && sourceCreationCount == 1 ? nil : source
            }
        )
        defer { monitor.stop() }

        monitor.start()
        #expect(CFRunLoopContainsSource(CFRunLoopGetMain(), source, .commonModes) == !initialSourceCreationFails)
        monitor.stop()
        monitor.stop()
        #expect(center.removedObserverCount == 1)
        #expect(!CFRunLoopContainsSource(CFRunLoopGetMain(), source, .commonModes))

        current.isLowPowerMode = true
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        #expect(readCount == 1)
        #expect(monitor.snapshot?.isLowPowerMode == false)

        monitor.start()
        #expect(sourceCreationCount == 2)
        #expect(center.notificationHandlers.count == 2)
        #expect(CFRunLoopContainsSource(CFRunLoopGetMain(), source, .commonModes))
        #expect(monitor.snapshot?.isLowPowerMode == true)
        current.isLowPowerMode = false
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        #expect(readCount == 3)
        #expect(monitor.snapshot?.isLowPowerMode == false)
    }

    @Test @MainActor
    func ignoresPowerStateDeliveryFromStoppedObservation() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = BatteryTestNotificationCenter()
        var current = try #require(BatteryMonitor.snapshot(from: powerSource(level: 100)))
        var readCount = 0
        let monitor = BatteryMonitor(
            defaults: defaults,
            notificationCenter: center,
            snapshotProvider: { readCount += 1; return current },
            runLoopSourceFactory: { _ in nil }
        )
        defer { monitor.stop() }

        monitor.start()
        let delayedDelivery = try #require(center.notificationHandlers.first)
        monitor.stop()
        current.isLowPowerMode = true
        delayedDelivery(Notification(name: .NSProcessInfoPowerStateDidChange))
        #expect(readCount == 1)
        #expect(monitor.snapshot?.isLowPowerMode == false)

        monitor.start()
        current.isLowPowerMode = false
        delayedDelivery(Notification(name: .NSProcessInfoPowerStateDidChange))
        #expect(readCount == 2)
        #expect(monitor.snapshot?.isLowPowerMode == true)

        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        #expect(readCount == 3)
        #expect(monitor.snapshot?.isLowPowerMode == false)
    }

    @Test @MainActor
    func deinitializingMonitorRemovesPowerStateObserverAndRunLoopSource() throws {
        let suiteName = "Zisla.BatteryMonitorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = BatteryTestNotificationCenter()
        var context = CFRunLoopSourceContext()
        context.info = Unmanaged.passUnretained(center).toOpaque()
        let source = try #require(CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context))
        var monitor: BatteryMonitor? = BatteryMonitor(
            defaults: defaults,
            notificationCenter: center,
            snapshotProvider: { nil },
            runLoopSourceFactory: { _ in source }
        )
        weak var retainedMonitor = monitor
        monitor?.start()
        #expect(CFRunLoopContainsSource(CFRunLoopGetMain(), source, .commonModes))

        monitor = nil
        #expect(retainedMonitor == nil)
        #expect(center.removedObserverCount == 1)
        #expect(!CFRunLoopContainsSource(CFRunLoopGetMain(), source, .commonModes))
    }

    @Test
    func registersPowerSourceNotificationsInCommonRunLoopModes() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ZislaKit/BatteryMonitor.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)"))
        #expect(source.contains("CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)"))
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

private final class BatteryTestNotificationCenter: NotificationCenter, @unchecked Sendable {
    private(set) var notificationHandlers: [@Sendable (Notification) -> Void] = []
    private(set) var removedObserverCount = 0

    override func addObserver(
        forName name: Notification.Name?,
        object: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> NSObjectProtocol {
        notificationHandlers.append(block)
        return super.addObserver(forName: name, object: object, queue: queue, using: block)
    }

    override func removeObserver(_ observer: Any) {
        removedObserverCount += 1
        super.removeObserver(observer)
    }
}
