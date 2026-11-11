import Foundation
import Testing

@testable import ZislaKit

struct BatteryChargingStateTests {
    @Test(arguments: [0.79, 0.8, 0.81, 0.95])
    func heldBatteryCanRequestFullChargeWithoutRelyingOnExactlyEightyPercent(level: Double) {
        let state = BatteryChargingState(chargeLimit: 80, chargingOverrideAllowed: true)
        var battery = Self.battery(level: level)
        battery.isCharged = true
        #expect(state.canChargeToFull(battery), "A native limit may mark 80% as charged")
    }

    @Test
    func disconnectedChargingFullAndMissingBatteriesCannotRequestAnOverride() {
        let state = BatteryChargingState(chargeLimit: 80, chargingOverrideAllowed: true)
        #expect(!state.canChargeToFull(nil))
        var battery = Self.battery()
        battery.isPluggedIn = false
        #expect(!state.canChargeToFull(battery))
        battery.isPluggedIn = true
        battery.isCharging = true
        #expect(!state.canChargeToFull(battery))
        battery.isCharging = false
        battery.level = 1
        #expect(!state.canChargeToFull(battery))
    }

    @Test(arguments: [UInt(0), 100, 101, UInt.max])
    func noOrInvalidLimitDoesNotInventChargingOnHold(limit: UInt) {
        #expect(!BatteryChargingState(chargeLimit: limit, chargingOverrideAllowed: true)
            .canChargeToFull(Self.battery()))
    }

    @Test
    func systemMustAllowTheOverride() {
        #expect(!BatteryChargingState(chargeLimit: 80, chargingOverrideAllowed: false)
            .canChargeToFull(Self.battery()))
    }

    @Test
    func manualLimitOffersItsOwnTemporaryOverrideWhenOptimizedOverrideIsUnavailable() {
        let state = BatteryChargingState(
            chargeLimit: 80, chargingOverrideAllowed: false, manualChargeLimitEnabled: true
        )
        #expect(state.canChargeToFull(Self.battery()))
    }

    static func battery(level: Double = 0.8) -> BatterySnapshot {
        BatterySnapshot(level: level, isCharging: false, isPluggedIn: true,
                        isCharged: false, timeRemainingMinutes: nil)
    }
}

@MainActor
struct BatteryChargingControllerTests {
    @Test
    func refreshOnlyReadsStateAndAcceptedRequestHidesTheButton() async {
        let system = ChargingSystem()
        let controller = Self.controller(system)
        await controller.refresh(for: BatteryChargingStateTests.battery())
        #expect(controller.canChargeToFull)
        #expect(await system.requests == 0)

        #expect(await controller.chargeToFull { BatteryChargingStateTests.battery() })
        #expect(!controller.canChargeToFull)
        #expect(!controller.isRequesting)
        #expect(!controller.requestFailed)
        #expect(await system.requests == 1)
    }

    @Test
    func failedPollOffersARecheckWithoutClaimingTheBatteryIsEligible() async {
        let system = ChargingSystem()
        let controller = Self.controller(system)
        await controller.refresh(for: BatteryChargingStateTests.battery())
        await system.failReads()
        await controller.refresh(for: BatteryChargingStateTests.battery())
        #expect(!controller.canChargeToFull)
        #expect(controller.canRetry)
        #expect(!controller.requestFailed)
        #expect(await system.requests == 0)
    }

    @Test
    func pollingKeepsTheConfirmedButtonVisibleUntilTheNextReadingArrives() async {
        let gate = StateGate()
        let controller = BatteryChargingController(readState: { await gate.read() }, requestCharge: {})
        await controller.refresh(for: BatteryChargingStateTests.battery())
        await gate.holdNextRead()
        let refresh = Task { await controller.refresh(for: BatteryChargingStateTests.battery()) }
        await gate.waitUntilReading()
        #expect(controller.canChargeToFull)
        await gate.resume()
        await refresh.value
        #expect(controller.canChargeToFull)
    }

    @Test
    func aFailedClickPreflightPreservesARecheckAndReportsTheFailure() async {
        let system = ChargingSystem()
        let controller = Self.controller(system)
        await controller.refresh(for: BatteryChargingStateTests.battery())
        await system.failReads()
        #expect(await controller.chargeToFull { BatteryChargingStateTests.battery() } == false)
        #expect(!controller.canChargeToFull)
        #expect(controller.canRetry)
        #expect(controller.requestFailed)
        #expect(!controller.isRequesting)
        #expect(await system.requests == 0)
    }

    @Test
    func retrySurvivesRepeatedReadFailuresWithoutWaitingForTheSnapshotToChange() async {
        let system = ChargingSystem()
        let controller = Self.controller(system)
        await controller.refresh(for: BatteryChargingStateTests.battery())
        await system.failReads()
        for _ in 0..<2 {
            #expect(await controller.chargeToFull { BatteryChargingStateTests.battery() } == false)
            controller.requestFailed = false
            await controller.refresh(for: BatteryChargingStateTests.battery())
            #expect(controller.canRetry)
            #expect(!controller.canChargeToFull)
        }
        #expect(await system.requests == 0)
        await system.failReads(false)
        #expect(await controller.chargeToFull { BatteryChargingStateTests.battery() })
        #expect(await system.requests == 1)
        #expect(!controller.canRetry)
        #expect(!controller.canChargeToFull)
        #expect(!controller.requestFailed)
    }

    @Test
    func anUnconfirmedReadFailureCannotInventARetryAndKnownIneligibilityClearsIt() async {
        let system = ChargingSystem()
        let controller = Self.controller(system)
        await system.failReads()
        await controller.refresh(for: BatteryChargingStateTests.battery())
        #expect(!controller.canRetry)
        await system.failReads(false)
        await controller.refresh(for: BatteryChargingStateTests.battery())
        await system.failReads()
        await controller.refresh(for: BatteryChargingStateTests.battery())
        #expect(controller.canRetry)
        await system.failReads(false)
        await system.disallowOverride()
        #expect(await controller.chargeToFull { BatteryChargingStateTests.battery() } == false)
        #expect(!controller.canRetry)
        #expect(!controller.canChargeToFull)
        #expect(await system.requests == 0)
    }

    @Test
    func disconnectingClearsARetryEvenWhileNativeReadsRemainUnavailable() async {
        let system = ChargingSystem()
        let controller = Self.controller(system)
        var battery = BatteryChargingStateTests.battery()
        await controller.refresh(for: battery)
        await system.failReads()
        await controller.refresh(for: battery)
        #expect(controller.canRetry)
        battery.isPluggedIn = false
        await controller.refresh(for: battery)
        #expect(!controller.canRetry)
        #expect(!controller.canChargeToFull)
        #expect(await controller.chargeToFull { battery } == false)
        #expect(await system.requests == 0)
    }

    @Test
    func hiddenActionCannotRequestCharging() async {
        let system = ChargingSystem()
        let controller = Self.controller(system)
        #expect(await controller.chargeToFull { BatteryChargingStateTests.battery() } == false)
        #expect(await system.requests == 0)
        #expect(!controller.requestFailed)
    }

    @Test(arguments: ["eligible", "unplugged", "charging", "full", "missing", "disallowed", "read-failed"])
    func explicitRecheckStillRequiresTheLiveBatteryAndNativePermission(_ scenario: String) async {
        let system = ChargingSystem()
        let controller = Self.controller(system)
        var battery: BatterySnapshot? = BatteryChargingStateTests.battery()
        switch scenario {
        case "unplugged": battery?.isPluggedIn = false
        case "charging": battery?.isCharging = true
        case "full": battery?.level = 1
        case "missing": battery = nil
        case "disallowed": await system.disallowOverride()
        case "read-failed": await system.failReads()
        default: break
        }
        #expect(!controller.canChargeToFull)
        let accepted = await controller.chargeToFull(recheckEligibility: true) { battery }
        #expect(accepted == (scenario == "eligible"))
        #expect(await system.requests == (scenario == "eligible" ? 1 : 0),
                "A display override must never bypass the native charging preflight")
        #expect(controller.requestFailed == !accepted)
        #expect(!controller.isRequesting)
    }

    @Test
    func irrelevantBatteryStatesDoNotReadOrChangeSystemChargingPolicy() async {
        let system = ChargingSystem()
        let controller = Self.controller(system)
        await controller.refresh(for: nil)
        var battery = BatteryChargingStateTests.battery()
        battery.isPluggedIn = false
        await controller.refresh(for: battery)
        battery.isPluggedIn = true
        battery.isCharging = true
        await controller.refresh(for: battery)
        battery.isCharging = false
        battery.level = 1
        await controller.refresh(for: battery)
        #expect(!controller.canChargeToFull)
        #expect(await system.reads == 0)
        #expect(await system.requests == 0)
    }

    @Test
    func staleButtonRechecksNativePermissionBeforeRequesting() async {
        let system = ChargingSystem()
        let controller = Self.controller(system)
        await controller.refresh(for: BatteryChargingStateTests.battery())
        await system.disallowOverride()
        #expect(await controller.chargeToFull { BatteryChargingStateTests.battery() } == false)
        #expect(!controller.canChargeToFull)
        #expect(controller.requestFailed)
        #expect(await system.requests == 0)
    }

    @Test
    func unpluggingDuringStateReadPreventsTheRequest() async {
        let gate = StateGate()
        let system = ChargingSystem()
        let controller = BatteryChargingController(
            readState: { await gate.read() }, requestCharge: { try await system.request() }
        )
        var battery = BatteryChargingStateTests.battery()
        await controller.refresh(for: battery)
        await gate.holdNextRead()
        let request = Task { await controller.chargeToFull { battery } }
        await gate.waitUntilReading()
        battery.isPluggedIn = false
        await gate.resume()
        #expect(await request.value == false)
        #expect(await system.requests == 0)
        #expect(!controller.isRequesting)
    }

    @Test
    func duplicateClicksAndRefreshesCannotSubmitAnotherRequest() async {
        let gate = StateGate()
        let system = ChargingSystem()
        let controller = BatteryChargingController(
            readState: { await gate.read() }, requestCharge: { try await system.request() }
        )
        await controller.refresh(for: BatteryChargingStateTests.battery())
        await gate.holdNextRead()
        let first = Task { await controller.chargeToFull { BatteryChargingStateTests.battery() } }
        await gate.waitUntilReading()
        #expect(controller.isRequesting)
        #expect(await controller.chargeToFull(recheckEligibility: true) { BatteryChargingStateTests.battery() } == false)
        #expect(await controller.chargeToFull { BatteryChargingStateTests.battery() } == false)
        await controller.refresh(for: BatteryChargingStateTests.battery())
        #expect(!controller.canChargeToFull)
        await gate.resume()
        #expect(await first.value)
        #expect(await system.requests == 1)
    }

    @Test
    func aSecondClickCannotSubmitWhileTheNativeRequestIsPending() async {
        let gate = StateGate()
        let system = ChargingSystem()
        let controller = BatteryChargingController(
            readState: { try await system.read() }, requestCharge: {
                _ = await gate.read()
                try await system.request()
            }
        )
        await controller.refresh(for: BatteryChargingStateTests.battery())
        await gate.holdNextRead()
        let first = Task { await controller.chargeToFull { BatteryChargingStateTests.battery() } }
        await gate.waitUntilReading()
        #expect(controller.isRequesting)
        #expect(await controller.chargeToFull { BatteryChargingStateTests.battery() } == false)
        await gate.resume()
        #expect(await first.value)
        #expect(await system.requests == 1)
    }

    /// A poll can arrive while the native call is pending and must still govern the failed result.
    @Test(arguments: ["unplugged", "charging", "full", "missing"], [false, true])
    func completionReconcilesTheLiveBatteryAfterSkippedPendingRefreshes(change: String, succeeds: Bool) async {
        let gate = StateGate()
        let system = ChargingSystem()
        await system.rejectRequests(!succeeds)
        let controller = BatteryChargingController(
            readState: { try await system.read() }, requestCharge: {
                _ = await gate.read()
                try await system.request()
            }
        )
        var battery: BatterySnapshot? = BatteryChargingStateTests.battery()
        await controller.refresh(for: battery)
        await gate.holdNextRead()
        let request = Task { await controller.chargeToFull { battery } }
        await gate.waitUntilReading()
        switch change {
        case "unplugged": battery?.isPluggedIn = false
        case "charging": battery?.isCharging = true
        case "full": battery?.level = 1
        default: battery = nil
        }
        await controller.refresh(for: battery)
        await gate.resume()
        #expect(await request.value == succeeds)
        #expect(!controller.canChargeToFull, "Request completion must not retain an action for an ineligible battery")
        #expect(!controller.canRetry)
        #expect(!controller.isRequesting)
        #expect(controller.requestFailed == !succeeds)
    }

    @Test
    func rejectedRequestCanBeRetriedWithoutClaimingChargingStarted() async {
        let system = ChargingSystem()
        let controller = Self.controller(system)
        await controller.refresh(for: BatteryChargingStateTests.battery())
        await system.rejectRequests(true)
        #expect(await controller.chargeToFull { BatteryChargingStateTests.battery() } == false)
        #expect(controller.requestFailed)
        #expect(controller.canChargeToFull)
        #expect(!controller.isRequesting)
        await system.rejectRequests(false)
        #expect(await controller.chargeToFull { BatteryChargingStateTests.battery() })
        #expect(!controller.requestFailed)
    }

    @Test
    func olderReadCannotResurrectTheButtonAfterUnplugging() async {
        let gate = StateGate()
        let controller = BatteryChargingController(readState: { await gate.read() }, requestCharge: {})
        await gate.holdNextRead()
        let oldRead = Task { await controller.refresh(for: BatteryChargingStateTests.battery()) }
        await gate.waitUntilReading()
        var battery = BatteryChargingStateTests.battery()
        battery.isPluggedIn = false
        await controller.refresh(for: battery)
        await gate.resume()
        await oldRead.value
        #expect(!controller.canChargeToFull)
    }

    private static func controller(_ system: ChargingSystem) -> BatteryChargingController {
        BatteryChargingController(readState: { try await system.read() }, requestCharge: { try await system.request() })
    }
}

private actor ChargingSystem {
    var reads = 0
    var requests = 0
    private var readFails = false
    private var requestFails = false
    private var allowed = true

    /// Injects read failures without involving the machine's charging service.
    func read() throws -> BatteryChargingState {
        reads += 1
        if readFails { throw BatteryChargingError.unavailable }
        return BatteryChargingState(chargeLimit: 80, chargingOverrideAllowed: allowed)
    }

    /// Records submission before refusal to model errors that may follow native acceptance.
    func request() throws {
        requests += 1
        if requestFails { throw BatteryChargingError.requestFailed }
    }

    func failReads(_ fail: Bool = true) { readFails = fail }
    func disallowOverride() { allowed = false }
    func rejectRequests(_ reject: Bool) { requestFails = reject }
}

private actor StateGate {
    private var shouldHold = false
    private var pendingRead: CheckedContinuation<BatteryChargingState, Never>?
    private var readingWaiter: CheckedContinuation<Void, Never>?

    func holdNextRead() { shouldHold = true }

    /// Suspends one read so tests can order unplugging and duplicate clicks without sleeps.
    func read() async -> BatteryChargingState {
        if shouldHold {
            shouldHold = false
            return await withCheckedContinuation { continuation in
                pendingRead = continuation
                readingWaiter?.resume()
                readingWaiter = nil
            }
        }
        return BatteryChargingState(chargeLimit: 80, chargingOverrideAllowed: true)
    }

    /// Handshakes with the suspended read rather than depending on task scheduling speed.
    func waitUntilReading() async {
        if pendingRead != nil { return }
        await withCheckedContinuation { readingWaiter = $0 }
    }

    func resume() {
        pendingRead?.resume(returning: BatteryChargingState(chargeLimit: 80, chargingOverrideAllowed: true))
        pendingRead = nil
    }
}
