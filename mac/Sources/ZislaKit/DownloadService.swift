import Foundation
import ZislaCore

public struct DownloadResult: Equatable, Sendable {
    public let taskID: UUID
    public let fileURL: URL

    public init(taskID: UUID, fileURL: URL) {
        self.taskID = taskID
        self.fileURL = fileURL
    }
}

public enum DownloadServiceError: Error, Equatable, Sendable {
    case duplicateTask(UUID)
    case cannotPrepareDirectory(String)
    case launchFailed(String)
    case processFailed(exitCode: Int32, diagnostic: String)
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
        bilibiliDownloader: any BilibiliDownloading = BilibiliDirectDownloader()
    ) {
        self.resolver = resolver
        self.temporaryRootDirectory = temporaryRootDirectory.standardizedFileURL
        self.mediaMuxer = mediaMuxer
        self.bilibiliDownloader = bilibiliDownloader
    }

    public func setNetworkProxyURL(_ value: String) {
        setNetworkProxy(url: value, enabled: true)
    }

    public func setNetworkProxy(url: String, enabled: Bool) {
        networkProxyURL = url
        networkProxyEnabled = enabled
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
            if request.mode == .video,
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

    init(_ process: Process) {
        self.process = process
    }

    func waitUntilExit() -> Int32 {
        process.waitUntilExit()
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

    init(onEvent: @escaping @Sendable (YTDLPEvent) async -> Void) {
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
