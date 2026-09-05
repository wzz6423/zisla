import Foundation
import ZislaCore

public struct WeatherSnapshot: Equatable, Sendable {
    public var temperature: Double
    public var temperatureMin: Double?
    public var temperatureMax: Double?
    public var apparentTemperature: Double
    public var condition: WeatherCondition
    public var currentPrecipitation: Double
    public var sunrise: String
    public var sunset: String
    public var precipitationProbability: Int
    public var precipitationSum: Double
    public var officialAlerts: [WeatherAlert]
    public var alertErrorDescription: String?
    public var timezone: String
    public var fetchedAt: Date
    /// Location-friendly display name for UI; nil if not resolved.
    public var locationName: String?
    /// Coordinates of the query this snapshot corresponds to.
    public var coordinate: GeoCoordinate

    public init(
        temperature: Double,
        temperatureMin: Double? = nil,
        temperatureMax: Double? = nil,
        apparentTemperature: Double,
        condition: WeatherCondition,
        currentPrecipitation: Double = 0,
        sunrise: String = "",
        sunset: String = "",
        precipitationProbability: Int = 0,
        precipitationSum: Double = 0,
        officialAlerts: [WeatherAlert] = [],
        alertErrorDescription: String? = nil,
        timezone: String,
        fetchedAt: Date,
        coordinate: GeoCoordinate,
        locationName: String? = nil
    ) {
        self.temperature = temperature
        self.temperatureMin = temperatureMin
        self.temperatureMax = temperatureMax
        self.apparentTemperature = apparentTemperature
        self.condition = condition
        self.currentPrecipitation = currentPrecipitation
        self.sunrise = sunrise
        self.sunset = sunset
        self.precipitationProbability = precipitationProbability
        self.precipitationSum = precipitationSum
        self.officialAlerts = officialAlerts
        self.alertErrorDescription = alertErrorDescription
        self.timezone = timezone
        self.fetchedAt = fetchedAt
        self.coordinate = coordinate
        self.locationName = locationName
    }
}

public enum WeatherServiceError: Error, LocalizedError, Sendable {
    case invalidCoordinates
    case invalidResponse
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidCoordinates: "天气位置坐标无效"
        case .invalidResponse: "天气服务返回了无效响应"
        case .responseTooLarge: "天气响应超过大小限制"
        }
    }
}

public actor WeatherService {
    private let session: URLSession
    private let alertProvider: any OfficialWeatherAlertProviding

    public init(
        session: URLSession? = nil,
        alertProvider: (any OfficialWeatherAlertProviding)? = nil
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration)
        }
        self.alertProvider = alertProvider ?? DefaultOfficialWeatherAlertService()
    }

    public func fetch(
        latitude: Double,
        longitude: Double,
        locationName: String? = nil
    ) async throws -> WeatherSnapshot {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw WeatherServiceError.invalidCoordinates
        }
        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else {
            throw WeatherServiceError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,weather_code,is_day,precipitation"
            ),
            URLQueryItem(
                name: "daily",
                value: "temperature_2m_min,temperature_2m_max,sunrise,sunset,precipitation_probability_max,precipitation_sum"
            ),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else { throw WeatherServiceError.invalidCoordinates }

        var request = URLRequest(url: url)
        request.setValue("zisla/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard data.count <= 1_048_576 else { throw WeatherServiceError.responseTooLarge }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw WeatherServiceError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        guard
            let daily = decoded.daily,
            let sunrise = daily.sunrise.first,
            let sunset = daily.sunset.first,
            let precipitationProbability = daily.precipitationProbabilityMax.first,
            let precipitationSum = daily.precipitationSum.first
        else {
            throw WeatherServiceError.invalidResponse
        }
        let officialAlerts: [WeatherAlert]
        let alertErrorDescription: String?
        do {
            officialAlerts = try await alertProvider.fetchOfficialAlerts(
                latitude: latitude,
                longitude: longitude,
                locationName: locationName
            )
            alertErrorDescription = nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            officialAlerts = []
            alertErrorDescription = AppLocalization.text("无法读取官方天气预警：%@", error.localizedDescription)
        }
        return WeatherSnapshot(
            temperature: decoded.current.temperature,
            temperatureMin: decoded.daily?.temperatureMin?.first,
            temperatureMax: decoded.daily?.temperatureMax?.first,
            apparentTemperature: decoded.current.apparentTemperature,
            condition: WeatherCondition(
                code: decoded.current.weatherCode,
                isDay: decoded.current.isDay
            ),
            currentPrecipitation: decoded.current.precipitation,
            sunrise: sunrise,
            sunset: sunset,
            precipitationProbability: precipitationProbability,
            precipitationSum: precipitationSum,
            officialAlerts: officialAlerts,
            alertErrorDescription: alertErrorDescription,
            timezone: decoded.timezone,
            fetchedAt: Date(),
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
            locationName: locationName
        )
    }
}
