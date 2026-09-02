import AppKit
import CoreLocation
import Foundation

/// Result returned to callers from a one-shot location/geocoding lookup: coordinates plus a UI-friendly region name.
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

/// Plain coordinates, isolating the non-`Sendable` `CLLocationCoordinate2D`.
public struct GeoCoordinate: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Localized errors for location and geocoding.
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
/// Sendable snapshot extracted from `CLPlacemark`, avoiding non-`Sendable` types crossing isolation boundaries.
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

    /// Assembles a UI-friendly region name: prefers city/district, uses province to disambiguate when needed, falls back to name/country/coordinates.
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

/// Forward/reverse geocoding abstraction for test injection.
public protocol PlaceGeocoding: Sendable {
    func geocode(_ query: String) async throws -> [GeocodedPlace]
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> [GeocodedPlace]
}

/// One-shot current location abstraction for test injection.
public protocol CurrentLocationProviding: Sendable {
    func requestOnce() async throws -> GeoCoordinate
}

/// Foundation layer combining location and geocoding. Stateless; logic is centralised here for unit testing.
public struct WeatherLocationService: Sendable {
    private let geocoder: PlaceGeocoding
    private let locationProvider: CurrentLocationProviding

    public init(geocoder: PlaceGeocoding, locationProvider: CurrentLocationProviding) {
        self.geocoder = geocoder
        self.locationProvider = locationProvider
    }

    /// Wires up CoreLocation implementations by default; must be created on the main thread.
    @MainActor
    public init() {
        self.init(
            geocoder: CLGeocoderPlaceGeocoder(),
            locationProvider: CoreLocationCurrentLocationProvider()
        )
    }

    /// Fetches the current location once and reverse-geocodes it to a region name.
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

    /// Looks up coordinates and a display name by place name.
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

/// `@MainActor` wrapper around `CLGeocoder`: immediately converts results to `Sendable` snapshots inside the completion handler.
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
                // Construct CLLocation on the main actor to avoid capturing a non-Sendable type across isolation boundaries.
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

/// One-shot location wrapper around `CLLocationManager`. All mutable state is `@MainActor`-isolated; delegate callbacks use `assumeIsolated`.
struct CurrentLocationRequestState: Sendable {
    private(set) var token: UUID?
    private var managerIdentifier: ObjectIdentifier?

    mutating func begin(_ token: UUID, managerIdentifier: ObjectIdentifier) {
        self.token = token
        self.managerIdentifier = managerIdentifier
    }

    func token(for managerIdentifier: ObjectIdentifier) -> UUID? {
        guard self.managerIdentifier == managerIdentifier else { return nil }
        return token
    }

    mutating func claimCompletion(for token: UUID) -> Bool {
        guard self.token == token else { return false }
        self.token = nil
        managerIdentifier = nil
        return true
    }
}

@MainActor
final class CoreLocationCurrentLocationProvider:
    NSObject, CurrentLocationProviding, CLLocationManagerDelegate
{
    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<GeoCoordinate, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var requestState = CurrentLocationRequestState()
    private var authorizationPromptHost: NSWindow?

    nonisolated func requestOnce() async throws -> GeoCoordinate {
        let token = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await requestOnce(token: token)
        } onCancel: {
            Task { @MainActor in
                self.finish(.failure(CancellationError()), matching: token)
            }
        }
    }

    private func requestOnce(token: UUID) async throws -> GeoCoordinate {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            start(continuation, token: token)
        }
    }

    private func start(
        _ continuation: CheckedContinuation<GeoCoordinate, Error>,
        token: UUID
    ) {
        guard requestState.token == nil else {
            continuation.resume(throwing: WeatherLocationError.locationUnavailable)
            return
        }

        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        self.manager = manager
        self.continuation = continuation
        requestState.begin(token, managerIdentifier: ObjectIdentifier(manager))

        switch manager.authorizationStatus {
        case .denied, .restricted:
            finish(.failure(WeatherLocationError.authorizationDenied), matching: token)
        case .notDetermined:
            scheduleTimeout(for: token)
            authorizationPromptHost = WindowPlacement.authorizationPromptHost()
            manager.requestWhenInUseAuthorization()
        default:
            scheduleTimeout(for: token)
            manager.requestLocation()
        }
    }

    private func finish(_ result: Result<GeoCoordinate, Error>, matching token: UUID) {
        guard let continuation, requestState.claimCompletion(for: token) else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        manager?.delegate = nil
        manager = nil
        dismissAuthorizationPromptHost()
        self.continuation = nil
        continuation.resume(with: result)
    }

    private func dismissAuthorizationPromptHost() {
        authorizationPromptHost?.orderOut(nil)
        authorizationPromptHost?.close()
        authorizationPromptHost = nil
    }

    private func scheduleTimeout(for token: UUID) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
            self?.finish(.failure(WeatherLocationError.locationUnavailable), matching: token)
        }
    }

    private func activeRequest(
        for managerIdentifier: ObjectIdentifier
    ) -> (manager: CLLocationManager, token: UUID)? {
        guard
            let manager,
            let token = requestState.token(for: managerIdentifier)
        else { return nil }
        return (manager, token)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Extract the Sendable authorization status in a nonisolated context to avoid sending a non-Sendable manager into the closure.
        let status = manager.authorizationStatus
        let managerIdentifier = ObjectIdentifier(manager)
        MainActor.assumeIsolated {
            guard let request = activeRequest(for: managerIdentifier) else { return }
            switch status {
            case .denied, .restricted:
                finish(
                    .failure(WeatherLocationError.authorizationDenied),
                    matching: request.token
                )
            case .notDetermined:
                break
            default:
                dismissAuthorizationPromptHost()
                request.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // Convert to a Sendable GeoCoordinate before crossing isolation boundaries.
        let coordinate = locations.last.map {
            GeoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        let managerIdentifier = ObjectIdentifier(manager)
        MainActor.assumeIsolated {
            guard let request = activeRequest(for: managerIdentifier) else { return }
            guard let coordinate else {
                finish(
                    .failure(WeatherLocationError.locationUnavailable),
                    matching: request.token
                )
                return
            }
            finish(.success(coordinate), matching: request.token)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let managerIdentifier = ObjectIdentifier(manager)
        MainActor.assumeIsolated {
            guard let request = activeRequest(for: managerIdentifier) else { return }
            finish(
                .failure(WeatherLocationError.locationUnavailable),
                matching: request.token
            )
        }
    }
}
