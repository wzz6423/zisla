import Foundation
import ZislaCore

@MainActor
public final class LowBatteryNoticeController {
    public nonisolated static let noticeID = "battery-low"

    private let queue: SideNoticeQueue
    private var notifiedAt: [String: Date] = [:]

    public init(queue: SideNoticeQueue) {
        self.queue = queue
    }

    public nonisolated static func isLowBatteryNotice(_ notice: IslandNotice) -> Bool {
        notice.id == noticeID || notice.id.hasPrefix("\(noticeID):")
    }

    public func update(devices: [NetworkBatteryDevice], enabled: Bool, at date: Date = Date()) {
        let prefix = "\(Self.noticeID):"
        let bluetoothDevices = devices.filter { $0.source == .bluetooth }
        queue.removeAll(
            withIDPrefix: prefix,
            except: Set(bluetoothDevices.map { prefix + $0.identifier })
        )
        for device in bluetoothDevices {
            let level = ([device.batteryLevel] + device.components.map(\.level))
                .filter { (0...1).contains($0) }
                .min()
            update(
                id: prefix + device.identifier,
                level: level,
                isCharging: device.isCharging,
                deviceName: device.name,
                enabled: enabled,
                at: date
            )
        }
    }

    public func update(snapshot: BatterySnapshot?, enabled: Bool, at date: Date = Date()) {
        guard let snapshot else {
            queue.remove(id: Self.noticeID)
            return
        }
        update(
            id: Self.noticeID,
            level: snapshot.level,
            isCharging: snapshot.isPluggedIn || snapshot.isCharging,
            deviceName: nil,
            enabled: enabled,
            at: date
        )
    }

    private func update(
        id: String,
        level: Double?,
        isCharging: Bool,
        deviceName: String?,
        enabled: Bool,
        at date: Date
    ) {
        guard let level, (0...1).contains(level) else {
            queue.remove(id: id)
            return
        }
        if level > 0.2 {
            notifiedAt[id] = nil
        }
        guard enabled, level <= 0.2, !isCharging else {
            queue.remove(id: id)
            return
        }

        let percent = Int((level * 100).rounded())
        let notice = IslandNotice(
            id: id,
            title: "电池电量低",
            detail: "\(percent)%",
            kind: .warning,
            side: .left,
            createdAt: notifiedAt[id] ?? date,
            style: .status,
            batteryLevels: deviceName.map { [NoticeBatteryLevel(label: $0, level: percent)] }
        )
        if notifiedAt[id] == nil {
            notifiedAt[id] = date
            queue.enqueue(notice)
        } else {
            // An expired or dismissed warning must not return on each battery refresh.
            queue.updateIfPresent(notice)
        }
    }
}
