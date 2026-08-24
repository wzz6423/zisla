import Foundation

public enum LegacyAppDataMigration {
    private static let legacyApplicationSupportDirectoryName = "Orbit"
    private static let legacyBundleIdentifier = "dev.wzz.orbit"
    private static let userDefaultsMigrationMarker = "zisla.legacy-user-defaults-migrated"

    public static func applicationSupportDirectory(
        isDebugBuild: Bool = false,
        fileManager: FileManager = .default
    ) -> URL {
        if let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return applicationSupportDirectory(baseURL: base, isDebugBuild: isDebugBuild, fileManager: fileManager)
        }
        return fallbackApplicationSupportDirectory(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            isDebugBuild: isDebugBuild,
            fileManager: fileManager
        )
    }

    static func applicationSupportDirectory(
        baseURL: URL,
        isDebugBuild: Bool = false,
        fileManager: FileManager = .default
    ) -> URL {
        let directoryName = isDebugBuild ? "zisla-debug" : "zisla"
        let current = baseURL.appendingPathComponent(directoryName, isDirectory: true)
        guard !isDebugBuild else { return current }
        let legacy = baseURL.appendingPathComponent(legacyApplicationSupportDirectoryName, isDirectory: true)
        return migrateDirectory(from: legacy, to: current, fileManager: fileManager)
    }

    static func fallbackApplicationSupportDirectory(
        homeDirectory: URL,
        isDebugBuild: Bool = false,
        fileManager: FileManager = .default
    ) -> URL {
        let directoryName = isDebugBuild ? ".local/share/zisla-debug" : ".local/share/zisla"
        let current = homeDirectory.appendingPathComponent(directoryName, isDirectory: true)
        guard !isDebugBuild else { return current }
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
        let isDebugBuild = (Bundle.main.object(
            forInfoDictionaryKey: "ZislaApplicationSupportDirectory"
        ) as? String) == "zisla-debug"
            || Bundle.main.bundleIdentifier?.hasSuffix(".debug") == true
        guard !isDebugBuild else { return }
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
