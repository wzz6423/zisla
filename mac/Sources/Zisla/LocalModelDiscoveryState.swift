import Combine
import Foundation
import ZislaCore
import ZislaKit

@MainActor
final class LocalModelDiscoveryState: ObservableObject {
    enum Action: Sendable {
        case discover
        case startServer
    }

    @Published private(set) var catalog: AILocalModelCatalog?
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false

    private var task: Task<Void, Never>?
    private let load: @Sendable (AIEndpoint, String?, Action) async throws -> AILocalModelCatalog

    init(load: @escaping @Sendable (AIEndpoint, String?, Action) async throws -> AILocalModelCatalog = { endpoint, key, action in
        let service = AIModelDiscoveryService()
        switch action {
        case .discover: return try await service.localCatalog(for: endpoint, apiKey: key)
        case .startServer: return try await service.startLMStudioServer(for: endpoint, apiKey: key)
        }
    }) {
        self.load = load
    }

    @discardableResult
    func refresh(
        endpoint: AIEndpoint,
        apiKey: String?,
        isEnabled: Bool,
        action: Action = .discover,
        delay: Duration = .milliseconds(350)
    ) -> Task<Void, Never>? {
        cancel()
        guard isEnabled else { return nil }
        isLoading = true
        let load = load
        let pending = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                let catalog = try await load(endpoint, apiKey, action)
                guard !Task.isCancelled, let self else { return }
                self.catalog = catalog
                self.isLoading = false
                self.task = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.error = error.localizedDescription
                self.isLoading = false
                self.task = nil
            }
        }
        task = pending
        return pending
    }

    func cancel() {
        task?.cancel()
        task = nil
        catalog = nil
        error = nil
        isLoading = false
    }
}
