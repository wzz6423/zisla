import Foundation

/// Live exchange-rate quote backing a clipboard assistant currency conversion.
public struct ExchangeRateQuote: Equatable, Sendable {
    public let sourceCurrencyCode: String
    public let targetCurrencyCode: String
    /// Units of the target currency per one unit of the source currency.
    public let rate: Double
    public let fetchedAt: Date

    public init(sourceCurrencyCode: String, targetCurrencyCode: String, rate: Double, fetchedAt: Date) {
        self.sourceCurrencyCode = sourceCurrencyCode
        self.targetCurrencyCode = targetCurrencyCode
        self.rate = rate
        self.fetchedAt = fetchedAt
    }
}

public enum ExchangeRateError: Error, Equatable, Sendable {
    case invalidResponse
    case malformedPayload
    case rateUnavailable(sourceCurrencyCode: String, targetCurrencyCode: String)
    case httpStatus(Int)
}

/// Fetches up-to-date exchange rates for the clipboard assistant. Every conversion hits the
/// network — quotes are deliberately never cached, because a copied amount must convert at the
/// live rate of the moment it is copied. The primary source is open.er-api.com (160+ currencies,
/// no key); frankfurter.dev (ECB reference rates, ~30 currencies) serves as the fallback.
public struct ExchangeRateService: Sendable {
    public var fetchRate: @Sendable (
        _ sourceCurrencyCode: String,
        _ targetCurrencyCode: String
    ) async throws -> ExchangeRateQuote

    public init(
        fetchRate: @escaping @Sendable (
            _ sourceCurrencyCode: String,
            _ targetCurrencyCode: String
        ) async throws -> ExchangeRateQuote
    ) {
        self.fetchRate = fetchRate
    }

    public static func live(session suppliedSession: URLSession? = nil) -> ExchangeRateService {
        let session = suppliedSession ?? makeSession()
        return ExchangeRateService { source, target in
            let source = source.uppercased()
            let target = target.uppercased()
            do {
                return try await fetchFromExchangeRateAPI(session: session, source: source, target: target)
            } catch {
                return try await fetchFromFrankfurter(session: session, source: source, target: target)
            }
        }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}

/// open.er-api.com payload: {"result":"success","base_code":"USD","rates":{"CNY":7.2,…}}
private struct ExchangeRateAPIPayload: Decodable {
    let result: String
    let rates: [String: Double]?
}

private func fetchFromExchangeRateAPI(
    session: URLSession,
    source: String,
    target: String
) async throws -> ExchangeRateQuote {
    guard let endpoint = URL(string: "https://open.er-api.com/v6/latest/\(source)") else {
        throw ExchangeRateError.invalidResponse
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = 8
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("zisla-macOS", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw ExchangeRateError.invalidResponse
    }
    guard http.statusCode == 200 else {
        throw ExchangeRateError.httpStatus(http.statusCode)
    }
    guard let payload = try? JSONDecoder().decode(ExchangeRateAPIPayload.self, from: data),
          payload.result == "success",
          let rates = payload.rates,
          let rate = rates[target] else {
        throw ExchangeRateError.malformedPayload
    }
    return ExchangeRateQuote(
        sourceCurrencyCode: source,
        targetCurrencyCode: target,
        rate: rate,
        fetchedAt: Date()
    )
}

/// frankfurter.dev payload: {"base":"USD","date":"2026-09-11","rates":{"CNY":7.2}}
private struct FrankfurterPayload: Decodable {
    let base: String
    let rates: [String: Double]
}

private func fetchFromFrankfurter(
    session: URLSession,
    source: String,
    target: String
) async throws -> ExchangeRateQuote {
    var components = URLComponents(string: "https://api.frankfurter.dev/v1/latest")
    components?.queryItems = [
        URLQueryItem(name: "base", value: source),
        URLQueryItem(name: "symbols", value: target),
    ]
    guard let endpoint = components?.url else {
        throw ExchangeRateError.invalidResponse
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = 8
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("zisla-macOS", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw ExchangeRateError.invalidResponse
    }
    guard http.statusCode == 200 else {
        throw ExchangeRateError.httpStatus(http.statusCode)
    }
    guard let payload = try? JSONDecoder().decode(FrankfurterPayload.self, from: data),
          payload.base == source,
          let rate = payload.rates[target] else {
        throw ExchangeRateError.rateUnavailable(
            sourceCurrencyCode: source,
            targetCurrencyCode: target
        )
    }
    return ExchangeRateQuote(
        sourceCurrencyCode: source,
        targetCurrencyCode: target,
        rate: rate,
        fetchedAt: Date()
    )
}
