import Combine
import Foundation
import IOKit.pwr_mgt
import ZislaCore

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
/// Manual keep-awake also owns a reversible system sleep override for lid closure.
@MainActor
public final class PowerAssertionController: ObservableObject {
    public static let clamshellLimitationHint =
        AppLocalization.text("macOS 仍可能因合盖、低电量、用户主动休眠或硬件策略进入睡眠；外接显示器并接通电源时可获得系统原生 clamshell 支持。")

    @Published public private(set) var keepDisplayAwake = false
    @Published public private(set) var preventIdleSystemSleep = false
    @Published public private(set) var isChangingDisplayAwake = false
    @Published public var displayAwakeError: String?

    private let manager: any PowerAssertionManaging
    private let startLidClosedSession: @Sendable () async throws -> any LidClosedDisplaySession
    private var lidClosedSession: (any LidClosedDisplaySession)?
    private var displayRequestRevision = 0
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

    public convenience init(manager: any PowerAssertionManaging) {
        self.init(manager: manager, startLidClosedSession: {
            try await Task.detached(priority: .userInitiated) {
                try PMSetLidClosedDisplaySession.start()
            }.value
        })
    }

    init(
        manager: any PowerAssertionManaging,
        startLidClosedSession: @escaping @Sendable () async throws -> any LidClosedDisplaySession
    ) {
        self.manager = manager
        self.startLidClosedSession = startLidClosedSession
    }

    isolated deinit {
        lidClosedSession?.cancel()
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
        displayRequestRevision &+= 1
        if enabled {
            acquireDisplay()
        } else {
            lidClosedSession?.cancel()
            lidClosedSession = nil
            releaseDisplay()
        }
        keepDisplayAwake = hasDisplayAssertion
    }

    public func setKeepDisplayAwakeIncludingLidClose(_ enabled: Bool) async {
        guard !isChangingDisplayAwake else { return }
        isChangingDisplayAwake = true
        displayAwakeError = nil
        displayRequestRevision &+= 1
        let revision = displayRequestRevision
        defer { isChangingDisplayAwake = false }

        if enabled {
            guard lidClosedSession == nil else { return }
            let alreadyAwake = hasDisplayAssertion
            acquireDisplay()
            guard hasDisplayAssertion else {
                displayAwakeError = "无法开启合盖亮屏，请检查管理员授权后重试。"
                return
            }
            do {
                let session = try await startLidClosedSession()
                guard revision == displayRequestRevision else {
                    session.cancel()
                    return
                }
                lidClosedSession = session
                keepDisplayAwake = true
            } catch {
                guard revision == displayRequestRevision else { return }
                if !alreadyAwake { releaseDisplay() }
                displayAwakeError = "无法开启合盖亮屏，请检查管理员授权后重试。"
            }
        } else {
            do {
                if let session = lidClosedSession {
                    try await Task.detached(priority: .userInitiated) {
                        try session.stop()
                    }.value
                }
                guard revision == displayRequestRevision else { return }
                lidClosedSession = nil
                releaseDisplay()
                keepDisplayAwake = false
            } catch {
                guard revision == displayRequestRevision else { return }
                displayAwakeError = "无法恢复休眠设置，请重试关闭保持亮屏。"
            }
        }
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
        displayRequestRevision &+= 1
        lidClosedSession?.cancel()
        lidClosedSession = nil
        displayAwakeError = nil
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
