import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct FanDisplayTests {
    @Test
    func menuBarMetricLabelsAreAlwaysEnglish() {
        #expect(SystemMonitorMenuBarMetric.allCases.map {
            SystemMonitorMenuBarPresentation.label(for: $0)
        } == ["CPU", "GPU", "Memory", "Disk", "Network", "Fans"])
    }

    @Test
    func detailedFanValueIncludesEveryReading() {
        #expect(SystemMonitorMenuBarPresentation.detailedFanValue([]) == nil)
        #expect(SystemMonitorMenuBarPresentation.detailedFanValue([2_000]) == "L 2000")
        #expect(SystemMonitorMenuBarPresentation.detailedFanValue([2_000, 2_500]) == "L 2000  R 2500")
        #expect(SystemMonitorMenuBarPresentation.detailedFanValue([
            1_000, 2_000, 3_000, 4_000, 5_000, 6_000, 7_000, 8_000,
        ]) == "L 1000  R 2000  F3 3000  F4 4000  F5 5000  F6 6000  F7 7000  F8 8000")
    }

    @Test
    func compactFanRowsUseLeftAndRightLinesWithoutDroppingReadings() {
        #expect(SystemMonitorMenuBarPresentation.compactFanRows([]) == [])
        #expect(SystemMonitorMenuBarPresentation.compactFanRows([2_000]) == ["L 2000"])
        #expect(SystemMonitorMenuBarPresentation.compactFanRows([2_000, 2_500]) == [
            "L 2000",
            "R 2500",
        ])
        #expect(SystemMonitorMenuBarPresentation.compactFanRows([
            1_000, 2_000, 3_000, 4_000, 5_000,
        ]) == [
            "L 1000   F3 3000   F5 5000",
            "R 2000   F4 4000",
        ])
    }

    @Test
    @MainActor
    func fanPositionLabelsFollowInterfaceLanguage() {
        #expect(SystemMonitorView.fanPositionLabel(for: 0, locale: Locale(identifier: "zh-Hans")) == "左")
        #expect(SystemMonitorView.fanPositionLabel(for: 1, locale: Locale(identifier: "zh-Hans")) == "右")
        #expect(SystemMonitorView.fanPositionLabel(for: 0, locale: Locale(identifier: "en")) == "L")
        #expect(SystemMonitorView.fanPositionLabel(for: 1, locale: Locale(identifier: "en")) == "R")
        #expect(SystemMonitorView.fanPositionLabel(for: 2, locale: Locale(identifier: "en")) == nil)
    }
}
