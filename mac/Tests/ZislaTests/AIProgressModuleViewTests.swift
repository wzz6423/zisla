import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

@Suite(.serialized)
struct AIProgressModuleViewTests {
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

    @Test
    func usageHistoryLoadsWithoutViewOwnedRefreshWork() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Zisla/AIProgressModuleView.swift"),
            encoding: .utf8
        )
        let modelSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Zisla/AppModel.swift"),
            encoding: .utf8
        )

        #expect(!viewSource.contains("TimelineView(.periodic(from: .now, by: 15))"))
        #expect(viewSource.contains("usageSummary(endingAt: .now)"))
        #expect(!viewSource.contains("monitor.refreshActiveTasks()"))
        #expect(!viewSource.contains("monitor.loadUsageHistory()"))
        #expect(!viewSource.contains("await Task.yield()"))
        #expect(viewSource.contains(".frame(height: 128)"))
        #expect(viewSource.contains("weeks: 24"))
        #expect(viewSource.contains("最近二十四周 AI token 用量热力图"))
        #expect(!viewSource.contains("usageTrendChartHeight"))
        #expect(!viewSource.contains("usageHeatmapWeeks"))
        #expect(modelSource.contains("static let ai = compactModule(contentHeight: 350)"))
        #expect(modelSource.contains("static let system = compactModule(contentHeight: 401)"))

        guard let selectedModule = modelSource.range(of: "@Published var selectedModule") else {
            Issue.record("Could not find selectedModule in AppModel")
            return
        }
        let selectedModuleSource = modelSource[selectedModule.lowerBound...]
        guard let aiModuleCase = selectedModuleSource.range(of: "case .aiMonitor:") else {
            Issue.record("Could not find aiMonitor case")
            return
        }
        let aiModuleBlock = selectedModuleSource[aiModuleCase.lowerBound...]
        guard let defaultCase = aiModuleBlock.range(of: "default:") else {
            Issue.record("Could not find default case")
            return
        }
        let aiModuleAction = aiModuleBlock[..<defaultCase.lowerBound]

        #expect(!aiModuleAction.contains("aiMonitor.refreshActiveTasks()"))
        #expect(aiModuleAction.contains("aiMonitor.loadUsageHistory()"))

        guard let expansionRefresh = modelSource.range(of: "func refreshForExpansion()") else {
            Issue.record("Could not find refreshForExpansion in AppModel")
            return
        }
        let expansionSource = modelSource[expansionRefresh.lowerBound...]
        guard let nextFunction = expansionSource.range(of: "func refreshWeather()") else {
            Issue.record("Could not isolate refreshForExpansion in AppModel")
            return
        }
        let expansionBody = expansionSource[..<nextFunction.lowerBound]
        guard let deferredWork = expansionBody.range(of: "Task { @MainActor") else {
            Issue.record("Could not find deferred expansion work")
            return
        }
        let synchronousExpansionWork = expansionBody[..<deferredWork.lowerBound]

        #expect(!synchronousExpansionWork.contains("aiMonitor.refreshActiveTasks()"))
        #expect(expansionBody.contains("try? await Task.sleep(for: .milliseconds(250))"))
        #expect(expansionBody.contains("if settings.aiProgressEnabled, module != .aiMonitor { self.aiMonitor.refresh() }"))
    }
}
