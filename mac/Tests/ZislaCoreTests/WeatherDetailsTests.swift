import Foundation
import Testing
@testable import ZislaCore

struct WeatherDetailsTests {
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
            "precipitation_probability_max":[82],
            "precipitation_sum":[18.5],
            "weather_code":[95]
          }
        }
        """

        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: Data(json.utf8))

        #expect(response.current.precipitation == 1.5)
        #expect(response.daily?.sunrise.first == "2026-07-23T05:04")
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
