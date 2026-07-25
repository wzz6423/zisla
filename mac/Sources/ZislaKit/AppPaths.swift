import Foundation
import ZislaCore

public enum AppPaths {
    public static var applicationSupport: URL {
        LegacyAppDataMigration.applicationSupportDirectory()
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

    public static var clipboardHistory: URL {
        applicationSupport.appendingPathComponent("clipboard-history.sqlite", isDirectory: false)
    }

    public static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }
}
