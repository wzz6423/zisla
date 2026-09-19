import Foundation
import Testing
import ZislaCore

@testable import ZislaKit

struct DownloadBrowserCookieDetectorTests {
    @Test
    func detectsInstalledBrowserProfilesAndIgnoresUnrelatedChromiumData() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let chrome = try Self.makeBrowserApp(
            named: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            in: applications
        )
        let arc = try Self.makeBrowserApp(
            named: "Arc",
            bundleIdentifier: "company.thebrowser.Browser",
            in: applications
        )
        let quark = try Self.makeBrowserApp(
            named: "Quark",
            bundleIdentifier: "com.example.Quark",
            in: applications
        )
        let zen = try Self.makeBrowserApp(
            named: "Zen",
            bundleIdentifier: "com.example.Zen",
            in: applications
        )
        let unrelated = try Self.makeBrowserApp(
            named: "Code",
            bundleIdentifier: "com.example.Code",
            in: applications,
            handlesWebDocuments: false
        )

        let home = root.appendingPathComponent("Home", isDirectory: true)
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        try Self.touch(support.appendingPathComponent("Google/Chrome/Default/Network/Cookies"))
        try Self.touch(support.appendingPathComponent("Google/Chrome/Profile 1/Cookies"))
        try Self.touch(support.appendingPathComponent("Arc/User Data/Default/Cookies"))
        try Self.touch(support.appendingPathComponent("Quark/Default/Cookies"))
        try Self.touch(support.appendingPathComponent("Zen/Profiles/test.default-release/cookies.sqlite"))
        try Self.touch(support.appendingPathComponent("Code/Default/Cookies"))

        let detector = DownloadBrowserCookieDetector(
            homeDirectory: home,
            applicationURLs: [chrome, arc, quark, zen, unrelated]
        )
        let sources = detector.detect()

        #expect(sources.count == 5)
        #expect(sources.map(\.displayName) == ["Arc", "Google Chrome", "Google Chrome", "Quark", "Zen"])
        #expect(sources.map(\.profileName) == ["Default", "Default", "Profile 1", "Default", "test.default-release"])
        #expect(sources.first?.ytDLPBrowser == "chrome")
        #expect(sources.last?.ytDLPBrowser == "firefox")
        #expect(sources.allSatisfy { $0.ytDLPBrowserSpecification.contains(":" ) })
        #expect(sources.allSatisfy { !$0.ytDLPBrowserSpecification.contains("\n") })
    }

    @Test
    func detectsSafariAndFirefoxOnlyWhenTheirCookieStoresExist() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let safari = try Self.makeBrowserApp(
            named: "Safari",
            bundleIdentifier: "com.apple.Safari",
            in: applications
        )
        let firefox = try Self.makeBrowserApp(
            named: "Firefox",
            bundleIdentifier: "org.mozilla.firefox",
            in: applications
        )
        let edge = try Self.makeBrowserApp(
            named: "Microsoft Edge",
            bundleIdentifier: "com.microsoft.edgemac",
            in: applications
        )
        let home = root.appendingPathComponent("Home", isDirectory: true)
        try Self.touch(home.appendingPathComponent("Library/Cookies/Cookies.binarycookies"))
        try Self.touch(home.appendingPathComponent(
            "Library/Application Support/Firefox/Profiles/test.default-release/cookies.sqlite"
        ))

        let detector = DownloadBrowserCookieDetector(
            homeDirectory: home,
            applicationURLs: [safari, firefox, edge]
        )
        let sources = detector.detect()

        #expect(sources.count == 2)
        #expect(sources.contains { $0.ytDLPBrowser == "safari" })
        #expect(sources.contains { $0.ytDLPBrowser == "firefox" })
        #expect(!sources.contains { $0.ytDLPBrowser == "edge" })
    }

    @Test
    func duplicateApplicationsProduceOneStableSource() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let chrome = try Self.makeBrowserApp(
            named: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            in: applications
        )
        let home = root.appendingPathComponent("Home", isDirectory: true)
        try Self.touch(home.appendingPathComponent(
            "Library/Application Support/Google/Chrome/Default/Cookies"
        ))

        let detector = DownloadBrowserCookieDetector(
            homeDirectory: home,
            applicationURLs: [chrome, chrome]
        )
        let first = detector.detect()
        let second = detector.detect()

        #expect(first == second)
        #expect(first.count == 1)
        #expect(first.first?.id == "chrome|\(home.path)/Library/Application Support/Google/Chrome/Default")
    }

    @Test
    func returnsNoSourcesWithoutAnInstalledBrowserOrCookieDatabase() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let chrome = try Self.makeBrowserApp(
            named: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            in: applications
        )
        let home = root.appendingPathComponent("Home", isDirectory: true)

        #expect(DownloadBrowserCookieDetector(
            homeDirectory: home,
            applicationURLs: []
        ).detect().isEmpty)
        #expect(DownloadBrowserCookieDetector(
            homeDirectory: home,
            applicationURLs: [chrome]
        ).detect().isEmpty)
    }

    @Test
    func rejectsCookieProfilesThatCannotBeRepresentedByYTDLP() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let chrome = try Self.makeBrowserApp(
            named: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            in: applications
        )
        let home = root.appendingPathComponent("Home:Unsafe", isDirectory: true)
        try Self.touch(home.appendingPathComponent(
            "Library/Application Support/Google/Chrome/Default/Cookies"
        ))

        let sources = DownloadBrowserCookieDetector(
            homeDirectory: home,
            applicationURLs: [chrome]
        ).detect()

        #expect(sources.isEmpty)
    }

    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-browser-detector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func makeBrowserApp(
        named name: String,
        bundleIdentifier: String,
        in directory: URL,
        handlesWebDocuments: Bool = true
    ) throws -> URL {
        let url = directory.appendingPathComponent("\(name).app", isDirectory: true)
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(
            at: infoURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleURLTypes": [[
                "CFBundleURLName": "Web",
                "CFBundleURLSchemes": ["http", "https"],
            ]],
        ]
        if handlesWebDocuments {
            info["CFBundleDocumentTypes"] = [[
                "CFBundleTypeRole": "Viewer",
                "LSItemContentTypes": ["public.html", "public.xhtml"],
            ]]
        }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: infoURL)
        return url
    }

    private static func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url)
    }
}
