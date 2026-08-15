import Foundation
import ZislaCore
import Testing

@testable import ZislaKit

struct ReleasePackageDownloadServiceTests {
    @Test
    func downloadSucceedsWithValidAsset() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleasePackageDownloadServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testData = Data("test dmg content".utf8)
        let stub = DownloadStub(responses: [
            "https://github.com/test/repo/releases/download/v1.0.0/app.dmg": .success(testData)
        ])
        let service = ReleasePackageDownloadService(loadData: { request in
            try await stub.load(request)
        })

        let asset = Self.makeAsset(name: "app.dmg", url: "https://github.com/test/repo/releases/download/v1.0.0/app.dmg")
        let result = try await service.download(asset: asset, to: tempDir)

        #expect(result.lastPathComponent == "app.dmg")
        #expect(FileManager.default.fileExists(atPath: result.path))
        let downloadedData = try Data(contentsOf: result)
        #expect(downloadedData == testData)
    }

    @Test
    func returnsExistingFileWithoutDownloadWhenFileExists() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleasePackageDownloadServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let existingFile = tempDir.appendingPathComponent("app.dmg")
        let existingData = Data("existing content".utf8)
        try existingData.write(to: existingFile)

        let stub = DownloadStub(responses: [:])
        let service = ReleasePackageDownloadService(loadData: { request in
            try await stub.load(request)
        })

        let asset = Self.makeAsset(name: "app.dmg", url: "https://github.com/test/repo/releases/download/v1.0.0/app.dmg")
        let result = try await service.download(asset: asset, to: tempDir)

        #expect(result == existingFile.standardizedFileURL)
        #expect(await stub.requestCount() == 0)
        let content = try Data(contentsOf: result)
        #expect(content == existingData)
    }

    @Test
    func throwsErrorOnNon2xxStatusCode() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleasePackageDownloadServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stub = DownloadStub(responses: [
            "https://github.com/test/repo/releases/download/v1.0.0/app.dmg": .status(404)
        ])
        let service = ReleasePackageDownloadService(loadData: { request in
            try await stub.load(request)
        })

        let asset = Self.makeAsset(name: "app.dmg", url: "https://github.com/test/repo/releases/download/v1.0.0/app.dmg")

        await #expect(throws: ReleasePackageDownloadError.httpError(404)) {
            try await service.download(asset: asset, to: tempDir)
        }
        #expect(!FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("app.dmg").path))
    }

    @Test
    func extractsLastPathComponentFromAssetName() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleasePackageDownloadServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testData = Data("test dmg content".utf8)
        let stub = DownloadStub(responses: [
            "https://github.com/test/repo/releases/download/v1.0.0/app.dmg": .success(testData)
        ])
        let service = ReleasePackageDownloadService(loadData: { request in
            try await stub.load(request)
        })

        let asset = Self.makeAsset(name: "path/to/app.dmg", url: "https://github.com/test/repo/releases/download/v1.0.0/app.dmg")
        let result = try await service.download(asset: asset, to: tempDir)

        #expect(result.lastPathComponent == "app.dmg")
        #expect(!result.path.contains("path/to/"))
    }

    @Test
    func throwsErrorOnInvalidAssetName() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleasePackageDownloadServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stub = DownloadStub(responses: [:])
        let service = ReleasePackageDownloadService(loadData: { request in
            try await stub.load(request)
        })

        let invalidNames = ["", ".", "..", "/", "//"]
        for name in invalidNames {
            let asset = Self.makeAsset(name: name, url: "https://github.com/test/repo/releases/download/v1.0.0/file")
            await #expect(throws: ReleasePackageDownloadError.invalidAssetName) {
                try await service.download(asset: asset, to: tempDir)
            }
        }
    }

    @Test
    func throwsErrorOnInvalidTargetDirectory() async throws {
        let stub = DownloadStub(responses: [:])
        let service = ReleasePackageDownloadService(loadData: { request in
            try await stub.load(request)
        })

        let asset = Self.makeAsset(name: "app.dmg", url: "https://github.com/test/repo/releases/download/v1.0.0/app.dmg")
        let invalidDir = URL(string: "https://example.com/invalid")!

        await #expect(throws: ReleasePackageDownloadError.invalidTargetDirectory) {
            try await service.download(asset: asset, to: invalidDir)
        }
    }

    @Test
    func throwsErrorOnOversizedResponse() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleasePackageDownloadServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stub = DownloadStub(responses: [
            "https://github.com/test/repo/releases/download/v1.0.0/app.dmg": .oversized
        ])
        let service = ReleasePackageDownloadService(loadData: { request in
            try await stub.load(request)
        })

        let asset = Self.makeAsset(name: "app.dmg", url: "https://github.com/test/repo/releases/download/v1.0.0/app.dmg")

        await #expect(throws: ReleasePackageDownloadError.responseTooLarge) {
            try await service.download(asset: asset, to: tempDir)
        }
    }

    @Test
    func rejectsDeclaredOversizedAssetBeforeDownloading() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleasePackageDownloadServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let stub = DownloadStub(responses: [:])
        let service = ReleasePackageDownloadService(loadData: { request in
            try await stub.load(request)
        })
        let asset = Self.makeAsset(
            name: "app.dmg",
            url: "https://github.com/test/repo/releases/download/v1.0.0/app.dmg",
            size: ReleasePackageDownloadService.maxDownloadSize + 1
        )

        await #expect(throws: ReleasePackageDownloadError.responseTooLarge) {
            try await service.download(asset: asset, to: tempDir)
        }
        #expect(await stub.requestCount() == 0)
    }

    @Test
    func createsTargetDirectoryIfNeeded() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleasePackageDownloadServiceTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("nested/directory", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent().deletingLastPathComponent()) }

        let testData = Data("test dmg content".utf8)
        let stub = DownloadStub(responses: [
            "https://github.com/test/repo/releases/download/v1.0.0/app.dmg": .success(testData)
        ])
        let service = ReleasePackageDownloadService(loadData: { request in
            try await stub.load(request)
        })

        let asset = Self.makeAsset(name: "app.dmg", url: "https://github.com/test/repo/releases/download/v1.0.0/app.dmg")
        let result = try await service.download(asset: asset, to: tempDir)

        #expect(FileManager.default.fileExists(atPath: result.path))
        #expect(result.lastPathComponent == "app.dmg")
    }

    private static func makeAsset(name: String, url: String, size: Int = 1_024) -> GitHubRelease.Asset {
        let json = """
        {"name":"\(name)","browser_download_url":"\(url)","size":\(size)}
        """
        return try! JSONDecoder().decode(GitHubRelease.Asset.self, from: Data(json.utf8))
    }
}

private actor DownloadStub {
    enum Response: Sendable {
        case success(Data)
        case status(Int)
        case oversized
    }

    private let responses: [String: Response]
    private var requests: Int = 0

    init(responses: [String: Response]) {
        self.responses = responses
    }

    func load(_ request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        guard let url = request.url, let response = responses[url.absoluteString] else {
            throw StubError.missingResponse
        }
        requests += 1

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("download-stub-\(UUID().uuidString)")

        switch response {
        case .success(let data):
            try data.write(to: tempFile)
            return (tempFile, httpResponse(url: url, statusCode: 200))
        case .status(let statusCode):
            try Data().write(to: tempFile)
            return (tempFile, httpResponse(url: url, statusCode: statusCode))
        case .oversized:
            try Data().write(to: tempFile)
            let response = httpResponse(url: url, statusCode: 200, contentLength: ReleasePackageDownloadService.maxDownloadSize + 1)
            return (tempFile, response)
        }
    }

    func requestCount() -> Int {
        requests
    }
}

private enum StubError: Error {
    case missingResponse
}

private func httpResponse(url: URL, statusCode: Int, contentLength: Int? = nil) -> HTTPURLResponse {
    var headers: [String: String] = [:]
    if let contentLength {
        headers["Content-Length"] = "\(contentLength)"
    }
    return HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
}
