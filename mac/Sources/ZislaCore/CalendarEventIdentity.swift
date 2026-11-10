import Foundation

public struct CalendarEventIdentity: Codable, Equatable, Hashable, Sendable {
    public var calendarIdentifier: String
    public var eventIdentifier: String
    public var occurrenceDate: Date?

    public init(calendarIdentifier: String, eventIdentifier: String, occurrenceDate: Date? = nil) {
        self.calendarIdentifier = calendarIdentifier
        self.eventIdentifier = eventIdentifier
        self.occurrenceDate = occurrenceDate
    }
}
