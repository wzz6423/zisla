import Foundation
import ZislaCore

public struct YTDLPTools: Equatable, Sendable {
    public let ytDLPURL: URL
    public let ffmpegURL: URL?

    public var capabilities: DownloadCapabilities {
        DownloadCapabilities(hasFFmpeg: ffmpegURL != nil)
    }
}

public enum YTDLPResolverError: Error, Equatable, Sendable, LocalizedError {
    case executableNotFound(searched: [URL])

    /// Installation moved from the Downloads module to Settings, so errors must direct the user there instead of exposing a bare NSError message.
    public var errorDescription: String? {
        "未找到可用的 yt-dlp。请在 设置 → 下载 → 组件 中一键安装后重试。"
    }
}

public struct YTDLPResolver: Sendable {
    public static var defaultYTDLPCandidates: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"),
            URL(fileURLWithPath: "/usr/local/bin/yt-dlp"),
            home.appendingPathComponent(".local/bin/yt-dlp"),
        ]
    }

    public static var defaultFFmpegCandidates: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            URL(fileURLWithPath: "/usr/local/bin/ffmpeg"),
            home.appendingPathComponent(".local/bin/ffmpeg"),
        ]
    }

    private let bundleURL: URL
    private let managedToolsDirectory: URL
    private let externalYTDLPCandidates: [URL]
    private let externalFFmpegCandidates: [URL]

    public init(
        bundleURL: URL = Bundle.main.bundleURL,
        managedToolsDirectory: URL = AppPaths.managedTools,
        externalYTDLPCandidates: [URL]? = nil,
        externalFFmpegCandidates: [URL]? = nil
    ) {
        self.bundleURL = bundleURL
        self.managedToolsDirectory = managedToolsDirectory
        self.externalYTDLPCandidates = externalYTDLPCandidates ?? Self.defaultYTDLPCandidates
        self.externalFFmpegCandidates = externalFFmpegCandidates ?? Self.defaultFFmpegCandidates
    }

    public func resolve() throws -> YTDLPTools {
        let helperDirectory = bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        // The Zisla-downloaded build takes precedence over the bundled one, otherwise the download page's "Update" button would have no effect.
        let ytDLPCandidates = [
            managedToolsDirectory.appendingPathComponent("yt-dlp"),
            helperDirectory.appendingPathComponent("yt-dlp"),
        ] + externalYTDLPCandidates
        guard let ytDLPURL = ytDLPCandidates.lazy.compactMap(Self.trustedExecutable).first else {
            throw YTDLPResolverError.executableNotFound(searched: ytDLPCandidates)
        }

        let ffmpegCandidates = [
            helperDirectory.appendingPathComponent("ffmpeg"),
            ytDLPURL.deletingLastPathComponent().appendingPathComponent("ffmpeg"),
        ] + externalFFmpegCandidates
        let ffmpegURL = ffmpegCandidates.lazy.compactMap(Self.trustedExecutable).first
        return YTDLPTools(ytDLPURL: ytDLPURL, ffmpegURL: ffmpegURL)
    }

    public static func isTrustedExecutable(_ url: URL) -> Bool {
        trustedExecutable(url) != nil
    }

    private static func trustedExecutable(_ candidate: URL) -> URL? {
        guard candidate.isFileURL else { return nil }
        let fileManager = FileManager.default
        let standardizedCandidate = candidate.standardizedFileURL
        guard hasTrustedDirectoryChain(
            from: standardizedCandidate.deletingLastPathComponent()
        ) else {
            return nil
        }

        let resolved = standardizedCandidate.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isExecutableFile(atPath: resolved.path),
              isNotWorldWritable(resolved),
              hasTrustedDirectoryChain(from: resolved.deletingLastPathComponent())
        else {
            return nil
        }
        return resolved
    }

    private static func hasTrustedDirectoryChain(from startURL: URL) -> Bool {
        var directory = startURL.standardizedFileURL
        while true {
            guard isNotWorldWritable(directory) else { return false }
            if directory.standardizedFileURL.path == "/" { break }
            directory = directory.deletingLastPathComponent().standardizedFileURL
        }
        return true
    }

    private static func isNotWorldWritable(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber
        else {
            return false
        }
        return permissions.intValue & 0o002 == 0
    }
}
