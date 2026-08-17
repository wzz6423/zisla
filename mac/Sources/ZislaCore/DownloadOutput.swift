import Foundation

public enum YTDLPEvent: Equatable, Sendable {
    case progress(fraction: Double, speed: String, eta: String)
    case completedFile(URL)
    case completedComponent(DownloadedMediaComponent)
}

public enum DownloadedMediaKind: String, Equatable, Sendable {
    case video
    case audio
    case combined
}

public struct DownloadedMediaComponent: Equatable, Sendable {
    public let fileURL: URL
    public let formatID: String
    public let kind: DownloadedMediaKind

    public init(fileURL: URL, formatID: String, kind: DownloadedMediaKind) {
        self.fileURL = fileURL
        self.formatID = formatID
        self.kind = kind
    }
}

public enum YTDLPOutputParser {
    public static let sentinel = "__ZISLA_YTDLP_JSON__"

    public static func parse(_ line: String) -> YTDLPEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(sentinel) else { return nil }

        let payloadStart = trimmed.index(trimmed.startIndex, offsetBy: sentinel.count)
        guard let data = String(trimmed[payloadStart...]).data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return nil
        }

        switch payload.event {
        case "progress":
            guard let percentText = payload.percent else { return nil }
            let normalizedPercent = percentText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: "")
            guard let percent = Double(normalizedPercent), percent.isFinite else { return nil }
            return .progress(
                fraction: min(max(percent / 100, 0), 1),
                speed: payload.speed ?? "",
                eta: payload.eta ?? ""
            )
        case "completed":
            guard let filepath = payload.filepath, !filepath.isEmpty else { return nil }
            return .completedFile(URL(fileURLWithPath: filepath))
        case "component":
            guard let filepath = payload.filepath, !filepath.isEmpty,
                  let formatID = payload.formatID, !formatID.isEmpty,
                  let kind = componentKind(vcodec: payload.vcodec, acodec: payload.acodec)
            else {
                return nil
            }
            return .completedComponent(DownloadedMediaComponent(
                fileURL: URL(fileURLWithPath: filepath),
                formatID: formatID,
                kind: kind
            ))
        default:
            return nil
        }
    }

    private struct Payload: Decodable {
        let event: String
        let percent: String?
        let speed: String?
        let eta: String?
        let filepath: String?
        let formatID: String?
        let vcodec: String?
        let acodec: String?

        private enum CodingKeys: String, CodingKey {
            case event, percent, speed, eta, filepath, vcodec, acodec
            case formatID = "format_id"
        }
    }

    private static func componentKind(vcodec: String?, acodec: String?) -> DownloadedMediaKind? {
        let hasVideo = vcodec?.lowercased() != "none" && vcodec?.isEmpty == false
        let hasAudio = acodec?.lowercased() != "none" && acodec?.isEmpty == false
        switch (hasVideo, hasAudio) {
        case (true, false): return .video
        case (false, true): return .audio
        case (true, true): return .combined
        case (false, false): return nil
        }
    }
}

public enum DownloadOutputPathBuilder {
    public static func destinationURL(
        for component: DownloadedMediaComponent,
        outputDirectory: URL,
        fileExtension: String? = nil
    ) -> URL {
        let sourceExtension = component.fileURL.pathExtension
        var stem = component.fileURL.deletingPathExtension().lastPathComponent
        let formatSuffix = ".\(component.formatID)"
        if stem.hasSuffix(formatSuffix) {
            stem.removeLast(formatSuffix.count)
        }
        let destinationExtension = fileExtension ?? sourceExtension
        return outputDirectory
            .appendingPathComponent(stem)
            .appendingPathExtension(destinationExtension)
            .standardizedFileURL
    }
}

public enum DownloadFailureDiagnostics {
    public static func actionableMessage(rawDiagnostic: String, urlString: String) -> String {
        guard isBilibiliHTTP412(rawDiagnostic: rawDiagnostic, urlString: urlString) else {
            return rawDiagnostic
        }
        return "B站返回 HTTP 412 风控拦截。请先在浏览器登录 B站并完成验证，稍后或更换网络重试；若仍被拦截，需要 Cookies 导入支持后再下载。"
    }

    public static func isBilibiliHTTP412(
        rawDiagnostic: String,
        urlString: String
    ) -> Bool {
        isBilibiliURL(urlString) && isHTTP412(rawDiagnostic)
    }

    public static func shouldUseBilibiliNativeFallback(
        rawDiagnostic: String,
        urlString: String
    ) -> Bool {
        isBilibiliURL(urlString)
            && (isHTTP412(rawDiagnostic) || isRequestedFormatUnavailable(rawDiagnostic))
    }

    public static func isBilibiliURL(_ string: String) -> Bool {
        guard let host = URL(string: string)?.host?.lowercased() else { return false }
        return host == "bilibili.com" || host.hasSuffix(".bilibili.com")
            || host == "b23.tv" || host.hasSuffix(".b23.tv")
    }

    private static func isHTTP412(_ diagnostic: String) -> Bool {
        let value = diagnostic.lowercased()
        return value.contains("http error 412")
            || value.contains("http 412")
            || value.contains("412: precondition failed")
    }

    private static func isRequestedFormatUnavailable(_ diagnostic: String) -> Bool {
        diagnostic.localizedCaseInsensitiveContains("requested format is not available")
    }
}

public enum DownloadOutputPathValidator {
    public static func normalizedFileURL(_ fileURL: URL, within outputDirectory: URL) -> URL? {
        guard fileURL.isFileURL, outputDirectory.isFileURL else { return nil }

        let directory = outputDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let directoryPath = directory.path
        let childPrefix = directoryPath == "/" ? "/" : directoryPath + "/"

        guard candidate.path.hasPrefix(childPrefix) else { return nil }
        return candidate
    }
}

public enum HTTPURLParser {
    public static func url(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \Character.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

public enum DownloadURLClassifier {
    private static let supportedHosts: Set<String> = [
        "youtube.com", "youtu.be", "bilibili.com", "b23.tv",
        "vimeo.com", "twitter.com", "x.com", "tiktok.com",
        "twitch.tv", "dailymotion.com",
        // Common Chinese video/music and shared-link hosts. yt-dlp still
        // decides whether a particular page is downloadable; this list only
        // controls whether clipboard/drag UI offers the download affordance.
        "v.qq.com", "video.qq.com", "weixin.qq.com", "mp.weixin.qq.com",
        "channels.weixin.qq.com",
        "youku.com", "mgtv.com", "iqiyi.com",
        "music.apple.com", "itunes.apple.com", "y.qq.com",
        "music.163.com", "kugou.com", "kuwo.cn",
    ]

    private static let mediaExtensions: Set<String> = [
        "mp4", "mkv", "webm", "mov", "m4v", "avi", "flv",
        "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus",
    ]

    public static func isLikelyDownloadable(_ string: String) -> Bool {
        guard let url = HTTPURLParser.url(from: string),
              let host = url.host?.lowercased() else {
            return false
        }

        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if supportedHosts.contains(where: { bareHost == $0 || bareHost.hasSuffix(".\($0)") }) {
            return true
        }
        return mediaExtensions.contains(url.pathExtension.lowercased())
    }
}

public struct ClipboardLinkDetector: Sendable {
    private let recentCapacity: Int
    private var lastChangeCount: Int?
    private var recentLinks: [String] = []
    private var recentLinkSet: Set<String> = []

    public init(recentCapacity: Int = 32) {
        self.recentCapacity = max(recentCapacity, 1)
    }

    public mutating func begin(atChangeCount changeCount: Int) {
        lastChangeCount = changeCount
    }

    public mutating func detect(changeCount: Int, string: String?) -> URL? {
        guard changeCount != lastChangeCount else { return nil }
        lastChangeCount = changeCount
        guard let string else { return nil }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DownloadURLClassifier.isLikelyDownloadable(trimmed),
              let url = URL(string: trimmed)
        else {
            return nil
        }

        let key = url.absoluteString
        guard recentLinkSet.insert(key).inserted else { return nil }
        recentLinks.append(key)
        if recentLinks.count > recentCapacity {
            recentLinkSet.remove(recentLinks.removeFirst())
        }
        return url
    }
}
