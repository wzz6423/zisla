import Foundation
import ZislaCore
import ZislaKit

@MainActor
final class AudioToolsController: ObservableObject {
    @Published private(set) var inputURLs: [URL] = []
    @Published private(set) var summaries: [AudioFileSummary] = []
    @Published private(set) var outputURLs: [URL] = []
    @Published private(set) var isInspecting = false
    @Published private(set) var isProcessing = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var message: String?
    @Published private(set) var failed = false

    private let service: AudioProcessingService
    private var task: Task<Void, Never>?
    private var generation = 0

    init(service: AudioProcessingService = .init()) {
        self.service = service
    }

    deinit { task?.cancel() }

    func setInputs(_ urls: [URL]) {
        cancel()
        inputURLs = urls
        summaries = []
        outputURLs = []
        message = nil
        failed = false
        guard !urls.isEmpty else { return }
        isInspecting = true
        let current = generation
        task = Task {
            do {
                var values: [AudioFileSummary] = []
                for url in urls { values.append(try await service.inspect(url)) }
                guard current == generation else { return }
                summaries = values
            } catch {
                guard current == generation else { return }
                message = error.localizedDescription
                failed = true
            }
            isInspecting = false
            task = nil
        }
    }

    func moveInput(at index: Int, offset: Int) {
        let destination = index + offset
        guard inputURLs.indices.contains(index), inputURLs.indices.contains(destination), summaries.count == inputURLs.count else { return }
        inputURLs.swapAt(index, destination)
        summaries.swapAt(index, destination)
    }

    func start(_ request: AudioProcessingRequest, output: URL) {
        cancel()
        isProcessing = true
        outputURLs = []
        message = nil
        failed = false
        completed = 0
        total = 0
        let current = generation
        task = Task { [self] in
            do {
                let outputs = try await service.process(request, outputURL: output) { [weak self] completed, total in
                    await MainActor.run {
                        guard let self, self.generation == current else { return }
                        self.completed = completed
                        self.total = total
                    }
                }
                guard current == generation else { return }
                outputURLs = outputs
                message = AppLocalization.text("已导出 %ld 个音频文件", outputs.count)
            } catch {
                guard current == generation else { return }
                message = error.localizedDescription
                failed = true
            }
            isProcessing = false
            task = nil
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        if isProcessing { message = AppLocalization.text("已取消") }
        isProcessing = false
        isInspecting = false
    }
}
