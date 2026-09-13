import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct AlarmItemTests {
    @Test
    func initClampsOutOfRangeTimeAndWeekdays() {
        let alarm = AlarmItem(hour: 30, minute: -5, weekdays: [0, 3, 8])
        #expect(alarm.hour == 23)
        #expect(alarm.minute == 0)
        #expect(alarm.weekdays == [3])
    }

    @Test
    func decodingPreservesValidAlarmsAcrossAllWeekdaySets() throws {
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        for mask in 0..<128 {
            let alarm = AlarmItem(
                id: id,
                hour: mask % 24,
                minute: mask % 60,
                label: "Morning",
                weekdays: Set((1...7).filter { mask & (1 << ($0 - 1)) != 0 }),
                isEnabled: mask.isMultiple(of: 2)
            )
            let restored = try JSONDecoder().decode(AlarmItem.self, from: JSONEncoder().encode(alarm))

            #expect(restored == alarm)
        }
    }

    @Test
    func decodingNormalizesPersistedTimeAndWeekdays() throws {
        let data = Data("""
            {"id":"00000000-0000-0000-0000-000000000001","hour":30,"minute":-5,
             "label":"Morning","weekdays":[0,3,8],"isEnabled":true}
            """.utf8)
        let alarm = try JSONDecoder().decode(AlarmItem.self, from: data)

        #expect(alarm.hour == 23)
        #expect(alarm.minute == 0)
        try #require(alarm.weekdays == [3])
        #expect(alarm.repeatText == "周二")
    }

    @Test
    func decodingBoundsExtremeValuesAndKeepsEmptyRepeatSet() throws {
        let data = Data("""
            {"id":"00000000-0000-0000-0000-000000000001","hour":\(Int.min),"minute":\(Int.max),
             "label":"","weekdays":[\(Int.min),0,8,\(Int.max)],"isEnabled":false}
            """.utf8)
        let alarm = try JSONDecoder().decode(AlarmItem.self, from: data)

        #expect(alarm.hour == 0)
        #expect(alarm.minute == 59)
        try #require(alarm.weekdays.isEmpty)
        #expect(alarm.repeatText == "仅一次")
        #expect(alarm.nextTriggerDate() == nil)
    }

    @Test
    func decodingRejectsMissingOrInvalidFields() throws {
        let fields: [String: Any] = [
            "id": "00000000-0000-0000-0000-000000000001",
            "hour": 8,
            "minute": 0,
            "label": "Morning",
            "weekdays": [2, 4],
            "isEnabled": true,
        ]
        for field in fields.keys.sorted() {
            var missingField = fields
            missingField.removeValue(forKey: field)
            let missingData = try JSONSerialization.data(withJSONObject: missingField)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(AlarmItem.self, from: missingData)
            }

            var invalidField = fields
            invalidField[field] = [:] as [String: String]
            let invalidData = try JSONSerialization.data(withJSONObject: invalidField)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(AlarmItem.self, from: invalidData)
            }
        }
    }

    @Test
    func loadingNormalizesPersistedAlarmsWithoutRewritingTheFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-alarm-decoding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("alarms.json")
        let original = Data("""
            [{"id":"00000000-0000-0000-0000-000000000001","hour":30,"minute":-5,
              "label":"Morning","weekdays":[0,3,8],"isEnabled":true}]
            """.utf8)
        try original.write(to: storageURL)

        let service = AlarmService(storageURL: storageURL, cancelHandler: { _ in })
        var alarm = try #require(service.alarms.first)
        #expect(alarm.hour == 23)
        #expect(alarm.minute == 0)
        #expect(alarm.weekdays == [3])
        #expect(service.errorMessage == nil)
        #expect(try Data(contentsOf: storageURL) == original)

        service.suspend()
        alarm.label = "Updated"
        service.update(alarm)
        let restored = AlarmService(storageURL: storageURL)
        #expect(restored.alarms == [alarm])
        #expect(restored.errorMessage == nil)
    }

    @Test
    func loadingInvalidAlarmDataKeepsTheFileAndCanRecover() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-alarm-invalid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("alarms.json")
        let original = Data("[{\"hour\":8}]".utf8)
        try original.write(to: storageURL)

        let service = AlarmService(storageURL: storageURL)
        #expect(service.alarms.isEmpty)
        #expect(service.errorMessage != nil)
        #expect(try Data(contentsOf: storageURL) == original)

        let alarm = AlarmItem(hour: 8, minute: 30)
        try JSONEncoder().encode([alarm]).write(to: storageURL)
        let restored = AlarmService(storageURL: storageURL)
        #expect(restored.alarms == [alarm])
        #expect(restored.errorMessage == nil)
    }

    @Test
    func timeTextPadsToTwoDigits() {
        #expect(AlarmItem(hour: 7, minute: 5).timeText == "07:05")
        #expect(AlarmItem(hour: 23, minute: 59).timeText == "23:59")
    }

    @Test
    func repeatTextNamesCommonWeekdaySets() {
        #expect(AlarmItem(hour: 8, minute: 0, weekdays: []).repeatText == "仅一次")
        #expect(AlarmItem(hour: 8, minute: 0, weekdays: Set(1...7)).repeatText == "每天")
        #expect(AlarmItem(hour: 8, minute: 0, weekdays: Set(2...6)).repeatText == "工作日")
        #expect(AlarmItem(hour: 8, minute: 0, weekdays: [1, 7]).repeatText == "周末")
        #expect(AlarmItem(hour: 8, minute: 0, weekdays: [2, 4]).repeatText == "周一 周三")
    }

    @Test
    func oneShotAlarmRollsToTomorrowOnceTimeHasPassed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 26, hour: 12, minute: 0)
        ))

        let later = try #require(
            AlarmItem(hour: 18, minute: 30).nextTriggerDate(after: now, calendar: calendar)
        )
        #expect(calendar.dateComponents([.day, .hour, .minute], from: later)
            == DateComponents(day: 26, hour: 18, minute: 30))

        let passed = try #require(
            AlarmItem(hour: 9, minute: 15).nextTriggerDate(after: now, calendar: calendar)
        )
        #expect(calendar.dateComponents([.day, .hour, .minute], from: passed)
            == DateComponents(day: 27, hour: 9, minute: 15))
    }

    @Test
    func repeatingAlarmPicksTheNearestSelectedWeekday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        // 2026-07-26 is a Sunday (weekday == 1).
        let now = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 26, hour: 12, minute: 0)
        ))
        #expect(calendar.component(.weekday, from: now) == 1)

        let wednesday = try #require(
            AlarmItem(hour: 7, minute: 0, weekdays: [4]).nextTriggerDate(after: now, calendar: calendar)
        )
        #expect(calendar.dateComponents([.day, .hour, .minute], from: wednesday)
            == DateComponents(day: 29, hour: 7, minute: 0))

        // Today is still selected, but 07:00 has passed, so advance to the next selected day (Monday).
        let nextSunday = try #require(
            AlarmItem(hour: 7, minute: 0, weekdays: [1, 2]).nextTriggerDate(after: now, calendar: calendar)
        )
        #expect(calendar.dateComponents([.day, .hour, .minute], from: nextSunday)
            == DateComponents(day: 27, hour: 7, minute: 0))
    }

    @Test
    func notificationIdentifiersCoverEachSelectedWeekday() {
        let oneShot = AlarmItem(hour: 8, minute: 0)
        #expect(AlarmService.notificationIdentifiers(for: oneShot)
            == ["zisla.alarm.\(oneShot.id.uuidString)"])

        let repeating = AlarmItem(hour: 8, minute: 0, weekdays: [5, 2])
        #expect(AlarmService.notificationIdentifiers(for: repeating) == [
            "zisla.alarm.\(repeating.id.uuidString).2",
            "zisla.alarm.\(repeating.id.uuidString).5",
        ])
    }
}
