import Foundation
import Testing
@testable import ZislaKit
@testable import ZislaCore

struct WeatherTemperatureRangeTests {
    @MainActor
    @Test
    func weatherServiceRequestsAndCarriesDailyTemperatureRange() async throws {
        WeatherServiceURLProtocol.reset()
        WeatherServiceURLProtocol.responseData = Data(
            #"{"timezone":"Asia/Shanghai","current":{"time":"2026-07-23T10:45","temperature_2m":28.5,"apparent_temperature":30.2,"weather_code":2,"is_day":1,"precipitation":0},"daily":{"sunrise":["2026-07-23T05:04"],"sunset":["2026-07-23T18:56"],"temperature_2m_min":[24.1],"temperature_2m_max":[33.8],"precipitation_probability_max":[10],"precipitation_sum":[0]}}"#.data(using: .utf8)!
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WeatherServiceURLProtocol.self]
        let service = WeatherService(
            session: URLSession(configuration: configuration),
            alertProvider: StubOfficialWeatherAlertProvider()
        )

        let snapshot = try await service.fetch(latitude: 31.2, longitude: 121.4)

        let request = try #require(WeatherServiceURLProtocol.lastRequest)
        let dailyQuery = try #require(
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first {
                $0.name == "daily"
            }?.value
        )
        #expect(dailyQuery.contains("temperature_2m_min"))
        #expect(dailyQuery.contains("temperature_2m_max"))
        #expect(snapshot.temperatureMin == 24.1)
        #expect(snapshot.temperatureMax == 33.8)
    }

    @Test
    func weatherSnapshotIncludesTemperatureRange() {
        let snapshot = WeatherSnapshot(
            temperature: 28.5,
            temperatureMin: 24.1,
            temperatureMax: 33.8,
            apparentTemperature: 30.2,
            condition: WeatherCondition(code: 2, isDay: true),
            timezone: "Asia/Shanghai",
            fetchedAt: Date(timeIntervalSince1970: 0),
            coordinate: GeoCoordinate(latitude: 31.23, longitude: 121.47)
        )

        #expect(snapshot.temperatureMin == 24.1)
        #expect(snapshot.temperatureMax == 33.8)
        #expect(snapshot.temperature == 28.5)
    }

    @Test
    func weatherSnapshotAllowsMissingTemperatureRange() {
        let snapshot = WeatherSnapshot(
            temperature: 28.5,
            apparentTemperature: 30.2,
            condition: WeatherCondition(code: 0, isDay: true),
            timezone: "Asia/Shanghai",
            fetchedAt: Date(timeIntervalSince1970: 0),
            coordinate: GeoCoordinate(latitude: 31.23, longitude: 121.47)
        )

        #expect(snapshot.temperatureMin == nil)
        #expect(snapshot.temperatureMax == nil)
        #expect(snapshot.temperature == 28.5)
    }
}

private struct StubOfficialWeatherAlertProvider: OfficialWeatherAlertProviding {
    func fetchOfficialAlerts(
        latitude: Double,
        longitude: Double,
        locationName: String?
    ) async throws -> [WeatherAlert] {
        []
    }
}

private final class WeatherServiceURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var responseData = Data()

    nonisolated static override func canInit(with request: URLRequest) -> Bool { true }

    nonisolated static override func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    @MainActor
    static func reset() {
        lastRequest = nil
        responseData = Data()
    }
}
