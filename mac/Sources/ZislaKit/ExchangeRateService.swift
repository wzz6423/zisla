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
/// live rate of the moment it is copied. exchangerate.dev supplies the primary intraday quote;
/// frankfurter.dev and open.er-api.com preserve a broad no-key fallback chain.
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
                return try await fetchFromExchangeRateDev(session: session, source: source, target: target)
            } catch {
                do {
                    return try await fetchFromFrankfurter(session: session, source: source, target: target)
                } catch {
                    return try await fetchFromExchangeRateAPI(session: session, source: source, target: target)
                }
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

/// api.exchangerate.dev payload: {"result":"success","base":"USD","rates":{"CNY":7.2,…}}
private struct ExchangeRateDevPayload: Decodable {
    let result: String
    let base: String
    let rates: [String: Double]
}

private func fetchFromExchangeRateDev(
    session: URLSession,
    source: String,
    target: String
) async throws -> ExchangeRateQuote {
    var components = URLComponents(string: "https://api.exchangerate.dev/v1/latest/\(source)")
    components?.queryItems = [URLQueryItem(name: "symbols", value: target)]
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
    guard let payload = try? JSONDecoder().decode(ExchangeRateDevPayload.self, from: data),
          payload.result == "success",
          payload.base == source,
          let rate = payload.rates[target], rate > 0 else {
        throw ExchangeRateError.malformedPayload
    }
    return ExchangeRateQuote(
        sourceCurrencyCode: source,
        targetCurrencyCode: target,
        rate: rate,
        fetchedAt: Date()
    )
}

/// open.er-api.com payload: {"result":"success","base_code":"USD","rates":{"CNY":7.2,…}}
private struct ExchangeRateAPIPayload: Decodable {
    let result: String
    let baseCode: String
    let rates: [String: Double]?

    private enum CodingKeys: String, CodingKey {
        case result, rates
        case baseCode = "base_code"
    }
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
          payload.baseCode == source,
          let rates = payload.rates,
          let rate = rates[target], rate > 0 else {
        throw ExchangeRateError.malformedPayload
    }
    return ExchangeRateQuote(
        sourceCurrencyCode: source,
        targetCurrencyCode: target,
        rate: rate,
        fetchedAt: Date()
    )
}

/// frankfurter.dev payload: {"date":"2026-09-17","base":"USD","quote":"CNY","rate":7.2}
private struct FrankfurterPayload: Decodable {
    let base: String
    let quote: String
    let rate: Double
}

private func fetchFromFrankfurter(
    session: URLSession,
    source: String,
    target: String
) async throws -> ExchangeRateQuote {
    guard let endpoint = URL(string: "https://api.frankfurter.dev/v2/rate/\(source)/\(target)") else {
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
          payload.quote == target,
          payload.rate > 0 else {
        throw ExchangeRateError.rateUnavailable(
            sourceCurrencyCode: source,
            targetCurrencyCode: target
        )
    }
    return ExchangeRateQuote(
        sourceCurrencyCode: source,
        targetCurrencyCode: target,
        rate: payload.rate,
        fetchedAt: Date()
    )
}
