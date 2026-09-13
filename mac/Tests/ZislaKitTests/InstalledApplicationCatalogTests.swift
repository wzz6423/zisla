import Foundation
import Testing

@testable import ZislaKit

/// The catalog indexes installed application names so copied text like "Safari"
/// or "访达" can offer a launch action. Tests build throwaway `.app` bundles
/// instead of relying on the host machine's application set.
struct InstalledApplicationCatalogTests {
    @Test
    func scansBundlesAndMatchesEveryIndexedName() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.makeBundle(
            named: "Preview Tool",
            bundleIdentifier: "com.example.preview-tool",
            displayName: "预览工具",
            in: directory
        )

        let applications = InstalledApplicationCatalog.scanApplications(directories: [directory])
        #expect(applications.count == 1)
        let application = try #require(applications.first)
        #expect(application.bundleIdentifier == "com.example.preview-tool")
        #expect(application.displayName == "预览工具")
        #expect(application.matchKeys.contains("预览工具"))
        #expect(application.matchKeys.contains("preview tool"))

        #expect(InstalledApplicationCatalog.application(
            named: "Preview Tool", in: applications
        )?.bundleIdentifier == "com.example.preview-tool")
        #expect(InstalledApplicationCatalog.application(
            named: "预览工具", in: applications
        )?.bundleIdentifier == "com.example.preview-tool")
        // Matching trims stray whitespace and ignores case.
        #expect(InstalledApplicationCatalog.application(
            named: "  preview tool ", in: applications
        ) != nil)
        // Text that names no installed application resolves to nothing.
        #expect(InstalledApplicationCatalog.application(
            named: "Preview To", in: applications
        ) == nil)
        #expect(InstalledApplicationCatalog.application(named: "", in: applications) == nil)
    }

    @Test
    func bundleWithoutDisplayNamesFallsBackToTheFileName() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.makeBundle(
            named: "Fallback",
            bundleIdentifier: "com.example.fallback",
            displayName: nil,
            bundleName: nil,
            in: directory
        )

        let applications = InstalledApplicationCatalog.scanApplications(directories: [directory])
        let application = try #require(applications.first)
        #expect(application.displayName == "Fallback")
        #expect(InstalledApplicationCatalog.application(
            named: "fallback", in: applications
        )?.bundleIdentifier == "com.example.fallback")
    }

    @Test
    func bundlesWithoutAnIdentifierAndPlainFilesAreSkipped() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("plain".utf8).write(to: directory.appendingPathComponent("readme.txt"))
        let nameless = try Self.makeBundle(
            named: "Nameless",
            bundleIdentifier: "",
            in: directory
        )

        #expect(InstalledApplicationCatalog.scanApplications(directories: [directory]).isEmpty)
        #expect(InstalledApplicationCatalog.installedApplication(at: nameless) == nil)
    }

    @Test
    func duplicateBundleIdentifiersKeepTheFirstDirectoryEntry() throws {
        let system = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: system) }
        let user = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: user) }
        try Self.makeBundle(named: "Twice", bundleIdentifier: "com.example.twice", in: user)
        try Self.makeBundle(named: "Twice", bundleIdentifier: "com.example.twice", in: system)

        // User directories come first, so their copy wins and no duplicate is kept.
        let applications = InstalledApplicationCatalog.scanApplications(
            directories: [user, system]
        )
        #expect(applications.count == 1)
    }

    @Test
    func matchKeyFoldsCaseDiacriticsWidthAndWhitespace() {
        let matchKey = InstalledApplicationCatalog.matchKey(for:)
        #expect(matchKey("Safari") == matchKey("safari"))
        #expect(matchKey("Ｃａｆé") == matchKey("cafe"))
        #expect(matchKey("  Notes  ") == "notes")
    }

    @Test
    func directorySignatureChangesWhenContentsChange() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = InstalledApplicationCatalog.directorySignatures(for: [directory])
        try Data("x".utf8).write(to: directory.appendingPathComponent("New App"))
        let after = InstalledApplicationCatalog.directorySignatures(for: [directory])
        #expect(before != after)
    }

    @Test
    func startPublishesTheFirstSnapshot() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.makeBundle(named: "Hello", bundleIdentifier: "com.example.hello", in: directory)
        let catalog = InstalledApplicationCatalog(scanDirectories: [directory])
        let counter = SnapshotCounter()

        catalog.start { applications in
            Task { await counter.record(applications) }
        }
        for _ in 0..<200 {
            if await counter.count != nil { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(await counter.count == 1)
        #expect(catalog.currentApplications.count == 1)
        #expect(InstalledApplicationCatalog.application(
            named: "hello", in: catalog.currentApplications
        )?.bundleIdentifier == "com.example.hello")
    }

    private actor SnapshotCounter {
        private(set) var count: Int?
        func record(_ applications: [InstalledApplication]) {
            count = applications.count
        }
    }

    // MARK: - Helpers

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-app-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeBundle(
        named name: String,
        bundleIdentifier: String,
        displayName: String? = nil,
        bundleName: String? = nil,
        in directory: URL
    ) throws -> URL {
        let bundleURL = directory.appendingPathComponent("\(name).app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundleURL.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        var info: [String: Any] = [:]
        if !bundleIdentifier.isEmpty { info["CFBundleIdentifier"] = bundleIdentifier }
        if let bundleName { info["CFBundleName"] = bundleName }
        if let displayName { info["CFBundleDisplayName"] = displayName }
        // Bundle(url:) reads Info.plist in plist formats only; JSON would silently
        // yield an empty infoDictionary.
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        return bundleURL
    }
}
