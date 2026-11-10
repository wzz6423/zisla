import Foundation
import ZislaCore

public enum MeetingWorkflow {
    public static func meetings(in events: [CalendarEventSnapshot], at date: Date) -> [CalendarEventSnapshot] {
        var identities: Set<CalendarEventIdentity> = []
        var ids: Set<String> = []
        return events.filter {
            $0.kind == .event && !$0.isAllDay && !$0.isCancelled && !$0.isDeclined
                && $0.startDate.timeIntervalSince1970.isFinite && $0.endDate.timeIntervalSince1970.isFinite
                && $0.endDate > $0.startDate && $0.endDate > date && $0.meetingURL != nil
        }.sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            return $0.id < $1.id
        }.filter {
            if let identity = $0.eventIdentity { return identities.insert(identity).inserted }
            return ids.insert($0.id).inserted
        }
    }

    public static func currentMeeting(in events: [CalendarEventSnapshot], at date: Date) -> CalendarEventSnapshot? {
        meetings(in: events, at: date).first { $0.startDate <= date }
    }

    public static func nextMeeting(in events: [CalendarEventSnapshot], at date: Date) -> CalendarEventSnapshot? {
        meetings(in: events, at: date).first
    }
}
