import Foundation
import CoreGraphics
import Testing

@testable import Zisla
@testable import KeyboardKit

@Suite(.serialized)
struct KeyboardSoundModuleViewTests {
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
    func islandKeyboardModuleIsReadOnlyAndFollowsAIMonitor() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Zisla/KeyboardSoundModuleView.swift"),
            encoding: .utf8
        )

        #expect(!viewSource.contains("Toggle("))
        #expect(!viewSource.contains("Picker("))
        #expect(!viewSource.contains("keyboardEnabled ="))
        #expect(!viewSource.contains("monitoringStateText"))
        #expect(!viewSource.contains("查看输入统计"))
        #expect(!viewSource.contains("openTypingStats()"))
        #expect(!viewSource.contains("只读监控"))
        #expect(!viewSource.contains("输入监控正在运行"))
        #expect(viewSource.contains("KeyboardTypingStatsDashboardView"))
        #expect(viewSource.contains("KeyboardTypingStatsDashboardView(summary: summary)"))
        #expect(!viewSource.contains("compact:"))

        let dashboardSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Zisla/KeyboardTypingStatsDashboardView.swift"),
            encoding: .utf8
        )
        #expect(dashboardSource.contains("输入趋势"))
        #expect(dashboardSource.contains("历史"))
        #expect(!dashboardSource.contains("subtitle:"))
        #expect(!dashboardSource.contains("Text(subtitle)"))
        let historyStart = try #require(dashboardSource.range(of: "private var historyPanel"))
        let keyboardStart = try #require(dashboardSource.range(of: "private var keyboardPanel"))
        let historySource = String(dashboardSource[historyStart.lowerBound..<keyboardStart.lowerBound])
        #expect(historySource.contains("LineMark("))
        #expect(!historySource.contains("BarMark("))
        #expect(historySource.contains("chartXScale(domain: domain)"))
        #expect(historySource.contains("AxisMarks(values: axisDates)"))
        // Both curves are LineMarks and need separate series values so Charts does not merge them.
        #expect(historySource.contains(#"series: .value("系列", "字符数")"#))
        #expect(historySource.contains(#"series: .value("系列", "峰值")"#))
        let historyLineMarkCount = historySource.components(separatedBy: "LineMark(").count - 1
        let historySeriesCount = historySource.components(separatedBy: "series: .value(").count - 1
        #expect(historyLineMarkCount == 2)
        #expect(historySeriesCount == historyLineMarkCount)
        #expect(dashboardSource.contains("键盘"))
        #expect(dashboardSource.contains("应用时间线"))
        #expect(dashboardSource.contains("今日按键"))
        #expect(dashboardSource.contains("累计按键"))
        #expect(dashboardSource.contains("private var activityPanels"))
        #expect(dashboardSource.contains("frame(height: 110)"))
        #expect(!dashboardSource.contains("let compact"))
        #expect(dashboardSource.contains("KeyboardHeatmapView"))
        #expect(dashboardSource.contains("Key(\"digit1\", \"1\", 18)"))
        #expect(dashboardSource.contains("Key(\"leftArrow\", \"←\", 123)"))
        #expect(dashboardSource.contains("Key(\"rightShift\", \"shift\", 60"))

        // The outer spacer keeps content-sized key counts aligned to the leading edge.
        let keyboardCountBody = try #require(
            dashboardSource
                .components(separatedBy: "private func keyboardCount")
                .dropFirst()
                .first?
                .components(separatedBy: "\n    private ")
                .first
        )
        #expect(!keyboardCountBody.contains("maxWidth: .infinity"))
        #expect(keyboardCountBody.contains("Self.compactCountText(count)"))
        #expect(keyboardCountBody.contains(".font(.system(size: 10, weight: .semibold, design: .monospaced))"))
        #expect(keyboardCountBody.contains(".accessibilityValue(count.formatted(.number))"))
        #expect(dashboardSource.contains("keyboardCount(\"累计按键\", summary.allTimeKeyPressCount)\n                Spacer()"))

        let modules = IslandModule.allCases
        let aiIndex = try #require(modules.firstIndex(of: .aiMonitor))
        let keyboardIndex = try #require(modules.firstIndex(of: .keyboardSound))
        #expect(keyboardIndex == modules.index(after: aiIndex))
    }

    @Test
    func heatmapKeycapShowsTodayAndAllTimeCounts() throws {
        let dashboardSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Zisla/KeyboardTypingStatsDashboardView.swift"),
            encoding: .utf8
        )

        #expect(dashboardSource.contains("todayCounts: summary.todayKeyCounts"))
        #expect(dashboardSource.contains("allTimeCounts: summary.allTimeKeyCounts"))
        #expect(!dashboardSource.contains("KeyboardHeatmapView(counts:"))

        #expect(dashboardSource.contains("let todayCount = key.keyCode.map { todayCounts[$0, default: 0] } ?? 0"))
        #expect(dashboardSource.contains("let allTimeCount = key.keyCode.map { allTimeCounts[$0, default: 0] } ?? 0"))
        #expect(dashboardSource.contains("KeyboardTypingStatsDashboardView.compactCountText(todayCount)"))
        #expect(dashboardSource.contains("KeyboardTypingStatsDashboardView.compactCountText(allTimeCount)"))
        #expect(dashboardSource.contains(".font(.system(size: 7, design: .monospaced))"))
        #expect(dashboardSource.contains(".minimumScaleFactor(0.7)"))

        #expect(dashboardSource.contains("0.08 + 0.68 * Double(todayCount) / Double(maximum)"))
        #expect(dashboardSource.contains("private var maximum: Int64 { max(1, todayCounts.values.max() ?? 0) }"))
        #expect(!dashboardSource.contains("Double(allTimeCount) / Double(maximum)"))

        #expect(dashboardSource.contains("if !compact, key.keyCode != nil {"))
        #expect(dashboardSource.contains(#"今日 \(todayCount.formatted(.number))，累计 \(allTimeCount.formatted(.number))"#))
        #expect(dashboardSource.contains(#"} ?? "")"#))
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
        #expect(KeyboardTypingStatsDashboardView.trendAxisDomain(for: Array(buckets.prefix(1))) == nil)

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
        #expect(historyDates.first == firstHistoryDate)
        #expect(historyDates.last == today)
        #expect(historyDates.contains(today))
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

    @Test
    func applicationTimelineAxisIsRenderedUnderRowsWithSharedSpacing() throws {
        let dashboardSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Zisla/KeyboardTypingStatsDashboardView.swift"),
            encoding: .utf8
        )

        let panelStart = try #require(dashboardSource.range(of: "private var applicationPanel"))
        let axisStart = try #require(dashboardSource.range(of: "private var timelineAxis"))
        let panelSource = String(dashboardSource[panelStart.lowerBound..<axisStart.lowerBound])

        #expect(panelSource.contains("timelineAxis"))
        // Bars and ticks must share one spacing constant to avoid independent drift.
        #expect(panelSource.contains("spacing: Self.timelineBucketSpacing"))
        #expect(!panelSource.contains("HStack(alignment: .bottom, spacing: 1)"))
        #expect(dashboardSource.contains(#"case "24h", "6h", "1h":"#))
        #expect(dashboardSource.contains(#"case "7d":"#))
    }
}
