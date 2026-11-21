import AppKit
import Darwin
import Foundation
import ZislaCore

public enum AIAccountBalanceBrowserCookieError: Error, Equatable, Sendable {
    case noDefaultBrowser, unsupportedBrowser, cookiesNotFound, accessFailed, invalidData

    public var statusKey: String {
        switch self {
        case .noDefaultBrowser: "无法识别默认浏览器，请手动粘贴 Cookie"
        case .unsupportedBrowser: "默认浏览器暂不支持 Cookie 导入，请手动粘贴"
        case .cookiesNotFound: "未找到当前网站的 Cookie，请在默认浏览器登录或手动粘贴"
        case .accessFailed, .invalidData: "无法读取默认浏览器 Cookie，请手动粘贴或检查访问权限"
        }
    }
}

public struct AIAccountBalanceBrowserCookieImporter: Sendable {
    private let store: AIAccountBalanceCookieStore
    private let source: AIAccountBalanceBrowserCookieSourceResolver
    private let reader: AIAccountBalanceBrowserCookieReader

    public init(store: AIAccountBalanceCookieStore = AIAccountBalanceCookieStore()) {
        self.init(store: store, source: AIAccountBalanceBrowserCookieSourceResolver(), reader: AIAccountBalanceBrowserCookieReader())
    }

    init(store: AIAccountBalanceCookieStore, source: AIAccountBalanceBrowserCookieSourceResolver,
         reader: AIAccountBalanceBrowserCookieReader) {
        self.store = store
        self.source = source
        self.reader = reader
    }

    public func importCookie(for website: AIAccountBalanceWebsite) throws {
        let source = try source.resolve(for: website)
        let header = try reader.header(from: source, website: website)
        try store.setCookie(header, for: website)
    }
}

struct AIAccountBalanceBrowserCookieSource: Sendable {
    let browser: BrowserDownloadAgent
    let databaseURL: URL
    let keychainAccount: String?
}

struct AIAccountBalanceBrowserCookieSourceResolver: Sendable {
    var home: URL = FileManager.default.homeDirectoryForCurrentUser
    var defaultApplication: @Sendable (URL) -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: $0) }

    func resolve(for website: AIAccountBalanceWebsite) throws -> AIAccountBalanceBrowserCookieSource {
        guard let application = defaultApplication(website.dashboard) else {
            throw AIAccountBalanceBrowserCookieError.noDefaultBrowser
        }
        guard let bundleID = Bundle(url: application)?.bundleIdentifier,
              let browser = BrowserDownloadAgentResolver.agent(forQuarantineAgentName: bundleID),
              browser.bundleIdentifiers.contains(bundleID) else {
            throw AIAccountBalanceBrowserCookieError.unsupportedBrowser
        }
        let library = home.resolvingSymlinksInPath().appendingPathComponent("Library", isDirectory: true)
        if browser == .safari {
            guard bundleID == "com.apple.Safari" else { throw AIAccountBalanceBrowserCookieError.unsupportedBrowser }
            let file = try firstExisting([
                library.appendingPathComponent("Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"),
                library.appendingPathComponent("Cookies/Cookies.binarycookies"),
            ])
            return AIAccountBalanceBrowserCookieSource(browser: browser, databaseURL: file, keychainAccount: nil)
        }
        let support = library.appendingPathComponent("Application Support", isDirectory: true)
        if browser == .firefox {
            guard bundleID == "org.mozilla.firefox" else { throw AIAccountBalanceBrowserCookieError.unsupportedBrowser }
            let root = support.appendingPathComponent("Firefox", isDirectory: true)
            let profile = try firefoxProfile(in: root)
            return AIAccountBalanceBrowserCookieSource(browser: browser,
                                                       databaseURL: try firstExisting([profile.appendingPathComponent("cookies.sqlite")]), keychainAccount: nil)
        }
        let directory: String
        let account: String
        switch browser {
        case .chrome:
            directory = bundleID == "com.google.Chrome.beta" ? "Google/Chrome Beta"
                : bundleID == "com.google.Chrome.canary" ? "Google/Chrome Canary" : "Google/Chrome"
            account = "Chrome"
        case .edge:
            directory = bundleID == "com.microsoft.edgemac.Beta" ? "Microsoft Edge Beta" : "Microsoft Edge"
            account = "Microsoft Edge"
        case .brave:
            directory = bundleID == "com.brave.Browser.beta" ? "BraveSoftware/Brave-Browser-Beta" : "BraveSoftware/Brave-Browser"
            account = "Brave"
        case .vivaldi: directory = "Vivaldi"; account = "Vivaldi"
        case .opera:
            directory = bundleID == "com.operasoftware.OperaGX" ? "com.operasoftware.OperaGX" : "com.operasoftware.Opera"
            account = "Opera"
        default: throw AIAccountBalanceBrowserCookieError.unsupportedBrowser
        }
        let root = support.appendingPathComponent(directory, isDirectory: true)
        let profile: URL
        if browser == .opera {
            profile = root
        } else if let metadata = try regularData(root.appendingPathComponent("Local State")) {
            guard let json = try? JSONSerialization.jsonObject(with: metadata) as? [String: Any],
                  let name = (json["profile"] as? [String: Any])?["last_used"] as? String,
                  safeProfileName(name) else { throw AIAccountBalanceBrowserCookieError.invalidData }
            profile = root.appendingPathComponent(name, isDirectory: true)
        } else {
            profile = root.appendingPathComponent("Default", isDirectory: true)
        }
        return AIAccountBalanceBrowserCookieSource(browser: browser, databaseURL: try firstExisting([
            profile.appendingPathComponent("Network/Cookies"), profile.appendingPathComponent("Cookies"),
        ]), keychainAccount: account)
    }

    private func firefoxProfile(in root: URL) throws -> URL {
        guard let data = try regularData(root.appendingPathComponent("profiles.ini")),
              let text = String(data: data, encoding: .utf8) else { throw AIAccountBalanceBrowserCookieError.cookiesNotFound }
        var sections: [(String, [String: String])] = []
        for line in text.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") { sections.append((String(line.dropFirst().dropLast()), [:])) }
            else if let index = line.firstIndex(of: "="), !sections.isEmpty {
                sections[sections.count - 1].1[String(line[..<index])] = String(line[line.index(after: index)...])
            }
        }
        let installedDefaults = Set(sections.filter { $0.0.hasPrefix("Install") }.compactMap { $0.1["Default"] })
        let defaults = installedDefaults.isEmpty ? Set(sections.filter {
            $0.0.hasPrefix("Profile") && $0.1["Default"] == "1" && $0.1["IsRelative"] == "1"
        }.compactMap { $0.1["Path"] }) : installedDefaults
        guard defaults.count == 1, let path = defaults.first,
              path.hasPrefix("Profiles/"), safeProfileName(String(path.dropFirst(9))) else {
            throw AIAccountBalanceBrowserCookieError.invalidData
        }
        return root.appendingPathComponent(path, isDirectory: true)
    }

    private func safeProfileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name.utf8.count <= 160
            && !name.contains("/") && !name.contains("\\") && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private func regularData(_ url: URL) throws -> Data? {
        guard url.standardizedFileURL == url.resolvingSymlinksInPath() else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        do { return try AIAccountBalanceCredentials.readRegularFile(url) }
        catch { throw AIAccountBalanceBrowserCookieError.accessFailed }
    }

    private func firstExisting(_ urls: [URL]) throws -> URL {
        for url in urls {
            guard url.standardizedFileURL == url.resolvingSymlinksInPath() else { throw AIAccountBalanceBrowserCookieError.accessFailed }
            var metadata = stat()
            if lstat(url.path, &metadata) == 0 {
                guard metadata.st_mode & S_IFMT == S_IFREG else { throw AIAccountBalanceBrowserCookieError.accessFailed }
                return url
            }
            guard errno == ENOENT else { throw AIAccountBalanceBrowserCookieError.accessFailed }
        }
        throw AIAccountBalanceBrowserCookieError.cookiesNotFound
    }
}
