import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
struct WeatherFallbackTests {
    private let coordinate = GeoCoordinate(latitude: 31.2, longitude: 121.4)
    private static let openMeteo = Data(#"{"timezone":"Asia/Shanghai","current":{"time":"2026-11-05T10:45","temperature_2m":28.5,"apparent_temperature":30.2,"weather_code":2,"is_day":1,"precipitation":0},"daily":{"sunrise":["2026-11-05T05:04"],"sunset":["2026-11-05T18:56"],"temperature_2m_min":[24.1],"temperature_2m_max":[33.8],"precipitation_probability_max":[10],"precipitation_sum":[0]}}"#.utf8)
    private static let met = Data(#"{"properties":{"meta":{"units":{"air_temperature":"celsius"}},"timeseries":[{"time":"2026-11-05T10:00:00Z","data":{"instant":{"details":{"air_temperature":16.2}},"next_1_hours":{"summary":{"symbol_code":"lightrainshowers_night"},"details":{"precipitation_amount":2.5}}}}]}}"#.utf8)
    private static let china = Data(#"var cityDZ={"weatherinfo":{"fctime":"202611050800"}};var alarmDZ={"w":[]};var dataSK={"temp":"16.1","weather":"多云","weathercode":"n01","city":"101020100"};var fc={"f":[{"fc":"18","fd":"14","fi":"11/5"}]};"#.utf8)
    private static let station = Data(#"([{"ref":"101020100~shanghai~上海~Shanghai~021~200000~SH~上海~上海"}])"#.utf8)

    private func makeService(
        alertFails: Bool = false,
        country: String? = "CN",
        countryError: URLError? = nil,
        alertError: URLError? = nil,
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1793874600) }
    ) -> WeatherService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ForecastURLProtocol.self]
        configuration.urlCache = URLCache(memoryCapacity: 1_048_576, diskCapacity: 0)
        return WeatherService(
            session: URLSession(configuration: configuration),
            alertProvider: ForecastAlertStub(fails: alertFails, error: alertError),
            countryGeocoder: ForecastGeocoderStub(country: country, error: countryError),
            now: now
        )
    }

    @Test(arguments: ["CN", "cn", "HK", "MO", "TW"])
    func domesticPrimaryReturnsChineseWeatherWithoutFabricatingMissingMetrics(country: String) async throws {
        ForecastURLProtocol.reset([
            .data(Self.station), .data(Self.china),
        ])
        let snapshot = try await makeService().fetch(
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            locationName: "上海", isoCountryCode: country
        )
        #expect(snapshot.temperature == 16.1)
        #expect(snapshot.apparentTemperature == nil)
        #expect(snapshot.precipitationProbability == nil)
        #expect(snapshot.precipitationSum == nil)
        #expect(snapshot.currentPrecipitation == nil)
        #expect(snapshot.condition.summary == WeatherCondition(code: 2, isDay: false).summary)
        #expect(snapshot.condition.symbolName == "cloud.sun.fill")
        #expect(snapshot.sourceURL?.host == "www.weather.com.cn")
        #expect(ForecastURLProtocol.requests.map { $0.url?.host } == ["toy1.weather.com.cn", "d1.weather.com.cn"])
        #expect(ForecastURLProtocol.requests.last?.value(forHTTPHeaderField: "Referer") == "https://www.weather.com.cn/")
    }

    @Test(arguments: ["GB", "JP", "MN", "RU", "VN"])
    func overseasNeverQueriesChineseNamesakes(country: String) async throws {
        ForecastURLProtocol.reset([.data(Self.openMeteo)])
        let snapshot = try await makeService().fetch(
            latitude: 35, longitude: 100, locationName: "上海", isoCountryCode: country
        )
        #expect(snapshot.temperature == 28.5)
        #expect(ForecastURLProtocol.requests.map { $0.url?.host } == ["api.open-meteo.com"])
    }

    @Test
    func legacyCountryIsResolvedFromPlacemarkAndCanUseDomesticPrimary() async throws {
        ForecastURLProtocol.reset([.data(Self.station), .data(Self.china)])
        _ = try await makeService().fetch(latitude: 31.2, longitude: 121.4, locationName: "上海")
        #expect(ForecastURLProtocol.requests.first?.url?.host == "toy1.weather.com.cn")
    }

    @Test
    func failedCountryResolutionUsesGlobalSources() async throws {
        ForecastURLProtocol.reset([.data(Self.openMeteo)])
        _ = try await makeService(country: nil).fetch(latitude: 31.2, longitude: 121.4, locationName: "上海")
        #expect(ForecastURLProtocol.requests.first?.url?.host == "api.open-meteo.com")
    }

    @Test
    func bothPrimaryFailuresReachIndependentGlobalFallback() async throws {
        ForecastURLProtocol.reset([
            .failure(URLError(.timedOut)), .http(503, Data(), [:]), .data(Self.met),
        ])
        let snapshot = try await makeService().fetch(
            latitude: 31.123456, longitude: 121.123456, locationName: "上海", isoCountryCode: "CN"
        )
        #expect(snapshot.temperature == 16.2)
        #expect(snapshot.condition.summary == AppLocalization.text("小阵雨"))
        #expect(snapshot.condition.symbolName == "cloud.drizzle.fill")
        #expect(snapshot.apparentTemperature == nil)
        #expect(snapshot.currentPrecipitation == nil)
        #expect(snapshot.precipitationProbability == nil)
        #expect(snapshot.precipitationSum == nil)
        #expect(snapshot.sunrise.isEmpty && snapshot.sunset.isEmpty)
        #expect(snapshot.source == "MET Norway")
        #expect(snapshot.licenseURL?.absoluteString == "https://creativecommons.org/licenses/by/4.0/")
        let request = try #require(ForecastURLProtocol.requests.last)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first { $0.name == "lat" }?.value == "31.1235")
        #expect(query?.first { $0.name == "lon" }?.value == "121.1235")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("github.com/wzz6423/zisla") == true)
    }

    @Test(arguments: [0, 1, 2, 3])
    func invalidPrimaryResponsesFallBack(kind: Int) async throws {
        let bad: Data = switch kind {
        case 0: Data("<html>proxy error</html>".utf8)
        case 1: Data(repeating: 65, count: 1_048_577)
        case 2: Data(#"{"timezone":"UTC","current":{"time":"2026-11-05T00:00","temperature_2m":999,"apparent_temperature":1,"weather_code":1,"is_day":1},"daily":null}"#.utf8)
        default: Data(#"{"timezone":"UTC","current":{"time":"2026-11-05T00:00","temperature_2m":1,"apparent_temperature":1,"weather_code":1,"is_day":1},"daily":{"sunrise":[],"sunset":[],"precipitation_probability_max":[],"precipitation_sum":[]}}"#.utf8)
        }
        ForecastURLProtocol.reset([.data(bad), .data(Self.met)])
        let snapshot = try await makeService().fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
        #expect(snapshot.source == "MET Norway")
        #expect(ForecastURLProtocol.requests.count == 2)
    }

    @Test
    func allSourcesFailWithNoFabricatedSnapshot() async {
        ForecastURLProtocol.reset([.http(502, Data(), [:]), .data(Data("{}".utf8))])
        do {
            _ = try await makeService().fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
            Issue.record("Failed sources must not produce weather")
        } catch {
            #expect(error as? WeatherServiceError == .invalidResponse)
            #expect(ForecastURLProtocol.requests.count == 2)
        }
    }

    @Test
    func urlSessionCancellationStopsBeforeFallback() async {
        ForecastURLProtocol.reset([.failure(URLError(.cancelled))])
        do {
            _ = try await makeService().fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
            Issue.record("Cancellation must propagate")
        } catch {
            #expect(error is CancellationError)
            #expect(ForecastURLProtocol.requests.count == 1)
        }
    }

    @Test
    func alreadyCancelledRequestDoesNotStartNetwork() async {
        ForecastURLProtocol.reset([])
        let service = makeService()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream {}
            return try await service.fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
        }
        task.cancel()
        continuation.finish()
        do {
            _ = try await task.value
            Issue.record("Cancellation must propagate")
        } catch {
            #expect(error is CancellationError)
            #expect(ForecastURLProtocol.requests.isEmpty)
        }
    }

    @Test
    func alertFailureKeepsSuccessfulForecastWithoutSwitchingSources() async throws {
        ForecastURLProtocol.reset([.data(Self.openMeteo)])
        let snapshot = try await makeService(alertFails: true).fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
        #expect(snapshot.temperature == 28.5)
        #expect(snapshot.alertErrorDescription != nil)
        #expect(ForecastURLProtocol.requests.count == 1)
    }

    @Test(arguments: AppLanguage.allCases)
    func forecastErrorsUseTheSelectedInterfaceLanguage(language: AppLanguage) throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: AppLocalization.defaultsKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: AppLocalization.defaultsKey)
            } else {
                defaults.removeObject(forKey: AppLocalization.defaultsKey)
            }
        }
        defaults.set(language.rawValue, forKey: AppLocalization.defaultsKey)
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let table = try #require(NSDictionary(contentsOf: packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )) as? [String: String])
        let errors: [(WeatherServiceError, String)] = [
            (.invalidCoordinates, "天气位置坐标无效"),
            (.invalidResponse, "天气服务返回了无效响应"),
            (.responseTooLarge, "天气响应超过大小限制"),
        ]
        for (error, key) in errors {
            let translated = try #require(table[key])
            #expect(!translated.isEmpty)
            #expect(error.localizedDescription == translated)
        }
        let payload = Data(String(decoding: Self.china, as: UTF8.self)
            .replacingOccurrences(of: "多云", with: "小雨").replacingOccurrences(of: "n01", with: "d07").utf8)
        let forecast = try WeatherForecastDecoder.chinaWeather(payload, stationID: "101020100", coordinate: coordinate, locationName: "上海")
        #expect(forecast.condition.summary == table["小雨"])
        #expect(forecast.condition.symbolName == "cloud.drizzle.fill")
    }

    @Test(arguments: [Double.nan, Double.infinity, 91, -91])
    func invalidCoordinatesStartNoNetwork(latitude: Double) async {
        ForecastURLProtocol.reset([])
        do {
            _ = try await makeService().fetch(latitude: latitude, longitude: 0, isoCountryCode: "GB")
            Issue.record("Invalid coordinates must fail")
        } catch {
            #expect(error as? WeatherServiceError == .invalidCoordinates)
            #expect(ForecastURLProtocol.requests.isEmpty)
        }
    }

    @Test
    func chineseDailyRangeUsesOnlyMatchingDayAndIgnoresMissingSentinel() throws {
        let date = ISO8601DateFormatter().date(from: "2026-11-05T10:00:00Z")!
        let snapshot = try WeatherForecastDecoder.chinaWeather(Self.china, stationID: "101020100", coordinate: coordinate, locationName: "上海", now: date)
        #expect(snapshot.temperatureMin == 14)
        #expect(snapshot.temperatureMax == 18)
        let tomorrow = try WeatherForecastDecoder.chinaWeather(Self.china, stationID: "101020100", coordinate: coordinate, locationName: "上海", now: date.addingTimeInterval(86400))
        #expect(tomorrow.temperatureMin == nil && tomorrow.temperatureMax == nil)
        let sentinel = Data(String(decoding: Self.china, as: UTF8.self).replacingOccurrences(of: "\"18\"", with: "\"999\"").utf8)
        let incomplete = try WeatherForecastDecoder.chinaWeather(sentinel, stationID: "101020100", coordinate: coordinate, locationName: "上海", now: date)
        #expect(incomplete.temperatureMax == nil)
    }

    @Test(arguments: ["d00", "n00", "d01", "n01"])
    func chineseCurrentIconDoesNotInferDaylightFromItsUnreliablePrefix(code: String) throws {
        let payload = Data(String(decoding: Self.china, as: UTF8.self).replacingOccurrences(of: "n01", with: code).utf8)
        let snapshot = try WeatherForecastDecoder.chinaWeather(payload, stationID: "101020100", coordinate: coordinate, locationName: "上海")
        #expect(snapshot.condition.symbolName == (code.hasSuffix("00") ? "sun.max.fill" : "cloud.sun.fill"))
    }

    @Test(arguments: ["d", "n"])
    func chineseForecastRetainsProviderDescriptionsAndUsesTheOriginalWeatherCode(prefix: String) throws {
        let conditions: [(Int, String, String)] = [
            (0, "晴", "sun.max.fill"), (1, "多云", "cloud.sun.fill"), (2, "阴", "cloud.fill"),
            (3, "阵雨", "cloud.rain.fill"), (4, "雷阵雨", "cloud.bolt.rain.fill"),
            (5, "雷阵雨伴有冰雹", "cloud.hail.fill"), (6, "雨夹雪", "cloud.sleet.fill"),
            (7, "小雨", "cloud.drizzle.fill"), (8, "中雨", "cloud.rain.fill"),
            (9, "大雨", "cloud.heavyrain.fill"), (10, "暴雨", "cloud.heavyrain.fill"),
            (11, "大暴雨", "cloud.heavyrain.fill"), (12, "特大暴雨", "cloud.heavyrain.fill"),
            (13, "阵雪", "cloud.snow.fill"), (14, "小雪", "snowflake"),
            (15, "中雪", "cloud.snow.fill"), (16, "大雪", "cloud.snow.fill"),
            (17, "暴雪", "wind.snow"), (18, "雾", "cloud.fog.fill"), (19, "冻雨", "cloud.sleet.fill"),
            (20, "沙尘暴", "sun.dust.fill"), (21, "小到中雨", "cloud.rain.fill"),
            (22, "中到大雨", "cloud.heavyrain.fill"), (23, "大到暴雨", "cloud.heavyrain.fill"),
            (24, "暴雨到大暴雨", "cloud.heavyrain.fill"), (25, "大暴雨到特大暴雨", "cloud.heavyrain.fill"),
            (26, "小到中雪", "cloud.snow.fill"), (27, "中到大雪", "cloud.snow.fill"),
            (28, "大到暴雪", "wind.snow"), (29, "浮尘", "sun.dust.fill"),
            (30, "扬沙", "sun.dust.fill"), (31, "强沙尘暴", "sun.dust.fill"),
            (32, "浓雾", "cloud.fog.fill"), (33, "雪", "cloud.snow.fill"), (49, "强浓雾", "cloud.fog.fill"),
            (53, "霾", "sun.haze.fill"), (54, "中度霾", "sun.haze.fill"),
            (55, "重度霾", "sun.haze.fill"), (56, "严重霾", "sun.haze.fill"),
            (57, "大雾", "cloud.fog.fill"), (58, "特强浓雾", "cloud.fog.fill"),
            (301, "雨", "cloud.rain.fill"), (302, "雪", "cloud.snow.fill"),
            (999, "来源自定义天气描述", "questionmark.circle"),
        ]
        let date = Date(timeIntervalSince1970: 1793874600)
        for (code, description, symbol) in conditions {
            let payload = Data(String(decoding: Self.china, as: UTF8.self)
                .replacingOccurrences(of: "n01", with: prefix + String(format: "%02d", code))
                .replacingOccurrences(of: "多云", with: description).utf8)
            let original = payload
            let snapshot = try WeatherForecastDecoder.chinaWeather(
                payload, stationID: "101020100", coordinate: coordinate, locationName: "上海", now: date
            )
            #expect(snapshot.condition.summary == AppLocalization.text(description), "Provider weather code \(code) must retain its description")
            #expect(snapshot.condition.symbolName == symbol, "Provider weather code \(code) must retain its precipitation type and intensity")
            #expect(snapshot.temperature == 16.1 && snapshot.temperatureMin == 14 && snapshot.temperatureMax == 18)
            #expect(payload == original && snapshot.fetchedAt == date)
        }
    }

    @Test(arguments: ["absent", "empty", "whitespace", "null"])
    func chineseMissingDescriptionsFailWithoutInventingWeather(kind: String) {
        let replacement = switch kind {
        case "null": "\"weather\":null,"
        case "empty": "\"weather\":\"\","
        case "whitespace": "\"weather\":\"   \","
        default: ""
        }
        let payload = Data(String(decoding: Self.china, as: UTF8.self)
            .replacingOccurrences(of: "\"weather\":\"多云\",", with: replacement).utf8)
        #expect(throws: WeatherServiceError.invalidResponse) {
            _ = try WeatherForecastDecoder.chinaWeather(payload, stationID: "101020100", coordinate: coordinate, locationName: "上海")
        }
    }

    @Test(arguments: ["", "day", "night", "polartwilight"])
    func METSymbolsRetainPrecipitationIntensityAndMixedTypes(variant: String) throws {
        let conditions: [(String, String, String)] = [
            ("lightrain", "小雨", "cloud.drizzle.fill"), ("rain", "雨", "cloud.rain.fill"),
            ("heavyrain", "大雨", "cloud.heavyrain.fill"),
            ("lightrainshowers", "小阵雨", "cloud.drizzle.fill"), ("rainshowers", "阵雨", "cloud.rain.fill"),
            ("heavyrainshowers", "强阵雨", "cloud.heavyrain.fill"),
            ("lightsnow", "小雪", "snowflake"), ("snow", "雪", "cloud.snow.fill"),
            ("heavysnow", "大雪", "cloud.snow.fill"),
            ("lightsnowshowers", "小阵雪", "snowflake"), ("snowshowers", "阵雪", "cloud.snow.fill"),
            ("heavysnowshowers", "强阵雪", "cloud.snow.fill"),
            ("lightsleet", "小雨夹雪", "cloud.sleet.fill"), ("sleet", "雨夹雪", "cloud.sleet.fill"),
            ("heavysleet", "强雨夹雪", "cloud.sleet.fill"),
            ("lightsleetshowers", "小阵性雨夹雪", "cloud.sleet.fill"), ("sleetshowers", "阵性雨夹雪", "cloud.sleet.fill"),
            ("heavysleetshowers", "强阵性雨夹雪", "cloud.sleet.fill"),
            ("lightrainandthunder", "小雨伴雷电", "cloud.bolt.rain.fill"),
            ("rainandthunder", "雨伴雷电", "cloud.bolt.rain.fill"),
            ("heavyrainandthunder", "大雨伴雷电", "cloud.bolt.rain.fill"),
            ("lightrainshowersandthunder", "小阵雨伴雷电", "cloud.bolt.rain.fill"),
            ("rainshowersandthunder", "阵雨伴雷电", "cloud.bolt.rain.fill"),
            ("heavyrainshowersandthunder", "强阵雨伴雷电", "cloud.bolt.rain.fill"),
            ("lightsnowandthunder", "小雪伴雷电", "cloud.bolt.fill"),
            ("snowandthunder", "雪伴雷电", "cloud.bolt.fill"),
            ("heavysnowandthunder", "大雪伴雷电", "cloud.bolt.fill"),
            ("lightssnowshowersandthunder", "小阵雪伴雷电", "cloud.bolt.fill"),
            ("snowshowersandthunder", "阵雪伴雷电", "cloud.bolt.fill"),
            ("heavysnowshowersandthunder", "强阵雪伴雷电", "cloud.bolt.fill"),
            ("lightsleetandthunder", "小雨夹雪伴雷电", "cloud.bolt.fill"),
            ("sleetandthunder", "雨夹雪伴雷电", "cloud.bolt.fill"),
            ("heavysleetandthunder", "强雨夹雪伴雷电", "cloud.bolt.fill"),
            ("lightssleetshowersandthunder", "小阵性雨夹雪伴雷电", "cloud.bolt.fill"),
            ("sleetshowersandthunder", "阵性雨夹雪伴雷电", "cloud.bolt.fill"),
            ("heavysleetshowersandthunder", "强阵性雨夹雪伴雷电", "cloud.bolt.fill"),
            ("cloudy", "阴", "cloud.fill"), ("fog", "雾", "cloud.fog.fill"),
            ("unrecognized", "天气未知", "questionmark.circle"),
        ]
        let date = Date(timeIntervalSince1970: 1793874600)
        for (code, description, dayIcon, nightIcon) in [
            ("clearsky", "晴", "sun.max.fill", "moon.stars.fill"),
            ("fair", "晴间少云", "sun.max.fill", "moon.fill"),
            ("partlycloudy", "多云", "cloud.sun.fill", "cloud.moon.fill"),
        ] {
            let symbol = code + (variant.isEmpty ? "" : "_" + variant)
            let payload = Data(String(decoding: Self.met, as: UTF8.self)
                .replacingOccurrences(of: "lightrainshowers_night", with: symbol).utf8)
            let forecast = try WeatherForecastDecoder.metNorway(payload, coordinate: coordinate, locationName: "上海", now: date)
            #expect(forecast.condition.summary == AppLocalization.text(description))
            #expect(forecast.condition.symbolName == (variant == "night" ? nightIcon : dayIcon),
                    "Only explicit night forecasts should use a moon icon")
        }
        for (code, description, symbol) in conditions {
            let original = code + (variant.isEmpty ? "" : "_" + variant)
            let payload = Data(String(decoding: Self.met, as: UTF8.self)
                .replacingOccurrences(of: "lightrainshowers_night", with: original).utf8)
            let snapshot = try WeatherForecastDecoder.metNorway(payload, coordinate: coordinate, locationName: "上海", now: date)
            #expect(snapshot.condition.summary == AppLocalization.text(description), "MET symbol \(original) must retain its full weather description")
            #expect(snapshot.condition.symbolName == symbol, "MET symbol \(original) must retain its precipitation type")
            #expect(snapshot.temperature == 16.2 && snapshot.fetchedAt == date.addingTimeInterval(-1800))
        }
    }

    @Test
    func missingChineseDescriptionFallsBackToTheNextProvider() async throws {
        let missing = Data(String(decoding: Self.china, as: UTF8.self)
            .replacingOccurrences(of: "\"weather\":\"多云\",", with: "").utf8)
        ForecastURLProtocol.reset([.data(Self.station), .data(missing), .data(Self.openMeteo)])
        let forecast = try await makeService().fetch(
            latitude: coordinate.latitude, longitude: coordinate.longitude, locationName: "上海", isoCountryCode: "CN"
        )
        #expect(forecast.source == "Open-Meteo")
        #expect(forecast.condition == WeatherCondition(code: 2, isDay: true))
        #expect(ForecastURLProtocol.requests.count == 3)
    }

    @Test
    func cancelledLegacyCountryLookupStartsNoForecast() async {
        ForecastURLProtocol.reset([])
        do {
            _ = try await makeService(countryError: URLError(.cancelled)).fetch(latitude: 51, longitude: 0)
            Issue.record("Geocoding cancellation must propagate")
        } catch {
            #expect(error is CancellationError)
            #expect(ForecastURLProtocol.requests.isEmpty)
        }
    }

    @Test
    func cancelledAlertsDoNotReturnACompletedSnapshot() async {
        ForecastURLProtocol.reset([.data(Self.openMeteo)])
        do {
            _ = try await makeService(alertError: URLError(.cancelled)).fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
            Issue.record("Alert cancellation must propagate")
        } catch {
            #expect(error is CancellationError)
            #expect(ForecastURLProtocol.requests.count == 1)
        }
    }

    @Test
    func domesticWithoutNameFallsBackToCoordinateSource() async throws {
        ForecastURLProtocol.reset([.data(Self.openMeteo)])
        let snapshot = try await makeService().fetch(latitude: 31.2, longitude: 121.4, isoCountryCode: "CN")
        #expect(snapshot.source == "Open-Meteo")
        #expect(ForecastURLProtocol.requests.count == 1)
    }

    @Test(arguments: ["999", "NaN", "Infinity"])
    func chineseMissingCurrentTemperatureFallsBack(value: String) async throws {
        ForecastURLProtocol.reset([
            .data(Self.station),
            .data(Data(String(decoding: Self.china, as: UTF8.self).replacingOccurrences(of: "16.1", with: value).utf8)),
            .data(Self.openMeteo),
        ])
        let snapshot = try await makeService().fetch(latitude: 31.2, longitude: 121.4, locationName: "上海", isoCountryCode: "CN")
        #expect(snapshot.source == "Open-Meteo")
    }

    @Test(arguments: ["var fc={}; fake", ";var fc={};", "; var fc = {};", "\";var fc={};", "\\\"; var fc={};", "刘海;var fc={};"])
    func variableAssignmentIgnoresNamesAndBracesInsideOtherStringValues(notes: String) throws {
        let json = try JSONSerialization.data(withJSONObject: ["weatherinfo": ["fctime": "202611050800", "notes": notes]])
        let prefix = Data("var cityDZ=\(String(decoding: json, as: UTF8.self));".utf8)
        let payload = prefix + Self.china
        let snapshot = try WeatherForecastDecoder.chinaWeather(payload, stationID: "101020100", coordinate: coordinate, locationName: "上海", now: Date(timeIntervalSince1970: 1793874600))
        #expect(snapshot.temperatureMax == 18)
        #expect(snapshot.temperatureMin == 14)
    }

    @Test
    func assignmentParsingPreservesForecastAcrossSeededJSONStrings() throws {
        let alphabet = [";", "var fc=", "{", "}", "\\", "\"", "中文", "😀", "\n", "\t"]
        var seed: UInt64 = 0x7151A
        for _ in 0..<48 {
            var notes = ";var fc={};"
            for _ in 0..<20 {
                seed = seed &* 6364136223846793005 &+ 1
                notes += alphabet[Int(seed % UInt64(alphabet.count))]
            }
            let json = try JSONSerialization.data(withJSONObject: ["notes": notes])
            let prefix = Data("var cityDZ=\(String(decoding: json, as: UTF8.self));".utf8)
            let snapshot = try WeatherForecastDecoder.chinaWeather(prefix + Self.china, stationID: "101020100", coordinate: coordinate, locationName: "上海", now: Date(timeIntervalSince1970: 1793874600))
            #expect(snapshot.temperatureMin == 14 && snapshot.temperatureMax == 18, "JSON strings must not replace the forecast assignment")
        }
    }

    @Test
    func chineseResponseCannotInjectAnotherStationIntoSourceLink() async {
        let injected = Data(String(decoding: Self.china, as: UTF8.self).replacingOccurrences(of: "101020100", with: "101020100/../../other").utf8)
        do {
            _ = try WeatherForecastDecoder.chinaWeather(injected, stationID: "101020100", coordinate: coordinate, locationName: "上海")
            Issue.record("Mismatched station must fail")
        } catch {
            #expect(error as? WeatherServiceError == .invalidResponse)
        }
    }

    @Test(arguments: ["temperature_2m", "precipitation", "precipitation_probability_max", "precipitation_sum"])
    func openMeteoInvalidNumericMetricsReachFallback(metric: String) async throws {
        var json = String(decoding: Self.openMeteo, as: UTF8.self)
        switch metric {
        case "temperature_2m": json = json.replacingOccurrences(of: "\"temperature_2m\":28.5", with: "\"temperature_2m\":999")
        case "precipitation": json = json.replacingOccurrences(of: "\"precipitation\":0", with: "\"precipitation\":-1")
        case "precipitation_probability_max": json = json.replacingOccurrences(of: "\"precipitation_probability_max\":[10]", with: "\"precipitation_probability_max\":[101]")
        default: json = json.replacingOccurrences(of: "\"precipitation_sum\":[0]", with: "\"precipitation_sum\":[-1]")
        }
        ForecastURLProtocol.reset([.data(Data(json.utf8)), .data(Self.met)])
        let snapshot = try await makeService().fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
        #expect(snapshot.source == "MET Norway")
    }

    @Test
    func cachedMETForecastHonorsExpiresAndRevalidatesWithLastModified() async throws {
        let clock = ForecastClock(Date(timeIntervalSince1970: 1793874600))
        let headers = [
            "Expires": "Thu, 05 Nov 2026 10:40:00 GMT",
            "Last-Modified": "Thu, 05 Nov 2026 10:00:00 GMT",
        ]
        ForecastURLProtocol.reset([.http(503, Data(), [:]), .http(200, Self.met, headers)])
        let service = makeService(now: { clock.date })
        let first = try await service.fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
        ForecastURLProtocol.reset([.http(503, Data(), [:])])
        let cached = try await service.fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
        #expect(cached == first)
        #expect(ForecastURLProtocol.requests.count == 1)

        clock.date = first.fetchedAt.addingTimeInterval(45 * 60)
        ForecastURLProtocol.reset([.http(503, Data(), [:]), .http(304, Data(), ["Expires": "Thu, 05 Nov 2026 12:00:00 GMT"])])
        let revalidated = try await service.fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
        #expect(revalidated.temperature == first.temperature)
        #expect(revalidated.fetchedAt == first.fetchedAt)
        #expect(ForecastURLProtocol.requests.last?.value(forHTTPHeaderField: "If-Modified-Since") == "Thu, 05 Nov 2026 10:00:00 GMT")
    }

    @Test
    func corruptMETResponseIsNotCachedAcrossRecovery() async throws {
        ForecastURLProtocol.reset([.http(503, Data(), [:]), .data(Data("{}".utf8))])
        let service = makeService()
        do {
            _ = try await service.fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
            Issue.record("Corrupt MET response must fail")
        } catch {
            #expect(error as? WeatherServiceError == .invalidResponse)
        }
        ForecastURLProtocol.reset([.http(503, Data(), [:]), .data(Self.met)])
        let recovered = try await service.fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
        #expect(recovered.source == "MET Norway")
        #expect(ForecastURLProtocol.requests.count == 2)
    }

    @Test
    func METCurrentEntryTracksClockInsteadOfCachedFirstHour() throws {
        let now = Date(timeIntervalSince1970: 1793874600)
        let old = String(decoding: Self.met, as: UTF8.self)
        let object = try JSONSerialization.jsonObject(with: Data(old.utf8)) as! [String: Any]
        var properties = object["properties"] as! [String: Any]
        let first = (properties["timeseries"] as! [[String: Any]])[0]
        var previous = first
        previous["time"] = "2026-11-05T09:00:00Z"
        properties["timeseries"] = [previous, first]
        let data = try JSONSerialization.data(withJSONObject: ["properties": properties])
        let snapshot = try WeatherForecastDecoder.metNorway(data, coordinate: coordinate, locationName: "上海", now: now)
        #expect(snapshot.fetchedAt == now.addingTimeInterval(-1800))
        for date in [now.addingTimeInterval(-3600), now.addingTimeInterval(3600)] {
            do {
                _ = try WeatherForecastDecoder.metNorway(Self.met, coordinate: coordinate, locationName: "上海", now: date)
                Issue.record("Future or stale instant must fail")
            } catch {
                #expect(error as? WeatherServiceError == .invalidResponse)
            }
        }
    }

    @Test(arguments: ["next_1_hours", "next_6_hours", "next_12_hours"])
    func METUsesTheAvailableForecastPeriod(period: String) throws {
        let data = Data(String(decoding: Self.met, as: UTF8.self).replacingOccurrences(of: "next_1_hours", with: period).utf8)
        let snapshot = try WeatherForecastDecoder.metNorway(data, coordinate: coordinate, locationName: "上海", now: Date(timeIntervalSince1970: 1793874600))
        #expect(snapshot.temperature == 16.2)
        #expect(snapshot.condition.summary == AppLocalization.text("小阵雨"))
        #expect(snapshot.condition.symbolName == "cloud.drizzle.fill")
        #expect(snapshot.precipitationSum == nil && snapshot.currentPrecipitation == nil)
    }

    @Test(arguments: ["air_temperature", "units", "symbol", "period", "time"])
    func METRejectsInvalidOrMissingCurrentData(field: String) throws {
        var json = String(decoding: Self.met, as: UTF8.self)
        switch field {
        case "air_temperature": json = json.replacingOccurrences(of: ":16.2", with: ":999")
        case "units": json = json.replacingOccurrences(of: "celsius", with: "fahrenheit")
        case "symbol": json = json.replacingOccurrences(of: "lightrainshowers_night", with: "")
        case "period": json = json.replacingOccurrences(of: "next_1_hours", with: "absent")
        default: json = json.replacingOccurrences(of: "2026-11-05T10:00:00Z", with: "invalid")
        }
        #expect(throws: WeatherServiceError.invalidResponse) {
            _ = try WeatherForecastDecoder.metNorway(Data(json.utf8), coordinate: coordinate, locationName: "上海", now: Date(timeIntervalSince1970: 1793874600))
        }
    }

    @Test
    func METCacheWithoutExpiresRevalidatesInsteadOfInventingFreshness() async throws {
        let service = makeService()
        for _ in 0..<2 {
            ForecastURLProtocol.reset([.http(503, Data(), [:]), .data(Self.met)])
            let snapshot = try await service.fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
            #expect(snapshot.source == "MET Norway")
            #expect(ForecastURLProtocol.requests.count == 2)
        }
    }

    @Test(arguments: [304, 503, -1, 1_048_577])
    func METUnusableResponsesFailWithoutCaching(code: Int) async throws {
        let response: ForecastURLProtocol.Result = switch code {
        case -1: .nonHTTP(Self.met)
        case 1_048_577: .data(Data(repeating: 65, count: code))
        default: .http(code, Data(), [:])
        }
        ForecastURLProtocol.reset([.http(503, Data(), [:]), response])
        let service = makeService()
        do {
            _ = try await service.fetch(latitude: 51, longitude: 0, isoCountryCode: "GB")
            Issue.record("MET failures must not produce or cache a snapshot")
        } catch {
            #expect(error as? WeatherServiceError == (code == 1_048_577 ? .responseTooLarge : .invalidResponse))
        }
        ForecastURLProtocol.reset([.http(503, Data(), [:]), .data(Self.met)])
        #expect(try await service.fetch(latitude: 51, longitude: 0, isoCountryCode: "GB").temperature == 16.2)
        #expect(ForecastURLProtocol.requests.count == 2)
    }
}

private struct ForecastAlertStub: OfficialWeatherAlertProviding {
    let fails: Bool
    let error: URLError?
    func fetchOfficialAlerts(latitude: Double, longitude: Double, locationName: String?) async throws -> [WeatherAlert] {
        if let error { throw error }
        if fails { throw URLError(.timedOut) }
        return []
    }
}

private struct ForecastGeocoderStub: PlaceGeocoding {
    let country: String?
    let error: URLError?
    func geocode(_ query: String) async throws -> [GeocodedPlace] { [] }
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> [GeocodedPlace] {
        if let error { throw error }
        if country == nil { throw URLError(.notConnectedToInternet) }
        return [GeocodedPlace(latitude: latitude, longitude: longitude, isoCountryCode: country)]
    }
}

private final class ForecastURLProtocol: URLProtocol, @unchecked Sendable {
    enum Result {
        case data(Data)
        case http(Int, Data, [String: String])
        case nonHTTP(Data)
        case failure(URLError)
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var results: [Result] = []
    nonisolated(unsafe) private static var recorded: [URLRequest] = []
    static var requests: [URLRequest] { lock.withLock { recorded } }
    static func reset(_ responses: [Result]) {
        lock.withLock { results = responses; recorded = [] }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let next = Self.lock.withLock {
            Self.recorded.append(request)
            return Self.results.isEmpty ? Result.failure(URLError(.resourceUnavailable)) : Self.results.removeFirst()
        }
        switch next {
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        case .data(let data): respond(status: 200, data: data, headers: [:])
        case .http(let status, let data, let headers): respond(status: status, data: data, headers: headers)
        case .nonHTTP(let data):
            let response = URLResponse(url: request.url!, mimeType: "application/json", expectedContentLength: data.count, textEncodingName: nil)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    private func respond(status: Int, data: Data, headers: [String: String]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers.merging(["Content-Type": "application/json"], uniquingKeysWith: { first, _ in first }))!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowedInMemoryOnly)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class ForecastClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var date: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
