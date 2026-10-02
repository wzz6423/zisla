import AppKit
import SwiftUI
import Testing
import ZislaKit

@testable import Zisla

@Suite(.serialized)
struct BatteryTrendWaveformTests {
    @Test(arguments: [430, 560], [nil, 600] as [CGFloat?]) @MainActor
    func trendCardsAlignWithMetricsWithoutStretchingTheirContent(width: Int, proposedHeight: CGFloat?) throws {
        let suiteName = "Zisla.BatteryTrendWaveformTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let view = BatteryDetailView(
            batteryMonitor: BatteryMonitor(defaults: defaults),
            networkMonitor: NetworkBatteryMonitor()
        )
        let battery = BatterySnapshot(
            level: 1, isCharging: false, isPluggedIn: false, isCharged: true,
            timeRemainingMinutes: nil, adapterRatedWatts: 85
        )
        let renderer = ImageRenderer(content: view.localBatterySection(battery)
            .frame(width: CGFloat(width), height: proposedHeight, alignment: .top)
            .background(.black)
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let leftX = width - 262
        let rightX = (width - 125) * 2
        let leftBottom = try #require((0..<bitmap.pixelsHigh).last {
            (bitmap.colorAt(x: leftX, y: $0)?.usingColorSpace(.deviceRGB)?.redComponent ?? 0) > 0.02
        })
        let rightBottom = try #require((0..<bitmap.pixelsHigh).last {
            (bitmap.colorAt(x: rightX, y: $0)?.usingColorSpace(.deviceRGB)?.redComponent ?? 0) > 0.02
        })
        let lastMetricTextBottom = try #require((0...rightBottom).last { y in
            ((width - 250) * 2 + 16..<bitmap.pixelsWide - 16).contains { x in
                (bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.redComponent ?? 0) > 0.4
            }
        })

        #expect(abs(leftBottom - rightBottom) <= 1,
                "The two trend cards and metrics must share their bottom edge")
        #expect(rightBottom - lastMetricTextBottom <= 24,
                "The metrics must retain their natural bottom padding")
    }

    @Test(arguments: [0.0, 0.5, 1.0], [80, 240]) @MainActor
    func constantReadingsKeepAHorizontalMeasuredEdge(level: Double, width: Int) throws {
        let bitmap = try renderChart(samples: Array(repeating: level, count: 6), width: width)
        let pixels = linePixels(in: bitmap).filter {
            (bitmap.colorAt(x: $0.x, y: $0.y)?.usingColorSpace(.deviceRGB)?.greenComponent ?? 0) > 0.8
        }
        let firstY = try #require(pixels.map(\.y).min())
        let lastY = try #require(pixels.map(\.y).max())

        #expect(Set(pixels.map(\.x)).count > bitmap.pixelsWide - 40)
        #expect(lastY - firstY <= 3, "A constant reading must not acquire artificial peaks")
        let expectedY = min(Double(bitmap.pixelsHigh - 1), max(0, (1 - level) * Double(bitmap.pixelsHigh) - 0.5))
        #expect(abs(Double(firstY + lastY) / 2 - expectedY) <= 2)
    }

    @Test @MainActor
    func fullChargeUsesTranslucentFillBelowItsMeasuredEdge() throws {
        let bitmap = try renderChart(samples: [1, 1])
        let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
            .usingColorSpace(.deviceRGB))

        #expect(isLineColor(center), "The battery trend must retain the shared waveform's filled appearance")
        #expect(center.greenComponent < 0.8, "The area must remain translucent beneath the measured edge")
    }

    @Test(arguments: [[0.2, 0.8, 0.4], [0.25, 0.75, 0.75, 0.25], [1, 1]], [80, 240]) @MainActor
    func batteryChartMatchesTheSharedCPUAndGPUWaveform(samples: [Double], width: Int) throws {
        let actual = try renderChart(samples: samples, width: width)
        let reference = try renderWaveform(samples: samples, width: width - 20)
        let actualPixels = Set(linePixels(in: actual))
        let referencePixels = Set(linePixels(in: reference))

        #expect(actual.pixelsWide == reference.pixelsWide && actual.pixelsHigh == reference.pixelsHigh)
        #expect(!actualPixels.isEmpty)
        #expect(actualPixels.symmetricDifference(referencePixels).count <= actual.pixelsWide * 3,
                "The chart must match the shared smooth line and area, allowing only subpixel layout differences")
    }

    @Test(arguments: [[], [0.7]]) @MainActor
    func missingHistoryDoesNotInventAConnectingLine(samples: [Double]) throws {
        let bitmap = try renderChart(samples: samples)
        #expect(linePixels(in: bitmap).isEmpty)
    }

    @Test @MainActor
    func interruptedPowerHistoryWaitsForTwoNewReadings() throws {
        let trend = BatteryTrendPresentation(samples: [
            BatteryTrendSample(date: .distantPast, level: 0.6, systemPowerWatts: 12),
            BatteryTrendSample(date: .distantPast, level: 0.6, systemPowerWatts: nil),
            BatteryTrendSample(date: .distantPast, level: 0.6, systemPowerWatts: 8),
        ])

        #expect(linePixels(in: try renderChart(samples: trend.powerLevels)).isEmpty,
                "A missing power reading must not connect the old and new segments")
    }

    @MainActor
    private func renderWaveform(
        samples: [Double],
        width: Int
    ) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: MultiLineWaveform(
            series: [WaveSeries(samples: samples, color: Color(red: 0, green: 1, blue: 0))], height: 40
        )
        .frame(width: CGFloat(width))
        .background(Color.fillCard)
        .background(.black)
        .environment(\.colorScheme, .dark))
        renderer.scale = 2
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    @MainActor
    private func renderChart(samples: [Double], width: Int = 240) throws -> NSBitmapImageRep {
        let suiteName = "Zisla.BatteryTrendWaveformTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let view = BatteryDetailView(
            batteryMonitor: BatteryMonitor(defaults: defaults),
            networkMonitor: NetworkBatteryMonitor()
        )
        let renderer = ImageRenderer(content: view.trendChart(
            title: "Charge", value: "100%", values: samples, tint: Color(red: 0, green: 1, blue: 0)
        )
        .frame(width: CGFloat(width))
        .background(.black)
        .environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let waveform = try #require(image.cropping(to: CGRect(
            x: 20, y: image.height - 20 - 80, width: image.width - 40, height: 80
        )))
        return NSBitmapImageRep(cgImage: waveform)
    }

    private func linePixels(in bitmap: NSBitmapImageRep) -> [Pixel] {
        (0..<bitmap.pixelsHigh).flatMap { y in
            (0..<bitmap.pixelsWide).compactMap { x in
                isLineColor(bitmap.colorAt(x: x, y: y)) ? Pixel(x: x, y: y) : nil
            }
        }
    }

    private func isLineColor(_ color: NSColor?) -> Bool {
        guard let color = color?.usingColorSpace(.deviceRGB) else { return false }
        return color.greenComponent > color.redComponent + 0.2
            && color.greenComponent > color.blueComponent + 0.2
    }

    private struct Pixel: Hashable {
        let x: Int
        let y: Int
    }
}
