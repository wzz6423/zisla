import Foundation
import Testing
@testable import ZislaCore

struct WeatherDetailsTests {
    @Test(arguments: [0, 1, 2], [Bool?.none, .some(false), .some(true)])
    func conditionsRetainKnownDaylightAndUseWeatherSymbolsWhenUnknown(code: Int, isDay: Bool?) {
        let condition = WeatherCondition(code: code, isDay: isDay)
        let expected: String
        switch (code, isDay) {
        case (0, .some(false)): expected = "moon.stars.fill"
        case (1, .some(false)): expected = "moon.fill"
        case (2, .some(false)): expected = "cloud.moon.fill"
        case (2, .some(true)): expected = "cloud.sun.fill"
        case (2, .none): expected = "cloud.sun.fill"
        case (_, .some(true)): expected = "sun.max.fill"
        default: expected = "sun.max.fill"
        }
        #expect(condition.symbolName == expected)
    }

    @Test(arguments: [Bool?.none, .some(false), .some(true)])
    func precipitationAndObscurationCodesRetainTheirWeatherType(isDay: Bool?) {
        let conditions: [(Int, String, String)] = [
            (3, "阴", "cloud.fill"), (45, "雾", "cloud.fog.fill"), (48, "雾", "cloud.fog.fill"),
            (51, "毛毛雨", "cloud.drizzle.fill"), (53, "毛毛雨", "cloud.drizzle.fill"),
            (55, "毛毛雨", "cloud.drizzle.fill"), (56, "冻毛毛雨", "cloud.sleet.fill"),
            (57, "冻毛毛雨", "cloud.sleet.fill"), (61, "小雨", "cloud.drizzle.fill"),
            (63, "中雨", "cloud.rain.fill"), (65, "大雨", "cloud.heavyrain.fill"),
            (66, "冻雨", "cloud.sleet.fill"), (67, "冻雨", "cloud.sleet.fill"),
            (71, "小雪", "snowflake"), (73, "中雪", "cloud.snow.fill"),
            (75, "大雪", "cloud.snow.fill"), (77, "雪粒", "snowflake"),
            (80, "小阵雨", "cloud.drizzle.fill"), (81, "阵雨", "cloud.rain.fill"),
            (82, "强阵雨", "cloud.heavyrain.fill"), (85, "小阵雪", "snowflake"),
            (86, "强阵雪", "cloud.snow.fill"), (95, "雷阵雨", "cloud.bolt.rain.fill"),
            (97, "强雷阵雨", "cloud.bolt.rain.fill"),
            (96, "雷阵雨伴冰雹", "cloud.hail.fill"), (99, "雷阵雨伴冰雹", "cloud.hail.fill"),
        ]
        for (code, summary, symbol) in conditions {
            let condition = WeatherCondition(code: code, isDay: isDay)
            #expect(condition.summary == AppLocalization.text(summary), "Weather code \(code) must retain its description")
            #expect(condition.symbolName == symbol, "Weather code \(code) must use the corresponding weather icon")
        }
    }

    @Test(arguments: [-1, 4, 100, Int.min, Int.max], [Bool?.none, .some(false), .some(true)])
    func unsupportedCodesRemainUnknown(code: Int, isDay: Bool?) {
        let condition = WeatherCondition(code: code, isDay: isDay)
        #expect(condition.summary == AppLocalization.text("天气未知"))
        #expect(condition.symbolName == "questionmark.circle")
    }

    @Test
    func openMeteoResponseDecodesDailyWeatherDetails() throws {
        let json = """
        {
          "timezone":"Asia/Shanghai",
          "current":{
            "time":"2026-07-23T10:45",
            "temperature_2m":32.7,
            "apparent_temperature":40.5,
            "weather_code":95,
            "is_day":1,
            "precipitation":1.5
          },
          "daily":{
            "sunrise":["2026-07-23T05:04"],
            "sunset":["2026-07-23T18:56"],
            "temperature_2m_min":[24.1],
            "temperature_2m_max":[33.8],
            "precipitation_probability_max":[82],
            "precipitation_sum":[18.5],
            "weather_code":[95]
          }
        }
        """

        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: Data(json.utf8))

        #expect(response.current.precipitation == 1.5)
        #expect(response.daily?.sunrise.first == "2026-07-23T05:04")
        #expect(response.daily?.temperatureMin?.first == 24.1)
        #expect(response.daily?.temperatureMax?.first == 33.8)
        #expect(response.daily?.precipitationProbabilityMax.first == 82)
        #expect(response.daily?.precipitationSum.first == 18.5)
    }

    @Test
    func weatherAlertPreservesOfficialPublisherPayload() {
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        let expiresAt = Date(timeIntervalSince1970: 2_000)
        let alert = WeatherAlert(
            severity: .severe,
            source: "National Weather Service",
            summary: "Severe Thunderstorm Warning",
            region: "District of Columbia",
            detailsURL: URL(string: "https://weather.gov/alerts/123")!,
            updatedAt: updatedAt,
            expiresAt: expiresAt
        )

        #expect(alert.severity.localizedTitle == "严重")
        #expect(alert.source == "National Weather Service")
        #expect(alert.summary == "Severe Thunderstorm Warning")
        #expect(alert.expiresAt == expiresAt)
        #expect(alert.id.contains("weather.gov/alerts/123"))
    }
}
