import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite(.serialized)
struct AIProgressModuleViewTests {
    @Test(arguments: [(CGFloat(280), 23), (CGFloat(378), 23), (CGFloat(378), 22),
        (CGFloat(378), 0), (CGFloat(378), 12)],
        AppLanguage.allCases)
    @MainActor
    func heatmapMonthLabelsRemainFullyVisibleAtTheGridEdges(
        scenario: (width: CGFloat, weekIndex: Int), language: AppLanguage
    ) throws {
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        var weeks = Array(repeating: Array<ContributionDay?>(repeating: nil, count: 7), count: 24)
        weeks[scenario.weekIndex][0] = ContributionDay(date: date, tokens: 0)
        let direction: LayoutDirection = language.isRightToLeft ? .rightToLeft : .leftToRight
        let heatmap = ImageRenderer(content: UsageHeatmap(weeks: weeks)
            .frame(width: scenario.width)
            .clipped()
            .background(.black)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, direction))
        heatmap.scale = 2
        let rendered = NSBitmapImageRep(cgImage: try #require(heatmap.cgImage))
        let label = ImageRenderer(content: Text(AppLocalization.text("%ld月", 11))
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary.opacity(0.75))
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: scenario.width, height: 13, alignment: .topLeading)
            .background(.black)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, direction))
        label.scale = 2
        let reference = NSBitmapImageRep(cgImage: try #require(label.cgImage))
        let labelTop = (scenario.width * 7 / 24 + 3) * heatmap.scale
        let visible = textMetrics(in: rendered,
            rows: Int(floor(labelTop))..<Int(ceil(labelTop + 13 * heatmap.scale)))
        let full = textMetrics(in: reference, rows: 0..<reference.pixelsHigh)
        try #require(full.weight > 0, "The reference must contain the complete month label")
        #expect(visible.weight >= full.weight * 0.95,
            "\(language.rawValue) month label in week \(scenario.weekIndex) must remain fully inside the grid")
        if scenario.weekIndex == 0 || scenario.weekIndex == 12 {
            let offset = Double(CGFloat(scenario.weekIndex) * (scenario.width + 1.5) / 24 * heatmap.scale)
            let expectedCenter = full.horizontalMoment / full.weight
                + (direction == .rightToLeft ? -offset : offset)
            #expect(abs(visible.horizontalMoment / visible.weight - expectedCenter) < 2,
                "Month labels with enough space must stay aligned with their week")
        }
    }

    /// Native scroll geometry proves bounded upper columns and outer access to quota without mutating state or showing a window.
    @Test(arguments: [(CGFloat(560), 12, true), (CGFloat(752), 12, true), (CGFloat(980), 12, true),
        (CGFloat(752), 12, false), (CGFloat(752), 0, false)],
        [AppLanguage.simplifiedChinese, .english, .arabic])
    @MainActor
    func usageSummaryKeepsNearEqualColumnsWithoutHorizontalScrolling(
        scenario: (width: CGFloat, taskCount: Int, hasUsage: Bool), language: AppLanguage
    ) async throws {
        let (width, taskCount, hasUsage) = scenario
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-layout-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let repository = AIStateRepository(directoryURL: directory)
        for index in 0..<taskCount {
            try repository.upsert(AIProgressTask(id: "layout-\(index)", provider: .gpt,
                title: "ChatGPT layout fixture \(index)", detail: "gpt-6.1-sol · max",
                progress: 0.5, status: .running, updatedAt: now))
        }
        if hasUsage {
            let samples = (0..<7).map { index in
                AIUsageSample(provider: .gpt, timestamp: now.addingTimeInterval(-Double(index) * 86_400),
                    inputTokens: (index + 1) * 1_000_000, outputTokens: 50_000)
            }
            try repository.recordUsage(samples)
        }
        let monitor = AIStateMonitor(directoryURL: directory, activityDetectors: [], now: { now })
        defer { monitor.stop() }
        monitor.reload()
        let initialState = monitor.state
        let host = NSHostingView(rootView: AIProgressModuleView(monitor: monitor)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 160),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        let allScrolls = descendants(in: host).compactMap { $0 as? NSScrollView }
        let outer = try #require(allScrolls.max { $0.frame.width < $1.frame.width })
        let scrolls = allScrolls.filter { $0 !== outer }.sorted {
            host.convert($0.bounds, from: $0).minX < host.convert($1.bounds, from: $1).minX
        }
        try #require(scrolls.count == (taskCount > 0 ? 2 : 1),
            "The usage scroll view must remain available when the task list is empty")
        #expect(outer.hasVerticalScroller && outer.frame.height <= 160.5,
            "The whole module must scroll to the balance section below both bounded columns")
        let summary = scrolls[taskCount == 0 || language.isRightToLeft ? 0 : 1]
        summary.scrollerStyle = .legacy
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        let availableColumnWidth = width - 24
        #expect(summary.frame.width > availableColumnWidth * 0.5,
            "The usage panel must be slightly wider than the task list")
        #expect(summary.frame.width < availableColumnWidth * 0.53,
            "The usage panel must keep the columns close to an equal split")
        if taskCount > 0 {
            let tasks = scrolls[language.isRightToLeft ? 1 : 0]
            #expect(tasks.hasVerticalScroller)
        }
        let document = try #require(summary.documentView)
        #expect(document.frame.width <= summary.contentView.bounds.width + 0.5,
            "Usage content must fit the viewport without horizontal scrolling")
        var shiftedBounds = summary.contentView.bounds
        shiftedBounds.origin.x += 80
        #expect(abs(summary.contentView.constrainBoundsRect(shiftedBounds).minX
            - summary.contentView.bounds.minX) < 0.5,
            "Horizontal scrolling must not move the usage panel")
        #expect(document.frame.height > summary.contentView.bounds.height,
            "The fixture must still exercise vertical overflow")
        #expect(summary.hasVerticalScroller)
        #expect(summary.frame.height <= AIProgressModuleView.upperSectionHeight(availableHeight: 160) + 0.5,
            "Long model history must scroll inside the upper right column")
        #expect(summary.horizontalScrollElasticity == .none,
            "Horizontal trackpad movement must not rubber-band the usage panel")
        #expect(monitor.state == initialState, "Laying out the panel must not alter AI state")
        #expect(!window.isVisible, "Layout tests must not show a window")
    }

    @Test
    @MainActor
    func tokenTrendDatesAlignWithFirstAndLastDataPoints() throws {
        let calendar = Calendar.current
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 19)))
        let values = [200, 0, 0, 0, 150, 485, 35]
        let series = try values.enumerated().map { index, value in
            let day = try #require(calendar.date(byAdding: .day, value: index, to: start))
            let midpoint = try #require(calendar.date(byAdding: .hour, value: 12, to: day))
            return UsageBreakdownPoint(timestamp: midpoint, inputTokens: value * 1_000_000, outputTokens: 0)
        }
        let renderer = ImageRenderer(content: UsageTrendChart(series: series)
            .frame(width: 408, height: 128)
            .background(.black)
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let lineColumns = (0..<bitmap.pixelsWide).filter { x in
            (20..<(bitmap.pixelsHigh - 26)).contains { y in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                return color.blueComponent > 0.55
                    && color.blueComponent > color.redComponent + 0.25
                    && color.blueComponent > color.greenComponent + 0.07
            }
        }
        let firstLineX = try #require(lineColumns.first)
        let lastLineX = try #require(lineColumns.last)

        func labelCenter(near lineX: Int) throws -> Double {
            let lowerBound = max(0, lineX - 60)
            let upperBound = min(bitmap.pixelsWide, lineX + 61)
            let columns = (lowerBound..<upperBound).filter { x in
                ((bitmap.pixelsHigh - 24)..<bitmap.pixelsHigh).contains { y in
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                    return color.redComponent > 0.18
                        && abs(color.redComponent - color.greenComponent) < 0.08
                        && abs(color.greenComponent - color.blueComponent) < 0.08
                }
            }
            let first = try #require(columns.first)
            let last = try #require(columns.last)
            return Double(first + last) / 2
        }

        let firstLabelX = try labelCenter(near: firstLineX)
        let lastLabelX = try labelCenter(near: lastLineX)
        #expect(abs(firstLabelX - Double(firstLineX)) < 10, "First date is not centered on its data point")
        #expect(abs(lastLabelX - Double(lastLineX)) < 10, "Last date is not centered on its data point")
    }

    @MainActor
    private func textMetrics(in bitmap: NSBitmapImageRep, rows: Range<Int>) -> (weight: Double, horizontalMoment: Double) {
        var weight = 0.0
        var horizontalMoment = 0.0
        for y in rows {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    weight += Double(color.redComponent)
                    horizontalMoment += Double(x) * Double(color.redComponent)
                }
            }
        }
        return (weight, horizontalMoment)
    }

    @MainActor
    private func descendants(in view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }
}
