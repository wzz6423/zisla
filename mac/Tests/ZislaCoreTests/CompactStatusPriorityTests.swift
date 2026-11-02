import Foundation
import Testing

@testable import ZislaCore

struct CompactStatusPriorityTests {
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
