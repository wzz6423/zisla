import Foundation
import ZislaCore

// Secondary sources do not supply the same daily or apparent-temperature metrics.
// Missing values remain absent instead of being reported as zero precipitation.
enum WeatherForecastDecoder {
    static func openMeteo(
        _ data: Data,
        coordinate: GeoCoordinate,
        locationName: String?
    ) throws -> WeatherSnapshot {
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        guard let daily = decoded.daily,
              let sunrise = daily.sunrise.first,
              let sunset = daily.sunset.first,
              let probability = daily.precipitationProbabilityMax.first,
              let precipitation = daily.precipitationSum.first,
              (-100...100).contains(decoded.current.temperature),
              (0...100).contains(probability),
              precipitation >= 0,
              decoded.current.precipitation >= 0
        else { throw WeatherServiceError.invalidResponse }
        return WeatherSnapshot(
            temperature: decoded.current.temperature,
            temperatureMin: daily.temperatureMin?.first,
            temperatureMax: daily.temperatureMax?.first,
            apparentTemperature: decoded.current.apparentTemperature,
            condition: WeatherCondition(code: decoded.current.weatherCode, isDay: decoded.current.isDay),
            currentPrecipitation: decoded.current.precipitation,
            sunrise: sunrise,
            sunset: sunset,
            precipitationProbability: probability,
            precipitationSum: precipitation,
            timezone: decoded.timezone,
            fetchedAt: Date(),
            coordinate: coordinate,
            locationName: locationName,
            source: "Open-Meteo",
            sourceURL: URL(string: "https://open-meteo.com/"),
            licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")
        )
    }

    static func chinaWeather(
        _ data: Data,
        stationID: String,
        coordinate: GeoCoordinate,
        locationName: String?,
        now: Date = Date()
    ) throws -> WeatherSnapshot {
        let source = String(decoding: data, as: UTF8.self)
        let currentJSON = try ChinaWeatherAlertService.assignedJSONObject(named: "dataSK", in: source)
        let current = try JSONDecoder().decode(ChinaWeatherCurrent.self, from: Data(currentJSON.utf8))
        guard stationID.count == 9, stationID.allSatisfy(\.isNumber), current.city == stationID,
              let temperature = Double(current.temp), (-100...100).contains(temperature),
              let code = Int(current.weathercode.dropFirst()),
              current.weathercode.first == "d" || current.weathercode.first == "n"
        else { throw WeatherServiceError.invalidResponse }
        let forecastJSON = try ChinaWeatherAlertService.assignedJSONObject(named: "fc", in: source)
        let forecast = try JSONDecoder().decode(ChinaWeatherDaily.self, from: Data(forecastJSON.utf8))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let day = "\(calendar.component(.month, from: now))/\(calendar.component(.day, from: now))"
        let daily = forecast.f.first { $0.fi == day }
        let minimum = daily.flatMap { Double($0.fd) }.flatMap { (-100...100).contains($0) ? $0 : nil }
        let maximum = daily.flatMap { Double($0.fc) }.flatMap { (-100...100).contains($0) ? $0 : nil }
        return WeatherSnapshot(
            temperature: temperature,
            temperatureMin: minimum,
            temperatureMax: maximum,
            // The current feed also returns d-prefixed icons at night.
            condition: WeatherCondition(code: chinaWeatherCode(code), isDay: nil),
            timezone: "Asia/Shanghai",
            fetchedAt: now,
            coordinate: coordinate,
            locationName: locationName,
            source: AppLocalization.text("中国天气网（中国气象局）"),
            sourceURL: URL(string: "https://www.weather.com.cn/weather1d/\(current.city).shtml")
        )
    }

    static func metNorway(
        _ data: Data,
        coordinate: GeoCoordinate,
        locationName: String?,
        now: Date = Date()
    ) throws -> WeatherSnapshot {
        let response = try JSONDecoder().decode(METForecast.self, from: data)
        let formatter = ISO8601DateFormatter()
        let candidates = response.properties.timeseries.compactMap { entry in
            formatter.date(from: entry.time).map { (entry: entry, date: $0) }
        }
        guard response.properties.meta.units["air_temperature"] == "celsius",
              let match = candidates.last(where: { $0.date <= now }),
              now.timeIntervalSince(match.date) < 3600,
              (-100...100).contains(match.entry.data.instant.details.airTemperature),
              let symbol = (match.entry.data.nextOneHour ?? match.entry.data.nextSixHours ?? match.entry.data.nextTwelveHours)?.summary.symbolCode,
              !symbol.isEmpty
        else { throw WeatherServiceError.invalidResponse }
        return WeatherSnapshot(
            temperature: match.entry.data.instant.details.airTemperature,
            condition: WeatherCondition(code: metWeatherCode(symbol), isDay: !symbol.hasSuffix("_night")),
            timezone: "UTC",
            fetchedAt: match.date,
            coordinate: coordinate,
            locationName: locationName,
            source: "MET Norway",
            sourceURL: URL(string: "https://www.met.no/"),
            licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")
        )
    }

    private static func chinaWeatherCode(_ code: Int) -> Int {
        switch code {
        case 0: 0
        case 1: 2
        case 2: 3
        case 3: 80
        case 4, 5: 95
        case 6, 7, 8, 9, 10, 11, 12, 21, 22, 23, 24, 25: 63
        case 13: 85
        case 14, 15, 16, 17, 26, 27, 28: 73
        case 18, 20, 29, 30, 31, 53: 45
        case 19: 66
        default: -1
        }
    }

    private static func metWeatherCode(_ symbol: String) -> Int {
        if symbol.contains("thunder") { return 95 }
        if symbol.contains("snow") { return symbol.contains("showers") ? 85 : 73 }
        if symbol.contains("sleet") { return 66 }
        if symbol.contains("rain") { return symbol.contains("showers") ? 80 : 63 }
        switch symbol.split(separator: "_").first {
        case "clearsky": return 0
        case "fair": return 1
        case "partlycloudy": return 2
        case "cloudy": return 3
        case "fog": return 45
        default: return -1
        }
    }
}

private struct ChinaWeatherCurrent: Decodable {
    let temp: String
    let weathercode: String
    let city: String
}

private struct ChinaWeatherDaily: Decodable {
    struct Day: Decodable {
        let fc: String
        let fd: String
        let fi: String
    }
    let f: [Day]
}

private struct METForecast: Decodable {
    struct Properties: Decodable {
        struct Meta: Decodable { let units: [String: String] }
        let meta: Meta
        let timeseries: [Entry]
    }
    struct Entry: Decodable {
        struct ForecastData: Decodable {
            struct Instant: Decodable {
                struct Details: Decodable {
                    let airTemperature: Double
                    enum CodingKeys: String, CodingKey { case airTemperature = "air_temperature" }
                }
                let details: Details
            }
            struct Period: Decodable {
                struct Summary: Decodable {
                    let symbolCode: String
                    enum CodingKeys: String, CodingKey { case symbolCode = "symbol_code" }
                }
                let summary: Summary
            }
            let instant: Instant
            let nextOneHour: Period?
            let nextSixHours: Period?
            let nextTwelveHours: Period?
            enum CodingKeys: String, CodingKey {
                case instant
                case nextOneHour = "next_1_hours"
                case nextSixHours = "next_6_hours"
                case nextTwelveHours = "next_12_hours"
            }
        }
        let time: String
        let data: ForecastData
    }
    let properties: Properties
}
