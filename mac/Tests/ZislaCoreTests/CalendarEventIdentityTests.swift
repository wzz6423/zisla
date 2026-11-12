import Foundation
import Testing
@testable import ZislaCore

struct CalendarEventIdentityTests {
    @Test
    func eventIdentityRoundTripsWithoutUsingTheMutableTitleOrStartTime() throws {
        let identity = CalendarEventIdentity(calendarIdentifier: "work", eventIdentifier: "server-id")
        #expect(try JSONDecoder().decode(CalendarEventIdentity.self, from: JSONEncoder().encode(identity)) == identity)
        let recurring = CalendarEventIdentity(calendarIdentifier: "work", eventIdentifier: "server-id",
            occurrenceDate: Date(timeIntervalSince1970: 1_000))
        #expect(try JSONDecoder().decode(CalendarEventIdentity.self, from: JSONEncoder().encode(recurring)) == recurring)
        #expect(Set([identity, recurring]).count == 2)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(CalendarEventIdentity.self, from: Data("{}".utf8)) }
    }
}
