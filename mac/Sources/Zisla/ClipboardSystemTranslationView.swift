import NaturalLanguage
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

    func autoTranslate(
        _ text: String,
        targetLanguage: String,
        service: ClipboardTranslationService
    ) async throws -> String {
        var additionalProviders: [ClipboardTranslationService.Provider] = []
        if #available(macOS 15.0, *) {
            additionalProviders.append { [self] text, language in
                try await translate(text, targetLanguage: language)
            }
        }
        return try await service.translate(text, targetLanguage: targetLanguage, additionalProviders: additionalProviders)
    }

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

    @available(macOS 15.0, *)
    static func installedConfiguration(
        for request: Request,
        statusForText: (String, Locale.Language) async throws -> LanguageAvailability.Status = {
            try await LanguageAvailability().status(for: $0, to: $1)
        },
        statusForLanguages: (Locale.Language, Locale.Language) async -> LanguageAvailability.Status = {
            await LanguageAvailability().status(from: $0, to: $1)
        }
    ) async throws -> TranslationSession.Configuration {
        let target = Locale.Language(identifier: request.targetLanguage)
        let status: LanguageAvailability.Status
        var source: Locale.Language?
        do {
            status = try await statusForText(request.text, target)
        } catch {
            guard TranslationError.unableToIdentifyLanguage ~= error,
                  let language = NLLanguageRecognizer.dominantLanguage(for: request.text) else { throw error }
            let identifiedSource = Locale.Language(identifier: language.rawValue)
            source = identifiedSource
            status = await statusForLanguages(identifiedSource, target)
        }
        try Task.checkCancellation()
        guard status == .installed else { throw ClipboardTranslationError.unavailable }
        return TranslationSession.Configuration(source: source, target: target)
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
                    configuration = try await ClipboardSystemTranslationBridge.installedConfiguration(for: request)
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
