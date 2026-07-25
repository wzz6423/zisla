import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

private struct StubGeocoder: PlaceGeocoding {
    var geocodeResult: Result<[GeocodedPlace], Error> = .success([])
    var reverseResult: Result<[GeocodedPlace], Error> = .success([])

    func geocode(_ query: String) async throws -> [GeocodedPlace] {
        try geocodeResult.get()
    }

    func reverseGeocode(latitude: Double, longitude: Double) async throws -> [GeocodedPlace] {
        try reverseResult.get()
    }
}
private struct StubLocationProvider: CurrentLocationProviding {
    var result: Result<GeoCoordinate, Error>

    func requestOnce() async throws -> GeoCoordinate {
        try result.get()
    }
}

private func makeService(
    geocoder: StubGeocoder = StubGeocoder(),
    provider: StubLocationProvider = StubLocationProvider(
        result: .success(GeoCoordinate(latitude: 0, longitude: 0))
    )
) -> WeatherLocationService {
    WeatherLocationService(geocoder: geocoder, locationProvider: provider)
}
struct WeatherLocationServiceTests {
    @Test
    func emptyQueryThrowsLocalizedError() async {
        let service = makeService()
        do {
            _ = try await service.search("   ")
            Issue.record("空查询应抛错")
        } catch {
            #expect((error as? WeatherLocationError) == .emptyQuery)
            #expect(error.localizedDescription == "请输入要查询的地区名称")
        }
    }

    @Test
    func searchWithoutMatchThrowsNoResults() async {
        let service = makeService(geocoder: StubGeocoder(geocodeResult: .success([])))
        do {
            _ = try await service.search("不存在的地方")
            Issue.record("无结果应抛错")
        } catch {
            #expect((error as? WeatherLocationError) == .noResults)
        }
    }

    @Test
    func searchReturnsCoordinateAndDisplayName() async throws {
        let place = GeocodedPlace(
            latitude: 31.2304,
            longitude: 121.4737,
            locality: "上海市",
            administrativeArea: "上海市"
        )
        let service = makeService(geocoder: StubGeocoder(geocodeResult: .success([place])))

        let result = try await service.search("上海")

        #expect(result.latitude == 31.2304)
        #expect(result.longitude == 121.4737)
        #expect(result.displayName == "上海市")
    }

    @Test
    func currentLocationReverseGeocodesCoordinate() async throws {
        let place = GeocodedPlace(
            latitude: 0,
            longitude: 0,
            locality: "海淀区",
            administrativeArea: "北京市"
        )
        let service = makeService(
            geocoder: StubGeocoder(reverseResult: .success([place])),
            provider: StubLocationProvider(
                result: .success(GeoCoordinate(latitude: 39.9, longitude: 116.3))
            )
        )

        let result = try await service.currentLocation()

        // 展示名来自反向解析，坐标来自定位。
        #expect(result.displayName == "北京市海淀区")
        #expect(result.latitude == 39.9)
        #expect(result.longitude == 116.3)
    }

    @Test
    func currentLocationFallsBackToCoordinateStringWhenNoPlacemark() async throws {
        let service = makeService(
            geocoder: StubGeocoder(reverseResult: .success([])),
            provider: StubLocationProvider(
                result: .success(GeoCoordinate(latitude: 12.3456, longitude: 65.4321))
            )
        )

        let result = try await service.currentLocation()

        #expect(result.displayName == "12.3456, 65.4321")
    }

    @Test
    func authorizationDeniedPropagates() async {
        let service = makeService(
            provider: StubLocationProvider(
                result: .failure(WeatherLocationError.authorizationDenied)
            )
        )
        do {
            _ = try await service.currentLocation()
            Issue.record("权限拒绝应抛错")
        } catch {
            #expect((error as? WeatherLocationError) == .authorizationDenied)
            #expect(error.localizedDescription == "定位权限被拒绝，请在系统设置中允许访问位置")
        }
    }

    @Test
    func geocodingFailurePropagates() async {
        let service = makeService(
            geocoder: StubGeocoder(
                geocodeResult: .failure(WeatherLocationError.geocodingFailed("网络错误"))
            )
        )
        do {
            _ = try await service.search("上海")
            Issue.record("地理编码失败应抛错")
        } catch {
            #expect((error as? WeatherLocationError) == .geocodingFailed("网络错误"))
        }
    }

    @Test
    func displayNamePrefersCityWithProvinceDisambiguation() {
        let place = GeocodedPlace(
            latitude: 1, longitude: 2,
            locality: "朝阳区",
            administrativeArea: "北京市"
        )
        #expect(place.displayName(latitude: 1, longitude: 2) == "北京市朝阳区")
    }

    @Test
    func displayNameFallsBackThroughAdminNameCountryThenCoordinate() {
        let onlyCountry = GeocodedPlace(latitude: 5, longitude: 6, country: "日本")
        #expect(onlyCountry.displayName(latitude: 5, longitude: 6) == "日本")

        let onlyName = GeocodedPlace(latitude: 7, longitude: 8, name: "富士山")
        #expect(onlyName.displayName(latitude: 7, longitude: 8) == "富士山")

        let empty = GeocodedPlace(latitude: 9.5, longitude: 10.25)
        #expect(empty.displayName(latitude: 9.5, longitude: 10.25) == "9.5000, 10.2500")
    }

    @Test
    func snapshotCarriesLocationNameAndCoordinate() {
        let snapshot = WeatherSnapshot(
            temperature: 20,
            apparentTemperature: 19,
            condition: WeatherCondition(code: 0, isDay: true),
            timezone: "Asia/Shanghai",
            fetchedAt: Date(timeIntervalSince1970: 0),
            coordinate: GeoCoordinate(latitude: 31.2, longitude: 121.4),
            locationName: "上海市"
        )

        #expect(snapshot.locationName == "上海市")
        #expect(snapshot.coordinate == GeoCoordinate(latitude: 31.2, longitude: 121.4))
    }
}
