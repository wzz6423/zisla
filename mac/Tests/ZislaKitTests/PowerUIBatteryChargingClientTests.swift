import Foundation
import Testing

@testable import ZislaKit

struct PowerUIBatteryChargingClientTests {
    @Test
    func sessionKeepsOneNativeConnectionAcrossReadsAndTheTemporaryRequest() async throws {
        let session = PowerUIBatteryChargingSession(makeClient: {
            PowerUIBatteryChargingClient(object: ReusableChargingClientStub())
        })
        #expect(try await session.state().chargeLimit == 80)
        #expect(try await session.state().chargeLimit == 81)
        try await session.requestChargeToFull()
        let after = try await session.state()
        #expect(after.chargeLimit == 100, "The request and subsequent read must share the existing connection")
        #expect(!after.chargingOverrideAllowed)
    }

    /// A native error may follow a side effect, so recovery must wait for a later operation.
    @Test(arguments: SessionClientFactory.Failure.allCases)
    fileprivate func failedConnectionsRecoverOnTheNextOperationWithoutRetryingMutations(
        failure: SessionClientFactory.Failure
    ) async throws {
        let factory = SessionClientFactory(failure: failure)
        let session = PowerUIBatteryChargingSession(makeClient: { try factory.makeClient() })
        if failure == .request {
            _ = try await session.state()
            await #expect(throws: BatteryChargingError.requestFailed) { try await session.requestChargeToFull() }
        } else {
            await #expect(throws: BatteryChargingError.unavailable) { try await session.state() }
        }
        #expect(factory.creationCount == 1, "Native failures must not submit an automatic retry")
        #expect(try await session.state().chargeLimit == 80)
        try await session.requestChargeToFull()
        #expect(factory.creationCount == 2, "A later operation must reconnect after initialization, read or request failure")
    }

    @Test
    func nativeStateReaderPreservesTheLimitAndOverridePermission() throws {
        let system = ChargingClientStub()
        let state = try PowerUIBatteryChargingClient(object: system).state()
        #expect(state.chargeLimit == 80)
        #expect(state.chargingOverrideAllowed)
        #expect(system.operations.isEmpty)
        system.allowed = false
        #expect(try !PowerUIBatteryChargingClient(object: system).state().chargingOverrideAllowed)
        system.manualEnabled = 1
        let manualState = try PowerUIBatteryChargingClient(object: system).state()
        #expect(manualState.manualChargeLimitEnabled)
        #expect(manualState.canChargeToFull(BatteryChargingStateTests.battery()))
    }

    @Test(arguments: [false, true])
    func failedStateReadNeverReturnsAnUsableSnapshot(reportsError: Bool) {
        let system = ChargingClientStub()
        system.querySucceeds = reportsError
        system.queryReportsError = reportsError
        #expect(throws: BatteryChargingError.unavailable) {
            try PowerUIBatteryChargingClient(object: system).state()
        }
        #expect(system.operations.isEmpty)
    }

    @Test
    func missingOrChangedStateMethodIsUnavailable() {
        #expect(throws: BatteryChargingError.unavailable) {
            try PowerUIBatteryChargingClient(object: NSObject()).state()
        }
        let changed = IncompatibleStateStub()
        #expect(throws: BatteryChargingError.unavailable) {
            try PowerUIBatteryChargingClient(object: changed).state()
        }
        #expect(!changed.wasInvoked)
    }

    @Test(arguments: [UInt(0), 1])
    func usesExactlyOneTemporaryOperationAndPreservesSavedSettings(manualEnabled: UInt) throws {
        let system = ChargingClientStub()
        system.manualEnabled = manualEnabled
        try PowerUIBatteryChargingClient(object: system).requestChargeToFull()
        #expect(system.operations == [manualEnabled == 1 ? "temporarilyDisableMCL:" : "temporarilyEnableCharging:"])
        #expect(system.savedOptimizedChargingEnabled)
        #expect(system.savedChargeLimit == 80)
    }

    @Test
    func optimizedChargingStillWorksOnSystemsWithoutManualChargeLimits() throws {
        let system = LegacyChargingClientStub()
        #expect(try PowerUIBatteryChargingClient(object: system).state()
            .canChargeToFull(BatteryChargingStateTests.battery()))
        try PowerUIBatteryChargingClient(object: system).requestChargeToFull()
        #expect(system.requested)
    }

    @Test
    func legacyEngagementMustBeActiveAndAllowAnOverride() throws {
        let system = LegacyChargingClientStub()
        system.engaged = false
        #expect(try !PowerUIBatteryChargingClient(object: system).state()
            .canChargeToFull(BatteryChargingStateTests.battery()))
        system.engaged = true
        system.allowed = false
        #expect(try !PowerUIBatteryChargingClient(object: system).state()
            .canChargeToFull(BatteryChargingStateTests.battery()))
    }

    @Test(arguments: [false, true])
    func legacyReadFailuresCannotInventAnOverride(reportsError: Bool) {
        let system = LegacyChargingClientStub()
        system.querySucceeds = reportsError
        system.queryReportsError = reportsError
        #expect(throws: BatteryChargingError.unavailable) {
            try PowerUIBatteryChargingClient(object: system).state()
        }
        #expect(!system.requested)
    }

    /// Unknown native enums must not silently select the optimized-charging mutation.
    @Test
    func unknownOrUnreadableManualStateCannotFallBackToAnotherMutation() {
        for state in [UInt(2), 3, UInt.max] {
            let system = ChargingClientStub()
            system.manualEnabled = state
            #expect(throws: BatteryChargingError.unavailable) {
                try PowerUIBatteryChargingClient(object: system).requestChargeToFull()
            }
            #expect(system.operations.isEmpty)
        }
        let system = ChargingClientStub()
        system.manualReportsError = true
        #expect(throws: BatteryChargingError.unavailable) {
            try PowerUIBatteryChargingClient(object: system).requestChargeToFull()
        }
        #expect(system.operations.isEmpty)
    }

    @Test(arguments: [false, true], [UInt(0), 1])
    func nativeRefusalAndNSErrorAreFailuresWithoutPermanentFallback(reportsError: Bool, manualEnabled: UInt) {
        let system = ChargingClientStub()
        system.manualEnabled = manualEnabled
        system.requestSucceeds = reportsError
        system.requestReportsError = reportsError
        #expect(throws: BatteryChargingError.requestFailed) {
            try PowerUIBatteryChargingClient(object: system).requestChargeToFull()
        }
        #expect(system.operations == [manualEnabled == 1 ? "temporarilyDisableMCL:" : "temporarilyEnableCharging:"])
        #expect(system.savedOptimizedChargingEnabled)
        #expect(system.savedChargeLimit == 80)
    }

    @Test
    func missingOverrideMethodFailsWithoutARequest() {
        #expect(throws: BatteryChargingError.unavailable) {
            try PowerUIBatteryChargingClient(object: NSObject()).requestChargeToFull()
        }
    }

    @Test
    func changedMutationSignatureIsRejectedBeforeInvocation() {
        let system = IncompatibleRequestStub()
        #expect(throws: BatteryChargingError.unavailable) {
            try PowerUIBatteryChargingClient(object: system).requestChargeToFull()
        }
        #expect(!system.wasInvoked)
    }
}

private final class ReusableChargingClientStub: NSObject {
    private var limit: UInt = 80
    private var requested = false

    /// State changes on each read reveal accidental connection replacement in the session.
    @objc(smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:)
    func read(_ state: UnsafeMutablePointer<UInt>, limit: UnsafeMutablePointer<UInt>,
              allowed: UnsafeMutablePointer<ObjCBool>, error: NSErrorPointer) -> Bool {
        state.pointee = 3
        limit.pointee = requested ? 100 : self.limit
        allowed.pointee = ObjCBool(!requested)
        self.limit += 1
        return true
    }

    @objc(temporarilyEnableCharging:)
    func request(_ error: NSErrorPointer) -> Bool {
        requested = true
        return true
    }
}

private final class SessionClientFactory: @unchecked Sendable {
    enum Failure: CaseIterable, Sendable { case initialization, read, request }
    private let failure: Failure
    private let lock = NSLock()
    private var creations = 0

    init(failure: Failure) { self.failure = failure }

    var creationCount: Int { lock.withLock { creations } }

    /// Fails only the first connection so recovery remains deterministic across actor hops.
    func makeClient() throws -> PowerUIBatteryChargingClient {
        let first = lock.withLock {
            creations += 1
            return creations == 1
        }
        if first, failure == .initialization { throw BatteryChargingError.unavailable }
        let object = ChargingClientStub()
        object.querySucceeds = !first || failure != .read
        object.requestSucceeds = !first || failure != .request
        return PowerUIBatteryChargingClient(object: object)
    }
}

private final class ChargingClientStub: NSObject {
    var allowed = true
    var querySucceeds = true
    var queryReportsError = false
    var manualEnabled: UInt = 0
    var manualReportsError = false
    var requestSucceeds = true
    var requestReportsError = false
    var operations: [String] = []
    var savedOptimizedChargingEnabled = true
    var savedChargeLimit = 80

    /// A successful BOOL plus NSError is still a failure at the Objective-C boundary.
    @objc(smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:)
    func read(_ state: UnsafeMutablePointer<UInt>, limit: UnsafeMutablePointer<UInt>,
              allowed: UnsafeMutablePointer<ObjCBool>, error: NSErrorPointer) -> Bool {
        state.pointee = 3
        limit.pointee = UInt(savedChargeLimit)
        allowed.pointee = ObjCBool(self.allowed)
        if queryReportsError { error?.pointee = Self.failure }
        return querySucceeds
    }

    /// Models enum and NSError results independently to catch unsafe mutation fallbacks.
    @objc(isMCLCurrentlyEnabled:)
    func manualLimit(_ error: NSErrorPointer) -> UInt {
        if manualReportsError { error?.pointee = Self.failure }
        return manualEnabled
    }

    /// Records the native attempt even when its reply reports an error after a possible side effect.
    @objc(temporarilyEnableCharging:)
    func enableCharging(_ error: NSErrorPointer) -> Bool {
        operations.append("temporarilyEnableCharging:")
        if requestReportsError { error?.pointee = Self.failure }
        return requestSucceeds
    }

    /// Manual-limit overrides obey the same refusal contract as optimized charging.
    @objc(temporarilyDisableMCL:)
    func disableManualLimit(_ error: NSErrorPointer) -> Bool {
        operations.append("temporarilyDisableMCL:")
        if requestReportsError { error?.pointee = Self.failure }
        return requestSucceeds
    }

    @objc(disableSmartCharging:)
    func disableOptimizedCharging(_ error: NSErrorPointer) -> Bool {
        savedOptimizedChargingEnabled = false
        operations.append("disableSmartCharging:")
        return true
    }

    @objc(setMCLLimit:error:)
    func setChargeLimit(_ limit: UInt8, error: NSErrorPointer) -> Bool {
        savedChargeLimit = Int(limit)
        operations.append("setMCLLimit:error:")
        return true
    }

    private static var failure: NSError { NSError(domain: "ChargingStub", code: 2) }
}

private final class LegacyChargingClientStub: NSObject {
    var requested = false
    var engaged = true
    var allowed = true
    var querySucceeds = true
    var queryReportsError = false

    /// The legacy ABI returns engagement and permission separately from the call's success.
    @objc(isOBCEngaged:asDesktopDevice:chargingOverrideAllowed:withError:)
    func read(_ engaged: UnsafeMutablePointer<ObjCBool>, desktop: UnsafeMutablePointer<ObjCBool>,
              allowed: UnsafeMutablePointer<ObjCBool>, error: NSErrorPointer) -> Bool {
        engaged.pointee = ObjCBool(self.engaged)
        desktop.pointee = false
        allowed.pointee = ObjCBool(self.allowed)
        if queryReportsError { error?.pointee = NSError(domain: "LegacyChargingStub", code: 2) }
        return querySucceeds
    }

    @objc(temporarilyEnableCharging:)
    func request(_ error: NSErrorPointer) -> Bool {
        requested = true
        return true
    }
}

private final class IncompatibleStateStub: NSObject {
    var wasInvoked = false

    @objc(smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:)
    func read(_ state: UnsafeMutablePointer<UInt>, limit: UnsafeMutablePointer<UInt>,
              allowed: UnsafeMutablePointer<ObjCBool>, error: NSErrorPointer) -> Int {
        wasInvoked = true
        return 1
    }
}

private final class IncompatibleRequestStub: NSObject {
    var wasInvoked = false

    @objc(temporarilyEnableCharging:)
    func request(_ error: NSErrorPointer) -> Int {
        wasInvoked = true
        return 1
    }
}
