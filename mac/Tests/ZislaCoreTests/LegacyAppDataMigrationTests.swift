import Foundation
import Testing
@testable import ZislaCore

struct LegacyAppDataMigrationTests {
    @Test
    func movesLegacyApplicationSupportDirectoryWhenCurrentDirectoryDoesNotExist() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyDirectory = root.appendingPathComponent("Orbit", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try Data("state".utf8).write(to: legacyDirectory.appendingPathComponent("ai-state.json"))

        let directory = LegacyAppDataMigration.applicationSupportDirectory(baseURL: root)

        #expect(directory == root.appendingPathComponent("zisla", isDirectory: true))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ai-state.json").path))
        #expect(!FileManager.default.fileExists(atPath: legacyDirectory.path))
    }

    @Test
    func preservesBothDirectoriesWhenCurrentDirectoryAlreadyExists() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyDirectory = root.appendingPathComponent("Orbit", isDirectory: true)
        let currentDirectory = root.appendingPathComponent("zisla", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: legacyDirectory.appendingPathComponent("ai-state.json"))

        let directory = LegacyAppDataMigration.applicationSupportDirectory(baseURL: root)

        #expect(directory == currentDirectory)
        #expect(FileManager.default.fileExists(atPath: legacyDirectory.appendingPathComponent("ai-state.json").path))
    }

    @Test
    func movesLegacyFallbackDirectoryWhenApplicationSupportIsUnavailable() throws {
        let home = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let legacyDirectory = home.appendingPathComponent(".orbit", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try Data("state".utf8).write(to: legacyDirectory.appendingPathComponent("ai-state.json"))

        let directory = LegacyAppDataMigration.fallbackApplicationSupportDirectory(homeDirectory: home)

        #expect(directory == home.appendingPathComponent(".local/share/zisla", isDirectory: true))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ai-state.json").path))
        #expect(!FileManager.default.fileExists(atPath: legacyDirectory.path))
    }

    @Test
    func debugBuildUsesSeparateApplicationSupportDirectoryWithoutMigrating() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyDirectory = root.appendingPathComponent("Orbit", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)

        let directory = LegacyAppDataMigration.applicationSupportDirectory(
            baseURL: root,
            isDebugBuild: true
        )

        #expect(directory == root.appendingPathComponent("zisla-debug", isDirectory: true))
        #expect(FileManager.default.fileExists(atPath: legacyDirectory.path))
    }

    @Test
    func debugFallbackUsesSeparateApplicationSupportDirectory() {
        let home = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let directory = LegacyAppDataMigration.fallbackApplicationSupportDirectory(
            homeDirectory: home,
            isDebugBuild: true
        )

        #expect(directory == home.appendingPathComponent(".local/share/zisla-debug", isDirectory: true))
    }

    @Test
    func importsMissingUserDefaultsValuesWithoutOverwritingCurrentValues() throws {
        let legacySuite = "zisla.legacy-migration.\(UUID().uuidString)"
        let currentSuite = "zisla.current-migration.\(UUID().uuidString)"
        let migrationMarker = "zisla.test-migrated"
        let legacyDefaults = try #require(UserDefaults(suiteName: legacySuite))
        let currentDefaults = try #require(UserDefaults(suiteName: currentSuite))
        defer {
            UserDefaults.standard.removePersistentDomain(forName: legacySuite)
            UserDefaults.standard.removePersistentDomain(forName: currentSuite)
        }

        legacyDefaults.set("from-legacy", forKey: "missing")
        legacyDefaults.set("legacy-value", forKey: "existing")
        currentDefaults.set("current-value", forKey: "existing")

        LegacyAppDataMigration.migrateUserDefaults(
            from: legacyDefaults,
            to: currentDefaults,
            legacyDomainName: legacySuite,
            migrationMarker: migrationMarker
        )

        #expect(currentDefaults.string(forKey: "missing") == "from-legacy")
        #expect(currentDefaults.string(forKey: "existing") == "current-value")
        #expect(currentDefaults.bool(forKey: migrationMarker))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-migration-\(UUID().uuidString)", isDirectory: true)
    }
}
