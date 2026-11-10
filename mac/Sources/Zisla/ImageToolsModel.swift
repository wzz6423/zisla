import Foundation
import ZislaCore
import ZislaKit

@MainActor
final class ImageToolsModel: ObservableObject {
    @Published var inputs: [URL] = []
    @Published private(set) var batch: ImageProcessingBatch?
    @Published private(set) var isProcessing = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published var message: String?
    private var task: Task<Void, Never>?

    isolated deinit {
        task?.cancel()
        if let directory = batch?.directoryURL { try? FileManager.default.removeItem(at: directory) }
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

    func start(service: ImageProcessingService, options: ImageProcessingOptions) {
        guard !isProcessing else { return }
        discardResults()
        isProcessing = true
        completed = 0
        total = inputs.count
        message = nil
        let inputs = inputs
        task = Task { [weak self] in
            do {
                let result = try await service.process(inputs, options: options) { [weak self] completed, total in
                    await MainActor.run {
                        self?.completed = completed
                        self?.total = total
                    }
                }
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
    }

    func cancel() { task?.cancel() }

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
