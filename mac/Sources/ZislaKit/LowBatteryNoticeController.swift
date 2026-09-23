import Foundation
import ZislaCore

@MainActor
public final class LowBatteryNoticeController {
    public nonisolated static let noticeID = "battery-low"

    private let queue: SideNoticeQueue
    private var notifiedAt: Date?

    public init(queue: SideNoticeQueue) {
        self.queue = queue
    }

    public func update(snapshot: BatterySnapshot?, enabled: Bool, at date: Date = Date()) {
        guard let snapshot, (0...1).contains(snapshot.level) else {
            queue.remove(id: Self.noticeID)
            return
        }
        if snapshot.level > 0.2 {
            notifiedAt = nil
        }
        guard enabled, snapshot.level <= 0.2, !snapshot.isPluggedIn, !snapshot.isCharging else {
            queue.remove(id: Self.noticeID)
            return
        }

        let notice = IslandNotice(
            id: Self.noticeID,
            title: "电池电量低",
            detail: "\(snapshot.percentInt)%",
            kind: .warning,
            side: .left,
            createdAt: notifiedAt ?? date,
            style: .status
        )
        if notifiedAt == nil {
            notifiedAt = date
            queue.enqueue(notice)
        } else {
            // An expired or dismissed warning must not return on each power-source update.
            queue.updateIfPresent(notice)
        }
    }
}
