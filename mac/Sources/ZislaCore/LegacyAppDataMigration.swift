import Foundation

public enum LegacyAppDataMigration {
    private static let legacyApplicationSupportDirectoryName = "Orbit"
    private static let legacyBundleIdentifier = "dev.wzz.orbit"
    private static let userDefaultsMigrationMarker = "zisla.legacy-user-defaults-migrated"

    public static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        if let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return applicationSupportDirectory(baseURL: base, fileManager: fileManager)
        }
        return fallbackApplicationSupportDirectory(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            fileManager: fileManager
        )
    }

    static func applicationSupportDirectory(baseURL: URL, fileManager: FileManager = .default) -> URL {
        let current = baseURL.appendingPathComponent("zisla", isDirectory: true)
        let legacy = baseURL.appendingPathComponent(legacyApplicationSupportDirectoryName, isDirectory: true)
        return migrateDirectory(from: legacy, to: current, fileManager: fileManager)
    }

    static func fallbackApplicationSupportDirectory(homeDirectory: URL, fileManager: FileManager = .default) -> URL {
        let current = homeDirectory.appendingPathComponent(".local/share/zisla", isDirectory: true)
        let legacy = homeDirectory.appendingPathComponent(".orbit", isDirectory: true)
        return migrateDirectory(from: legacy, to: current, fileManager: fileManager)
    }

    private static func migrateDirectory(from legacy: URL, to current: URL, fileManager: FileManager) -> URL {
        guard fileManager.fileExists(atPath: legacy.path) else { return current }
        guard !fileManager.fileExists(atPath: current.path) else { return current }

        do {
            try fileManager.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: legacy, to: current)
            return current
        } catch {
            return legacy
        }
    }

    public static func migrateUserDefaults() {
        guard let legacyDefaults = UserDefaults(suiteName: legacyBundleIdentifier) else { return }
        migrateUserDefaults(
            from: legacyDefaults,
            to: .standard,
            legacyDomainName: legacyBundleIdentifier,
            migrationMarker: userDefaultsMigrationMarker
        )
    }

    static func migrateUserDefaults(
        from legacyDefaults: UserDefaults,
        to currentDefaults: UserDefaults,
        legacyDomainName: String,
        migrationMarker: String
    ) {
        guard currentDefaults.object(forKey: migrationMarker) == nil else { return }

        for (key, value) in legacyDefaults.persistentDomain(forName: legacyDomainName) ?? [:]
        where currentDefaults.object(forKey: key) == nil {
            currentDefaults.set(value, forKey: key)
        }
        currentDefaults.set(true, forKey: migrationMarker)
    }
}
