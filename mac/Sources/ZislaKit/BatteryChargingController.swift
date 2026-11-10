import Combine
import Darwin
import Foundation
import ObjectiveC.runtime

struct BatteryChargingState: Equatable, Sendable {
    let chargeLimit: UInt
    let chargingOverrideAllowed: Bool
    var manualChargeLimitEnabled = false
    var optimizedChargingOnHold = false

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
        self.init(
            readState: {
                try await Task.detached(priority: .utility) {
                    try PowerUIBatteryChargingClient().state()
                }.value
            },
            requestCharge: {
                try await Task.detached(priority: .userInitiated) {
                    try PowerUIBatteryChargingClient().requestChargeToFull()
                }.value
            }
        )
    }

    init(readState: @escaping StateReader, requestCharge: @escaping ChargeRequester) {
        self.readState = readState
        self.requestCharge = requestCharge
    }

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

struct PowerUIBatteryChargingClient {
    private static let frameworkLoaded = dlopen(
        "/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW | RTLD_LOCAL
    ) != nil

    private let object: NSObject

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

    func requestChargeToFull() throws {
        let selectorName = try manualChargeLimitEnabled() ? "temporarilyDisableMCL:" : "temporarilyEnableCharging:"
        // Match Control Center's one-shot override without changing saved charging preferences.
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

    private func method(_ selector: Selector, encodings: [String]) throws -> Method {
        guard let method = class_getInstanceMethod(type(of: object), selector),
              let encoding = method_getTypeEncoding(method),
              encodings.contains(String(cString: encoding))
        else { throw BatteryChargingError.unavailable }
        return method
    }
}
