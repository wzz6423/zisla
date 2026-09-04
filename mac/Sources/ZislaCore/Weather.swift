import Foundation

/// Minimal decoding model for the Open-Meteo Forecast weather response.
public struct OpenMeteoResponse: Decodable, Equatable, Sendable {
    public struct Current: Decodable, Equatable, Sendable {
        public var time: String
        public var temperature: Double
        public var apparentTemperature: Double
        public var weatherCode: Int
        public var isDay: Bool
        public var precipitation: Double

        private enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case isDay = "is_day"
            case precipitation
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            time = try container.decode(String.self, forKey: .time)
            temperature = try container.decode(Double.self, forKey: .temperature)
            apparentTemperature = try container.decode(Double.self, forKey: .apparentTemperature)
            weatherCode = try container.decode(Int.self, forKey: .weatherCode)
            // Open-Meteo encodes day/night as 0/1.
            isDay = try container.decode(Int.self, forKey: .isDay) != 0
            precipitation = try container.decodeIfPresent(Double.self, forKey: .precipitation) ?? 0
        }
    }

    public struct Daily: Decodable, Equatable, Sendable {
        public var sunrise: [String]
        public var sunset: [String]
        public var temperatureMin: [Double]?
        public var temperatureMax: [Double]?
        public var precipitationProbabilityMax: [Int]
        public var precipitationSum: [Double]

        private enum CodingKeys: String, CodingKey {
            case sunrise
            case sunset
            case temperatureMin = "temperature_2m_min"
            case temperatureMax = "temperature_2m_max"
            case precipitationProbabilityMax = "precipitation_probability_max"
            case precipitationSum = "precipitation_sum"
        }
    }

    public var timezone: String
    public var current: Current
    public var daily: Daily?
}

/// Maps WMO weather codes to Chinese condition descriptions and SF Symbols; unknown codes fall back gracefully.
public struct WeatherCondition: Equatable, Sendable {
    public let summary: String
    public let symbolName: String

    public init(code: Int, isDay: Bool) {
        switch code {
        case 0:
            summary = AppLocalization.text("晴")
            symbolName = isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1:
            summary = AppLocalization.text("晴间少云")
            symbolName = isDay ? "sun.max.fill" : "moon.fill"
        case 2:
            summary = AppLocalization.text("多云")
            symbolName = isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:
            summary = AppLocalization.text("阴")
            symbolName = "cloud.fill"
        case 45, 48:
            summary = AppLocalization.text("雾")
            symbolName = "cloud.fog.fill"
        case 51, 53, 55, 56, 57:
            summary = AppLocalization.text("毛毛雨")
            symbolName = "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67:
            summary = AppLocalization.text("雨")
            symbolName = "cloud.rain.fill"
        case 71, 73, 75, 77:
            summary = AppLocalization.text("雪")
            symbolName = "cloud.snow.fill"
        case 80, 81, 82:
            summary = AppLocalization.text("阵雨")
            symbolName = "cloud.heavyrain.fill"
        case 85, 86:
            summary = AppLocalization.text("阵雪")
            symbolName = "cloud.snow.fill"
        case 95:
            summary = AppLocalization.text("雷阵雨")
            symbolName = "cloud.bolt.rain.fill"
        case 96, 99:
            summary = AppLocalization.text("雷阵雨伴冰雹")
            symbolName = "cloud.bolt.rain.fill"
        default:
            summary = AppLocalization.text("天气未知")
            symbolName = "questionmark.circle"
        }
    }
}

/// Weather alert record passed through from WeatherKit or a Chinese weather service;
/// content and source are issued by the meteorological authority.
public struct WeatherAlert: Identifiable, Equatable, Sendable {
    public enum Severity: String, Codable, CaseIterable, Sendable {
        case minor
        case moderate
        case severe
        case extreme

        public var localizedTitle: String {
            switch self {
            case .minor: "一般"
            case .moderate: "较重"
            case .severe: "严重"
            case .extreme: "极端"
            }
        }

        public var symbolName: String {
            switch self {
            case .minor: "exclamationmark.circle.fill"
            case .moderate: "exclamationmark.triangle.fill"
            case .severe, .extreme: "exclamationmark.octagon.fill"
            }
        }
    }

    public let id: String
    public let severity: Severity
    public let source: String
    public let summary: String
    public let region: String?
    public let detailsURL: URL
    public let updatedAt: Date
    public let expiresAt: Date?

    public init(
        severity: Severity,
        source: String,
        summary: String,
        region: String?,
        detailsURL: URL,
        updatedAt: Date,
        expiresAt: Date?
    ) {
        self.id = "\(detailsURL.absoluteString)|\(source)|\(summary)|\(expiresAt?.timeIntervalSince1970 ?? 0)"
        self.severity = severity
        self.source = source
        self.summary = summary
        self.region = region
        self.detailsURL = detailsURL
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
    }
}
