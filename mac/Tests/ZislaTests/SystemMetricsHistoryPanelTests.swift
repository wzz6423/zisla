import AppKit
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

/// Preserve standard history controls and distinguish explicit requests from passive view updates.
@Suite(.serialized)
struct SystemMetricsHistoryPanelTests {
    /// Uses a nonordering window to exercise the real coordinator without changing application focus.
    @Test @MainActor
    func repeatedRequestsRaiseTheWindowOncePerClickAndDismissalCanReopen() throws {
        let state = SystemMetricsHistoryPanelPresentationState()
        let history = OrderingHistoryPanel(
            contentRect: CGRect(x: -100_000, y: -100_000, width: 720, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        let host = SettingsWindow(
            contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false
        )
        history.isReleasedWhenClosed = false
        host.isReleasedWhenClosed = false
        defer { history.close(); host.close() }
        let service = SystemMonitorService()
        var collapseRequests = 0
        var coordinator = SystemMetricsHistoryPanelPresenter.Coordinator(
            panel: history, requestIslandCollapse: { collapseRequests += 1 }
        )
        #expect(!state.isPresented)
        state.present()
        let first = try #require(state.requestID)
        coordinator.update(
            requestID: first, dismissPresentation: state.dismiss,
            service: service, hostWindow: host
        )
        #expect(history.frontRequestCount == 1)
        #expect(history.requestedKey)
        history.reportsVisible = true
        coordinator.update(
            requestID: first, dismissPresentation: state.dismiss,
            service: service, hostWindow: host
        )
        #expect(history.frontRequestCount == 1, "Passive updates must not take focus from Settings")

        state.present()
        let second = try #require(state.requestID)
        #expect(second != first)
        coordinator.update(
            requestID: second, dismissPresentation: state.dismiss,
            service: service, hostWindow: host
        )
        #expect(history.frontRequestCount == 2, "Another click must raise the already visible history window")
        history.reportsVisible = false
        history.reportsMiniaturized = true
        coordinator.update(
            requestID: second, dismissPresentation: state.dismiss,
            service: service, hostWindow: host
        )
        #expect(history.frontRequestCount == 2, "Passive updates must preserve minimization")
        state.present()
        coordinator.update(
            requestID: state.requestID, dismissPresentation: state.dismiss,
            service: service, hostWindow: host
        )
        #expect(history.frontRequestCount == 3, "An explicit click must restore the minimized history window")

        history.reportsMiniaturized = false
        history.reportsVisible = true
        state.dismiss()
        coordinator.update(
            requestID: state.requestID, dismissPresentation: state.dismiss,
            service: service, hostWindow: host
        )
        #expect(state.requestID == nil)
        #expect(!state.isPresented)
        #expect(!history.isVisible)
        #expect(history.frontRequestCount == 3)
        coordinator = SystemMetricsHistoryPanelPresenter.Coordinator(
            panel: history, requestIslandCollapse: { collapseRequests += 1 }
        )
        state.present()
        coordinator.update(
            requestID: state.requestID, dismissPresentation: state.dismiss,
            service: service, hostWindow: host
        )
        #expect(history.frontRequestCount == 4)
        #expect(collapseRequests == 4)
    }

    /// Exercises origin-dependent focus requests without ordering real application windows.
    @Test(arguments: ["settings", "island", "detached"])
    @MainActor
    func presentationTakesFocusOnlyFromSettings(origin: String) {
        let history = OrderingHistoryPanel(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        history.isReleasedWhenClosed = false
        let host: NSWindow? = switch origin {
        case "settings": SettingsWindow(
            contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false
        )
        case "island": NSPanel(
            contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false
        )
        default: nil
        }
        host?.isReleasedWhenClosed = false
        defer { history.close(); host?.close() }

        history.present(over: host)

        #expect(history.requestedKey == (origin == "settings"))
        #expect(history.requestedOrderFront == (origin != "settings"))
        #expect(!history.isVisible)
    }

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

    @MainActor
    private final class OrderingHistoryPanel: SystemMetricsHistoryPanel {
        var requestedKey = false
        var requestedOrderFront = false
        var frontRequestCount = 0
        var reportsVisible = false
        var reportsMiniaturized = false

        override var isVisible: Bool { reportsVisible }
        override var isMiniaturized: Bool { reportsMiniaturized }

        override func makeKeyAndOrderFront(_ sender: Any?) {
            requestedKey = true
            frontRequestCount += 1
        }

        override func orderFront(_ sender: Any?) {
            requestedOrderFront = true
            frontRequestCount += 1
        }

        override func orderOut(_ sender: Any?) {
            reportsVisible = false
        }
    }

}
