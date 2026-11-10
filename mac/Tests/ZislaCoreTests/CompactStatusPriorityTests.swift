import Foundation
import Testing

@testable import ZislaCore

struct CompactStatusPriorityTests {
    @Test
    func legacyMeetingInsertionKeepsTheUsersOtherPrioritiesAndCustomMeetingOrder() throws {
        let old = CompactStatusPriority.defaultOrder.filter { $0 != .meeting }
        let reversed = Array(old.reversed())
        let normalized = CompactStatusPriority.normalized(reversed)
        #expect(normalized.filter { $0 != .meeting } == reversed)
        #expect(normalized.firstIndex(of: .meeting) == normalized.firstIndex(of: .focusCountdown)! - 1)
        let custom = [.meeting, .media, .focusCountdown] + reversed.filter { $0 != .media && $0 != .focusCountdown }
        #expect(CompactStatusPriority.normalized(custom) == custom)
        #expect(CompactStatusPriority.normalized(normalized) == normalized)
        let settings = FeatureSettings(compactStatusPriority: normalized)
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test
    func machineMonitorIsAppendedToLegacyPriorityOrders() throws {
        #expect(CompactStatusPriority.defaultOrder.last?.rawValue == "systemMonitor")
        let data = Data(#"{"compactStatusPriority":["media","transient","media","aiActivity"]}"#.utf8)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(settings.compactStatusPriority.prefix(3).map(\.rawValue) == ["media", "transient", "aiActivity"])
        #expect(settings.compactStatusPriority.last?.rawValue == "systemMonitor")
        #expect(Set(settings.compactStatusPriority).count == settings.compactStatusPriority.count)
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test
    func customMonitorOrderSurvivesRepeatedNormalizationAndRoundTrip() throws {
        let settings = FeatureSettings(compactStatusPriority: [.systemMonitor, .media, .systemMonitor, .transient])
        #expect(Array(settings.compactStatusPriority.prefix(3)) == [.systemMonitor, .media, .transient])
        #expect(settings.compactStatusPriority.count == CompactStatusPriority.allCases.count)
        #expect(CompactStatusPriority.normalized(settings.compactStatusPriority) == settings.compactStatusPriority)
        #expect(CompactStatusPriority.normalized([]) == CompactStatusPriority.defaultOrder)
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test
    func defaultOrderMatchesSettingsPriority() {
        #expect(CompactStatusPriority.defaultOrder == [
            .transient,
            .videoDownload,
            .browserDownload,
            .mail,
            .meeting,
            .focusCountdown,
            .focusMode,
            .aiActivity,
            .media,
            .toolboxReminder,
            .updateAvailable,
            .systemMonitor,
        ])
    }
}
