import Foundation
import Testing
@testable import ZislaKit

@MainActor
struct BatteryPowerModeControllerTests {
    @Test
    func initializationDoesNotRunCommandsOrRequestAuthorization() {
        let commands = Commands()
        let controller = BatteryPowerModeController(runCommand: commands.run)

        #expect(commands.requests.isEmpty)
        #expect(controller.currentMode == nil)
        #expect(controller.supportedModes.isEmpty)
        #expect(!controller.isChanging)
        #expect(controller.error == nil)
    }

    @Test(arguments: BatteryPowerMode.allCases)
    func readsUnifiedPowerModesWithoutTreatingHighPowerCapabilityAsState(mode: BatteryPowerMode) async {
        let commands = Commands()
        commands.appendRead(preferences: Self.preferences(adapter: mode.rawValue) + "\n highpowermode 1")
        let controller = BatteryPowerModeController(runCommand: commands.run)

        await controller.refresh()

        #expect(controller.currentMode == mode)
        #expect(controller.supportedModes == [.automatic, .lowPower, .highPower])
        #expect(controller.error == nil)
        #expect(commands.requests.allSatisfy { $0.executable.path == "/usr/bin/pmset" })
    }

    @Test(arguments: [BatteryPowerSource.battery, .powerAdapter])
    func selectsTheActivePowerSourceProfile(source: BatteryPowerSource) async {
        let commands = Commands()
        commands.appendRead(source: source, preferences: Self.preferences(battery: 1, adapter: 2))
        let controller = BatteryPowerModeController(runCommand: commands.run)

        await controller.refresh()

        #expect(controller.powerSource == source)
        #expect(controller.currentMode == (source == .battery ? .lowPower : .highPower))
    }

    @Test
    func readsLegacyLowPowerModeAndUsesCapabilitiesToLimitOptions() async {
        let commands = Commands()
        commands.appendRead(
            highPower: false,
            preferences: "AC Power:\n lowpowermode 1\n highpowermode 1"
        )
        let controller = BatteryPowerModeController(runCommand: commands.run)

        await controller.refresh()

        #expect(controller.currentMode == .lowPower)
        #expect(controller.supportedModes == [.automatic, .lowPower])
    }

    @Test
    func unsupportedHardwareDoesNotOfferExecutableModes() async {
        let commands = Commands(outputs: [
            Self.output("Capabilities for AC Power:\n sleep\n displaysleep"),
            Self.output("AC Power:\n sleep 1"),
        ])
        let controller = BatteryPowerModeController(runCommand: commands.run)

        await controller.refresh()

        #expect(controller.currentMode == nil)
        #expect(controller.supportedModes.isEmpty)
        #expect(controller.error == nil)
    }

    @Test
    func capabilityNamesMustBeCompleteLines() async {
        let commands = Commands(outputs: [
            Self.output("Capabilities for AC Power:\n lowpowermode\n highpowermode unsupported"),
            Self.output(Self.preferences()),
        ])
        let controller = BatteryPowerModeController(runCommand: commands.run)

        await controller.refresh()

        #expect(controller.supportedModes == [.automatic, .lowPower])
    }

    @Test(arguments: [
        "", "powermode", "powermode 3", "powermode -1", "powermode 01",
        "powermode two", "powermode 1;id", "powermode $(id)", "powermode 1 2",
        "lowpowermode 2", "powermode 0\n powermode 1", "powermode 0\n lowpowermode 0",
    ])
    func malformedPreferencesCannotBecomeASelectedModeOrACommand(setting: String) async {
        let commands = Commands()
        commands.appendRead(preferences: "AC Power:\n \(setting)")
        let controller = BatteryPowerModeController(runCommand: commands.run)

        let succeeded = await controller.setMode(.lowPower)

        #expect(!succeeded)
        #expect(controller.currentMode == nil)
        #expect(controller.supportedModes.isEmpty)
        #expect(controller.error == .stateUnavailable)
        #expect(commands.requests.allSatisfy { $0.executable.path == "/usr/bin/pmset" })
    }

    @Test(arguments: [
        "", "Capabilities for UPS Power:\n lowpowermode", "lowpowermode\n highpowermode",
        "Capabilities for AC Power",
        "Capabilities for AC Power; id:\n highpowermode",
        "Capabilities for Battery Power:\n lowpowermode\nCapabilities for AC Power:\n highpowermode",
    ])
    func rejectsUnknownOrAmbiguousCapabilitySources(capabilities: String) async {
        let commands = Commands(outputs: [Self.output(capabilities), Self.output(Self.preferences())])
        let controller = BatteryPowerModeController(runCommand: commands.run)

        await controller.refresh()

        #expect(controller.powerSource == nil)
        #expect(controller.supportedModes.isEmpty)
        #expect(controller.error == .stateUnavailable)
    }

    @Test
    func seededWhitespaceAndProfileOrderChangesPreserveTheSelectedMode() async {
        var seed: UInt64 = 0xB477_E2
        func next(_ upperBound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int((seed >> 32) % UInt64(upperBound))
        }
        for sample in 0..<64 {
            let battery = BatteryPowerMode.allCases[next(3)]
            let adapter = BatteryPowerMode.allCases[next(3)]
            let source: BatteryPowerSource = next(2) == 0 ? .battery : .powerAdapter
            let padding = [" ", "\t", "   "][next(3)]
            let separator = [" ", "\t", " \t "][next(3)]
            let newline = next(2) == 0 ? "\n" : "\r\n"
            var sections = [
                "\(padding)Battery Power:\(newline)\(padding)powermode\(separator)\(battery.rawValue)",
                "\(padding)AC Power:\(newline)\(padding)powermode\(separator)\(adapter.rawValue)",
            ]
            if next(2) == 0 { sections.reverse() }
            let commands = Commands()
            commands.appendRead(source: source, preferences: sections.joined(separator: newline))
            let controller = BatteryPowerModeController(runCommand: commands.run)

            await controller.refresh()

            #expect(controller.currentMode == (source == .battery ? battery : adapter), "Seed 0xB477E2, sample \(sample)")
            #expect(controller.error == nil)
        }
    }

    @Test
    func unrelatedPowerSourceSectionsDoNotOverwriteTheActiveProfile() async {
        let commands = Commands()
        commands.appendRead(preferences: "AC Power:\n powermode 1\nUPS Power:\n powermode 2")
        let controller = BatteryPowerModeController(runCommand: commands.run)

        await controller.refresh()

        #expect(controller.currentMode == .lowPower)
    }

    @Test
    func missingHardwareSupportCannotBeInferredFromAStoredHighPowerValue() async {
        let commands = Commands()
        commands.appendRead(highPower: false, preferences: Self.preferences(adapter: 2))
        let controller = BatteryPowerModeController(runCommand: commands.run)

        await controller.refresh()

        #expect(controller.currentMode == nil)
        #expect(controller.supportedModes.isEmpty)
        #expect(controller.error == .stateUnavailable)
    }

    @Test
    func successfulRefreshClearsAnEarlierFailureWithoutRequestingAuthorization() async {
        let commands = Commands(outputs: [Self.output("unavailable", status: 1)])
        commands.appendRead(preferences: Self.preferences(adapter: 1))
        let controller = BatteryPowerModeController(runCommand: commands.run)
        await controller.refresh()
        #expect(controller.error == .stateUnavailable)

        await controller.refresh()

        #expect(controller.currentMode == .lowPower)
        #expect(controller.error == nil)
        #expect(commands.requests.allSatisfy { $0.executable.path == "/usr/bin/pmset" })
    }

    @Test
    func readFailuresClearPreviouslyKnownState() async {
        let failures: [(AIAgentProcessOutput, BatteryPowerModeError)] = [
            (Self.output("permission denied", status: 1), .stateUnavailable),
            (Self.output("", didTimeout: true), .timedOut),
            (AIAgentProcessOutput(status: 0, standardOutput: Data([0xFF]), standardError: "", didTimeout: false), .stateUnavailable),
        ]
        for (failure, expectedError) in failures {
            let commands = Commands()
            commands.appendRead(preferences: Self.preferences(adapter: 1))
            commands.outputs.append(failure)
            commands.outputs.append(Self.output(Self.preferences()))
            let controller = BatteryPowerModeController(runCommand: commands.run)
            await controller.refresh()
            #expect(controller.currentMode == .lowPower)

            await controller.refresh()

            #expect(controller.currentMode == nil)
            #expect(controller.powerSource == nil)
            #expect(controller.supportedModes.isEmpty)
            #expect(controller.error == expectedError)
        }
    }

    @Test(arguments: ["refresh", "change", "readback"])
    func processLaunchFailuresInvalidateStateAtEachReadBoundary(phase: String) async {
        let commands = Commands()
        var remainingReads = phase == "readback" ? 2 : 0
        if phase == "readback" {
            commands.appendRead()
            commands.outputs.append(Self.output("0"))
        }
        commands.override = { request in
            if Self.isChangeRequest(request) { return nil }
            guard request.executable.path == "/usr/bin/pmset" else { return nil }
            guard remainingReads > 0 else { throw CocoaError(.executableLoad) }
            remainingReads -= 1
            return nil
        }
        let controller = BatteryPowerModeController(runCommand: commands.run)

        if phase == "refresh" {
            await controller.refresh()
        } else {
            #expect(!(await controller.setMode(.highPower)))
        }

        #expect(controller.currentMode == nil)
        #expect(controller.supportedModes.isEmpty)
        #expect(controller.error == (phase == "readback" ? .verificationFailed : .stateUnavailable))
        #expect(!controller.isChanging)
    }

    @Test(arguments: BatteryPowerMode.allCases, [BatteryPowerSource.battery, .powerAdapter])
    func successfulChangesUseOnlyTheSelectedSourceAndVerifyReadback(
        mode: BatteryPowerMode,
        source: BatteryPowerSource
    ) async {
        let previous = mode == .automatic ? 2 : 0
        let commands = Commands()
        commands.appendRead(source: source, preferences: Self.preferences(battery: previous, adapter: previous))
        commands.outputs.append(Self.output("0\n"))
        commands.appendRead(source: source, preferences: Self.preferences(
            battery: source == .battery ? mode.rawValue : previous,
            adapter: source == .powerAdapter ? mode.rawValue : previous
        ))
        let controller = BatteryPowerModeController(runCommand: commands.run)

        let succeeded = await controller.setMode(mode)

        #expect(succeeded)
        #expect(controller.currentMode == mode)
        #expect(controller.error == nil)
        #expect(!controller.isChanging)
        let changes = commands.requests.filter(Self.isChangeRequest)
        #expect(changes.count == 1)
        #expect(changes.first?.arguments == [source == .battery ? "-b" : "-c", "powermode", String(mode.rawValue)])
        #expect(commands.outputs.isEmpty)
    }

    @Test
    func lowPowerOnlyHardwareUsesTheLegacySetting() async {
        let commands = Commands()
        commands.appendRead(source: .battery, highPower: false, preferences: "Battery Power:\n lowpowermode 0")
        commands.outputs.append(Self.output("0"))
        commands.appendRead(source: .battery, highPower: false, preferences: "Battery Power:\n lowpowermode 1")
        let controller = BatteryPowerModeController(runCommand: commands.run)

        #expect(await controller.setMode(.lowPower))
        let change = commands.requests.first(where: Self.isChangeRequest)
        #expect(change?.arguments == ["-b", "lowpowermode", "1"])
    }

    @Test
    func unsupportedModesNeverRequestAuthorization() async {
        let commands = Commands()
        commands.appendRead(highPower: false)
        let controller = BatteryPowerModeController(runCommand: commands.run)

        #expect(!(await controller.setMode(.highPower)))
        #expect(controller.currentMode == .automatic)
        #expect(controller.error == .unsupportedMode)
        #expect(!controller.isChanging)
        #expect(commands.requests.allSatisfy { $0.executable.path == "/usr/bin/pmset" })
    }

    @Test
    func selectingTheCurrentModeDoesNotRequestAuthorization() async {
        let commands = Commands()
        commands.appendRead(preferences: Self.preferences(adapter: 1))
        let controller = BatteryPowerModeController(runCommand: commands.run)

        #expect(await controller.setMode(.lowPower))
        #expect(controller.error == nil)
        #expect(!controller.isChanging)
        #expect(commands.requests.allSatisfy { $0.executable.path == "/usr/bin/pmset" })
    }

    @Test(arguments: [-128, -60006, -60005, -60007, 5])
    func authorizationErrorsAreReportedWithoutOptimisticStateChanges(code: Int) async {
        let commands = Commands()
        commands.appendRead()
        commands.outputs.append(Self.output("\(code)"))
        commands.appendRead()
        let controller = BatteryPowerModeController(runCommand: commands.run)

        #expect(!(await controller.setMode(.highPower)))
        #expect(controller.currentMode == .automatic)
        #expect(!controller.isChanging)
        let expected: BatteryPowerModeError = switch code {
        case -128, -60006: .authorizationCancelled
        case -60005, -60007: .authorizationDenied
        default: .changeFailed
        }
        #expect(controller.error == expected)
        controller.clearError()
        #expect(controller.error == nil)
        #expect(controller.currentMode == .automatic)
    }

    @Test
    func failedOrTimedOutCommandsStillReadTheSystemState() async {
        let failures: [(AIAgentProcessOutput, BatteryPowerModeError)] = [
            (Self.output("0", status: 1), .changeFailed),
            (Self.output("0", didTimeout: true), .timedOut),
            (Self.output("invalid result"), .changeFailed),
            (Self.output("0\n0"), .changeFailed),
        ]
        for (failure, expectedError) in failures {
            let commands = Commands()
            commands.appendRead()
            commands.outputs.append(failure)
            commands.appendRead(preferences: Self.preferences(adapter: 2))
            let controller = BatteryPowerModeController(runCommand: commands.run)

            #expect(!(await controller.setMode(.highPower)))
            #expect(controller.currentMode == .highPower)
            #expect(controller.error == expectedError)
            #expect(!controller.isChanging)
        }
    }

    @Test(arguments: [false, true])
    func processLaunchFailureAndCancellationReleaseTheChangingState(cancelled: Bool) async {
        let commands = Commands()
        commands.appendRead()
        commands.appendRead()
        commands.override = { request in
            guard Self.isChangeRequest(request) else { return nil }
            if cancelled { throw CancellationError() }
            throw CocoaError(.executableLoad)
        }
        let controller = BatteryPowerModeController(runCommand: commands.run)

        #expect(!(await controller.setMode(.highPower)))
        #expect(controller.currentMode == .automatic)
        #expect(controller.error == (cancelled ? .authorizationCancelled : .changeFailed))
        #expect(!controller.isChanging)
    }

    @Test
    func successfulExitWithUnchangedPreferencesIsNotReportedAsSuccess() async {
        let commands = Commands()
        commands.appendRead()
        commands.outputs.append(Self.output("0"))
        commands.appendRead()
        let controller = BatteryPowerModeController(runCommand: commands.run)

        #expect(!(await controller.setMode(.highPower)))
        #expect(controller.currentMode == .automatic)
        #expect(controller.error == .verificationFailed)
    }

    @Test
    func unreadablePostChangeStateDoesNotKeepAnUnverifiedSelection() async {
        let commands = Commands()
        commands.appendRead()
        commands.outputs.append(Self.output("0"))
        commands.outputs.append(Self.output("read failed", status: 1))
        let controller = BatteryPowerModeController(runCommand: commands.run)

        #expect(!(await controller.setMode(.highPower)))
        #expect(controller.currentMode == nil)
        #expect(controller.supportedModes.isEmpty)
        #expect(controller.error == .stateUnavailable)
        #expect(!controller.isChanging)
    }

    @Test
    func changingPowerSourceDuringAuthorizationKeepsTheOriginalTarget() async {
        let commands = Commands()
        commands.appendRead(source: .battery)
        commands.outputs.append(Self.output("0"))
        commands.appendRead(source: .powerAdapter, preferences: Self.preferences(battery: 2, adapter: 1))
        let controller = BatteryPowerModeController(runCommand: commands.run)

        #expect(await controller.setMode(.highPower))
        #expect(controller.powerSource == .powerAdapter)
        #expect(controller.currentMode == .lowPower)
        let change = commands.requests.first(where: Self.isChangeRequest)
        #expect(change?.arguments == ["-b", "powermode", "2"])
    }

    @Test
    func concurrentChangesAndRefreshesCannotStartAnotherAuthorization() async {
        let commands = Commands()
        commands.appendRead()
        commands.appendRead(preferences: Self.preferences(adapter: 2))
        let (started, signal) = AsyncStream<Void>.makeStream()
        var resume: CheckedContinuation<AIAgentProcessOutput, Never>?
        commands.override = { request in
            guard Self.isChangeRequest(request) else { return nil }
            return await withCheckedContinuation { continuation in
                resume = continuation
                signal.yield(())
                signal.finish()
            }
        }
        let controller = BatteryPowerModeController(runCommand: commands.run)
        let change = Task { await controller.setMode(.highPower) }
        for await _ in started { break }

        #expect(controller.isChanging)
        #expect(controller.currentMode == .automatic)
        #expect(!(await controller.setMode(.lowPower)))
        await controller.refresh()
        #expect(commands.requests.filter(Self.isChangeRequest).count == 1)

        resume?.resume(returning: Self.output("0"))
        #expect(await change.value)
        #expect(controller.currentMode == .highPower)
        #expect(!controller.isChanging)
    }

    @Test(arguments: [false, true])
    func oldRefreshCannotOverwriteANewerRefreshOrACompletedChange(performChange: Bool) async {
        let commands = Commands(outputs: [Self.output(Self.capabilities())])
        if performChange {
            commands.appendRead()
            commands.outputs.append(Self.output("0"))
        }
        commands.appendRead(preferences: Self.preferences(adapter: 1))
        let (started, signal) = AsyncStream<Void>.makeStream()
        var suspended = false
        var resume: CheckedContinuation<AIAgentProcessOutput, Never>?
        commands.override = { request in
            guard request.arguments == ["-g", "custom"], !suspended else { return nil }
            suspended = true
            return await withCheckedContinuation { continuation in
                resume = continuation
                signal.yield(())
                signal.finish()
            }
        }
        let controller = BatteryPowerModeController(runCommand: commands.run)
        let oldRefresh = Task { await controller.refresh() }
        for await _ in started { break }

        if performChange {
            #expect(await controller.setMode(.lowPower))
        } else {
            await controller.refresh()
        }
        #expect(controller.currentMode == .lowPower)
        resume?.resume(returning: Self.output(Self.preferences()))
        await oldRefresh.value

        #expect(controller.currentMode == .lowPower)
        #expect(controller.error == nil)
    }

    private static func output(
        _ text: String,
        status: Int32 = 0,
        didTimeout: Bool = false
    ) -> AIAgentProcessOutput {
        AIAgentProcessOutput(
            status: status, standardOutput: Data(text.utf8), standardError: "", didTimeout: didTimeout
        )
    }

    private static func capabilities(
        _ source: BatteryPowerSource = .powerAdapter,
        highPower: Bool = true
    ) -> String {
        "Capabilities for \(source.rawValue):\n displaysleep\n lowpowermode\n"
            + (highPower ? " highpowermode\n" : "")
    }

    private static func preferences(battery: Int = 0, adapter: Int = 0) -> String {
        "Battery Power:\n powermode \(battery)\n sleep 1\nAC Power:\n powermode \(adapter)\n sleep 1"
    }

    private static func isChangeRequest(_ request: Request) -> Bool {
        request.executable.path == "/usr/bin/pmset"
            && (request.arguments.first == "-b" || request.arguments.first == "-c")
    }

    private struct Request {
        let executable: URL
        let arguments: [String]
    }

    @MainActor
    private final class Commands {
        var outputs: [AIAgentProcessOutput]
        var requests: [Request] = []
        var override: ((Request) async throws -> AIAgentProcessOutput?)?

        init(outputs: [AIAgentProcessOutput] = []) {
            self.outputs = outputs
        }

        func appendRead(
            source: BatteryPowerSource = .powerAdapter,
            highPower: Bool = true,
            preferences: String? = nil
        ) {
            outputs.append(BatteryPowerModeControllerTests.output(
                BatteryPowerModeControllerTests.capabilities(source, highPower: highPower)
            ))
            outputs.append(BatteryPowerModeControllerTests.output(
                preferences ?? BatteryPowerModeControllerTests.preferences()
            ))
        }

        func run(_ executable: URL, _ arguments: [String], _ timeout: TimeInterval) async throws -> AIAgentProcessOutput {
            let request = Request(executable: executable, arguments: arguments)
            requests.append(request)
            if let output = try await override?(request) { return output }
            guard !outputs.isEmpty else { throw CocoaError(.fileReadUnknown) }
            return outputs.removeFirst()
        }
    }
}
