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
        if isDouyinCookieFailure(rawDiagnostic: rawDiagnostic, urlString: urlString) {
            return douyinCookieFailureMessage
        }
        guard isBilibiliHTTP412(rawDiagnostic: rawDiagnostic, urlString: urlString) else {
            return rawDiagnostic
        }
        return AppLocalization.text("B站返回 HTTP 412 风控拦截。请先在浏览器登录 B站并完成验证，稍后或更换网络重试；若仍被拦截，需要 Cookies 导入支持后再下载。")
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

    public static func isDouyinCookieFailure(
        rawDiagnostic: String,
        urlString: String
    ) -> Bool {
        guard isDouyinURL(urlString) else { return false }
        let diagnostic = rawDiagnostic.lowercased()
        return diagnostic.contains("fresh cookies")
            || (diagnostic.contains("http 403") && diagnostic.contains("cookies"))
    }

    public static func requiresBrowserCookies(
        rawDiagnostic: String,
        urlString: String
    ) -> Bool {
        guard isDouyinURL(urlString) else { return false }
        return isDouyinCookieFailure(rawDiagnostic: rawDiagnostic, urlString: urlString)
            || isDouyinCookieFailureMessage(rawDiagnostic)
    }

    public static func shouldRetryWithoutBrowserCookies(
        rawDiagnostic: String,
        browserCookieSource: DownloadBrowserCookieSource?
    ) -> Bool {
        guard browserCookieSource != nil else { return false }
        return isBrowserCookieDatabaseUnavailable(rawDiagnostic)
    }

    public static func canTryAnotherBrowserCookieSource(
        rawDiagnostic: String,
        urlString: String
    ) -> Bool {
        requiresBrowserCookies(rawDiagnostic: rawDiagnostic, urlString: urlString)
            || isBrowserCookieDatabaseUnavailable(rawDiagnostic)
    }

    public static func isBrowserCookiePermissionDenied(_ rawDiagnostic: String) -> Bool {
        rawDiagnostic.lowercased().range(
            of: #"(?:operation not permitted|permission denied): ['"][^\r\n]*/cookies(?:\.binarycookies|\.sqlite)?['"]"#,
            options: .regularExpression
        ) != nil
    }

    public static var browserCookieAccessFailureMessage: String {
        AppLocalization.text(browserCookieAccessFailureKey)
    }

    public static func requiresBrowserCookieAccess(_ message: String) -> Bool {
        AppLanguage.allCases.contains {
            message == AppLocalization.string(browserCookieAccessFailureKey, language: $0)
        }
    }

    private static func isBrowserCookieDatabaseUnavailable(_ rawDiagnostic: String) -> Bool {
        let diagnostic = rawDiagnostic.lowercased()
        return (diagnostic.contains("could not find")
            && diagnostic.contains("cookies database")
        ) || (
            diagnostic.contains("cookies")
                && (diagnostic.contains("cannot decrypt") || diagnostic.contains("failed to decrypt"))
        ) || diagnostic.range(
            of: #"(?:operation not permitted|permission denied|no such file or directory): ['"][^\r\n]*/cookies(?:\.binarycookies|\.sqlite)?['"]"#,
            options: .regularExpression
        ) != nil
    }

    public static func isDouyinURL(_ string: String) -> Bool {
        guard let host = HTTPURLParser.url(from: string)?.host?.lowercased() else { return false }
        return host == "douyin.com" || host.hasSuffix(".douyin.com")
            || host == "iesdouyin.com" || host.hasSuffix(".iesdouyin.com")
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

    private static var douyinCookieFailureMessage: String {
        AppLocalization.text(douyinCookieFailureKey)
    }

    private static func isDouyinCookieFailureMessage(_ value: String) -> Bool {
        AppLanguage.allCases.contains {
            value == AppLocalization.string(douyinCookieFailureKey, language: $0)
        }
    }

    private static let douyinCookieFailureKey = "抖音返回 HTTP 403，需要近期浏览器 Cookies。请选择可用的浏览器 Cookies 后重试；无需登录。"
    private static let browserCookieAccessFailureKey = "无法读取浏览器 Cookies。请在「系统设置 → 隐私与安全性 → 完全磁盘访问」中允许 zisla，然后重启应用重试。"
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
        guard !trimmed.isEmpty else { return nil }

        let candidate = markdownURLString(from: trimmed)
            ?? duplicatedMarkdownURLString(from: trimmed)
            ?? trimmed
        if let url = standaloneHTTPURL(from: candidate) {
            return url
        }
        return detectedHTTPURL(in: trimmed)
    }

    private static func standaloneHTTPURL(from candidate: String) -> URL? {
        guard !candidate.isEmpty, !candidate.contains(where: \Character.isWhitespace) else {
            return nil
        }

        if let url = completeHTTPURL(from: candidate) {
            return url
        }
        if candidate.hasPrefix("//") {
            return completeHTTPURL(from: "https:\(candidate)")
        }
        guard !candidate.contains("://"),
              !candidate.contains("@"),
              let url = completeHTTPURL(from: "https://\(candidate)"),
              isBareWebHost(url.host, candidate: candidate) else {
            return nil
        }
        return url
    }

    private static func completeHTTPURL(from candidate: String) -> URL? {
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return normalizedDouyinURL(url)
    }

    private static func normalizedDouyinURL(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              host == "douyin.com" || host == "www.douyin.com",
              url.path == "/jingxuan" || url.path == "/jingxuan/",
              let videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "modal_id" })?
                .value,
              (1...30).contains(videoID.utf8.count),
              videoID.utf8.allSatisfy({ (48...57).contains($0) }) else {
            return url
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.douyin.com"
        components.path = "/video/\(videoID)"
        return components.url ?? url
    }

    private static func isBareWebHost(_ host: String?, candidate: String) -> Bool {
        guard let host, !host.isEmpty else { return false }
        guard hasValidBareHostCharacters(candidate) else { return false }
        return host.lowercased() == "localhost" || host.contains(".") || host.contains(":")
    }

    private static func hasValidBareHostCharacters(_ candidate: String) -> Bool {
        let authority = candidate.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        if authority.hasPrefix("[") {
            return true
        }
        let rawHost = authority.split(separator: ":", maxSplits: 1).first ?? ""
        let allowedCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-."))
        return !rawHost.isEmpty && rawHost.unicodeScalars.allSatisfy(allowedCharacters.contains)
    }

    private static func markdownURLString(from string: String) -> String? {
        if string.first == "<", string.last == ">", string.count > 2 {
            return String(string.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let content = string.hasPrefix("!") ? String(string.dropFirst()) : string
        guard content.first == "[",
              let closingBracket = content.firstIndex(of: "]") else {
            return nil
        }
        let openingParenthesis = content.index(after: closingBracket)
        guard openingParenthesis < content.endIndex,
              content[openingParenthesis] == "(",
              content.last == ")" else {
            return nil
        }
        let destinationStart = content.index(after: openingParenthesis)
        let destinationEnd = content.index(before: content.endIndex)
        let destination = String(content[destinationStart..<destinationEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return nil }

        if destination.first == "<", destination.last == ">", destination.count > 2 {
            return String(destination.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return destination
    }

    private static func duplicatedMarkdownURLString(from string: String) -> String? {
        guard !string.hasPrefix("["),
              let separator = string.range(of: "](") else {
            return nil
        }
        let source = String(string[..<separator.lowerBound])
        var destination = String(string[separator.upperBound...])
        if destination.last == ")" {
            destination.removeLast()
        }
        return source == destination ? source : nil
    }

    private static func detectedHTTPURL(in string: String) -> URL? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return nil
        }
        let range = NSRange(string.startIndex..., in: string)
        for match in detector.matches(in: string, options: [], range: range) {
            guard let matchRange = Range(match.range, in: string),
                  let detectedURL = match.url else {
                continue
            }
            var candidate = String(string[matchRange])
            if candidate.last == "]", matchRange.upperBound < string.endIndex,
               string[matchRange.upperBound] == "(" {
                candidate.removeLast()
            }
            if let url = completeHTTPURL(from: candidate)
                ?? completeHTTPURL(from: detectedURL.absoluteString) {
                return url
            }
        }
        return nil
    }
}

public enum DownloadURLClassifier {
    private static let supportedHosts: Set<String> = [
        "youtube.com", "youtu.be", "bilibili.com", "b23.tv",
        "vimeo.com", "twitter.com", "x.com", "tiktok.com",
        "twitch.tv", "dailymotion.com",
        "douyin.com", "iesdouyin.com",
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
        guard let url = HTTPURLParser.url(from: trimmed) else { return nil }

        let key = url.absoluteString
        guard recentLinkSet.insert(key).inserted else { return nil }
        recentLinks.append(key)
        if recentLinks.count > recentCapacity {
            recentLinkSet.remove(recentLinks.removeFirst())
        }
        return url
    }
}
