import Foundation

@MainActor
public final class VoicePostProcessingQueue {
    public typealias Operation = @MainActor @Sendable () async -> Void

    private var pending: [Operation?] = []
    private var worker: Task<Void, Never>?
    private var generation = 0
    private var pendingHead = 0

    public init() {}

    public func enqueue(_ operation: @escaping Operation) {
        pending.append(operation)
        startWorkerIfNeeded()
    }

    public func cancelAll() {
        generation += 1
        pending.removeAll()
        pendingHead = 0
        worker?.cancel()
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, !pending.isEmpty else { return }
        let workerGeneration = generation
        worker = Task { @MainActor [weak self] in
            await self?.drain(generation: workerGeneration)
        }
    }

    private func drain(generation workerGeneration: Int) async {
        while !Task.isCancelled,
              generation == workerGeneration,
              pendingHead < pending.count {
            guard let operation = pending[pendingHead] else {
                pendingHead += 1
                continue
            }
            pending[pendingHead] = nil
            pendingHead += 1
            await operation()
            compactPendingIfNeeded()
        }
        compactPendingIfNeeded()
        guard generation == workerGeneration else {
            // Keep the cancelled worker registered until its operation has returned;
            // otherwise a new enqueue could start a second worker concurrently.
            worker = nil
            startWorkerIfNeeded()
            return
        }
        worker = nil
        startWorkerIfNeeded()
    }

    private func compactPendingIfNeeded() {
        guard pendingHead > 0 else { return }
        if pendingHead == pending.count {
            pending.removeAll()
            pendingHead = 0
        } else if pendingHead >= 64, pendingHead * 2 >= pending.count {
            // Bound cleared prefix storage while keeping compaction amortized O(1).
            pending.removeFirst(pendingHead)
            pendingHead = 0
        }
    }
}
