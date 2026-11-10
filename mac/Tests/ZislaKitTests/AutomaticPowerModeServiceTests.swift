import Foundation
import Testing
import struct ZislaCore.FeatureSettings

@testable import ZislaKit

@MainActor
struct AutomaticPowerModeServiceTests {
    @Test(arguments: BatteryPowerMode.allCases, BatteryPowerMode.allCases)
    func eachPowerSourceUsesItsConfiguredDefault(adapter: BatteryPowerMode, battery: BatteryPowerMode) async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        defer { service.stop() }
        let settings = FeatureSettings(automaticPowerModeEnabled: true,
            powerAdapterDefaultMode: adapter, batteryDefaultMode: battery, lowBatteryPowerModeEnabled: false)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        #expect(fixture.adapterMode == adapter)
        #expect(fixture.batteryMode == .automatic)
        fixture.source = .battery
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        #expect(fixture.batteryMode == battery)
        #expect(fixture.adapterMode == adapter)
        #expect(!service.manualPaused)
        #expect(service.error == nil)
        #expect(fixture.changes.count == (adapter == .automatic ? 0 : 1) + (battery == .automatic ? 0 : 1))
    }

    @Test
    func defaultDisabledAutomationDoesNotObserveManualChangesOrCreateAPhase() async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        defer { service.stop() }
        fixture.notifications.post(name: BatteryPowerModeController.manualModeChangeNotification, object: nil)
        #expect(!service.manualPaused)
        #expect(fixture.defaults.data(forKey: "automatic-power-mode-phase-v1") == nil)
        var settings = FeatureSettings.default
        service.apply(settings: settings, snapshot: fixture.snapshot())
        fixture.notifications.post(name: BatteryPowerModeController.manualModeChangeNotification, object: nil)
        #expect(!service.manualPaused)
        #expect(fixture.defaults.data(forKey: "automatic-power-mode-phase-v1") == nil)
        fixture.source = .battery
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
        #expect(fixture.defaults.data(forKey: "automatic-power-mode-phase-v1") == nil)
        settings.automaticPowerModeEnabled = true
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
        await fixture.drain(service)
        #expect(!service.manualPaused)
        #expect(fixture.batteryMode == .lowPower)
        #expect(fixture.changes == [["-b", "powermode", "1"]])
    }

    @Test
    func manualChangesWhileDisabledDoNotCreatePauseButPreserveAnExistingManualPause() async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        defer { service.stop() }
        var settings = FeatureSettings(automaticPowerModeEnabled: true)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        settings.automaticPowerModeEnabled = false
        service.apply(settings: settings, snapshot: fixture.snapshot())
        fixture.notifications.post(name: BatteryPowerModeController.manualModeChangeNotification, object: nil)
        #expect(!service.manualPaused)
        settings.automaticPowerModeEnabled = true
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        fixture.notifications.post(name: BatteryPowerModeController.manualModeChangeNotification, object: nil)
        #expect(service.manualPaused)
        settings.automaticPowerModeEnabled = false
        service.apply(settings: settings, snapshot: fixture.snapshot())
        fixture.notifications.post(name: BatteryPowerModeController.manualModeChangeNotification, object: nil)
        settings.automaticPowerModeEnabled = true
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
        await fixture.drain(service)
        #expect(service.manualPaused)
        #expect(fixture.changes.isEmpty)
    }

    @Test(arguments: [BatteryPowerSource.battery, .powerAdapter], [0.0, 0.1999, 0.20, 0.2001, 1.0])
    func lowChargeAtOrBelowTwentyPercentOverridesBothSourcesAndRestoresDefault(
        source: BatteryPowerSource, level: Double
    ) async throws {
        let fixture = try PowerFixture()
        fixture.source = source
        let service = fixture.service()
        defer { service.stop() }
        let settings = FeatureSettings(automaticPowerModeEnabled: true,
            powerAdapterDefaultMode: .highPower, batteryDefaultMode: .highPower)
        service.apply(settings: settings, snapshot: fixture.snapshot(level: level))
        await fixture.drain(service)
        #expect(fixture.currentMode == (level <= 0.20 ? .lowPower : .highPower))
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.2001))
        await fixture.drain(service)
        #expect(fixture.currentMode == .highPower)
        #expect(service.error == nil)
        #expect(!service.manualPaused)
    }

    @Test(arguments: [false, true], [false, true])
    func bothFeatureSwitchesGateAllSystemRequests(systemEnabled: Bool, automaticEnabled: Bool) async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        defer { service.stop() }
        let settings = FeatureSettings(systemMonitorEnabled: systemEnabled,
            automaticPowerModeEnabled: automaticEnabled, powerAdapterDefaultMode: .highPower)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        #expect(fixture.requests.isEmpty == !(systemEnabled && automaticEnabled))
        #expect(fixture.changes.isEmpty == !(systemEnabled && automaticEnabled))
    }

    @Test(arguments: [Double.nan, Double.infinity, -0.1, 1.1])
    func unavailableOrInvalidBatteryNeverReadsOrChangesPowerMode(level: Double) async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        defer { service.stop() }
        let settings = FeatureSettings(automaticPowerModeEnabled: true, powerAdapterDefaultMode: .highPower)
        service.apply(settings: settings, snapshot: nil)
        var snapshot = fixture.snapshot()
        snapshot.level = level
        service.apply(settings: settings, snapshot: snapshot)
        await fixture.drain(service)
        #expect(fixture.requests.isEmpty)
        #expect(fixture.changes.isEmpty)
    }

    @Test
    func disablingTheLowChargeOverrideUsesTheConfiguredModeAtLowCharge() async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        defer { service.stop() }
        var settings = FeatureSettings(automaticPowerModeEnabled: true, powerAdapterDefaultMode: .highPower)
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
        await fixture.drain(service)
        #expect(fixture.currentMode == .lowPower)
        settings.lowBatteryPowerModeEnabled = false
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
        await fixture.drain(service)
        #expect(fixture.currentMode == .highPower)
        #expect(!service.manualPaused)
    }

    @Test
    func periodicReadDetectsAnExternalManualChangeAndPausesAcrossChargeAndSettingsChanges() async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        defer { service.stop() }
        var settings = FeatureSettings(automaticPowerModeEnabled: true, powerAdapterDefaultMode: .highPower)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        fixture.adapterMode = .automatic
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.2))
        await fixture.drain(service)
        #expect(service.manualPaused)
        #expect(fixture.adapterMode == .automatic)
        let requests = fixture.requests.count
        settings.powerAdapterDefaultMode = .lowPower
        settings.notificationsMuted = true
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.05))
        await fixture.drain(service)
        #expect(fixture.requests.count == requests)
        #expect(fixture.changes.count == 1)
        fixture.source = .battery
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.05))
        await fixture.drain(service)
        #expect(!service.manualPaused)
        #expect(fixture.batteryMode == .lowPower)
    }

    @Test
    func manualChangesInThisAppPauseBeforeAuthorizationAndResumeOnlyAfterUnplugging() async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        defer { service.stop() }
        let settings = FeatureSettings(automaticPowerModeEnabled: true, powerAdapterDefaultMode: .highPower)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        fixture.beforeRequest = { arguments in
            if arguments.first != "-g" { #expect(service.manualPaused) }
        }
        let manual = BatteryPowerModeController(runCommand: fixture.run, notificationCenter: fixture.notifications)
        #expect(await manual.setMode(.automatic))
        fixture.beforeRequest = nil
        #expect(service.manualPaused)
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
        await fixture.drain(service)
        #expect(fixture.adapterMode == .automatic)
        #expect(fixture.changes.count == 2)
        fixture.source = .battery
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
        await fixture.drain(service)
        #expect(fixture.batteryMode == .lowPower)
        #expect(!service.manualPaused)
    }

    @Test(arguments: [false, true])
    func sameSourceRelaunchKeepsManualPauseAndDetectsOfflineManualChanges(prePaused: Bool) async throws {
        let fixture = try PowerFixture()
        var service = fixture.service()
        var settings = FeatureSettings(automaticPowerModeEnabled: true, powerAdapterDefaultMode: .highPower)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        if prePaused {
            fixture.notifications.post(name: BatteryPowerModeController.manualModeChangeNotification, object: nil)
        }
        service.stop()
        fixture.adapterMode = .automatic
        let count = fixture.changes.count
        service = fixture.service()
        defer { service.stop() }
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
        await fixture.drain(service)
        #expect(service.manualPaused)
        #expect(fixture.changes.count == count)
        settings.automaticPowerModeEnabled = false
        service.apply(settings: settings, snapshot: fixture.snapshot())
        settings.automaticPowerModeEnabled = true
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
        await fixture.drain(service)
        #expect(service.manualPaused)
        #expect(fixture.changes.count == count)
        fixture.source = .battery
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
        await fixture.drain(service)
        #expect(!service.manualPaused)
        #expect(fixture.batteryMode == .lowPower)
    }

    @Test(arguments: [-128, -60005])
    func rejectedAuthorizationDoesNotRepeatUntilExplicitReenableOrSourceChange(code: Int32) async throws {
        let fixture = try PowerFixture()
        fixture.changeStatus = code
        var service = fixture.service()
        var settings = FeatureSettings(automaticPowerModeEnabled: true, powerAdapterDefaultMode: .highPower)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        #expect(service.error == (code == -128 ? .authorizationCancelled : .authorizationDenied))
        #expect(fixture.changes.count == 1)
        #expect(fixture.failures.count == 1)
        #expect(fixture.currentMode == .automatic)
        for _ in 0..<5 {
            service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
            await fixture.drain(service)
        }
        #expect(fixture.changes.count == 1)
        service.stop()
        service = fixture.service()
        defer { service.stop() }
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        #expect(fixture.changes.count == 1)
        fixture.changeStatus = 0
        settings.automaticPowerModeEnabled = false
        service.apply(settings: settings, snapshot: fixture.snapshot())
        settings.automaticPowerModeEnabled = true
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        #expect(fixture.currentMode == .highPower)
        #expect(fixture.changes.count == 2)
        #expect(service.error == nil)
        fixture.source = .battery
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        #expect(fixture.batteryMode == .lowPower)
    }

    @Test(arguments: ["none", "unsupported", "read", "timeout", "source"])
    func missingCapabilitiesOrReadFailureNeverRequestAuthorization(failure: String) async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        defer { service.stop() }
        switch failure {
        case "none": fixture.hasCapabilities = false
        case "unsupported": fixture.highPowerSupported = false
        case "read": fixture.readFails = true
        case "timeout": fixture.readTimesOut = true
        default: fixture.source = .battery
        }
        let settings = FeatureSettings(automaticPowerModeEnabled: true, powerAdapterDefaultMode: .highPower)
        let snapshot = BatterySnapshot(level: 0.7, isCharging: false, isPluggedIn: true,
            isCharged: false, timeRemainingMinutes: nil)
        service.apply(settings: settings, snapshot: snapshot)
        await fixture.drain(service)
        #expect(fixture.changes.isEmpty)
        #expect(service.error != nil)
        #expect(fixture.failures.count == 1)
        let requests = fixture.requests.count
        service.apply(settings: settings, snapshot: snapshot)
        await fixture.drain(service)
        #expect(fixture.requests.count == requests)
    }

    @Test
    func quickSourceAndConfigurationUpdatesBeforeExecutionApplyOnlyTheLatestRequest() async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        defer { service.stop() }
        var settings = FeatureSettings(automaticPowerModeEnabled: true, powerAdapterDefaultMode: .highPower)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        fixture.source = .battery
        service.apply(settings: settings, snapshot: fixture.snapshot())
        settings.batteryDefaultMode = .highPower
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.2))
        service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.3))
        await fixture.drain(service)
        #expect(fixture.changes == [["-b", "powermode", "2"]])
        #expect(fixture.batteryMode == .highPower)
        #expect(fixture.adapterMode == .automatic)
        #expect(!service.manualPaused)
    }

    @Test(arguments: ["stop", "disable", "manual", "release"])
    func stoppingOrManualPausingQueuedWorkPreventsAllSystemCommands(action: String) async throws {
        let fixture = try PowerFixture()
        var service: AutomaticPowerModeService? = fixture.service()
        weak var reference = service
        var settings = FeatureSettings(automaticPowerModeEnabled: true, powerAdapterDefaultMode: .highPower)
        service?.apply(settings: settings, snapshot: fixture.snapshot())
        let task = try #require(service?.updateTask)
        switch action {
        case "stop": service?.stop()
        case "disable":
            settings.automaticPowerModeEnabled = false
            service?.apply(settings: settings, snapshot: fixture.snapshot())
        case "manual": fixture.notifications.post(name: BatteryPowerModeController.manualModeChangeNotification, object: nil)
        default: service = nil
        }
        await task.value
        #expect(fixture.requests.isEmpty)
        #expect(fixture.changes.isEmpty)
        if action == "release" { #expect(reference == nil) }
        service?.stop()
    }

    @Test
    func stoppingRemovesTheManualObserverAndRestartRestoresIt() async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        var settings = FeatureSettings(automaticPowerModeEnabled: true)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        service.stop()
        fixture.notifications.post(name: BatteryPowerModeController.manualModeChangeNotification, object: nil)
        #expect(!service.manualPaused)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        fixture.notifications.post(name: BatteryPowerModeController.manualModeChangeNotification, object: nil)
        await fixture.drain(service)
        #expect(service.manualPaused)
        settings.automaticPowerModeEnabled = false
        service.apply(settings: settings, snapshot: fixture.snapshot())
        service.stop()
    }

    @Test(arguments: ["manual", "source", "stop"])
    func cancelledPreflightCannotAuthorizeOrChangeTheLatestPhase(action: String) async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        defer { service.stop() }
        let gate = PowerCommandGate()
        fixture.gate = gate
        fixture.gatedArguments = ["-g", "custom"]
        let settings = FeatureSettings(automaticPowerModeEnabled: true, powerAdapterDefaultMode: .highPower)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await gate.waitUntilStarted()
        switch action {
        case "manual":
            fixture.notifications.post(name: BatteryPowerModeController.manualModeChangeNotification, object: nil)
            fixture.adapterMode = .lowPower
        case "source":
            fixture.source = .battery
            service.apply(settings: settings, snapshot: fixture.snapshot())
        default: service.stop()
        }
        await gate.release()
        await fixture.drain(service)
        #expect(service.manualPaused == (action == "manual"))
        #expect(service.error == nil)
        #expect(fixture.failures.isEmpty)
        if action == "source" {
            #expect(fixture.changes == [["-b", "powermode", "1"]])
            #expect(fixture.batteryMode == .lowPower)
        } else {
            #expect(fixture.changes.isEmpty)
            #expect(fixture.requests.count == 2)
        }
    }

    @Test(arguments: ["threshold", "configuration", "source", "manual", "stop"])
    func updatesDuringSubmittedChangesRemainSerialAndRespectTheLatestPhase(action: String) async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        defer { service.stop() }
        let gate = PowerCommandGate()
        fixture.gate = gate
        fixture.gatedArguments = ["-c", "powermode", "2"]
        var settings = FeatureSettings(automaticPowerModeEnabled: true, powerAdapterDefaultMode: .highPower)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await gate.waitUntilStarted()
        let original = try #require(service.updateTask)
        switch action {
        case "threshold": service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
        case "configuration":
            settings.powerAdapterDefaultMode = .lowPower
            service.apply(settings: settings, snapshot: fixture.snapshot())
        case "source":
            fixture.source = .battery
            service.apply(settings: settings, snapshot: fixture.snapshot())
        case "manual":
            fixture.notifications.post(name: BatteryPowerModeController.manualModeChangeNotification, object: nil)
            service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
        default: service.stop()
        }
        #expect(fixture.changes.count == 1)
        await gate.release()
        await original.value
        await fixture.drain(service)
        if action == "stop" || action == "manual" {
            #expect(fixture.changes.count == 1)
            #expect(service.manualPaused == (action == "manual"))
        } else {
            #expect(fixture.changes.count == 2)
            #expect(!service.manualPaused)
            #expect(fixture.currentMode == .lowPower)
            #expect(fixture.changes.last == (action == "source"
                ? ["-b", "powermode", "1"] : ["-c", "powermode", "1"]))
        }
    }

    @Test
    func repeatedSamplesDuringAnActiveCommandDoNotStartOverlappingRequests() async throws {
        let fixture = try PowerFixture()
        let service = fixture.service()
        defer { service.stop() }
        let gate = PowerCommandGate()
        fixture.gate = gate
        fixture.gatedArguments = ["-c", "powermode", "2"]
        let settings = FeatureSettings(automaticPowerModeEnabled: true, powerAdapterDefaultMode: .highPower)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await gate.waitUntilStarted()
        for _ in 0..<6 { service.apply(settings: settings, snapshot: fixture.snapshot()) }
        #expect(fixture.changes.count == 1)
        await gate.release()
        await fixture.drain(service)
        #expect(fixture.changes.count == 1)
        #expect(fixture.adapterMode == .highPower)
        #expect(!service.manualPaused)
        #expect(service.error == nil)
        let completedRequestCount = fixture.requests.count
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await fixture.drain(service)
        #expect(fixture.requests.count == completedRequestCount + 2,
                "An unchanged target should use only one read-only cap/custom refresh")
        #expect(fixture.changes.count == 1)
    }

    @Test(arguments: ["manual", "external", "source", "threshold", "disable"])
    func changesWhileWaitingForAuthorizationCannotOverrideTheLatestUserState(action: String) async throws {
        let fixture = try PowerFixture()
        let gate = PowerCommandGate()
        fixture.prepareAuthorization = { await gate.wait(); return 0 }
        let service = fixture.service()
        defer { service.stop() }
        var settings = FeatureSettings(automaticPowerModeEnabled: true, powerAdapterDefaultMode: .highPower)
        service.apply(settings: settings, snapshot: fixture.snapshot())
        await gate.waitUntilStarted()
        switch action {
        case "manual":
            fixture.notifications.post(name: BatteryPowerModeController.manualModeChangeNotification, object: nil)
            fixture.adapterMode = .lowPower
        case "external": fixture.adapterMode = .lowPower
        case "source":
            fixture.source = .battery
            service.apply(settings: settings, snapshot: fixture.snapshot())
        case "threshold": service.apply(settings: settings, snapshot: fixture.snapshot(level: 0.1))
        default:
            settings.automaticPowerModeEnabled = false
            service.apply(settings: settings, snapshot: fixture.snapshot())
        }
        fixture.prepareAuthorization = { 0 }
        await gate.release()
        await fixture.drain(service)
        if action == "source" {
            #expect(fixture.changes == [["-b", "powermode", "1"]])
        } else if action == "threshold" {
            #expect(fixture.changes == [["-c", "powermode", "1"]])
            #expect(fixture.adapterMode == .lowPower)
            #expect(!service.manualPaused)
        } else {
            #expect(fixture.changes.isEmpty)
            #expect(service.manualPaused == (action == "manual" || action == "external"))
        }
        #expect(!fixture.changes.contains { $0 == ["-c", "powermode", "2"] })
    }
}

@MainActor
private final class PowerFixture {
    let suite = "Zisla.AutomaticPowerMode.\(UUID().uuidString)"
    let defaults: UserDefaults
    let notifications = NotificationCenter()
    var source: BatteryPowerSource = .powerAdapter
    var adapterMode: BatteryPowerMode = .automatic
    var batteryMode: BatteryPowerMode = .automatic
    var hasCapabilities = true
    var highPowerSupported = true
    var readFails = false
    var readTimesOut = false
    var changeStatus: Int32 = 0
    var requests: [[String]] = []
    var failures: [BatteryPowerModeError] = []
    var gate: PowerCommandGate?
    var gatedArguments: [String]?
    var beforeRequest: (([String]) -> Void)?
    var prepareAuthorization: BatteryPowerModeController.AuthorizationPreparer = { 0 }
    var changes: [[String]] { requests.filter { $0.first != "-g" } }
    var currentMode: BatteryPowerMode { source == .powerAdapter ? adapterMode : batteryMode }

    init() throws { defaults = try #require(UserDefaults(suiteName: suite)) }
    isolated deinit { defaults.removePersistentDomain(forName: suite) }

    func service() -> AutomaticPowerModeService {
        AutomaticPowerModeService(controller: BatteryPowerModeController(runCommand: run,
            notificationCenter: notifications, prepareAuthorization: { try await self.prepareAuthorization() }),
            defaults: defaults, notificationCenter: notifications,
            onFailure: { self.failures.append($0) })
    }

    func snapshot(level: Double = 0.7) -> BatterySnapshot {
        BatterySnapshot(level: level, isCharging: source == .powerAdapter,
            isPluggedIn: source == .powerAdapter, isCharged: false, timeRemainingMinutes: nil)
    }

    func drain(_ service: AutomaticPowerModeService) async {
        while let task = service.updateTask { await task.value }
    }

    func run(_ executable: URL, _ arguments: [String], _ timeout: TimeInterval) async throws -> AIAgentProcessOutput {
        #expect(executable.path == "/usr/bin/pmset")
        requests.append(arguments)
        beforeRequest?(arguments)
        if let gate, gatedArguments == arguments {
            self.gate = nil
            await gate.wait()
        }
        if arguments == ["-g", "cap"] {
            #expect(timeout == 5)
            let text = "Capabilities for \(source.rawValue):\n displaysleep\n"
                + (hasCapabilities ? " lowpowermode\n" : "")
                + (hasCapabilities && highPowerSupported ? " highpowermode\n" : "")
            return output(text, status: readFails ? 1 : 0, timedOut: readTimesOut)
        }
        if arguments == ["-g", "custom"] {
            #expect(timeout == 5)
            return output("Battery Power:\n powermode \(batteryMode.rawValue)\nAC Power:\n powermode \(adapterMode.rawValue)")
        }
        #expect(timeout == 120)
        #expect(arguments.count == 3)
        if changeStatus == 0, let raw = Int(arguments.last ?? ""), let mode = BatteryPowerMode(rawValue: raw) {
            if arguments.first == "-c" { adapterMode = mode } else { batteryMode = mode }
        }
        return output(String(changeStatus))
    }

    private func output(_ text: String, status: Int32 = 0, timedOut: Bool = false) -> AIAgentProcessOutput {
        AIAgentProcessOutput(status: status, standardOutput: Data(text.utf8), standardError: "", didTimeout: timedOut)
    }
}

private actor PowerCommandGate {
    private var pending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var started = false

    func wait() async {
        await withCheckedContinuation { continuation in
            pending = continuation
            started = true
            waiter?.resume()
            waiter = nil
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func release() {
        pending?.resume()
        pending = nil
    }
}
