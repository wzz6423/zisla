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
