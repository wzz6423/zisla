import Foundation
import ZislaCore

public enum ReleasePackageDownloadError: Error, LocalizedError, Equatable, Sendable {
    case invalidAssetName
    case invalidTargetDirectory
    case httpError(Int)
    case responseTooLarge
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAssetName: "Asset 文件名无效"
        case .invalidTargetDirectory: "目标目录无效"
        case .httpError(let code): "HTTP 请求失败（状态码 \(code)）"
        case .responseTooLarge: "下载文件超过大小限制"
        case .downloadFailed(let message): "下载失败：\(message)"
        }
    }
}

public actor ReleasePackageDownloadService {
    public static let maxDownloadSize = 2_147_483_648
    public typealias DataLoader = @Sendable (URLRequest) async throws -> (URL, HTTPURLResponse)

    private let loadData: DataLoader

    public init(session: URLSession? = nil) {
        let activeSession: URLSession
        if let session {
            activeSession = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 3600
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            activeSession = URLSession(configuration: configuration)
        }
        self.loadData = { request in
            let (tempURL, response) = try await activeSession.download(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw ReleasePackageDownloadError.downloadFailed("无效的 HTTP 响应")
            }
            return (tempURL, response)
        }
    }

    public init(loadData: @escaping DataLoader) {
        self.loadData = loadData
    }

    public func download(
        asset: GitHubRelease.Asset,
        to directory: URL
    ) async throws -> URL {
        guard directory.isFileURL else {
            throw ReleasePackageDownloadError.invalidTargetDirectory
        }

        let fileName = (asset.name as NSString).lastPathComponent
        guard !fileName.isEmpty, fileName != ".", fileName != ".." else {
            throw ReleasePackageDownloadError.invalidAssetName
        }

        let targetDirectory = directory.standardizedFileURL
        let targetURL = targetDirectory
            .appendingPathComponent(fileName, isDirectory: false)
            .standardizedFileURL
        guard targetURL != targetDirectory,
              targetURL.deletingLastPathComponent() == targetDirectory else {
            throw ReleasePackageDownloadError.invalidAssetName
        }

        guard asset.size <= Self.maxDownloadSize else {
            throw ReleasePackageDownloadError.responseTooLarge
        }

        if FileManager.default.fileExists(atPath: targetURL.path) {
            return targetURL
        }

        var request = URLRequest(url: asset.downloadURL)
        request.setValue("zisla-update-downloader", forHTTPHeaderField: "User-Agent")

        let (tempURL, response) = try await loadData(request)

        guard (200...299).contains(response.statusCode) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw ReleasePackageDownloadError.httpError(response.statusCode)
        }

        if let contentLength = response.value(forHTTPHeaderField: "Content-Length"),
           let size = Int(contentLength),
           size > Self.maxDownloadSize {
            try? FileManager.default.removeItem(at: tempURL)
            throw ReleasePackageDownloadError.responseTooLarge
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: tempURL.path)
        if let fileSize = attributes?[.size] as? Int64, fileSize > Self.maxDownloadSize {
            try? FileManager.default.removeItem(at: tempURL)
            throw ReleasePackageDownloadError.responseTooLarge
        }

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw ReleasePackageDownloadError.downloadFailed(error.localizedDescription)
        }

        if FileManager.default.fileExists(atPath: targetURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
            return targetURL
        }

        do {
            try FileManager.default.moveItem(at: tempURL, to: targetURL)
            return targetURL
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw ReleasePackageDownloadError.downloadFailed(error.localizedDescription)
        }
    }
}
