import CryptoKit
import Foundation
import ZislaCore

/// Downloads and verifies macOS Comfort Sounds assets from Apple CDN based on local manifest.
public actor SystemBackgroundSoundAssetDownloader {
    public static let defaultManifestPath = URL(
        fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_ComfortSoundsAssets/com_apple_MobileAsset_ComfortSoundsAssets.xml"
    )
    public static let maxDownloadSize = 100 * 1024 * 1024
    public static let maxUnarchivedSize = 120 * 1024 * 1024

    public enum DownloadError: LocalizedError, Equatable, Sendable {
        case manifestNotFound
        case manifestReadFailed(String)
        case soundNotFoundInManifest(String)
        case invalidURL
        case invalidTargetDirectory
        case httpError(Int)
        case checksumMismatch(expected: String, actual: String)
        case unzipFailed(String)
        case downloadFailed(String)

        public var errorDescription: String? {
            switch self {
            case .manifestNotFound:
                "系统资源清单文件不存在"
            case .manifestReadFailed(let message):
                "读取系统资源清单失败：\(message)"
            case .soundNotFoundInManifest(let name):
                "声音资源 \(name) 未在清单中找到"
            case .invalidURL:
                "资源下载 URL 无效"
            case .invalidTargetDirectory:
                "目标目录路径无效"
            case .httpError(let code):
                "HTTP 下载失败（状态码 \(code)）"
            case .checksumMismatch(let expected, let actual):
                "文件校验失败（期望 \(expected)，实际 \(actual)）"
            case .unzipFailed(let message):
                "解压失败：\(message)"
            case .downloadFailed(let message):
                "下载失败：\(message)"
            }
        }
    }

    /// Asset metadata from the manifest plist
    public struct AssetMetadata: Equatable, Sendable {
        public let soundName: String
        public let downloadURL: URL
        public let sha1: Data
        public let downloadSize: Int
        public let unarchivedSize: Int

        public init(
            soundName: String,
            downloadURL: URL,
            sha1: Data,
            downloadSize: Int,
            unarchivedSize: Int
        ) {
            self.soundName = soundName
            self.downloadURL = downloadURL
            self.sha1 = sha1
            self.downloadSize = downloadSize
            self.unarchivedSize = unarchivedSize
        }
    }

    public typealias DataLoader = @Sendable (URLRequest) async throws -> (URL, HTTPURLResponse)
    public typealias PlistReader = @Sendable (URL) throws -> [String: Any]
    public typealias Unzipper = @Sendable (URL, URL) throws -> Void

    private let manifestPath: URL
    private let loadData: DataLoader
    private let readPlist: PlistReader
    private let unzip: Unzipper

    public init(
        manifestPath: URL = SystemBackgroundSoundAssetDownloader.defaultManifestPath,
        session: URLSession? = nil
    ) {
        self.manifestPath = manifestPath

        let activeSession: URLSession
        if let session {
            activeSession = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 7200
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            activeSession = URLSession(configuration: configuration)
        }

        self.loadData = { request in
            let (tempURL, response) = try await activeSession.download(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw DownloadError.downloadFailed(AppLocalization.text("无效的 HTTP 响应"))
            }
            return (tempURL, response)
        }

        self.readPlist = { url in
            let data = try Data(contentsOf: url)
            guard let dict = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            return dict
        }

        self.unzip = { zipURL, destinationURL in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            task.arguments = ["-q", "-o", zipURL.path, "-d", destinationURL.path]
            task.standardOutput = nil
            task.standardError = nil
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                throw DownloadError.unzipFailed("unzip 退出码 \(task.terminationStatus)")
            }
        }
    }

    init(
        manifestPath: URL,
        loadData: @escaping DataLoader,
        readPlist: @escaping PlistReader,
        unzip: @escaping Unzipper
    ) {
        self.manifestPath = manifestPath
        self.loadData = loadData
        self.readPlist = readPlist
        self.unzip = unzip
    }

    /// Downloads and installs the specified Comfort Sound to the target directory.
    /// - Parameters:
    ///   - soundName: Name of the sound (e.g., "Rain", "Ocean")
    ///   - targetDirectory: Directory where the .asset bundle will be created
    /// - Returns: URL of the installed .asset directory containing the sound files
    public func download(soundName: String, to targetDirectory: URL) async throws -> URL {
        guard targetDirectory.isFileURL else {
            throw DownloadError.invalidTargetDirectory
        }

        let sanitizedName = sanitizeSoundName(soundName)
        guard sanitizedName == soundName else {
            throw DownloadError.soundNotFoundInManifest(soundName)
        }

        let metadata = try readManifest(for: soundName)
        guard (metadata.downloadSize == 0 || metadata.downloadSize <= Self.maxDownloadSize),
              (metadata.unarchivedSize == 0 || metadata.unarchivedSize <= Self.maxUnarchivedSize) else {
            throw DownloadError.downloadFailed(AppLocalization.text("资源大小超出允许范围"))
        }
        let sanitizedTargetDirectory = targetDirectory.standardizedFileURL

        try FileManager.default.createDirectory(
            at: sanitizedTargetDirectory,
            withIntermediateDirectories: true
        )

        var request = URLRequest(url: metadata.downloadURL)
        request.setValue("Zisla/1.0", forHTTPHeaderField: "User-Agent")

        let (tempZipURL, response) = try await loadData(request)
        defer { try? FileManager.default.removeItem(at: tempZipURL) }

        guard (200..<300).contains(response.statusCode) else {
            throw DownloadError.httpError(response.statusCode)
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: tempZipURL.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let downloadedSize = (attributes[.size] as? NSNumber)?.int64Value,
              downloadedSize <= Int64(Self.maxDownloadSize) else {
            throw DownloadError.downloadFailed(AppLocalization.text("资源大小超出允许范围"))
        }

        let actualSHA1 = try computeSHA1(of: tempZipURL)
        guard actualSHA1 == metadata.sha1 else {
            throw DownloadError.checksumMismatch(
                expected: metadata.sha1.hexString,
                actual: actualSHA1.hexString
            )
        }

        let assetName = "\(soundName).asset"
        let assetDirectory = sanitizedTargetDirectory.appendingPathComponent(assetName, isDirectory: true)
        let stagingDirectory = sanitizedTargetDirectory.appendingPathComponent(
            ".\(assetName).\(UUID().uuidString).staging",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)

        do {
            try unzip(tempZipURL, stagingDirectory)
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: assetDirectory.path) {
                _ = try FileManager.default.replaceItemAt(assetDirectory, withItemAt: stagingDirectory)
            } else {
                try FileManager.default.moveItem(at: stagingDirectory, to: assetDirectory)
            }
        } catch {
            throw error
        }

        return assetDirectory
    }

    /// Reads the manifest and extracts metadata for the specified sound.
    func readManifest(for soundName: String) throws -> AssetMetadata {
        guard FileManager.default.fileExists(atPath: manifestPath.path) else {
            throw DownloadError.manifestNotFound
        }

        let manifest: [String: Any]
        do {
            manifest = try readPlist(manifestPath)
        } catch {
            throw DownloadError.manifestReadFailed(error.localizedDescription)
        }

        guard let assets = manifest["Assets"] as? [[String: Any]] else {
            throw DownloadError.manifestReadFailed(AppLocalization.text("Assets 数组不存在"))
        }

        let candidates = assets.filter { ($0["SoundName"] as? String) == soundName }
        guard let asset = candidates.max(by: Self.isPreferredAsset) else {
            throw DownloadError.soundNotFoundInManifest(soundName)
        }

        guard let baseURL = asset["__BaseURL"] as? String,
              let relativePath = asset["__RelativePath"] as? String,
              let base = URL(string: baseURL),
              base.scheme == "https",
              base.host != nil,
              let downloadURL = URL(string: relativePath, relativeTo: base)?.absoluteURL,
              downloadURL.scheme == base.scheme,
              downloadURL.host == base.host,
              !relativePath.split(separator: "/").contains("..") else {
            throw DownloadError.invalidURL
        }

        guard let measurementData = asset["_Measurement"] as? Data else {
            throw DownloadError.manifestReadFailed(AppLocalization.text("_Measurement 字段缺失或格式错误"))
        }

        let downloadSize = (asset["_DownloadSize"] as? Int) ?? 0
        let unarchivedSize = (asset["_UnarchivedSize"] as? Int) ?? 0

        return AssetMetadata(
            soundName: soundName,
            downloadURL: downloadURL,
            sha1: measurementData,
            downloadSize: downloadSize,
            unarchivedSize: unarchivedSize
        )
    }

    private static func isPreferredAsset(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        let lhsCompatibility = lhs["CompatibilityVersion"] as? Int ?? 0
        let rhsCompatibility = rhs["CompatibilityVersion"] as? Int ?? 0
        if lhsCompatibility != rhsCompatibility { return lhsCompatibility < rhsCompatibility }
        let lhsFormat = lhs["FormatVersion"] as? Int ?? 0
        let rhsFormat = rhs["FormatVersion"] as? Int ?? 0
        if lhsFormat != rhsFormat { return lhsFormat < rhsFormat }
        let lhsVersion = lhs["_MasteredVersion"] as? String ?? ""
        let rhsVersion = rhs["_MasteredVersion"] as? String ?? ""
        return lhsVersion.localizedStandardCompare(rhsVersion) == .orderedAscending
    }

    private func computeSHA1(of fileURL: URL) throws -> Data {
        let data = try Data(contentsOf: fileURL)
        let digest = Insecure.SHA1.hash(data: data)
        return Data(digest)
    }

    private func sanitizeSoundName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return ""
        }
        return name
    }
}

extension Data {
    fileprivate var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
