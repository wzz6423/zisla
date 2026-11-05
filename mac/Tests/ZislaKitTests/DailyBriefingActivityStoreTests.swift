import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct DailyBriefingActivityStoreTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("briefing-activity-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func activitiesSurviveRestartAndSeparateMidnightWithoutChangingUsage() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = DailyBriefingStore(fileURL: file)
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 23, minute: 59))!
        try await store.observe(.init(date: date, applicationID: "editor", applicationName: "Editor", category: .work,
            isActive: true, isListening: false), calendar: calendar)
        var before = DailyBriefingActivityBatch(date: date, calendar: calendar)
        before.activity.record(.clipboardCaptured)
        before.recordKeyPress(hour: 23)
        var after = DailyBriefingActivityBatch(date: date.addingTimeInterval(120), calendar: calendar)
        after.activity.record(.noteCreated)
        after.activity.record(.pomodoroCompleted, focusSeconds: 1500)
        after.recordKeyPress(hour: 0)
        try await store.recordActivities([after, before], calendar: calendar)
        let restored = DailyBriefingStore(fileURL: file)
        let first = try await restored.day(at: date, calendar: calendar)
        let second = try await restored.day(at: after.date, calendar: calendar)
        #expect(first.activity?.count(for: .clipboardCaptured) == 1)
        #expect(first.activity?.count(for: .noteCreated) == 0)
        #expect(first.hourlyKeyPresses?[23] == 1)
        #expect(first.hourlyKeyPresses?[22] == nil)
        #expect(second.activity?.count(for: .noteCreated) == 1)
        #expect(second.activity?.completedFocusSeconds == 1500)
        #expect(second.hourlyKeyPresses?[0] == 1)
        #expect(second.hourlyKeyPresses?[1] == nil)
        #expect(first.activeSeconds == 0)
        #expect(second.activeSeconds == 0)
    }

    @Test
    func failedBatchPersistenceRollsBackAndCanRetryExactlyOnce() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("archive")
        let file = folder.appendingPathComponent("history.json")
        let store = DailyBriefingStore(fileURL: file)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var original = DailyBriefingActivityBatch(date: date, calendar: calendar)
        original.activity.record(.quickNoteCreated)
        try await store.recordActivities([original], calendar: calendar)
        let backup = directory.appendingPathComponent("backup")
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked".utf8).write(to: folder)
        var delta = DailyBriefingActivityBatch(date: date, calendar: calendar)
        delta.activity.record(.quickNoteCreated)
        delta.recordKeyPress(hour: 8)
        await #expect(throws: (any Error).self) { try await store.recordActivities([delta], calendar: calendar) }
        let unchanged = try await store.day(at: date, calendar: calendar)
        #expect(unchanged.activity?.count(for: .quickNoteCreated) == 1)
        #expect(unchanged.hourlyKeyPresses == nil)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        try await store.recordActivities([delta], calendar: calendar)
        let restored = try await DailyBriefingStore(fileURL: file).day(at: date, calendar: calendar)
        #expect(restored.activity?.count(for: .quickNoteCreated) == 2)
        #expect(restored.hourlyKeyPresses?[8] == 1)
        #expect(restored.hourlyKeyPresses?[7] == nil)
    }

    @Test
    func emptyBatchesHaveNoFilesystemSideEffects() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = DailyBriefingStore(fileURL: file)
        try await store.recordActivities([], calendar: calendar)
        let day = try await store.day(at: Date(timeIntervalSince1970: 1_800_000_000), calendar: calendar)
        #expect(day.activity == nil)
        #expect(day.hourlyKeyPresses == nil)
        #expect(day.powerSamples == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test
    func concurrentBatchesKeepAllCountsAndExpiredDatesDoNotCrash() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = DailyBriefingStore(fileURL: file)
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let calendar = calendar
        for offset in 0..<40 {
            var batch = DailyBriefingActivityBatch(date: date.addingTimeInterval(Double(offset) * 86400), calendar: calendar)
            batch.activity.record(.shelfItemsAdded)
            try await store.recordActivities([batch], calendar: calendar)
        }
        var expired = DailyBriefingActivityBatch(date: date, calendar: calendar)
        expired.activity.record(.noteDeleted)
        try await store.recordActivities([expired], calendar: calendar)
        let latest = date.addingTimeInterval(39 * 86400)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    var batch = DailyBriefingActivityBatch(date: latest, calendar: calendar)
                    batch.activity.record(.shelfItemsAdded)
                    batch.recordKeyPress(hour: 10)
                    try await store.recordActivities([batch], calendar: calendar)
                }
            }
            try await group.waitForAll()
        }
        let day = try await store.day(at: latest, calendar: calendar)
        #expect(day.activity?.count(for: .shelfItemsAdded) == 21)
        #expect(day.hourlyKeyPresses?[10] == 20)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let days = try #require(object["days"] as? [[String: Any]])
        #expect(days.count == 35)
        #expect(!days.contains { $0["key"] as? String == "2026-09-01" })
    }

    @Test
    func observationsDistinguishNoTypingFromUnavailableTypingAndPreservePowerGaps() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DailyBriefingStore(fileURL: directory.appendingPathComponent("history.json"))
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        func observation(_ offset: TimeInterval, recording: Bool, hardwareDate: Date?) -> DailyBriefingObservation {
            .init(date: date.addingTimeInterval(offset), applicationID: "editor", applicationName: "Editor", category: .work,
                isActive: true, isListening: false,
                hardware: hardwareDate.map { .init(date: $0, powerWatts: 10) }, recordsKeyPresses: recording)
        }
        try await store.observe(observation(0, recording: false, hardwareDate: nil), calendar: calendar)
        #expect(try await store.day(at: date, calendar: calendar).hourlyKeyPresses == nil)
        try await store.observe(observation(30, recording: true, hardwareDate: date), calendar: calendar)
        try await store.observe(observation(60, recording: true, hardwareDate: date), calendar: calendar)
        try await store.observe(observation(900, recording: true, hardwareDate: date), calendar: calendar)
        let day = try await store.day(at: date, calendar: calendar)
        #expect(day.hourlyKeyPresses?[9] == 0)
        #expect(day.hourlyKeyPresses?[8] == nil)
        #expect(day.hourlyKeyPresses?[10] == nil)
        #expect(day.powerSamples?.count == 1)
        #expect(day.powerSamples?.first?.sampleCount == 1)
    }

    @Test
    func malformedPersistedSeriesArePreservedAndRejected() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var day = DailyBriefingDay(date: date, calendar: calendar)
        day.hourlyKeyPresses = [1, 2]
        let object = ["days": [try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(day)) as? [String: Any])], "exportedDays": []] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: file)
        let store = DailyBriefingStore(fileURL: file)
        await #expect(throws: (any Error).self) { try await store.day(at: date, calendar: calendar) }
        #expect(try Data(contentsOf: file) == data)
    }

    @Test
    func powerAggregationUsesTheObservationCalendarAtMidnightBoundaries() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DailyBriefingStore(fileURL: directory.appendingPathComponent("history.json"))
        var calendar = calendar
        calendar.timeZone = TimeZone(secondsFromGMT: TimeZone.current.secondsFromGMT() + 900)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 23))!
        let observation = DailyBriefingObservation(date: date, applicationID: "fixture", applicationName: "Fixture", category: .work,
            isActive: true, isListening: false, hardware: .init(date: date, powerWatts: 10))
        try await store.observe(observation, calendar: calendar)
        let day = try await store.day(at: date, calendar: calendar)
        #expect(day.powerSamples?.count == 1)
        #expect(day.powerSamples?.first?.averageWatts == 10)
    }

    @Test
    func lateKeyboardRecordingLeavesPastFutureAndDisabledHoursUnknown() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DailyBriefingStore(fileURL: directory.appendingPathComponent("history.json"))
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 20, minute: 59, second: 45))!
        func observation(_ offset: TimeInterval, records: Bool) -> DailyBriefingObservation {
            .init(date: date.addingTimeInterval(offset), applicationID: "fixture", applicationName: "Fixture", category: .work,
                isActive: false, isListening: false, recordsKeyPresses: records)
        }
        try await store.observe(observation(0, records: true), calendar: calendar)
        try await store.observe(observation(30, records: true), calendar: calendar)
        try await store.observe(observation(3600, records: true), calendar: calendar)
        try await store.observe(observation(3630, records: false), calendar: calendar)
        try await store.observe(observation(7215, records: true), calendar: calendar)
        var keys = try #require(try await store.day(at: date, calendar: calendar).hourlyKeyPresses)
        #expect(keys[0..<20].allSatisfy { $0 == nil })
        #expect(keys[20] == 0)
        #expect(keys[21] == 0)
        #expect(keys[22] == nil)
        #expect(keys[23] == 0)
        var batch = DailyBriefingActivityBatch(date: date.addingTimeInterval(7215), calendar: calendar)
        batch.recordKeyPress(hour: 23)
        try await store.recordActivities([batch], calendar: calendar)
        try await store.observe(observation(7245, records: true), calendar: calendar)
        keys = try #require(try await store.day(at: date, calendar: calendar).hourlyKeyPresses)
        #expect(keys[21] == 0)
        #expect(keys[23] == 1)
        #expect(keys[22] == nil)
        let restored = try await DailyBriefingStore(fileURL: directory.appendingPathComponent("history.json")).day(at: date, calendar: calendar)
        #expect(restored.hourlyKeyPresses == keys)
    }
}
