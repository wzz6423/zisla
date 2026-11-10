import Foundation
import Testing

@testable import ZislaKit

struct PowerUIBatteryChargingClientTests {
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

    @objc(smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:)
    func read(_ state: UnsafeMutablePointer<UInt>, limit: UnsafeMutablePointer<UInt>,
              allowed: UnsafeMutablePointer<ObjCBool>, error: NSErrorPointer) -> Bool {
        state.pointee = 3
        limit.pointee = UInt(savedChargeLimit)
        allowed.pointee = ObjCBool(self.allowed)
        if queryReportsError { error?.pointee = Self.failure }
        return querySucceeds
    }

    @objc(isMCLCurrentlyEnabled:)
    func manualLimit(_ error: NSErrorPointer) -> UInt {
        if manualReportsError { error?.pointee = Self.failure }
        return manualEnabled
    }

    @objc(temporarilyEnableCharging:)
    func enableCharging(_ error: NSErrorPointer) -> Bool {
        operations.append("temporarilyEnableCharging:")
        if requestReportsError { error?.pointee = Self.failure }
        return requestSucceeds
    }

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
