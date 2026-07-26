import Foundation
import ZislaCore

/// Platform identified by the native downloader. Used to resolve the official logo on the collapsed left side.
public enum VideoDownloadPlatform: String, CaseIterable, Sendable {
    case youtube
    case bilibili
    case douyin
    case xiaohongshu
    case weibo
    case tiktok
    case instagram

    public var displayName: String {
        switch self {
        case .youtube: "YouTube"
        case .bilibili: "哔哩哔哩"
        case .douyin: "抖音"
        case .xiaohongshu: "小红书"
        case .weibo: "微博"
        case .tiktok: "TikTok"
        case .instagram: "Instagram"
        }
    }

    /// Bundled offline asset name, located in `Resources/BrandIcons/`.
    public var assetName: String {
        switch self {
        case .youtube: "youtube.svg"
        case .bilibili: "bilibili.svg"
        case .douyin: "douyin.svg"
        case .xiaohongshu: "xiaohongshu.svg"
        case .weibo: "weibo.svg"
        case .tiktok: "tiktok.svg"
        case .instagram: "instagram.svg"
        }
    }

    /// Location of the bundled logo; returns nil for platforms not included in the upstream icon library (e.g. Douyin),
    /// in which case the caller falls back to fetching the site's own favicon — still an official icon.
    public var bundledIconURL: URL? {
        AppPaths.bundledResource(relativePath: "BrandIcons/\(assetName)")
    }

    /// Bare hostnames used for matching; short-link domains are included to identify links before any redirect.
    var hosts: [String] {
        switch self {
        case .youtube: ["youtube.com", "youtu.be", "youtube-nocookie.com"]
        case .bilibili: ["bilibili.com", "b23.tv", "bilibili.tv"]
        case .douyin: ["douyin.com", "iesdouyin.com"]
        case .xiaohongshu: ["xiaohongshu.com", "xhslink.com"]
        case .weibo: ["weibo.com", "weibo.cn", "t.cn"]
        case .tiktok: ["tiktok.com", "vt.tiktok.com"]
        case .instagram: ["instagram.com", "instagr.am"]
        }
    }
}

/// Resolves the source platform from a download URL. Pure function, easy to unit-test.
public enum VideoDownloadPlatformResolver {
    /// Returns the matching enum when a built-in platform is recognized; otherwise returns nil and the caller falls back to favicon.
    public static func platform(forURLString string: String) -> VideoDownloadPlatform? {
        guard let host = bareHost(ofURLString: string) else { return nil }
        for platform in VideoDownloadPlatform.allCases
        where platform.hosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return platform
        }
        return nil
    }

    /// Favicon for long-tail sites is cached by bare hostname; strip `www.` to avoid duplicate fetches for the same site.
    public static func bareHost(ofURLString string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = URL(string: trimmed)?.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// When no platform is recognized, uses the domain body as the display name (e.g. `v.qq.com` → `v.qq.com`).
    public static func displayName(forURLString string: String) -> String? {
        platform(forURLString: string)?.displayName ?? bareHost(ofURLString: string)
    }
}

/// Collapsed download bar frame state.
public struct VideoDownloadSnapshot: Equatable, Sendable {
    public var platform: VideoDownloadPlatform?
    /// Used to fetch the favicon when no built-in platform matches, and also as the accessibility label when no icon is available.
    public var host: String?
    public var sourceName: String
    public var fraction: Double?
    public var isFinished: Bool

    public init(
        platform: VideoDownloadPlatform?,
        host: String?,
        sourceName: String,
        fraction: Double?,
        isFinished: Bool
    ) {
        self.platform = platform
        self.host = host
        self.sourceName = sourceName
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.isFinished = isFinished
    }

    /// Caps progress at 99% during download, reserving 100% for the success checkmark, to avoid visual duplication of the two states.
    public var progressText: String {
        guard let fraction else { return isFinished ? "100%" : "…" }
        if isFinished { return "100%" }
        return "\(min(99, Int(fraction * 100)))%"
    }
}
