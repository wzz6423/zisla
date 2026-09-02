import AppKit
import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct YTDLPResolverTests {
    @Test
    func bundledHelperTakesPriorityOverExternalExecutable() throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundleURL = directory.appendingPathComponent("Zisla.app", isDirectory: true)
        let helper = bundleURL.appendingPathComponent("Contents/Helpers/yt-dlp")
        let external = directory.appendingPathComponent("external/yt-dlp")
        try writeExecutable("#!/bin/sh\nexit 0\n", to: helper)
        try writeExecutable("#!/bin/sh\nexit 0\n", to: external)

        let tools = try YTDLPResolver(
            bundleURL: bundleURL,
            managedToolsDirectory: directory.appendingPathComponent("ManagedTools", isDirectory: true),
            externalYTDLPCandidates: [external],
            externalFFmpegCandidates: []
        ).resolve()

        #expect(tools.ytDLPURL == helper.resolvingSymlinksInPath().standardizedFileURL)
        #expect(tools.ffmpegURL == nil)
    }

    @Test
    func resolverRejectsWorldWritableExecutableAndUsesFallback() throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundleURL = directory.appendingPathComponent("Zisla.app", isDirectory: true)
        let unsafeHelper = bundleURL.appendingPathComponent("Contents/Helpers/yt-dlp")
        let fallback = directory.appendingPathComponent("safe/yt-dlp")
        try writeExecutable("#!/bin/sh\nexit 0\n", to: unsafeHelper, permissions: 0o777)
        try writeExecutable("#!/bin/sh\nexit 0\n", to: fallback)

        let tools = try YTDLPResolver(
            bundleURL: bundleURL,
            managedToolsDirectory: directory.appendingPathComponent("ManagedTools", isDirectory: true),
            externalYTDLPCandidates: [unsafeHelper, fallback],
            externalFFmpegCandidates: []
        ).resolve()

        #expect(tools.ytDLPURL == fallback.resolvingSymlinksInPath().standardizedFileURL)
    }

    @Test
    func resolverRejectsSymlinkFromWorldWritableDirectory() throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let trustedTarget = directory.appendingPathComponent("trusted/yt-dlp")
        let unsafeDirectory = directory.appendingPathComponent("unsafe-links", isDirectory: true)
        let unsafeLink = unsafeDirectory.appendingPathComponent("yt-dlp")
        let fallback = directory.appendingPathComponent("fallback/yt-dlp")
        try writeExecutable("#!/bin/sh\nexit 0\n", to: trustedTarget)
        try FileManager.default.createDirectory(
            at: unsafeDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o777)],
            ofItemAtPath: unsafeDirectory.path
        )
        try FileManager.default.createSymbolicLink(
            at: unsafeLink,
            withDestinationURL: trustedTarget
        )
        try writeExecutable("#!/bin/sh\nexit 0\n", to: fallback)

        let tools = try YTDLPResolver(
            bundleURL: directory.appendingPathComponent("Empty.app"),
            managedToolsDirectory: directory.appendingPathComponent("ManagedTools", isDirectory: true),
            externalYTDLPCandidates: [unsafeLink, fallback],
            externalFFmpegCandidates: []
        ).resolve()

        #expect(tools.ytDLPURL == fallback.standardizedFileURL)
    }
}

@Suite(.serialized)
struct DownloadServiceTests {
    @Test
    func nativeMuxerRejectsInputWithoutMediaTracks() async throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let video = directory.appendingPathComponent("video.mp4")
        let audio = directory.appendingPathComponent("audio.m4a")
        let output = directory.appendingPathComponent("output.mp4")
        try Data().write(to: video)
        try Data().write(to: audio)

        do {
            try await NativeMediaMuxer().mux(
                videoURL: video,
                audioURL: audio,
                outputURL: output
            )
            Issue.record("Inputs without tracks must fail")
        } catch let error as NativeMediaMuxerError {
            #expect(error == .missingVideoTrack)
        }
    }

    @Test
    func nativeMuxerErrorsIdentifyTheMissingTrack() {
        #expect(
            NativeMediaMuxerError.missingVideoTrack.localizedDescription
                .contains("视频轨")
        )
    }

    @Test
    func processEnvironmentRemovesDynamicLoaderAndPythonOverrides() {
        let environment = DownloadProcessEnvironment.sanitized([
            "PATH": "/usr/bin",
            "HOME": "/Users/me",
            "DYLD_INSERT_LIBRARIES": "/tmp/inject.dylib",
            "DYLD_LIBRARY_PATH": "/tmp/lib",
            "PYTHONPATH": "/tmp/python",
            "PYTHONHOME": "/tmp/home",
        ])

        #expect(environment["PATH"] == "/usr/bin")
        #expect(environment["HOME"] == "/Users/me")
        #expect(environment.keys.allSatisfy { !$0.hasPrefix("DYLD_") })
        #expect(environment.keys.allSatisfy { !$0.hasPrefix("PYTHON") })
    }

    @Test
    func serviceReturnsExistingFileReportedBySuccessfulProcess() async throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("tools/yt-dlp")
        let outputDirectory = directory.appendingPathComponent("Downloads", isDirectory: true)
        let outputFile = outputDirectory.appendingPathComponent("result.mp4")
        let escapedOutputPath = shellSingleQuoted(outputFile.path)
        let jsonPath = outputFile.path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        #!/bin/sh
        /bin/mkdir -p \(shellSingleQuoted(outputDirectory.path))
        /usr/bin/touch \(escapedOutputPath)
        /usr/bin/printf '%s\\n' '\(YTDLPOutputParser.sentinel){"event":"completed","filepath":"\(jsonPath)"}'
        """
        try writeExecutable(script, to: executable)
        let resolver = YTDLPResolver(
            bundleURL: directory.appendingPathComponent("Empty.app"),
            managedToolsDirectory: directory.appendingPathComponent("ManagedTools", isDirectory: true),
            externalYTDLPCandidates: [executable],
            externalFFmpegCandidates: []
        )
        let service = DownloadService(
            resolver: resolver,
            temporaryRootDirectory: directory.appendingPathComponent("Tasks", isDirectory: true)
        )
        let request = try DownloadRequest(
            urlString: "https://example.com/audio.m4a",
            mode: .audio,
            outputDirectory: outputDirectory
        )

        let result = try await service.download(request, taskID: UUID())

        #expect(result.fileURL == outputFile.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: result.fileURL.path))
    }

    @Test
    func serviceRunsSeparateDownloadTasksConcurrently() async throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("tools/yt-dlp")
        let firstOutputDirectory = directory.appendingPathComponent("Downloads/one", isDirectory: true)
        let secondOutputDirectory = directory.appendingPathComponent("Downloads/two", isDirectory: true)
        let firstOutput = firstOutputDirectory.appendingPathComponent("one.m4a")
        let secondOutput = secondOutputDirectory.appendingPathComponent("two.m4a")
        let firstMarker = directory.appendingPathComponent("one.started")
        let secondMarker = directory.appendingPathComponent("two.started")
        let releaseMarker = directory.appendingPathComponent("release")
        let firstOutputJSON = jsonEscaped(firstOutput.path)
        let secondOutputJSON = jsonEscaped(secondOutput.path)
        let script = """
        #!/bin/sh
        url=""
        for arg in "$@"; do url="$arg"; done
        case "$url" in
        *one*) target=\(shellSingleQuoted(firstOutput.path)); marker=\(shellSingleQuoted(firstMarker.path)); json=\(shellSingleQuoted(firstOutputJSON)) ;;
        *two*) target=\(shellSingleQuoted(secondOutput.path)); marker=\(shellSingleQuoted(secondMarker.path)); json=\(shellSingleQuoted(secondOutputJSON)) ;;
        *) exit 2 ;;
        esac
        /bin/mkdir -p "$(/usr/bin/dirname "$target")"
        /usr/bin/touch "$marker"
        while [ ! -f \(shellSingleQuoted(releaseMarker.path)) ]; do /bin/sleep 0.02; done
        /usr/bin/touch "$target"
        /usr/bin/printf '%s\\n' '\(YTDLPOutputParser.sentinel){"event":"completed","filepath":"'$json'"}'
        """
        try writeExecutable(script, to: executable)

        let service = DownloadService(
            resolver: YTDLPResolver(
                bundleURL: directory.appendingPathComponent("Empty.app"),
                managedToolsDirectory: directory.appendingPathComponent("ManagedTools", isDirectory: true),
                externalYTDLPCandidates: [executable],
                externalFFmpegCandidates: []
            ),
            temporaryRootDirectory: directory.appendingPathComponent("Tasks", isDirectory: true)
        )
        let firstRequest = try DownloadRequest(
            urlString: "https://example.com/one",
            mode: .audio,
            outputDirectory: firstOutputDirectory
        )
        let secondRequest = try DownloadRequest(
            urlString: "https://example.com/two",
            mode: .audio,
            outputDirectory: secondOutputDirectory
        )
        let firstTask = Task { try await service.download(firstRequest, taskID: UUID()) }
        let secondTask = Task { try await service.download(secondRequest, taskID: UUID()) }

        var bothStarted = false
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: firstMarker.path),
               FileManager.default.fileExists(atPath: secondMarker.path) {
                bothStarted = true
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(bothStarted)
        try Data().write(to: releaseMarker)

        let firstResult = try await firstTask.value
        let secondResult = try await secondTask.value
        #expect(firstResult.fileURL == firstOutput.standardizedFileURL)
        #expect(secondResult.fileURL == secondOutput.standardizedFileURL)
    }

    @Test
    func serviceNativePackagesSeparateDASHComponents() async throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("tools/yt-dlp")
        let taskID = UUID()
        let taskDirectory = directory.appendingPathComponent("Tasks/\(taskID.uuidString)")
        let video = taskDirectory.appendingPathComponent("result [BV].32.mp4")
        let audio = taskDirectory.appendingPathComponent("result [BV].30280.m4a")
        let videoJSON = jsonEscaped(video.path)
        let audioJSON = jsonEscaped(audio.path)
        let script = """
        #!/bin/sh
        /bin/mkdir -p \(shellSingleQuoted(taskDirectory.path))
        /usr/bin/touch \(shellSingleQuoted(video.path)) \(shellSingleQuoted(audio.path))
        /usr/bin/printf '%s\\n' '\(YTDLPOutputParser.sentinel){"event":"component","filepath":"\(videoJSON)","format_id":"32","vcodec":"avc1.64001F","acodec":"none"}'
        /usr/bin/printf '%s\\n' '\(YTDLPOutputParser.sentinel){"event":"component","filepath":"\(audioJSON)","format_id":"30280","vcodec":"none","acodec":"mp4a.40.2"}'
        """
        try writeExecutable(script, to: executable)
        let muxer = RecordingMediaMuxer()
        let service = DownloadService(
            resolver: YTDLPResolver(
                bundleURL: directory.appendingPathComponent("Empty.app"),
                managedToolsDirectory: directory.appendingPathComponent("ManagedTools", isDirectory: true),
                externalYTDLPCandidates: [executable],
                externalFFmpegCandidates: []
            ),
            temporaryRootDirectory: directory.appendingPathComponent("Tasks", isDirectory: true),
            mediaMuxer: muxer
        )
        let outputDirectory = directory.appendingPathComponent("Downloads", isDirectory: true)
        let request = try DownloadRequest(
            urlString: "https://example.com/video.mp4",
            mode: .video,
            outputDirectory: outputDirectory
        )

        let result = try await service.download(request, taskID: taskID)
        let call = await muxer.lastCall

        #expect(call?.videoURL == video.standardizedFileURL)
        #expect(call?.audioURL == audio.standardizedFileURL)
        #expect(result.fileURL == outputDirectory.appendingPathComponent("result [BV].mp4"))
        #expect(FileManager.default.fileExists(atPath: result.fileURL.path))
    }

    @Test
    func bilibiliVideoUsesNativeBackendBeforeLaunchingYTDLP() async throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("tools/yt-dlp")
        let invocationMarker = directory.appendingPathComponent("yt-dlp-invoked")
        try writeExecutable(
            "#!/bin/sh\n/usr/bin/touch \(shellSingleQuoted(invocationMarker.path))\nexit 1\n",
            to: executable
        )
        let muxer = RecordingMediaMuxer()
        let backend = RecordingBilibiliDownloader()
        let service = DownloadService(
            resolver: YTDLPResolver(
                bundleURL: directory.appendingPathComponent("Empty.app"),
                managedToolsDirectory: directory.appendingPathComponent("ManagedTools", isDirectory: true),
                externalYTDLPCandidates: [executable],
                externalFFmpegCandidates: []
            ),
            temporaryRootDirectory: directory.appendingPathComponent("Tasks", isDirectory: true),
            mediaMuxer: muxer,
            bilibiliDownloader: backend
        )
        let request = try DownloadRequest(
            urlString: "https://www.bilibili.com/video/BV1d2N16KEh6",
            mode: .video,
            outputDirectory: directory.appendingPathComponent("Downloads", isDirectory: true)
        )

        let result = try await service.download(request, taskID: UUID())

        #expect(await backend.requestedURL == request.urlString)
        #expect(await muxer.lastCall != nil)
        #expect(FileManager.default.fileExists(atPath: result.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: invocationMarker.path))
    }

    @Test
    func nativeBackendRejectsDuplicateTaskIDWhileDownloadIsRunning() async throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = RecordingBilibiliDownloader(pausesFirstDownload: true)
        let service = DownloadService(
            resolver: YTDLPResolver(
                bundleURL: directory.appendingPathComponent("Empty.app"),
                managedToolsDirectory: directory.appendingPathComponent("ManagedTools", isDirectory: true),
                externalYTDLPCandidates: [],
                externalFFmpegCandidates: []
            ),
            temporaryRootDirectory: directory.appendingPathComponent("Tasks", isDirectory: true),
            mediaMuxer: RecordingMediaMuxer(),
            bilibiliDownloader: backend
        )
        let request = try DownloadRequest(
            urlString: "https://www.bilibili.com/video/BV1d2N16KEh6",
            mode: .video,
            outputDirectory: directory.appendingPathComponent("Downloads", isDirectory: true)
        )
        let taskID = UUID()
        let firstTask = Task { try await service.download(request, taskID: taskID) }

        var firstStarted = false
        for _ in 0..<100 {
            if await backend.invocationCount == 1 {
                firstStarted = true
                break
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(firstStarted)

        do {
            _ = try await service.download(request, taskID: taskID)
            Issue.record("A running native download must reserve its task ID")
        } catch let error as DownloadServiceError {
            #expect(error == .duplicateTask(taskID))
        }

        await backend.releaseFirstDownload()
        _ = try await firstTask.value
        #expect(await backend.invocationCount == 1)
    }

    @Test
    func bilibiliVideoWorksWithoutYTDLPButAudioDoesNotUseVideoFallback() async throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = YTDLPResolver(
            bundleURL: directory.appendingPathComponent("Empty.app"),
            managedToolsDirectory: directory.appendingPathComponent("ManagedTools", isDirectory: true),
            externalYTDLPCandidates: [],
            externalFFmpegCandidates: []
        )
        let videoBackend = RecordingBilibiliDownloader()
        let videoService = DownloadService(
            resolver: resolver,
            temporaryRootDirectory: directory.appendingPathComponent("VideoTasks", isDirectory: true),
            mediaMuxer: RecordingMediaMuxer(),
            bilibiliDownloader: videoBackend
        )
        let videoRequest = try DownloadRequest(
            urlString: "https://www.bilibili.com/video/BV1d2N16KEh6",
            mode: .video,
            outputDirectory: directory.appendingPathComponent("VideoDownloads", isDirectory: true)
        )

        let videoResult = try await videoService.download(videoRequest, taskID: UUID())

        #expect(FileManager.default.fileExists(atPath: videoResult.fileURL.path))
        #expect(await videoBackend.requestedURL == videoRequest.urlString)

        let audioBackend = RecordingBilibiliDownloader()
        let audioService = DownloadService(
            resolver: resolver,
            temporaryRootDirectory: directory.appendingPathComponent("AudioTasks", isDirectory: true),
            mediaMuxer: RecordingMediaMuxer(),
            bilibiliDownloader: audioBackend
        )
        let audioRequest = try DownloadRequest(
            urlString: videoRequest.urlString,
            mode: .audio,
            outputDirectory: directory.appendingPathComponent("AudioDownloads", isDirectory: true)
        )

        do {
            _ = try await audioService.download(audioRequest, taskID: UUID())
            Issue.record("Audio mode must not invoke the video fallback")
        } catch {
            #expect(error is YTDLPResolverError)
        }
        #expect(await audioBackend.requestedURL == nil)
    }

    @Test
    func directBilibiliBackendSelectsAVCVideoAndHighestBandwidthAudio() async throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = StubBilibiliHTTPClient(directory: directory)
        let backend = BilibiliDirectDownloader(httpClient: client)

        let components = try await backend.downloadComponents(
            from: "https://www.bilibili.com/video/BV1d2N16KEh6",
            to: directory.appendingPathComponent("Task", isDirectory: true)
        )
        let requestedMediaURLs = await client.requestedMediaURLs

        #expect(components.map(\.kind).sorted(by: { $0.rawValue < $1.rawValue }) == [.audio, .video])
        #expect(requestedMediaURLs.contains(URL(string: "https://cdn.example/avc.mp4")!))
        #expect(requestedMediaURLs.contains(URL(string: "https://cdn.example/audio-high.m4a")!))
        #expect(!requestedMediaURLs.contains(URL(string: "https://cdn.example/hevc.mp4")!))
        #expect(components.allSatisfy { FileManager.default.fileExists(atPath: $0.fileURL.path) })
    }

    @Test
    func directBilibiliBackendErrorsExplainTheMissingCapability() {
        #expect(
            BilibiliDirectDownloaderError.missingDASHTracks.localizedDescription
                .contains("DASH")
        )
    }

    @Test
    func explicitCancellationTerminatesTheRunningProcess() async throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("tools/yt-dlp")
        try writeExecutable("#!/bin/sh\nexec /bin/sleep 30\n", to: executable)
        let service = DownloadService(
            resolver: YTDLPResolver(
                bundleURL: directory.appendingPathComponent("Empty.app"),
                managedToolsDirectory: directory.appendingPathComponent("ManagedTools", isDirectory: true),
                externalYTDLPCandidates: [executable],
                externalFFmpegCandidates: []
            ),
            temporaryRootDirectory: directory.appendingPathComponent("Tasks", isDirectory: true)
        )
        let request = try DownloadRequest(
            urlString: "https://example.com/video.mp4",
            mode: .video,
            outputDirectory: directory.appendingPathComponent("Downloads", isDirectory: true)
        )
        let taskID = UUID()
        let task = Task { try await service.download(request, taskID: taskID) }
        try await Task.sleep(for: .milliseconds(100))

        await service.cancel(taskID: taskID)

        do {
            _ = try await task.value
            Issue.record("Cancelled download should throw")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test
    func explicitCancellationTerminatesNativeBilibiliDownload() async throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = RecordingBilibiliDownloader(pausesFirstDownload: true)
        let service = DownloadService(
            resolver: YTDLPResolver(
                bundleURL: directory.appendingPathComponent("Empty.app"),
                managedToolsDirectory: directory.appendingPathComponent("ManagedTools", isDirectory: true),
                externalYTDLPCandidates: [],
                externalFFmpegCandidates: []
            ),
            temporaryRootDirectory: directory.appendingPathComponent("Tasks", isDirectory: true),
            mediaMuxer: RecordingMediaMuxer(),
            bilibiliDownloader: backend
        )
        let request = try DownloadRequest(
            urlString: "https://www.bilibili.com/video/BV1d2N16KEh6",
            mode: .video,
            outputDirectory: directory.appendingPathComponent("Downloads", isDirectory: true)
        )
        let taskID = UUID()
        let task = Task { try await service.download(request, taskID: taskID) }

        var downloadStarted = false
        for _ in 0..<100 {
            if await backend.invocationCount == 1 {
                downloadStarted = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(downloadStarted)

        await service.cancel(taskID: taskID)
        await backend.releaseFirstDownload()

        do {
            _ = try await task.value
            Issue.record("Cancelled Bilibili download should throw CancellationError")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(await backend.observedCancellation)
    }

    @Test
    func explicitCancellationTreatsNativeBilibiliBackendErrorAsCancellation() async throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = RecordingBilibiliDownloader(
            pausesFirstDownload: true,
            throwsGenericErrorAfterCancellation: true
        )
        let service = DownloadService(
            resolver: YTDLPResolver(
                bundleURL: directory.appendingPathComponent("Empty.app"),
                managedToolsDirectory: directory.appendingPathComponent("ManagedTools", isDirectory: true),
                externalYTDLPCandidates: [],
                externalFFmpegCandidates: []
            ),
            temporaryRootDirectory: directory.appendingPathComponent("Tasks", isDirectory: true),
            mediaMuxer: RecordingMediaMuxer(),
            bilibiliDownloader: backend
        )
        let request = try DownloadRequest(
            urlString: "https://www.bilibili.com/video/BV1d2N16KEh6",
            mode: .video,
            outputDirectory: directory.appendingPathComponent("Downloads", isDirectory: true)
        )
        let taskID = UUID()
        let task = Task { try await service.download(request, taskID: taskID) }

        var downloadStarted = false
        for _ in 0..<100 {
            if await backend.invocationCount == 1 {
                downloadStarted = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(downloadStarted)

        await service.cancel(taskID: taskID)
        await backend.releaseFirstDownload()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await backend.observedCancellation)
    }

    @Test
    func explicitCancellationBeforeMuxPreventsFileInstallation() async throws {
        let directory = kitTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let muxer = PausableMediaMuxer(throwsGenericErrorAfterCancellation: true)
        let service = DownloadService(
            resolver: YTDLPResolver(
                bundleURL: directory.appendingPathComponent("Empty.app"),
                managedToolsDirectory: directory.appendingPathComponent("ManagedTools", isDirectory: true),
                externalYTDLPCandidates: [],
                externalFFmpegCandidates: []
            ),
            temporaryRootDirectory: directory.appendingPathComponent("Tasks", isDirectory: true),
            mediaMuxer: muxer,
            bilibiliDownloader: RecordingBilibiliDownloader()
        )
        let outputDirectory = directory.appendingPathComponent("Downloads", isDirectory: true)
        let request = try DownloadRequest(
            urlString: "https://www.bilibili.com/video/BV1d2N16KEh6",
            mode: .video,
            outputDirectory: outputDirectory
        )
        let taskID = UUID()
        let task = Task { try await service.download(request, taskID: taskID) }

        var muxStarted = false
        for _ in 0..<100 {
            if await muxer.invocationCount == 1 {
                muxStarted = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(muxStarted)

        await service.cancel(taskID: taskID)
        await muxer.releaseMux()

        do {
            _ = try await task.value
            Issue.record("Cancelled download before mux completion should throw")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(await muxer.observedCancellation)

        let installedFiles = try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(installedFiles.isEmpty, "No files should be installed after cancellation")
    }

    @Test @MainActor
    func clipboardMonitoringIsDisabledByDefault() {
        let monitor = ClipboardLinkMonitor()

        #expect(!monitor.isEnabled)
    }

    @Test @MainActor
    func clipboardReadsAChangedValueOnlyOnce() {
        let source = CountingClipboardSource(changeCount: 7, value: "https://youtu.be/abc")
        let monitor = ClipboardLinkMonitor(source: source, pollInterval: 10)
        monitor.setEnabled(true)
        source.changeCount = 8

        monitor.pollNow()
        monitor.pollNow()

        #expect(source.stringReadCount == 1)
        monitor.setEnabled(false)
    }

    @Test @MainActor
    func namedPasteboardMonitoringNeverChangesOrClearsContents() {
        let name = NSPasteboard.Name("dev.wzz.zisla.tests.\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        pasteboard.clearContents()
        #expect(pasteboard.setString("initial", forType: .string))
        var detectedURL: URL?
        let monitor = ClipboardLinkMonitor(pasteboard: pasteboard, pollInterval: 10) {
            detectedURL = $0
        }
        monitor.setEnabled(true)
        pasteboard.clearContents()
        #expect(pasteboard.setString("https://youtu.be/abc", forType: .string))
        let changeCountBeforePoll = pasteboard.changeCount
        let valueBeforePoll = pasteboard.string(forType: .string)

        monitor.pollNow()

        #expect(detectedURL?.absoluteString == "https://youtu.be/abc")
        #expect(pasteboard.changeCount == changeCountBeforePoll)
        #expect(pasteboard.string(forType: .string) == valueBeforePoll)
        monitor.setEnabled(false)
        pasteboard.releaseGlobally()
    }
}

private actor RecordingMediaMuxer: MediaMuxing {
    struct Call: Sendable {
        let videoURL: URL
        let audioURL: URL
        let outputURL: URL
    }

    private(set) var lastCall: Call?

    func mux(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        lastCall = Call(videoURL: videoURL, audioURL: audioURL, outputURL: outputURL)
        try Data("muxed".utf8).write(to: outputURL)
    }
}

private actor PausableMediaMuxer: MediaMuxing {
    private let throwsGenericErrorAfterCancellation: Bool
    private(set) var invocationCount = 0
    private(set) var observedCancellation = false
    private var muxContinuation: CheckedContinuation<Void, Never>?

    init(throwsGenericErrorAfterCancellation: Bool = false) {
        self.throwsGenericErrorAfterCancellation = throwsGenericErrorAfterCancellation
    }

    func mux(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        invocationCount += 1
        await withCheckedContinuation { continuation in
            muxContinuation = continuation
        }
        observedCancellation = Task.isCancelled
        if throwsGenericErrorAfterCancellation {
            try Data("partial".utf8).write(to: outputURL)
            throw DownloadServiceTestError.cancelled
        }
        try Task.checkCancellation()
        try Data("muxed".utf8).write(to: outputURL)
    }

    func releaseMux() {
        muxContinuation?.resume()
        muxContinuation = nil
    }
}

private actor RecordingBilibiliDownloader: BilibiliDownloading {
    private let pausesFirstDownload: Bool
    private let throwsGenericErrorAfterCancellation: Bool
    private(set) var requestedURL: String?
    private(set) var invocationCount = 0
    private(set) var observedCancellation = false
    private var firstDownloadContinuation: CheckedContinuation<Void, Never>?

    init(
        pausesFirstDownload: Bool = false,
        throwsGenericErrorAfterCancellation: Bool = false
    ) {
        self.pausesFirstDownload = pausesFirstDownload
        self.throwsGenericErrorAfterCancellation = throwsGenericErrorAfterCancellation
    }

    func downloadComponents(from urlString: String, to directory: URL) async throws
        -> [DownloadedMediaComponent]
    {
        invocationCount += 1
        if pausesFirstDownload, invocationCount == 1 {
            await withCheckedContinuation { continuation in
                firstDownloadContinuation = continuation
            }
            observedCancellation = Task.isCancelled
            if throwsGenericErrorAfterCancellation {
                throw DownloadServiceTestError.cancelled
            }
            try Task.checkCancellation()
        }
        requestedURL = urlString
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let video = directory.appendingPathComponent("fallback [BV1d2N16KEh6].32.mp4")
        let audio = directory.appendingPathComponent("fallback [BV1d2N16KEh6].30280.m4a")
        try Data("video".utf8).write(to: video)
        try Data("audio".utf8).write(to: audio)
        return [
            DownloadedMediaComponent(fileURL: video, formatID: "32", kind: .video),
            DownloadedMediaComponent(fileURL: audio, formatID: "30280", kind: .audio),
        ]
    }

    func releaseFirstDownload() {
        firstDownloadContinuation?.resume()
        firstDownloadContinuation = nil
    }
}

private enum DownloadServiceTestError: Error, Sendable {
    case cancelled
}

private actor StubBilibiliHTTPClient: BilibiliHTTPClient {
    private let directory: URL
    private(set) var requestedMediaURLs: [URL] = []

    init(directory: URL) {
        self.directory = directory
    }

    func data(for request: URLRequest) async throws -> BilibiliHTTPDataResponse {
        let data: Data
        if request.url?.path == "/x/web-interface/view" {
            data = Data(#"{"code":0,"message":"OK","data":{"title":"A/B Test","cid":123,"bvid":"BV1d2N16KEh6"}}"#.utf8)
        } else {
            data = Data(#"{"code":0,"message":"OK","data":{"dash":{"video":[{"id":32,"baseUrl":"https://cdn.example/hevc.mp4","backupUrl":[],"bandwidth":3000,"codecs":"hvc1.1.6","mimeType":"video/mp4","width":852,"height":480},{"id":32,"baseUrl":"https://cdn.example/avc.mp4","backupUrl":[],"bandwidth":2000,"codecs":"avc1.64001F","mimeType":"video/mp4","width":852,"height":480}],"audio":[{"id":30216,"baseUrl":"https://cdn.example/audio-low.m4a","backupUrl":[],"bandwidth":64000,"codecs":"mp4a.40.2","mimeType":"audio/mp4"},{"id":30280,"baseUrl":"https://cdn.example/audio-high.m4a","backupUrl":[],"bandwidth":192000,"codecs":"mp4a.40.2","mimeType":"audio/mp4"}]}}}"#.utf8)
        }
        return BilibiliHTTPDataResponse(data: data, statusCode: 200)
    }

    func download(for request: URLRequest, to destinationURL: URL) async throws
        -> BilibiliHTTPResponse
    {
        let url = try #require(request.url)
        requestedMediaURLs.append(url)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(url.absoluteString.utf8).write(to: destinationURL)
        return BilibiliHTTPResponse(statusCode: 200)
    }
}

@MainActor
private final class CountingClipboardSource: ClipboardStringReading {
    var changeCount: Int
    var value: String?
    private(set) var stringReadCount = 0

    init(changeCount: Int, value: String?) {
        self.changeCount = changeCount
        self.value = value
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        stringReadCount += 1
        return value
    }
}

private func kitTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ZislaKitTests-\(UUID().uuidString)", isDirectory: true)
}

private func writeExecutable(
    _ contents: String,
    to url: URL,
    permissions: Int = 0o755
) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: url)
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: permissions)],
        ofItemAtPath: url.path
    )
}

private func shellSingleQuoted(_ string: String) -> String {
    "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func jsonEscaped(_ string: String) -> String {
    string.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
