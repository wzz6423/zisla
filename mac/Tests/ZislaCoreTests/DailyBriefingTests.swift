import Foundation
import Testing
@testable import ZislaCore

struct DailyBriefingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test
    func legacySettingsDefaultOnAndRoundTripAllTemplates() throws {
        let legacy = try JSONDecoder().decode(FeatureSettings.self, from: Data("{}".utf8))
        #expect(legacy.dailyBriefing.enabled)
        #expect(legacy.dailyBriefing.minuteOfDay == 1320)
        #expect(DailyBriefingTemplate.allCases.count == 8)
        for template in DailyBriefingTemplate.allCases {
            var settings = legacy
            settings.dailyBriefing = .init(enabled: true, minuteOfDay: 1385, template: template, readsSystemScreenTime: false)
            let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
            #expect(restored.dailyBriefing == settings.dailyBriefing)
            #expect(restored.mediaEnabled == legacy.mediaEnabled)
        }
    }

    @Test(arguments: ["{}", #"{"dailyBriefing":null}"#, #"{"dailyBriefing":{}}"#,
                      #"{"dailyBriefing":{"enabled":null,"minuteOfDay":1385}}"#])
    func missingAndNullBriefingPreferencesEnableTheDailySchedule(payload: String) throws {
        #expect(DailyBriefingSettings().enabled)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
        #expect(settings.dailyBriefing.enabled)
        if payload.contains("1385") { #expect(settings.dailyBriefing.minuteOfDay == 1385) }
        let disabled = DailyBriefingSettings(enabled: false, minuteOfDay: 1385, template: .forest, readsSystemScreenTime: false)
        #expect(try JSONDecoder().decode(DailyBriefingSettings.self, from: JSONEncoder().encode(disabled)) == disabled)
    }

    @Test
    func templatesGroupLightStylesBeforeDarkStyles() {
        let rawValues = DailyBriefingTemplate.allCases.map(\.rawValue)
        #expect(rawValues == ["minimal", "paper", "forest", "sunrise", "coastal", "blossom", "midnight", "terminal"])
        #expect(Array(rawValues.suffix(2)) == ["midnight", "terminal"])
    }

    @Test(arguments: ["minimal", "paper", "midnight", "forest", "sunrise", "terminal"])
    func legacyTemplateRawValuesRemainDecodable(rawValue: String) throws {
        let settings = try JSONDecoder().decode(DailyBriefingSettings.self, from: Data("{\"template\":\"\(rawValue)\"}".utf8))
        #expect(settings.template.rawValue == rawValue)
    }

    @Test(arguments: [-900, 0, 1439, 9000])
    func invalidExportMinutesAreClamped(value: Int) throws {
        var settings = try JSONDecoder().decode(DailyBriefingSettings.self, from: Data("{\"minuteOfDay\":\(value)}".utf8))
        #expect(settings.minuteOfDay == min(1439, max(0, value)))
        settings.minuteOfDay = value
        #expect(settings.minuteOfDay == min(1439, max(0, value)))
    }

    @Test
    func invalidSettingsFailDecoding() {
        for source in [#"{"dailyBriefing":{"enabled":"yes"}}"#, #"{"dailyBriefing":{"template":"unknown"}}"#] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(FeatureSettings.self, from: Data(source.utf8))
            }
        }
    }

    @Test
    func exportScheduleUsesWallClockAcrossDaylightSavingChanges() {
        var calendar = self.calendar
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let spring = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let fall = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let evening = DailyBriefingSettings(minuteOfDay: 22 * 60)
        #expect(calendar.component(.hour, from: evening.exportDate(on: spring, calendar: calendar)) == 22)
        #expect(calendar.component(.hour, from: evening.exportDate(on: fall, calendar: calendar)) == 22)
        let skipped = DailyBriefingSettings(minuteOfDay: 150).exportDate(on: spring, calendar: calendar)
        #expect(calendar.component(.hour, from: skipped) == 3)
        #expect(calendar.isDate(skipped, inSameDayAs: spring))
    }

    @Test
    func activeAndIdleSamplesKeepMusicAndUsageSeparate() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var day = DailyBriefingDay(date: start, calendar: calendar)
        var observation = DailyBriefingObservation(date: start, applicationID: "editor", applicationName: "Editor",
            category: .work, isActive: true, isListening: true)
        day.record(from: start, to: start.addingTimeInterval(30), observation: observation, calendar: calendar)
        observation.isActive = false
        day.record(from: start.addingTimeInterval(30), to: start.addingTimeInterval(60), observation: observation, calendar: calendar)
        #expect(day.activeSeconds == 30)
        #expect(day.seconds(in: .work) == 30)
        #expect(day.listeningSeconds == 60)
        #expect(day.firstActivity == start)
        #expect(day.lastActivity == start.addingTimeInterval(30))
        #expect(day.observedThrough == start.addingTimeInterval(60))
        day.record(from: start, to: start.addingTimeInterval(1000), observation: observation, calendar: calendar)
        day.record(from: start, to: start, observation: observation, calendar: calendar)
        #expect(day.listeningSeconds == 60)
    }

    @Test
    func hardwarePeaksRejectUnavailableAndInvalidValues() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var day = DailyBriefingDay(date: start, calendar: calendar)
        day.record(hardware: .init(date: start, powerWatts: 52, batteryLevel: 0.8, fanRPM: 2000))
        day.record(hardware: .init(date: start.addingTimeInterval(60), powerWatts: 20, batteryLevel: 0.3, fanRPM: 3000))
        day.record(hardware: .init(date: start, powerWatts: .nan, batteryLevel: 2, fanRPM: -.infinity))
        day.record(hardware: .init(date: start, powerWatts: .infinity, batteryLevel: .nan, fanRPM: .infinity))
        #expect(day.peakPower == .init(value: 52, date: start))
        #expect(day.peakFan?.value == 3000)
        #expect(day.minimumBattery == 0.3)
        #expect(day.maximumBattery == 0.8)
        let empty = DailyBriefingDay(date: start, calendar: calendar)
        #expect(empty.peakPower == nil)
        #expect(empty.listeningSeconds == nil)
    }

    @Test
    func applicationCategoriesLeaveBrowsersUnclassified() {
        #expect(DailyBriefingCategory(applicationCategory: "public.app-category.developer-tools") == .work)
        #expect(DailyBriefingCategory(applicationCategory: "public.app-category.strategy-games") == .leisure)
        #expect(DailyBriefingCategory(applicationCategory: "public.app-category.music") == .leisure)
        #expect(DailyBriefingCategory(applicationCategory: "public.app-category.utilities") == .other)
        #expect(DailyBriefingCategory(applicationCategory: nil) == .other)
    }
}
