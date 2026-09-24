import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct AIQuotaAntigravityTests {
    private let processLine = "123 /Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm --csrf_token=fictional-csrf"

    @Test
    func discoveryLimitsItselfToIDEProcessesAndValidUniqueListeningPorts() {
        let other = "777 /tmp/language_server --csrf_token=other\n"
        let script = "999 /Applications/Antigravity.app/bin/unrelated --csrf_token=no\n"
        #expect(AIQuotaAntigravityClient.candidates(other + script + processLine) == [.init(pid: 123, token: "fictional-csrf")])
        #expect(AIQuotaAntigravityClient.ports("p123\nn127.0.0.1:5000\nn*:5000\nn[::1]:6000\nn*:999999\nf12") == [5000, 6000])
    }

    @Test
    func aDiscoveredClientUsesOnlyLoopbackRPCWithItsCSRFToken() async throws {
        let http = AIQuotaMockHTTP([.success(AIQuotaFixtures.reference["antigravity-quota"]!)])
        let line = processLine
        let client = AIQuotaAntigravityClient(http: http, clock: { AIQuotaFixtures.now }, run: { executable, arguments in
            if executable.lastPathComponent == "ps" {
                #expect(arguments.contains("-U"))
                return line
            }
            #expect(arguments.contains("123"))
            return "p123\nn127.0.0.1:5100"
        })
        let data = try await client.read()
        #expect(data == AIQuotaFixtures.reference["antigravity-quota"])
        let request = try #require(await http.requests.first)
        #expect(request.url?.absoluteString == "https://127.0.0.1:5100/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == Data("{}".utf8))
        #expect(request.value(forHTTPHeaderField: "x-codeium-csrf-token") == "fictional-csrf")
        #expect(request.timeoutInterval == 2)
        #expect(await http.trustedLoopback == [true])
    }

    @Test(arguments: [AIQuotaError.credentialRejected, .network, .invalidResponse, .noQuota])
    func runningClientFailuresDoNotClaimTheApplicationIsMissing(_ error: AIQuotaError) async {
        let http = AIQuotaMockHTTP([.failure(error)])
        let line = processLine
        let client = AIQuotaAntigravityClient(http: http, run: { executable, _ in
            executable.lastPathComponent == "ps" ? line : "n127.0.0.1:5100"
        })
        await #expect(throws: error) { try await client.read() }
    }

    @Test
    func absentClientAndAbsentListeningPortRemainDistinctFailures() async {
        let http = AIQuotaMockHTTP([])
        let missing = AIQuotaAntigravityClient(http: http, run: { _, _ in "" })
        await #expect(throws: AIQuotaError.clientUnavailable) { try await missing.read() }
        let line = processLine
        let offline = AIQuotaAntigravityClient(http: http, run: { executable, _ in executable.lastPathComponent == "ps" ? line : "" })
        await #expect(throws: AIQuotaError.network) { try await offline.read() }
        #expect(await http.requests.isEmpty)
    }

    @Test
    func probingIsBoundedToEightRPCRequests() async {
        let http = AIQuotaMockHTTP(Array(repeating: .failure(.network), count: 8))
        let line = processLine
        let ports = (5000..<5100).map { "n127.0.0.1:\($0)" }.joined(separator: "\n")
        let client = AIQuotaAntigravityClient(http: http, run: { executable, _ in executable.lastPathComponent == "ps" ? line : ports })
        await #expect(throws: AIQuotaError.network) { try await client.read() }
        #expect(await http.requests.count == 8)
    }
}
