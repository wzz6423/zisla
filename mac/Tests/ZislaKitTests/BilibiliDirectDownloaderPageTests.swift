import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct BilibiliDirectDownloaderPageTests {
    @Test(arguments: [
        ("", 111),
        ("?p=1", 111),
        ("?p=2", 222),
        ("?p=02", 222),
        ("?p=%32", 222),
        ("?spm_id_from=333.1007&p=2#p=1", 222),
    ])
    func downloadsTheMediaFromTheRequestedPage(suffix: String, cid: Int) async throws {
        let directory = pageTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = PageBilibiliHTTPClient()

        let components = try await BilibiliDirectDownloader(httpClient: client).downloadComponents(
            from: pageVideoURL + suffix,
            to: directory
        )

        try expectPageMedia(components, cid: cid)
    }

    @Test(arguments: ["", "?p=1"])
    func firstPageRemainsCompatibleWithResponsesWithoutPages(suffix: String) async throws {
        let directory = pageTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = PageBilibiliHTTPClient(viewJSON: pageViewJSON(pages: nil))

        let components = try await BilibiliDirectDownloader(httpClient: client).downloadComponents(
            from: pageVideoURL + suffix,
            to: directory
        )

        try expectPageMedia(components, cid: 111)
    }

    @Test(arguments: [
        [1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1],
    ])
    func pageNumbersDetermineSelectionForEveryTableOrder(order: [Int]) async throws {
        let directory = pageTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pages = order.map { #"{"page":\#($0),"cid":\#($0 * 111)}"# }.joined(separator: ",")
        let client = PageBilibiliHTTPClient(viewJSON: pageViewJSON(pages: "[\(pages)]"))

        for page in 1...3 {
            let components = try await BilibiliDirectDownloader(httpClient: client).downloadComponents(
                from: pageVideoURL + "?p=\(page)",
                to: directory.appendingPathComponent("Page-\(page)")
            )
            try expectPageMedia(components, cid: page * 111)
        }
    }

    @Test(arguments: [
        "p", "p=", "p=0", "p=-1", "p=+2", "p=%2B2", "p=1.5", "p=2e0",
        "p=%20", "p=%202", "p=2%20", "p=abc", "p=%EF%BC%92", "p=%00",
        "p=999999999999999999999999999999", "p=2&p=1", "p=2&p=2", "p=2&p",
    ])
    func invalidPageParametersFailBeforeRequestsOrWrites(query: String) async throws {
        let directory = pageTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = PageBilibiliHTTPClient()

        await #expect(throws: BilibiliDirectDownloaderError.invalidVideoURL) {
            try await BilibiliDirectDownloader(httpClient: client).downloadComponents(
                from: pageVideoURL + "?" + query,
                to: directory
            )
        }

        #expect(await client.requestedAPIURLs.isEmpty)
        #expect(await client.requestedMediaURLs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test(arguments: [
        ("?p=2", nil as String?, 111),
        ("?p=2", "null", 111),
        ("?p=2", "[]", 111),
        ("?p=3", #"[{"page":1,"cid":111},{"page":2,"cid":222}]"#, 111),
        ("?p=2", #"[{"page":1,"cid":111},{"page":3,"cid":333}]"#, 111),
        ("", #"[{"page":2,"cid":222}]"#, 111),
        ("?p=1", "[]", 111),
        ("?p=2", #"[{"page":2,"cid":0}]"#, 111),
        ("?p=2", #"[{"page":2,"cid":-222}]"#, 111),
        ("?p=2", #"[{"page":2,"cid":222},{"page":2,"cid":333}]"#, 111),
        ("?p=2", #"[{"page":2,"cid":222},{"page":2,"cid":222}]"#, 111),
        ("", nil, 0),
        ("?p=1", nil, -111),
        ("?p=\(Int.max)", #"[{"page":1,"cid":111},{"page":2,"cid":222}]"#, 111),
    ])
    func unavailableOrAmbiguousPagesFailWithoutChangingExistingFiles(
        suffix: String,
        pages: String?,
        topLevelCID: Int
    ) async throws {
        let directory = pageTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existingFile = directory.appendingPathComponent("existing.mp4")
        let contents = Data("preserved".utf8)
        try contents.write(to: existingFile)
        let client = PageBilibiliHTTPClient(viewJSON: pageViewJSON(pages: pages, cid: topLevelCID))

        await #expect(throws: BilibiliDirectDownloaderError.invalidVideoURL) {
            try await BilibiliDirectDownloader(httpClient: client).downloadComponents(
                from: pageVideoURL + suffix,
                to: directory
            )
        }

        #expect(await client.requestedAPIURLs.allSatisfy { $0.path == "/x/web-interface/view" })
        #expect(await client.requestedMediaURLs.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["existing.mp4"])
        #expect(try Data(contentsOf: existingFile) == contents)
    }

    @Test(arguments: [
        #"{}"#, #""invalid""#, #"[{"page":"2","cid":222}]"#,
        #"[{"page":2}]"#, #"[{"page":2,"cid":"222"}]"#,
        #"[{"page":2,"cid":9223372036854775808}]"#,
    ])
    func malformedPageMetadataFailsBeforeMediaRequests(pages: String) async throws {
        let directory = pageTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = PageBilibiliHTTPClient(viewJSON: pageViewJSON(pages: pages))

        await #expect(throws: DecodingError.self) {
            try await BilibiliDirectDownloader(httpClient: client).downloadComponents(
                from: pageVideoURL + "?p=2",
                to: directory
            )
        }

        #expect(await client.requestedMediaURLs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test(arguments: [PageAPIEndpoint.view, .play])
    private func dependencyFailuresPropagateWithoutCreatingMedia(endpoint: PageAPIEndpoint) async throws {
        let directory = pageTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = PageBilibiliHTTPClient(failingEndpoint: endpoint)

        await #expect(throws: URLError(.cannotConnectToHost)) {
            try await BilibiliDirectDownloader(httpClient: client).downloadComponents(
                from: pageVideoURL + "?p=2",
                to: directory
            )
        }

        #expect(await client.requestedMediaURLs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test
    func serviceCleansFailedPageAndAllowsTheSameTaskIDToRetry() async throws {
        let directory = pageTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = PageBilibiliHTTPClient()
        let service = pageDownloadService(directory: directory, client: client)
        let output = directory.appendingPathComponent("Output")
        let taskID = UUID()

        await #expect(throws: BilibiliDirectDownloaderError.invalidVideoURL) {
            try await service.download(
                DownloadRequest(urlString: pageVideoURL + "?p=3", mode: .video, outputDirectory: output),
                taskID: taskID
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("Tasks/\(taskID)").path))

        let result = try await service.download(
            DownloadRequest(urlString: pageVideoURL + "?p=2", mode: .video, outputDirectory: output),
            taskID: taskID
        )
        #expect(try String(contentsOf: result.fileURL, encoding: .utf8) == "/222/video.mp4|/222/audio.m4a")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Tasks").path).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingSecondPageRemovesPartialFilesAndAllowsRetry() async throws {
        let directory = pageTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = PageBilibiliHTTPClient(pausesFirstMediaDownloads: true)
        let service = pageDownloadService(directory: directory, client: client)
        let output = directory.appendingPathComponent("Output")
        let request = try DownloadRequest(urlString: pageVideoURL + "?p=2", mode: .video, outputDirectory: output)
        let taskID = UUID()
        let task = Task { try await service.download(request, taskID: taskID) }

        await client.waitForPausedMediaDownloads()
        await service.cancel(taskID: taskID)
        await client.releaseMediaDownloads()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Tasks").path).isEmpty)

        let result = try await service.download(request, taskID: taskID)
        #expect(try String(contentsOf: result.fileURL, encoding: .utf8) == "/222/video.mp4|/222/audio.m4a")
    }
}

private let pageVideoURL = "https://www.bilibili.com/video/BV1d2N16KEh6/"

private func pageTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("BilibiliPageTests-\(UUID().uuidString)", isDirectory: true)
}

private func pageViewJSON(
    pages: String? = #"[{"page":1,"cid":111},{"page":2,"cid":222}]"#,
    cid: Int = 111
) -> String {
    let pageField = pages.map { #", "pages":\#($0)"# } ?? ""
    return #"{"code":0,"message":"OK","data":{"title":"Page Test","cid":\#(cid)\#(pageField)}}"#
}

private func expectPageMedia(_ components: [DownloadedMediaComponent], cid: Int) throws {
    #expect(components.count == 2)
    let video = try #require(components.first { $0.kind == .video })
    let audio = try #require(components.first { $0.kind == .audio })
    #expect(video.formatID == "32")
    #expect(audio.formatID == "30280")
    #expect(try String(contentsOf: video.fileURL, encoding: .utf8) == "/\(cid)/video.mp4")
    #expect(try String(contentsOf: audio.fileURL, encoding: .utf8) == "/\(cid)/audio.m4a")
}

private func pageDownloadService(directory: URL, client: PageBilibiliHTTPClient) -> DownloadService {
    DownloadService(
        resolver: YTDLPResolver(
            bundleURL: directory.appendingPathComponent("Empty.app"),
            managedToolsDirectory: directory.appendingPathComponent("Tools"),
            externalYTDLPCandidates: [],
            externalFFmpegCandidates: []
        ),
        temporaryRootDirectory: directory.appendingPathComponent("Tasks"),
        mediaMuxer: PageMediaMuxer(),
        bilibiliDownloader: BilibiliDirectDownloader(httpClient: client),
        browserCookieSourceProvider: { [] }
    )
}

private struct PageMediaMuxer: MediaMuxing {
    func mux(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        let video = try String(contentsOf: videoURL, encoding: .utf8)
        let audio = try String(contentsOf: audioURL, encoding: .utf8)
        try Data("\(video)|\(audio)".utf8).write(to: outputURL)
    }
}

private enum PageAPIEndpoint: String, Sendable {
    case view = "/x/web-interface/view"
    case play = "/x/player/playurl"
}

private actor PageBilibiliHTTPClient: BilibiliHTTPClient {
    private let viewJSON: String
    private let failingEndpoint: PageAPIEndpoint?
    private let pausesFirstMediaDownloads: Bool
    private var pausedDownloads: [CheckedContinuation<Void, Never>] = []
    private var pausedObserver: CheckedContinuation<Void, Never>?
    private(set) var requestedAPIURLs: [URL] = []
    private(set) var requestedMediaURLs: [URL] = []

    init(
        viewJSON: String = pageViewJSON(),
        failingEndpoint: PageAPIEndpoint? = nil,
        pausesFirstMediaDownloads: Bool = false
    ) {
        self.viewJSON = viewJSON
        self.failingEndpoint = failingEndpoint
        self.pausesFirstMediaDownloads = pausesFirstMediaDownloads
    }

    func data(for request: URLRequest) async throws -> BilibiliHTTPDataResponse {
        let url = try #require(request.url)
        requestedAPIURLs.append(url)
        if url.path == failingEndpoint?.rawValue {
            throw URLError(.cannotConnectToHost)
        }
        if url.path == PageAPIEndpoint.view.rawValue {
            return BilibiliHTTPDataResponse(data: Data(viewJSON.utf8), statusCode: 200)
        }
        #expect(url.path == PageAPIEndpoint.play.rawValue)
        let cid = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "cid" }?.value)
        let playJSON = #"{"code":0,"data":{"dash":{"video":[{"id":32,"baseUrl":"https://cdn.example/\#(cid)/video.mp4","codecs":"avc1.64001F","mimeType":"video/mp4"}],"audio":[{"id":30280,"baseUrl":"https://cdn.example/\#(cid)/audio.m4a"}]}}}"#
        return BilibiliHTTPDataResponse(data: Data(playJSON.utf8), statusCode: 200)
    }

    func download(for request: URLRequest, to destinationURL: URL) async throws -> BilibiliHTTPResponse {
        let url = try #require(request.url)
        requestedMediaURLs.append(url)
        try Data(url.path.utf8).write(to: destinationURL)
        if pausesFirstMediaDownloads, requestedMediaURLs.count <= 2 {
            await withCheckedContinuation { continuation in
                pausedDownloads.append(continuation)
                if pausedDownloads.count == 2 {
                    pausedObserver?.resume()
                    pausedObserver = nil
                }
            }
        }
        try Task.checkCancellation()
        return BilibiliHTTPResponse(statusCode: 200)
    }

    func waitForPausedMediaDownloads() async {
        guard pausedDownloads.count < 2 else { return }
        await withCheckedContinuation { pausedObserver = $0 }
    }

    func releaseMediaDownloads() {
        pausedDownloads.forEach { $0.resume() }
        pausedDownloads.removeAll()
    }
}
