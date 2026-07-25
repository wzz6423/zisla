import AppKit
import Foundation
import ZislaCore

public enum AIMascotLibrary {
    /// Qoder 没有随包附带的品牌资源，改为运行时读取本机 App 图标。
    /// bundle id 优先，`com.qoder.work.cn` 为本机已确认的中国版宿主。
    public static let coderBundleIdentifiers = [
        "com.qoder.work.cn",
        "com.qoder.work",
    ]

    /// bundle id 查不到时按常见 App 名称回退到 /Applications 等目录。
    public static let coderApplicationNames = [
        "QoderWork CN",
        "QoderWork",
        "Qoder",
    ]

    /// TRAE 不随 Zisla 打包，使用本机已安装客户端提供的官方图标。
    public static let traeBundleIdentifiers = [
        "cn.trae.solo.app",
    ]

    public static let traeApplicationNames = [
        "TRAE SOLO CN",
    ]

    /// harnext 数据目录对应的产品使用 WorkBuddy 官方客户端图标。
    public static let workBuddyBundleIdentifiers = [
        "com.workbuddy.workbuddy",
    ]

    public static let workBuddyApplicationNames = [
        "WorkBuddy",
    ]

    /// 定位本机安装的 Qoder/QoderWork.app；找不到返回 nil（保留 SF Symbol 回退）。
    /// 通过注入闭包保持纯逻辑可测，默认走 NSWorkspace / FileManager。
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

    /// 定位本机安装的 TRAE；找不到返回 nil，由 UI 保留通用回退。
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

    /// 定位本机安装的 WorkBuddy；找不到返回 nil，由 UI 保留通用回退。
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
        case .qwen: "qwen-color.svg"
        case .coder: nil
        case .trae: nil
        case .opencode: "opencode.svg"
        case .harness: nil
        case .doubao: "doubao-color.svg"
        }
    }

    public static func providerDisplayName(for provider: AIProvider) -> String {
        switch provider {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .grok: "Grok"
        case .gpt: "ChatGPT"
        case .qwen: "千问"
        case .coder: "Qoder"
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
