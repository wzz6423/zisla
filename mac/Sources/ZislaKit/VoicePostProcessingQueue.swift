import Foundation

@MainActor
public final class VoicePostProcessingQueue {
    public typealias Operation = @MainActor @Sendable () async -> Void

    private var pending: [Operation?] = []
    private var worker: Task<Void, Never>?
    private var generation = 0
    private var pendingHead = 0
    private var pendingCount = 0

    public init() {}

    public func enqueue(_ operation: @escaping Operation) {
        ensurePendingCapacity()
        let tail = (pendingHead + pendingCount) % pending.count
        pending[tail] = operation
        pendingCount += 1
        startWorkerIfNeeded()
    }

    public func cancelAll() {
        generation += 1
        for index in pending.indices {
            pending[index] = nil
        }
        pendingHead = 0
        pendingCount = 0
        worker?.cancel()
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, pendingCount > 0 else { return }
        let workerGeneration = generation
        worker = Task { @MainActor [weak self] in
            await self?.drain(generation: workerGeneration)
        }
    }

    private func drain(generation workerGeneration: Int) async {
        while !Task.isCancelled,
              generation == workerGeneration,
              pendingCount > 0 {
            let index = pendingHead
            let operation = pending[index]
            pending[index] = nil
            pendingHead = (index + 1) % pending.count
            pendingCount -= 1
            guard let operation else { continue }
            await operation()
        }
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

    private func ensurePendingCapacity() {
        guard pendingCount == pending.count else { return }

        let oldCapacity = pending.count
        let newCapacity = oldCapacity == 0 ? 1 : oldCapacity * 2
        var expanded = Array<Operation?>(repeating: nil, count: newCapacity)
        if oldCapacity > 0 {
            for offset in 0..<pendingCount {
                expanded[offset] = pending[(pendingHead + offset) % oldCapacity]
            }
        }
        pending = expanded
        pendingHead = 0
    }
}
