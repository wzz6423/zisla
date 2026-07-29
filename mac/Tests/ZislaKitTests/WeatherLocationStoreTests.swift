import Foundation
import ZislaCore
import Testing

@testable import ZislaKit

@MainActor
struct WeatherLocationStoreTests {
    private func tempURL(_ name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-weather-locations-\(name).json", isDirectory: false)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "zisla.weather-location-store.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test
    func defaultsToSingleCurrentLocationFirst() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WeatherLocationStore(storageURL: url, defaults: makeDefaults())

        #expect(store.locations.count == 1)
        #expect(store.locations[0].kind == .current)
        #expect(store.locations[0].id == WeatherLocation.currentID)
        #expect(store.locations[0].coordinate == nil)
        #expect(store.errorDescription == nil)
    }

    @Test
    func addSavedDedupesByApproximateCoordinateAndUpdatesName() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WeatherLocationStore(storageURL: url, defaults: makeDefaults())

        store.addSaved(
            name: "上海",
            coordinate: GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
        )
        store.addSaved(
            name: "上海市",
            coordinate: GeoCoordinate(latitude: 31.2305, longitude: 121.4738)
        )

        let saved = store.locations.filter { $0.kind == .saved }
        #expect(saved.count == 1)
        #expect(saved[0].displayName == "上海市")
        #expect(store.locations.first?.kind == .current)
    }

    @Test
    func capsSavedAtSixAndEvictsOldestSavedNotCurrent() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WeatherLocationStore(storageURL: url, defaults: makeDefaults())

        for i in 0..<7 {
            store.addSaved(
                name: "地点\(i)",
                coordinate: GeoCoordinate(latitude: Double(i), longitude: Double(i))
            )
        }

        let saved = store.locations.filter { $0.kind == .saved }
        #expect(store.locations.first?.kind == .current)
        #expect(saved.count == 6)
        #expect(saved.map(\.displayName) == (1...6).map { "地点\($0)" })
    }

    @Test
    func removeOnlyDeletesSaved() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WeatherLocationStore(storageURL: url, defaults: makeDefaults())

        store.addSaved(
            name: "北京",
            coordinate: GeoCoordinate(latitude: 39.9, longitude: 116.4)
        )
        let savedID = store.locations.first(where: { $0.kind == .saved })!.id

        store.remove(id: WeatherLocation.currentID)
        #expect(store.locations.contains(where: { $0.kind == .current }))

        store.remove(id: savedID)
        #expect(store.locations.filter { $0.kind == .saved }.isEmpty)
        #expect(store.locations.count == 1)
    }

    @Test
    func persistsAndReloads() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let defaults = makeDefaults()

        do {
            let store = WeatherLocationStore(storageURL: url, defaults: defaults)
            store.addSaved(
                name: "杭州",
                coordinate: GeoCoordinate(latitude: 30.25, longitude: 120.15)
            )
            store.updateCurrent(
                name: "当前位置",
                coordinate: GeoCoordinate(latitude: 1, longitude: 2)
            )
        }

        let reloaded = WeatherLocationStore(storageURL: url, defaults: defaults)
        #expect(reloaded.locations.count == 2)
        #expect(reloaded.locations[0].kind == .current)
        #expect(reloaded.locations[0].displayName == "当前位置")
        #expect(reloaded.locations[0].coordinate == GeoCoordinate(latitude: 1, longitude: 2))
        #expect(reloaded.locations[1].displayName == "杭州")
        #expect(reloaded.errorDescription == nil)
    }

    @Test
    func corruptFileKeepsDefaultCurrentExposesErrorAndDoesNotOverwrite() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let payload = Data("not-json{{{".utf8)
        try payload.write(to: url, options: .atomic)

        let store = WeatherLocationStore(storageURL: url, defaults: makeDefaults())

        #expect(store.locations.count == 1)
        #expect(store.locations[0].kind == .current)
        #expect(store.errorDescription != nil)

        let onDisk = try Data(contentsOf: url)
        #expect(onDisk == payload)
    }

    @Test
    func repairsAndPersistsAValidFileMissingCurrentLocation() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let saved = WeatherLocation.saved(
            displayName: "东京",
            coordinate: GeoCoordinate(latitude: 35.68, longitude: 139.69)
        )
        try JSONEncoder().encode([saved]).write(to: url, options: .atomic)

        let store = WeatherLocationStore(storageURL: url, defaults: makeDefaults())

        #expect(store.locations.first?.kind == .current)
        let persisted = try JSONDecoder().decode(
            [WeatherLocation].self,
            from: Data(contentsOf: url)
        )
        #expect(persisted.first?.kind == .current)
        #expect(persisted.count == 2)
    }

    @Test
    func migratesLegacyUserDefaultsOnceWithoutClearingKeys() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let defaults = makeDefaults()
        defaults.set(31.2, forKey: "weather-latitude")
        defaults.set(121.5, forKey: "weather-longitude")
        defaults.set("上海", forKey: "weather-location-name")

        let store = WeatherLocationStore(storageURL: url, defaults: defaults)

        let saved = store.locations.filter { $0.kind == .saved }
        #expect(saved.count == 1)
        #expect(saved[0].displayName == "上海")
        #expect(saved[0].coordinate == GeoCoordinate(latitude: 31.2, longitude: 121.5))
        #expect(defaults.object(forKey: "weather-latitude") as? Double == 31.2)
        #expect(defaults.string(forKey: "weather-location-name") == "上海")

        // Do not re-migrate/append when the file already exists
        store.addSaved(
            name: "其它",
            coordinate: GeoCoordinate(latitude: 10, longitude: 20)
        )
        let again = WeatherLocationStore(storageURL: url, defaults: defaults)
        #expect(again.locations.filter { $0.kind == .saved }.count == 2)
    }

    @Test
    func appPathsExposesWeatherLocationsURL() {
        #expect(AppPaths.weatherLocations.lastPathComponent == "weather-locations.json")
        #expect(AppPaths.weatherLocations.deletingLastPathComponent() == AppPaths.applicationSupport)
    }

    @Test
    func ordersAvailableSnapshotsLikeConfiguredLocations() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WeatherLocationStore(storageURL: url, defaults: makeDefaults())
        store.updateCurrent(
            name: "当前位置",
            coordinate: GeoCoordinate(latitude: 31.2, longitude: 121.4)
        )
        store.addSaved(
            name: "北京",
            coordinate: GeoCoordinate(latitude: 39.9, longitude: 116.4)
        )
        store.addSaved(
            name: "东京",
            coordinate: GeoCoordinate(latitude: 35.7, longitude: 139.7)
        )
        let current = WeatherSnapshot.stub(name: "当前位置", latitude: 31.2)
        let tokyo = WeatherSnapshot.stub(name: "东京", latitude: 35.7)
        let tokyoID = store.locations.first { $0.displayName == "东京" }!.id

        let ordered = store.orderedSnapshots([
            tokyoID: tokyo,
            WeatherLocation.currentID: current,
        ])

        #expect(ordered.map(\.locationName) == ["当前位置", "东京"])
    }

    @Test
    func movesSavedLocationsAndPersistsTheirDisplayOrder() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let defaults = makeDefaults()
        let store = WeatherLocationStore(storageURL: url, defaults: defaults)
        store.addSaved(
            name: "北京",
            coordinate: GeoCoordinate(latitude: 39.9, longitude: 116.4)
        )
        store.addSaved(
            name: "东京",
            coordinate: GeoCoordinate(latitude: 35.7, longitude: 139.7)
        )
        store.addSaved(
            name: "伦敦",
            coordinate: GeoCoordinate(latitude: 51.5, longitude: -0.1)
        )

        let tokyoID = store.locations.first { $0.displayName == "东京" }!.id
        let beijingID = store.locations.first { $0.displayName == "北京" }!.id
        let londonID = store.locations.first { $0.displayName == "伦敦" }!.id
        #expect(store.moveSaved(id: tokyoID, to: beijingID))
        #expect(store.moveSaved(id: beijingID, to: londonID))
        #expect(!store.moveSaved(id: WeatherLocation.currentID, to: tokyoID))
        #expect(!store.moveSaved(id: beijingID, to: beijingID))

        #expect(store.locations.map(\.displayName) == ["当前位置", "东京", "伦敦", "北京"])
        let ordered = store.orderedSnapshots([
            WeatherLocation.currentID: .stub(name: "当前位置", latitude: 0),
            tokyoID: .stub(name: "东京", latitude: 35.7),
        ])
        #expect(ordered.map(\.locationName) == ["当前位置", "东京"])

        let reloaded = WeatherLocationStore(storageURL: url, defaults: defaults)
        #expect(reloaded.locations.map(\.displayName) == ["当前位置", "东京", "伦敦", "北京"])
    }
}

private extension WeatherSnapshot {
    static func stub(name: String, latitude: Double) -> WeatherSnapshot {
        WeatherSnapshot(
            temperature: 20,
            apparentTemperature: 19,
            condition: WeatherCondition(code: 0, isDay: true),
            timezone: "UTC",
            fetchedAt: Date(timeIntervalSince1970: 0),
            coordinate: GeoCoordinate(latitude: latitude, longitude: 0),
            locationName: name
        )
    }
}
