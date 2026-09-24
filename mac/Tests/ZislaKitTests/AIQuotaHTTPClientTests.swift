import Foundation
import Security
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct AIQuotaHTTPClientTests {
    private func fixture(_ reply: AIQuotaURLProtocol.Reply) -> (AIQuotaURLSessionClient, URLRequest) {
        let url = URL(string: "https://aiquota.fixture.invalid/\(UUID().uuidString)")!
        AIQuotaURLProtocol.registry.register(reply, url: url)
        let client = AIQuotaURLSessionClient(configuration: {
            let value = URLSessionConfiguration.ephemeral
            value.protocolClasses = [AIQuotaURLProtocol.self]
            return value
        })
        return (client, URLRequest(url: url))
    }

    @Test(arguments: [401, 403, 404, 429, 500, 302])
    func realSessionClassifiesHTTPFailuresWithoutReturningSensitiveBodies(_ status: Int) async {
        let (client, request) = fixture(.init(status: status, body: Data("fictional-sensitive-server-body".utf8)))
        defer { AIQuotaURLProtocol.registry.remove(request.url!) }
        let expected: AIQuotaError = status == 401 || status == 403 ? .credentialRejected
            : status == 404 ? .noQuota : status == 429 ? .rateLimited : .server
        await #expect(throws: expected) { try await client.data(for: request) }
        #expect(!expected.localizedDescription.contains("fictional-sensitive"))
    }

    @Test
    func realSessionReadsSuccessfulBytes() async throws {
        let bytes = Data(#"{"remaining":42}"#.utf8)
        let (client, request) = fixture(.init(body: bytes))
        defer { AIQuotaURLProtocol.registry.remove(request.url!) }
        #expect(try await client.data(for: request) == bytes)
    }

    @Test(arguments: [true, false])
    func realSessionRejectsBothDeclaredAndStreamedOversizeResponses(_ declared: Bool) async {
        let maximum = AIQuotaURLSessionClient.maximumResponseBytes
        let (client, request) = fixture(.init(body: declared ? Data() : Data(repeating: 65, count: maximum + 1), length: declared ? maximum + 1 : nil))
        defer { AIQuotaURLProtocol.registry.remove(request.url!) }
        await #expect(throws: AIQuotaError.responseTooLarge) { try await client.data(for: request) }
    }

    @Test
    func cancellationStopsTheSessionAndIsNotMisreportedAsANetworkFailure() async {
        let (client, request) = fixture(.init(held: true))
        defer { AIQuotaURLProtocol.registry.remove(request.url!) }
        let task = Task { try await client.data(for: request) }
        #expect(await aiQuotaEventually { AIQuotaURLProtocol.registry.hasStarted(request.url!) })
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await aiQuotaEventually { AIQuotaURLProtocol.registry.hasStopped(request.url!) })
    }

    @Test
    func aTransportTimeoutMapsToTheSafeNetworkError() async {
        let (client, request) = fixture(.init(error: URLError(.timedOut)))
        defer { AIQuotaURLProtocol.registry.remove(request.url!) }
        await #expect(throws: AIQuotaError.network) { try await client.data(for: request) }
    }

    @Test
    func delegateRejectsRedirectsBeforeCredentialsCanBeForwarded() async {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let source = URL(string: "https://source.example.test")!
        var redirected = URLRequest(url: URL(string: "https://other.example.test")!)
        redirected.setValue("Bearer fictional-token", forHTTPHeaderField: "Authorization")
        redirected.setValue("session=fictional", forHTTPHeaderField: "Cookie")
        let task = session.dataTask(with: source)
        let response = HTTPURLResponse(url: source, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": redirected.url!.absoluteString])!
        let result: URLRequest? = await withCheckedContinuation { continuation in
            AIQuotaSessionDelegate(trustLoopback: false).urlSession(session, task: task,
                willPerformHTTPRedirection: response, newRequest: redirected) { continuation.resume(returning: $0) }
        }
        #expect(result == nil)
    }

    @Test
    func onlyTheExplicitIPv4LoopbackTLSChallengeMayUseLocalTrust() async throws {
        let certificate = try #require(SecCertificateCreateWithData(nil, AIQuotaTestCertificate.data as CFData))
        var trust: SecTrust?
        #expect(SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust) == errSecSuccess)
        let localTrust = try #require(trust)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        for (enabled, host) in [(true, "127.0.0.1"), (false, "127.0.0.1"), (true, "localhost"), (true, "127.0.0.1.example.test"), (true, "api.example.test")] {
            let space = AIQuotaTrustSpace(host: host, trust: localTrust)
            let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil,
                previousFailureCount: 0, failureResponse: nil, error: nil, sender: AIQuotaChallengeSender())
            let disposition = await withCheckedContinuation { continuation in
                AIQuotaSessionDelegate(trustLoopback: enabled).urlSession(session, didReceive: challenge) { disposition, _ in
                    continuation.resume(returning: disposition)
                }
            }
            #expect(disposition == (enabled && host == "127.0.0.1" ? .useCredential : .performDefaultHandling))
        }
    }

    @Test
    func proxyAppliesToRemoteServicesWhileLoopbackAndCredentialsStayIsolated() {
        let client = AIQuotaURLSessionClient(proxyURL: "http://127.0.0.1:18080", proxyEnabled: true)
        let remote = client.configuration(trustLoopback: false)
        let local = client.configuration(trustLoopback: true)
        #expect(remote.connectionProxyDictionary?.isEmpty == false)
        #expect(local.connectionProxyDictionary?.isEmpty == true)
        for configuration in [remote, local] {
            #expect(!configuration.httpShouldSetCookies)
            #expect(configuration.httpCookieStorage == nil)
            #expect(configuration.urlCache == nil)
            #expect(configuration.timeoutIntervalForResource == 25)
        }
    }
}

private final class AIQuotaURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var body = Data()
        var length: Int?
        var held = false
        var error: URLError?
    }

    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [URL: Reply] = [:]
        private var started: Set<URL> = []
        private var stopped: Set<URL> = []
        func register(_ reply: Reply, url: URL) { lock.withLock { replies[url] = reply } }
        func load(_ url: URL) -> Reply? { lock.withLock { started.insert(url); return replies[url] } }
        func stop(_ url: URL) { _ = lock.withLock { stopped.insert(url) } }
        func hasStarted(_ url: URL) -> Bool { lock.withLock { started.contains(url) } }
        func hasStopped(_ url: URL) -> Bool { lock.withLock { stopped.contains(url) } }
        func remove(_ url: URL) { lock.withLock { replies[url] = nil; started.remove(url); stopped.remove(url) } }
    }

    static let registry = Registry()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "aiquota.fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let reply = Self.registry.load(url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if let error = reply.error { client?.urlProtocol(self, didFailWithError: error); return }
        var headers = ["Content-Type": "application/json"]
        if let length = reply.length { headers["Content-Length"] = "\(length)" }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty { client?.urlProtocol(self, didLoad: reply.body) }
        if !reply.held { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { if let url = request.url { Self.registry.stop(url) } }
}

private final class AIQuotaTrustSpace: URLProtectionSpace, @unchecked Sendable {
    private let suppliedTrust: SecTrust
    init(host: String, trust: SecTrust) {
        suppliedTrust = trust
        super.init(host: host, port: 443, protocol: "https", realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust)
    }
    required init?(coder: NSCoder) { fatalError("Test protection spaces are not decoded") }
    override var serverTrust: SecTrust? { suppliedTrust }
}

private final class AIQuotaChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
