import AppKit
import Combine
import Darwin
import Foundation
import ZislaCore
import ZislaKit

struct ImageToolsRecognitionResult: Identifiable, Equatable, Sendable {
    let inputURL: URL
    let text: String
    let table: ScreenshotRecognizedTable
    var id: URL { inputURL }
}

struct ImageToolsRecognitionFailure: Equatable, Sendable {
    let inputURL: URL
    let message: String
}

enum ImageToolsRecognitionError: LocalizedError {
    case noText

    var errorDescription: String? { AppLocalization.text("未识别到文字") }
}

@MainActor
final class ImageToolsRecognitionModel: ObservableObject {
    @Published private(set) var results: [ImageToolsRecognitionResult] = []
    @Published private(set) var failures: [ImageToolsRecognitionFailure] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var currentInputURL: URL?
    @Published private(set) var message: String?
    private var inputURLs: [URL] = []
    private var operation: ScreenshotRecognitionOperation?
    private var task: Task<Void, Never>?

    isolated deinit {
        task?.cancel()
    }

    @discardableResult
    func start(
        urls: [URL],
        service: ImageProcessingService,
        loadImage: (@Sendable (URL) async throws -> CGImage)? = nil,
        beforePublish: (@Sendable (URL) async -> Void)? = nil,
        recognizeImage: @escaping @Sendable (CGImage, ScreenshotRecognitionOperation) async throws -> [ScreenshotRecognizedFragment] = {
            try await ScreenshotRecognitionWarmUp.shared.recognize($0, operation: $1)
        }
    ) -> Task<Void, Never>? {
        guard !isProcessing else { return nil }
        clear()
        guard !urls.isEmpty else {
            message = ImageProcessingError.emptyInput.localizedDescription
            return nil
        }
        let operation = ScreenshotRecognitionOperation()
        self.operation = operation
        inputURLs = urls
        isProcessing = true
        total = urls.count
        let loadImage = loadImage ?? { try await service.loadRasterImage($0) }
        let task = Task { [weak self] in
            do {
                let work = Task.detached(priority: .userInitiated) { [weak self] () async throws -> Void in
                    for (index, url) in urls.enumerated() {
                        try operation.checkCancellation()
                        await MainActor.run { [weak self] in
                            guard let self, self.operation === operation else { return }
                            self.currentInputURL = url
                        }
                        try operation.checkCancellation()
                        let result: Result<ImageToolsRecognitionResult, any Error>
                        do {
                            let image = try await loadImage(url)
                            try operation.checkCancellation()
                            let fragments = try await recognizeImage(image, operation)
                            let text = ScreenshotRecognitionFormatter.plainText(from: fragments)
                            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                throw ImageToolsRecognitionError.noText
                            }
                            let table = ScreenshotRecognitionFormatter.table(from: fragments, image: image)
                            try operation.checkCancellation()
                            result = .success(ImageToolsRecognitionResult(inputURL: url, text: text, table: table))
                        } catch {
                            try operation.checkCancellation()
                            if error is CancellationError { throw error }
                            result = .failure(error)
                        }
                        if let beforePublish { await beforePublish(url) }
                        await MainActor.run { [weak self] in
                            guard let self, self.operation === operation else { return }
                            switch result {
                            case let .success(item): self.results.append(item)
                            case let .failure(error):
                                self.failures.append(ImageToolsRecognitionFailure(inputURL: url, message: error.localizedDescription))
                            }
                            self.completed = index + 1
                        }
                    }
                }
                try await withTaskCancellationHandler { try await work.value } onCancel: {
                    operation.cancel()
                    work.cancel()
                }
                guard let self, self.operation === operation else { return }
                self.message = AppLocalization.text("已识别 %ld 张图片，失败 %ld 项", self.results.count, self.failures.count)
                self.finish()
            } catch {
                guard let self, self.operation === operation else { return }
                self.message = error is CancellationError ? AppLocalization.text("已取消") : error.localizedDescription
                self.finish()
            }
        }
        self.task = task
        return task
    }

    func cancel() {
        operation = nil
        task?.cancel()
        task = nil
        isProcessing = false
        currentInputURL = nil
        message = AppLocalization.text("已取消")
    }

    func clear() {
        cancel()
        results = []
        failures = []
        inputURLs = []
        completed = 0
        total = 0
        message = nil
    }

    func copyText(
        _ result: ImageToolsRecognitionResult,
        write: @MainActor (String) -> Bool = { ClipboardHistoryPasteboard.write(.text($0)) }
    ) {
        message = write(result.text) ? AppLocalization.text("已复制") : AppLocalization.text("无法写入剪贴板")
    }

    @discardableResult
    func exportText(_ result: ImageToolsRecognitionResult, to destination: URL) -> Task<Void, Never>? {
        startExport([.init(result: result, format: .text, destination: destination)], batch: false)
    }

    @discardableResult
    func exportTable(_ result: ImageToolsRecognitionResult, to destination: URL) -> Task<Void, Never>? {
        startExport([.init(result: result, format: .table, destination: destination)], batch: false)
    }

    @discardableResult
    func exportTexts(to directory: URL) -> Task<Void, Never>? {
        startExport(ImageToolsRecognitionExporter.textDocuments(results, in: directory), batch: true)
    }

    private func startExport(_ documents: [ImageToolsRecognitionDocument], batch: Bool) -> Task<Void, Never>? {
        guard !isProcessing else { return nil }
        let operation = ScreenshotRecognitionOperation()
        self.operation = operation
        isProcessing = true
        total = 0
        currentInputURL = nil
        message = nil
        let inputs = inputURLs
        let task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let work = Task.detached(priority: .userInitiated) {
                    try ImageToolsRecognitionExporter.write(documents, protectedInputs: inputs, checkCancellation: {
                        try operation.checkCancellation()
                    })
                }
                let outputs = try await withTaskCancellationHandler { try await work.value } onCancel: {
                    operation.cancel()
                    work.cancel()
                }
                guard let self, self.operation === operation else { return }
                self.message = batch
                    ? AppLocalization.text("已导出 %ld 份文字", outputs.count)
                    : AppLocalization.text("已保存 %@", outputs[0].lastPathComponent)
                self.finish()
            } catch {
                guard let self, self.operation === operation else { return }
                self.message = error is CancellationError ? AppLocalization.text("已取消") : error.localizedDescription
                self.finish()
            }
        }
        self.task = task
        return task
    }

    private func finish() {
        self.operation = nil
        task = nil
        isProcessing = false
        currentInputURL = nil
    }
}

struct ImageToolsRecognitionDocument: Sendable {
    enum Format: Sendable {
        case text
        case table
    }

    let result: ImageToolsRecognitionResult
    let format: Format
    let destination: URL
}

enum ImageToolsRecognitionExporter {
    static func textDocuments(_ results: [ImageToolsRecognitionResult], in directory: URL) -> [ImageToolsRecognitionDocument] {
        var names = Set<String>()
        return results.map { result in
            let base = result.inputURL.deletingPathExtension().lastPathComponent + "-ocr"
            var name = base + ".txt"
            var suffix = 2
            while !names.insert(name.lowercased()).inserted {
                name = "\(base)-\(suffix).txt"
                suffix += 1
            }
            return ImageToolsRecognitionDocument(result: result, format: .text, destination: directory.appendingPathComponent(name))
        }
    }

    static func write(
        _ documents: [ImageToolsRecognitionDocument],
        protectedInputs: [URL] = [],
        stagingParent: URL = FileManager.default.temporaryDirectory,
        checkCancellation: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> [URL] {
        try checkCancellation()
        guard !documents.isEmpty else { throw ImageProcessingError.emptyInput }
        let protectedPaths = Set((protectedInputs + documents.map(\.result.inputURL)).map {
            $0.standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
        })
        var directories: [String: Int32] = [:]
        defer { directories.values.forEach { _ = Darwin.close($0) } }
        var paths = Set<String>()
        for document in documents {
            try checkCancellation()
            let url = document.destination
            guard url.isFileURL, !url.path(percentEncoded: false).contains("\0") else {
                throw ImageProcessingError.invalidInput(url)
            }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
            guard !protectedPaths.contains(path), paths.insert(path).inserted else {
                throw ImageProcessingError.outputAlreadyExists(url)
            }
            let parent = url.deletingLastPathComponent().path
            if directories[parent] == nil {
                let descriptor = Darwin.open(parent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                directories[parent] = descriptor
            }
            var metadata = stat()
            if fstatat(directories[parent]!, url.lastPathComponent, &metadata, AT_SYMLINK_NOFOLLOW) == 0 {
                throw ImageProcessingError.outputAlreadyExists(url)
            }
            guard errno == ENOENT else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            switch document.format {
            case .text:
                guard !document.result.text.isEmpty else { throw ImageToolsRecognitionError.noText }
            case .table:
                guard !document.result.table.isEmpty else { throw ImageToolsRecognitionError.noText }
            }
        }
        let manager = FileManager.default
        let temporary = stagingParent.appendingPathComponent("zisla-image-ocr-export-\(UUID())", isDirectory: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: temporary) }
        var staged: [URL] = []
        for (index, document) in documents.enumerated() {
            try checkCancellation()
            let url = temporary.appendingPathComponent(String(index))
            switch document.format {
            case .text: try Data(document.result.text.utf8).write(to: url, options: .withoutOverwriting)
            case .table: try ScreenshotXLSXExporter.write(document.result.table, to: url, checkCancellation: checkCancellation)
            }
            staged.append(url)
        }

        struct CreatedFile {
            let directory: Int32
            let name: String
            let device: dev_t
            let inode: ino_t
        }
        var created: [CreatedFile] = []
        do {
            for (document, source) in zip(documents, staged) {
                try checkCancellation()
                let destination = document.destination
                let directory = directories[destination.deletingLastPathComponent().path]!
                let reader = try FileHandle(forReadingFrom: source)
                defer { try? reader.close() }
                // Pin the chosen directory and create exclusively so concurrent files and dangling links survive.
                let descriptor = openat(directory, destination.lastPathComponent, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                guard descriptor >= 0 else {
                    if errno == EEXIST { throw ImageProcessingError.outputAlreadyExists(destination) }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                let writer = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                defer { try? writer.close() }
                var metadata = stat()
                guard fstat(descriptor, &metadata) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                created.append(CreatedFile(directory: directory, name: destination.lastPathComponent, device: metadata.st_dev, inode: metadata.st_ino))
                while let bytes = try reader.read(upToCount: 64 * 1_024), !bytes.isEmpty {
                    try checkCancellation()
                    try writer.write(contentsOf: bytes)
                }
                try writer.synchronize()
                try checkCancellation()
            }
            return documents.map(\.destination)
        } catch {
            for file in created {
                var metadata = stat()
                if fstatat(file.directory, file.name, &metadata, AT_SYMLINK_NOFOLLOW) == 0,
                   metadata.st_dev == file.device, metadata.st_ino == file.inode {
                    _ = unlinkat(file.directory, file.name, 0)
                }
            }
            throw error
        }
    }
}
