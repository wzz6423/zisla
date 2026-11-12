import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite(.serialized)
struct AIUsageHistoryPresentationTests {
    /// Explicit requests raise the AI report above Settings; passive refreshes preserve focus and minimization.
    @Test @MainActor
    func historyRequestsRaiseOncePerClickAndReopenAfterClose() throws {
        let state = SystemMetricsHistoryPanelPresentationState()
        let panel = OrderingAIHistoryPanel(contentRect: CGRect(x: -100_000, y: -100_000, width: 760, height: 640),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let host = SettingsWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        host.isReleasedWhenClosed = false
        defer { panel.close(); host.close() }
        let controller = AIUsageHistoryController(read: { AIUsageHistory() }, clear: {}, write: { _, _ in })
        let languageStore = AppLanguageStore()
        var coordinator = AIUsageHistoryPanelPresenter.Coordinator(window: panel)
        func update() {
            coordinator.update(requestID: state.requestID, dismiss: state.dismiss,
                controller: controller, languageStore: languageStore, hostWindow: host)
        }
        state.present()
        let first = try #require(state.requestID)
        update()
        #expect(panel.frontRequestCount == 1 && panel.requestedKey)
        panel.reportsVisible = true
        update()
        #expect(panel.frontRequestCount == 1, "A passive refresh cannot retake focus")
        state.present()
        #expect(state.requestID != first)
        update()
        #expect(panel.frontRequestCount == 2, "A repeated click must raise an already visible report")
        panel.reportsVisible = false
        panel.reportsMiniaturized = true
        update()
        #expect(panel.frontRequestCount == 2, "Passive updates must preserve minimization")
        state.present()
        update()
        #expect(panel.frontRequestCount == 3, "An explicit request must restore the minimized report")
        panel.reportsMiniaturized = false
        panel.reportsVisible = true
        panel.onCancel()
        #expect(state.requestID == nil && !panel.reportsVisible)
        update()
        #expect(panel.frontRequestCount == 3)
        coordinator = AIUsageHistoryPanelPresenter.Coordinator(window: panel)
        state.present()
        update()
        #expect(panel.frontRequestCount == 4 && panel.requestedKey)
        #expect(!host.isVisible, "The test must not order a real Settings window")
    }

    /// Short ranges must keep 12-point cells instead of stretching one week across the entire window width.
    @Test(arguments: [SystemMetricsHistoryRange.day, .week, .month, .all], [LayoutDirection.leftToRight, .rightToLeft])
    @MainActor
    func fixedHeatmapCellsRemainVisibleWithinSmallHistoryWindows(range: SystemMetricsHistoryRange, direction: LayoutDirection) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let old = try #require(calendar.date(byAdding: .year, value: -1, to: today))
        let sample = AIUsageSample(provider: .codex, timestamp: old, inputTokens: 10, outputTokens: 2)
        let history = AIUsageHistory(usageSamples: [sample])
        let domain = AIUsageHistoryPresentation.domain(history: history, range: range, now: today)
        let weeks = AIUsageHistoryPresentation.heatmap(history: history, domain: domain,
            year: range == .all ? today : nil, now: today)
        let root = UsageHeatmap(weeks: weeks, selectedDate: .constant(today), cellSize: 12)
            .environment(\.layoutDirection, direction)
        let renderer = ImageRenderer(content: root)
        let rendered = try #require(renderer.cgImage)
        #expect(rendered.height >= 120 && rendered.height < 180, "Heatmap cells must not produce a tall clipped grid")
        let expectedGridWidth = CGFloat(weeks.count) * 12 + CGFloat(max(0, weeks.count - 1)) * 1.5
        #expect(abs(CGFloat(rendered.width) - max(240, expectedGridWidth)) <= 1)

        let host = NSHostingView(rootView: ScrollView(.horizontal) { root }.frame(width: 584, height: 160))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 584, height: 160),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let cells = accessibilityObjects(host).compactMap { object -> (any NSAccessibilityElementProtocol)? in
            guard value(object, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue else { return nil }
            return object as? any NSAccessibilityElementProtocol
        }
        try #require(!cells.isEmpty, "Calendar dates must remain selectable through accessibility")
        // Accessibility includes the existing half-point outline and one-point selection stroke outside the 12-point cell.
        #expect(cells.allSatisfy {
            let frame = $0.accessibilityFrame()
            return (abs(frame.height - 12.5) < 0.1 || abs(frame.height - 13) < 0.1)
                && abs(frame.height - frame.width) < 0.1
        }, "Calendar button bounds must contain only the fixed cell and its outline")
        #expect(!window.isVisible)
    }

    /// A calendar button and chart coordinates select the same zero-usage day, which the model detail preserves.
    @Test @MainActor
    func heatmapAndChartSelectionAgreeForEmptyDays() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let next = try #require(Calendar.current.date(byAdding: .day, value: 1, to: day))
        var selected: Date?
        let weeks: [[ContributionDay?]] = [[ContributionDay(date: day, tokens: 0)] + Array(repeating: nil, count: 6)]
        let host = NSHostingView(rootView: UsageHeatmap(weeks: weeks, selectedDate: Binding(get: { selected }, set: { selected = $0 }), cellSize: 12))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let cell = try #require(accessibilityObjects(host).first {
            value($0, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue
        })
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(cell.responds(to: press))
        _ = cell.perform(press)
        #expect(selected == day)
        #expect(UsageTrendChart.selectionDate(at: day.addingTimeInterval(3600), domain: day...next) == selected)
        #expect(UsageTrendChart.selectionDate(at: next, domain: day...next) == nil)
        let detail = AIUsageHistoryPresentation.selectedDay(in: .init(), date: try #require(selected))
        #expect(detail.date == day && detail.models.isEmpty && detail.totalTokens == 0)
    }

    /// All seven dates remain on one row; details appear only after a user selects a date and survive refreshes.
    @Test(arguments: [CGSize(width: 620, height: 480), CGSize(width: 760, height: 640)],
        [LayoutDirection.leftToRight, .rightToLeft])
    @MainActor
    func historyWindowFitsAndRefreshKeepsTheSelectedDate(size: CGSize, direction: LayoutDirection) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let language: AppLanguage = direction == .rightToLeft ? .arabic : .english
        let today = Calendar.current.startOfDay(for: Date())
        let older = try #require(Calendar.current.date(byAdding: .day, value: -1, to: today))
        let archiveStart = try #require(Calendar.current.date(byAdding: .year, value: -1, to: today))
        var samples = [AIUsageSample(provider: .codex, timestamp: today, inputTokens: 10, outputTokens: 2, model: "today-model"),
            AIUsageSample(provider: .claude, timestamp: older, inputTokens: 20, outputTokens: 4, model: "older-model"),
            AIUsageSample(provider: .gpt, timestamp: archiveStart, inputTokens: 1, outputTokens: 1, model: "archive-model")]
        let controller = AIUsageHistoryController(read: { .init(usageSamples: samples, modelUsageSamples: samples) }, clear: {}, write: { _, _ in })
        await controller.load()
        let host = NSHostingView(rootView: AIUsageHistoryContent(controller: controller)
            .environment(\.locale, language.locale).environment(\.layoutDirection, direction))
        host.sizingOptions = []
        let window = SystemMetricsHistoryPanel(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        func settle() async {
            for _ in 0..<5 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
        }
        await settle()
        let cells = accessibilityObjects(host).filter {
            value($0, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue
                && (value($0, "accessibilityLabel") as? String)?.contains("Token") == true
        }
        try #require(cells.count == 7, "The default week must keep all seven calendar dates in the assembled window")
        let frames = cells.compactMap { ($0 as? any NSAccessibilityElementProtocol)?.accessibilityFrame() }
        #expect(frames.allSatisfy { $0.height >= 12 && $0.height <= 13.1 })
        #expect((frames.map(\.midY).max() ?? 0) - (frames.map(\.midY).min() ?? 0) < 1,
            "The seven calendar dates must form one horizontal row")
        #expect(Set(frames.map { Int($0.midX.rounded()) }).count == 7)
        let scroll = try #require(descendants(host).compactMap { $0 as? NSScrollView }.max(by: { $0.frame.height < $1.frame.height }))
        let document = try #require(scroll.documentView)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle()
        func displayedValues() -> [String] {
            accessibilityObjects(host).compactMap { value($0, "accessibilityValue") as? String }
        }
        #expect(!displayedValues().contains { $0.contains("today-model") }, "The initial selection must be empty")
        #expect(!displayedValues().contains { $0.contains("older-model") })
        let oldCell = try #require(cells.first { (value($0, "accessibilityLabel") as? String)?.contains("24 Token") == true })
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(oldCell.responds(to: press))
        _ = oldCell.perform(press)
        await settle()
        #expect(displayedValues().contains { $0.contains("older-model") })
        samples[0].inputTokens += 10
        await controller.load()
        await settle()
        #expect(displayedValues().contains { $0.contains("older-model") }, "Refreshing must preserve the selected older day")
        let allRange = try #require(accessibilityObjects(host).first { object in
            ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].contains { key in
                value(object, key) as? String == AppLocalization.string(SystemMetricsHistoryRange.all.titleKey, language: language)
            }
        })
        try #require(allRange.responds(to: press))
        _ = allRange.perform(press)
        await settle()
        let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
        try #require(scrolls.count == 2, "All history must keep a vertical body and a horizontal calendar")
        let vertical = try #require(scrolls.max(by: { $0.frame.height < $1.frame.height }))
        let horizontal = try #require(scrolls.first { $0 !== vertical })
        await settle()
        let viewport = window.convertToScreen(vertical.contentView.convert(vertical.contentView.bounds, to: nil))
        let calendarDocument = try #require(horizontal.documentView)
        let calendarBounds = window.convertToScreen(calendarDocument.convert(calendarDocument.bounds, to: nil))
        let calendarViewport = window.convertToScreen(horizontal.contentView.convert(horizontal.contentView.bounds, to: nil))
        #expect(vertical.scrollerStyle == .overlay)
        let chartLabel = try #require(accessibilityObjects(host).first {
            value($0, "accessibilityValue") as? String == AppLocalization.string("Token 消耗趋势", language: language)
        } as? any NSAccessibilityElementProtocol)
        #expect(chartLabel.accessibilityFrame().minX >= viewport.minX
            && chartLabel.accessibilityFrame().maxX <= viewport.maxX,
            "Long-range chart labels must remain visible in both layout directions")
        let tracks = [try #require(vertical.verticalScroller), try #require(horizontal.horizontalScroller)].map {
            window.convertToScreen($0.convert($0.bounds, to: nil))
        }
        let visibleFrames = accessibilityObjects(host).compactMap { object -> CGRect? in
            let role = value(object, "accessibilityRole") as? String
            guard role == NSAccessibility.Role.staticText.rawValue || role == NSAccessibility.Role.button.rawValue,
                  let element = object as? any NSAccessibilityElementProtocol else { return nil }
            var frame = element.accessibilityFrame()
            if calendarBounds.intersects(frame) { frame = frame.intersection(calendarViewport) }
            frame = frame.intersection(viewport)
            return frame.isNull ? nil : frame
        }
        try #require(!visibleFrames.isEmpty)
        #expect(visibleFrames.allSatisfy { frame in !tracks.contains { $0.intersects(frame) } },
            "History scrollbars must not cover chart labels, calendar cells, or model values")
        #expect(!window.isVisible && window.level == .normal)
    }

    /// Daily persistence cannot supply a 24-hour chart; the unselected date remains a working detail entry.
    @Test(arguments: [false, true], [AppLanguage.simplifiedChinese, .english, .arabic]) @MainActor
    func dayRangeHidesChartsAndOnlyRevealsDetailsAfterItsDateButton(empty: Bool, language: AppLanguage) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: today))
        let samples = empty ? [] : [
            AIUsageSample(sourceID: AIUsageAnalytics.dailyUsageSummaryPrefix + "fixture", provider: .codex,
                timestamp: today.addingTimeInterval(8 * 3600), inputTokens: 10, outputTokens: 2, model: "today-model"),
            AIUsageSample(provider: .claude, timestamp: yesterday, inputTokens: 20, outputTokens: 4, model: "older-model"),
        ]
        let history = AIUsageHistory(usageSamples: samples, modelUsageSamples: samples)
        let controller = AIUsageHistoryController(read: { history }, clear: {}, write: { _, _ in })
        await controller.load()
        let host = NSHostingView(rootView: AIUsageHistoryContent(controller: controller)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -100_000, y: -100_000, width: 620, height: 480),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        func settle() async {
            for _ in 0..<6 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
        }
        func values() -> [String] {
            accessibilityObjects(host).compactMap { value($0, "accessibilityValue") as? String }
        }
        func press(_ object: NSObject) throws {
            let selector = NSSelectorFromString("accessibilityPerformPress")
            try #require(object.responds(to: selector))
            _ = object.perform(selector)
        }
        func rangeControl(_ range: SystemMetricsHistoryRange) throws -> NSObject {
            let title = AppLocalization.string(range.titleKey, language: language)
            return try #require(accessibilityObjects(host).first { object in
                ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].contains { key in value(object, key) as? String == title }
            }, "Missing range control \(title)")
        }
        await settle()
        try press(rangeControl(.day))
        await settle()
        let objects = accessibilityObjects(host)
        #expect(!objects.contains { object in AppLanguage.allCases.contains {
            value(object, "accessibilityLabel") as? String == AppLocalization.string("AI token 用量热力图", language: $0)
        } })
        #expect(!objects.contains { object in AppLanguage.allCases.contains {
            value(object, "accessibilityLabel") as? String == AppLocalization.string("Token 消耗趋势", language: $0)
        } })
        #expect(!values().contains { $0.contains("today-model") || $0.contains("older-model") })
        let dateButton = try #require(objects.first {
            value($0, "accessibilityLabel") as? String == AppLocalization.string("日期", language: language)
                && value($0, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue
        })
        try press(dateButton)
        await settle()
        if empty {
            #expect(values().contains(AppLocalization.string("暂无模型用量", language: language)))
        } else {
            #expect(values().contains("today-model"))
        }
        #expect(!values().contains("older-model"))
        #expect(controller.history == history)
        #expect(!window.isVisible)
    }

    /// Refreshing across midnight must clear an out-of-domain date without implicitly selecting the new today.
    @Test @MainActor
    func daySelectionExpiresWhenRefreshAdvancesTheCalendarDomain() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let today = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        var now = today.addingTimeInterval(23 * 3600)
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: today))
        var samples = [AIUsageSample(provider: .codex, timestamp: today, inputTokens: 10, outputTokens: 2, model: "before-midnight")]
        let controller = AIUsageHistoryController(read: { .init(usageSamples: samples, modelUsageSamples: samples) }, clear: {}, write: { _, _ in })
        await controller.load()
        let host = NSHostingView(rootView: AIUsageHistoryContent(controller: controller, now: { now })
            .environment(\.locale, AppLanguage.english.locale))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -100_000, y: -100_000, width: 620, height: 480),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        func settle() async {
            for _ in 0..<6 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
        }
        func press(label: String) throws {
            let control = try #require(accessibilityObjects(host).first { value($0, "accessibilityLabel") as? String == label })
            let selector = NSSelectorFromString("accessibilityPerformPress")
            try #require(control.responds(to: selector))
            _ = control.perform(selector)
        }
        func contains(_ text: String) -> Bool {
            accessibilityObjects(host).contains { value($0, "accessibilityValue") as? String == text }
        }
        await settle()
        try press(label: AppLocalization.string(SystemMetricsHistoryRange.day.titleKey, language: .english))
        await settle()
        try press(label: "Date")
        await settle()
        #expect(contains("before-midnight"))
        now = tomorrow.addingTimeInterval(3600)
        samples.append(AIUsageSample(provider: .claude, timestamp: tomorrow, inputTokens: 20, outputTokens: 4, model: "after-midnight"))
        await controller.load()
        await settle()
        #expect(!contains("before-midnight") && !contains("after-midnight"), "Domain changes must clear the old selection")
        try press(label: "Date")
        await settle()
        #expect(contains("after-midnight") && !contains("before-midnight"))
        #expect(!window.isVisible)
    }

    /// Runtime labels and search anchors must resolve in every supported language, including formats used on error paths.
    @Test
    func allHistoryControlsHaveRuntimeTranslationsAndSearchableAnchors() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let keys = ["AI 用量历史", "把全部 AI 用量历史导出为 xlsx 表格", "已清空 AI 用量历史", "清空失败：%@",
            "清空 AI 用量历史？", "删除本机保存的 AI 用量历史，保留任务和日志去重记录。此操作无法撤销。",
            "上一年", "下一年", "AI token 用量热力图", "查看历史记录", "导出", "清空", "取消", "重试", "刷新",
            "时间范围", "正在读取历史记录", "已保存到 %@", "导出失败：%@", "Token 消耗趋势", "日期"]
            + SystemMetricsHistoryRange.allCases.map(\.titleKey)
        for language in AppLanguage.allCases {
            let table = try #require(NSDictionary(contentsOf: package.appendingPathComponent(
                "Resources/Localization/\(language.rawValue).lproj/Localizable.strings")) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "Missing \(key) in \(language.rawValue)")
                #expect(!value.isEmpty && AppLocalization.string(key, language: language) == value)
                #expect(value.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count)
            }
            let query = AppLocalization.string("AI 用量历史", language: language)
            #expect(SettingsSearchIndex.results(for: query, settings: .default, locale: language.locale).contains {
                $0.section == .ai && $0.anchor == .group("AI 用量历史")
            })
        }
        let settings = try String(contentsOf: package.appendingPathComponent("Sources/Zisla/SettingsView.swift"), encoding: .utf8)
        let history = try #require(settings.range(of: "settingsGroup(\"AI 用量历史\")"))
        let cli = try #require(settings.range(of: "settingsGroup(\"CLI 与 Skills\")"))
        #expect(history.lowerBound < cli.lowerBound)
        let source = try String(contentsOf: package.appendingPathComponent("Sources/Zisla/AIUsageHistoryView.swift"), encoding: .utf8)
        let settingsStart = try #require(source.range(of: "struct AIUsageHistorySettingsActions"))
        let contentStart = try #require(source.range(of: "struct AIUsageHistoryContent"))
        let settingsSource = String(source[settingsStart.lowerBound..<contentStart.lowerBound])
        #expect(settingsSource.contains(".task { await controller.load() }"),
            "Settings reentry must refresh an old empty snapshot before export and clear controls are disabled")
    }

    @MainActor
    private func value(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }

    @MainActor
    private func accessibilityObjects(_ object: NSObject) -> [NSObject] {
        [object] + (value(object, "accessibilityChildren") as? [NSObject] ?? []).flatMap(accessibilityObjects)
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    @MainActor
    private final class OrderingAIHistoryPanel: SystemMetricsHistoryPanel {
        var frontRequestCount = 0
        var requestedKey = false
        var reportsVisible = false
        var reportsMiniaturized = false
        override var isVisible: Bool { reportsVisible }
        override var isMiniaturized: Bool { reportsMiniaturized }
        override func makeKeyAndOrderFront(_ sender: Any?) { requestedKey = true; frontRequestCount += 1 }
        override func orderFront(_ sender: Any?) { frontRequestCount += 1 }
        override func orderOut(_ sender: Any?) { reportsVisible = false }
    }
}
