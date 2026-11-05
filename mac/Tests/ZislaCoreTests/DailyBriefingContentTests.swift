import Foundation
import Testing

@testable import ZislaCore

struct DailyBriefingContentTests {
    @Test
    func contentsHaveStableUniqueIdentifiersAndCompleteGroups() {
        let contents = DailyBriefingContent.allCases
        #expect(contents.count == 34)
        #expect(contents.map(\.rawValue) == [
            "localUsage", "firstActivity", "lastActivity", "allDevicesUsage", "hourlyUsage", "applicationUsage",
            "workTime", "leisureTime", "otherTime", "listeningTime", "characters", "topTypingApplication",
            "peakTypingHour", "keyPressTrend", "peakPower", "batteryRange", "peakFan", "powerTrend",
            "notificationCount", "unlockCount", "islandOpenings", "clipboardCaptured", "clipboardReused",
            "shelfItemsAdded", "shelfItemsCopied", "pomodoroStarted", "pomodoroCompleted", "completedFocusTime",
            "noteCreated", "noteSaved", "noteDeleted", "quickNoteCreated", "quickNoteSaved", "quickNoteDeleted",
        ])
        #expect(Set(contents.map(\.rawValue)).count == contents.count)
        #expect(Set(contents.map(\.title)).count == contents.count)
        #expect(DailyBriefingContentGroup.allCases.flatMap(\.contents) == contents)
        #expect(DailyBriefingContentGroup.allCases.map { $0.contents.count } == [10, 4, 6, 14])
        #expect(DailyBriefingContentGroup.allCases.allSatisfy { !$0.contents.isEmpty })
        #expect(contents.filter { $0.activity != nil }.count == 13)
        #expect(Set(contents.compactMap(\.activity)) == Set(DailyBriefingActivity.allCases))
        #expect(contents.allSatisfy { !$0.title.isEmpty })
        #expect(DailyBriefingContent.workTime.category == .work)
        #expect(DailyBriefingContent.leisureTime.category == .leisure)
        #expect(DailyBriefingContent.otherTime.category == .other)
    }

    @Test
    func missingSelectionEnablesEveryContentWhileEmptySelectionStaysEmpty() {
        #expect(DailyBriefingContent.selection(from: nil) == Set(DailyBriefingContent.allCases))
        #expect(DailyBriefingContent.defaultSelection == Set(DailyBriefingContent.allCases))
        #expect(DailyBriefingContent.selection(from: []).isEmpty)
    }

    @Test
    func unknownIdentifiersAreIgnoredWithoutRestoringDeselectedContents() {
        #expect(DailyBriefingContent.selection(from: ["peakPower", "futureMetric", "peakPower"]) == [.peakPower])
        #expect(DailyBriefingContent.selection(from: ["futureMetric"]).isEmpty)
    }

    @Test(arguments: DailyBriefingContent.allCases)
    func selectionContainsExactlyTheChosenItem(content: DailyBriefingContent) throws {
        let selection = DailyBriefingContent.selection(from: [content.rawValue])
        #expect(selection == [content])
        let data = try JSONEncoder().encode(selection)
        #expect(try JSONDecoder().decode(Set<DailyBriefingContent>.self, from: data) == selection)
    }

    @Test(arguments: ["{}", "{\"selectedContent\":null}"])
    func legacySettingsDefaultToAllContents(json: String) throws {
        let settings = try JSONDecoder().decode(DailyBriefingSettings.self, from: Data(json.utf8))
        #expect(settings.selectedContent == DailyBriefingContent.defaultSelection)
    }

    @Test
    func settingsPreserveEmptyAndSparseSelections() throws {
        let selections: [Set<DailyBriefingContent>] = [[], [.notificationCount, .noteSaved], DailyBriefingContent.defaultSelection]
        for selection in selections {
            let settings = DailyBriefingSettings(selectedContent: selection)
            let data = try JSONEncoder().encode(settings)
            #expect(try JSONDecoder().decode(DailyBriefingSettings.self, from: data).selectedContent == selection)
        }
        let unknown = try JSONDecoder().decode(DailyBriefingSettings.self,
            from: Data(#"{"selectedContent":["noteSaved","futureContent"]}"#.utf8))
        #expect(unknown.selectedContent == [.noteSaved])
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(DailyBriefingSettings.self, from: Data(#"{"selectedContent":"all"}"#.utf8))
        }
    }
}
