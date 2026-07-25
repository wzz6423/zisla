import Foundation
import ZislaCore

public protocol BilibiliDownloading: Sendable {
    func downloadComponents(from urlString: String, to directory: URL) async throws
        -> [DownloadedMediaComponent]
}

public enum BilibiliDirectDownloaderError: LocalizedError, Equatable, Sendable {
    case invalidVideoURL
    case invalidAPIResponse(String)
    case missingDASHTracks
    case mediaDownloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidVideoURL:
            return "无法从链接中识别 B 站 BV 号"
        case let .invalidAPIResponse(message):
            return "B站接口返回异常：\(message)"
        case .missingDASHTracks:
            return "B站接口未返回可封装的 DASH 视频轨和音频轨"
        case let .mediaDownloadFailed(message):
            return "B站媒体轨下载失败：\(message)"
        }
    }
}

struct BilibiliHTTPDataResponse: Sendable {
    let data: Data
    let statusCode: Int
}

struct BilibiliHTTPResponse: Sendable {
    let statusCode: Int
}

protocol BilibiliHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> BilibiliHTTPDataResponse
    func download(for request: URLRequest, to destinationURL: URL) async throws
        -> BilibiliHTTPResponse
}

public struct BilibiliDirectDownloader: BilibiliDownloading, Sendable {
    private let httpClient: any BilibiliHTTPClient

    public init() {
        self.httpClient = URLSessionBilibiliHTTPClient(session: .shared)
    }

    init(httpClient: any BilibiliHTTPClient) {
        self.httpClient = httpClient
    }

    public func downloadComponents(from urlString: String, to directory: URL) async throws
        -> [DownloadedMediaComponent]
    {
        guard let bvid = Self.bvid(from: urlString) else {
            throw BilibiliDirectDownloaderError.invalidVideoURL
        }
        let referer = "https://www.bilibili.com/video/\(bvid)/"
        let view: ViewData = try await fetchAPI(
            endpoint: "/x/web-interface/view",
            queryItems: [URLQueryItem(name: "bvid", value: bvid)],
            referer: referer
        )
        let play: PlayData = try await fetchAPI(
            endpoint: "/x/player/playurl",
            queryItems: [
                URLQueryItem(name: "bvid", value: bvid),
                URLQueryItem(name: "cid", value: String(view.cid)),
                URLQueryItem(name: "qn", value: "127"),
                URLQueryItem(name: "fnval", value: "4048"),
                URLQueryItem(name: "fourk", value: "1"),
            ],
            referer: referer
        )
        guard let dash = play.dash,
              let video = Self.preferredVideo(from: dash.video),
              let audio = dash.audio.max(by: { $0.bandwidth < $1.bandwidth })
        else {
            throw BilibiliDirectDownloaderError.missingDASHTracks
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = Self.safeFilename("\(view.title) [\(bvid)]")
        let videoURL = directory.appendingPathComponent("\(stem).\(video.id).mp4")
        let audioURL = directory.appendingPathComponent("\(stem).\(audio.id).m4a")

        async let videoDownload: Void = download(
            track: video,
            referer: referer,
            destinationURL: videoURL
        )
        async let audioDownload: Void = download(
            track: audio,
            referer: referer,
            destinationURL: audioURL
        )
        _ = try await (videoDownload, audioDownload)

        return [
            DownloadedMediaComponent(
                fileURL: videoURL,
                formatID: String(video.id),
                kind: .video
            ),
            DownloadedMediaComponent(
                fileURL: audioURL,
                formatID: String(audio.id),
                kind: .audio
            ),
        ]
    }

    private func fetchAPI<Value: Decodable>(
        endpoint: String,
        queryItems: [URLQueryItem],
        referer: String
    ) async throws -> Value {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.bilibili.com"
        components.path = endpoint
        components.queryItems = queryItems
        guard let url = components.url else {
            throw BilibiliDirectDownloaderError.invalidVideoURL
        }

        let response = try await httpClient.data(for: Self.request(url: url, referer: referer))
        guard (200..<300).contains(response.statusCode) else {
            throw BilibiliDirectDownloaderError.invalidAPIResponse(
                "HTTP \(response.statusCode)"
            )
        }
        let envelope = try JSONDecoder().decode(APIEnvelope<Value>.self, from: response.data)
        guard envelope.code == 0, let data = envelope.data else {
            throw BilibiliDirectDownloaderError.invalidAPIResponse(
                envelope.message ?? "code \(envelope.code)"
            )
        }
        return data
    }

    private func download(
        track: DASHTrack,
        referer: String,
        destinationURL: URL
    ) async throws {
        let candidates = ([track.baseURL] + track.backupURLs)
            .compactMap(URL.init(string:))
            .filter { $0.scheme?.lowercased() == "https" }
        var lastFailure = "没有可用的 HTTPS 媒体地址"

        for url in candidates {
            try Task.checkCancellation()
            do {
                let response = try await httpClient.download(
                    for: Self.request(url: url, referer: referer),
                    to: destinationURL
                )
                if (200..<300).contains(response.statusCode) {
                    return
                }
                lastFailure = "\(url.host ?? "B站 CDN") 返回 HTTP \(response.statusCode)"
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastFailure = error.localizedDescription
            }
            try? FileManager.default.removeItem(at: destinationURL)
        }
        throw BilibiliDirectDownloaderError.mediaDownloadFailed(lastFailure)
    }

    private static func request(url: URL, referer: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
        return request
    }

    private static func bvid(from string: String) -> String? {
        guard let url = URL(string: string) else { return nil }
        return url.pathComponents.first(where: { component in
            component.hasPrefix("BV")
                && component.count >= 12
                && component.dropFirst(2).allSatisfy {
                    $0.isASCII && ($0.isLetter || $0.isNumber)
                }
        })
    }

    private static func preferredVideo(from tracks: [DASHTrack]) -> DASHTrack? {
        let mp4Tracks = tracks.filter { $0.mimeType.lowercased() == "video/mp4" }
        let avcTracks = mp4Tracks.filter { $0.codecs.lowercased().hasPrefix("avc1") }
        return (avcTracks.isEmpty ? mp4Tracks : avcTracks)
            .max(by: { lhs, rhs in
                let lhsPixels = lhs.width * lhs.height
                let rhsPixels = rhs.width * rhs.height
                return lhsPixels == rhsPixels
                    ? lhs.bandwidth < rhs.bandwidth
                    : lhsPixels < rhsPixels
            })
    }

    private static func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|")
            .union(.controlCharacters)
        let scalars = value.unicodeScalars.map { forbidden.contains($0) ? "_" : String($0) }
        let filename = scalars.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((filename.isEmpty ? "Bilibili Video" : filename).prefix(160))
    }
}

private struct URLSessionBilibiliHTTPClient: BilibiliHTTPClient, Sendable {
    let session: URLSession

    func data(for request: URLRequest) async throws -> BilibiliHTTPDataResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw BilibiliDirectDownloaderError.invalidAPIResponse("无效 HTTP 响应")
        }
        return BilibiliHTTPDataResponse(data: data, statusCode: response.statusCode)
    }

    func download(for request: URLRequest, to destinationURL: URL) async throws
        -> BilibiliHTTPResponse
    {
        let (temporaryURL, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard let response = response as? HTTPURLResponse else {
            throw BilibiliDirectDownloaderError.invalidAPIResponse("无效 HTTP 响应")
        }
        guard (200..<300).contains(response.statusCode) else {
            return BilibiliHTTPResponse(statusCode: response.statusCode)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return BilibiliHTTPResponse(statusCode: response.statusCode)
    }
}

private struct APIEnvelope<Value: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: Value?
}

private struct ViewData: Decodable {
    let title: String
    let cid: Int64
}

private struct PlayData: Decodable {
    let dash: DASHData?
}

private struct DASHData: Decodable {
    let video: [DASHTrack]
    let audio: [DASHTrack]
}

private struct DASHTrack: Decodable, Sendable {
    let id: Int
    let baseURL: String
    let backupURLs: [String]
    let bandwidth: Int
    let codecs: String
    let mimeType: String
    let width: Int
    let height: Int

    private enum CodingKeys: String, CodingKey {
        case id, bandwidth, codecs, mimeType, width, height
        case baseURLCamel = "baseUrl"
        case baseURLSnake = "base_url"
        case backupURLsCamel = "backupUrl"
        case backupURLsSnake = "backup_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURLCamel)
            ?? container.decode(String.self, forKey: .baseURLSnake)
        backupURLs = try container.decodeIfPresent([String].self, forKey: .backupURLsCamel)
            ?? container.decodeIfPresent([String].self, forKey: .backupURLsSnake)
            ?? []
        bandwidth = try container.decodeIfPresent(Int.self, forKey: .bandwidth) ?? 0
        codecs = try container.decodeIfPresent(String.self, forKey: .codecs) ?? ""
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 0
    }
}
