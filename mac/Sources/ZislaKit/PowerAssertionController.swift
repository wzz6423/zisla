import Combine
import Foundation
import IOKit.pwr_mgt

/// IOPM assertion 抽象，便于单测注入。
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

/// 管理亮屏与防闲置系统休眠断言。
/// - 亮屏：`kIOPMAssertPreventUserIdleDisplaySleep`
/// - 合盖不熄屏（防闲置系统休眠）：`kIOPMAssertPreventUserIdleSystemSleep`
/// 文案须说明：合盖、低电量、用户主动休眠或硬件策略仍可能导致睡眠。
@MainActor
public final class PowerAssertionController: ObservableObject {
    public static let clamshellLimitationHint =
        "macOS 仍可能因合盖、低电量、用户主动休眠或硬件策略进入睡眠；外接显示器并接通电源时可获得系统原生 clamshell 支持。"

    @Published public private(set) var keepDisplayAwake = false
    @Published public private(set) var preventIdleSystemSleep = false

    private let manager: any PowerAssertionManaging
    private var displayAssertionID: IOPMAssertionID = 0
    private var systemAssertionID: IOPMAssertionID = 0
    private var hasDisplayAssertion = false
    private var hasSystemAssertion = false

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
        } else {
            releaseSystem()
        }
        preventIdleSystemSleep = hasSystemAssertion
    }

    public func releaseAll() {
        releaseDisplay()
        releaseSystem()
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

    private func acquireSystem() {
        guard !hasSystemAssertion else { return }
        var id: IOPMAssertionID = 0
        let result = manager.create(
            type: kIOPMAssertPreventUserIdleSystemSleep as CFString,
            name: "zisla Do not Sleep" as CFString,
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
