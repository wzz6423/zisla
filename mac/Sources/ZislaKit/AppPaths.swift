import Foundation
import ZislaCore

public enum AppPaths {
    public static var applicationSupport: URL {
        LegacyAppDataMigration.applicationSupport
    }

    public static var aiStateDatabase: URL {
        applicationSupport.appendingPathComponent("ai-state.sqlite", isDirectory: false)
    }

    public static var fileShelf: URL {
        applicationSupport.appendingPathComponent("file-shelf.json", isDirectory: false)
    }

    public static var weatherLocations: URL {
        applicationSupport.appendingPathComponent("weather-locations.json", isDirectory: false)
    }

    public static var quickNotes: URL {
        applicationSupport.appendingPathComponent("quick-notes.json", isDirectory: false)
    }

    public static var alarms: URL {
        applicationSupport.appendingPathComponent("alarms.json", isDirectory: false)
    }

    public static var voiceHistory: URL {
        applicationSupport.appendingPathComponent("voice-history.json", isDirectory: false)
    }

    public static var voiceRecordings: URL {
        applicationSupport.appendingPathComponent("voice-recordings", isDirectory: true)
    }

    /// Command-line tools that Zisla downloads and manages itself (yt-dlp). Kept under
    /// Application Support: the user directory is not writable by other users, which satisfies
    /// the trusted directory chain required by `YTDLPResolver`.
    public static var managedTools: URL {
        applicationSupport.appendingPathComponent("Tools", isDirectory: true)
    }

    public static var clipboardHistory: URL {
        applicationSupport.appendingPathComponent("clipboard-history.sqlite", isDirectory: false)
    }

    public static var aiAgent: URL {
        applicationSupport.appendingPathComponent("ai-agent.json", isDirectory: false)
    }

    public static var aiAgentSecrets: URL {
        applicationSupport.appendingPathComponent("ai-agent-secrets.sqlite", isDirectory: false)
    }

    public static var favicons: URL {
        applicationSupport.appendingPathComponent("favicons", isDirectory: true)
    }

    public static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    /// Resolves bundled resources, falling back to the repository Resources directory when running with `swift run`.
    /// Returns nil when the resource is not bundled so callers can choose an appropriate fallback.
    public static func bundledResource(relativePath: String) -> URL? {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            Bundle.main.resourceURL,
            sourceRoot.appendingPathComponent("Resources", isDirectory: true),
        ].compactMap { $0 }
        return candidates
            .map { $0.appendingPathComponent(relativePath, isDirectory: false) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
