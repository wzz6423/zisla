import CryptoKit
import Foundation
import Testing

@testable import ZislaKit

struct SystemBackgroundSoundAssetDownloaderTests {
    @Test
    func readsManifestAndExtractsMetadata() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DownloaderTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifestPath = tempDir.appendingPathComponent("manifest.xml")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let sha1Data = Data([0x9D, 0x78, 0xD7, 0x01, 0x3C, 0xEA, 0xBE, 0x8F])
        let manifestDict: [String: Any] = [
            "Assets": [
                [
                    "SoundName": "Rain",
                    "__BaseURL": "https://example.com/base/",
                    "__RelativePath": "path/to/rain.zip",
                    "_Measurement": sha1Data,
                    "_DownloadSize": 1000000,
                    "_UnarchivedSize": 1200000,
                ],
            ],
        ]
        let manifestData = try PropertyListSerialization.data(
            fromPropertyList: manifestDict,
            format: .xml,
            options: 0
        )
        try manifestData.write(to: manifestPath)

        let downloader = SystemBackgroundSoundAssetDownloader(
            manifestPath: manifestPath,
            loadData: { _ in throw URLError(.badServerResponse) },
            readPlist: { url in
                let data = try Data(contentsOf: url)
                return try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as! [String: Any]
            },
            unzip: { _, _ in }
        )

        let metadata = try await downloader.readManifest(for: "Rain")

        #expect(metadata.soundName == "Rain")
        #expect(metadata.downloadURL.absoluteString == "https://example.com/base/path/to/rain.zip")
        #expect(metadata.sha1 == sha1Data)
        #expect(metadata.downloadSize == 1000000)
        #expect(metadata.unarchivedSize == 1200000)
    }

    @Test
    func prefersHighestCompatibilityAssetWhenSoundHasMultipleVersions() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let manifestPath = tempDirectory.appendingPathComponent("manifest.xml")
        let manifest: [String: Any] = [
            "Assets": [
                [
                    "SoundName": "Rain",
                    "CompatibilityVersion": 1,
                    "FormatVersion": 1,
                    "__BaseURL": "https://example.com/",
                    "__RelativePath": "old.zip",
                    "_Measurement": Data([1]),
                ],
                [
                    "SoundName": "Rain",
                    "CompatibilityVersion": 4,
                    "FormatVersion": 4,
                    "__BaseURL": "https://example.com/",
                    "__RelativePath": "new.zip",
                    "_Measurement": Data([4]),
                ],
            ],
        ]
        let manifestData = try PropertyListSerialization.data(
            fromPropertyList: manifest,
            format: .xml,
            options: 0
        )
        try manifestData.write(to: manifestPath)

        let downloader = SystemBackgroundSoundAssetDownloader(
            manifestPath: manifestPath,
            loadData: { _ in throw URLError(.badServerResponse) },
            readPlist: { url in
                let data = try Data(contentsOf: url)
                return try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as! [String: Any]
            },
            unzip: { _, _ in }
        )

        let metadata = try await downloader.readManifest(for: "Rain")

        #expect(metadata.downloadURL.absoluteString == "https://example.com/new.zip")
        #expect(metadata.sha1 == Data([4]))
    }

    @Test
    func throwsWhenManifestDoesNotExist() async throws {
        let nonExistent = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).xml")
        let downloader = SystemBackgroundSoundAssetDownloader(
            manifestPath: nonExistent,
            loadData: { _ in throw URLError(.badServerResponse) },
            readPlist: { _ in [:] },
            unzip: { _, _ in }
        )

        await #expect(throws: SystemBackgroundSoundAssetDownloader.DownloadError.manifestNotFound) {
            try await downloader.readManifest(for: "Rain")
        }
    }

    @Test
    func throwsWhenSoundNotFoundInManifest() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DownloaderTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifestPath = tempDir.appendingPathComponent("manifest.xml")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let manifestDict: [String: Any] = [
            "Assets": [
                [
                    "SoundName": "Ocean",
                    "__BaseURL": "https://example.com/",
                    "__RelativePath": "ocean.zip",
                    "_Measurement": Data([0x00]),
                ],
            ],
        ]
        let manifestData = try PropertyListSerialization.data(
            fromPropertyList: manifestDict,
            format: .xml,
            options: 0
        )
        try manifestData.write(to: manifestPath)

        let downloader = SystemBackgroundSoundAssetDownloader(
            manifestPath: manifestPath,
            loadData: { _ in throw URLError(.badServerResponse) },
            readPlist: { url in
                let data = try Data(contentsOf: url)
                return try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as! [String: Any]
            },
            unzip: { _, _ in }
        )

        await #expect(
            throws: SystemBackgroundSoundAssetDownloader.DownloadError.soundNotFoundInManifest("Rain")
        ) {
            try await downloader.readManifest(for: "Rain")
        }
    }

    @Test
    func downloadsAndVerifiesChecksumSuccessfully() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DownloaderTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifestPath = tempDir.appendingPathComponent("manifest.xml")
        let targetDir = tempDir.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let testContent = Data("test audio content".utf8)
        let testSHA1 = Data(Insecure.SHA1.hash(data: testContent))

        let manifestDict: [String: Any] = [
            "Assets": [
                [
                    "SoundName": "Fire",
                    "__BaseURL": "https://cdn.example.com/",
                    "__RelativePath": "fire.zip",
                    "_Measurement": testSHA1,
                    "_DownloadSize": testContent.count,
                    "_UnarchivedSize": testContent.count * 2,
                ],
            ],
        ]
        let manifestData = try PropertyListSerialization.data(
            fromPropertyList: manifestDict,
            format: .xml,
            options: 0
        )
        try manifestData.write(to: manifestPath)

        final class CallTracker: @unchecked Sendable {
            private let lock = NSLock()
            private var _downloadCalled = false
            private var _unzipCalled = false

            var downloadCalled: Bool {
                lock.withLock { _downloadCalled }
            }

            var unzipCalled: Bool {
                lock.withLock { _unzipCalled }
            }

            func markDownloadCalled() {
                lock.withLock { _downloadCalled = true }
            }

            func markUnzipCalled() {
                lock.withLock { _unzipCalled = true }
            }
        }

        let tracker = CallTracker()

        let downloader = SystemBackgroundSoundAssetDownloader(
            manifestPath: manifestPath,
            loadData: { request in
                tracker.markDownloadCalled()
                #expect(request.url?.absoluteString == "https://cdn.example.com/fire.zip")
                let tempZip = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "test-\(UUID().uuidString).zip"
                )
                try testContent.write(to: tempZip)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (tempZip, response)
            },
            readPlist: { url in
                let data = try Data(contentsOf: url)
                return try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as! [String: Any]
            },
            unzip: { zipURL, destURL in
                tracker.markUnzipCalled()
                let assetData = destURL.appendingPathComponent("AssetData", isDirectory: true)
                try FileManager.default.createDirectory(at: assetData, withIntermediateDirectories: true)
                try testContent.write(to: assetData.appendingPathComponent("fire.m4a"))
            }
        )

        let result = try await downloader.download(soundName: "Fire", to: targetDir)

        #expect(tracker.downloadCalled)
        #expect(tracker.unzipCalled)
        #expect(result.lastPathComponent == "Fire.asset")
        #expect(FileManager.default.fileExists(atPath: result.path))
        #expect(
            FileManager.default.fileExists(
                atPath: result.appendingPathComponent("AssetData/fire.m4a").path
            )
        )
    }

    @Test
    func throwsOnChecksumMismatch() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DownloaderTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifestPath = tempDir.appendingPathComponent("manifest.xml")
        let targetDir = tempDir.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let expectedSHA1 = Data([0xFF, 0xFF, 0xFF, 0xFF])
        let manifestDict: [String: Any] = [
            "Assets": [
                [
                    "SoundName": "Ocean",
                    "__BaseURL": "https://cdn.example.com/",
                    "__RelativePath": "ocean.zip",
                    "_Measurement": expectedSHA1,
                ],
            ],
        ]
        let manifestData = try PropertyListSerialization.data(
            fromPropertyList: manifestDict,
            format: .xml,
            options: 0
        )
        try manifestData.write(to: manifestPath)

        let wrongContent = Data("wrong content".utf8)

        let downloader = SystemBackgroundSoundAssetDownloader(
            manifestPath: manifestPath,
            loadData: { request in
                let tempZip = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "test-\(UUID().uuidString).zip"
                )
                try wrongContent.write(to: tempZip)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (tempZip, response)
            },
            readPlist: { url in
                let data = try Data(contentsOf: url)
                return try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as! [String: Any]
            },
            unzip: { _, _ in }
        )

        await #expect(
            throws: SystemBackgroundSoundAssetDownloader.DownloadError.self
        ) {
            try await downloader.download(soundName: "Ocean", to: targetDir)
        }
    }

    @Test
    func throwsOnHTTPError() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DownloaderTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifestPath = tempDir.appendingPathComponent("manifest.xml")
        let targetDir = tempDir.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let manifestDict: [String: Any] = [
            "Assets": [
                [
                    "SoundName": "Stream",
                    "__BaseURL": "https://cdn.example.com/",
                    "__RelativePath": "stream.zip",
                    "_Measurement": Data([0x00]),
                ],
            ],
        ]
        let manifestData = try PropertyListSerialization.data(
            fromPropertyList: manifestDict,
            format: .xml,
            options: 0
        )
        try manifestData.write(to: manifestPath)

        let downloader = SystemBackgroundSoundAssetDownloader(
            manifestPath: manifestPath,
            loadData: { request in
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("dummy")
                try Data().write(to: tempURL)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 404,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (tempURL, response)
            },
            readPlist: { url in
                let data = try Data(contentsOf: url)
                return try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as! [String: Any]
            },
            unzip: { _, _ in }
        )

        await #expect(throws: SystemBackgroundSoundAssetDownloader.DownloadError.httpError(404)) {
            try await downloader.download(soundName: "Stream", to: targetDir)
        }
    }

    @Test
    func sanitizesSoundNameAndRejectsInvalidCharacters() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DownloaderTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifestPath = tempDir.appendingPathComponent("manifest.xml")
        let targetDir = tempDir.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let manifestDict: [String: Any] = ["Assets": []]
        let manifestData = try PropertyListSerialization.data(
            fromPropertyList: manifestDict,
            format: .xml,
            options: 0
        )
        try manifestData.write(to: manifestPath)

        let downloader = SystemBackgroundSoundAssetDownloader(
            manifestPath: manifestPath,
            loadData: { _ in throw URLError(.badServerResponse) },
            readPlist: { url in
                let data = try Data(contentsOf: url)
                return try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as! [String: Any]
            },
            unzip: { _, _ in }
        )

        await #expect(
            throws: SystemBackgroundSoundAssetDownloader.DownloadError.soundNotFoundInManifest(
                "../Evil"
            )
        ) {
            try await downloader.download(soundName: "../Evil", to: targetDir)
        }
    }

    @Test
    func createsTargetDirectoryIfNeeded() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DownloaderTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifestPath = tempDir.appendingPathComponent("manifest.xml")
        let targetDir = tempDir.appendingPathComponent("deep/nested/target", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let testContent = Data("content".utf8)
        let testSHA1 = Data(Insecure.SHA1.hash(data: testContent))

        let manifestDict: [String: Any] = [
            "Assets": [
                [
                    "SoundName": "Night",
                    "__BaseURL": "https://cdn.example.com/",
                    "__RelativePath": "night.zip",
                    "_Measurement": testSHA1,
                ],
            ],
        ]
        let manifestData = try PropertyListSerialization.data(
            fromPropertyList: manifestDict,
            format: .xml,
            options: 0
        )
        try manifestData.write(to: manifestPath)

        let downloader = SystemBackgroundSoundAssetDownloader(
            manifestPath: manifestPath,
            loadData: { request in
                let tempZip = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "test-\(UUID().uuidString).zip"
                )
                try testContent.write(to: tempZip)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (tempZip, response)
            },
            readPlist: { url in
                let data = try Data(contentsOf: url)
                return try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as! [String: Any]
            },
            unzip: { _, destURL in
                try FileManager.default.createDirectory(
                    at: destURL.appendingPathComponent("AssetData"),
                    withIntermediateDirectories: true
                )
            }
        )

        let result = try await downloader.download(soundName: "Night", to: targetDir)

        #expect(FileManager.default.fileExists(atPath: targetDir.path))
        #expect(result.path.hasPrefix(targetDir.path))
    }

    @Test
    func replacesExistingAssetDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DownloaderTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifestPath = tempDir.appendingPathComponent("manifest.xml")
        let targetDir = tempDir.appendingPathComponent("target", isDirectory: true)
        let existingAsset = targetDir.appendingPathComponent("Train.asset", isDirectory: true)
        try FileManager.default.createDirectory(at: existingAsset, withIntermediateDirectories: true)
        let oldFile = existingAsset.appendingPathComponent("old.txt")
        try Data("old".utf8).write(to: oldFile)

        let testContent = Data("new content".utf8)
        let testSHA1 = Data(Insecure.SHA1.hash(data: testContent))

        let manifestDict: [String: Any] = [
            "Assets": [
                [
                    "SoundName": "Train",
                    "__BaseURL": "https://cdn.example.com/",
                    "__RelativePath": "train.zip",
                    "_Measurement": testSHA1,
                ],
            ],
        ]
        let manifestData = try PropertyListSerialization.data(
            fromPropertyList: manifestDict,
            format: .xml,
            options: 0
        )
        try manifestData.write(to: manifestPath)

        let downloader = SystemBackgroundSoundAssetDownloader(
            manifestPath: manifestPath,
            loadData: { request in
                let tempZip = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "test-\(UUID().uuidString).zip"
                )
                try testContent.write(to: tempZip)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (tempZip, response)
            },
            readPlist: { url in
                let data = try Data(contentsOf: url)
                return try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as! [String: Any]
            },
            unzip: { _, destURL in
                let newFile = destURL.appendingPathComponent("new.txt")
                try Data("new".utf8).write(to: newFile)
            }
        )

        let result = try await downloader.download(soundName: "Train", to: targetDir)

        #expect(!FileManager.default.fileExists(atPath: oldFile.path))
        #expect(FileManager.default.fileExists(atPath: result.appendingPathComponent("new.txt").path))
    }
}
