import CryptoKit
import Foundation
import Testing

@testable import ZislaKit

struct SystemBackgroundSoundIntegrationTests {
    @Test
    func readsRealManifestIfAvailable() async throws {
        let manifestPath = URL(
            fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_ComfortSoundsAssets/com_apple_MobileAsset_ComfortSoundsAssets.xml"
        )

        guard FileManager.default.fileExists(atPath: manifestPath.path) else {
            return
        }

        let downloader = SystemBackgroundSoundAssetDownloader(manifestPath: manifestPath)

        do {
            let metadata = try await downloader.readManifest(for: "Rain")
            #expect(metadata.soundName == "Rain")
            #expect(metadata.downloadURL.absoluteString.contains("cdn"))
            #expect(metadata.sha1.count == 20)
            #expect(metadata.downloadSize > 0)
        } catch SystemBackgroundSoundAssetDownloader.DownloadError.soundNotFoundInManifest {
            // Rain may not be installed on the system; skip.
        }
    }

    @Test
    func validatesCatalogAndDownloaderIntegration() async throws {
        let systemRoot = URL(
            fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_ComfortSoundsAssets",
            isDirectory: true
        )

        guard FileManager.default.fileExists(atPath: systemRoot.path) else {
            return
        }

        let installedSounds = SystemBackgroundSoundCatalog.installedSounds(in: systemRoot)

        if let firstSound = installedSounds.first {
            let manifestPath = systemRoot.appendingPathComponent(
                "com_apple_MobileAsset_ComfortSoundsAssets.xml"
            )
            guard FileManager.default.fileExists(atPath: manifestPath.path) else {
                return
            }

            let downloader = SystemBackgroundSoundAssetDownloader(manifestPath: manifestPath)

            do {
                let metadata = try await downloader.readManifest(for: firstSound.name)
                #expect(metadata.soundName == firstSound.name)
            } catch {
                // Some installed sounds may not appear in the manifest (legacy versions); skip.
            }
        }
    }

    @Test
    @MainActor
    func queuesDownloadsInFIFOOrder() async throws {
        let testRoot = URL(fileURLWithPath: "/tmp/test-sounds-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let gate = BackgroundSoundDownloadGate()
        let service = SystemBackgroundSoundService(
            assetRoots: [],
            downloadedAssetRoot: testRoot,
            assetDownloader: queuedDownloadTestDownloader(using: gate)
        )

        service.requestDownload(sound: .rain)
        await gate.waitUntilRequested("Rain")
        service.requestDownload(sound: .ocean)

        #expect(service.downloadState(for: .rain) == .downloading)
        #expect(service.downloadState(for: .ocean) == .queued)
        let oceanStartedEarly = await gate.hasRequested("Ocean")
        #expect(!oceanStartedEarly)

        await gate.completeDownload(for: "Rain")
        let rainFinished = await waitUntil { !service.isDownloading(.rain) }
        let oceanStarted = await waitUntil { service.downloadState(for: .ocean) == .downloading }
        #expect(rainFinished)
        #expect(oceanStarted)
        await gate.waitUntilRequested("Ocean")

        await gate.completeDownload(for: "Ocean")
        let oceanFinished = await waitUntil { !service.isDownloading(.ocean) }
        #expect(oceanFinished)
        await gate.cleanup()
    }

    @Test
    @MainActor
    func doesNotCancelActiveDownloadWhenSelectingNewSound() async throws {
        let testRoot = URL(fileURLWithPath: "/tmp/test-sounds-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let gate = BackgroundSoundDownloadGate()
        let service = SystemBackgroundSoundService(
            assetRoots: [],
            downloadedAssetRoot: testRoot,
            assetDownloader: queuedDownloadTestDownloader(using: gate)
        )

        service.requestDownload(sound: .rain, playWhenReady: true)
        await gate.waitUntilRequested("Rain")
        service.requestDownload(sound: .ocean, playWhenReady: false)

        #expect(service.downloadState(for: .rain) == .downloading)
        #expect(service.downloadState(for: .ocean) == .queued)

        service.cancelAllDownloads()
        await gate.cancelAll()
        await Task.yield()
        await gate.cleanup()
    }

    @Test
    @MainActor
    func startsNextDownloadOnlyAfterTheCancelledDownloadFinishes() async throws {
        let testRoot = URL(fileURLWithPath: "/tmp/test-sounds-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let gate = BackgroundSoundDownloadGate()
        let service = SystemBackgroundSoundService(
            assetRoots: [],
            downloadedAssetRoot: testRoot,
            assetDownloader: queuedDownloadTestDownloader(using: gate)
        )

        service.requestDownload(sound: .rain)
        await gate.waitUntilRequested("Rain")
        service.requestDownload(sound: .ocean)
        service.cancelDownload(sound: .rain)

        try await Task.sleep(for: .milliseconds(25))
        let oceanStartedBeforeCancellationFinished = await gate.hasRequested("Ocean")
        #expect(!oceanStartedBeforeCancellationFinished)
        #expect(service.downloadState(for: .ocean) == .queued)

        await gate.cancelDownload(for: "Rain")
        let oceanStarted = await waitUntil { service.downloadState(for: .ocean) == .downloading }
        #expect(oceanStarted)
        await gate.waitUntilRequested("Ocean")

        await gate.completeDownload(for: "Ocean")
        let oceanFinished = await waitUntil { !service.isDownloading(.ocean) }
        #expect(oceanFinished)
        await gate.cleanup()
    }

    @Test
    @MainActor
    func revokesAutoPlayIntentWhenSwitchingSelection() async throws {
        let testRoot = URL(fileURLWithPath: "/tmp/test-sounds-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let gate = BackgroundSoundDownloadGate()
        let service = SystemBackgroundSoundService(
            assetRoots: [],
            downloadedAssetRoot: testRoot,
            assetDownloader: queuedDownloadTestDownloader(using: gate)
        )

        service.requestDownload(sound: .rain, playWhenReady: true)
        await gate.waitUntilRequested("Rain")
        service.requestDownload(sound: .ocean, playWhenReady: false)

        await gate.completeDownload(for: "Rain")
        let oceanStarted = await waitUntil { service.downloadState(for: .ocean) == .downloading }
        #expect(oceanStarted)
        #expect(!service.isPlaying)

        await gate.waitUntilRequested("Ocean")
        service.cancelAllDownloads()
        await gate.cancelAll()
        await Task.yield()
        await gate.cleanup()
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test
    @MainActor
    func preloadsTwoPlaybackCycles() {
        #expect(SystemBackgroundSoundService.initialPlaybackCycleCount == 2)
    }

    @Test
    @MainActor
    func startsAndStopsInstalledBackgroundSoundIfAvailable() {
        let systemRoot = URL(
            fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_ComfortSoundsAssets",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: systemRoot.path) else { return }

        let service = SystemBackgroundSoundService(assetRoots: [systemRoot])
        guard service.isInstalled(.rain) else { return }

        #expect(service.play(sound: .rain))
        #expect(service.isPlaying)
        #expect(service.playingSound == .rain)

        service.stop()
        #expect(!service.isPlaying)
        #expect(service.playingSound == nil)
    }
}

private let queuedDownloadTestArchive = Data("background sound test archive".utf8)

private func queuedDownloadTestDownloader(
    using gate: BackgroundSoundDownloadGate
) -> SystemBackgroundSoundAssetDownloader {
    let checksum = Data(Insecure.SHA1.hash(data: queuedDownloadTestArchive))
    let archiveSize = queuedDownloadTestArchive.count

    return SystemBackgroundSoundAssetDownloader(
        manifestPath: URL(fileURLWithPath: "/dev/null"),
        loadData: { request in
            guard let soundName = request.url?.deletingPathExtension().lastPathComponent else {
                throw URLError(.badURL)
            }
            return try await gate.response(for: soundName)
        },
        readPlist: { _ in
            let assets: [[String: Any]] = ["Rain", "Ocean"].map { soundName in
                [
                    "SoundName": soundName,
                    "__BaseURL": "https://example.com/",
                    "__RelativePath": "\(soundName).zip",
                    "_Measurement": checksum,
                    "_DownloadSize": archiveSize,
                    "_UnarchivedSize": archiveSize,
                ]
            }
            return ["Assets": assets]
        },
        unzip: { archiveURL, destination in
            let soundName = archiveURL.deletingPathExtension().lastPathComponent
            let assetData = destination.appendingPathComponent("AssetData", isDirectory: true)
            try FileManager.default.createDirectory(at: assetData, withIntermediateDirectories: true)
            let metadata = ["MobileAssetProperties": ["SoundName": soundName]]
            let metadataData = try PropertyListSerialization.data(
                fromPropertyList: metadata,
                format: .xml,
                options: 0
            )
            try metadataData.write(to: destination.appendingPathComponent("Info.plist"))
            try Data().write(to: assetData.appendingPathComponent("\(soundName).m4a"))
        }
    )
}

private actor BackgroundSoundDownloadGate {
    private let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("BackgroundSoundDownloadGate-\(UUID().uuidString)", isDirectory: true)
    private var pendingResponses: [String: CheckedContinuation<(URL, HTTPURLResponse), Error>] = [:]
    private var requestedSounds: Set<String> = []
    private var requestWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    init() {
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    func response(for soundName: String) async throws -> (URL, HTTPURLResponse) {
        requestedSounds.insert(soundName)
        let waiters = requestWaiters.removeValue(forKey: soundName) ?? []
        waiters.forEach { $0.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[soundName] = continuation
        }
    }

    func waitUntilRequested(_ soundName: String) async {
        guard !requestedSounds.contains(soundName) else { return }
        await withCheckedContinuation { continuation in
            requestWaiters[soundName, default: []].append(continuation)
        }
    }

    func hasRequested(_ soundName: String) -> Bool {
        requestedSounds.contains(soundName)
    }

    func completeDownload(for soundName: String) {
        guard let continuation = pendingResponses.removeValue(forKey: soundName) else { return }

        let archiveURL = temporaryDirectory.appendingPathComponent("\(soundName).zip")
        do {
            try queuedDownloadTestArchive.write(to: archiveURL)
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com/\(soundName).zip")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            continuation.resume(returning: (archiveURL, response))
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func cancelDownload(for soundName: String) {
        pendingResponses.removeValue(forKey: soundName)?.resume(throwing: CancellationError())
    }

    func cancelAll() {
        let pending = pendingResponses
        pendingResponses.removeAll()
        pending.values.forEach { $0.resume(throwing: CancellationError()) }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}
