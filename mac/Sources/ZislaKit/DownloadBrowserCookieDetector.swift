import AppKit
import Foundation
import ZislaCore

/// Finds browser cookie stores that belong to browsers actually installed on this Mac.
/// The detector intentionally inspects browser registrations and data files instead of
/// presenting a static menu of browser names.
public struct DownloadBrowserCookieDetector: @unchecked Sendable {
    private let homeDirectory: URL
    private let applicationURLsProvider: @Sendable () -> [URL]
    private let fileManager: FileManager

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationURLs: [URL]? = nil,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.fileManager = fileManager
        if let applicationURLs {
            let urls = applicationURLs.map(\.standardizedFileURL)
            self.applicationURLsProvider = { urls }
        } else {
            self.applicationURLsProvider = Self.defaultApplicationURLs
        }
    }

    public func detect() -> [DownloadBrowserCookieSource] {
        let applications = applicationURLsProvider()
            .compactMap(browserApplication(at:))
            .sorted { lhs, rhs in
                if lhs.displayName.localizedStandardCompare(rhs.displayName) != .orderedSame {
                    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.bundleIdentifier < rhs.bundleIdentifier
            }

        guard !applications.isEmpty else { return [] }

        let supportDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let cookieFiles = cookieDatabaseFiles(in: supportDirectory)
        var sources: [DownloadBrowserCookieSource] = []
        var seen = Set<String>()

        for application in applications {
            if application.ytDLPBrowser == "safari" {
                for cookiesURL in safariCookieDatabases() {
                    guard fileManager.fileExists(atPath: cookiesURL.path) else { continue }
                    appendSource(
                        for: application,
                        profileURL: cookiesURL,
                        cookieDirectory: cookiesURL.deletingLastPathComponent(),
                        profileName: nil,
                        to: &sources,
                        seen: &seen
                    )
                }
                continue
            }

            for cookieFile in cookieFiles {
                guard pathMatches(cookieFile, application: application) else { continue }
                let browser = cookieFile.lastPathComponent == "cookies.sqlite"
                    ? "firefox"
                    : application.ytDLPBrowser
                let profileURL = profileDirectory(for: cookieFile, browser: browser)
                let profileName = profileDisplayName(for: profileURL, browser: browser)
                appendSource(
                    for: application,
                    ytDLPBrowser: browser,
                    profileURL: profileURL,
                    cookieDirectory: profileURL,
                    profileName: profileName,
                    to: &sources,
                    seen: &seen
                )
            }
        }

        return sources.sorted { lhs, rhs in
            let left = lhs.menuTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let right = rhs.menuTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if left != right { return left < right }
            return lhs.id < rhs.id
        }
    }

    private struct BrowserApplication {
        let bundleIdentifier: String
        let displayName: String
        let ytDLPBrowser: String
        let tokens: Set<String>
    }

    private func browserApplication(at url: URL) -> BrowserApplication? {
        guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return nil
        }

        let info = bundle.infoDictionary ?? [:]
        let localizedInfo = bundle.localizedInfoDictionary ?? [:]
        let displayName = (
            localizedInfo["CFBundleDisplayName"] as? String
                ?? localizedInfo["CFBundleName"] as? String
                ?? info["CFBundleDisplayName"] as? String
                ?? info["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return nil }

        let ytDLPBrowser = browserType(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            bundleURL: url
        )
        guard isSupportedBrowserApplication(
            info: info,
            ytDLPBrowser: ytDLPBrowser
        ) else {
            return nil
        }

        let tokens = Set(Self.tokens(in: [displayName, url.deletingPathExtension().lastPathComponent]))
        return BrowserApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            ytDLPBrowser: ytDLPBrowser,
            tokens: tokens
        )
    }

    private func appendSource(
        for application: BrowserApplication,
        ytDLPBrowser: String? = nil,
        profileURL: URL,
        cookieDirectory: URL,
        profileName: String?,
        to sources: inout [DownloadBrowserCookieSource],
        seen: inout Set<String>
    ) {
        let browser = ytDLPBrowser ?? application.ytDLPBrowser
        let profile = profileURL.path
        let id = "\(browser)|\(profileURL.standardizedFileURL.path)"
        guard seen.insert(id).inserted else { return }
        guard let source = DownloadBrowserCookieSource(
            id: id,
            displayName: application.displayName,
            ytDLPBrowser: browser,
            profile: profile,
            cookieDirectory: cookieDirectory,
            profileName: profileName
        ) else {
            seen.remove(id)
            return
        }
        sources.append(source)
    }

    private func cookieDatabaseFiles(in root: URL) -> [URL] {
        guard fileManager.fileExists(atPath: root.path),
              let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let relativeDepth = url.pathComponents.count - root.pathComponents.count
            guard relativeDepth <= 8 else {
                enumerator.skipDescendants()
                continue
            }
            let name = url.lastPathComponent
            guard name == "Cookies" || name == "cookies.sqlite" else { continue }
            if url.pathComponents.contains(where: { $0 == "Cache" || $0 == "Code Cache" || $0 == "GPUCache" }) {
                continue
            }
            files.append(url.standardizedFileURL)
        }
        return files
    }

    private func safariCookieDatabases() -> [URL] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return [
            library.appendingPathComponent("Cookies/Cookies.binarycookies"),
            library.appendingPathComponent(
                "Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
            ),
        ]
    }

    private func pathMatches(_ file: URL, application: BrowserApplication) -> Bool {
        guard !application.tokens.isEmpty else { return false }
        let pathTokens = Set(Self.tokens(in: file.pathComponents))
        return !application.tokens.isDisjoint(with: pathTokens)
    }

    private func profileDirectory(for cookieFile: URL, browser: String) -> URL {
        var current = cookieFile.deletingLastPathComponent()
        if browser == "firefox" { return current.standardizedFileURL }

        while current.pathComponents.count > 1 {
            let name = current.lastPathComponent
            if name == "Default" || name.hasPrefix("Profile ") {
                return current.standardizedFileURL
            }
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }

        current = cookieFile.deletingLastPathComponent()
        while current.pathComponents.count > 1 {
            if fileManager.fileExists(atPath: current.appendingPathComponent("Preferences").path)
                || fileManager.fileExists(atPath: current.appendingPathComponent("Local State").path) {
                return current.standardizedFileURL
            }
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }
        return cookieFile.deletingLastPathComponent().standardizedFileURL
    }

    private func profileDisplayName(for profileURL: URL, browser: String) -> String? {
        guard browser != "firefox" else { return profileURL.lastPathComponent }
        let name = profileURL.lastPathComponent
        guard name == "Default" || name.hasPrefix("Profile ") else { return nil }
        return name
    }

    private func browserType(bundleIdentifier: String, displayName: String, bundleURL: URL) -> String {
        let tokens = Set(Self.tokens(in: [bundleIdentifier, displayName, bundleURL.lastPathComponent]))
        if tokens.contains("safari") { return "safari" }
        if tokens.contains("firefox") { return "firefox" }
        if tokens.contains("brave") { return "brave" }
        if tokens.contains("vivaldi") { return "vivaldi" }
        if tokens.contains("opera") { return "opera" }
        if tokens.contains("whale") { return "whale" }
        if tokens.contains("edge") { return "edge" }
        if tokens.contains("chromium") { return "chromium" }
        return "chrome"
    }

    private func hasWebURLHandler(_ info: [String: Any]) -> Bool {
        guard let urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] else { return false }
        return urlTypes.contains { type in
            let schemes = type["CFBundleURLSchemes"] as? [String] ?? []
            return schemes.contains { scheme in
                scheme.caseInsensitiveCompare("http") == .orderedSame
                    || scheme.caseInsensitiveCompare("https") == .orderedSame
            }
        }
    }

    private func hasWebDocumentHandler(_ info: [String: Any]) -> Bool {
        guard let documentTypes = info["CFBundleDocumentTypes"] as? [[String: Any]] else {
            return false
        }
        let contentTypes = Set(["public.html", "public.xhtml"])
        let extensions = Set(["htm", "html", "xhtml"])
        let mimeTypes = Set(["text/html", "application/xhtml+xml"])
        return documentTypes.contains { type in
            let declaredContentTypes = Set(type["LSItemContentTypes"] as? [String] ?? [])
            let declaredExtensions = Set(type["CFBundleTypeExtensions"] as? [String] ?? [])
            let declaredMIMETypes = Set(type["CFBundleTypeMIMETypes"] as? [String] ?? [])
            return !contentTypes.isDisjoint(with: declaredContentTypes)
                || !extensions.isDisjoint(with: declaredExtensions)
                || !mimeTypes.isDisjoint(with: declaredMIMETypes)
        }
    }

    private func isSupportedBrowserApplication(
        info: [String: Any],
        ytDLPBrowser: String
    ) -> Bool {
        hasWebURLHandler(info)
            && (ytDLPBrowser == "safari" || hasWebDocumentHandler(info))
    }

    private static func tokens(in values: [String]) -> [String] {
        values
            .flatMap { value in
                value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            }
            .filter { $0.count >= 3 && !["app", "com", "browser"].contains($0) }
    }

    private static func defaultApplicationURLs() -> [URL] {
        let handlerURL = URL(string: "https://example.com")!
        var urls = NSWorkspace.shared.urlsForApplications(toOpen: handlerURL)
        let directories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]
        for directory in directories {
            urls += (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )) ?? []
        }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
