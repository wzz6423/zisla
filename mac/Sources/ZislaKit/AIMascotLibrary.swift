import AppKit
import Foundation
import ZislaCore

public enum AIMascotLibrary {
    /// Prefer reading the official icon from a locally installed Qoder client when present; bundle assets are used as offline fallback.
    /// Bundle ID takes priority; `com.qoder.work.cn` is the confirmed local CN host.
    public static let coderBundleIdentifiers = [
        "com.qoder.work.cn",
        "com.qoder.work",
    ]

    /// Fall back to scanning common App directories like /Applications when a bundle ID lookup fails.
    public static let coderApplicationNames = [
        "QoderWork CN",
        "QoderWork",
        "Qoder",
    ]

    /// Prefer reading the official icon from a locally installed TRAE client when present; bundle assets are used as offline fallback.
    public static let traeBundleIdentifiers = [
        "cn.trae.solo.app",
    ]

    public static let traeApplicationNames = [
        "TRAE SOLO CN",
    ]

    /// The harnext data directory's product uses the WorkBuddy official client icon.
    public static let workBuddyBundleIdentifiers = [
        "com.workbuddy.workbuddy",
    ]

    public static let workBuddyApplicationNames = [
        "WorkBuddy",
    ]

    /// Locates the locally installed Qoder/QoderWork.app; returns nil if not found, falling back to bundled brand assets.
    /// Uses injected closures to keep logic pure and testable; defaults to NSWorkspace / FileManager.
    public static func installedCoderApplicationURL(
        resolveBundleIdentifier: (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        applicationDirectories: [URL] = FileManager.default.urls(
            for: .applicationDirectory,
            in: .allDomainsMask
        ),
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        installedApplicationURL(
            bundleIdentifiers: coderBundleIdentifiers,
            applicationNames: coderApplicationNames,
            resolveBundleIdentifier: resolveBundleIdentifier,
            applicationDirectories: applicationDirectories,
            fileExists: fileExists
        )
    }

    /// Locates the locally installed TRAE; returns nil if not found, falling back to bundled brand assets.
    public static func installedTraeApplicationURL(
        resolveBundleIdentifier: (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        applicationDirectories: [URL] = FileManager.default.urls(
            for: .applicationDirectory,
            in: .allDomainsMask
        ),
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        installedApplicationURL(
            bundleIdentifiers: traeBundleIdentifiers,
            applicationNames: traeApplicationNames,
            resolveBundleIdentifier: resolveBundleIdentifier,
            applicationDirectories: applicationDirectories,
            fileExists: fileExists
        )
    }

    /// Locates the locally installed WorkBuddy; returns nil if not found, falling back to bundled brand assets.
    public static func installedWorkBuddyApplicationURL(
        resolveBundleIdentifier: (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        applicationDirectories: [URL] = FileManager.default.urls(
            for: .applicationDirectory,
            in: .allDomainsMask
        ),
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        installedApplicationURL(
            bundleIdentifiers: workBuddyBundleIdentifiers,
            applicationNames: workBuddyApplicationNames,
            resolveBundleIdentifier: resolveBundleIdentifier,
            applicationDirectories: applicationDirectories,
            fileExists: fileExists
        )
    }

    private static func installedApplicationURL(
        bundleIdentifiers: [String],
        applicationNames: [String],
        resolveBundleIdentifier: (String) -> URL?,
        applicationDirectories: [URL],
        fileExists: (URL) -> Bool
    ) -> URL? {
        for identifier in bundleIdentifiers {
            if let url = resolveBundleIdentifier(identifier) {
                return url
            }
        }
        for directory in applicationDirectories {
            for name in applicationNames {
                let candidate = directory.appendingPathComponent("\(name).app", isDirectory: true)
                if fileExists(candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    public static func providerAssetName(for provider: AIProvider) -> String? {
        switch provider {
        case .claude: "claude-color.svg"
        case .codex: "codex-color.svg"
        case .gemini: "gemini-color.svg"
        case .grok: "grok.svg"
        case .gpt: "openai.svg"
        case .copilot: "copilot.svg"
        case .kimi: "kimi.png"
        case .qwen: "qwen-color.svg"
        case .coder: "qoder.icns"
        case .zcode: "zcode.icns"
        case .trae: "trae.icns"
        case .opencode: "opencode.svg"
        case .harness: "workbuddy.icns"
        case .doubao: "doubao.png"
        }
    }

    public static func providerAssetURL(
        for provider: AIProvider,
        resourceRoots: [URL],
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        guard let assetName = providerAssetName(for: provider) else { return nil }
        return providerAssetURL(named: assetName, resourceRoots: resourceRoots, fileExists: fileExists)
    }

    public static func providerAssetURL(
        named assetName: String,
        resourceRoots: [URL],
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        return resourceRoots
            .lazy
            .map { $0.appendingPathComponent("BrandIcons/\(assetName)", isDirectory: false) }
            .first(where: fileExists)
    }

    public static func providerDisplayName(for provider: AIProvider) -> String {
        switch provider {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .grok: "Grok"
        case .gpt: "ChatGPT"
        case .copilot: "GitHub Copilot"
        case .kimi: "Kimi Code"
        case .qwen: "千问"
        case .coder: "Qoder"
        case .zcode: "ZCode"
        case .trae: "TRAE"
        case .opencode: "opencode"
        case .harness: "harnext"
        case .doubao: "豆包"
        }
    }

    public static func provider(fromNoticeID noticeID: String?) -> AIProvider? {
        guard let noticeID = noticeID?.lowercased() else { return nil }
        let prefix = "ai-active-"
        guard noticeID.hasPrefix(prefix) else { return nil }
        let token = noticeID
            .dropFirst(prefix.count)
            .split(separator: "-", maxSplits: 1)
            .first
        return token.flatMap { AIProvider(token: String($0)) }
    }

    public static func uniqueProviders(fromNoticeIDs noticeIDs: [String]) -> [AIProvider] {
        var seen: Set<String> = []
        return noticeIDs.compactMap { noticeID in
            guard let provider = provider(fromNoticeID: noticeID),
                  seen.insert(provider.rawValue).inserted else {
                return nil
            }
            return provider
        }
    }

}
