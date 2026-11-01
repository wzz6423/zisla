import Foundation
import Testing
@testable import ZislaKit

@MainActor
struct ScreenRecordingOutputDirectoryStoreTests {
    @Test func corruptPreferencesUseDownloadsRatherThanTheWorkingDirectory() throws {
        let suite = "zisla-recording-directory-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([0]), forKey: "screen-recording-directory-bookmark")
        defaults.set("", forKey: "screen-recording-directory-path")

        #expect(ScreenRecordingOutputDirectoryStore(defaults: defaults).directory == AppPaths.downloads)
    }

    @Test func defaultsToDownloadsAndPersistsAnIndependentCustomDirectory() throws {
        let suite = "zisla-recording-directory-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = ScreenRecordingOutputDirectoryStore(defaults: defaults)
        #expect(directory.directory == AppPaths.downloads)
        defaults.set(Data([1, 2, 3]), forKey: "download-directory-bookmark")

        try directory.setDirectory(root)

        #expect(directory.directory.path == root.path)
        #expect(ScreenRecordingOutputDirectoryStore(defaults: defaults).directory.path == root.path)
        #expect(defaults.data(forKey: "download-directory-bookmark") == Data([1, 2, 3]))
    }

    @Test func invalidSelectionKeepsThePreviouslySavedDirectory() throws {
        let suite = "zisla-recording-directory-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = ScreenRecordingOutputDirectoryStore(defaults: defaults)
        try directory.setDirectory(root)
        let file = root.appendingPathComponent("file")
        try Data([1]).write(to: file)

        for invalid in [file, root.appendingPathComponent("missing"), URL(string: "https://invalid.example\(root.path)")!] {
            #expect(throws: (any Error).self) { try directory.setDirectory(invalid) }
            #expect(directory.directory.path == root.path)
            #expect(ScreenRecordingOutputDirectoryStore(defaults: defaults).directory.path == root.path)
        }
    }

    @Test func downloadBookmarkCompatibilityKeepsRecordingPreferencesIndependent() throws {
        let suite = "zisla-download-directory-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let recordings = root.appendingPathComponent("recordings", isDirectory: true)
        let downloads = root.appendingPathComponent("downloads", isDirectory: true)
        for directory in [recordings, downloads] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        let legacy = ScreenRecordingOutputDirectoryStore(defaults: defaults)
        try legacy.setDirectory(recordings)
        let legacyBookmark = try #require(defaults.data(forKey: "screen-recording-directory-bookmark"))
        let existingDownloadBookmark = try downloads.bookmarkData(options: .withSecurityScope,
            includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(existingDownloadBookmark, forKey: "download-directory-bookmark")
        let shared = ScreenRecordingOutputDirectoryStore(defaults: defaults,
            bookmarkKey: "download-directory-bookmark", pathKey: nil)

        #expect(shared.directory.path == downloads.path)
        try shared.setDirectory(root)

        #expect(ScreenRecordingOutputDirectoryStore(defaults: defaults,
            bookmarkKey: "download-directory-bookmark", pathKey: nil).directory.path == root.path)
        #expect(ScreenRecordingOutputDirectoryStore(defaults: defaults).directory.path == recordings.path)
        #expect(defaults.data(forKey: "screen-recording-directory-bookmark") == legacyBookmark)
        #expect(defaults.string(forKey: "screen-recording-directory-path") == recordings.path)
    }

    @Test func corruptDownloadBookmarkUsesDownloadsAndDoesNotAdoptTheRecordingPath() throws {
        let suite = "zisla-download-directory-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([0]), forKey: "download-directory-bookmark")
        defaults.set("/legacy-recording-path", forKey: "screen-recording-directory-path")

        let shared = ScreenRecordingOutputDirectoryStore(defaults: defaults,
            bookmarkKey: "download-directory-bookmark", pathKey: nil)

        #expect(shared.directory == AppPaths.downloads)
        #expect(defaults.data(forKey: "download-directory-bookmark") == Data([0]))
        #expect(defaults.string(forKey: "screen-recording-directory-path") == "/legacy-recording-path")
    }

    @Test func damagedBookmarkPreservesTheConfiguredPathForRecovery() throws {
        let suite = "zisla-recording-directory-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let directory = ScreenRecordingOutputDirectoryStore(defaults: defaults)
        try directory.setDirectory(root)
        try FileManager.default.removeItem(at: root)
        defaults.set(Data([0]), forKey: "screen-recording-directory-bookmark")

        let restored = ScreenRecordingOutputDirectoryStore(defaults: defaults)

        #expect(restored.directory.path == root.path)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(defaults.string(forKey: "screen-recording-directory-path") == root.path)
    }
}
