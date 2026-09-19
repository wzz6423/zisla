import Foundation
import ZislaCore

public struct DownloadResult: Equatable, Sendable {
    public let taskID: UUID
    public let fileURL: URL
    public let browserCookieSource: DownloadBrowserCookieSource?

    public init(
        taskID: UUID,
        fileURL: URL,
        browserCookieSource: DownloadBrowserCookieSource? = nil
    ) {
        self.taskID = taskID
        self.fileURL = fileURL
        self.browserCookieSource = browserCookieSource
    }
}

public enum DownloadServiceError: Error, Equatable, Sendable {
    case duplicateTask(UUID)
    case cannotPrepareDirectory(String)
    case launchFailed(String)
    case processFailed(exitCode: Int32, diagnostic: String)
    case browserCookieAccessDenied
    case formatSelectionRequiresFFmpeg
    case invalidFormatProbeResponse
    case missingCompletedFile
    case unsafeCompletedFile(String)
    case completedFileDoesNotExist(String)
}

enum DownloadProcessEnvironment {
    static func sanitized(_ environment: [String: String], proxyURL: String = "", proxyEnabled: Bool = true) -> [String: String] {
        let sanitized = environment.filter { key, _ in
            !key.hasPrefix("DYLD_") && !key.hasPrefix("PYTHON")
        }
        return NetworkProxy.environment(from: proxyURL, enabled: proxyEnabled, base: sanitized)
    }
}

public actor DownloadService {
    private let resolver: YTDLPResolver
    private let temporaryRootDirectory: URL
    private let mediaMuxer: any MediaMuxing
    private let bilibiliDownloader: any BilibiliDownloading
    private let browserCookieSourceProvider: @Sendable () -> [DownloadBrowserCookieSource]
    private let browserCookieDirectoryAccess: @Sendable (URL) throws -> Void
    private var activeTaskIDs: Set<UUID> = []
    private var activeProcesses: [UUID: ProcessBox] = [:]
    private var activeNativeDownloadTasks: [UUID: Task<[DownloadedMediaComponent], Error>] = [:]
    private var activeNativeMuxTasks: [UUID: Task<Void, Error>] = [:]
    private var explicitlyCancelledTasks: Set<UUID> = []
    private var reservedOutputURLs: Set<URL> = []
    private var networkProxyURL = ""
    private var networkProxyEnabled = false

    public init(
        resolver: YTDLPResolver = YTDLPResolver(),
        temporaryRootDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla/Downloads", isDirectory: true),
        mediaMuxer: any MediaMuxing = NativeMediaMuxer(),
        bilibiliDownloader: any BilibiliDownloading = BilibiliDirectDownloader(),
        browserCookieSourceProvider: @escaping @Sendable () -> [DownloadBrowserCookieSource] = {
            DownloadBrowserCookieDetector().detect()
        },
        browserCookieDirectoryAccess: @escaping @Sendable (URL) throws -> Void = {
            _ = try FileManager.default.contentsOfDirectory(atPath: $0.path)
        }
    ) {
        self.resolver = resolver
        self.temporaryRootDirectory = temporaryRootDirectory.standardizedFileURL
        self.mediaMuxer = mediaMuxer
        self.bilibiliDownloader = bilibiliDownloader
        self.browserCookieSourceProvider = browserCookieSourceProvider
        self.browserCookieDirectoryAccess = browserCookieDirectoryAccess
    }

    public func availableBrowserCookieSources() -> [DownloadBrowserCookieSource] {
        browserCookieSourceProvider()
    }

    public func setNetworkProxyURL(_ value: String) {
        setNetworkProxy(url: value, enabled: true)
    }

    public func setNetworkProxy(url: String, enabled: Bool) {
        networkProxyURL = url
        networkProxyEnabled = enabled
    }

    public func probeFormats(
        urlString: String,
        browserCookieSource: DownloadBrowserCookieSource? = nil
    ) async throws -> DownloadFormatProbeResult {
        guard let url = HTTPURLParser.url(from: urlString) else {
            throw DownloadRequestError.unsupportedURL
        }

        let tools = try resolver.resolve()
        let probeDirectory = temporaryRootDirectory
            .appendingPathComponent("FormatProbe-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: probeDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw DownloadServiceError.cannotPrepareDirectory(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: probeDirectory) }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = tools.ytDLPURL
        process.arguments = DownloadFormatProbe.arguments(
            urlString: url.absoluteString,
            browserCookieSource: browserCookieSource
        )
        process.environment = DownloadProcessEnvironment.sanitized(
            ProcessInfo.processInfo.environment,
            proxyURL: networkProxyURL,
            proxyEnabled: networkProxyEnabled
        )
        process.currentDirectoryURL = probeDirectory
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let processBox = ProcessBox(process)
        do {
            try Task.checkCancellation()
            try process.run()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DownloadServiceError.launchFailed(error.localizedDescription)
        }

        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        let collector = DownloadEventCollector()
        async let stdout = Self.readProbeOutput(FileHandleBox(stdoutPipe.fileHandleForReading))
        async let stderr = Self.drain(
            FileHandleBox(stderrPipe.fileHandleForReading),
            collector: collector
        )

        let exitCode = await withTaskCancellationHandler {
            await Self.waitForExit(processBox)
        } onCancel: {
            processBox.terminate()
        }
        let output = await stdout
        let diagnostic = await stderr

        try Task.checkCancellation()
        guard exitCode == 0 else {
            if browserCookieAccessIsDenied(browserCookieSource, diagnostic: diagnostic) {
                throw DownloadServiceError.browserCookieAccessDenied
            }
            throw DownloadServiceError.processFailed(
                exitCode: exitCode,
                diagnostic: DownloadFailureDiagnostics.actionableMessage(
                    rawDiagnostic: diagnostic,
                    urlString: url.absoluteString
                )
            )
        }
        guard !output.isTruncated,
              let result = try? DownloadFormatProbe.result(from: output.string) else {
            throw DownloadServiceError.invalidFormatProbeResponse
        }
        return DownloadFormatProbeResult(
            title: result.title,
            formats: result.formats,
            canSelectFormats: tools.capabilities.hasFFmpeg,
            browserCookieSource: browserCookieSource
        )
    }

    public func probeFormatsAutomatically(
        urlString: String,
        browserCookieSource: DownloadBrowserCookieSource? = nil
    ) async throws -> DownloadFormatProbeResult {
        do {
            return try await probeFormats(
                urlString: urlString,
                browserCookieSource: browserCookieSource
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard browserCookieSource == nil,
                  Self.requiresBrowserCookieDetection(error, urlString: urlString),
                  let result = try await probeFormatsUsingAvailableBrowserCookies(urlString: urlString)
            else {
                throw error
            }
            return result
        }
    }

    public func download(
        _ request: DownloadRequest,
        taskID: UUID = UUID(),
        onEvent: @escaping @Sendable (YTDLPEvent) async -> Void = { _ in }
    ) async throws -> DownloadResult {
        guard activeTaskIDs.insert(taskID).inserted else {
            throw DownloadServiceError.duplicateTask(taskID)
        }
        defer {
            if let downloadTask = activeNativeDownloadTasks.removeValue(forKey: taskID) {
                downloadTask.cancel()
            }
            if let muxTask = activeNativeMuxTasks.removeValue(forKey: taskID) {
                muxTask.cancel()
            }
            activeProcesses.removeValue(forKey: taskID)
            explicitlyCancelledTasks.remove(taskID)
            activeTaskIDs.remove(taskID)
        }

        let fileManager = FileManager.default
        let taskTemporaryDirectory = temporaryRootDirectory
            .appendingPathComponent(taskID.uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: request.outputDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: taskTemporaryDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw DownloadServiceError.cannotPrepareDirectory(error.localizedDescription)
        }
        defer { try? fileManager.removeItem(at: taskTemporaryDirectory) }

        if request.mode == .video,
           request.formatSelection == nil,
           DownloadFailureDiagnostics.isBilibiliURL(request.urlString) {
            return try await downloadBilibiliVideo(
                request,
                taskID: taskID,
                taskTemporaryDirectory: taskTemporaryDirectory
            )
        }

        let tools: YTDLPTools
        do {
            tools = try resolver.resolve()
        } catch let resolverError {
            guard request.mode == .video,
                  request.formatSelection == nil,
                  DownloadFailureDiagnostics.isBilibiliURL(request.urlString)
            else {
                throw resolverError
            }
            do {
                return try await downloadBilibiliVideo(
                    request,
                    taskID: taskID,
                    taskTemporaryDirectory: taskTemporaryDirectory
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw DownloadServiceError.processFailed(
                    exitCode: 0,
                    diagnostic: AppLocalization.text("%@\n原生备用下载失败：%@", Self.resolverDiagnostic(resolverError), error.localizedDescription)
                )
            }
        }
        let strategy = YTDLPArgumentBuilder.strategy(
            for: request,
            capabilities: tools.capabilities
        )
        if request.formatSelection != nil, !tools.capabilities.hasFFmpeg {
            throw DownloadServiceError.formatSelectionRequiresFFmpeg
        }
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = tools.ytDLPURL
        process.arguments = YTDLPArgumentBuilder.arguments(
            for: request,
            capabilities: tools.capabilities,
            taskTemporaryDirectory: taskTemporaryDirectory,
            ffmpegExecutableURL: tools.ffmpegURL
        )
        process.environment = DownloadProcessEnvironment.sanitized(
            ProcessInfo.processInfo.environment,
            proxyURL: networkProxyURL,
            proxyEnabled: networkProxyEnabled
        )
        process.currentDirectoryURL = taskTemporaryDirectory
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let processBox = ProcessBox(process)
        activeProcesses[taskID] = processBox

        do {
            try Task.checkCancellation()
            try process.run()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DownloadServiceError.launchFailed(error.localizedDescription)
        }

        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        let collector = DownloadEventCollector(onEvent: onEvent)
        async let stdoutDiagnostic = Self.drain(
            FileHandleBox(stdoutPipe.fileHandleForReading),
            collector: collector
        )
        async let stderrDiagnostic = Self.drain(
            FileHandleBox(stderrPipe.fileHandleForReading),
            collector: collector
        )

        let exitCode = await withTaskCancellationHandler {
            await Self.waitForExit(processBox)
        } onCancel: {
            processBox.terminate()
        }
        let diagnostics = await (stdoutDiagnostic, stderrDiagnostic)

        try throwIfCancelled(taskID: taskID)
        guard exitCode == 0 else {
            let diagnostic = Self.combinedDiagnostic(
                stdout: diagnostics.0,
                stderr: diagnostics.1
            )
            if browserCookieAccessIsDenied(request.browserCookieSource, diagnostic: diagnostic) {
                throw DownloadServiceError.browserCookieAccessDenied
            }
            if request.mode == .video,
               request.formatSelection == nil,
               DownloadFailureDiagnostics.shouldUseBilibiliNativeFallback(
                   rawDiagnostic: diagnostic,
                   urlString: request.urlString
               ) {
                do {
                    return try await downloadBilibiliVideo(
                        request,
                        taskID: taskID,
                        taskTemporaryDirectory: taskTemporaryDirectory
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let actionable = DownloadFailureDiagnostics.actionableMessage(
                        rawDiagnostic: diagnostic,
                        urlString: request.urlString
                    )
                    throw DownloadServiceError.processFailed(
                        exitCode: exitCode,
                        diagnostic: AppLocalization.text("%@\n原生备用下载失败：%@", actionable, error.localizedDescription)
                    )
                }
            }
            throw DownloadServiceError.processFailed(
                exitCode: exitCode,
                diagnostic: DownloadFailureDiagnostics.actionableMessage(
                    rawDiagnostic: diagnostic,
                    urlString: request.urlString
                )
            )
        }

        switch strategy {
        case .direct:
            guard let reportedFile = await collector.completedFile else {
                throw DownloadServiceError.missingCompletedFile
            }
            return try validatedResult(
                taskID: taskID,
                reportedFile: reportedFile,
                outputDirectory: request.outputDirectory
            )
        case .nativePackaging:
            return try await finalizeNativePackaging(
                taskID: taskID,
                components: await collector.components,
                taskTemporaryDirectory: taskTemporaryDirectory,
                outputDirectory: request.outputDirectory
            )
        }
    }

    public func downloadAutomatically(
        _ request: DownloadRequest,
        taskID: UUID = UUID(),
        onEvent: @escaping @Sendable (YTDLPEvent) async -> Void = { _ in }
    ) async throws -> DownloadResult {
        do {
            return try await download(request, taskID: taskID, onEvent: onEvent)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard request.browserCookieSource == nil,
                  Self.requiresBrowserCookieDetection(error, urlString: request.urlString),
                  let probeResult = try await probeFormatsUsingAvailableBrowserCookies(
                    urlString: request.urlString
                  ),
                  let browserCookieSource = probeResult.browserCookieSource
            else {
                throw error
            }
            let retryRequest = try DownloadRequest(
                urlString: request.urlString,
                mode: request.mode,
                outputDirectory: request.outputDirectory,
                formatSelection: request.formatSelection,
                browserCookieSource: browserCookieSource
            )
            let result = try await download(retryRequest, taskID: taskID, onEvent: onEvent)
            return DownloadResult(
                taskID: result.taskID,
                fileURL: result.fileURL,
                browserCookieSource: browserCookieSource
            )
        }
    }

    private func downloadBilibiliVideo(
        _ request: DownloadRequest,
        taskID: UUID,
        taskTemporaryDirectory: URL
    ) async throws -> DownloadResult {
        try throwIfCancelled(taskID: taskID)
        let downloader = bilibiliDownloader
        let nativeDownloadTask: Task<[DownloadedMediaComponent], Error> = Task {
            try await downloader.downloadComponents(
                from: request.urlString,
                to: taskTemporaryDirectory
            )
        }
        activeNativeDownloadTasks[taskID] = nativeDownloadTask
        defer {
            nativeDownloadTask.cancel()
            activeNativeDownloadTasks[taskID] = nil
        }

        let components: [DownloadedMediaComponent]
        do {
            components = try await withTaskCancellationHandler {
                try await nativeDownloadTask.value
            } onCancel: {
                nativeDownloadTask.cancel()
            }
        } catch {
            if isCancelled(taskID: taskID) || error is CancellationError {
                throw CancellationError()
            }
            throw error
        }
        try throwIfCancelled(taskID: taskID)

        return try await finalizeNativePackaging(
            taskID: taskID,
            components: components,
            taskTemporaryDirectory: taskTemporaryDirectory,
            outputDirectory: request.outputDirectory
        )
    }

    private func probeFormatsUsingAvailableBrowserCookies(
        urlString: String
    ) async throws -> DownloadFormatProbeResult? {
        var cookieAccessWasDenied = false
        var attemptedSourceIDs = Set<String>()
        for source in browserCookieSourceProvider() where attemptedSourceIDs.insert(source.id).inserted {
            do {
                return try await probeFormats(
                    urlString: urlString,
                    browserCookieSource: source
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch DownloadServiceError.browserCookieAccessDenied {
                cookieAccessWasDenied = true
            } catch {
                guard Self.canTryAnotherBrowserCookieSource(error, urlString: urlString) else {
                    throw error
                }
            }
        }
        if cookieAccessWasDenied {
            throw DownloadServiceError.browserCookieAccessDenied
        }
        return nil
    }

    private func browserCookieAccessIsDenied(
        _ source: DownloadBrowserCookieSource?,
        diagnostic: String
    ) -> Bool {
        guard let source else { return false }
        if DownloadFailureDiagnostics.isBrowserCookiePermissionDenied(diagnostic) {
            return true
        }
        guard DownloadFailureDiagnostics.shouldRetryWithoutBrowserCookies(
            rawDiagnostic: diagnostic,
            browserCookieSource: source
        ) else { return false }

        let directory = source.cookieDirectory
            ?? Self.defaultBrowserCookieDirectory(for: source.ytDLPBrowser)
        guard let directory else { return false }
        // yt-dlp's directory walk hides macOS privacy errors as missing cookie databases.
        do {
            try browserCookieDirectoryAccess(directory)
        } catch {
            let error = error as NSError
            let cause = error.userInfo[NSUnderlyingErrorKey] as? NSError ?? error
            return cause.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(cause.code)
        }
        return false
    }

    private static func defaultBrowserCookieDirectory(
        for browser: String
    ) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch browser {
        case "safari":
            return home.appendingPathComponent("Library/Cookies", isDirectory: true)
        case "firefox":
            return home.appendingPathComponent(
                "Library/Application Support/Firefox/Profiles",
                isDirectory: true
            )
        case "brave":
            return home.appendingPathComponent(
                "Library/Application Support/BraveSoftware/Brave-Browser",
                isDirectory: true
            )
        case "chrome":
            return home.appendingPathComponent(
                "Library/Application Support/Google/Chrome",
                isDirectory: true
            )
        case "chromium":
            return home.appendingPathComponent(
                "Library/Application Support/Chromium",
                isDirectory: true
            )
        case "edge":
            return home.appendingPathComponent(
                "Library/Application Support/Microsoft Edge",
                isDirectory: true
            )
        case "opera":
            return home.appendingPathComponent(
                "Library/Application Support/com.operasoftware.Opera",
                isDirectory: true
            )
        case "vivaldi":
            return home.appendingPathComponent(
                "Library/Application Support/Vivaldi",
                isDirectory: true
            )
        case "whale":
            return home.appendingPathComponent(
                "Library/Application Support/Naver/Whale",
                isDirectory: true
            )
        default:
            return nil
        }
    }

    private static func requiresBrowserCookieDetection(
        _ error: Error,
        urlString: String
    ) -> Bool {
        guard let error = error as? DownloadServiceError,
              case let .processFailed(_, diagnostic) = error else {
            return false
        }
        return DownloadFailureDiagnostics.requiresBrowserCookies(
            rawDiagnostic: diagnostic,
            urlString: urlString
        )
    }

    private static func canTryAnotherBrowserCookieSource(
        _ error: Error,
        urlString: String
    ) -> Bool {
        guard let error = error as? DownloadServiceError,
              case let .processFailed(_, diagnostic) = error else {
            return false
        }
        return DownloadFailureDiagnostics.canTryAnotherBrowserCookieSource(
            rawDiagnostic: diagnostic,
            urlString: urlString
        )
    }

    private func finalizeNativePackaging(
        taskID: UUID,
        components: [DownloadedMediaComponent],
        taskTemporaryDirectory: URL,
        outputDirectory: URL
    ) async throws -> DownloadResult {
        try throwIfCancelled(taskID: taskID)

        let validatedComponents = try components.map {
            try validatedComponent($0, within: taskTemporaryDirectory)
        }

        if let combined = validatedComponents.last(where: { $0.kind == .combined }) {
            let desiredURL = DownloadOutputPathBuilder.destinationURL(
                for: combined,
                outputDirectory: outputDirectory
            )
            let destinationURL = availableOutputURL(for: desiredURL)
            reservedOutputURLs.insert(destinationURL)
            defer { reservedOutputURLs.remove(destinationURL) }

            try throwIfCancelled(taskID: taskID)

            do {
                try FileManager.default.moveItem(at: combined.fileURL, to: destinationURL)
            } catch {
                throw DownloadServiceError.cannotPrepareDirectory(error.localizedDescription)
            }
            return try validatedResult(
                taskID: taskID,
                reportedFile: destinationURL,
                outputDirectory: outputDirectory
            )
        }

        guard let video = validatedComponents.last(where: { $0.kind == .video }),
              let audio = validatedComponents.last(where: { $0.kind == .audio })
        else {
            throw DownloadServiceError.missingCompletedFile
        }
        let desiredURL = DownloadOutputPathBuilder.destinationURL(
            for: video,
            outputDirectory: outputDirectory,
            fileExtension: "mp4"
        )
        let destinationURL = availableOutputURL(for: desiredURL)
        reservedOutputURLs.insert(destinationURL)
        defer { reservedOutputURLs.remove(destinationURL) }

        try throwIfCancelled(taskID: taskID)
        let muxer = mediaMuxer
        let nativeMuxTask: Task<Void, Error> = Task {
            try await muxer.mux(
                videoURL: video.fileURL,
                audioURL: audio.fileURL,
                outputURL: destinationURL
            )
        }
        activeNativeMuxTasks[taskID] = nativeMuxTask
        defer {
            nativeMuxTask.cancel()
            activeNativeMuxTasks[taskID] = nil
        }

        do {
            try await withTaskCancellationHandler {
                try await nativeMuxTask.value
            } onCancel: {
                nativeMuxTask.cancel()
            }
            try throwIfCancelled(taskID: taskID)
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            if isCancelled(taskID: taskID) || error is CancellationError {
                throw CancellationError()
            }
            throw DownloadServiceError.processFailed(
                exitCode: 0,
                diagnostic: AppLocalization.text("系统原生媒体封装失败：%@", error.localizedDescription)
            )
        }
        return try validatedResult(
            taskID: taskID,
            reportedFile: destinationURL,
            outputDirectory: outputDirectory
        )
    }

    private func validatedComponent(
        _ component: DownloadedMediaComponent,
        within directory: URL
    ) throws -> DownloadedMediaComponent {
        guard let normalizedURL = DownloadOutputPathValidator.normalizedFileURL(
            component.fileURL,
            within: directory
        ) else {
            throw DownloadServiceError.unsafeCompletedFile(component.fileURL.path)
        }
        try ensureExistingFile(normalizedURL)
        return DownloadedMediaComponent(
            fileURL: normalizedURL,
            formatID: component.formatID,
            kind: component.kind
        )
    }

    private func validatedResult(
        taskID: UUID,
        reportedFile: URL,
        outputDirectory: URL
    ) throws -> DownloadResult {
        guard let normalizedFile = DownloadOutputPathValidator.normalizedFileURL(
            reportedFile,
            within: outputDirectory
        ) else {
            throw DownloadServiceError.unsafeCompletedFile(reportedFile.path)
        }
        try ensureExistingFile(normalizedFile)
        return DownloadResult(taskID: taskID, fileURL: normalizedFile)
    }

    private func ensureExistingFile(_ fileURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw DownloadServiceError.completedFileDoesNotExist(fileURL.path)
        }
    }

    private func availableOutputURL(for desiredURL: URL) -> URL {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: desiredURL.path),
              !reservedOutputURLs.contains(desiredURL)
        else {
            let directory = desiredURL.deletingLastPathComponent()
            let fileExtension = desiredURL.pathExtension
            let stem = desiredURL.deletingPathExtension().lastPathComponent
            for index in 1...9_999 {
                let candidate = directory
                    .appendingPathComponent("\(stem) (\(index))")
                    .appendingPathExtension(fileExtension)
                    .standardizedFileURL
                if !fileManager.fileExists(atPath: candidate.path),
                   !reservedOutputURLs.contains(candidate) {
                    return candidate
                }
            }
            return directory
                .appendingPathComponent("\(stem) \(UUID().uuidString)")
                .appendingPathExtension(fileExtension)
                .standardizedFileURL
        }
        return desiredURL
    }

    public func cancel(taskID: UUID) {
        guard activeTaskIDs.contains(taskID) else { return }
        explicitlyCancelledTasks.insert(taskID)
        activeProcesses[taskID]?.terminate()
        activeNativeDownloadTasks[taskID]?.cancel()
        activeNativeMuxTasks[taskID]?.cancel()
    }

    public func cancelAll() {
        for taskID in activeTaskIDs {
            explicitlyCancelledTasks.insert(taskID)
            activeProcesses[taskID]?.terminate()
            activeNativeDownloadTasks[taskID]?.cancel()
            activeNativeMuxTasks[taskID]?.cancel()
        }
    }

    private func isCancelled(taskID: UUID) -> Bool {
        Task.isCancelled || explicitlyCancelledTasks.contains(taskID)
    }

    private func throwIfCancelled(taskID: UUID) throws {
        guard !isCancelled(taskID: taskID) else {
            throw CancellationError()
        }
    }

    private nonisolated static func waitForExit(_ process: ProcessBox) async -> Int32 {
        await Task.detached(priority: .utility) {
            process.waitUntilExit()
        }.value
    }

    private nonisolated static func drain(
        _ fileHandle: FileHandleBox,
        collector: DownloadEventCollector
    ) async -> String {
        await Task.detached(priority: .utility) {
            var pending = Data()
            var diagnostic = BoundedData(limit: 128 * 1_024)
            do {
                while let chunk = try fileHandle.read(upToCount: 32 * 1_024), !chunk.isEmpty {
                    diagnostic.append(chunk)
                    pending.append(chunk)
                    while let newline = pending.firstIndex(of: 0x0A) {
                        let lineData = pending[..<newline]
                        pending.removeSubrange(...newline)
                        let line = String(decoding: lineData, as: UTF8.self)
                        if let event = YTDLPOutputParser.parse(line) {
                            await collector.accept(event)
                        }
                    }
                }
                if !pending.isEmpty,
                   let event = YTDLPOutputParser.parse(String(decoding: pending, as: UTF8.self)) {
                    await collector.accept(event)
                }
            } catch {
                diagnostic.append(Data("\n\(error.localizedDescription)".utf8))
            }
            return diagnostic.string
        }.value
    }

    private nonisolated static func readProbeOutput(
        _ fileHandle: FileHandleBox
    ) async -> BoundedProcessOutput {
        await Task.detached(priority: .utility) {
            let limit = 4 * 1_024 * 1_024
            var data = Data()
            var isTruncated = false
            do {
                while let chunk = try fileHandle.read(upToCount: 32 * 1_024), !chunk.isEmpty {
                    let remaining = limit - data.count
                    if remaining > 0 {
                        data.append(chunk.prefix(remaining))
                    }
                    if chunk.count > remaining {
                        isTruncated = true
                    }
                }
            } catch {
                data.append(Data("\n\(error.localizedDescription)".utf8))
                isTruncated = true
            }
            return BoundedProcessOutput(
                string: String(decoding: data, as: UTF8.self),
                isTruncated: isTruncated
            )
        }.value
    }

    private nonisolated static func combinedDiagnostic(stdout: String, stderr: String) -> String {
        [stderr, stdout]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private nonisolated static func resolverDiagnostic(_ error: Error) -> String {
        guard case YTDLPResolverError.executableNotFound = error else {
            return error.localizedDescription
        }
        return AppLocalization.text("下载工具不可用")
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private let exitSignal = DispatchSemaphore(value: 0)

    init(_ process: Process) {
        self.process = process
        // Register before launch so fast cookie probes cannot lose their exit notification.
        process.terminationHandler = { [exitSignal] _ in
            exitSignal.signal()
        }
    }

    func waitUntilExit() -> Int32 {
        exitSignal.wait()
        return process.terminationStatus
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        if process.isRunning {
            process.terminate()
        }
    }
}

private final class FileHandleBox: @unchecked Sendable {
    private let fileHandle: FileHandle

    init(_ fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func read(upToCount count: Int) throws -> Data? {
        try fileHandle.read(upToCount: count)
    }
}

private actor DownloadEventCollector {
    private let onEvent: @Sendable (YTDLPEvent) async -> Void
    private(set) var completedFile: URL?
    private(set) var components: [DownloadedMediaComponent] = []

    init(onEvent: @escaping @Sendable (YTDLPEvent) async -> Void = { _ in }) {
        self.onEvent = onEvent
    }

    func accept(_ event: YTDLPEvent) async {
        if case let .completedFile(url) = event {
            completedFile = url
        }
        if case let .completedComponent(component) = event {
            components.append(component)
        }
        await onEvent(event)
    }
}

private struct BoundedProcessOutput: Sendable {
    let string: String
    let isTruncated: Bool
}

private struct BoundedData {
    let limit: Int
    private var data = Data()

    init(limit: Int) {
        self.limit = limit
    }

    mutating func append(_ newData: Data) {
        data.append(newData)
        if data.count > limit {
            data.removeFirst(data.count - limit)
        }
    }

    var string: String {
        String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
