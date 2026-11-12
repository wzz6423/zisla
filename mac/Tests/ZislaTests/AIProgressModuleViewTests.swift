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

    /// Native geometry keeps the full usage content in the outer document while tasks retain independent scrolling.
    @Test(arguments: [(CGFloat(560), 12, true), (CGFloat(752), 12, true), (CGFloat(980), 12, true),
        (CGFloat(752), 96, true), (CGFloat(752), 1, false),
        (CGFloat(752), 12, false), (CGFloat(752), 0, false)],
        [AppLanguage.simplifiedChinese, .english, .arabic])
    @MainActor
    func upperSectionUsesTheFullUsageHeightWithOuterScrolling(
        scenario: (width: CGFloat, taskCount: Int, hasUsage: Bool), language: AppLanguage
    ) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
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
        let host = NSHostingView(rootView: AIProgressModuleView(monitor: monitor,
            displayedBalanceProviders: [], monitoredBalanceProviders: [], language: language)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 160),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        func settle() async {
            for _ in 0..<8 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }
        await settle()
        let allScrolls = descendants(in: host).compactMap { $0 as? NSScrollView }
        let outer = try #require(allScrolls.max { $0.frame.width < $1.frame.width })
        let scrolls = allScrolls.filter { $0 !== outer }
        try #require(scrolls.count == (taskCount > 0 ? 1 : 0),
            "Only the task list may scroll inside the upper section; usage belongs to the outer document")
        #expect(scrolls.allSatisfy { $0.documentView is NSTableView })
        let document = try #require(outer.documentView)
        func frame(_ title: String, role: NSAccessibility.Role? = nil) throws -> CGRect {
            let object = try #require(accessibilityObjects(host).first { object in
                (role == nil || value(object, "accessibilityRole") as? String == role?.rawValue)
                    && ["accessibilityLabel", "accessibilityValue"].contains {
                        value(object, $0) as? String == AppLocalization.string(title, language: language)
                    }
            }, "The complete upper section must expose \(title)")
            let element = try #require(object as? any NSAccessibilityElementProtocol)
            return document.convert(window.convertFromScreen(element.accessibilityFrame()), from: nil)
        }
        let title = try frame("Token 消耗趋势", role: .staticText)
        let taskTitle = try frame("运行任务", role: .staticText)
        let heatmap = try frame("AI token 用量热力图")
        let availableColumnWidth = document.bounds.width - 24
        #expect(heatmap.width > availableColumnWidth * 0.5
            && heatmap.width < availableColumnWidth * 0.53,
            "The full usage panel must remain slightly wider than the task list")
        #expect(title.minY >= -0.5 && abs(title.minY - taskTitle.minY) < 2,
            "Both column headers must start at the top of the document")
        #expect(language.isRightToLeft ? heatmap.midX < taskTitle.midX : heatmap.midX > taskTitle.midX,
            "The usage panel must follow the task column in the language's reading direction")
        #expect(heatmap.maxY > 160,
            "The fixture must require scrolling the outer module to reach the whole heatmap")
        #expect(abs(document.bounds.maxY - heatmap.maxY) < 1,
            "The full usage content must determine upper height without fixed blank space or clipping")
        #expect(heatmap.minX >= -0.5 && heatmap.maxX <= document.bounds.maxX + 0.5,
            "The heatmap must fit horizontally in both layout directions")
        #expect(outer.hasVerticalScroller && outer.frame.height <= 160.5)
        #expect(outer.horizontalScrollElasticity == .none)
        #expect(!accessibilityObjects(host).contains {
            value($0, "accessibilityValue") as? String == AppLocalization.string("每日模型用量", language: language)
        }, "The island must keep model details hidden before the user selects a date")

        if let tasks = scrolls.first {
            let table = try #require(tasks.documentView as? NSTableView)
            #expect(table.numberOfRows == taskCount)
            let taskFrame = document.convert(tasks.bounds, from: tasks)
            let gap = language.isRightToLeft ? taskFrame.minX - heatmap.maxX : heatmap.minX - taskFrame.maxX
            #expect(gap >= 24 && gap <= 25.5,
                "The columns must keep two twelve-point gaps around their thin divider")
            #expect(abs(taskFrame.maxY - heatmap.maxY) < 1,
                "The task viewport must end at the full usage content height")
            if taskCount >= 12 {
                try #require(table.frame.height > tasks.contentView.bounds.height)
                tasks.contentView.scroll(to: CGPoint(x: 0,
                    y: (table.frame.height - tasks.contentView.bounds.height) / 2))
                tasks.reflectScrolledClipView(tasks.contentView)
                await settle()
                let offset = tasks.contentView.bounds.minY
                let outerOffset = outer.contentView.bounds.minY
                tasks.contentView.scroll(to: CGPoint(x: 0, y: offset + 54))
                tasks.reflectScrolledClipView(tasks.contentView)
                await settle()
                #expect(abs(tasks.contentView.bounds.minY - offset) > 0.5,
                    "The native task viewport must scroll independently through its complete document")
                #expect(outer.contentView.bounds.minY == outerOffset,
                    "Scrolling tasks must preserve the outer module position")
                #expect(try frame("AI token 用量热力图") == heatmap,
                    "Task scrolling must not move or resize the usage content")
            }
        }

        outer.contentView.scroll(to: CGPoint(x: 0, y: 54))
        outer.reflectScrolledClipView(outer.contentView)
        await settle()
        #expect(outer.contentView.bounds.minY > 0,
            "Usage content must scroll through the native outer module")
        outer.contentView.scroll(to: CGPoint(x: 0, y: document.frame.height - outer.contentView.bounds.height))
        outer.reflectScrolledClipView(outer.contentView)
        await settle()
        #expect(try frame("AI token 用量热力图").maxY <= outer.contentView.bounds.maxY + 0.5,
            "Outer scrolling must reveal the heatmap bottom")
        let scroller = try #require(outer.verticalScroller)
        let track = window.convertToScreen(scroller.convert(scroller.bounds, to: nil))
        let viewport = window.convertToScreen(outer.contentView.convert(outer.contentView.bounds, to: nil))
        let visibleUsageFrames = accessibilityObjects(host).compactMap { object -> CGRect? in
            let role = value(object, "accessibilityRole") as? String
            guard role == NSAccessibility.Role.staticText.rawValue || role == NSAccessibility.Role.button.rawValue,
                  let element = object as? any NSAccessibilityElementProtocol else { return nil }
            let frame = element.accessibilityFrame()
            let localFrame = document.convert(window.convertFromScreen(frame), from: nil)
            return frame.intersects(viewport) && localFrame.midX >= heatmap.minX
                && localFrame.midX <= heatmap.maxX ? frame : nil
        }
        try #require(!visibleUsageFrames.isEmpty)
        #expect(visibleUsageFrames.allSatisfy { !$0.intersects(track) },
            "The outer scrollbar must not cover heatmap cells, dates, or visible usage values")
        var shiftedBounds = outer.contentView.bounds
        shiftedBounds.origin.x += 80
        #expect(abs(outer.contentView.constrainBoundsRect(shiftedBounds).minX
            - outer.contentView.bounds.minX) < 0.5,
            "Horizontal trackpad movement must not move the AI module")

        window.setContentSize(NSSize(width: width, height: 500))
        await settle()
        let tallerHeatmap = try frame("AI token 用量热力图")
        #expect(abs(tallerHeatmap.maxY - heatmap.maxY) < 1,
            "Changing the outer viewport height must not add fixed space to the upper section")
        if let tasks = scrolls.first {
            #expect(abs(document.convert(tasks.bounds, from: tasks).maxY - tallerHeatmap.maxY) < 1,
                "More available outer space must not expand the task viewport beyond the usage content")
        }

        outer.scrollerStyle = .legacy
        window.setContentSize(NSSize(width: width, height: 160))
        await settle()
        let resizedHeatmap = try frame("AI token 用量热力图")
        #expect(document.frame.width <= outer.contentView.bounds.width + 0.5,
            "Native scrollbar policy must not create horizontal overflow")
        #expect(resizedHeatmap.minX >= -0.5 && resizedHeatmap.maxX <= document.bounds.maxX + 0.5)
        if let tasks = scrolls.first {
            #expect(abs(document.convert(tasks.bounds, from: tasks).maxY - resizedHeatmap.maxY) < 1)
        }
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

    @MainActor
    private func value(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }

    @MainActor
    private func accessibilityObjects(_ object: NSObject) -> [NSObject] {
        [object] + (value(object, "accessibilityChildren") as? [NSObject] ?? []).flatMap(accessibilityObjects)
    }
}
