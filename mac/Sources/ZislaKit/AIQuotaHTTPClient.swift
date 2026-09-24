import Foundation
import ZislaCore

public protocol AIQuotaHTTPClient: Sendable {
    func data(for request: URLRequest, trustLoopback: Bool) async throws -> Data
}

public struct AIQuotaURLSessionClient: AIQuotaHTTPClient {
    static let maximumResponseBytes = 2 * 1_024 * 1_024
    private let proxyURL: String
    private let proxyEnabled: Bool
    private var sessionConfiguration: (@Sendable () -> URLSessionConfiguration)?

    public init(proxyURL: String = "", proxyEnabled: Bool = false) {
        self.proxyURL = proxyURL
        self.proxyEnabled = proxyEnabled
    }

    init(configuration: @escaping @Sendable () -> URLSessionConfiguration) {
        proxyURL = ""
        proxyEnabled = false
        sessionConfiguration = configuration
    }

    func configuration(trustLoopback: Bool) -> URLSessionConfiguration {
        let configuration = sessionConfiguration?()
            ?? NetworkProxy.sessionConfiguration(from: proxyURL, enabled: proxyEnabled && !trustLoopback)
        if trustLoopback { configuration.connectionProxyDictionary = [:] }
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 25
        return configuration
    }

    public func data(for request: URLRequest, trustLoopback: Bool = false) async throws -> Data {
        let configuration = configuration(trustLoopback: trustLoopback)
        let session = URLSession(configuration: configuration,
                                 delegate: AIQuotaSessionDelegate(trustLoopback: trustLoopback),
                                 delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIQuotaError.invalidResponse }
            try Self.validate(status: http.statusCode)
            guard response.expectedContentLength <= Self.maximumResponseBytes else {
                throw AIQuotaError.responseTooLarge
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < Self.maximumResponseBytes else { throw AIQuotaError.responseTooLarge }
                data.append(byte)
            }
            try Task.checkCancellation()
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as AIQuotaError { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw AIQuotaError.network
        }
    }

    static func validate(status: Int) throws {
        switch status {
        case 200: return
        case 401, 403: throw AIQuotaError.credentialRejected
        case 429: throw AIQuotaError.rateLimited
        case 404: throw AIQuotaError.noQuota
        default: throw AIQuotaError.server
        }
    }
}

final class AIQuotaSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let trustLoopback: Bool
    init(trustLoopback: Bool) { self.trustLoopback = trustLoopback }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Cookie headers otherwise survive cross-origin redirects.
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard trustLoopback, challenge.protectionSpace.host == "127.0.0.1",
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
