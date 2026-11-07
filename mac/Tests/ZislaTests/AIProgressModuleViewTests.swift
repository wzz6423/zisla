import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite(.serialized)
struct AIProgressModuleViewTests {
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
        let scrolls = descendants(in: host).compactMap { $0 as? NSScrollView }.sorted {
            host.convert($0.bounds, from: $0).minX < host.convert($1.bounds, from: $1).minX
        }
        try #require(scrolls.count == (taskCount > 0 ? 2 : 1),
            "The usage scroll view must remain available when the task list is empty")
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
    private func descendants(in view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }
}
