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

}
