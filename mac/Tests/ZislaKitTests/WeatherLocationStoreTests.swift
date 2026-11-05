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
        ], at: Date(timeIntervalSince1970: 0))

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
        ], at: Date(timeIntervalSince1970: 0))
        #expect(ordered.map(\.locationName) == ["当前位置", "东京"])

        let reloaded = WeatherLocationStore(storageURL: url, defaults: defaults)
        #expect(reloaded.locations.map(\.displayName) == ["当前位置", "东京", "伦敦", "北京"])
    }
    @Test
    func countryCodeSurvivesStorageAndLegacyFilesRemainReadable() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WeatherLocationStore(storageURL: url, defaults: makeDefaults())
        store.addSaved(name: "上海", coordinate: GeoCoordinate(latitude: 31.2, longitude: 121.4), isoCountryCode: "CN")
        store.updateCurrent(name: "伦敦", coordinate: GeoCoordinate(latitude: 51.5, longitude: 0), isoCountryCode: "GB")
        store.addSaved(name: "上海市", coordinate: GeoCoordinate(latitude: 31.2, longitude: 121.4))
        let reloaded = WeatherLocationStore(storageURL: url, defaults: makeDefaults())
        #expect(reloaded.locations.map(\.isoCountryCode) == ["GB", "CN"])
        let legacy = Data(#"[{"id":"old","kind":"saved","displayName":"上海","latitude":31.2,"longitude":121.4}]"#.utf8)
        let decoded = try JSONDecoder().decode([WeatherLocation].self, from: legacy)
        #expect(decoded.first?.isoCountryCode == nil)
        #expect(decoded.first?.coordinate == GeoCoordinate(latitude: 31.2, longitude: 121.4))
    }

    @Test
    func deduplicatingLoadedLocationsRetainsTheKnownCountryCode() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let entries = [
            WeatherLocation.saved(id: "first", displayName: "旧上海", coordinate: GeoCoordinate(latitude: 31.2, longitude: 121.4)),
            WeatherLocation.saved(id: "second", displayName: "上海", coordinate: GeoCoordinate(latitude: 31.2, longitude: 121.4), isoCountryCode: "CN"),
            WeatherLocation.saved(id: "third", displayName: "上海市", coordinate: GeoCoordinate(latitude: 31.2, longitude: 121.4)),
        ]
        try JSONEncoder().encode(entries).write(to: url)
        let store = WeatherLocationStore(storageURL: url, defaults: makeDefaults())
        #expect(store.locations.last?.displayName == "上海市")
        #expect(store.locations.last?.isoCountryCode == "CN")
        let explicitNull = Data(#"[{"id":"legacy","kind":"saved","displayName":"上海","latitude":31.2,"longitude":121.4,"isoCountryCode":null}]"#.utf8)
        #expect(try JSONDecoder().decode([WeatherLocation].self, from: explicitNull).first?.isoCountryCode == nil)
    }

    @Test
    func refreshFailureRetainsOnlySnapshotsForExistingUnchangedCoordinates() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WeatherLocationStore(storageURL: url, defaults: makeDefaults())
        store.updateCurrent(name: "当前位置", coordinate: GeoCoordinate(latitude: 31.2, longitude: 0))
        store.addSaved(name: "东京", coordinate: GeoCoordinate(latitude: 35.7, longitude: 0))
        let tokyoID = store.locations.first { $0.kind == .saved }!.id
        let current = WeatherSnapshot.stub(name: "当前位置", latitude: 31.2)
        let tokyo = WeatherSnapshot.stub(name: "东京", latitude: 35.7)
        let previous = [WeatherLocation.currentID: current, tokyoID: tokyo, "removed": tokyo]
        let date = Date(timeIntervalSince1970: 0)
        #expect(store.mergingSnapshots([:], retaining: previous, at: date) == [WeatherLocation.currentID: current, tokyoID: tokyo])
        var refreshed = tokyo
        refreshed.temperature = 25
        #expect(store.mergingSnapshots([tokyoID: refreshed], retaining: previous, at: date)[tokyoID]?.temperature == 25)
        store.updateCurrent(name: "已移动", coordinate: GeoCoordinate(latitude: 41, longitude: 0))
        #expect(store.mergingSnapshots([:], retaining: previous, at: date)[WeatherLocation.currentID] == nil)
        let staleResponse = WeatherSnapshot.stub(name: "旧坐标", latitude: 31.2)
        #expect(store.mergingSnapshots([WeatherLocation.currentID: staleResponse], retaining: previous, at: date)[WeatherLocation.currentID] == nil)
        store.remove(id: tokyoID)
        #expect(store.mergingSnapshots([tokyoID: refreshed], retaining: previous, at: date).isEmpty)
    }

    @Test(arguments: [0.0, 3599.0, 3600.0, 3601.0, 7200.0])
    func weatherReadsAndRetentionStopAtOneHour(age: TimeInterval) {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WeatherLocationStore(storageURL: url, defaults: makeDefaults())
        store.updateCurrent(name: "London", coordinate: GeoCoordinate(latitude: 51, longitude: 0))
        let snapshot = WeatherSnapshot.stub(name: "London", latitude: 51)
        let previous = [WeatherLocation.currentID: snapshot]
        let date = snapshot.fetchedAt.addingTimeInterval(age)
        let expected = age < 3600 ? previous : [:]
        #expect(store.mergingSnapshots([:], retaining: previous, at: date) == expected,
                "Network failure must not retain weather at or beyond one hour")
        #expect(store.mergingSnapshots(previous, retaining: [:], at: date) == expected,
                "An already expired provider response must not reintroduce old weather")
        #expect(store.orderedSnapshots(previous, at: date) == (age < 3600 ? [snapshot] : []),
                "Displayed snapshots must expire without requiring another network refresh")
        #expect(store.snapshot(for: WeatherLocation.currentID, in: previous, at: date) == (age < 3600 ? snapshot : nil),
                "Single-location consumers must obey the same one-hour limit")
        #expect(store.snapshot(for: "missing", in: previous, at: date) == nil)
        #expect(previous[WeatherLocation.currentID] == snapshot, "Expiry checks must not mutate provider data")
    }

    @Test
    func repeatedFailuresDoNotRenewWeatherAndAValidRefreshRestoresIt() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WeatherLocationStore(storageURL: url, defaults: makeDefaults())
        store.updateCurrent(name: "London", coordinate: GeoCoordinate(latitude: 51, longitude: 0))
        let snapshot = WeatherSnapshot.stub(name: "London", latitude: 51)
        let persisted = try Data(contentsOf: url)
        let originalLocations = store.locations
        var retained = [WeatherLocation.currentID: snapshot]
        for age in [900.0, 1800.0, 2700.0, 3599.0] {
            retained = store.mergingSnapshots([:], retaining: retained, at: snapshot.fetchedAt.addingTimeInterval(age))
            #expect(retained[WeatherLocation.currentID] == snapshot,
                    "Repeated outages must keep the original update time and data")
        }
        let expiredAt = snapshot.fetchedAt.addingTimeInterval(3600)
        retained = store.mergingSnapshots([:], retaining: retained, at: expiredAt)
        #expect(retained.isEmpty)
        #expect(store.orderedSnapshots(retained, at: expiredAt).isEmpty)
        var recovered = snapshot
        recovered.fetchedAt = expiredAt.addingTimeInterval(30)
        recovered.temperature = 25
        retained = store.mergingSnapshots([WeatherLocation.currentID: recovered], retaining: retained, at: recovered.fetchedAt)
        #expect(store.orderedSnapshots(retained, at: recovered.fetchedAt) == [recovered],
                "A successful forecast must recover after all retained data has expired")
        #expect(store.locations == originalLocations)
        #expect(try Data(contentsOf: url) == persisted, "Weather expiry must not change saved locations")
    }

    @Test
    func partiallyExpiredWeatherPreservesLocationOrderAndFreshFallback() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WeatherLocationStore(storageURL: url, defaults: makeDefaults())
        store.updateCurrent(name: "London", coordinate: GeoCoordinate(latitude: 51, longitude: 0))
        store.addSaved(name: "Tokyo", coordinate: GeoCoordinate(latitude: 35.7, longitude: 0))
        let tokyoID = store.locations.last!.id
        let current = WeatherSnapshot.stub(name: "London", latitude: 51)
        var tokyo = WeatherSnapshot.stub(name: "Tokyo", latitude: 35.7)
        tokyo.fetchedAt = current.fetchedAt.addingTimeInterval(1800)
        let previous = [WeatherLocation.currentID: current, tokyoID: tokyo]
        let date = current.fetchedAt.addingTimeInterval(3600)
        #expect(store.orderedSnapshots(previous, at: date) == [tokyo])
        #expect(store.mergingSnapshots([:], retaining: previous, at: date) == [tokyoID: tokyo])
        var expiredResponse = tokyo
        expiredResponse.fetchedAt = current.fetchedAt
        #expect(store.mergingSnapshots([tokyoID: expiredResponse], retaining: previous, at: date) == [tokyoID: tokyo],
                "An expired refresh must fall back to the still-usable previous snapshot")
        var refreshed = current
        refreshed.fetchedAt = date
        #expect(store.orderedSnapshots(
            store.mergingSnapshots([WeatherLocation.currentID: refreshed], retaining: previous, at: date), at: date
        ) == [refreshed, tokyo])
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
