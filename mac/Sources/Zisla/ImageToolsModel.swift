import AppKit
import ImageIO
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit

struct ImageToolsEditorInput: Identifiable {
    let inputURL: URL
    let image: NSImage
    var id: URL { inputURL }
}

@MainActor
final class ImageToolsModel: ObservableObject {
    @Published var inputs: [URL] = []
    @Published private(set) var batch: ImageProcessingBatch?
    @Published private(set) var isProcessing = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published var message: String?
    @Published var editorInput: ImageToolsEditorInput?
    @Published private(set) var editedImageURLs: [URL: URL] = [:]
    private var task: Task<Void, Never>?
    private var editDirectory: URL?

    isolated deinit {
        task?.cancel()
        if let directory = batch?.directoryURL { try? FileManager.default.removeItem(at: directory) }
        if let editDirectory { try? FileManager.default.removeItem(at: editDirectory) }
    }

    func addInputs(_ urls: [URL]) {
        guard !isProcessing else { return }
        isProcessing = true
        total = 0
        task = Task { [weak self] in
            let scan = Task.detached { try ImageProcessingService.collectInputs(urls) }
            do {
                let files = try await withTaskCancellationHandler { try await scan.value } onCancel: { scan.cancel() }
                try Task.checkCancellation()
                guard let self else { return }
                self.inputs = Array(Set(self.inputs + files)).sorted { $0.path < $1.path }
                self.message = files.isEmpty ? AppLocalization.text("请先选择图片或包含图片的文件夹") : nil
                self.isProcessing = false
            } catch {
                self?.isProcessing = false
                self?.message = error is CancellationError ? AppLocalization.text("已取消") : error.localizedDescription
            }
        }
    }

    @discardableResult
    func start(service: ImageProcessingService, options: ImageProcessingOptions,
               rasterTransform: ImageProcessingService.RasterTransform? = nil,
               inputURLs: [URL]? = nil) -> Task<Void, Never>? {
        guard !isProcessing else { return nil }
        discardResults()
        isProcessing = true
        completed = 0
        let inputs = inputURLs ?? self.inputs
        total = inputs.count
        message = nil
        task = Task { [weak self] in
            do {
                let result = try await service.process(inputs, options: options, rasterTransform: rasterTransform,
                                                       progress: { [weak self] completed, total in
                    await MainActor.run {
                        self?.completed = completed
                        self?.total = total
                    }
                })
                guard let self else {
                    try? FileManager.default.removeItem(at: result.directoryURL)
                    return
                }
                self.batch = result
                self.isProcessing = false
                self.message = AppLocalization.text("完成 %ld 张图片，失败 %ld 项", result.items.count, result.failures.count)
            } catch {
                self?.isProcessing = false
                self?.message = error is CancellationError ? AppLocalization.text("已取消") : error.localizedDescription
            }
        }
        return task
    }

    func cancel() { task?.cancel() }

    @discardableResult
    func prepareEditor(_ input: URL, service: ImageProcessingService,
                       loadImage: (@Sendable (URL) async throws -> CGImage)? = nil) -> Task<Void, Never>? {
        guard !isProcessing else { return nil }
        isProcessing = true
        total = 0
        message = nil
        let source = editedImageURLs[input] ?? input
        let loadImage: @Sendable (URL) async throws -> CGImage = loadImage ?? { try await service.loadRasterImage($0) }
        task = Task { [weak self] in
            do {
                let image = try await loadImage(source)
                try Task.checkCancellation()
                self?.editorInput = ImageToolsEditorInput(inputURL: input,
                    image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
            } catch {
                self?.message = error is CancellationError ? AppLocalization.text("已取消") : error.localizedDescription
            }
            self?.isProcessing = false
        }
        return task
    }

    @discardableResult
    func recordEdit(_ image: CGImage, for input: URL) -> Task<Void, Never>? {
        guard !isProcessing else { return nil }
        let directory: URL
        do {
            if let editDirectory { directory = editDirectory }
            else {
                directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-image-edits-\(UUID())")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                editDirectory = directory
            }
        } catch {
            message = error.localizedDescription
            return nil
        }
        let output = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        isProcessing = true
        total = 0
        message = nil
        editorInput = nil
        task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let work = Task.detached {
                    guard image.width <= 150_000, image.height <= 150_000,
                          Int64(image.width) * Int64(image.height) <= ImageProcessingService.maximumPixels else {
                        throw ImageProcessingError.resourceLimit
                    }
                    guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                        throw ImageProcessingError.invalidOutput
                    }
                    CGImageDestinationAddImage(destination, image, nil)
                    guard CGImageDestinationFinalize(destination) else { throw ImageProcessingError.invalidOutput }
                }
                try await work.value
                guard !Task.isCancelled, let self else { throw CancellationError() }
                if let previous = self.editedImageURLs[input] { try FileManager.default.removeItem(at: previous) }
                self.editedImageURLs[input] = output
                self.isProcessing = false
                self.discardResults()
            } catch {
                try? FileManager.default.removeItem(at: output)
                self?.message = error is CancellationError ? AppLocalization.text("已取消") : error.localizedDescription
            }
            self?.isProcessing = false
        }
        return task
    }

    func startEdited(service: ImageProcessingService) {
        let edits = editedImageURLs
        guard !edits.isEmpty else {
            message = AppLocalization.text("请先编辑需要处理的图片")
            return
        }
        start(service: service, options: .init(formats: [.png]), rasterTransform: { _, input in
            try await service.loadRasterImage(edits[input]!)
        }, inputURLs: edits.keys.sorted { $0.path < $1.path })
    }

    func discardEdits() {
        guard !isProcessing else { return }
        if let editDirectory { try? FileManager.default.removeItem(at: editDirectory) }
        editDirectory = nil
        editedImageURLs = [:]
        editorInput = nil
    }

    func exportImages(_ items: [ImageProcessedItem], to directory: URL, smallestOnly: Bool) {
        guard !isProcessing else { return }
        isProcessing = true
        total = 0
        task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let work = Task.detached { try ImageProcessingService.export(items, to: directory, smallestOnly: smallestOnly) }
                let outputs = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                self?.message = AppLocalization.text("已导出 %ld 张图片", outputs.count)
            } catch {
                self?.message = error is CancellationError ? AppLocalization.text("已取消") : error.localizedDescription
            }
            self?.isProcessing = false
        }
    }

    func exportZIP(_ items: [ImageProcessedItem], to destination: URL,
                   archive: @escaping @Sendable (URL, URL) async -> String? = { source, output in
                       await AppModel.zipArchiveError(source: source, destination: output)
                   }) {
        guard !isProcessing else { return }
        isProcessing = true
        total = 0
        task = Task { [weak self] in
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-image-export-\(UUID())")
            defer { try? FileManager.default.removeItem(at: temporary) }
            do {
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let folder = temporary.appendingPathComponent("images", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let staging = temporary.appendingPathComponent("images.zip")
                let work = Task.detached {
                    _ = try ImageProcessingService.export(items, to: folder, smallestOnly: false)
                    if let error = await archive(folder, staging) { throw ImageProcessingError.processingFailed(error) }
                    try Task.checkCancellation()
                    try FileManager.default.copyItem(at: staging, to: destination)
                }
                try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                self?.message = AppLocalization.text("已保存 %@", destination.lastPathComponent)
            } catch {
                self?.message = error is CancellationError ? AppLocalization.text("已取消") : error.localizedDescription
            }
            self?.isProcessing = false
        }
    }

    func discardResults() {
        guard !isProcessing else { return }
        if let directory = batch?.directoryURL { try? FileManager.default.removeItem(at: directory) }
        batch = nil
    }
}
