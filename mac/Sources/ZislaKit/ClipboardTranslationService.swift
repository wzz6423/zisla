import Foundation
import NaturalLanguage

public enum ClipboardTranslationError: Error, Equatable, Sendable {
    case invalidInput
    case unavailable
    case invalidResponse
}

public struct ClipboardTranslationService: Sendable {
    public typealias Provider = @Sendable (_ text: String, _ targetLanguage: String) async throws -> String

    private let providers: [Provider]
    private let waitForTimeout: @Sendable () async throws -> Void

    public init(
        providers: [Provider],
        waitForTimeout: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .seconds(15))
        }
    ) {
        self.providers = providers
        self.waitForTimeout = waitForTimeout
    }

    public func translate(
        _ text: String,
        targetLanguage: String,
        additionalProviders: [Provider] = []
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClipboardTranslationError.invalidInput
        }
        try Task.checkCancellation()
        let candidates = providers + additionalProviders
        guard !candidates.isEmpty else { throw ClipboardTranslationError.unavailable }
        let (events, continuation) = AsyncStream<Event>.makeStream()
        // A provider that ignores cancellation must not hold up the winning result.
        let tasks = candidates.map { provider in
            Task {
                do {
                    let result = try await provider(text, targetLanguage)
                    continuation.yield(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? .failed : .translated(result))
                } catch {
                    continuation.yield(.failed)
                }
            }
        }
        let timeout = Task {
            do {
                try await waitForTimeout()
                continuation.yield(.timedOut)
            } catch {
                // Cancellation ends the timer after a winner, failure, or user dismissal.
            }
        }
        defer {
            tasks.forEach { $0.cancel() }
            timeout.cancel()
            continuation.finish()
        }
        var remaining = candidates.count
        for await event in events {
            try Task.checkCancellation()
            switch event {
            case .translated(let result): return result
            case .failed:
                remaining -= 1
                if remaining == 0 { throw ClipboardTranslationError.unavailable }
            case .timedOut: throw ClipboardTranslationError.unavailable
            }
        }
        throw CancellationError()
    }

    public static func live(session suppliedSession: URLSession? = nil) -> Self {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        let session = suppliedSession ?? URLSession(configuration: configuration)
        return Self(providers: [
            { try await google(text: $0, targetLanguage: $1, session: session) },
            { try await myMemory(text: $0, targetLanguage: $1, session: session) },
        ])
    }

    static func google(text: String, targetLanguage: String, session: URLSession) async throws -> String {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: targetLanguage),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]
        // These endpoints decode queries as forms, where a literal plus otherwise becomes a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        let data = try await responseData(for: URLRequest(url: components.url!), session: session)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = payload.first as? [[Any]], !segments.isEmpty else {
            throw ClipboardTranslationError.invalidResponse
        }
        return try segments.map { segment in
            guard let translation = segment.first as? String, !translation.isEmpty else {
                throw ClipboardTranslationError.invalidResponse
            }
            return translation
        }.joined()
    }

    static func responseData(for request: URLRequest, session: URLSession) async throws -> Data {
        var request = request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw ClipboardTranslationError.invalidResponse
        }
        return data
    }

    static func myMemory(text: String, targetLanguage: String, session: URLSession) async throws -> String {
        guard let language = NLLanguageRecognizer.dominantLanguage(for: text) else {
            throw ClipboardTranslationError.unavailable
        }
        let sourceLanguage: String
        switch language {
        case .simplifiedChinese: sourceLanguage = "zh-CN"
        case .traditionalChinese: sourceLanguage = "zh-TW"
        default: sourceLanguage = language.rawValue
        }
        var output = ""
        // Requests remain sequential within a platform, and only the complete text can win.
        for chunk in try chunks(text, maximumBytes: 500) {
            try Task.checkCancellation()
            let content = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                output += chunk
                continue
            }
            var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
            components.queryItems = [
                URLQueryItem(name: "q", value: content),
                URLQueryItem(name: "langpair", value: "\(sourceLanguage)|\(targetLanguage)"),
            ]
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            let data = try await responseData(for: URLRequest(url: components.url!), session: session)
            let payload = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
            let result = payload.responseData.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload.responseStatus == 200, !payload.quotaFinished, !result.isEmpty else {
                throw ClipboardTranslationError.invalidResponse
            }
            let prefix = chunk.prefix(while: \.isWhitespace)
            let suffix = chunk.reversed().prefix(while: \.isWhitespace).reversed()
            output += String(prefix) + result + String(suffix)
        }
        return output
    }

    static func chunks(_ text: String, maximumBytes: Int) throws -> [String] {
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            var end = start
            var lastBoundary: String.Index?
            var bytes = 0
            while end < text.endIndex {
                let character = text[end]
                let size = character.utf8.count
                guard size <= maximumBytes else { throw ClipboardTranslationError.invalidInput }
                if bytes + size > maximumBytes { break }
                bytes += size
                end = text.index(after: end)
                if character.isWhitespace { lastBoundary = end }
            }
            if end < text.endIndex, let lastBoundary { end = lastBoundary }
            result.append(String(text[start..<end]))
            start = end
        }
        return result
    }

    private struct MyMemoryResponse: Decodable {
        struct ResponseData: Decodable { let translatedText: String }
        let responseData: ResponseData
        let responseStatus: Int
        let quotaFinished: Bool
    }

    private enum Event: Sendable {
        case translated(String)
        case failed
        case timedOut
    }
}
