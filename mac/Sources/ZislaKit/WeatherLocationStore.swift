import Combine
import Foundation

public enum WeatherLocationKind: String, Codable, Equatable, Sendable {
    case current
    case saved
}

public struct WeatherLocation: Identifiable, Codable, Equatable, Sendable {
    public static let currentID = "weather-location-current"

    public var id: String
    public var kind: WeatherLocationKind
    public var displayName: String
    public var coordinate: GeoCoordinate?

    public init(
        id: String,
        kind: WeatherLocationKind,
        displayName: String,
        coordinate: GeoCoordinate?
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.coordinate = coordinate
    }

    public static func current(
        displayName: String = "当前位置",
        coordinate: GeoCoordinate? = nil
    ) -> WeatherLocation {
        WeatherLocation(
            id: currentID,
            kind: .current,
            displayName: displayName,
            coordinate: coordinate
        )
    }

    public static func saved(
        id: String = UUID().uuidString,
        displayName: String,
        coordinate: GeoCoordinate
    ) -> WeatherLocation {
        WeatherLocation(
            id: id,
            kind: .saved,
            displayName: displayName,
            coordinate: coordinate
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, displayName, latitude, longitude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(WeatherLocationKind.self, forKey: .kind)
        displayName = try container.decode(String.self, forKey: .displayName)
        if container.contains(.latitude), container.contains(.longitude),
           let latitude = try container.decodeIfPresent(Double.self, forKey: .latitude),
           let longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        {
            coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
        } else {
            coordinate = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(coordinate?.latitude, forKey: .latitude)
        try container.encodeIfPresent(coordinate?.longitude, forKey: .longitude)
    }
}

@MainActor
public final class WeatherLocationStore: ObservableObject {
    public static let maxSavedCount = 6

    /// 约 100m 量级，用于同地去重。
    public static let coordinateMatchTolerance = 0.001

    @Published public private(set) var locations: [WeatherLocation]
    @Published public private(set) var errorDescription: String?

    private let storageURL: URL
    private let defaults: UserDefaults
    private let maxSaved: Int

    private static let legacyLatitudeKey = "weather-latitude"
    private static let legacyLongitudeKey = "weather-longitude"
    private static let legacyNameKey = "weather-location-name"

    public init(
        storageURL: URL = AppPaths.weatherLocations,
        defaults: UserDefaults = .standard,
        maxSaved: Int = WeatherLocationStore.maxSavedCount
    ) {
        self.storageURL = storageURL
        self.defaults = defaults
        self.maxSaved = max(1, maxSaved)
        self.locations = [WeatherLocation.current()]
        load()
    }

    public func addSaved(name: String, coordinate: GeoCoordinate) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? "未命名地点" : trimmed

        if let index = locations.firstIndex(where: {
            $0.kind == .saved && Self.coordinatesApproximatelyEqual($0.coordinate, coordinate)
        }) {
            locations[index].displayName = displayName
            locations[index].coordinate = coordinate
            normalize()
            persist()
            return
        }

        locations.append(.saved(displayName: displayName, coordinate: coordinate))
        normalize()
        persist()
    }

    public func updateCurrent(name: String, coordinate: GeoCoordinate?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? "当前位置" : trimmed
        if let index = locations.firstIndex(where: { $0.kind == .current }) {
            locations[index].displayName = displayName
            locations[index].coordinate = coordinate
            locations[index].id = WeatherLocation.currentID
        } else {
            locations.insert(
                .current(displayName: displayName, coordinate: coordinate),
                at: 0
            )
        }
        normalize()
        persist()
    }

    public func remove(id: String) {
        guard id != WeatherLocation.currentID else { return }
        let before = locations.count
        locations.removeAll { $0.kind == .saved && $0.id == id }
        guard locations.count != before else { return }
        normalize()
        persist()
    }

    @discardableResult
    public func moveSaved(id: String, to destinationID: String) -> Bool {
        guard id != destinationID,
              let sourceIndex = locations.firstIndex(where: { $0.id == id && $0.kind == .saved }),
              let destinationIndex = locations.firstIndex(where: {
                  $0.id == destinationID && $0.kind == .saved
              })
        else { return false }

        var reordered = locations
        let location = reordered.remove(at: sourceIndex)
        reordered.insert(location, at: destinationIndex)
        guard reordered != locations else { return false }
        locations = reordered
        persist()
        return true
    }

    public func orderedSnapshots(
        _ snapshotsByLocationID: [String: WeatherSnapshot]
    ) -> [WeatherSnapshot] {
        locations.compactMap { snapshotsByLocationID[$0.id] }
    }

    private func load() {
        let fileExists = FileManager.default.fileExists(atPath: storageURL.path)
        guard fileExists else {
            locations = [WeatherLocation.current()]
            migrateLegacyIfNeeded(hadExistingFile: false)
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode([WeatherLocation].self, from: data)
            locations = decoded
            errorDescription = nil
            normalize()
            if locations != decoded { persist() }
        } catch {
            locations = [WeatherLocation.current()]
            errorDescription = error.localizedDescription
        }
    }

    private func migrateLegacyIfNeeded(hadExistingFile: Bool) {
        guard !hadExistingFile else { return }
        guard defaults.object(forKey: Self.legacyLatitudeKey) != nil,
              defaults.object(forKey: Self.legacyLongitudeKey) != nil,
              let name = defaults.string(forKey: Self.legacyNameKey),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        let coordinate = GeoCoordinate(
            latitude: defaults.double(forKey: Self.legacyLatitudeKey),
            longitude: defaults.double(forKey: Self.legacyLongitudeKey)
        )
        locations = [
            WeatherLocation.current(),
            .saved(displayName: name, coordinate: coordinate),
        ]
        normalize()
        persist()
    }

    private func normalize() {
        var current = locations.first(where: { $0.kind == .current })
            ?? WeatherLocation.current()
        current.id = WeatherLocation.currentID
        current.kind = .current

        var saved: [WeatherLocation] = []
        var seenIDs = Set<String>()
        for item in locations where item.kind == .saved {
            guard let coordinate = item.coordinate else { continue }
            if let existingIndex = saved.firstIndex(where: {
                Self.coordinatesApproximatelyEqual($0.coordinate, coordinate)
            }) {
                saved[existingIndex].displayName = item.displayName
                saved[existingIndex].coordinate = coordinate
                continue
            }
            var copy = item
            if copy.id == WeatherLocation.currentID || seenIDs.contains(copy.id) {
                copy.id = UUID().uuidString
            }
            seenIDs.insert(copy.id)
            copy.kind = .saved
            copy.coordinate = coordinate
            saved.append(copy)
        }

        if saved.count > maxSaved {
            saved = Array(saved.suffix(maxSaved))
        }

        locations = [current] + saved
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(locations)
            try data.write(to: storageURL, options: .atomic)
            errorDescription = nil
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    private static func coordinatesApproximatelyEqual(
        _ lhs: GeoCoordinate?,
        _ rhs: GeoCoordinate
    ) -> Bool {
        guard let lhs else { return false }
        return abs(lhs.latitude - rhs.latitude) <= coordinateMatchTolerance
            && abs(lhs.longitude - rhs.longitude) <= coordinateMatchTolerance
    }
}
