import AVFAudio
import Foundation
import CoreGraphics
import Testing

@testable import Zisla
@testable import KeyboardKit

@Suite(.serialized)
struct KeyboardSoundModuleViewTests {
    @Test
    @MainActor
    func idleKeyboardServicesDoNotConstructAudioEngine() throws {
        let suiteName = "Zisla.KeyboardSoundModuleViewTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "enabled")
        defaults.set(false, forKey: "typingStatsEnabled")

        var constructionCount = 0
        let audioEngine = KeyboardAudioEngine(makeEngine: {
            constructionCount += 1
            return AVAudioEngine()
        })
        let model = KeyboardAppModel(
            settings: AppSettings(defaults: defaults),
            audioEngine: audioEngine,
            startsServices: false
        )

        model.startServicesIfNeeded()
        #expect(constructionCount == 0)
        model.stop()
    }

    @Test
    @MainActor
    func rightCommandFlagsChangedPreservesPresses() {
        let rightCommand = UInt16(54)
        #expect(
            KeyboardMonitor.modifierIsDown(
                keyCode: rightCommand,
                flags: CGEventFlags(rawValue: 0x0000_0000_0000_0010),
                pressedModifierKeyCodes: []
            )
        )
        #expect(
            !KeyboardMonitor.modifierIsDown(
                keyCode: rightCommand,
                flags: CGEventFlags(rawValue: 0x0000_0000_0000_0008),
                pressedModifierKeyCodes: [rightCommand]
            )
        )
        #expect(
            KeyboardMonitor.modifierIsDown(
                keyCode: rightCommand,
                flags: .maskCommand,
                pressedModifierKeyCodes: []
            )
        )
        #expect(
            !KeyboardMonitor.modifierIsDown(
                keyCode: rightCommand,
                flags: .maskCommand,
                pressedModifierKeyCodes: [rightCommand]
            )
        )
    }

    @Test
    func islandKeyboardModuleFollowsAIMonitor() throws {
        let modules = IslandModule.allCases
        let aiIndex = try #require(modules.firstIndex(of: .aiMonitor))
        let keyboardIndex = try #require(modules.firstIndex(of: .keyboardSound))
        #expect(keyboardIndex == modules.index(after: aiIndex))
    }

    @Test
    @MainActor
    func dashboardChartAxesPinWindowEndpointsAndToday() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let bucketSeconds: TimeInterval = 900
        let buckets = (0..<4).map { index in
            KeyboardTypingStatsTrendPoint(
                id: index,
                start: start.addingTimeInterval(bucketSeconds * Double(index)),
                characterCount: Int64(index)
            )
        }

        let trendDomain = try #require(KeyboardTypingStatsDashboardView.trendAxisDomain(for: buckets))
        #expect(trendDomain.lowerBound == start)
        #expect(trendDomain.upperBound == start.addingTimeInterval(bucketSeconds * 4))
        let trendDates = KeyboardTypingStatsDashboardView.trendAxisDates(for: buckets)
        #expect(trendDates.first == trendDomain.lowerBound)
        #expect(trendDates.last == trendDomain.upperBound)
        #expect(KeyboardTypingStatsDashboardView.chartXAxisLabelPadding > 0)
        #expect(KeyboardTypingStatsDashboardView.trendAxisDomain(for: Array(buckets.prefix(1))) == nil)
        #expect(KeyboardTypingStatsDashboardView.trendCharacterCountUpperBound(for: buckets) == 3)
        #expect(KeyboardTypingStatsDashboardView.trendCharacterCountUpperBound(for: []) == 1)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let today = calendar.startOfDay(for: now)
        let firstHistoryDate = try #require(calendar.date(byAdding: .day, value: -13, to: today))
        let staleHistoryDate = try #require(calendar.date(byAdding: .day, value: -2, to: today))
        let history = [
            KeyboardTypingStatsDaySummary(
                id: "first",
                date: firstHistoryDate,
                characterCount: 10,
                peakCharactersPerSecond: 2,
                activeMinuteBuckets: 1
            ),
            KeyboardTypingStatsDaySummary(
                id: "stale",
                date: staleHistoryDate,
                characterCount: 20,
                peakCharactersPerSecond: 3,
                activeMinuteBuckets: 2
            ),
        ]

        let historyDomain = KeyboardTypingStatsDashboardView.historyAxisDomain(
            for: history,
            now: now,
            calendar: calendar
        )
        #expect(historyDomain.lowerBound == firstHistoryDate)
        #expect(historyDomain.upperBound == today)
        let historyDates = KeyboardTypingStatsDashboardView.historyAxisDates(
            for: history,
            now: now,
            calendar: calendar
        )
        #expect(historyDates.last == today)
        #expect(historyDates.contains(today))
        let expectedHistoryAxisDates = try [
            #require(calendar.date(byAdding: .day, value: -12, to: today)),
            #require(calendar.date(byAdding: .day, value: -9, to: today)),
            #require(calendar.date(byAdding: .day, value: -6, to: today)),
            #require(calendar.date(byAdding: .day, value: -3, to: today)),
            today,
        ]
        #expect(historyDates == expectedHistoryAxisDates)
        let historyDayIntervals = zip(historyDates, historyDates.dropFirst()).map {
            calendar.dateComponents([.day], from: $0, to: $1).day
        }
        #expect(historyDayIntervals == [3, 3, 3, 3])
    }

    @Test
    @MainActor
    func dashboardHistoryYAxisUsesCharacterCountMaximum() {
        let history = [
            KeyboardTypingStatsDaySummary(
                id: "first",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                characterCount: 8_000,
                peakCharactersPerSecond: 80_000,
                activeMinuteBuckets: 1
            ),
            KeyboardTypingStatsDaySummary(
                id: "second",
                date: Date(timeIntervalSince1970: 1_700_086_400),
                characterCount: 12_345,
                peakCharactersPerSecond: 120_000,
                activeMinuteBuckets: 1
            ),
        ]
        let zeroHistory = [
            KeyboardTypingStatsDaySummary(
                id: "zero",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                characterCount: 0,
                peakCharactersPerSecond: 1,
                activeMinuteBuckets: 0
            ),
        ]

        #expect(KeyboardTypingStatsDashboardView.historyCharacterCountUpperBound(for: history) == 12_345)
        #expect(KeyboardTypingStatsDashboardView.historyCharacterCountUpperBound(for: zeroHistory) == 1)
        #expect(KeyboardTypingStatsDashboardView.historyCharacterCountUpperBound(for: []) == 1)
    }

    @Test
    func dashboardCompactCountTextUsesKAndWBoundaries() {
        #expect(KeyboardTypingStatsDashboardView.compactCountText(-1) == "0")
        #expect(KeyboardTypingStatsDashboardView.compactCountText(999) == "999")
        #expect(KeyboardTypingStatsDashboardView.compactCountText(1_000) == "1k")
        #expect(KeyboardTypingStatsDashboardView.compactCountText(7_468) == "7.5k")
        #expect(KeyboardTypingStatsDashboardView.compactCountText(10_000) == "1w")
        #expect(KeyboardTypingStatsDashboardView.compactCountText(19_240) == "1.9w")
    }

    @Test
    @MainActor
    func applicationTimelineAxisAlignsWithBucketCells() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let step: TimeInterval = 900
        let buckets = (0..<96).map { index in
            KeyboardTypingStatsTrendPoint(
                id: index,
                start: start.addingTimeInterval(step * Double(index)),
                characterCount: Int64(index)
            )
        }
        let width: CGFloat = 240
        let spacing = KeyboardTypingStatsDashboardView.timelineBucketSpacing
        let ticks = KeyboardTypingStatsDashboardView.timelineAxisTicks(
            buckets: buckets,
            width: width
        )

        #expect(ticks.count == 3)

        let count = CGFloat(buckets.count)
        let cellWidth = (width - spacing * (count - 1)) / count
        let pitch = cellWidth + spacing

        // All ticks land on bucket boundaries: first edge, middle edge, and last edge.
        #expect(abs(ticks[0].x - 0) < 0.001)
        #expect(abs(ticks[1].x - 48 * pitch) < 0.001)
        #expect(abs(ticks[2].x - width) < 0.001)
        #expect(cellWidth > 0)

        #expect(ticks[0].date == start)
        #expect(ticks[1].date == start.addingTimeInterval(step * 48))
        #expect(ticks[2].date == start.addingTimeInterval(step * 96))

        // Time-to-pixel mapping must stay linear so labels remain aligned with buckets.
        let span = ticks[2].date.timeIntervalSince(ticks[0].date)
        for tick in ticks {
            let expected = CGFloat(tick.date.timeIntervalSince(ticks[0].date) / span) * width
            #expect(abs(tick.x - expected) < 1)
        }

        #expect(ticks[0].anchor == .leading)
        #expect(ticks[1].anchor == .center)
        #expect(ticks[2].anchor == .trailing)

        // Do not draw ticks without enough data or layout width.
        #expect(
            KeyboardTypingStatsDashboardView
                .timelineAxisTicks(buckets: Array(buckets.prefix(1)), width: width)
                .isEmpty
        )
        #expect(KeyboardTypingStatsDashboardView.timelineAxisTicks(buckets: buckets, width: 0).isEmpty)
    }

}
