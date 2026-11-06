import Foundation
import ZislaCore

public struct WeatherSnapshot: Equatable, Sendable {
    public var temperature: Double
    public var temperatureMin: Double?
    public var temperatureMax: Double?
    public var apparentTemperature: Double?
    public var condition: WeatherCondition
    public var currentPrecipitation: Double?
    public var sunrise: String
    public var sunset: String
    public var precipitationProbability: Int?
    public var precipitationSum: Double?
    public var officialAlerts: [WeatherAlert]
    public var alertErrorDescription: String?
    public var timezone: String
    public var fetchedAt: Date
    /// Location-friendly display name for UI; nil if not resolved.
    public var locationName: String?
    /// Coordinates of the query this snapshot corresponds to.
    public var coordinate: GeoCoordinate
    public var source: String?
    public var sourceURL: URL?
    public var licenseURL: URL?

    public var expiresAt: Date { fetchedAt.addingTimeInterval(3600) }

    public init(
        temperature: Double,
        temperatureMin: Double? = nil,
        temperatureMax: Double? = nil,
        apparentTemperature: Double? = nil,
        condition: WeatherCondition,
        currentPrecipitation: Double? = nil,
        sunrise: String = "",
        sunset: String = "",
        precipitationProbability: Int? = nil,
        precipitationSum: Double? = nil,
        officialAlerts: [WeatherAlert] = [],
        alertErrorDescription: String? = nil,
        timezone: String,
        fetchedAt: Date,
        coordinate: GeoCoordinate,
        locationName: String? = nil,
        source: String? = nil,
        sourceURL: URL? = nil,
        licenseURL: URL? = nil
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
        self.source = source
        self.sourceURL = sourceURL
        self.licenseURL = licenseURL
    }
}

public enum WeatherServiceError: Error, LocalizedError, Equatable, Sendable {
    case invalidCoordinates
    case invalidResponse
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidCoordinates: AppLocalization.text("天气位置坐标无效")
        case .invalidResponse: AppLocalization.text("天气服务返回了无效响应")
        case .responseTooLarge: AppLocalization.text("天气响应超过大小限制")
        }
    }
}

public actor WeatherService {
    private let session: URLSession
    private let alertProvider: any OfficialWeatherAlertProviding
    private let countryGeocoder: (any PlaceGeocoding)?
    private let now: @Sendable () -> Date
    private let metCache = URLCache(memoryCapacity: 8 * 1_048_576, diskCapacity: 0)

    public init(
        session: URLSession? = nil,
        alertProvider: (any OfficialWeatherAlertProviding)? = nil,
        countryGeocoder: (any PlaceGeocoding)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
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
        self.countryGeocoder = countryGeocoder
        self.now = now
    }

    public func fetch(
        latitude: Double,
        longitude: Double,
        locationName: String? = nil,
        isoCountryCode: String? = nil
    ) async throws -> WeatherSnapshot {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw WeatherServiceError.invalidCoordinates
        }
        try Task.checkCancellation()
        var country = isoCountryCode
        if country == nil {
            do {
                let geocoder = if let countryGeocoder {
                    countryGeocoder
                } else {
                    await MainActor.run { CLGeocoderPlaceGeocoder() as any PlaceGeocoding }
                }
                country = try await geocoder.reverseGeocode(latitude: latitude, longitude: longitude)
                    .first?.isoCountryCode
            } catch {
                try Self.rethrowCancellation(error)
            }
        }
        let providers: [WeatherForecastSource] = ["CN", "HK", "MO", "TW"].contains(country?.uppercased() ?? "")
            ? [.chinaWeather, .openMeteo, .metNorway] : [.openMeteo, .metNorway]
        var forecast: WeatherSnapshot?
        var lastError: Error = WeatherServiceError.invalidResponse
        for provider in providers {
            try Task.checkCancellation()
            do {
                forecast = try await fetchForecast(
                    provider, latitude: latitude, longitude: longitude, locationName: locationName
                )
                break
            } catch {
                try Self.rethrowCancellation(error)
                lastError = error is DecodingError ? WeatherServiceError.invalidResponse : error
            }
        }
        guard var snapshot = forecast else { throw lastError }
        try Task.checkCancellation()
        do {
            snapshot.officialAlerts = try await alertProvider.fetchOfficialAlerts(
                latitude: latitude, longitude: longitude, locationName: locationName
            )
        } catch {
            try Self.rethrowCancellation(error)
            snapshot.alertErrorDescription = AppLocalization.text("无法读取官方天气预警：%@", error.localizedDescription)
        }
        try Task.checkCancellation()
        return snapshot
    }

    private func fetchForecast(
        _ provider: WeatherForecastSource,
        latitude: Double,
        longitude: Double,
        locationName: String?
    ) async throws -> WeatherSnapshot {
        let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
        switch provider {
        case .chinaWeather:
            guard let locationName, !locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ChinaWeatherAlertServiceError.locationNameUnavailable
            }
            let stationID = try await ChinaWeatherAlertService(session: session).fetchStationID(locationName: locationName)
            let data = try await request(
                URL(string: "https://d1.weather.com.cn/weather_index/\(stationID).html")!,
                referer: "https://www.weather.com.cn/"
            )
            return try WeatherForecastDecoder.chinaWeather(
                data, stationID: stationID, coordinate: coordinate, locationName: locationName, now: now()
            )
        case .openMeteo:
            var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: String(latitude)),
                URLQueryItem(name: "longitude", value: String(longitude)),
                URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,precipitation"),
                URLQueryItem(name: "daily", value: "temperature_2m_min,temperature_2m_max,sunrise,sunset,precipitation_probability_max,precipitation_sum"),
                URLQueryItem(name: "timezone", value: "auto"),
            ]
            let data = try await request(components.url!)
            return try WeatherForecastDecoder.openMeteo(data, coordinate: coordinate, locationName: locationName)
        case .metNorway:
            var components = URLComponents(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact")!
            components.queryItems = [
                URLQueryItem(name: "lat", value: String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), latitude)),
                URLQueryItem(name: "lon", value: String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), longitude)),
            ]
            return try await requestMET(components.url!, coordinate: coordinate, locationName: locationName)
        }
    }

    private func requestMET(_ url: URL, coordinate: GeoCoordinate, locationName: String?) async throws -> WeatherSnapshot {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("zisla/1.0 github.com/wzz6423/zisla", forHTTPHeaderField: "User-Agent")
        let cached = metCache.cachedResponse(for: request)
        if let cached,
           let expires = cached.userInfo?["expiresAt"] as? Date,
           now() < expires
        {
            return try WeatherForecastDecoder.metNorway(
                cached.data, coordinate: coordinate, locationName: locationName, now: now()
            )
        }
        if let response = cached?.response as? HTTPURLResponse,
           let modified = response.value(forHTTPHeaderField: "Last-Modified")
        {
            request.setValue(modified, forHTTPHeaderField: "If-Modified-Since")
        }
        let (data, rawResponse) = try await session.data(for: request)
        try Task.checkCancellation()
        guard data.count <= 1_048_576 else { throw WeatherServiceError.responseTooLarge }
        guard let response = rawResponse as? HTTPURLResponse else { throw WeatherServiceError.invalidResponse }
        let body: Data
        if response.statusCode == 304, let cached {
            body = cached.data
        } else if response.statusCode == 200 {
            body = data
        } else {
            throw WeatherServiceError.invalidResponse
        }
        let snapshot = try WeatherForecastDecoder.metNorway(
            body, coordinate: coordinate, locationName: locationName, now: now()
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let expiration = response.value(forHTTPHeaderField: "Expires").flatMap(formatter.date(from:))
            ?? now()
        let cacheResponse = response.statusCode == 304 ? cached!.response : response
        metCache.storeCachedResponse(
            CachedURLResponse(response: cacheResponse, data: body, userInfo: ["expiresAt": expiration], storagePolicy: .allowedInMemoryOnly),
            for: request
        )
        return snapshot
    }

    private func request(_ url: URL, referer: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("zisla/1.0 github.com/wzz6423/zisla", forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard data.count <= 1_048_576 else { throw WeatherServiceError.responseTooLarge }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw WeatherServiceError.invalidResponse
        }
        return data
    }

    private static func rethrowCancellation(_ error: Error) throws {
        if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
            throw CancellationError()
        }
    }
}

private enum WeatherForecastSource {
    case chinaWeather, openMeteo, metNorway
}
