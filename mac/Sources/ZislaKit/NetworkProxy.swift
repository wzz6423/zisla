import Combine
import Foundation
import Network

/// Converts the one user-facing proxy URL into the process and URLSession settings
/// used by network-capable local tasks.
public enum NetworkProxy {
    public static func url(from value: String) -> URL? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "socks5", "socks5h"].contains(scheme),
              url.host != nil
        else { return nil }
        // Allow a nil port (uses the default port) or an explicitly specified non-zero port.
        if let port = url.port, port == 0 { return nil }
        return url
    }

    public static func environment(
        from value: String,
        enabled: Bool = true,
        base: [String: String]
    ) -> [String: String] {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return base }
        guard enabled else {
            return base.filter { key, _ in
                !["http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"].contains(key)
            }
        }
        guard let url = url(from: raw) else { return base }
        var environment = base
        let proxy = url.absoluteString
        environment["http_proxy"] = proxy
        environment["https_proxy"] = proxy
        environment["HTTP_PROXY"] = proxy
        environment["HTTPS_PROXY"] = proxy
        return environment
    }

    public static func sessionConfiguration(
        from value: String,
        enabled: Bool = true,
        base: URLSessionConfiguration = .ephemeral
    ) -> URLSessionConfiguration {
        guard enabled,
              let url = url(from: value),
              let host = url.host else { return base }
        let scheme = url.scheme?.lowercased()
        let port = url.port ?? defaultPort(for: scheme)
        if scheme == "socks5" || scheme == "socks5h" {
            base.connectionProxyDictionary = [
                kCFNetworkProxiesSOCKSEnable as String: true,
                kCFNetworkProxiesSOCKSProxy as String: host,
                kCFNetworkProxiesSOCKSPort as String: port,
            ]
        } else {
            base.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        }
        return base
    }

    static func endpoint(from value: String) -> (host: String, port: UInt16)? {
        guard let url = url(from: value), let host = url.host else { return nil }
        let port = url.port ?? defaultPort(for: url.scheme)
        guard (1...65_535).contains(port) else { return nil }
        return (host, UInt16(port))
    }

    private static func defaultPort(for scheme: String?) -> Int {
        switch scheme?.lowercased() {
        case "https": 443
        case "socks5", "socks5h": 1080
        default: 80
        }
    }
}

public enum NetworkProxyAvailability: Equatable, Sendable {
    case disabled
    case notConfigured
    case invalid
    case checking
    case available
    case unavailable
}

@MainActor
public final class NetworkProxyAvailabilityMonitor: ObservableObject {
    @Published public private(set) var availability: NetworkProxyAvailability = .notConfigured

    public init() {}

    private var connection: NWConnection?
    private var requestID = 0

    public func check(urlString: String, enabled: Bool) {
        requestID += 1
        let currentRequestID = requestID
        connection?.cancel()
        connection = nil

        guard enabled else {
            availability = .disabled
            return
        }
        guard !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            availability = .notConfigured
            return
        }
        guard let endpoint = NetworkProxy.endpoint(from: urlString) else {
            availability = .invalid
            return
        }

        availability = .checking
        let connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: NWEndpoint.Port(rawValue: endpoint.port)!,
            using: .tcp
        )
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else {
                guard case .failed = state else { return }
                Task { @MainActor [weak self] in
                    self?.finishCheck(requestID: currentRequestID, available: false)
                }
                return
            }
            Task { @MainActor [weak self] in
                self?.finishCheck(requestID: currentRequestID, available: true)
            }
        }
        connection.start(queue: .global(qos: .utility))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.finishCheck(requestID: currentRequestID, available: false)
        }
    }

    private func finishCheck(requestID: Int, available: Bool) {
        guard requestID == self.requestID else { return }
        self.requestID += 1
        connection?.cancel()
        connection = nil
        availability = available ? .available : .unavailable
    }
}
