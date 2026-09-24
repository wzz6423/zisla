import Combine
import Foundation
import ZislaCore

public protocol AIQuotaReading: Sendable {
    var id: String { get }
    var providerID: String { get }
    func read() async throws -> [AIQuotaAccount]
}

public extension AIQuotaReading {
    var id: String { providerID }
}

@MainActor
public final class AIQuotaMonitor: ObservableObject {
    @Published public private(set) var snapshot = AIQuotaSnapshot(accounts: [])
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var errors: [String: AIQuotaError] = [:]

    private var readers: [any AIQuotaReading]
    private var refreshTask: Task<([AIQuotaAccount], [String: AIQuotaError]), Never>?
    private var loopTask: Task<Void, Never>?
    private var generation = 0
    private let sleeper: @Sendable (Duration) async throws -> Void

    public convenience init(readers: [any AIQuotaReading] = []) {
        self.init(readers: readers, sleeper: { try await Task.sleep(for: $0) })
    }

    init(readers: [any AIQuotaReading], sleeper: @escaping @Sendable (Duration) async throws -> Void) {
        self.readers = readers
        self.sleeper = sleeper
    }

    deinit {
        loopTask?.cancel()
        refreshTask?.cancel()
    }

    public func configure(readers: [any AIQuotaReading]) {
        let wasRunning = loopTask != nil
        stop()
        self.readers = readers
        if wasRunning { start() }
    }

    public func start() {
        guard loopTask == nil else { return }
        let sleeper = sleeper
        loopTask = Task { [weak self, sleeper] in
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.refresh()
                do { try await sleeper(.seconds(60)) }
                catch { return }
            }
        }
    }

    public func stop() {
        generation &+= 1
        loopTask?.cancel()
        loopTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        snapshot = AIQuotaSnapshot(accounts: [])
        errors = [:]
    }

    public func refresh() async {
        guard refreshTask == nil else { return }
        isRefreshing = true
        let currentGeneration = generation
        let readers = readers
        let task = Task {
            await withTaskGroup(of: (String, Result<[AIQuotaAccount], AIQuotaError>).self) { group in
                var next = readers.makeIterator()
                func enqueue(_ reader: any AIQuotaReading) {
                    group.addTask {
                        do { return (reader.id, .success(try await reader.read())) }
                        catch { return (reader.id, .failure(error as? AIQuotaError ?? .network)) }
                    }
                }
                for _ in 0..<4 { if let reader = next.next() { enqueue(reader) } }
                var accounts: [AIQuotaAccount] = []
                var errors: [String: AIQuotaError] = [:]
                for await (id, result) in group {
                    switch result {
                    case .success(let values): accounts.append(contentsOf: values)
                    case .failure(let error): errors[id] = error
                    }
                    if !Task.isCancelled, let reader = next.next() { enqueue(reader) }
                }
                return (accounts, errors)
            }
        }
        refreshTask = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: { task.cancel() }
        guard currentGeneration == generation else { return }
        refreshTask = nil
        isRefreshing = false
        guard !Task.isCancelled else { return }
        snapshot = AIQuotaSnapshot(accounts: result.0.sorted { ($0.label, $0.id) < ($1.label, $1.id) })
        errors = result.1
    }
}
