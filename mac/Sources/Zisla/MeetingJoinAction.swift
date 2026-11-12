import AppKit
import ZislaKit

enum MeetingJoinResult: Equatable {
    case opened
    case unavailable
    case failed
}

@MainActor
enum MeetingJoinAction {
    static func perform(
        _ event: CalendarEventSnapshot,
        resolve: (CalendarEventSnapshot) -> CalendarEventSnapshot?,
        open: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) -> MeetingJoinResult {
        guard let current = resolve(event), let url = current.meetingURL else { return .unavailable }
        return open(url) ? .opened : .failed
    }
}
