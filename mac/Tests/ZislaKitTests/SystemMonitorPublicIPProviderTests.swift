import Foundation
import Testing

@testable import ZislaKit

@Suite(.serialized)
struct SystemMonitorPublicIPProviderTests {
    @Test
    func ipv4UsesTheIPv4OnlyEndpoint() async throws {
        let session = makeSession(responses: [
            "api.ipify.org": .body(200, #"{"ip":"203.0.113.8"}"#),
        ])
        defer { session.invalidateAndCancel() }

        let address = await DefaultPublicIPProvider(session: session).publicIPAddress()

        #expect(address == .address("203.0.113.8"))
        let request = try #require(PublicIPURLProtocol.requests.first)
        #expect(request.url?.host == "api.ipify.org")
        #expect(request.url?.query == "format=json")
        #expect(request.timeoutInterval == 5)
    }

    @Test(arguments: ["2001:db8::8", "2001:db8:0:0:0:0:0:8"])
    func ipv6UsesTheIPv6OnlyEndpoint(address: String) async throws {
        let session = makeSession(responses: [
            "api6.ipify.org": .body(200, "{\"ip\":\"\(address)\"}"),
        ])
        defer { session.invalidateAndCancel() }

        #expect(await DefaultPublicIPProvider(session: session).publicIPv6Address() == .address(address))
        let request = try #require(PublicIPURLProtocol.requests.first)
        #expect(request.url?.host == "api6.ipify.org")
        #expect(request.url?.query == "format=json")
        #expect(request.timeoutInterval == 5)
    }

    @Test(arguments: [
        "not-json", "{}", #"{"ip":""}"#, #"{"ip":"invalid"}"#,
        #"{"ip":"2001:db8::8"}"#, #"{"ip":"203.0.113.999"}"#,
        #"{"ip":"203.0.113.8\u0000invalid"}"#,
    ])
    func ipv4RejectsMalformedOrWrongFamilyResponses(body: String) async {
        let session = makeSession(responses: ["api.ipify.org": .body(200, body)])
        defer { session.invalidateAndCancel() }

        #expect(await provider(session: session, routable: true).publicIPAddress() == .failed)
    }

    @Test(arguments: [
        "not-json", "{}", #"{"ip":""}"#, #"{"ip":"invalid"}"#,
        #"{"ip":"203.0.113.8"}"#, #"{"ip":"2001:db8:::8"}"#,
        #"{"ip":"2001:db8::8\u0000invalid"}"#,
    ])
    func ipv6RejectsMalformedOrWrongFamilyResponses(body: String) async {
        let session = makeSession(responses: ["api6.ipify.org": .body(200, body)])
        defer { session.invalidateAndCancel() }

        #expect(await provider(session: session, routable: true).publicIPv6Address() == .failed)
    }

    @Test(arguments: [true, false])
    func aFailedFamilyDoesNotHideTheOtherAddress(ipv4Fails: Bool) async {
        let session = makeSession(responses: [
            "api.ipify.org": ipv4Fails ? .failure(.timedOut) : .body(200, #"{"ip":"203.0.113.8"}"#),
            "api6.ipify.org": ipv4Fails ? .body(200, #"{"ip":"2001:db8::8"}"#) : .failure(.notConnectedToInternet),
        ])
        defer { session.invalidateAndCancel() }
        let provider = provider(session: session, routable: true)
        async let ipv4 = provider.publicIPAddress()
        async let ipv6 = provider.publicIPv6Address()

        #expect(await ipv4 == (ipv4Fails ? .failed : .address("203.0.113.8")))
        #expect(await ipv6 == (ipv4Fails ? .address("2001:db8::8") : .failed))
    }

    @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet, .cancelled])
    func unavailableNetworkProducesNoAddress(error: URLError.Code) async {
        let session = makeSession(responses: ["api.ipify.org": .failure(error)])
        defer { session.invalidateAndCancel() }

        #expect(await provider(session: session, routable: true).publicIPAddress() == .failed)
    }

    @Test
    func unsuccessfulHTTPResponseDoesNotPublishItsBody() async {
        let session = makeSession(responses: [
            "api.ipify.org": .body(503, #"{"ip":"203.0.113.8"}"#),
        ])
        defer { session.invalidateAndCancel() }

        #expect(await provider(session: session, routable: true).publicIPAddress() == .failed)
    }

    @Test
    func aFailedLookupIsAbsenceOnlyWhenThisHostHasNoRoutableAddress() async {
        let session = makeSession(responses: [
            "api.ipify.org": .failure(.timedOut),
            "api6.ipify.org": .failure(.cannotConnectToHost),
        ])
        defer { session.invalidateAndCancel() }
        let lookup = provider(session: session, routable: false)

        #expect(await lookup.publicIPAddress() == .absent)
        #expect(await lookup.publicIPv6Address() == .absent)
    }

    @Test(arguments: [
        ("203.0.113.8", AF_INET, true),
        ("10.1.2.3", AF_INET, true),
        ("10.1.2", AF_INET, false),
        ("nope", AF_INET, false),
        ("127.0.0.1", AF_INET, false),
        ("169.254.1.1", AF_INET, false),
        ("0.0.0.0", AF_INET, false),
        ("2001:db8::8", AF_INET6, true),
        ("2001:db8::8%en0", AF_INET6, true),
        ("fe80::1%en0", AF_INET6, false),
        ("::1", AF_INET6, false),
        ("fd00::1", AF_INET6, false),
    ])
    func routableInterfaceAddressesExcludeLoopbackLinkLocalAndUniqueLocal(
        address: String, family: Int32, routable: Bool
    ) {
        #expect(SystemSampler.isRoutableInterfaceAddress(address, family: family) == routable)
    }

    @Test
    func aFailedInterfaceListingDoesNotLookLikeAMissingAddressFamily() {
        #expect(SystemSampler.hasRoutableAddress(family: AF_INET, addresses: nil))
        #expect(!SystemSampler.hasRoutableAddress(family: AF_INET6, addresses: []))
        #expect(!SystemSampler.hasRoutableAddress(family: AF_INET, addresses: ["169.254.1.1", "127.0.0.1"]))
        #expect(SystemSampler.hasRoutableAddress(family: AF_INET, addresses: ["10.0.0.8"]))
        #expect(SystemSampler.hasRoutableAddress(family: AF_INET6, addresses: ["fe80::1%en0", "2001:db8::8"]))
    }

    private func provider(session: URLSession, routable: Bool) -> DefaultPublicIPProvider {
        DefaultPublicIPProvider(session: session, hasRoutableAddress: { _ in routable })
    }

    private func makeSession(responses: [String: PublicIPURLProtocol.Response]) -> URLSession {
        PublicIPURLProtocol.reset(responses: responses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PublicIPURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class PublicIPURLProtocol: URLProtocol, @unchecked Sendable {
    enum Response: Sendable {
        case body(Int, String)
        case failure(URLError.Code)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Response] = [:]
    nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []

    static var requests: [URLRequest] { lock.withLock { capturedRequests } }

    static func reset(responses: [String: Response]) {
        lock.withLock {
            Self.responses = responses
            capturedRequests = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = Self.lock.withLock {
            Self.capturedRequests.append(request)
            return Self.responses[request.url!.host!] ?? .body(404, "{}")
        }
        switch response {
        case let .body(status, body):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: URLError(error))
        }
    }

    override func stopLoading() {}
}
