import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct DailyBriefingStoreTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func observation(_ date: Date, active: Bool = true) -> DailyBriefingObservation {
        .init(date: date, applicationID: "editor", applicationName: "Editor", category: .work,
            isActive: active, isListening: false)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-briefing-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test
    func observationsSplitAtHoursAndMidnightAndSurviveRestart() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = DailyBriefingStore(fileURL: file)
        let before = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 23, minute: 59, second: 45))!
        try await store.observe(observation(before), calendar: calendar)
        try await store.observe(observation(before.addingTimeInterval(30)), calendar: calendar)
        try await store.observe(observation(before.addingTimeInterval(30)), calendar: calendar)
        try await store.flush()
        let restored = DailyBriefingStore(fileURL: file)
        let previousDay = try await restored.day(at: before, calendar: calendar)
        let nextDay = try await restored.day(at: before.addingTimeInterval(30), calendar: calendar)
        #expect(previousDay.activeSeconds == 15)
        #expect(previousDay.hourlySeconds[23] == 15)
        #expect(nextDay.activeSeconds == 15)
        #expect(nextDay.hourlySeconds[0] == 15)
        #expect(nextDay.firstActivity == calendar.startOfDay(for: before.addingTimeInterval(30)))
    }

    @Test
    func suspensionGapsAndInactiveEndpointsDoNotBecomeUsage() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DailyBriefingStore(fileURL: directory.appendingPathComponent("history.json"))
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        try await store.observe(observation(start), calendar: calendar)
        try await store.observe(observation(start.addingTimeInterval(30)), calendar: calendar)
        try await store.observe(observation(start.addingTimeInterval(60), active: false), calendar: calendar)
        try await store.observe(observation(start.addingTimeInterval(75)), calendar: calendar)
        try await store.observe(observation(start.addingTimeInterval(3675)), calendar: calendar)
        try await store.suspend()
        try await store.observe(observation(start.addingTimeInterval(3705)), calendar: calendar)
        let day = try await store.day(at: start, calendar: calendar)
        #expect(day.activeSeconds == 30)
        #expect(day.firstActivity == start)
    }

    @Test
    func staleAndPreviousDayHardwareCannotBeReportedAsCurrentReadings() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DailyBriefingStore(fileURL: directory.appendingPathComponent("history.json"))
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4))!
        var sample = observation(midnight)
        sample.hardware = .init(date: midnight.addingTimeInterval(-30), powerWatts: 999, batteryLevel: 1, fanRPM: 9999)
        try await store.observe(sample, calendar: calendar)
        sample.date = midnight.addingTimeInterval(30)
        sample.hardware = .init(date: midnight.addingTimeInterval(-100), powerWatts: 999, batteryLevel: 1, fanRPM: 9999)
        try await store.observe(sample, calendar: calendar)
        var day = try await store.day(at: midnight, calendar: calendar)
        #expect(day.peakPower == nil)
        #expect(day.minimumBattery == nil)
        sample.date = midnight.addingTimeInterval(60)
        sample.hardware = .init(date: sample.date, powerWatts: 0, batteryLevel: 0, fanRPM: 0)
        try await store.observe(sample, calendar: calendar)
        day = try await store.day(at: midnight, calendar: calendar)
        #expect(day.peakPower?.value == 0)
        #expect(day.peakFan?.value == 0)
        #expect(day.minimumBattery == 0)
    }

    @Test
    func scheduleIsOptInAndDeduplicatedAcrossRestarts() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = DailyBriefingStore(fileURL: file)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        let due = DailyBriefingSettings(enabled: true).exportDate(on: morning, calendar: calendar)
        try await store.observe(observation(morning), calendar: calendar)
        let disabled = try await store.pendingExports(at: due, settings: .init(), calendar: calendar)
        let early = try await store.pendingExports(at: due.addingTimeInterval(-1), settings: .init(enabled: true), calendar: calendar)
        #expect(disabled.isEmpty)
        #expect(early.isEmpty)
        let pending = try await store.pendingExports(at: due, settings: .init(enabled: true), calendar: calendar)
        #expect(pending.count == 1)
        try await store.markExported(pending[0])
        let restored = DailyBriefingStore(fileURL: file)
        let duplicate = try await restored.pendingExports(at: due.addingTimeInterval(3600), settings: .init(enabled: true), calendar: calendar)
        #expect(duplicate.isEmpty)
    }

    @Test
    func enablingAfterTheChosenTimeStartsWithTheNextDay() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DailyBriefingStore(fileURL: directory.appendingPathComponent("history.json"))
        let late = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 23))!
        try await store.observe(observation(late), calendar: calendar)
        let pending = try await store.pendingExports(at: late, settings: .init(enabled: true), calendar: calendar)
        #expect(pending.isEmpty)
    }

    @Test
    func historyAndExportMarkersRemainBounded() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = DailyBriefingStore(fileURL: file)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9))!
        for offset in 0..<40 {
            try await store.observe(observation(calendar.date(byAdding: .day, value: offset, to: start)!), calendar: calendar)
        }
        let pending = try await store.pendingExports(at: start.addingTimeInterval(50 * 86400), settings: .init(enabled: true), calendar: calendar)
        #expect(pending.count == 35)
        #expect(pending.first?.key == "2026-09-06")
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect((object["days"] as? [Any])?.count == 35)
    }

    @Test
    func failedCompletionPersistenceRemainsRetryable() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("archive")
        let file = folder.appendingPathComponent("history.json")
        let store = DailyBriefingStore(fileURL: file)
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        try await store.observe(observation(date), calendar: calendar)
        let day = try await store.day(at: date, calendar: calendar)
        let backup = directory.appendingPathComponent("backup")
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked".utf8).write(to: folder)
        await #expect(throws: (any Error).self) { try await store.markExported(day) }
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        let pending = try await store.pendingExports(at: date.addingTimeInterval(14 * 3600), settings: .init(enabled: true), calendar: calendar)
        #expect(pending.count == 1)
        try await store.markExported(day)
    }

    @Test
    func corruptArchivesArePreservedAndNeverOverwritten() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: file)
        let store = DailyBriefingStore(fileURL: file)
        await #expect(throws: (any Error).self) { try await store.observe(observation(Date()), calendar: calendar) }
        #expect(try Data(contentsOf: file) == corrupt)
    }

    @Test
    func concurrentExpansionsAreSerializedAndPersisted() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = DailyBriefingStore(fileURL: file)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = self.calendar
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { try await store.recordExpansion(at: date, calendar: calendar) } }
            try await group.waitForAll()
        }
        let day = try await DailyBriefingStore(fileURL: file).day(at: date, calendar: calendar)
        #expect(day.expansionCount == 20)
    }

    @Test
    func pngNamesAreLocalizedAndWritesStayInsideTheSelectedDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4))!
        #expect(DailyBriefingPNGExport.fileName(for: date, language: .english, calendar: calendar) == "zisla-2026-11-04-daily-briefing.png")
        #expect(DailyBriefingPNGExport.fileName(for: date, language: .simplifiedChinese, calendar: calendar) == "zisla-2026-11-04-每日简报.png")
        #expect(DailyBriefingPNGExport.fileName(for: date, language: .thai, calendar: calendar) == "zisla-2026-11-04-สรุปรายวัน.png")
        for language in AppLanguage.allCases {
            let name = DailyBriefingPNGExport.fileName(for: date, language: language, calendar: calendar)
            #expect(!name.contains("/"))
            #expect(name.hasPrefix("zisla-2026-11-04-"))
            #expect(name.hasSuffix(".png"))
        }
        let first = try DailyBriefingPNGExport.write(Data([1]), for: date, language: .english, calendar: calendar, directory: directory)
        let second = try DailyBriefingPNGExport.write(Data([2]), for: date, language: .english, calendar: calendar, directory: directory)
        #expect(first == second)
        #expect(try Data(contentsOf: first) == Data([2]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
        let outside = directory.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)")
        try Data([99]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.removeItem(at: first)
        try FileManager.default.createSymbolicLink(at: first, withDestinationURL: outside)
        #expect(throws: (any Error).self) {
            try DailyBriefingPNGExport.write(Data([3]), for: date, language: .english, calendar: calendar, directory: directory)
        }
        #expect(try Data(contentsOf: outside) == Data([99]))
        try FileManager.default.removeItem(at: outside)
        let replaced = try DailyBriefingPNGExport.write(Data([4]), for: date, language: .english, calendar: calendar, directory: directory)
        #expect(try Data(contentsOf: replaced) == Data([4]))
        #expect(!FileManager.default.fileExists(atPath: outside.path))
    }
}
