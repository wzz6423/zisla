import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
struct BilibiliDirectDownloaderLifecycleTests {
    @Test(arguments: LifecycleWaitKind.allCases)
    func cancelledWaitRejectsEvenAnAlreadySatisfiedCondition(kind: LifecycleWaitKind) async throws {
        let client = LifecycleBilibiliHTTPClient()
        let task = Task<Void, Error> {
            withUnsafeCurrentTask { $0?.cancel() }
            switch kind {
            case .requests: try await client.waitForRequests(0)
            case .paused: try await client.waitForPausedDownloads(0)
            case .completed: try await client.waitForCompletedDownloads(0)
            }
        }

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test(arguments: LifecycleWaitKind.allCases)
    func anUnreachableConditionTimesOut(kind: LifecycleWaitKind) async throws {
        let client = LifecycleBilibiliHTTPClient()

        await #expect(throws: LifecycleWaitError.timedOut) {
            switch kind {
            case .requests: try await client.waitForRequests(1, timeout: .zero)
            case .paused: try await client.waitForPausedDownloads(1, timeout: .zero)
            case .completed: try await client.waitForCompletedDownloads(1, timeout: .zero)
            }
        }
        #expect(await client.activeRequestCount == 0)
    }

    @Test
    func aFailedWaitJoinsBeforeReturningToItsCaller() async throws {
        try await LifecycleBilibiliHTTPClient().verifyWaitCleanup()
    }

    @Test(.timeLimit(.minutes(1)), arguments: LifecycleWaitKind.allCases, [false, true])
    func failedWaitCancelsAndJoinsItsDownload(kind: LifecycleWaitKind, requiresRelease: Bool) async throws {
        let directory = lifecycleTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = LifecycleBilibiliHTTPClient(ignoresCancellation: requiresRelease)
        let muxer = LifecycleMediaMuxer()
        let service = lifecycleDownloadService(directory: directory, client: client, muxer: muxer)
        let output = directory.appendingPathComponent("Output")
        let request = try DownloadRequest(urlString: lifecycleVideoURL, mode: .video, outputDirectory: output)
        let task = Task { try await service.download(request) }
        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(20))
            } catch {
                return
            }
            Issue.record("Wait cleanup left a media download suspended")
            task.cancel()
            await client.releasePausedDownloads()
        }

        await #expect(throws: LifecycleWaitError.timedOut) {
            try await withLifecycleDownload(task: task, client: client) {
                try await client.waitForPausedDownloads(2)
                switch kind {
                case .requests: try await client.waitForRequests(3, timeout: .zero)
                case .paused: try await client.waitForPausedDownloads(3, timeout: .zero)
                case .completed: try await client.waitForCompletedDownloads(1, timeout: .zero)
                }
            }
        }
        watchdog.cancel()

        #expect(await client.activeRequestCount == 0)
        #expect(await client.pausedDownloadCount == 0)
        #expect(await muxer.invocationCount == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(
            atPath: directory.appendingPathComponent("Tasks").path
        ).isEmpty)
        await #expect(throws: CancellationError.self) { try await task.value }
        await watchdog.value
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingTheWaitCancelsAndJoinsItsDownload() async throws {
        let directory = lifecycleTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = LifecycleBilibiliHTTPClient()
        let task = Task {
            try await BilibiliDirectDownloader(httpClient: client).downloadComponents(
                from: lifecycleVideoURL, to: directory
            )
        }
        let waiter = Task {
            try await withLifecycleDownload(task: task, client: client) {
                try await client.waitForCompletedDownloads(1)
            }
        }
        try await withLifecycleDownload(task: waiter, client: client) {
            try await client.waitForPausedDownloads(2)
            waiter.cancel()
            await #expect(throws: CancellationError.self) { try await waiter.value }
        }
        #expect(await client.activeRequestCount == 0)
        #expect(await client.pausedDownloadCount == 0)
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test(.timeLimit(.minutes(1)), arguments: LifecycleTrack.allCases, [false, true])
    func aFailedTrackCancelsItsPendingSibling(failingTrack: LifecycleTrack, transportFailure: Bool) async throws {
        let directory = lifecycleTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = LifecycleBilibiliHTTPClient(failingTrack: failingTrack, transportFailure: transportFailure)
        let muxer = LifecycleMediaMuxer()
        let service = lifecycleDownloadService(directory: directory, client: client, muxer: muxer)
        let output = directory.appendingPathComponent("Output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let existing = output.appendingPathComponent("existing.mp4")
        try Data("preserved".utf8).write(to: existing)
        let request = try DownloadRequest(urlString: lifecycleVideoURL, mode: .video, outputDirectory: output)
        let taskID = UUID()

        // This only releases a broken implementation; it is not a transfer-speed threshold.
        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(20))
            } catch {
                return
            }
            Issue.record("A failed media track left its sibling waiting indefinitely")
            await client.releasePausedDownloads()
        }
        let result = await Task { try await service.download(request, taskID: taskID) }.result
        watchdog.cancel()
        await watchdog.value

        switch result {
        case .success:
            Issue.record("An exhausted media request must fail the download")
        case let .failure(error):
            guard let error = error as? BilibiliDirectDownloaderError else {
                Issue.record("Expected the original media failure, received \(error)")
                return
            }
            guard case let .mediaDownloadFailed(diagnostic) = error else {
                Issue.record("Expected the original media failure, received \(error)")
                return
            }
            if transportFailure {
                #expect(diagnostic == URLError(.cannotConnectToHost).localizedDescription)
            } else {
                #expect(diagnostic.contains("503"))
            }
        }

        #expect(await client.cancelledTracks == [failingTrack.other],
                "The remaining track must observe cancellation without finishing its transfer")
        #expect(await client.activeRequestCount == 0)
        #expect(await client.maximumActiveRequestCount == 2)
        #expect(await client.bytesWritten == 14,
                "A terminal failure must not allow more bytes to be transferred by its sibling")
        #expect(await muxer.invocationCount == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path) == ["existing.mp4"])
        #expect(try String(contentsOf: existing, encoding: .utf8) == "preserved")
        #expect(try FileManager.default.contentsOfDirectory(
            atPath: directory.appendingPathComponent("Tasks").path
        ).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)), arguments: LifecycleTrack.allCases)
    func successfulTransfersRemainConcurrentAndKeepComponentOrder(firstToFinish: LifecycleTrack) async throws {
        let directory = lifecycleTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = LifecycleBilibiliHTTPClient()
        let task = Task {
            try await BilibiliDirectDownloader(httpClient: client).downloadComponents(
                from: lifecycleVideoURL, to: directory
            )
        }

        try await withLifecycleDownload(task: task, client: client) {
            try await client.waitForPausedDownloads(2)
            #expect(await client.activeRequestCount == 2)
            await client.releasePausedDownloads(track: firstToFinish)
            try await client.waitForCompletedDownloads(1)
            #expect(await client.activeRequestCount == 1)
            #expect(await client.cancelledTracks.isEmpty)
            await client.releasePausedDownloads(track: firstToFinish.other)
            let components = try await task.value

            #expect(components.map(\.kind) == [.video, .audio])
            #expect(components.map(\.formatID) == ["32", "30280"])
            #expect(try components.map { try String(contentsOf: $0.fileURL, encoding: .utf8) }
                    == ["/video.mp4", "/audio.m4a"])
            #expect(await client.activeRequestCount == 0)
            #expect(await client.maximumActiveRequestCount == 2)
            #expect(await client.bytesWritten == 34)
        }
    }

    @Test
    func successfulTransferProducesBothFilesWithoutAReleaseGate() async throws {
        let directory = lifecycleTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = LifecycleBilibiliHTTPClient(pausesDownloads: false)

        let components = try await BilibiliDirectDownloader(httpClient: client).downloadComponents(
            from: lifecycleVideoURL, to: directory
        )

        #expect(components.map(\.kind) == [.video, .audio])
        #expect(try components.map { try String(contentsOf: $0.fileURL, encoding: .utf8) }
                == ["/video.mp4", "/audio.m4a"])
        #expect(await client.requestedMediaURLs.count == 2)
        #expect(await client.activeRequestCount == 0)
    }

    @Test(.timeLimit(.minutes(1)), arguments: LifecycleTrack.allCases)
    func aSuccessfulBackupDoesNotCancelTheOtherTrack(backupTrack: LifecycleTrack) async throws {
        let directory = lifecycleTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = LifecycleBilibiliHTTPClient(backupTrack: backupTrack)
        let muxer = LifecycleMediaMuxer()
        let service = lifecycleDownloadService(directory: directory, client: client, muxer: muxer)
        let output = directory.appendingPathComponent("Output")
        let request = try DownloadRequest(urlString: lifecycleVideoURL, mode: .video, outputDirectory: output)
        let task = Task { try await service.download(request) }

        try await withLifecycleDownload(task: task, client: client) {
            try await client.waitForPausedDownloads(2)
            #expect(await client.failureCount == 1)
            #expect(await client.activeRequestCount == 2)
            #expect(await client.cancelledTracks.isEmpty)
            await client.releasePausedDownloads()
            let result = try await task.value
            let requested = await client.requestedMediaURLs

            #expect(try String(contentsOf: result.fileURL, encoding: .utf8) == "/video.mp4|/audio.m4a")
            #expect(requested.count == 3)
            #expect(requested.filter { $0.deletingPathExtension().lastPathComponent == backupTrack.rawValue }
                    .map(\.host) == ["cdn.example", "backup.cdn.example"])
            #expect(await client.cancelledTracks.isEmpty)
            #expect(await client.activeRequestCount == 0)
            #expect(await client.maximumActiveRequestCount == 2)
            #expect(await muxer.invocationCount == 1)
        }
        #expect(try FileManager.default.contentsOfDirectory(
            atPath: directory.appendingPathComponent("Tasks").path
        ).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 2])
    func cancellationStopsBothTracksAndRemovesPartialFiles(cancellation: Int) async throws {
        let directory = lifecycleTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = LifecycleBilibiliHTTPClient()
        let muxer = LifecycleMediaMuxer()
        let service = lifecycleDownloadService(directory: directory, client: client, muxer: muxer)
        let output = directory.appendingPathComponent("Output")
        let request = try DownloadRequest(urlString: lifecycleVideoURL, mode: .video, outputDirectory: output)
        let taskID = UUID()
        let task = Task { try await service.download(request, taskID: taskID) }

        try await withLifecycleDownload(task: task, client: client) {
            try await client.waitForPausedDownloads(2)
            switch cancellation {
            case 0: task.cancel()
            case 1: await service.cancel(taskID: taskID)
            default: await service.cancelAll()
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        }

        #expect(await client.cancelledTracks.sorted { $0.rawValue < $1.rawValue } == [.audio, .video])
        #expect(await client.activeRequestCount == 0)
        #expect(await client.bytesWritten == 14)
        #expect(await muxer.invocationCount == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(
            atPath: directory.appendingPathComponent("Tasks").path
        ).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)), arguments: LifecycleTrack.allCases)
    func serviceReleasesFailedTaskIDsForRetry(failingTrack: LifecycleTrack) async throws {
        let directory = lifecycleTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = LifecycleBilibiliHTTPClient(failingTrack: failingTrack)
        let muxer = LifecycleMediaMuxer()
        let service = lifecycleDownloadService(directory: directory, client: client, muxer: muxer)
        let output = directory.appendingPathComponent("Output")
        let request = try DownloadRequest(urlString: lifecycleVideoURL, mode: .video, outputDirectory: output)
        let taskID = UUID()
        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(20))
            } catch {
                return
            }
            Issue.record("A failed media track left its sibling waiting indefinitely")
            await client.releasePausedDownloads()
        }

        let failure = await Task { try await service.download(request, taskID: taskID) }.result
        watchdog.cancel()
        await watchdog.value
        guard case let .failure(error) = failure,
              case .mediaDownloadFailed = error as? BilibiliDirectDownloaderError else {
            Issue.record("Expected the original media failure, received \(failure)")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(
            atPath: directory.appendingPathComponent("Tasks").path
        ).isEmpty)
        await client.prepareSuccessfulRetry()

        let result = try await service.download(request, taskID: taskID)
        #expect(result.taskID == taskID)
        #expect(try String(contentsOf: result.fileURL, encoding: .utf8) == "/video.mp4|/audio.m4a")
        #expect(await client.activeRequestCount == 0)
        #expect(await muxer.invocationCount == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).count == 1)
        #expect(try FileManager.default.contentsOfDirectory(
            atPath: directory.appendingPathComponent("Tasks").path
        ).isEmpty)
    }
}

private let lifecycleVideoURL = "https://www.bilibili.com/video/BV1d2N16KEh6/"

enum LifecycleTrack: String, CaseIterable, Sendable {
    case video
    case audio

    var other: Self { self == .video ? .audio : .video }
}

enum LifecycleWaitKind: CaseIterable, Sendable {
    case requests
    case paused
    case completed
}

private enum LifecycleWaitError: Error, Equatable {
    case timedOut
}

private func withLifecycleDownload<Value: Sendable>(
    task: Task<Value, Error>,
    client: isolated LifecycleBilibiliHTTPClient,
    operation: () async throws -> Void
) async throws {
    do {
        try await operation()
    } catch {
        task.cancel()
        client.releasePausedDownloads()
        _ = await task.result
        throw error
    }
}

private func lifecycleTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("BilibiliLifecycleTests-\(UUID().uuidString)", isDirectory: true)
}

private func lifecycleDownloadService(
    directory: URL,
    client: LifecycleBilibiliHTTPClient,
    muxer: LifecycleMediaMuxer
) -> DownloadService {
    DownloadService(
        resolver: YTDLPResolver(
            bundleURL: directory.appendingPathComponent("Empty.app"),
            managedToolsDirectory: directory.appendingPathComponent("Tools"),
            externalYTDLPCandidates: [],
            externalFFmpegCandidates: []
        ),
        temporaryRootDirectory: directory.appendingPathComponent("Tasks"),
        mediaMuxer: muxer,
        bilibiliDownloader: BilibiliDirectDownloader(httpClient: client),
        browserCookieSourceProvider: { [] }
    )
}

private actor LifecycleMediaMuxer: MediaMuxing {
    private(set) var invocationCount = 0

    func mux(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        invocationCount += 1
        let video = try String(contentsOf: videoURL, encoding: .utf8)
        let audio = try String(contentsOf: audioURL, encoding: .utf8)
        try Data("\(video)|\(audio)".utf8).write(to: outputURL)
    }
}

private actor LifecycleBilibiliHTTPClient: BilibiliHTTPClient {
    private var failingTrack: LifecycleTrack?
    private let transportFailure: Bool
    private let backupTrack: LifecycleTrack?
    private let ignoresCancellation: Bool
    private var pausesDownloads: Bool
    private var cleanupTaskCompleted = false
    private var pending: [UUID: (LifecycleTrack, CheckedContinuation<Void, Error>)] = [:]
    private(set) var requestedMediaURLs: [URL] = []
    private(set) var cancelledTracks: [LifecycleTrack] = []
    private(set) var failureCount = 0
    private(set) var completedDownloadCount = 0
    private(set) var activeRequestCount = 0
    private(set) var maximumActiveRequestCount = 0
    private(set) var bytesWritten = 0

    var pausedDownloadCount: Int { pending.count }

    func verifyWaitCleanup() async throws {
        // Actor isolation prevents the task from finishing until the cleanup joins it.
        let task = Task<Void, Error> {
            cleanupTaskCompleted = true
            try Task.checkCancellation()
        }
        do {
            try await withLifecycleDownload(task: task, client: self) {
                let completedBeforeWait = self.cleanupTaskCompleted
                #expect(!completedBeforeWait)
                throw LifecycleWaitError.timedOut
            }
            Issue.record("The original wait error must propagate")
        } catch {
            #expect(error as? LifecycleWaitError == .timedOut)
        }
        let completedBeforeReturn = cleanupTaskCompleted
        #expect(completedBeforeReturn, "Wait cleanup must join its task before returning")
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    init(
        failingTrack: LifecycleTrack? = nil,
        transportFailure: Bool = false,
        backupTrack: LifecycleTrack? = nil,
        pausesDownloads: Bool = true,
        ignoresCancellation: Bool = false
    ) {
        self.failingTrack = failingTrack
        self.transportFailure = transportFailure
        self.backupTrack = backupTrack
        self.pausesDownloads = pausesDownloads
        self.ignoresCancellation = ignoresCancellation
    }

    func data(for request: URLRequest) async throws -> BilibiliHTTPDataResponse {
        let url = try #require(request.url)
        var json: String
        if url.path == "/x/web-interface/view" {
            json = #"{"code":0,"data":{"title":"Lifecycle","cid":111}}"#
        } else {
            #expect(url.path == "/x/player/playurl")
            json = #"{"code":0,"data":{"dash":{"video":[{"id":32,"baseUrl":"https://cdn.example/video.mp4","codecs":"avc1","mimeType":"video/mp4"}],"audio":[{"id":30280,"baseUrl":"https://cdn.example/audio.m4a"}]}}}"#
        }
        if let backupTrack {
            let suffix = backupTrack == .video ? "mp4" : "m4a"
            let base = "\"baseUrl\":\"https://cdn.example/\(backupTrack.rawValue).\(suffix)\""
            json = json.replacingOccurrences(of: base, with:
                base + ",\"backupUrl\":[\"https://backup.cdn.example/\(backupTrack.rawValue).\(suffix)\"]"
            )
        }
        return BilibiliHTTPDataResponse(data: Data(json.utf8), statusCode: 200)
    }

    func download(for request: URLRequest, to destinationURL: URL) async throws -> BilibiliHTTPResponse {
        let url = try #require(request.url)
        let track = try #require(LifecycleTrack(rawValue: url.deletingPathExtension().lastPathComponent))
        requestedMediaURLs.append(url)
        activeRequestCount += 1
        maximumActiveRequestCount = max(maximumActiveRequestCount, activeRequestCount)
        defer {
            activeRequestCount -= 1
        }
        try write(Data("partial".utf8), to: destinationURL)

        if track == failingTrack || (track == backupTrack && url.host == "cdn.example") {
            try await waitForRequests(2)
            failureCount += 1
            if transportFailure { throw URLError(.cannotConnectToHost) }
            return BilibiliHTTPResponse(statusCode: 503)
        }

        if pausesDownloads {
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled {
                        cancelledTracks.append(track)
                        continuation.resume(throwing: CancellationError())
                    } else {
                        pending[id] = (track, continuation)
                    }
                }
            } onCancel: {
                Task { await self.cancel(id: id) }
            }
        }
        try Task.checkCancellation()
        try write(Data(url.path.utf8), to: destinationURL)
        completedDownloadCount += 1
        return BilibiliHTTPResponse(statusCode: 200)
    }

    func waitForRequests(_ count: Int, timeout: Duration = .seconds(3)) async throws {
        try Task.checkCancellation()
        let deadline = ContinuousClock.now + timeout
        while requestedMediaURLs.count < count {
            guard ContinuousClock.now < deadline else { throw LifecycleWaitError.timedOut }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    func waitForPausedDownloads(_ count: Int, timeout: Duration = .seconds(3)) async throws {
        try Task.checkCancellation()
        let deadline = ContinuousClock.now + timeout
        while pending.count < count {
            guard ContinuousClock.now < deadline else { throw LifecycleWaitError.timedOut }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    func waitForCompletedDownloads(_ count: Int, timeout: Duration = .seconds(3)) async throws {
        try Task.checkCancellation()
        let deadline = ContinuousClock.now + timeout
        while completedDownloadCount < count {
            guard ContinuousClock.now < deadline else { throw LifecycleWaitError.timedOut }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    func releasePausedDownloads(track: LifecycleTrack? = nil) {
        let ids = pending.filter { track == nil || $0.value.0 == track }.map(\.key)
        ids.forEach { pending.removeValue(forKey: $0)?.1.resume() }
    }

    func prepareSuccessfulRetry() {
        failingTrack = nil
        pausesDownloads = false
    }

    private func cancel(id: UUID) {
        guard !ignoresCancellation else { return }
        guard let (track, continuation) = pending.removeValue(forKey: id) else { return }
        cancelledTracks.append(track)
        continuation.resume(throwing: CancellationError())
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
        bytesWritten += data.count
    }
}
