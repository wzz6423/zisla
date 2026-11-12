import Foundation
import ZislaCore

public enum MeetingCountdown {
    public static let noticePrefix = "meeting-countdown-"
    public static let leadTime: TimeInterval = 600

    public static func clock(for event: CalendarEventSnapshot, at date: Date) -> String {
        let seconds = Int(ceil(max(0, event.startDate.timeIntervalSince(date))))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    public static func notices(for event: CalendarEventSnapshot, at date: Date, locale: Locale) -> [IslandNotice] {
        let detail = event.startDate > date ? clock(for: event, at: date)
            : AppLocalization.string("会议进行中", locale: locale)
        return [NoticeSide.left, .right].map { side in
            IslandNotice(id: noticePrefix + event.id + (side == .left ? "-left" : "-right"),
                title: event.title, detail: detail, side: side, createdAt: event.startDate,
                symbolName: "video.fill", metadata: ["eventID": event.id])
        }
    }
}
