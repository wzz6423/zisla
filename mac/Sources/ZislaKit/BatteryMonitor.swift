import Combine
import Foundation
import IOKit.ps

/// 电池状态快照。桌面 Mac 无内置电池时 `BatteryMonitor.snapshot` 为 nil。
public struct BatterySnapshot: Equatable, Sendable {
    /// 剩余电量占比，0...1。
    public var level: Double
    public var isCharging: Bool
    /// 是否接入外部电源（含充满后仍插电）。
    public var isPluggedIn: Bool
    public var isCharged: Bool
    /// 放电时为剩余分钟数、充电时为充满分钟数；系统仍在估算时为 nil。
    public var timeRemainingMinutes: Int?

    public init(
        level: Double,
        isCharging: Bool,
        isPluggedIn: Bool,
        isCharged: Bool,
        timeRemainingMinutes: Int?
    ) {
        self.level = level
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.isCharged = isCharged
        self.timeRemainingMinutes = timeRemainingMinutes
    }

    public var percentInt: Int {
        Int((level * 100).rounded())
    }

    /// 锁屏风格电量符号：充电中用 bolt，其余按档位选取对应填充图标。
    public var symbolName: String {
        if isCharging || (isPluggedIn && !isCharged) {
            return "battery.100percent.bolt"
        }
        switch percentInt {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// 使用公开 IOKit Power Source API 读取电量，并通过运行循环通知刷新。
@MainActor
public final class BatteryMonitor: ObservableObject {
    @Published public private(set) var snapshot: BatterySnapshot?

    private var runLoopSource: CFRunLoopSource?

    public init() {}

    public func start() {
        refresh()
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let unmanaged = IOPSNotificationCreateRunLoopSource({ rawContext in
            guard let rawContext else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(rawContext)
                .takeUnretainedValue()
            Task { @MainActor in monitor.refresh() }
        }, context) else { return }
        let source = unmanaged.takeRetainedValue()
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    public func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
    }

    public func refresh() {
        snapshot = Self.currentSnapshot()
    }

    nonisolated static func currentSnapshot() -> BatterySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue()
              as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if let snapshot = snapshot(from: description) { return snapshot }
        }
        return nil
    }

    /// 纯逻辑：把 Power Source 描述字典解析成快照，便于单测。
    nonisolated static func snapshot(from description: [String: Any]) -> BatterySnapshot? {
        if let type = description[kIOPSTypeKey as String] as? String,
           type != kIOPSInternalBatteryType as String {
            return nil
        }
        guard let current = (description[kIOPSCurrentCapacityKey as String] as? NSNumber)?
            .doubleValue,
            let maximum = (description[kIOPSMaxCapacityKey as String] as? NSNumber)?
            .doubleValue,
            maximum > 0 else { return nil }

        let level = min(max(current / maximum, 0), 1)
        let isCharging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false
        let isCharged = (description[kIOPSIsChargedKey as String] as? Bool) ?? false
        let state = description[kIOPSPowerSourceStateKey as String] as? String
        let isPluggedIn = state == (kIOPSACPowerValue as String)

        let rawTime = isCharging
            ? (description[kIOPSTimeToFullChargeKey as String] as? NSNumber)?.intValue
            : (description[kIOPSTimeToEmptyKey as String] as? NSNumber)?.intValue
        // IOKit 用 -1 表示仍在估算。
        let timeRemaining = (rawTime ?? -1) > 0 ? rawTime : nil

        return BatterySnapshot(
            level: level,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isCharged: isCharged,
            timeRemainingMinutes: timeRemaining
        )
    }
}
