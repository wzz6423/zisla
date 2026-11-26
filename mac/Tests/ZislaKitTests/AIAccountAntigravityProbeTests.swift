import Darwin
import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct AIAccountAntigravityProbeTests {
    @Test func processParserClassifiesAppCLIIDEAndGeminiAppInPriorityOrder() throws {
        let token = "ea1dbb2a-65a8-4766-a155-8e70f032f4ac"
        let stdout = [
            "111 /bin/bash --login",
            "700 /opt/imagytool/bin/run --serve",
            "701 /usr/local/bin/legacy-agent start",
            "703 /tools/watcher --exec \"/Users/example/.antigravity/agy\"",
            "70003 /Applications/Antigravity IDE.app/Contents/Resources/bin/language_server --csrf_token ide-tok --app_data_dir antigravity-ide",
            "70001 /Users/example/.antigravity/bin/agy language-server --stdio",
            "70002 /Applications/Gemini.app/Contents/Resources/bin/language_server_macos_arm --csrf_token gem-tok --app_data_dir antigravity",
            "70000 /Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone --csrf_token \(token) --app_data_dir antigravity --extension_server_port 12345 --extension_server_csrf_token ext-tok --hub-port 44444",
        ].joined(separator: "\n")

        let entries = try AIAccountAntigravityProbe.parseProcessList(stdout)
        #expect(entries.map(\.kind) == [.app, .app, .cli, .ide])
        #expect(entries.map(\.pid) == [70_000, 70_002, 70_001, 70_003])
        #expect(entries[0].csrfToken == token)
        #expect(entries[0].extensionPort == 12_345)
        #expect(entries[0].extensionCsrfToken == "ext-tok")
        #expect(entries[0].hubPort == 44_444)
        #expect(entries[2].csrfToken.isEmpty)
    }

    @Test func missingServerReturnsEmptyWhileTokenlessAppOrHubThrowsCredentialsUnavailable() throws {
        #expect(try AIAccountAntigravityProbe.parseProcessList("111 /bin/bash --login\n").isEmpty)
        #expect(throws: AIAccountBalanceError.credentialsUnavailable) {
            try AIAccountAntigravityProbe.parseProcessList(
                "53602 /Applications/Antigravity.app/Contents/Resources/bin/language_server --app_data_dir antigravity"
            )
        }
        #expect(throws: AIAccountBalanceError.credentialsUnavailable) {
            try AIAccountAntigravityProbe.parseProcessList(
                "9001 /Users/example/.antigravity/bin/agy --hub --hub-port=55555 --app_data_dir=antigravity"
            )
        }
    }

    @Test func desktopHubDiscoveryValidatesDescriptorsAndRequiresExactLoopbackListener() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-ag-hub-\(UUID())")
        let daemon = root.appendingPathComponent(".gemini/antigravity/daemon", isDirectory: true)
        try FileManager.default.createDirectory(at: daemon, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let csrf = "ea1dbb2a-65a8-4766-a155-8e70f032f4ac"
        try Data(#"{"pid":123,"httpPort":4242,"csrfToken":"\#(csrf)"}"#.utf8)
            .write(to: daemon.appendingPathComponent("hub_4242.json"))
        // Mismatched port must be rejected.
        try Data(#"{"pid":456,"httpPort":4244,"csrfToken":"\#(csrf)"}"#.utf8)
            .write(to: daemon.appendingPathComponent("hub_4243.json"))
        // Short non-hex token must be rejected.
        try Data(#"{"pid":789,"httpPort":4245,"csrfToken":"short"}"#.utf8)
            .write(to: daemon.appendingPathComponent("hub_4245.json"))
        // Oversized descriptor must be rejected.
        let oversize = #"{"pid":999,"httpPort":4246,"csrfToken":"\#(csrf)","pad":"\#(String(repeating: "a", count: 4_100))"}"#
        try Data(oversize.utf8).write(to: daemon.appendingPathComponent("hub_4246.json"))
        // Symlink descriptor must be rejected.
        let outside = root.appendingPathComponent("outside.json")
        try Data(#"{"pid":888,"httpPort":4247,"csrfToken":"\#(csrf)"}"#.utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: daemon.appendingPathComponent("hub_4247.json"), withDestinationURL: outside)

        let hubs = AIAccountAntigravityProbe.defaultReadDesktopHubs(home: root)
        #expect(Array(hubs.keys) == [123])
        #expect(hubs[123]?.httpPort == 4_242 && hubs[123]?.csrfToken == csrf)

        let cmd = "/Applications/Antigravity.app/Contents/Resources/bin/language_server --app_data_dir antigravity --read_host_bridge_token_from_stdin"
        let processes = try AIAccountAntigravityProbe.parseProcessList("123 \(cmd)\n456 \(cmd)\n789 \(cmd)\n888 \(cmd)", desktopHubs: hubs)
        #expect(processes.map(\.pid) == [123])
        #expect(AIAccountAntigravityProbe.endpointCandidates(for: processes[0], listeningPorts: [4_242, 9_000]) == [
            .init(scheme: "http", port: 4_242, csrfToken: csrf, desktopPID: 123),
        ])
        #expect(AIAccountAntigravityProbe.endpointCandidates(for: processes[0], listeningPorts: [9_000]).isEmpty)

        let lsof = [
            "server 123 user 3u IPv6 TCP [::1]:4242 (LISTEN)",
            "server 123 user 4u IPv4 TCP 192.0.2.1:4242 (LISTEN)",
            "server 123 user 5u IPv4 TCP 127.0.0.1:4321 (LISTEN)",
            "server 123 user 6u IPv4 TCP 127.0.0.1:4300->127.0.0.1:4242 (ESTABLISHED)",
        ].joined(separator: "\n")
        #expect(AIAccountAntigravityProbe.parseListeningPorts(lsof, ipv4LoopbackOnly: true) == [4_321])
        #expect(AIAccountAntigravityProbe.parseListeningPorts(lsof, ipv4LoopbackOnly: false) == [4_242, 4_321])
    }

    @Test func verifiedLoopbackSocketSendsZeroBytesWhenPeerIsUnownedAndSucceedsAfterOwnershipCheck() async throws {
        // Unowned peer must never receive any bytes or the CSRF token.
        let unownedServer = try LoopbackStubServer(response: Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}".utf8))
        defer { unownedServer.close() }
        await #expect(throws: AIAccountBalanceError.noQuota) {
            try await AIAccountAntigravityProbe.callVerifiedLoopbackHTTP(
                port: unownedServer.port,
                pid: 999_999,
                csrfToken: "fixture-secret-csrf-token",
                method: "RetrieveUserQuotaSummary",
                payload: Data("{}".utf8),
                timeout: 3,
                verifySocketOwner: { _, _, _ in false }
            )
        }
        let leaked = await unownedServer.receivedData()
        #expect(leaked.isEmpty, "Unowned loopback socket must receive zero bytes")

        // Owned peer receives request only after verification and handles chunked transfer encoding.
        let body = #"{"verified":true}"#
        let chunked = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: application/json\r\n\r\n\(String(body.utf8.count, radix: 16))\r\n\(body)\r\n0\r\n\r\n"
        let ownedServer = try LoopbackStubServer(response: Data(chunked.utf8))
        defer { ownedServer.close() }
        let response = try await AIAccountAntigravityProbe.callVerifiedLoopbackHTTP(
            port: ownedServer.port,
            pid: Int(getpid()),
            csrfToken: "fixture-verified-token",
            method: "RetrieveUserQuotaSummary",
            payload: Data(#"{"forceRefresh":true}"#.utf8),
            timeout: 3,
            verifySocketOwner: { port, _, localPort in
                #expect(port == ownedServer.port && localPort > 0)
                return true
            }
        )
        #expect(response.statusCode == 200)
        #expect(String(data: response.body, encoding: .utf8) == body)
        let received = String(data: await ownedServer.receivedData(), encoding: .utf8) ?? ""
        #expect(received.contains("POST /exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary HTTP/1.1"))
        #expect(received.contains("x-codeium-csrf-token: fixture-verified-token"))
        #expect(received.contains("Connect-Protocol-Version: 1"))
    }

    @Test func probePrefersGroupedSummaryEnrichesIdentityAndFallsBackAcrossProcessKinds() async throws {
        let token = "ea1dbb2a-65a8-4766-a155-8e70f032f4ac"
        let psOut = [
            "30 /Applications/Antigravity IDE.app/Contents/Resources/bin/language_server --csrf_token ide-tok --app_data_dir antigravity-ide",
            "20 /Users/example/.antigravity/bin/agy language-server --stdio",
            "10 /Applications/Antigravity.app/Contents/Resources/bin/language_server --csrf_token \(token) --app_data_dir antigravity",
        ].joined(separator: "\n")
        let calls = LockedCalls()
        let probe = AIAccountAntigravityProbe(
            home: URL(fileURLWithPath: "/fixture"),
            runCommand: { path, args, _ in
                if path == "/bin/ps" { return (0, psOut, "") }
                if path == "/usr/sbin/lsof", let pid = args.last {
                    return (0, "ls \(pid) user 6u IPv4 0x0 0t0 TCP 127.0.0.1:\(pid)00 (LISTEN)\n", "")
                }
                return (1, "", "")
            },
            readDesktopHubs: { _ in [:] },
            rpcCall: { candidate, method, _, _ in
                calls.append("\(candidate.port):\(candidate.scheme):\(method)")
                if candidate.port == 1_000, method == "RetrieveUserQuotaSummary" {
                    // Disabled bucket only -> unusable, must fall back to CLI.
                    return .init(statusCode: 200, body: Data(#"{"groups":[{"displayName":"Gemini Models","buckets":[{"window":"weekly","remainingFraction":0.5,"disabled":true}]}]}"#.utf8))
                }
                if candidate.port == 2_000, method == "RetrieveUserQuotaSummary" {
                    return .init(statusCode: 200, body: Data(#"{"groups":[{"displayName":"Gemini Models","buckets":[{"window":"5h","remainingFraction":0.8},{"window":"weekly","remainingFraction":0.7}]}]}"#.utf8))
                }
                if candidate.port == 2_000, method == "GetUserStatus" {
                    return .init(statusCode: 200, body: Data(#"{"userStatus":{"email":"CLI@Example.test","userTier":{"name":"Google AI Pro"}}}"#.utf8))
                }
                return .init(statusCode: 200, body: Data("{}".utf8))
            }
        )

        let snapshot = try #require(try await probe.probe())
        #expect(snapshot.sourceDetail == .cli)
        #expect(snapshot.accountID == "cli@example.test")
        #expect(snapshot.accountName == "cli@example.test")
        #expect(snapshot.windows.map(\.remainingPercent) == [80, 70])
        #expect(calls.values.allSatisfy { !$0.hasPrefix("3000:") }, "Must stop once CLI succeeds without probing IDE")
    }

    @Test func probeClassifiesCSRFErrorBodyAsCredentialsExpiredAndIsolatesExtensionTokenFailure() async throws {
        let psOut = "10 /Applications/Antigravity.app/Contents/Resources/bin/language_server --csrf_token primary-tok --app_data_dir antigravity --extension_server_port 9999 --extension_server_csrf_token alt-tok"
        let probe = AIAccountAntigravityProbe(
            home: URL(fileURLWithPath: "/fixture"),
            runCommand: { path, _, _ in
                if path == "/bin/ps" { return (0, psOut, "") }
                return (0, "ls 10 user 6u IPv4 0x0 0t0 TCP 127.0.0.1:5000 (LISTEN)\n", "")
            },
            readDesktopHubs: { _ in [:] },
            rpcCall: { candidate, method, _, _ in
                if method == "RetrieveUserQuotaSummary", candidate.port == 5_000 {
                    return .init(statusCode: 400, body: Data(#"{"code":"invalid_argument","message":"missing CSRF token"}"#.utf8))
                }
                return .init(statusCode: 500, body: Data("{}".utf8))
            }
        )
        await #expect(throws: AIAccountBalanceError.credentialsExpired) {
            try await probe.probe()
        }

        // Only alternate extension token returns 401 while primary port is down -> must not surface as expired login.
        let extensionOnly = AIAccountAntigravityProbe(
            home: URL(fileURLWithPath: "/fixture"),
            runCommand: { path, _, _ in
                if path == "/bin/ps" { return (0, psOut, "") }
                return (0, "", "")
            },
            readDesktopHubs: { _ in [:] },
            rpcCall: { _, method, _, _ in
                if method == "RetrieveUserQuotaSummary" {
                    return .init(statusCode: 401, body: Data("nope".utf8))
                }
                return .init(statusCode: 500, body: Data("{}".utf8))
            }
        )
        await #expect(throws: AIAccountBalanceError.noQuota) {
            try await extensionOnly.probe()
        }
    }
}

private final class LockedCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var values: [String] { lock.withLock { storage } }
    func append(_ value: String) { lock.withLock { storage.append(value) } }
}

private final class LoopbackStubServer: @unchecked Sendable {
    let port: Int
    private let listenFD: Int32
    private let lock = NSLock()
    private var received = Data()
    private let group = DispatchGroup()

    init(response: Data) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AIAccountBalanceError.noQuota }
        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 4) == 0 else {
            Darwin.close(fd)
            throw AIAccountBalanceError.noQuota
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        listenFD = fd
        port = Int(UInt16(bigEndian: actual.sin_port))
        group.enter()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { self?.group.leave() }
            let client = Darwin.accept(fd, nil, nil)
            guard client >= 0 else { return }
            defer { Darwin.close(client) }
            var tv = timeval(tv_sec: 1, tv_usec: 0)
            _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var buffer = [UInt8](repeating: 0, count: 4_096)
            var collected = Data()
            while true {
                let count = Darwin.recv(client, &buffer, buffer.count, 0)
                if count <= 0 { break }
                collected.append(contentsOf: buffer.prefix(count))
                if collected.range(of: Data("\r\n\r\n".utf8)) != nil { break }
            }
            self?.lock.withLock { self?.received = collected }
            if !collected.isEmpty {
                _ = response.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return 0 }
                    return Darwin.send(client, base, raw.count, 0)
                }
            }
        }
    }

    func receivedData() async -> Data {
        await withCheckedContinuation { continuation in
            group.notify(queue: .global(qos: .utility)) {
                continuation.resume(returning: self.lock.withLock { self.received })
            }
        }
    }

    func close() {
        Darwin.close(listenFD)
    }
}
