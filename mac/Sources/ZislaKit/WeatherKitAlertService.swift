import CoreLocation
import Foundation
import ZislaCore
import WeatherKit

public protocol OfficialWeatherAlertProviding: Sendable {
    func fetchOfficialAlerts(
        latitude: Double,
        longitude: Double,
        locationName: String?
    ) async throws -> [ZislaCore.WeatherAlert]
}

public enum WeatherAlertServiceError: Error, LocalizedError, Sendable {
    case invalidCoordinates

    public var errorDescription: String? {
        switch self {
        case .invalidCoordinates: "天气位置坐标无效"
        }
    }
}

public actor WeatherKitAlertService: OfficialWeatherAlertProviding {
    public init() {}

    public func fetchOfficialAlerts(
        latitude: Double,
        longitude: Double,
        locationName _: String?
    ) async throws -> [ZislaCore.WeatherAlert] {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw WeatherAlertServiceError.invalidCoordinates
        }
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let alerts = try await WeatherKit.WeatherService.shared.weather(
            for: location,
            including: .alerts
        ) ?? []
        return alerts.map { alert in
            ZislaCore.WeatherAlert(
                severity: ZislaCore.WeatherAlert.Severity(rawValue: alert.severity.rawValue) ?? .moderate,
                source: alert.source,
                summary: alert.summary,
                region: alert.region,
                detailsURL: alert.detailsURL,
                updatedAt: alert.metadata.date,
                expiresAt: alert.metadata.expirationDate
            )
        }
    }
}

public enum ChinaWeatherAlertServiceError: Error, LocalizedError, Sendable {
    case locationNameUnavailable
    case stationNotFound
    case invalidResponse
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .locationNameUnavailable: "无法匹配中国天气网的地区"
        case .stationNotFound: "未找到中国天气网站点"
        case .invalidResponse: "中国天气网返回了无效预警数据"
        case .responseTooLarge: "中国天气网响应超过大小限制"
        }
    }
}

public actor DefaultOfficialWeatherAlertService: OfficialWeatherAlertProviding {
    private let chinaWeather: any OfficialWeatherAlertProviding
    private let weatherKit: any OfficialWeatherAlertProviding

    public init(
        chinaWeather: (any OfficialWeatherAlertProviding)? = nil,
        weatherKit: (any OfficialWeatherAlertProviding)? = nil
    ) {
        self.chinaWeather = chinaWeather ?? ChinaWeatherAlertService()
        self.weatherKit = weatherKit ?? WeatherKitAlertService()
    }

    public func fetchOfficialAlerts(
        latitude: Double,
        longitude: Double,
        locationName: String?
    ) async throws -> [ZislaCore.WeatherAlert] {
        do {
            return try await chinaWeather.fetchOfficialAlerts(
                latitude: latitude,
                longitude: longitude,
                locationName: locationName
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await weatherKit.fetchOfficialAlerts(
                latitude: latitude,
                longitude: longitude,
                locationName: locationName
            )
        }
    }
}

public actor ChinaWeatherAlertService: OfficialWeatherAlertProviding {
    private static let maxResponseSize = 1_048_576
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration)
        }
    }

    public func fetchOfficialAlerts(
        latitude: Double,
        longitude: Double,
        locationName: String?
    ) async throws -> [ZislaCore.WeatherAlert] {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw WeatherAlertServiceError.invalidCoordinates
        }
        guard let locationName, !locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChinaWeatherAlertServiceError.locationNameUnavailable
        }
        let stationID = try await fetchStationID(locationName: locationName)
        return try await fetchAlerts(stationID: stationID, region: locationName)
    }

    private func fetchStationID(locationName: String) async throws -> String {
        for query in Self.searchQueries(for: locationName) {
            var components = URLComponents(string: "https://toy1.weather.com.cn/search")!
            components.queryItems = [URLQueryItem(name: "cityname", value: query)]
            guard let url = components.url else { continue }
            let data = try await request(url)
            if let stationID = try Self.stationID(in: data, query: query, locationName: locationName) {
                return stationID
            }
        }
        throw ChinaWeatherAlertServiceError.stationNotFound
    }

    private func fetchAlerts(stationID: String, region: String) async throws -> [ZislaCore.WeatherAlert] {
        var components = URLComponents(string: "https://d1.weather.com.cn/dingzhi/\(stationID).html")!
        components.queryItems = [URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970)))]
        guard let url = components.url else { throw ChinaWeatherAlertServiceError.invalidResponse }
        let data = try await request(url)
        return try Self.alerts(in: data, stationID: stationID, region: region)
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("zisla/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.weather.com.cn/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard data.count <= Self.maxResponseSize else {
            throw ChinaWeatherAlertServiceError.responseTooLarge
        }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw ChinaWeatherAlertServiceError.invalidResponse
        }
        return data
    }

    static func stationID(in data: Data, query: String, locationName: String) throws -> String? {
        let source = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.first == "(", source.last == ")" else {
            throw ChinaWeatherAlertServiceError.invalidResponse
        }
        let json = String(source.dropFirst().dropLast())
        let entries = try JSONDecoder().decode([ChinaWeatherSearchEntry].self, from: Data(json.utf8))
        let stations = entries.compactMap(ChinaWeatherStation.init)
        let normalizedQuery = normalizedPlaceName(query)
        let exactMatches = stations.filter { normalizedPlaceName($0.city) == normalizedQuery }
        if let provinceMatch = exactMatches.first(where: { locationName.contains($0.province) }) {
            return provinceMatch.id
        }
        return exactMatches.first?.id
    }

    static func alerts(in data: Data, stationID: String, region: String) throws -> [ZislaCore.WeatherAlert] {
        let source = String(decoding: data, as: UTF8.self)
        let json = try assignedJSONObject(named: "alarmDZ", in: source)
        let response = try JSONDecoder().decode(ChinaWeatherAlertResponse.self, from: Data(json.utf8))
        return response.w.map { alert in
            let updatedAt = publicationDate(from: alert.w8) ?? Date()
            let detailURL = alert.w11.flatMap { file in
                URL(string: "https://www.weather.com.cn/alarm/newalarmcontent.shtml?file=\(file)")
            } ?? URL(string: "https://www.weather.com.cn/weather1d/\(stationID).shtml")!
            return ZislaCore.WeatherAlert(
                severity: severity(for: alert.w7),
                source: "中国天气网（中国气象局）",
                summary: alert.w13 ?? [alert.w5, alert.w7].compactMap { $0 }.joined(separator: " "),
                region: region,
                detailsURL: detailURL,
                updatedAt: updatedAt,
                expiresAt: nil
            )
        }
    }

    private static func searchQueries(for locationName: String) -> [String] {
        var queries = [locationName]
        for separator in ["特别行政区", "自治区", "省"] {
            if let range = locationName.range(of: separator) {
                queries.append(String(locationName[range.upperBound...]))
            }
        }
        if let range = locationName.range(of: "市") {
            queries.append(String(locationName[..<range.lowerBound]))
        }
        return queries
            .map(normalizedPlaceName)
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, query in
                if !result.contains(query) { result.append(query) }
            }
    }

    private static func normalizedPlaceName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "特别行政区", with: "")
            .replacingOccurrences(of: "自治区", with: "")
            .replacingOccurrences(of: "省", with: "")
            .replacingOccurrences(of: "市", with: "")
    }

    private static func assignedJSONObject(named variable: String, in source: String) throws -> String {
        guard let variableRange = source.range(of: variable),
              let objectStart = source[variableRange.upperBound...].firstIndex(of: "{")
        else {
            throw ChinaWeatherAlertServiceError.invalidResponse
        }
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        for index in source[objectStart...].indices {
            let character = source[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }
            if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[objectStart...index])
                }
            }
        }
        throw ChinaWeatherAlertServiceError.invalidResponse
    }

    private static func publicationDate(from value: String?) -> Date? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        guard digits.count >= 12 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter.date(from: String(digits.prefix(12)))
    }

    private static func severity(for value: String?) -> ZislaCore.WeatherAlert.Severity {
        switch value ?? "" {
        case let level where level.contains("红") || level == "04": .extreme
        case let level where level.contains("橙") || level == "03": .severe
        case let level where level.contains("黄") || level == "02": .moderate
        default: .minor
        }
    }
}

private struct ChinaWeatherSearchEntry: Decodable {
    let ref: String
}

private struct ChinaWeatherStation {
    let id: String
    let city: String
    let province: String

    init?(_ entry: ChinaWeatherSearchEntry) {
        let components = entry.ref.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 9,
              components[0].allSatisfy(\.isNumber),
              components[0].count == 9
        else {
            return nil
        }
        id = components[0]
        city = components[2]
        province = components[8]
    }
}

private struct ChinaWeatherAlertResponse: Decodable {
    let w: [ChinaWeatherAlertPayload]
}

private struct ChinaWeatherAlertPayload: Decodable {
    let w5: String?
    let w7: String?
    let w8: String?
    let w11: String?
    let w13: String?
}
