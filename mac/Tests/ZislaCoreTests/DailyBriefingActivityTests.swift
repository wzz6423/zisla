import Foundation
import Testing
@testable import ZislaCore

struct DailyBriefingActivityTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test(arguments: DailyBriefingActivity.allCases)
    func activityCountsRoundTripWithoutMergingDifferentActions(activity: DailyBriefingActivity) throws {
        var totals = DailyBriefingActivityTotals()
        let duration: TimeInterval = activity == .pomodoroCompleted ? 1500 : 0
        let recorded = totals.record(activity, count: 2, focusSeconds: duration)
        #expect(recorded)
        #expect(totals.count(for: activity) == 2)
        #expect(totals.counts.count == 1)
        #expect(totals.completedFocusSeconds == duration)
        #expect(try JSONDecoder().decode(DailyBriefingActivityTotals.self, from: JSONEncoder().encode(totals)) == totals)
    }

    @Test
    func invalidEventsAndOverflowLeaveTotalsUnchanged() throws {
        var totals = DailyBriefingActivityTotals()
        for count in [0, -1] {
            let recorded = totals.record(.noteSaved, count: count)
            #expect(!recorded)
        }
        for duration in [-1.0, .nan, .infinity] {
            let recorded = totals.record(.pomodoroCompleted, focusSeconds: duration)
            #expect(!recorded)
        }
        let invalidDuration = totals.record(.noteSaved, focusSeconds: 1)
        #expect(!invalidDuration)
        #expect(totals == DailyBriefingActivityTotals())
        let data = Data("{\"counts\":{\"noteSaved\":\(Int64.max)}}".utf8)
        totals = try JSONDecoder().decode(DailyBriefingActivityTotals.self, from: data)
        let original = totals
        let overflow = totals.record(.noteSaved)
        #expect(!overflow)
        var delta = DailyBriefingActivityTotals()
        delta.record(.noteSaved)
        #expect(throws: (any Error).self) { try totals.merge(delta) }
        #expect(totals == original)
    }

    @Test
    func totalsPreserveFutureCountersAndRejectNegativeArchives() throws {
        let future = Data(#"{"counts":{"futureAction":7},"completedFocusSeconds":12}"#.utf8)
        var totals = try JSONDecoder().decode(DailyBriefingActivityTotals.self, from: future)
        totals.record(.quickNoteCreated)
        #expect(totals.counts["futureAction"] == 7)
        #expect(totals.count(for: .quickNoteCreated) == 1)
        for source in [#"{"counts":{"noteSaved":-1}}"#, #"{"completedFocusSeconds":-1}"#] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(DailyBriefingActivityTotals.self, from: Data(source.utf8))
            }
        }
    }

    @Test
    func legacyDaysKeepNewMetricsUnavailableUntilTheyAreRecorded() throws {
        let day = DailyBriefingDay(date: Date(timeIntervalSince1970: 1_800_000_000), calendar: calendar)
        #expect(day.activity == DailyBriefingActivityTotals())
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(day)) as? [String: Any])
        for key in ["activity", "hourlyKeyPresses", "powerSamples"] { object.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(DailyBriefingDay.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.activity == nil)
        #expect(restored.hourlyKeyPresses == nil)
        #expect(restored.powerSamples == nil)
        #expect(restored.hasValidTimeSeries)
    }

    @Test
    func batchesMergeHoursAndObservationBoundsAndRejectOtherDays() throws {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        var first = DailyBriefingActivityBatch(date: date, calendar: calendar)
        first.activity.record(.noteCreated)
        first.recordKeyPress(hour: 9)
        first.recordKeyPress(hour: -1)
        first.recordKeyPress(hour: 24)
        var second = DailyBriefingActivityBatch(date: date.addingTimeInterval(-3600), calendar: calendar)
        second.activity.record(.quickNoteSaved, count: 2)
        second.recordKeyPress(hour: 8)
        try first.merge(second)
        #expect(first.date == second.date)
        #expect(first.lastDate == date)
        #expect(first.activity.count(for: .noteCreated) == 1)
        #expect(first.activity.count(for: .quickNoteSaved) == 2)
        #expect(first.hourlyKeyPresses?[8] == 1)
        #expect(first.hourlyKeyPresses?[9] == 1)
        #expect(first.hourlyKeyPresses?.compactMap { $0 }.reduce(0, +) == 2)
        #expect(first.hourlyKeyPresses?[0] == nil)
        #expect(first.hourlyKeyPresses?[23] == nil)
        let previous = first
        let anotherDay = DailyBriefingActivityBatch(date: date.addingTimeInterval(86400), calendar: calendar)
        #expect(throws: (any Error).self) { try first.merge(anotherDay) }
        #expect(first == previous)
    }

    @Test
    func powerBucketsAverageDistinctSamplesAndKeepUnobservedGaps() throws {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4))!
        var day = DailyBriefingDay(date: date, calendar: calendar)
        func sample(_ offset: TimeInterval, _ watts: Double) -> DailyBriefingHardware {
            .init(date: date.addingTimeInterval(offset), powerWatts: watts)
        }
        day.record(hardware: sample(60, 10), calendar: calendar)
        day.record(hardware: sample(60, 999), calendar: calendar)
        day.record(hardware: sample(120, 30), calendar: calendar)
        day.record(hardware: sample(900, 0), calendar: calendar)
        day.record(hardware: sample(600, 40), calendar: calendar)
        day.record(hardware: sample(30, 500), calendar: calendar)
        day.record(hardware: sample(180, .nan), calendar: calendar)
        day.record(hardware: sample(180, -1), calendar: calendar)
        day.record(hardware: sample(86400, 80), calendar: calendar)
        let samples = try #require(day.powerSamples)
        #expect(samples.map(\.date) == [date, date.addingTimeInterval(600), date.addingTimeInterval(900)])
        #expect(samples.map(\.averageWatts) == [20, 40, 0])
        #expect(samples.map(\.sampleCount) == [2, 1, 1])
        #expect(day.hasValidTimeSeries)
        #expect(try JSONDecoder().decode(DailyBriefingDay.self, from: JSONEncoder().encode(day)).powerSamples == samples)
    }

    @Test(arguments: [3, 11])
    func fiveMinutePowerHistoryFitsShortAndLongDSTDays(month: Int) throws {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = calendar.date(from: DateComponents(year: 2026, month: month, day: month == 3 ? 8 : 1))!
        let interval = try #require(calendar.dateInterval(of: .day, for: date))
        var day = DailyBriefingDay(date: date, calendar: calendar)
        for offset in stride(from: 0.0, to: interval.duration, by: 300) {
            day.record(hardware: .init(date: date.addingTimeInterval(offset), powerWatts: 10), calendar: calendar)
        }
        #expect(day.powerSamples?.count == Int(interval.duration / 300))
        #expect(day.hasValidTimeSeries)
        #expect((day.powerSamples?.count ?? 0) <= 300)
    }

    @Test
    func invalidOrUnboundedSeriesAreRejected() {
        let date = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        var day = DailyBriefingDay(date: date, calendar: calendar)
        day.hourlyKeyPresses = [1]
        #expect(!day.hasValidTimeSeries)
        day.hourlyKeyPresses = Array(repeating: 0, count: 24)
        day.hourlyKeyPresses?[4] = -1
        #expect(!day.hasValidTimeSeries)
        day.hourlyKeyPresses = nil
        day.powerSamples = [.init(date: date, averageWatts: .infinity)]
        #expect(!day.hasValidTimeSeries)
        day.powerSamples = [.init(date: date.addingTimeInterval(1), averageWatts: 10)]
        #expect(!day.hasValidTimeSeries)
        day.powerSamples = [.init(date: date, averageWatts: 1), .init(date: date, averageWatts: 2)]
        #expect(!day.hasValidTimeSeries)
        day.powerSamples = (0...300).map { .init(date: date.addingTimeInterval(Double($0) * 300), averageWatts: 1) }
        #expect(!day.hasValidTimeSeries)
    }

    @Test
    func maliciousSampleCountCannotOverflowWhenAReadingArrives() throws {
        let date = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let sample = DailyBriefingPowerSample(date: date, averageWatts: 10)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any])
        object["sampleCount"] = Int.max
        var decoded = try JSONDecoder().decode(DailyBriefingPowerSample.self, from: JSONSerialization.data(withJSONObject: object))
        let original = decoded
        decoded.record(watts: 20, at: date.addingTimeInterval(1))
        #expect(decoded == original)
    }

    @Test
    func legacyNumericHoursDecodeAsKnownValuesAndNewUnknownHoursRoundTrip() throws {
        let date = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let day = DailyBriefingDay(date: date, calendar: calendar)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(day)) as? [String: Any])
        object["hourlyKeyPresses"] = Array(repeating: 2, count: 24)
        let legacy = try JSONDecoder().decode(DailyBriefingDay.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.hourlyKeyPresses == Array(repeating: Int64?(2), count: 24))
        var observed = day
        observed.recordKeyPressAvailability(hour: 20)
        #expect(observed.hourlyKeyPresses?[20] == 0)
        #expect(observed.hourlyKeyPresses?[0] == nil)
        #expect(observed.hourlyKeyPresses?[21] == nil)
        #expect(try JSONDecoder().decode(DailyBriefingDay.self, from: JSONEncoder().encode(observed)).hourlyKeyPresses == observed.hourlyKeyPresses)
    }
}
