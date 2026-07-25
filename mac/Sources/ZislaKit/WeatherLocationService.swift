import AppKit
import CoreLocation
import Foundation

/// 一次性定位/地理编码返回给上层的结果：坐标 + 适合 UI 展示的地区名。
public struct GeoLocation: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var displayName: String

    public init(latitude: Double, longitude: Double, displayName: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.displayName = displayName
    }
}

/// 纯坐标，隔离非 Sendable 的 `CLLocationCoordinate2D`。
public struct GeoCoordinate: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// 定位与地理编码的中文错误。
public enum WeatherLocationError: Error, LocalizedError, Equatable, Sendable {
    case authorizationDenied
    case locationUnavailable
    case emptyQuery
    case noResults
    case geocodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .authorizationDenied: "定位权限被拒绝，请在系统设置中允许访问位置"
        case .locationUnavailable: "无法获取当前位置"
        case .emptyQuery: "请输入要查询的地区名称"
        case .noResults: "未找到匹配的地区"
        case .geocodingFailed(let message): message
        }
    }
}
/// 从 `CLPlacemark` 抽取的 Sendable 快照，避免非 Sendable 类型跨隔离域。
public struct GeocodedPlace: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var name: String?
    public var locality: String?
    public var subAdministrativeArea: String?
    public var administrativeArea: String?
    public var country: String?

    public init(
        latitude: Double,
        longitude: Double,
        name: String? = nil,
        locality: String? = nil,
        subAdministrativeArea: String? = nil,
        administrativeArea: String? = nil,
        country: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.locality = locality
        self.subAdministrativeArea = subAdministrativeArea
        self.administrativeArea = administrativeArea
        self.country = country
    }

    init(placemark: CLPlacemark) {
        let coordinate = placemark.location?.coordinate
        self.latitude = coordinate?.latitude ?? 0
        self.longitude = coordinate?.longitude ?? 0
        self.name = placemark.name
        self.locality = placemark.locality
        self.subAdministrativeArea = placemark.subAdministrativeArea
        self.administrativeArea = placemark.administrativeArea
        self.country = placemark.country
    }

    /// 组装适合 UI 展示的地区名：优先市/区，必要时用省消歧，最后回退到名称/国家/坐标。
    func displayName(latitude: Double, longitude: Double) -> String {
        let city = locality ?? subAdministrativeArea
        if let city, !city.isEmpty {
            if let area = administrativeArea, !area.isEmpty, area != city {
                return "\(area)\(city)"
            }
            return city
        }
        for candidate in [administrativeArea, name, country] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return String(format: "%.4f, %.4f", latitude, longitude)
    }
}

/// 正向/反向地理编码抽象，便于测试注入 stub。
public protocol PlaceGeocoding: Sendable {
    func geocode(_ query: String) async throws -> [GeocodedPlace]
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> [GeocodedPlace]
}

/// 一次性当前位置抽象，便于测试注入 stub。
public protocol CurrentLocationProviding: Sendable {
    func requestOnce() async throws -> GeoCoordinate
}

/// 组合定位与地理编码的基础层。无状态，逻辑集中在此以便单测。
public struct WeatherLocationService: Sendable {
    private let geocoder: PlaceGeocoding
    private let locationProvider: CurrentLocationProviding

    public init(geocoder: PlaceGeocoding, locationProvider: CurrentLocationProviding) {
        self.geocoder = geocoder
        self.locationProvider = locationProvider
    }

    /// 默认接线 CoreLocation 实现；需在主线程创建。
    @MainActor
    public init() {
        self.init(
            geocoder: CLGeocoderPlaceGeocoder(),
            locationProvider: CoreLocationCurrentLocationProvider()
        )
    }

    /// 一次性获取当前位置并反向解析成地区名。
    public func currentLocation() async throws -> GeoLocation {
        let coordinate = try await locationProvider.requestOnce()
        let places = try await geocoder.reverseGeocode(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        let place = places.first
        return GeoLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            displayName: place?.displayName(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ) ?? String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
        )
    }

    /// 按地名查询坐标与展示名。
    public func search(_ query: String) async throws -> GeoLocation {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WeatherLocationError.emptyQuery }
        let places = try await geocoder.geocode(trimmed)
        guard let place = places.first else { throw WeatherLocationError.noResults }
        return GeoLocation(
            latitude: place.latitude,
            longitude: place.longitude,
            displayName: place.displayName(latitude: place.latitude, longitude: place.longitude)
        )
    }
}

/// `CLGeocoder` 的 `@MainActor` 包装：completion 内立即转 Sendable 快照。
@MainActor
final class CLGeocoderPlaceGeocoder: PlaceGeocoding {
    private let geocoder = CLGeocoder()

    nonisolated func geocode(_ query: String) async throws -> [GeocodedPlace] {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                geocoder.geocodeAddressString(query) { placemarks, error in
                    Self.resume(continuation, placemarks: placemarks, error: error)
                }
            }
        }
    }

    nonisolated func reverseGeocode(
        latitude: Double,
        longitude: Double
    ) async throws -> [GeocodedPlace] {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                // 在主隔离域内构造 CLLocation，避免非 Sendable 类型跨域捕获。
                let location = CLLocation(latitude: latitude, longitude: longitude)
                geocoder.reverseGeocodeLocation(location) { placemarks, error in
                    Self.resume(continuation, placemarks: placemarks, error: error)
                }
            }
        }
    }

    nonisolated private static func resume(
        _ continuation: CheckedContinuation<[GeocodedPlace], Error>,
        placemarks: [CLPlacemark]?,
        error: Error?
    ) {
        if let error {
            let code = (error as? CLError)?.code
            if code == .geocodeFoundNoResult || code == .geocodeFoundPartialResult {
                continuation.resume(returning: [])
            } else {
                continuation.resume(
                    throwing: WeatherLocationError.geocodingFailed(error.localizedDescription)
                )
            }
            return
        }
        continuation.resume(returning: (placemarks ?? []).map(GeocodedPlace.init(placemark:)))
    }
}

/// `CLLocationManager` 的一次性定位包装。`@MainActor` 隔离全部可变状态，delegate 回调用 `assumeIsolated`。
@MainActor
final class CoreLocationCurrentLocationProvider:
    NSObject, CurrentLocationProviding, CLLocationManagerDelegate
{
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<GeoCoordinate, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var configured = false
    private var authorizationPromptHost: NSWindow?

    nonisolated func requestOnce() async throws -> GeoCoordinate {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task { @MainActor in
                    self.start(continuation)
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.finish(.failure(CancellationError()))
            }
        }
    }

    private func start(_ continuation: CheckedContinuation<GeoCoordinate, Error>) {
        if !configured {
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            configured = true
        }
        if self.continuation != nil {
            continuation.resume(throwing: WeatherLocationError.locationUnavailable)
            return
        }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            continuation.resume(throwing: WeatherLocationError.authorizationDenied)
        case .notDetermined:
            self.continuation = continuation
            scheduleTimeout()
            authorizationPromptHost = WindowPlacement.authorizationPromptHost()
            manager.requestWhenInUseAuthorization()
        default:
            self.continuation = continuation
            scheduleTimeout()
            manager.requestLocation()
        }
    }

    private func finish(_ result: Result<GeoCoordinate, Error>) {
        guard let continuation else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        dismissAuthorizationPromptHost()
        self.continuation = nil
        continuation.resume(with: result)
    }

    private func dismissAuthorizationPromptHost() {
        authorizationPromptHost?.orderOut(nil)
        authorizationPromptHost?.close()
        authorizationPromptHost = nil
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
            self?.finish(.failure(WeatherLocationError.locationUnavailable))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // 先在 nonisolated 上下文取出 Sendable 的授权状态，避免把非 Sendable 的 manager 送入闭包。
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard continuation != nil else { return }
            switch status {
            case .denied, .restricted:
                finish(.failure(WeatherLocationError.authorizationDenied))
            case .notDetermined:
                break
            default:
                dismissAuthorizationPromptHost()
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // 先转成 Sendable 的 GeoCoordinate，再跨隔离域。
        let coordinate = locations.last.map {
            GeoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        MainActor.assumeIsolated {
            guard let coordinate else {
                finish(.failure(WeatherLocationError.locationUnavailable))
                return
            }
            finish(.success(coordinate))
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        MainActor.assumeIsolated {
            finish(.failure(WeatherLocationError.locationUnavailable))
        }
    }
}
