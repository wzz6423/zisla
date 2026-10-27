import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite(.serialized) @MainActor
struct SystemMonitorNetworkLayoutTests {
    @Test(arguments: AppLanguage.allCases)
    func longIPv6AddressesKeepEachPublicAddressRowOnOneLine(language: AppLanguage) throws {
        let row = SystemMonitorView.CopyableAddressRow(
            label: "公网", value: "2001:0db8:1234:5678:9abc:def0:1234:5678",
            placeholder: "--", labelSuffix: " IPv6"
        )
        let direction: LayoutDirection = language.isRightToLeft ? .rightToLeft : .leftToRight
        let narrow = try render(row.frame(width: 230)
            .environment(\.locale, language.locale).environment(\.layoutDirection, direction))
        let wide = try render(row.frame(width: 460)
            .environment(\.locale, language.locale).environment(\.layoutDirection, direction))

        #expect(abs(narrow.pixelsHigh - wide.pixelsHigh) <= 1,
                "A full IPv6 address must not turn its public address row into multiple lines in \(language.rawValue)")
    }

    @Test(arguments: [
        NetworkIdentity(publicIPAddress: "203.0.113.8", publicIPv6Address: "2001:db8::8"),
        NetworkIdentity(publicIPAddress: "203.0.113.8"),
        NetworkIdentity(publicIPv6Address: "2001:db8::8"),
        NetworkIdentity(),
    ], [AppLanguage.simplifiedChinese, .english, .arabic])
    func publicAddressesHaveTwoOrderedRowsWithMissingFamilyPlaceholders(
        identity: NetworkIdentity, language: AppLanguage
    ) async throws {
        let service = SystemMonitorService(publicIPProvider: LayoutPublicIPProvider(identity: identity))
        await service.refreshPublicIPAddress()
        let view = SystemMonitorView(service: service, onCleanupRequested: {})
        let direction: LayoutDirection = language.isRightToLeft ? .rightToLeft : .leftToRight
        let actual = try render(view.networkCard.frame(width: 250)
            .environment(\.locale, language.locale).environment(\.layoutDirection, direction))
        let title = AppLocalization.string("公网", locale: language.locale)
        let reference = try render(VStack(alignment: .leading, spacing: 7) {
            SystemMonitorView.CopyableAddressRow(label: title + " IPv4", value: identity.publicIPAddress, placeholder: "--")
            SystemMonitorView.CopyableAddressRow(label: title + " IPv6", value: identity.publicIPv6Address, placeholder: "--")
        }
        .frame(width: 230).background(Color.fillCard)
        .environment(\.locale, language.locale).environment(\.layoutDirection, direction))
        let image = try #require(actual.cgImage?.cropping(to: CGRect(
            x: 20, y: actual.pixelsHigh - 20 - reference.pixelsHigh,
            width: reference.pixelsWide, height: reference.pixelsHigh
        )))
        let rows = NSBitmapImageRep(cgImage: image)
        var differentPixels = 0
        for y in 0..<reference.pixelsHigh {
            for x in 0..<reference.pixelsWide {
                let expected = try #require(reference.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let actual = try #require(rows.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if abs(expected.redComponent - actual.redComponent) > 0.02
                    || abs(expected.greenComponent - actual.greenComponent) > 0.02
                    || abs(expected.blueComponent - actual.blueComponent) > 0.02 {
                    differentPixels += 1
                }
            }
        }
        #expect(differentPixels <= reference.pixelsWide * reference.pixelsHigh / 100,
                "Public IPv4 must precede IPv6, and each unavailable family must display --")
    }

    @Test(arguments: [140, 270])
    func computeCardsAlignWithTheNetworkColumn(width: Int) throws {
        let view = SystemMonitorView(service: SystemMonitorService(), onCleanupRequested: {})
        let right = try render(view.systemColumn.frame(width: 250))
        let left = try render(view.computeColumn.frame(
            width: CGFloat(width), height: CGFloat(right.pixelsHigh) / 2, alignment: .top
        ))
        let cards = bands(in: left, x: 12) { $0.redComponent > 0.02 }
        #expect(cards.count == 2)
        let first = try #require(cards.first)
        let last = try #require(cards.last)
        #expect(abs(first.count - last.count) <= 1,
                "CPU and GPU cards must receive equal heights")
        #expect(abs(last.upperBound - (right.pixelsHigh - 1)) <= 1,
                "The compute and network columns must share their bottom edge")
    }

    @Test(arguments: [140, 270])
    func networkColumnGrowthIsSharedByBothWaveforms(width: Int) throws {
        let view = SystemMonitorView(service: SystemMonitorService(), onCleanupRequested: {})
        let right = try render(view.systemColumn.frame(width: 250))
        let height = CGFloat(right.pixelsHigh) / 2
        let baseline = try render(view.computeColumn.frame(width: CGFloat(width), height: height))
        let expanded = try render(view.computeColumn.frame(width: CGFloat(width), height: height + 24))
        let initialCharts = try waveformBands(in: baseline)
        let expandedCharts = try waveformBands(in: expanded)
        #expect(initialCharts.count == 2)
        #expect(expandedCharts.count == 2)
        for (initial, expanded) in zip(initialCharts, expandedCharts) {
            #expect(abs(expanded.count - initial.count - 24) <= 1,
                    "Each waveform must absorb half of the added column height")
        }
    }

    @Test
    func initialWaveformsKeepTheirMinimumHeightBeforeColumnMeasurement() throws {
        let view = SystemMonitorView(service: SystemMonitorService(), onCleanupRequested: {})
        let bitmap = try render(view.computeColumn.frame(width: 270))
        let charts = try waveformBands(in: bitmap)
        #expect(charts.count == 2)
        for chart in charts {
            #expect(chart.count >= 130, "Initial waveforms must retain their 65.5-point minimum")
        }
    }

    private func waveformBands(in bitmap: NSBitmapImageRep) throws -> [ClosedRange<Int>] {
        let reference = try render(MultiLineWaveform(series: []).frame(width: 80).background(Color.fillCard))
        let color = try #require(reference.colorAt(x: 80, y: 54)?.usingColorSpace(.deviceRGB))
        return bands(in: bitmap, x: bitmap.pixelsWide / 2) {
            abs($0.redComponent - color.redComponent) < 0.002
                && abs($0.greenComponent - color.greenComponent) < 0.002
                && abs($0.blueComponent - color.blueComponent) < 0.002
        }
        .filter { $0.count >= 100 }
    }

    private func bands(
        in bitmap: NSBitmapImageRep,
        x: Int,
        matching predicate: (NSColor) -> Bool
    ) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        var start: Int?
        for y in 0..<bitmap.pixelsHigh {
            let matches = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB).map(predicate) ?? false
            if matches {
                if start == nil { start = y }
            } else if let first = start {
                result.append(first...(y - 1))
                start = nil
            }
        }
        if let start { result.append(start...(bitmap.pixelsHigh - 1)) }
        return result
    }

    private func render<V: View>(_ content: V) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: content.background(.black).environment(\.colorScheme, .dark))
        renderer.scale = 2
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }
}

private struct LayoutPublicIPProvider: PublicIPProviding {
    let identity: NetworkIdentity

    func publicIPAddress() async -> String? { identity.publicIPAddress }
    func publicIPv6Address() async -> String? { identity.publicIPv6Address }
}
