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
              current.weathercode.first == "d" || current.weathercode.first == "n",
              let description = current.weather, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            condition: WeatherCondition(
                summary: AppLocalization.text(description), symbolName: chinaWeatherSymbol(code)
            ),
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
            condition: metWeatherCondition(symbol),
            timezone: "UTC",
            fetchedAt: match.date,
            coordinate: coordinate,
            locationName: locationName,
            source: "MET Norway",
            sourceURL: URL(string: "https://www.met.no/"),
            licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")
        )
    }

    private static func chinaWeatherSymbol(_ code: Int) -> String {
        switch code {
        // The provider's d/n prefix is unreliable, so clear skies use a condition-only sun icon.
        case 0: "sun.max.fill"
        case 1: "cloud.sun.fill"
        case 2: "cloud.fill"
        case 3, 8, 21, 301: "cloud.rain.fill"
        case 4: "cloud.bolt.rain.fill"
        case 5: "cloud.hail.fill"
        case 6, 19: "cloud.sleet.fill"
        case 7: "cloud.drizzle.fill"
        case 9...12, 22...25: "cloud.heavyrain.fill"
        case 13, 15, 16, 26, 27, 33, 302: "cloud.snow.fill"
        case 14: "snowflake"
        case 17, 28: "wind.snow"
        case 18, 32, 49, 57, 58: "cloud.fog.fill"
        case 20, 29...31: "sun.dust.fill"
        case 53...56: "sun.haze.fill"
        default: "questionmark.circle"
        }
    }

    private static func metWeatherCondition(_ symbol: String) -> WeatherCondition {
        let isDay: Bool? = symbol.hasSuffix("_night") ? false : nil
        let description: String
        let icon: String
        switch symbol.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)[0] {
        case "clearsky": return WeatherCondition(code: 0, isDay: isDay)
        case "fair": return WeatherCondition(code: 1, isDay: isDay)
        case "partlycloudy": return WeatherCondition(code: 2, isDay: isDay)
        case "cloudy": return WeatherCondition(code: 3, isDay: isDay)
        case "fog": return WeatherCondition(code: 45, isDay: isDay)
        case "lightrain": (description, icon) = ("小雨", "cloud.drizzle.fill")
        case "rain": (description, icon) = ("雨", "cloud.rain.fill")
        case "heavyrain": (description, icon) = ("大雨", "cloud.heavyrain.fill")
        case "lightrainshowers": (description, icon) = ("小阵雨", "cloud.drizzle.fill")
        case "rainshowers": (description, icon) = ("阵雨", "cloud.rain.fill")
        case "heavyrainshowers": (description, icon) = ("强阵雨", "cloud.heavyrain.fill")
        case "lightsnow": (description, icon) = ("小雪", "snowflake")
        case "snow": (description, icon) = ("雪", "cloud.snow.fill")
        case "heavysnow": (description, icon) = ("大雪", "cloud.snow.fill")
        case "lightsnowshowers": (description, icon) = ("小阵雪", "snowflake")
        case "snowshowers": (description, icon) = ("阵雪", "cloud.snow.fill")
        case "heavysnowshowers": (description, icon) = ("强阵雪", "cloud.snow.fill")
        case "lightsleet": (description, icon) = ("小雨夹雪", "cloud.sleet.fill")
        case "sleet": (description, icon) = ("雨夹雪", "cloud.sleet.fill")
        case "heavysleet": (description, icon) = ("强雨夹雪", "cloud.sleet.fill")
        case "lightsleetshowers": (description, icon) = ("小阵性雨夹雪", "cloud.sleet.fill")
        case "sleetshowers": (description, icon) = ("阵性雨夹雪", "cloud.sleet.fill")
        case "heavysleetshowers": (description, icon) = ("强阵性雨夹雪", "cloud.sleet.fill")
        case "lightrainandthunder": (description, icon) = ("小雨伴雷电", "cloud.bolt.rain.fill")
        case "rainandthunder": (description, icon) = ("雨伴雷电", "cloud.bolt.rain.fill")
        case "heavyrainandthunder": (description, icon) = ("大雨伴雷电", "cloud.bolt.rain.fill")
        case "lightrainshowersandthunder": (description, icon) = ("小阵雨伴雷电", "cloud.bolt.rain.fill")
        case "rainshowersandthunder": (description, icon) = ("阵雨伴雷电", "cloud.bolt.rain.fill")
        case "heavyrainshowersandthunder": (description, icon) = ("强阵雨伴雷电", "cloud.bolt.rain.fill")
        case "lightsnowandthunder": (description, icon) = ("小雪伴雷电", "cloud.bolt.fill")
        case "snowandthunder": (description, icon) = ("雪伴雷电", "cloud.bolt.fill")
        case "heavysnowandthunder": (description, icon) = ("大雪伴雷电", "cloud.bolt.fill")
        case "lightssnowshowersandthunder": (description, icon) = ("小阵雪伴雷电", "cloud.bolt.fill")
        case "snowshowersandthunder": (description, icon) = ("阵雪伴雷电", "cloud.bolt.fill")
        case "heavysnowshowersandthunder": (description, icon) = ("强阵雪伴雷电", "cloud.bolt.fill")
        case "lightsleetandthunder": (description, icon) = ("小雨夹雪伴雷电", "cloud.bolt.fill")
        case "sleetandthunder": (description, icon) = ("雨夹雪伴雷电", "cloud.bolt.fill")
        case "heavysleetandthunder": (description, icon) = ("强雨夹雪伴雷电", "cloud.bolt.fill")
        case "lightssleetshowersandthunder": (description, icon) = ("小阵性雨夹雪伴雷电", "cloud.bolt.fill")
        case "sleetshowersandthunder": (description, icon) = ("阵性雨夹雪伴雷电", "cloud.bolt.fill")
        case "heavysleetshowersandthunder": (description, icon) = ("强阵性雨夹雪伴雷电", "cloud.bolt.fill")
        default: return WeatherCondition(code: -1, isDay: isDay)
        }
        return WeatherCondition(summary: AppLocalization.text(description), symbolName: icon)
    }
}

private struct ChinaWeatherCurrent: Decodable {
    let temp: String
    let weather: String?
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
