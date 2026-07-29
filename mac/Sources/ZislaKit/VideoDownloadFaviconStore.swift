import Foundation

/// Official icon source for long-tail sites: only requests favicons from the target site itself,
/// without routing through any third-party icon service, so the user's download activity is not
/// leaked to additional parties (the target site is already the yt-dlp request destination).
public protocol VideoDownloadFaviconFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct VideoDownloadFaviconURLSessionFetcher: VideoDownloadFaviconFetching {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VideoDownloadFaviconError.badResponse
        }
        return data
    }
}

public enum VideoDownloadFaviconError: Error, Equatable {
    case badResponse
    case tooLarge
    case notFound
}

/// Fetches and persists site icon cache to disk. Cache hits produce no network requests.
public actor VideoDownloadFaviconStore {
    /// Candidate relative paths tried in order: high-resolution first, falling back to the traditional favicon.ico.
    static let candidatePaths = [
        "/apple-touch-icon.png",
        "/apple-touch-icon-precomposed.png",
        "/favicon.ico",
    ]

    private static let maximumByteCount = 512 * 1024

    /// Sites often answer a nonexistent icon path with "200 + a JSON error body" (Douyin's /apple-touch-icon.png does exactly this).
    /// Relying on the status code alone would write that error body into the disk cache as an icon and pollute the domain permanently, so confirm it really is an image by magic number.
    static func looksLikeImage(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 4 else { return false }
        switch (bytes[0], bytes[1], bytes[2], bytes[3]) {
        case (0x89, 0x50, 0x4E, 0x47): return true  // PNG
        case (0x00, 0x00, 0x01, 0x00): return true  // ICO
        case (0x00, 0x00, 0x02, 0x00): return true  // CUR
        case (0x47, 0x49, 0x46, 0x38): return true  // GIF
        case (0xFF, 0xD8, 0xFF, _): return true  // JPEG
        case (0x52, 0x49, 0x46, 0x46):  // RIFF container, still needs a WEBP check
            return bytes.count >= 12 && Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50]
        default: return false
        }
    }

    private let fetcher: any VideoDownloadFaviconFetching
    private let directory: URL
    private let fileManager: FileManager
    private var memoryCache: [String: Data] = [:]
    /// Records domains with no icon in a negative cache to avoid three failed requests on every download.
    private var knownMisses: Set<String> = []

    public init(
        fetcher: any VideoDownloadFaviconFetching = VideoDownloadFaviconURLSessionFetcher(),
        directory: URL = AppPaths.favicons,
        fileManager: FileManager = .default
    ) {
        self.fetcher = fetcher
        self.directory = directory
        self.fileManager = fileManager
    }

    public func icon(forHost host: String) async -> Data? {
        let key = host.lowercased()
        guard !key.isEmpty, !knownMisses.contains(key) else { return nil }
        if let cached = memoryCache[key] { return cached }
        if let onDisk = try? Data(contentsOf: cacheURL(forHost: key)) {
            memoryCache[key] = onDisk
            return onDisk
        }

        for path in Self.candidatePaths {
            guard let url = URL(string: "https://\(key)\(path)") else { continue }
            guard let data = try? await fetcher.data(from: url),
                !data.isEmpty,
                data.count <= Self.maximumByteCount,
                Self.looksLikeImage(data)
            else { continue }
            memoryCache[key] = data
            persist(data, forHost: key)
            return data
        }

        knownMisses.insert(key)
        return nil
    }

    private func persist(_ data: Data, forHost host: String) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL(forHost: host), options: .atomic)
    }

    /// Using the hostname directly as a filename would introduce path-separator characters; replace them with safe characters.
    private func cacheURL(forHost host: String) -> URL {
        let safe = host.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
        return directory.appendingPathComponent(String(safe), isDirectory: false)
            .appendingPathExtension("icon")
    }
}
