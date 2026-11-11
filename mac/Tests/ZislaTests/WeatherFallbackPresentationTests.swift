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
    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic], [
        (1, NSAppearance.Name.aqua), (7, .aqua), (1, .darkAqua), (7, .darkAqua),
    ])
    func weatherListKeepsTemperatureInsideTheViewportWithoutHorizontalScrolling(
        language: AppLanguage, configuration: (locationCount: Int, appearance: NSAppearance.Name)
    ) async throws {
        let locationCount = configuration.locationCount
        let isDark = configuration.appearance == .darkAqua
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("weather-layout-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "weather-layout-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let locations = WeatherLocationStore(storageURL: directory.appendingPathComponent("locations.json"), defaults: defaults)
        let date = Date(timeIntervalSince1970: 86_400)
        let name: String
        switch language {
        case .arabic: name = "مدينة ذات اسم طويل لاختبار الطقس"
        case .english: name = "A city with a long weather location name"
        default: name = "陕西省西安市"
        }
        locations.updateCurrent(name: name, coordinate: GeoCoordinate(latitude: 36, longitude: 104))
        for index in 1..<locationCount {
            locations.addSaved(name: "\(name) \(index)", coordinate: GeoCoordinate(latitude: Double(index), longitude: 100))
        }
        let snapshots = Dictionary(uniqueKeysWithValues: locations.locations.map { location in
            (location.id, WeatherSnapshot(
                temperature: -12, temperatureMin: -18, temperatureMax: -1,
                condition: WeatherCondition(code: 0, isDay: true), timezone: "UTC", fetchedAt: date,
                coordinate: location.coordinate!, locationName: location.displayName,
                source: AppLocalization.string("中国天气网（中国气象局）", language: language),
                sourceURL: URL(string: "https://example.com/weather")
            ))
        })
        let persisted = try Data(contentsOf: directory.appendingPathComponent("locations.json"))
        func content(_ snapshots: [String: WeatherSnapshot]) -> some View {
            AgendaModuleView.weatherContent(
                locations: locations, snapshotsByLocationID: snapshots, state: .ready("\(locationCount)"), at: date
            ).background(isDark ? Color.black : Color.white)
                .environment(\.colorScheme, isDark ? .dark : .light)
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        }
        let host = NSHostingView(rootView: content(snapshots))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 184, height: 124),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: configuration.appearance)
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        func descendants(in view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(in: $0) }
        }
        func expectVisibleScrollbar(in scroll: NSScrollView) throws {
            let bar = try #require(scroll.verticalScroller)
            let track = bar.convert(bar.bounds, to: host)
            #expect(scroll.scrollerStyle == .legacy && !bar.isHidden,
                    "Overflowing weather must keep its scrollbar visible without waiting for an interaction")
            #expect(abs(track.maxX - host.bounds.maxX) < 0.5,
                    "The scrollbar must stay at the weather column's right edge")
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            var knobColumns = Set<Int>()
            for y in 0..<bitmap.pixelsHigh {
                for x in Int(track.minX * scale)..<Int(track.maxX * scale) {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    let contrast = isDark ? color.redComponent : 1 - color.redComponent
                    if contrast * color.alphaComponent > 0.1 { knobColumns.insert(x) }
                }
            }
            #expect(knobColumns.count == Int(3 * scale),
                    "The weather column must actually render a visible 3pt scrollbar")
            let knob = bar.rect(for: .knob)
            let hitPoint = bar.convert(CGPoint(x: knob.midX, y: knob.midY), to: nil)
            #expect(bar.testPart(hitPoint) == .knob, "The visible weather scrollbar must accept dragging")
        }
        let scroll = try #require(descendants(in: host).compactMap { $0 as? NSScrollView }.first)
        scroll.tile()
        scroll.reflectScrolledClipView(scroll.contentView)
        let document = try #require(scroll.documentView)
        let sourceLink = try #require(descendants(in: document).compactMap { $0 as? NSButton }.first)
        let sourceFrame = sourceLink.convert(sourceLink.bounds, to: document)
        #expect(language.isRightToLeft
            ? abs(sourceFrame.maxX - document.bounds.maxX + 2) < 0.5
            : abs(sourceFrame.minX - document.bounds.minX) < 0.5,
                "Weather attribution must retain the enclosing layout direction in \(language.rawValue): \(sourceFrame)")
        #expect(document.frame.width <= scroll.contentView.bounds.width,
                "Weather rows must fit the viewport, including the vertical scrollbar")
        var shiftedBounds = scroll.contentView.bounds
        shiftedBounds.origin.x += 24
        #expect(abs(scroll.contentView.constrainBoundsRect(shiftedBounds).minX
            - scroll.contentView.bounds.minX) < 0.5,
                "A horizontal scroll gesture must not move weather or clip the temperature")
        #expect(scroll.horizontalScrollElasticity == .none,
                "Horizontal trackpad movement must not rubber-band the weather list")
        if locationCount > 1 {
            let scroller = try #require(scroll.verticalScroller)
            #expect(scroller.knobProportion > 0 && scroller.knobProportion < 1,
                    "Overflowing weather must retain a usable vertical scrollbar")
            let track = scroller.convert(scroller.bounds, to: host)
            try expectVisibleScrollbar(in: scroll)
            let wasHidden = scroller.isHidden
            scroller.isHidden = true
            defer { scroller.isHidden = wasHidden }
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            let gutter = track.insetBy(dx: -2, dy: 0).intersection(host.bounds)
            var overlappingPixels = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in Int(gutter.minX * scale)..<Int(gutter.maxX * scale) {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    let contrast = isDark ? color.redComponent : 1 - color.redComponent
                    if contrast * color.alphaComponent > 0.1 { overlappingPixels += 1 }
                }
            }
            #expect(overlappingPixels == 0,
                    "Weather text must leave the native scrollbar track and a 2pt gap clear in \(language.rawValue)")
            scroll.contentView.scroll(to: CGPoint(x: 0, y: document.frame.height - scroll.contentView.bounds.height))
            scroll.reflectScrolledClipView(scroll.contentView)
            #expect(scroll.contentView.bounds.minY > 0, "Additional cities must remain vertically scrollable")
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            for changeTemperature in [true, false] {
                let changed = snapshots.mapValues { snapshot in
                    var snapshot = snapshot
                    if changeTemperature { snapshot.temperature = -34 }
                    else { snapshot.temperatureMin = -38 }
                    return snapshot
                }
                host.rootView = content(changed)
                for _ in 0..<8 {
                    host.layoutSubtreeIfNeeded()
                    await withCheckedContinuation { continuation in
                        DispatchQueue.main.async { continuation.resume() }
                    }
                }
                let updated = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: updated)
                let columns = language.isRightToLeft
                    ? 0..<Int(60 * scale)
                    : Int((host.bounds.width - 60) * scale)..<bitmap.pixelsWide
                var changedPixels = 0
                for y in 0..<Int(30 * scale) {
                    for x in columns {
                        let before = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                        let after = try #require(updated.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                        if abs(before.redComponent - after.redComponent) > 0.02 { changedPixels += 1 }
                    }
                }
                #expect(changedPixels > 0,
                        "The \(changeTemperature ? "current temperature" : "temperature range") must render beside the scrollbar")
            }
        }
        if locationCount == 1 {
            #expect(scroll.verticalScroller?.isHidden == true,
                    "Weather that fits must not show an inactive scrollbar")
        }
        host.rootView = content([:])
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        #expect(descendants(in: host).allSatisfy { !($0 is NSScrollView) },
                "Removing weather content must remove its native scroll container")
        window.contentView = nil
        window.contentView = host
        host.rootView = content(snapshots)
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        let remounted = try #require(descendants(in: host).compactMap { $0 as? NSScrollView }.first)
        remounted.tile()
        host.layoutSubtreeIfNeeded()
        remounted.reflectScrolledClipView(remounted.contentView)
        #expect(remounted.documentView?.frame.width == remounted.contentView.bounds.width,
                "Reopening weather must keep the document fitted to its viewport")
        if locationCount > 1 {
            try expectVisibleScrollbar(in: remounted)
            let originalHeight = window.frame.height
            window.setContentSize(CGSize(width: 184, height: 64))
            host.layoutSubtreeIfNeeded()
            window.setContentSize(CGSize(width: 184, height: originalHeight))
            host.layoutSubtreeIfNeeded()
            remounted.reflectScrolledClipView(remounted.contentView)
            try expectVisibleScrollbar(in: remounted)
            remounted.scrollerStyle = .overlay
            for _ in 0..<8 {
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
            remounted.tile()
            remounted.reflectScrolledClipView(remounted.contentView)
            try expectVisibleScrollbar(in: remounted)
        }
        #expect(try Data(contentsOf: directory.appendingPathComponent("locations.json")) == persisted)
        #expect(locations.orderedSnapshots(snapshots, at: date).count == locationCount)
        #expect(!window.isVisible)
    }

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
    func weatherPresentationUsesTranslatedDescriptionsAndSourceCopy(language: AppLanguage) throws {
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let table = try #require(NSDictionary(contentsOf: packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )) as? [String: String])
        let core = try String(contentsOf: packageRoot.appendingPathComponent("Sources/ZislaCore/Weather.swift"), encoding: .utf8)
        let decoder = try String(contentsOf: packageRoot.appendingPathComponent("Sources/ZislaKit/WeatherForecastDecoder.swift"), encoding: .utf8)
        let literal = try NSRegularExpression(pattern: #"(?:AppLocalization\.text\(|\(description, icon\) = \()"([^"]+)""#)
        let source = core + decoder
        var keys = Set(literal.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
            String(source[Range($0.range(at: 1), in: source)!])
        })
        keys.formUnion([
            "中国天气网（中国气象局）", "更新于 %@", "无法获取天气", "等待刷新", "没有可用的天气数据",
            "雷阵雨伴有冰雹", "雨夹雪", "暴雨", "大暴雨", "特大暴雨", "暴雪", "小到中雨", "中到大雨", "大到暴雨",
            "暴雨到大暴雨", "大暴雨到特大暴雨", "小到中雪", "中到大雪", "大到暴雪",
            "浓雾", "强浓雾", "大雾", "特强浓雾", "霾", "中度霾", "重度霾", "严重霾",
            "沙尘暴", "浮尘", "扬沙", "强沙尘暴",
        ])
        for key in keys {
            let value = try #require(table[key])
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, locale: language.locale) == value)
        }
        #expect(AppLocalization.string("小雨", language: .english) == "Light rain")
        #expect(AppLocalization.string("大雪", language: .arabic) == "ثلوج كثيفة")
    }

    @Test
    func everyWeatherSymbolIsAvailableAndPrecipitationIconsRenderDistinctly() throws {
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/ZislaCore/Weather.swift"), encoding: .utf8)
            + String(contentsOf: packageRoot.appendingPathComponent("Sources/ZislaKit/WeatherForecastDecoder.swift"), encoding: .utf8)
        let literal = try NSRegularExpression(pattern: #""((?:sun|moon|cloud|wind|questionmark)\.[a-zA-Z0-9.]+|snowflake)""#)
        let symbols = Set(literal.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
            String(source[Range($0.range(at: 1), in: source)!])
        })
        #expect(!symbols.isEmpty)
        for symbol in symbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                    "Weather icon \(symbol) must be available on the target macOS")
        }
        let date = Date(timeIntervalSince1970: 86_400)
        func pixels(_ symbol: String) throws -> Data {
            try renderedPixels(AgendaModuleView.weatherRow(WeatherSnapshot(
                temperature: 16, condition: WeatherCondition(summary: "Weather condition", symbolName: symbol),
                timezone: "UTC", fetchedAt: date, coordinate: GeoCoordinate(latitude: 51, longitude: 0)
            ), at: date))
        }
        let lightRain = try pixels("cloud.drizzle.fill")
        let rain = try pixels("cloud.rain.fill")
        let heavyRain = try pixels("cloud.heavyrain.fill")
        #expect(lightRain != rain && rain != heavyRain && lightRain != heavyRain,
                "Light, moderate, and heavy rain must display distinct weather icons")
        #expect(try pixels("snowflake") != pixels("cloud.snow.fill"))
        #expect(try pixels("cloud.sleet.fill") != rain, "Mixed precipitation must not render as ordinary rain")
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
        let visible = try renderedPixels(AgendaModuleView.weatherRow(snapshot, at: date))
        #expect(try visible == renderedPixels(AgendaModuleView.weatherRow(expected, at: date)),
                "Expired and boundary alerts must not render while live and unknown-expiry alerts remain")
        expected.officialAlerts = [snapshot.officialAlerts.last!]
        let laterDate = date.addingTimeInterval(2)
        let later = try renderedPixels(AgendaModuleView.weatherRow(snapshot, at: laterDate))
        #expect(try later == renderedPixels(AgendaModuleView.weatherRow(expected, at: laterDate)),
                "Alerts must expire even when no forecast refresh succeeds")
        expected.officialAlerts = []
        #expect(try later != renderedPixels(AgendaModuleView.weatherRow(expected, at: laterDate)),
                "The provider's unknown-expiry alert must stay visible")
        #expect(snapshot.officialAlerts.count == 4, "Rendering must leave the stored provider response unchanged")
    }

    @Test
    func openWeatherContentExpiresByLocationAndRecoversWithoutMutatingData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("weather-presentation-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let locations = WeatherLocationStore(storageURL: url, defaults: UserDefaults(suiteName: "weather-presentation-\(UUID())")!)
        locations.updateCurrent(name: "London", coordinate: GeoCoordinate(latitude: 51, longitude: 0))
        locations.addSaved(name: "Tokyo", coordinate: GeoCoordinate(latitude: 35.7, longitude: 0))
        let tokyoID = locations.locations.last!.id
        let date = Date(timeIntervalSince1970: 86_400)
        let london = WeatherSnapshot(
            temperature: 16, condition: WeatherCondition(code: 3, isDay: true),
            timezone: "UTC", fetchedAt: date, coordinate: GeoCoordinate(latitude: 51, longitude: 0), locationName: "London"
        )
        var tokyo = london
        tokyo.locationName = "Tokyo"
        tokyo.coordinate = GeoCoordinate(latitude: 35.7, longitude: 0)
        tokyo.fetchedAt = date.addingTimeInterval(1800)
        let stored = [WeatherLocation.currentID: london, tokyoID: tokyo]
        let persisted = try Data(contentsOf: url)
        func pixels(_ snapshots: [String: WeatherSnapshot], at date: Date, state: WeatherLocationUIState = .ready("2")) throws -> Data {
            try renderedPixels(AgendaModuleView.weatherContent(
                locations: locations, snapshotsByLocationID: snapshots, state: state, at: date
            ).frame(height: 160, alignment: .topLeading))
        }
        let before = date.addingTimeInterval(3599)
        #expect(try pixels(stored, at: before) != pixels([tokyoID: tokyo], at: before),
                "Both usable locations must still render just before the first expiry")
        let boundary = date.addingTimeInterval(3600)
        #expect(try pixels(stored, at: boundary) == pixels([tokyoID: tokyo], at: boundary),
                "Only the expired location must disappear at the one-hour boundary")
        let allExpired = date.addingTimeInterval(5400)
        let expired = try pixels(stored, at: allExpired)
        #expect(try expired == renderedPixels(Label(
            AppLocalization.text("无法获取天气"), systemImage: "cloud.slash"
        ).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: 160, alignment: .topLeading)),
                "All expired locations must show weather unavailable, not an empty scroll view")
        #expect(try expired != pixels([:], at: allExpired), "An initial empty state must still show waiting for refresh")
        var recovered = london
        recovered.temperature = 25
        recovered.fetchedAt = allExpired
        let refreshed = [WeatherLocation.currentID: recovered, tokyoID: tokyo]
        #expect(try pixels(refreshed, at: allExpired) != expired, "A new forecast must replace the expired placeholder")
        #expect(try pixels(refreshed, at: allExpired) == pixels([WeatherLocation.currentID: recovered], at: allExpired))
        #expect(try pixels(stored, at: allExpired, state: .failed("Offline")) == pixels([:], at: allExpired, state: .failed("Offline")))
        #expect(stored[WeatherLocation.currentID] == london && stored[tokyoID] == tokyo)
        #expect(try Data(contentsOf: url) == persisted, "Rendering and expiry must leave saved locations untouched")
    }

    @Test
    func weatherExpiryRemovesOnlyExpiredDataAndPreservesOtherStates() {
        let date = Date(timeIntervalSince1970: 86_400)
        let expired = WeatherSnapshot(
            temperature: 16, condition: WeatherCondition(code: 3, isDay: true),
            timezone: "UTC", fetchedAt: date.addingTimeInterval(-3600),
            coordinate: GeoCoordinate(latitude: 51, longitude: 0)
        )
        var fresh = expired
        fresh.fetchedAt = date.addingTimeInterval(-3599)
        let original = ["expired": expired, "fresh": fresh]
        var snapshots = original
        var state = WeatherLocationUIState.ready("2")
        AppModel.expireWeather(snapshots: &snapshots, state: &state, at: date)
        #expect(snapshots == ["fresh": fresh])
        #expect(state == .ready("2"), "A still-usable location must keep weather available")
        AppModel.expireWeather(snapshots: &snapshots, state: &state, at: date.addingTimeInterval(1))
        #expect(snapshots.isEmpty)
        #expect(state == .failed(AppLocalization.text("没有可用的天气数据")))
        for originalState in [WeatherLocationUIState.idle, .locating, .searching, .failed("Offline")] {
            snapshots = ["expired": expired]
            state = originalState
            AppModel.expireWeather(snapshots: &snapshots, state: &state, at: date)
            #expect(snapshots.isEmpty)
            #expect(state == originalState, "Expiry must preserve in-flight loading and existing errors")
        }
        #expect(original == ["expired": expired, "fresh": fresh])
    }

    @Test(arguments: [-1.0, 0.0, 30.0])
    func weatherExpiryTaskUpdatesOtherConsumersAtTheEarliestExpiry(delay: TimeInterval) async throws {
        let date = Date(timeIntervalSince1970: 86_400)
        let sleeper = WeatherExpirySleeper()
        var didExpire = false
        let task = try #require(AppModel.weatherExpiryTask(
            expirationDates: [date.addingTimeInterval(60), date.addingTimeInterval(delay)],
            now: { date }, sleeper: { try await sleeper.sleep(for: $0) }
        ) { didExpire = true })
        await sleeper.waitUntilSleeping()
        #expect(await sleeper.duration == .seconds(max(0, delay)))
        #expect(!didExpire, "Weather must remain visible until the expiry sleeper completes")
        await sleeper.finish()
        await task.value
        #expect(didExpire, "Expiry must notify consumers even when no refresh or UI timeline runs")
        #expect(AppModel.weatherExpiryTask(expirationDates: []) { didExpire = true } == nil)
    }

    @Test(arguments: ["cancelled", "failed", "cancelled-and-failed"])
    func weatherExpiryTaskDoesNotUpdateConsumersAfterCancellationOrFailure(reason: String) async throws {
        let date = Date(timeIntervalSince1970: 86_400)
        let sleeper = WeatherExpirySleeper()
        var didExpire = false
        let task = try #require(AppModel.weatherExpiryTask(
            expirationDates: [date.addingTimeInterval(30)], now: { date },
            sleeper: { try await sleeper.sleep(for: $0) }
        ) { didExpire = true })
        await sleeper.waitUntilSleeping()
        if reason.hasPrefix("cancelled") { task.cancel() }
        await sleeper.finish(failed: reason.hasSuffix("failed"))
        await task.value
        #expect(!didExpire, "Stopping or replacing the task must not publish a late expiry")
    }

    private func recognizedText(in weather: WeatherSnapshot, at date: Date = Date()) throws -> String {
        let cgImage = try renderedImage(AgendaModuleView.weatherRow(weather, at: date))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    private func renderedPixels<Content: View>(_ content: Content) throws -> Data {
        let image = try renderedImage(content)
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try #require(context.data), count: image.width * image.height * 4)
    }

    private func renderedImage<Content: View>(_ content: Content) throws -> CGImage {
        let hosting = NSHostingView(rootView: content
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

private actor WeatherExpirySleeper {
    private(set) var duration: Duration?
    private var continuation: CheckedContinuation<Void, Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async throws {
        self.duration = duration
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            for waiter in startWaiters { waiter.resume() }
            startWaiters.removeAll()
        }
    }

    func waitUntilSleeping() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish(failed: Bool = false) {
        if failed {
            continuation?.resume(throwing: CancellationError())
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}
