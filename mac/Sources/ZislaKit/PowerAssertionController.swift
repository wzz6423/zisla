import Combine
import Foundation
import IOKit.pwr_mgt

/// IOPM assertion abstraction for unit test injection.
@MainActor
public protocol PowerAssertionManaging: AnyObject {
    func create(
        type: CFString,
        name: CFString,
        level: IOPMAssertionLevel,
        assertionID: inout IOPMAssertionID
    ) -> IOReturn

    func release(assertionID: IOPMAssertionID) -> IOReturn
}

@MainActor
public final class IOPMPowerAssertionManager: PowerAssertionManaging {
    public init() {}

    public func create(
        type: CFString,
        name: CFString,
        level: IOPMAssertionLevel,
        assertionID: inout IOPMAssertionID
    ) -> IOReturn {
        IOPMAssertionCreateWithName(type, level, name, &assertionID)
    }

    public func release(assertionID: IOPMAssertionID) -> IOReturn {
        IOPMAssertionRelease(assertionID)
    }
}

/// Manages display-on and idle-system-sleep-prevention assertions.
/// - Display on: `kIOPMAssertPreventUserIdleDisplaySleep`
/// - Prevent idle system sleep: `kIOPMAssertPreventUserIdleSystemSleep`
/// Both assertions affect idle behaviour only; macOS still sleeps for lid close, low battery,
/// user-initiated sleep, or hardware policy.
@MainActor
public final class PowerAssertionController: ObservableObject {
    public static let clamshellLimitationHint =
        "macOS 仍可能因合盖、低电量、用户主动休眠或硬件策略进入睡眠；外接显示器并接通电源时可获得系统原生 clamshell 支持。"

    @Published public private(set) var keepDisplayAwake = false
    @Published public private(set) var preventIdleSystemSleep = false

    private let manager: any PowerAssertionManaging
    private var displayAssertionID: IOPMAssertionID = 0
    private var activityDisplayAssertionID: IOPMAssertionID = 0
    private var systemAssertionID: IOPMAssertionID = 0
    private var hasDisplayAssertion = false
    private var hasActivityDisplayAssertion = false
    private var hasSystemAssertion = false
    private var aiActivityActive = false

    public convenience init() {
        self.init(manager: IOPMPowerAssertionManager())
    }

    public init(manager: any PowerAssertionManaging) {
        self.manager = manager
    }

    isolated deinit {
        // IOKit release is safe from any thread for teardown.
        if hasDisplayAssertion {
            _ = manager.release(assertionID: displayAssertionID)
        }
        if hasActivityDisplayAssertion {
            _ = manager.release(assertionID: activityDisplayAssertionID)
        }
        if hasSystemAssertion {
            _ = manager.release(assertionID: systemAssertionID)
        }
    }

    public func setKeepDisplayAwake(_ enabled: Bool) {
        if enabled {
            acquireDisplay()
        } else {
            releaseDisplay()
        }
        keepDisplayAwake = hasDisplayAssertion
    }

    public func setPreventIdleSystemSleep(_ enabled: Bool) {
        if enabled {
            acquireSystem()
            if hasSystemAssertion, aiActivityActive {
                acquireActivityDisplay()
            }
        } else {
            releaseActivityDisplay()
            releaseSystem()
        }
        preventIdleSystemSleep = hasSystemAssertion
    }

    /// Keeps the display awake while an AI task is active, but only when the user has
    /// enabled the separate idle-system-sleep prevention switch.
    public func setAIActivityActive(_ active: Bool) {
        aiActivityActive = active
        guard hasSystemAssertion, active else {
            releaseActivityDisplay()
            return
        }
        acquireActivityDisplay()
    }

    public func releaseAll() {
        releaseDisplay()
        releaseActivityDisplay()
        releaseSystem()
        aiActivityActive = false
        keepDisplayAwake = false
        preventIdleSystemSleep = false
    }

    private func acquireDisplay() {
        guard !hasDisplayAssertion else { return }
        var id: IOPMAssertionID = 0
        let result = manager.create(
            type: kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            name: "zisla Keep Screen On" as CFString,
            level: IOPMAssertionLevel(kIOPMAssertionLevelOn),
            assertionID: &id
        )
        if result == kIOReturnSuccess {
            displayAssertionID = id
            hasDisplayAssertion = true
        }
    }

    private func releaseDisplay() {
        guard hasDisplayAssertion else { return }
        _ = manager.release(assertionID: displayAssertionID)
        displayAssertionID = 0
        hasDisplayAssertion = false
    }

    private func acquireActivityDisplay() {
        guard !hasActivityDisplayAssertion else { return }
        var id: IOPMAssertionID = 0
        let result = manager.create(
            type: kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            name: "zisla AI Activity Keep Screen On" as CFString,
            level: IOPMAssertionLevel(kIOPMAssertionLevelOn),
            assertionID: &id
        )
        if result == kIOReturnSuccess {
            activityDisplayAssertionID = id
            hasActivityDisplayAssertion = true
        }
    }

    private func releaseActivityDisplay() {
        guard hasActivityDisplayAssertion else { return }
        _ = manager.release(assertionID: activityDisplayAssertionID)
        activityDisplayAssertionID = 0
        hasActivityDisplayAssertion = false
    }

    private func acquireSystem() {
        guard !hasSystemAssertion else { return }
        var id: IOPMAssertionID = 0
        let result = manager.create(
            type: kIOPMAssertPreventUserIdleSystemSleep as CFString,
            name: "zisla Prevent Idle Sleep" as CFString,
            level: IOPMAssertionLevel(kIOPMAssertionLevelOn),
            assertionID: &id
        )
        if result == kIOReturnSuccess {
            systemAssertionID = id
            hasSystemAssertion = true
        }
    }

    private func releaseSystem() {
        guard hasSystemAssertion else { return }
        _ = manager.release(assertionID: systemAssertionID)
        systemAssertionID = 0
        hasSystemAssertion = false
    }
}
