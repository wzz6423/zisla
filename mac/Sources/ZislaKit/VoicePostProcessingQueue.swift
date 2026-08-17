import Foundation

@MainActor
public final class VoicePostProcessingQueue {
    public typealias Operation = @MainActor @Sendable () async -> Void

    private var pending: [Operation] = []
    private var worker: Task<Void, Never>?
    private var generation = 0

    public init() {}

    public func enqueue(_ operation: @escaping Operation) {
        pending.append(operation)
        startWorkerIfNeeded()
    }

    public func cancelAll() {
        generation += 1
        pending.removeAll()
        worker?.cancel()
        worker = nil
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, !pending.isEmpty else { return }
        let workerGeneration = generation
        worker = Task { @MainActor [weak self] in
            await self?.drain(generation: workerGeneration)
        }
    }

    private func drain(generation workerGeneration: Int) async {
        while !Task.isCancelled, generation == workerGeneration, !pending.isEmpty {
            let operation = pending.removeFirst()
            await operation()
        }
        guard generation == workerGeneration else { return }
        worker = nil
        startWorkerIfNeeded()
    }
}
