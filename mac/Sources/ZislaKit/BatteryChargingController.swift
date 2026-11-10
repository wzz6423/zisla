import Combine
import Darwin
import Foundation
import ObjectiveC.runtime

struct BatteryChargingState: Equatable, Sendable {
    let chargeLimit: UInt
    let chargingOverrideAllowed: Bool
    var manualChargeLimitEnabled = false
    var optimizedChargingOnHold = false

    /// Native limits can mark a held battery as charged below 100%, so `isCharged` is not a veto.
    func canChargeToFull(_ battery: BatterySnapshot?) -> Bool {
        guard let battery else { return false }
        return battery.isPluggedIn && !battery.isCharging && battery.level < 1
            && ((1..<100).contains(chargeLimit) || optimizedChargingOnHold)
            && (chargingOverrideAllowed || manualChargeLimitEnabled)
    }
}

enum BatteryChargingError: Error, Equatable {
    case unavailable
    case notOnHold
    case requestFailed
}

@MainActor
public final class BatteryChargingController: ObservableObject {
    @Published public private(set) var canChargeToFull = false
    @Published public private(set) var isRequesting = false
    @Published public var requestFailed = false

    typealias StateReader = @Sendable () async throws -> BatteryChargingState
    typealias ChargeRequester = @Sendable () async throws -> Void

    private let readState: StateReader
    private let requestCharge: ChargeRequester
    private var refreshRevision = 0

    public convenience init() {
        let session = PowerUIBatteryChargingSession()
        self.init(
            readState: { try await session.state() },
            requestCharge: { try await session.requestChargeToFull() }
        )
    }

    init(readState: @escaping StateReader, requestCharge: @escaping ChargeRequester) {
        self.readState = readState
        self.requestCharge = requestCharge
    }

    /// Refreshes eligibility without letting an older system reply replace a newer battery state.
    public func refresh(for battery: BatterySnapshot?) async {
        refreshRevision += 1
        let revision = refreshRevision
        guard !isRequesting else { return }
        guard let battery, battery.isPluggedIn, !battery.isCharging, battery.level < 1 else {
            canChargeToFull = false
            return
        }
        let state = try? await readState()
        guard revision == refreshRevision else { return }
        canChargeToFull = state?.canChargeToFull(battery) == true
    }

    /// Rechecks the live battery before the one-shot request; success means macOS accepted it.
    @discardableResult
    public func chargeToFull(battery: @MainActor () -> BatterySnapshot?) async -> Bool {
        guard canChargeToFull, !isRequesting else { return false }
        isRequesting = true
        refreshRevision += 1
        requestFailed = false
        canChargeToFull = false
        defer { isRequesting = false }
        do {
            let state = try await readState()
            canChargeToFull = state.canChargeToFull(battery())
            guard canChargeToFull else { throw BatteryChargingError.notOnHold }
            try await requestCharge()
            canChargeToFull = false
            return true
        } catch {
            requestFailed = true
            return false
        }
    }
}

/// Keeps a private, non-Sendable PowerUI client off the main actor and serializes native calls.
actor PowerUIBatteryChargingSession {
    private let makeClient: @Sendable () throws -> PowerUIBatteryChargingClient
    private var client: PowerUIBatteryChargingClient?

    init(makeClient: @escaping @Sendable () throws -> PowerUIBatteryChargingClient = { try .init() }) {
        self.makeClient = makeClient
    }

    func state() throws -> BatteryChargingState {
        try withClient { try $0.state() }
    }

    func requestChargeToFull() throws {
        try withClient { try $0.requestChargeToFull() }
    }

    /// Reuses successful connections, but discards failed ones so the next explicit operation can recover.
    private func withClient<Result>(_ operation: (PowerUIBatteryChargingClient) throws -> Result) throws -> Result {
        do {
            let current = try client ?? makeClient()
            client = current
            return try operation(current)
        } catch {
            client = nil
            throw error
        }
    }
}

struct PowerUIBatteryChargingClient {
    private static let frameworkLoaded = dlopen(
        "/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW | RTLD_LOCAL
    ) != nil

    private let object: NSObject

    /// Uses the native initializer's ownership convention while keeping private symbols optional.
    init() throws {
        let initializer = NSSelectorFromString("initWithClientName:")
        guard Self.frameworkLoaded,
              let clientClass = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
              clientClass.instancesRespond(to: initializer),
              let allocated = clientClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let client = allocated.perform(initializer, with: "dev.wzz.zisla")?.takeRetainedValue() as? NSObject
        else { throw BatteryChargingError.unavailable }
        object = client
    }

    init(object: NSObject) {
        self.object = object
    }

    /// Reads the native limit or legacy hold permission without changing charging preferences.
    func state() throws -> BatteryChargingState {
        let selector = NSSelectorFromString("smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:")
        if !object.responds(to: selector) {
            let legacySelector = NSSelectorFromString("isOBCEngaged:asDesktopDevice:chargingOverrideAllowed:withError:")
            let method = try method(legacySelector, encodings: ["B48@0:8^B16^B24^B32^@40", "c48@0:8^c16^c24^c32^@40"])
            typealias ReadEngagement = @convention(c) (
                AnyObject, Selector, UnsafeMutablePointer<ObjCBool>, UnsafeMutablePointer<ObjCBool>,
                UnsafeMutablePointer<ObjCBool>, AutoreleasingUnsafeMutablePointer<NSError?>
            ) -> Bool
            let read = unsafeBitCast(method_getImplementation(method), to: ReadEngagement.self)
            var engaged = ObjCBool(false)
            var desktop = ObjCBool(false)
            var allowed = ObjCBool(false)
            var error: NSError?
            guard read(object, legacySelector, &engaged, &desktop, &allowed, &error), error == nil
            else { throw BatteryChargingError.unavailable }
            return BatteryChargingState(
                chargeLimit: 100, chargingOverrideAllowed: allowed.boolValue,
                optimizedChargingOnHold: engaged.boolValue
            )
        }
        let method = try method(selector, encodings: ["B48@0:8^Q16^Q24^B32^@40", "c48@0:8^Q16^Q24^c32^@40"])
        typealias ReadState = @convention(c) (
            AnyObject, Selector, UnsafeMutablePointer<UInt>, UnsafeMutablePointer<UInt>,
            UnsafeMutablePointer<ObjCBool>, AutoreleasingUnsafeMutablePointer<NSError?>
        ) -> Bool
        let read = unsafeBitCast(method_getImplementation(method), to: ReadState.self)
        var uiState: UInt = 0
        var limit: UInt = 0
        var allowed = ObjCBool(false)
        var error: NSError?
        guard read(object, selector, &uiState, &limit, &allowed, &error), error == nil
        else { throw BatteryChargingError.unavailable }
        return BatteryChargingState(
            chargeLimit: limit, chargingOverrideAllowed: allowed.boolValue,
            manualChargeLimitEnabled: try manualChargeLimitEnabled()
        )
    }

    /// Selects the system's temporary override; a refusal never falls back to a permanent setter.
    func requestChargeToFull() throws {
        let selectorName = try manualChargeLimitEnabled() ? "temporarilyDisableMCL:" : "temporarilyEnableCharging:"
        let selector = NSSelectorFromString(selectorName)
        let method = try method(selector, encodings: ["B24@0:8^@16", "c24@0:8^@16"])
        typealias RequestCharge = @convention(c) (
            AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>
        ) -> Bool
        let request = unsafeBitCast(method_getImplementation(method), to: RequestCharge.self)
        var error: NSError?
        guard request(object, selector, &error), error == nil
        else { throw BatteryChargingError.requestFailed }
    }

    /// Treats absent manual limits as legacy macOS, but rejects unknown native enum values.
    private func manualChargeLimitEnabled() throws -> Bool {
        let manualSelector = NSSelectorFromString("isMCLCurrentlyEnabled:")
        guard object.responds(to: manualSelector) else { return false }
        let method = try method(manualSelector, encodings: ["Q24@0:8^@16"])
        typealias ReadManualLimit = @convention(c) (
            AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>
        ) -> UInt
        let read = unsafeBitCast(method_getImplementation(method), to: ReadManualLimit.self)
        var error: NSError?
        let enabled = read(object, manualSelector, &error)
        guard error == nil, enabled <= 1 else { throw BatteryChargingError.unavailable }
        return enabled == 1
    }

    /// Rejects ABI drift before casting an IMP to a function with pointer arguments.
    private func method(_ selector: Selector, encodings: [String]) throws -> Method {
        guard let method = class_getInstanceMethod(type(of: object), selector),
              let encoding = method_getTypeEncoding(method),
              encodings.contains(String(cString: encoding))
        else { throw BatteryChargingError.unavailable }
        return method
    }
}
