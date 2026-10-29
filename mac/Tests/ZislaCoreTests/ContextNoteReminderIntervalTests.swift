import Foundation
import Testing
@testable import ZislaCore

struct ContextNoteReminderIntervalTests {
    @Test
    func optionsMatchTheRequestedFixedIntervals() {
        #expect(ContextNoteReminderInterval.allCases.map(\.duration) == [0, 3_600, 5_400, 10_800, 21_600, 43_200, 86_400, 172_800, 259_200])
        #expect(Set(ContextNoteReminderInterval.allCases.map(\.id)).count == 9)
    }

    @Test(arguments: ContextNoteReminderInterval.allCases)
    func persistedIntervalsRoundTrip(interval: ContextNoteReminderInterval) throws {
        #expect(try JSONDecoder().decode(ContextNoteReminderInterval.self, from: JSONEncoder().encode(interval)) == interval)
    }

    @Test(arguments: [-60, 1, 30, 61, Int.max])
    func unsupportedIntervalsCannotBeSelected(minutes: Int) {
        #expect(ContextNoteReminderInterval(rawValue: minutes) == nil)
    }
}
