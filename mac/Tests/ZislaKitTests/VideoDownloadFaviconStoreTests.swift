import Foundation
import Testing
@testable import ZislaKit

private actor RecordingFetcher: VideoDownloadFaviconFetching {
    private let responses: [String: Data]
    private(set) var requestedURLs: [String] = []

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func data(from url: URL) async throws -> Data {
        requestedURLs.append(url.absoluteString)
        guard let data = responses[url.absoluteString] else {
            throw VideoDownloadFaviconError.notFound
        }
        return data
    }

    func urls() -> [String] { requestedURLs }
}

private func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("favicon-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// The magic bytes must be genuine, otherwise looksLikeImage would reject them.
private let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 0, count: 8))
private let icoData = Data([0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x20, 0x20] + [UInt8](repeating: 0, count: 8))

struct VideoDownloadFaviconStoreTests {
    @Test
    func prefersAppleTouchIconOverFavicon() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = pngData
        let fetcher = RecordingFetcher(responses: [
            "https://example.com/apple-touch-icon.png": expected,
            "https://example.com/favicon.ico": icoData,
        ])
        let store = VideoDownloadFaviconStore(fetcher: fetcher, directory: directory)

        let data = await store.icon(forHost: "example.com")

        #expect(data == expected)
        #expect(await fetcher.urls() == ["https://example.com/apple-touch-icon.png"])
    }

    @Test
    func fallsThroughToFaviconWhenHighResolutionMissing() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = icoData
        let fetcher = RecordingFetcher(responses: [
            "https://example.com/favicon.ico": expected
        ])
        let store = VideoDownloadFaviconStore(fetcher: fetcher, directory: directory)

        #expect(await store.icon(forHost: "example.com") == expected)
        #expect(await fetcher.urls().count == VideoDownloadFaviconStore.candidatePaths.count)
    }

    /// A memory-cache hit must not produce any further network requests.
    @Test
    func secondLookupIsServedFromCacheWithoutRefetching() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = RecordingFetcher(responses: [
            "https://example.com/apple-touch-icon.png": pngData
        ])
        let store = VideoDownloadFaviconStore(fetcher: fetcher, directory: directory)

        _ = await store.icon(forHost: "example.com")
        _ = await store.icon(forHost: "example.com")

        #expect(await fetcher.urls().count == 1)
    }

    @Test
    func iconPersistsToDiskAndSurvivesNewStoreInstance() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = pngData
        let first = VideoDownloadFaviconStore(
            fetcher: RecordingFetcher(responses: [
                "https://example.com/apple-touch-icon.png": expected
            ]),
            directory: directory
        )
        _ = await first.icon(forHost: "example.com")

        // New instance with an empty fetcher: data is only available if disk persistence worked.
        let offline = RecordingFetcher(responses: [:])
        let second = VideoDownloadFaviconStore(fetcher: offline, directory: directory)

        #expect(await second.icon(forHost: "example.com") == expected)
        #expect(await offline.urls().isEmpty)
    }

    /// Unreachable hosts enter negative cache; a second lookup must not repeat the three failed requests.
    @Test
    func failedHostIsNotRetried() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = RecordingFetcher(responses: [:])
        let store = VideoDownloadFaviconStore(fetcher: fetcher, directory: directory)

        #expect(await store.icon(forHost: "example.com") == nil)
        let afterFirst = await fetcher.urls().count
        #expect(await store.icon(forHost: "example.com") == nil)

        #expect(await fetcher.urls().count == afterFirst)
    }

    @Test
    func emptyHostIsRejectedWithoutNetworkAccess() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = RecordingFetcher(responses: [:])
        let store = VideoDownloadFaviconStore(fetcher: fetcher, directory: directory)

        #expect(await store.icon(forHost: "") == nil)
        #expect(await fetcher.urls().isEmpty)
    }

    @Test
    func oversizedResponseIsRejected() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Include a valid PNG header so the rejection is due to size rather than the magic-number check.
        let huge = pngData + Data(repeating: 0, count: 513 * 1024)
        let fetcher = RecordingFetcher(responses: [
            "https://example.com/apple-touch-icon.png": huge,
            "https://example.com/apple-touch-icon-precomposed.png": huge,
            "https://example.com/favicon.ico": huge,
        ])
        let store = VideoDownloadFaviconStore(fetcher: fetcher, directory: directory)

        #expect(await store.icon(forHost: "example.com") == nil)
    }

    /// Observed Douyin behavior: /apple-touch-icon.png returns 200 but the content is JSON.
    /// It must be skipped so the remaining candidates are tried, and the JSON must not be cached as an icon.
    @Test
    func jsonErrorBodyIsRejectedAndFallsThroughToRealIcon() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = RecordingFetcher(responses: [
            "https://example.com/apple-touch-icon.png": Data(#"{"status":"error"}"#.utf8),
            "https://example.com/favicon.ico": icoData,
        ])
        let store = VideoDownloadFaviconStore(fetcher: fetcher, directory: directory)

        #expect(await store.icon(forHost: "example.com") == icoData)
    }

    /// Non-image content is never written to disk, otherwise a disk hit would pollute the domain permanently.
    @Test
    func nonImageResponseIsNotPersisted() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let html = Data("<!DOCTYPE html><html>404</html>".utf8)
        let fetcher = RecordingFetcher(responses: [
            "https://example.com/apple-touch-icon.png": html,
            "https://example.com/apple-touch-icon-precomposed.png": html,
            "https://example.com/favicon.ico": html,
        ])
        let store = VideoDownloadFaviconStore(fetcher: fetcher, directory: directory)

        #expect(await store.icon(forHost: "example.com") == nil)
        let cached = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(cached?.isEmpty != false)
    }

    @Test(arguments: [
        ([UInt8]([0x89, 0x50, 0x4E, 0x47]), true),
        ([UInt8]([0x00, 0x00, 0x01, 0x00]), true),
        ([UInt8]([0x47, 0x49, 0x46, 0x38]), true),
        ([UInt8]([0xFF, 0xD8, 0xFF, 0xE0]), true),
        ([UInt8]([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]), true),
        // A RIFF container that is not WEBP (e.g. wav) must be rejected.
        ([UInt8]([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]), false),
        ([UInt8]([0x7B, 0x22, 0x61, 0x22]), false),  // {"a"
        ([UInt8]([0x3C, 0x21, 0x44, 0x4F]), false),  // <!DO
        ([UInt8]([0x89, 0x50]), false),  // truncated, fewer than 4 bytes
    ])
    func recognizesImageMagicBytes(bytes: [UInt8], expected: Bool) {
        #expect(VideoDownloadFaviconStore.looksLikeImage(Data(bytes)) == expected)
    }

    /// Hosts containing path separators must not escape the cache directory.
    @Test
    func hostWithPathSeparatorsStaysInsideCacheDirectory() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = RecordingFetcher(responses: [:])
        let store = VideoDownloadFaviconStore(fetcher: fetcher, directory: directory)

        _ = await store.icon(forHost: "../../escape")

        let escaped = directory.deletingLastPathComponent()
            .appendingPathComponent("escape.icon")
        #expect(!FileManager.default.fileExists(atPath: escaped.path))
    }
}
