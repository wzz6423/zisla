import AppKit
import Foundation
import SwiftUI
import Testing
import Vision
import ZislaCore
@testable import Zisla
@testable import ZislaKit

@MainActor
struct WeatherFallbackPresentationTests {
    @Test
    func fallbackRowShowsAttributionAndDoesNotPresentUnknownMetricsAsZero() throws {
        let fallback = WeatherSnapshot(
            temperature: 16,
            condition: WeatherCondition(code: 3, isDay: true),
            timezone: "UTC",
            fetchedAt: Date(timeIntervalSince1970: 0),
            coordinate: GeoCoordinate(latitude: 51, longitude: 0),
            locationName: "London",
            source: "MET Norway",
            sourceURL: URL(string: "https://www.met.no/"),
            licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")
        )
        let missing = try recognizedText(in: fallback)
        #expect(missing.contains("MET Norway"))
        #expect(missing.contains("CC BY 4.0"))
        #expect(!missing.contains("mm"))
        #expect(!missing.contains("%"))
        #expect(!missing.contains("32"))
        #expect(!missing.contains("0°"))

        var complete = fallback
        complete.apparentTemperature = 32
        complete.currentPrecipitation = 4
        complete.precipitationProbability = 82
        complete.precipitationSum = 18.5
        complete.sunrise = "2026-11-05T06:00"
        complete.sunset = "2026-11-05T18:30"
        let metrics = try recognizedText(in: complete)
        #expect(metrics.contains("32"))
        #expect(metrics.contains("82"))
        #expect(metrics.contains("18.5"))
        #expect(metrics.contains("mm"))
        #expect(metrics.contains("06:00"))
        #expect(metrics.contains("18:30"))
    }

    @Test(arguments: AppLanguage.allCases)
    func attributionUsesExistingTranslatedSourceCopy(language: AppLanguage) throws {
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let table = try #require(NSDictionary(contentsOf: packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )) as? [String: String])
        let key = "中国天气网（中国气象局）"
        let value = try #require(table[key])
        #expect(!value.isEmpty)
        #expect(AppLocalization.string(key, locale: language.locale) == value)
    }

    private func recognizedText(in weather: WeatherSnapshot) throws -> String {
        let hosting = NSHostingView(rootView: AgendaModuleView.weatherRow(weather)
            .frame(width: 300)
            .padding(12)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .scaleEffect(4, anchor: .topLeading)
            .frame(width: 1296, height: 600, alignment: .topLeading))
        let window = NSPanel(
            contentRect: NSRect(x: -100_000, y: -100_000, width: 1296, height: 600),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer {
            window.contentView = nil
            window.close()
        }
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) })
        // Native link labels require AppKit hosting; ImageRenderer omits native controls.
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let cgImage = try #require(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
}
