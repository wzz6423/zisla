import Foundation
import Testing
@testable import ZislaKit

@MainActor
struct SaveLocationStoreTests {
    @Test func freshDefaultsStayIndependentAfterChangingDownloadsAndRestarting() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let locations = SaveLocationStore(defaults: fixture.defaults)
        let expected: [SaveLocation: URL] = [
            .download: AppPaths.downloads,
            .pdfTools: AppPaths.downloads.appendingPathComponent("pdf", isDirectory: true),
            .imageTools: AppPaths.downloads.appendingPathComponent("picture", isDirectory: true),
            .screenshot: AppPaths.downloads.appendingPathComponent("picture", isDirectory: true),
            .recording: AppPaths.downloads.appendingPathComponent("video", isDirectory: true),
            .quickActions: AppPaths.downloads.appendingPathComponent("quick", isDirectory: true),
            .dailyBriefing: AppPaths.downloads.appendingPathComponent("daily", isDirectory: true),
        ]
        #expect(locations.directories == expected)
        for location in SaveLocation.allCases where location != .download {
            #expect(fixture.defaults.string(forKey: location.pathKey!) == expected[location]!.path)
            #expect(fixture.defaults.data(forKey: location.bookmarkKey) == nil)
        }

        try locations.setDirectory(fixture.root, for: .download)

        let restored = SaveLocationStore(defaults: fixture.defaults)
        #expect(restored[.download].path == fixture.root.path)
        for location in SaveLocation.allCases where location != .download {
            #expect(locations[location] == expected[location])
            #expect(restored[location] == expected[location])
        }
    }

    @Test func upgradePreservesPreviouslyStoredDownloadsPathsWithoutRewritingPreferences() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        for location in SaveLocation.allCases where location != .download {
            fixture.defaults.set(AppPaths.downloads.path, forKey: location.pathKey!)
        }
        let preferences = fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:]

        let locations = SaveLocationStore(defaults: fixture.defaults)
        let restored = SaveLocationStore(defaults: fixture.defaults)

        for location in SaveLocation.allCases {
            #expect(locations[location] == AppPaths.downloads)
            #expect(restored[location] == AppPaths.downloads)
        }
        #expect(NSDictionary(dictionary: fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:])
            == NSDictionary(dictionary: preferences), "Stored paths must remain intact even when they match the old defaults")
    }

    @Test func upgradeKeepsTheEffectiveDownloadLocationAndDoesNotReviveLegacyRecordingPreferences() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let shared = try fixture.makeDirectory("Shared downloads")
        let legacy = try fixture.makeDirectory("Legacy recording preference")
        try ScreenRecordingOutputDirectoryStore(defaults: fixture.defaults).setDirectory(legacy)
        let legacyPreferences = (fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:])
        let downloadStore = ScreenRecordingOutputDirectoryStore(defaults: fixture.defaults,
            bookmarkKey: "download-directory-bookmark", pathKey: nil)
        try downloadStore.setDirectory(shared)
        let locations = SaveLocationStore(defaults: fixture.defaults)
        for location in SaveLocation.allCases { #expect(locations[location].path == shared.path) }

        try locations.setDirectory(fixture.root, for: .download)

        let restored = SaveLocationStore(defaults: fixture.defaults)
        for location in SaveLocation.allCases where location != .download {
            #expect(restored[location].path == shared.path)
        }
        for key in ["screen-recording-directory-bookmark", "screen-recording-directory-path"] {
            #expect(NSDictionary(dictionary: [key: fixture.defaults.object(forKey: key)!])
                == NSDictionary(dictionary: [key: legacyPreferences[key]!]))
        }
    }

    @Test func migratedBookmarksFollowRenamedFoldersAcrossRestart() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let original = try fixture.makeDirectory("Original shared folder")
        let downloads = ScreenRecordingOutputDirectoryStore(defaults: fixture.defaults,
            bookmarkKey: "download-directory-bookmark", pathKey: nil)
        try downloads.setDirectory(original)
        _ = SaveLocationStore(defaults: fixture.defaults)
        let renamed = fixture.root.appendingPathComponent("Renamed shared folder", isDirectory: true)

        try FileManager.default.moveItem(at: original, to: renamed)

        let restored = SaveLocationStore(defaults: fixture.defaults)
        for location in SaveLocation.allCases {
            #expect(restored[location].path == renamed.path,
                    "Migrated locations must retain bookmark tracking when the original folder moves")
        }
        #expect(!FileManager.default.fileExists(atPath: original.path))
    }

    @Test func fileToolDefaultsMigrateFromCurrentDownloadsWithoutChangingExistingLocations() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let shared = try fixture.makeDirectory("Current downloads")
        let downloads = ScreenRecordingOutputDirectoryStore(defaults: fixture.defaults,
            bookmarkKey: SaveLocation.download.bookmarkKey, pathKey: nil)
        try downloads.setDirectory(shared)
        let existingLocations: [SaveLocation] = [.screenshot, .recording, .quickActions, .dailyBriefing]
        var existingPaths: [SaveLocation: URL] = [:]
        for location in existingLocations {
            let path = try fixture.makeDirectory(location.rawValue)
            let directory = ScreenRecordingOutputDirectoryStore(defaults: fixture.defaults,
                bookmarkKey: location.bookmarkKey, pathKey: location.pathKey)
            try directory.setDirectory(path)
            existingPaths[location] = path
        }
        let preferences = fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:]

        let locations = SaveLocationStore(defaults: fixture.defaults)

        for location in [SaveLocation.pdfTools, .imageTools] {
            #expect(locations[location].path == shared.path)
        }
        for location in existingLocations {
            #expect(locations[location].path == existingPaths[location]!.path)
            for key in [location.bookmarkKey, location.pathKey!] {
                #expect(NSDictionary(dictionary: [key: fixture.defaults.object(forKey: key)!])
                    == NSDictionary(dictionary: [key: preferences[key]!]))
            }
        }

        try locations.setDirectory(fixture.root, for: .download)

        let restored = SaveLocationStore(defaults: fixture.defaults)
        for location in [SaveLocation.pdfTools, .imageTools] {
            #expect(restored[location].path == shared.path,
                    "New file-tool defaults must retain their migrated location after downloads change")
        }
        for location in existingLocations {
            #expect(restored[location].path == existingPaths[location]!.path)
        }
    }

    @Test(arguments: SaveLocation.allCases)
    func eachLocationPersistsWithoutChangingOtherLocations(_ selected: SaveLocation) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let locations = SaveLocationStore(defaults: fixture.defaults)
        for location in SaveLocation.allCases {
            try locations.setDirectory(fixture.makeDirectory(location.rawValue), for: location)
        }
        let original = locations.directories
        let custom = try fixture.makeDirectory("Custom 中文 folder")

        try locations.setDirectory(custom, for: selected)

        let restored = SaveLocationStore(defaults: fixture.defaults)
        for location in SaveLocation.allCases {
            let expected = location == selected ? custom.path : original[location]!.path
            #expect(locations[location].path == expected)
            #expect(restored[location].path == expected)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: custom.path).isEmpty,
                "Changing defaults must not move or create content")
    }

    @Test(arguments: SaveLocation.allCases)
    func invalidSelectionLeavesDirectoriesAndPreferencesUnchanged(_ selected: SaveLocation) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let locations = SaveLocationStore(defaults: fixture.defaults)
        try locations.setDirectory(fixture.root, for: selected)
        let directories = locations.directories
        let preferences = (fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:])
        let file = fixture.root.appendingPathComponent("existing.txt")
        try Data("existing".utf8).write(to: file)
        for invalid in [file, fixture.root.appendingPathComponent("missing"),
                        URL(string: "https://invalid.example/folder")!] {
            #expect(throws: (any Error).self) { try locations.setDirectory(invalid, for: selected) }
            #expect(locations.directories == directories)
            #expect(NSDictionary(dictionary: (fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:]))
                == NSDictionary(dictionary: preferences))
            #expect(try Data(contentsOf: file) == Data("existing".utf8))
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("missing").path))
    }

    @Test func corruptSharedBookmarkUsesDownloadsWithoutRewritingExistingPreferences() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.defaults.set(Data([0]), forKey: "download-directory-bookmark")
        fixture.defaults.set("/legacy-recording", forKey: "screen-recording-directory-path")

        let locations = SaveLocationStore(defaults: fixture.defaults)

        for location in SaveLocation.allCases { #expect(locations[location] == AppPaths.downloads) }
        #expect(fixture.defaults.data(forKey: "download-directory-bookmark") == Data([0]))
        #expect(fixture.defaults.string(forKey: "screen-recording-directory-path") == "/legacy-recording")
        let preferences = (fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:])
        _ = SaveLocationStore(defaults: fixture.defaults)
        #expect(NSDictionary(dictionary: (fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:]))
            == NSDictionary(dictionary: preferences), "Loading migrated preferences must be idempotent")
    }

    @Test(arguments: [SaveLocation.screenshot, .pdfTools, .imageTools])
    func damagedIndependentBookmarkKeepsItsConfiguredPath(_ location: SaveLocation) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let custom = try fixture.makeDirectory("Recoverable location")
        let locations = SaveLocationStore(defaults: fixture.defaults)
        try locations.setDirectory(custom, for: location)
        fixture.defaults.set(Data([0]), forKey: location.bookmarkKey)
        try FileManager.default.removeItem(at: custom)

        let restored = SaveLocationStore(defaults: fixture.defaults)

        #expect(restored[location].path == custom.path)
        #expect(restored[.download] == AppPaths.downloads)
        #expect(!FileManager.default.fileExists(atPath: custom.path))
    }

    @Test(arguments: SaveLocation.allCases.filter { $0 != .download },
          ["bookmark only", "path only"])
    func upgradeKeepsPartiallyStoredIndependentPreferences(_ location: SaveLocation, fields: String) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let custom = try fixture.makeDirectory("Independent folder")
        let directory = ScreenRecordingOutputDirectoryStore(defaults: fixture.defaults,
            bookmarkKey: location.bookmarkKey, pathKey: location.pathKey)
        try directory.setDirectory(custom)
        fixture.defaults.removeObject(forKey: fields == "bookmark only" ? location.pathKey! : location.bookmarkKey)
        let bookmark = fixture.defaults.data(forKey: location.bookmarkKey)
        let path = fixture.defaults.string(forKey: location.pathKey!)

        let locations = SaveLocationStore(defaults: fixture.defaults)

        #expect(locations[location].path == custom.path)
        #expect(fixture.defaults.data(forKey: location.bookmarkKey) == bookmark)
        #expect(fixture.defaults.string(forKey: location.pathKey!) == path)
        #expect(SaveLocationStore(defaults: fixture.defaults)[location].path == custom.path)
    }

    @MainActor
    private final class Fixture {
        let suite = "zisla-save-location-test-\(UUID())"
        let defaults: UserDefaults
        let root: URL

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        }

        func makeDirectory(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            return url
        }

        func close() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
