import SwiftUI
import Translation
import ZislaKit

@MainActor
final class ClipboardSystemTranslationBridge: ObservableObject {
    struct Request: Identifiable, Sendable {
        let id: UUID
        let text: String
        let targetLanguage: String
    }

    @Published private(set) var request: Request?
    private var continuation: CheckedContinuation<String, any Error>?

    func translate(_ text: String, targetLanguage: String) async throws -> String {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                cancel()
                self.continuation = continuation
                request = Request(id: id, text: text, targetLanguage: targetLanguage)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.complete(id: id, result: .failure(CancellationError()))
            }
        }
    }

    func complete(id: UUID, result: Result<String, any Error>) {
        guard request?.id == id else { return }
        let continuation = continuation
        self.continuation = nil
        request = nil
        continuation?.resume(with: result)
    }

    func cancel() {
        guard let request else { return }
        complete(id: request.id, result: .failure(CancellationError()))
    }
}

@available(macOS 15.0, *)
struct ClipboardSystemTranslationView: View {
    @ObservedObject var bridge: ClipboardSystemTranslationBridge

    var body: some View {
        if let request = bridge.request {
            InstalledTranslationView(request: request, bridge: bridge)
                .id(request.id)
        }
    }
}

@available(macOS 15.0, *)
private struct InstalledTranslationView: View {
    let request: ClipboardSystemTranslationBridge.Request
    let bridge: ClipboardSystemTranslationBridge
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                do {
                    let target = Locale.Language(identifier: request.targetLanguage)
                    let status = try await LanguageAvailability().status(for: request.text, to: target)
                    try Task.checkCancellation()
                    guard status == .installed else {
                        bridge.complete(id: request.id, result: .failure(ClipboardTranslationError.unavailable))
                        return
                    }
                    configuration = TranslationSession.Configuration(target: target)
                } catch {
                    bridge.complete(id: request.id, result: .failure(error))
                }
            }
            .translationTask(configuration) { @Sendable [request, bridge] session in
                do {
                    let response = try await session.translate(request.text)
                    await bridge.complete(id: request.id, result: .success(response.targetText))
                } catch {
                    await bridge.complete(id: request.id, result: .failure(error))
                }
            }
    }
}
