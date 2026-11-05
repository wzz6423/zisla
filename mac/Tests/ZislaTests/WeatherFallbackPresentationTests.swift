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
            fetchedAt: Date(timeIntervalSince1970: 86_400),
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
        #expect(missing.contains("1970"), "Retained forecasts must show the update date, not just the time")

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
        for key in ["中国天气网（中国气象局）", "更新于 %@"] {
            let value = try #require(table[key])
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, locale: language.locale) == value)
        }
    }

    @Test
    func retainedWeatherOmitsExpiredAlertsWithoutChangingStoredData() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-05T10:30:00Z"))
        func alert(_ summary: String, expiresAt: Date?) -> WeatherAlert {
            WeatherAlert(
                severity: .moderate, source: "Weather provider", summary: summary, region: nil,
                detailsURL: URL(string: "https://example.com/\(summary)")!,
                updatedAt: date.addingTimeInterval(-3600), expiresAt: expiresAt
            )
        }
        let snapshot = WeatherSnapshot(
            temperature: 16, condition: WeatherCondition(code: 3, isDay: true),
            officialAlerts: [
                alert("ExpiredWarning", expiresAt: date.addingTimeInterval(-1)),
                alert("BoundaryWarning", expiresAt: date),
                alert("ActiveWarning", expiresAt: date.addingTimeInterval(1)),
                alert("UnknownWarning", expiresAt: nil),
            ],
            timezone: "UTC", fetchedAt: date,
            coordinate: GeoCoordinate(latitude: 51, longitude: 0), locationName: "London"
        )
        var expected = snapshot
        expected.officialAlerts = Array(snapshot.officialAlerts.suffix(2))
        let visible = try renderedPixels(in: snapshot, at: date)
        #expect(try visible == renderedPixels(in: expected, at: date),
                "Expired and boundary alerts must not render while live and unknown-expiry alerts remain")
        expected.officialAlerts = [snapshot.officialAlerts.last!]
        let laterDate = date.addingTimeInterval(2)
        let later = try renderedPixels(in: snapshot, at: laterDate)
        #expect(try later == renderedPixels(in: expected, at: laterDate),
                "Alerts must expire even when no forecast refresh succeeds")
        expected.officialAlerts = []
        #expect(try later != renderedPixels(in: expected, at: laterDate),
                "The provider's unknown-expiry alert must stay visible")
        #expect(snapshot.officialAlerts.count == 4, "Rendering must leave the stored provider response unchanged")
    }

    private func recognizedText(in weather: WeatherSnapshot, at date: Date = Date()) throws -> String {
        let cgImage = try renderedImage(in: weather, at: date)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    private func renderedPixels(in weather: WeatherSnapshot, at date: Date) throws -> Data {
        let image = try renderedImage(in: weather, at: date)
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try #require(context.data), count: image.width * image.height * 4)
    }

    private func renderedImage(in weather: WeatherSnapshot, at date: Date) throws -> CGImage {
        let hosting = NSHostingView(rootView: AgendaModuleView.weatherRow(weather, at: date)
            .frame(width: 300)
            .padding(12)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .scaleEffect(4, anchor: .topLeading)
            .frame(width: 1296, height: 1000, alignment: .topLeading))
        let window = NSPanel(
            contentRect: NSRect(x: -100_000, y: -100_000, width: 1296, height: 1000),
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
        return try #require(bitmap.cgImage)
    }
}
