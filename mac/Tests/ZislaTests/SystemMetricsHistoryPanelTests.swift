import AppKit
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

/// 历史窗口复用清理面板的窗口约定：普通窗口控件、关闭按钮回落到状态对象，不抢焦点层级。
@Suite(.serialized)
struct SystemMetricsHistoryPanelTests {
    @Test @MainActor
    func usesStandardWindowControlsAndRoutesClose() {
        let presentationState = SystemMetricsHistoryPanelPresentationState()
        let historyWindow = SystemMetricsHistoryPanel(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let window: NSWindow = historyWindow
        var cancelCount = 0
        presentationState.present()
        historyWindow.onCancel = {
            cancelCount += 1
            presentationState.dismiss()
        }

        #expect(!(window is NSPanel))
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.standardWindowButton(.closeButton) != nil)
        #expect(window.standardWindowButton(.miniaturizeButton) != nil)

        window.performClose(nil)
        #expect(cancelCount == 1)
        #expect(!presentationState.isPresented)
    }

    @Test @MainActor
    func staysAtNormalLevelWhenKeyStatusChanges() {
        let window = SystemMetricsHistoryPanel(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.level = .normal

        window.becomeKey()
        #expect(window.level == .normal)

        window.resignKey()
        #expect(window.level == .normal)
    }

    @Test
    func historyLoaderBindsRangeAndRejectsStaleTasks() throws {
        let source = try String(contentsOf: Self.historyViewSourceURL, encoding: .utf8)

        #expect(source.contains("private struct HistoryLoadRequest: Equatable"))
        #expect(source.contains(".task(id: HistoryLoadRequest(range: range, generation: reloadGeneration))"))
        #expect(source.contains("let loadedSections = await service.historySections(range: selectedRange)"))
        #expect(source.contains("let historyStats = service.historyStats"))
        #expect(source.contains("loadedHistoryStats = historyStats"))
        #expect(source.contains("let rangeEnd = Date()"))
        #expect(source.contains("sectionsLoadedAt = rangeEnd"))
        #expect(source.contains("guard !Task.isCancelled else { return }\n        let historyStats = service.historyStats\n        let rangeEnd = Date()"))
        #expect(source.contains("let loadedSections = await service.historySections(range: selectedRange)\n        guard !Task.isCancelled else { return }\n        sections = loadedSections"))
    }

    @Test
    func historyChartAppliesTheRangeDomain() throws {
        let source = try String(contentsOf: Self.historyViewSourceURL, encoding: .utf8)

        #expect(source.contains("SystemMetricsChartCard(section: section, xDomain: xDomain)"))
        #expect(source.contains("chart.chartXScale(domain: xDomain)"))
    }

    @Test
    func chartDomainFollowsTheSelectedRange() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let section = SystemMetricsChartSection(
            id: "cpu",
            titleKey: "CPU 利用率",
            unit: .ratio,
            series: [
                SystemMetricsChartSeries(
                    id: "cpu.usage",
                    titleKey: "利用率",
                    points: [
                        SystemMetricsChartPoint(date: now.addingTimeInterval(-60), value: 0.2),
                        SystemMetricsChartPoint(date: now, value: 0.4),
                    ]
                ),
            ]
        )

        let stats = SystemMetricsHistoryStats(
            count: 2,
            oldest: now.addingTimeInterval(-60),
            newest: now
        )
        let day = SystemMetricsHistoryChartDomain.domain(
            for: .day,
            historyStats: stats,
            sections: [section],
            now: now
        )
        let all = SystemMetricsHistoryChartDomain.domain(
            for: .all,
            historyStats: stats,
            sections: [section],
            now: now
        )

        #expect(day?.lowerBound == now.addingTimeInterval(-24 * 3600))
        #expect(day?.upperBound == now)
        #expect(all?.lowerBound == now.addingTimeInterval(-60))
        #expect(all?.upperBound == now)
    }

    @Test
    func allRangePadsAChartWithOnePoint() {
        let pointDate = Date(timeIntervalSince1970: 1_000_000)
        let section = SystemMetricsChartSection(
            id: "cpu",
            titleKey: "CPU 利用率",
            unit: .ratio,
            series: [
                SystemMetricsChartSeries(
                    id: "cpu.usage",
                    titleKey: "利用率",
                    points: [SystemMetricsChartPoint(date: pointDate, value: 0.4)]
                ),
            ]
        )

        let domain = SystemMetricsHistoryChartDomain.domain(
            for: .all,
            historyStats: SystemMetricsHistoryStats(count: 1, oldest: pointDate, newest: pointDate),
            sections: [section],
            now: pointDate
        )

        #expect(domain?.lowerBound == pointDate.addingTimeInterval(-60))
        #expect(domain?.upperBound == pointDate.addingTimeInterval(60))
    }

    @Test
    func allRangeUsesArchiveBoundsAfterSeriesBucketing() {
        let oldest = Date(timeIntervalSince1970: 1_000_000)
        let newest = oldest.addingTimeInterval(43_199 * 60)
        let sections = SystemMetricsHistorySeriesBuilder.sections(
            records: (0..<43_200).map { index in
                SystemMetricsRecord(
                    timestamp: oldest.addingTimeInterval(Double(index * 60)),
                    cpuUsage: 0.4
                )
            },
            range: .all,
            now: newest,
            maximumPoints: 240
        )
        let stats = SystemMetricsHistoryStats(count: 43_200, oldest: oldest, newest: newest)

        let domain = SystemMetricsHistoryChartDomain.domain(
            for: .all,
            historyStats: stats,
            sections: sections,
            now: newest
        )

        #expect(domain?.lowerBound == oldest)
        #expect(domain?.upperBound == newest)
    }

    @Test
    func xAxisTicksStartAtTheDomainLowerBound() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 1_789_000_000)
        let domain = start...start.addingTimeInterval(18 * 3600 + 30 * 60)

        let ticks = SystemMetricsChartAxis.dates(in: domain, calendar: calendar)

        #expect(ticks.first == domain.lowerBound)
        #expect(!ticks.isEmpty)
        #expect(ticks.count <= 6)
        #expect(ticks.allSatisfy { domain.contains($0) })
        #expect(zip(ticks, ticks.dropFirst()).allSatisfy { $1 > $0 })
    }

    @Test
    func xAxisTicksKeepAboutFiveLabelsAcrossSpanSizes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 1_789_000_000)
        let day = 24 * 3600.0
        let spans: [TimeInterval] = [2 * 3600, 24 * 3600, 7 * day, 30 * day, 365 * day]

        for span in spans {
            let ticks = SystemMetricsChartAxis.dates(
                in: start...start.addingTimeInterval(span),
                calendar: calendar
            )
            #expect(ticks.first == start, "span \(span) missed the start tick")
            #expect((2...6).contains(ticks.count), "span \(span) produced \(ticks.count) ticks")
        }

        // Beyond the step table the stride caps at the largest entry instead of degenerating.
        let ticks = SystemMetricsChartAxis.dates(
            in: start...start.addingTimeInterval(100 * 365 * day),
            calendar: calendar
        )
        #expect(ticks.first == start)
        #expect(!ticks.isEmpty)
    }

    @Test
    func xAxisTicksFallBackToTheStartLabelForZeroWidthDomains() {
        let date = Date(timeIntervalSince1970: 1_789_000_000)

        let ticks = SystemMetricsChartAxis.dates(in: date...date)

        #expect(ticks == [date])
    }

    @Test
    func historyChartBindsStartAnchoredXAxisTicks() throws {
        let source = try String(contentsOf: Self.historyViewSourceURL, encoding: .utf8)

        #expect(source.contains("SystemMetricsChartAxis.dates(in: xDomain)"))
        #expect(source.contains("AxisMarks(values: xAxisDates)"))
    }

    @Test
    func historyPanelKeepsVisibleThroughAppDeactivation() throws {
        let source = try String(contentsOf: Self.historyViewSourceURL, encoding: .utf8)

        #expect(source.contains("panel.hidesOnDeactivate = false"))
        #expect(source.contains("panel.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]"))
    }

    private static let historyViewSourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Zisla/SystemMetricsHistoryView.swift")
}
