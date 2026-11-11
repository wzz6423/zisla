import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite(.serialized)
struct AIUsageHistoryPresentationTests {
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
        var selected = day.addingTimeInterval(-86400)
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
        let detail = AIUsageHistoryPresentation.selectedDay(in: .init(), date: selected)
        #expect(detail.date == day && detail.models.isEmpty && detail.totalTokens == 0)
    }

    /// The assembled window must leave calendar cells visible at its minimum size and keep the default selection on today.
    @Test(arguments: [CGSize(width: 620, height: 480), CGSize(width: 760, height: 640)],
        [LayoutDirection.leftToRight, .rightToLeft])
    @MainActor
    func historyWindowFitsAndRefreshKeepsTheSelectedDate(size: CGSize, direction: LayoutDirection) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let today = Calendar.current.startOfDay(for: Date())
        let older = try #require(Calendar.current.date(byAdding: .day, value: -1, to: today))
        var samples = [AIUsageSample(provider: .codex, timestamp: today, inputTokens: 10, outputTokens: 2, model: "today-model"),
            AIUsageSample(provider: .claude, timestamp: older, inputTokens: 20, outputTokens: 4, model: "older-model")]
        let controller = AIUsageHistoryController(read: { .init(usageSamples: samples, modelUsageSamples: samples) }, clear: {}, write: { _, _ in })
        await controller.load()
        let host = NSHostingView(rootView: AIUsageHistoryContent(controller: controller).environment(\.layoutDirection, direction))
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
        let scroll = try #require(descendants(host).compactMap { $0 as? NSScrollView }.max(by: { $0.frame.height < $1.frame.height }))
        let document = try #require(scroll.documentView)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle()
        func displayedValues() -> [String] {
            accessibilityObjects(host).compactMap { value($0, "accessibilityValue") as? String }
        }
        #expect(displayedValues().contains { $0.contains("today-model") })
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
        #expect(!window.isVisible && window.level == .normal)
    }

    /// Runtime labels and search anchors must resolve in every supported language, including formats used on error paths.
    @Test
    func allHistoryControlsHaveRuntimeTranslationsAndSearchableAnchors() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let keys = ["AI 用量历史", "把全部 AI 用量历史导出为 xlsx 表格", "已清空 AI 用量历史", "清空失败：%@",
            "清空 AI 用量历史？", "删除本机保存的 AI 用量历史，保留任务和日志去重记录。此操作无法撤销。",
            "上一年", "下一年", "AI token 用量热力图", "查看历史记录", "导出", "清空", "取消", "重试", "刷新",
            "时间范围", "正在读取历史记录", "已保存到 %@", "导出失败：%@", "Token 消耗趋势"]
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
}
