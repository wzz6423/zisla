import Foundation
import Testing
@testable import ZislaKit

/// The clipboard assistant must always convert at the live rate, so every request goes to the
/// network with cache reading disabled and falls back to the secondary source on failure.
/// Serialized: the stub protocol answers from a shared response queue.
@Suite(.serialized)
struct ExchangeRateServiceTests {
    @Test
    func fetchesRateFromPrimarySourceWithoutCaching() async throws {
        ExchangeRateStubURLProtocol.reset()
        ExchangeRateStubURLProtocol.enqueue(
            status: 200,
            body: #"{"result":"success","base_code":"USD","rates":{"CNY":7.23}}"#
        )
        let service = ExchangeRateService.live(session: Self.stubbedSession())

        let quote = try await service.fetchRate("USD", "CNY")

        #expect(quote.rate == 7.23)
        #expect(quote.sourceCurrencyCode == "USD")
        #expect(quote.targetCurrencyCode == "CNY")
        let request = try #require(ExchangeRateStubURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://open.er-api.com/v6/latest/USD")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test
    func fallsBackToFrankfurterWhenPrimaryFails() async throws {
        ExchangeRateStubURLProtocol.reset()
        ExchangeRateStubURLProtocol.enqueue(status: 500, body: "{}")
        ExchangeRateStubURLProtocol.enqueue(
            status: 200,
            body: #"{"base":"USD","date":"2026-09-11","rates":{"CNY":7.2}}"#
        )
        let service = ExchangeRateService.live(session: Self.stubbedSession())

        let quote = try await service.fetchRate("usd", "cny")

        #expect(quote.rate == 7.2)
        #expect(quote.sourceCurrencyCode == "USD")
        let request = try #require(ExchangeRateStubURLProtocol.lastRequest)
        #expect(request.url?.host == "api.frankfurter.dev")
        #expect(request.url?.query?.contains("base=USD") == true)
        #expect(request.url?.query?.contains("symbols=CNY") == true)
    }

    @Test
    func surfacesFailureWhenBothSourcesFail() async {
        ExchangeRateStubURLProtocol.reset()
        ExchangeRateStubURLProtocol.enqueue(status: 503, body: "{}")
        ExchangeRateStubURLProtocol.enqueue(status: 503, body: "{}")
        let service = ExchangeRateService.live(session: Self.stubbedSession())

        await #expect(throws: ExchangeRateError.self) {
            try await service.fetchRate("USD", "CNY")
        }
    }

    @Test
    func rejectsMalformedPrimaryPayloadInsteadOfGuessingARate() async {
        ExchangeRateStubURLProtocol.reset()
        // The primary payload lacks the target rate; the stub's default empty response then
        // makes the fallback fail too, so no quote may surface at all.
        ExchangeRateStubURLProtocol.enqueue(
            status: 200,
            body: #"{"result":"success","base_code":"USD","rates":{"EUR":0.9}}"#
        )
        let service = ExchangeRateService.live(session: Self.stubbedSession())

        do {
            _ = try await service.fetchRate("USD", "CNY")
            Issue.record("a payload missing the target rate must not yield a quote")
        } catch {
            #expect(!"\(error)".contains("0.9"))
        }
    }

    @Test(arguments: [
        #"{"result":"success","base_code":"EUR","rates":{"CNY":7.23}}"#,
        #"{"result":"success","rates":{"CNY":7.23}}"#,
        #"{"result":"success","base_code":"USD","rates":{"CNY":0}}"#,
        #"{"result":"success","base_code":"USD","rates":{"CNY":-7.23}}"#,
    ])
    func rejectsInvalidPrimaryQuoteAndUsesValidFallback(body: String) async throws {
        ExchangeRateStubURLProtocol.reset()
        ExchangeRateStubURLProtocol.enqueue(status: 200, body: body)
        ExchangeRateStubURLProtocol.enqueue(
            status: 200,
            body: #"{"base":"USD","date":"2026-09-14","rates":{"CNY":7.2}}"#
        )
        let service = ExchangeRateService.live(session: Self.stubbedSession())

        let quote = try await service.fetchRate("USD", "CNY")

        #expect(quote.rate == 7.2)
        #expect(ExchangeRateStubURLProtocol.lastRequest?.url?.host == "api.frankfurter.dev")
    }

    @Test(arguments: [0.0, -7.2])
    func rejectsNonpositiveFallbackRates(rate: Double) async {
        ExchangeRateStubURLProtocol.reset()
        ExchangeRateStubURLProtocol.enqueue(status: 503, body: "{}")
        ExchangeRateStubURLProtocol.enqueue(
            status: 200,
            body: "{\"base\":\"USD\",\"rates\":{\"CNY\":\(rate)}}"
        )
        let service = ExchangeRateService.live(session: Self.stubbedSession())

        await #expect(throws: ExchangeRateError.self) {
            try await service.fetchRate("USD", "CNY")
        }
    }

    private static func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExchangeRateStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class ExchangeRateStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var queue: [(status: Int, body: String)] = []
    nonisolated(unsafe) static var lastRequest: URLRequest?

    nonisolated static func reset() {
        queue = []
        lastRequest = nil
    }

    nonisolated static func enqueue(status: Int, body: String) {
        queue.append((status, body))
    }

    nonisolated static override func canInit(with request: URLRequest) -> Bool { true }

    nonisolated static override func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let next: (status: Int, body: String) = Self.queue.isEmpty ? (status: 200, body: "{}") : Self.queue.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(next.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
