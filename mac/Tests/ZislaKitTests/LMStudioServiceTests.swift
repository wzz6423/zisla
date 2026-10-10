import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct LMStudioServiceTests {
    @Test
    func installedCatalogUsesModelIDsAndExcludesEmbeddings() async throws {
        let fixture = try LMStudioFixture()
        defer { fixture.remove() }
        let models = try await fixture.service.installedModels()
        #expect(models.map(\.name) == ["google/gemma-4", "qwen/qwen3.8-27b"])
    }

    @Test(arguments: ["http://127.0.0.1:1234", "http://localhost:2345/v1", "http://[::1]:1234/v1/"])
    func startsOnlyTheRequestedLoopbackListener(address: String) async throws {
        let fixture = try LMStudioFixture()
        defer { fixture.remove() }
        try await fixture.service.startServer(for: AIEndpoint(name: "LM Studio", baseURL: address))
        let expectedHost = address.contains("[::1]") ? "::1" : "127.0.0.1"
        let expectedPort = address.contains("2345") ? "2345" : "1234"
        #expect(Array(fixture.commands.suffix(6)) == ["server", "start", "--bind", expectedHost, "--port", expectedPort])
    }

    @Test(arguments: [
        "http://127.evil.example:1234/v1", "https://remote.example:1234/v1",
        "http://0.0.0.0:1234/v1", "http://192.168.0.1:1234/v1", "http://localhost/v1",
        "http://localhost:0/v1", "http://localhost:65536/v1", "http://localhost:1234/proxy/v1",
        "http://user:pass@localhost:1234/v1", "http://localhost:1234/v1#fragment",
        "http://localhost:1234/v1?query", "file:///v1", "not-a-url",
    ])
    func rejectsEndpointsThatCannotBeManagedLocally(address: String) async throws {
        let fixture = try LMStudioFixture()
        defer { fixture.remove() }
        await #expect(throws: AIModelDiscoveryError.self) {
            try await fixture.service.startServer(for: AIEndpoint(name: "LM Studio", baseURL: address))
        }
        #expect(fixture.commands.isEmpty)
    }

    @Test
    func doesNotReconfigureAnAlreadyRunningServer() async throws {
        let fixture = try LMStudioFixture(running: true)
        defer { fixture.remove() }
        try await fixture.service.startServer(for: AIEndpoint(name: "LM Studio", baseURL: "http://localhost:5678/v1"))
        #expect(fixture.commands == ["server", "status", "--json"])
    }

    @Test(arguments: ["{", "{}", #"[{"type":"llm","modelKey":42}]"#])
    func rejectsMalformedInstalledCatalogs(catalog: String) async throws {
        let fixture = try LMStudioFixture(catalog: catalog)
        defer { fixture.remove() }
        await #expect(throws: DecodingError.self) { try await fixture.service.installedModels() }
    }

    @Test
    func commandFailureDoesNotExposeCLIOutput() async throws {
        let fixture = try LMStudioFixture(script: "#!/bin/sh\necho secret-provider-detail >&2\nexit 17\n")
        defer { fixture.remove() }
        do {
            _ = try await fixture.service.installedModels()
            Issue.record("A failed CLI command must fail discovery")
        } catch {
            #expect(error is LMStudioServiceError)
            #expect(!error.localizedDescription.contains("secret-provider-detail"))
        }
    }

    @Test
    func stalledCLIIsTerminated() async throws {
        let fixture = try LMStudioFixture(script: "#!/bin/sh\ntrap 'exit 0' TERM\nwhile :; do :; done\n", timeout: 0.05)
        defer { fixture.remove() }
        await #expect(throws: LMStudioServiceError.self) { try await fixture.service.installedModels() }
    }
}

struct LMStudioFixture {
    let directory: URL
    let service: LMStudioService

    init(running: Bool = false, catalog: String? = nil, script: String? = nil, timeout: TimeInterval = 15) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-lms-test-\(UUID().uuidString)")
        let executable = directory.appendingPathComponent(".lmstudio/bin/lms")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let source = script ?? """
        #!/bin/sh
        printf '%s\\n' "$@" >> "$ZISLA_TEST_LMS_LOG"
        case "$1 $2" in
          'server status') /bin/cat "$ZISLA_TEST_LMS_STATUS" ;;
          'ls --llm') /bin/cat "$ZISLA_TEST_LMS_CATALOG" ;;
          'server start') exit 0 ;;
          *) exit 1 ;;
        esac
        """
        try source.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let statusURL = directory.appendingPathComponent("status.json")
        try "{\"running\":\(running),\"port\":1234}".write(to: statusURL, atomically: true, encoding: .utf8)
        let catalogURL = directory.appendingPathComponent("catalog.json")
        try (catalog ?? #"[{"type":"llm","modelKey":" qwen/qwen3.8-27b ","displayName":"Qwen3.8 27B"},{"type":"llm","modelKey":"qwen/qwen3.8-27b"},{"type":"llm","modelKey":"google/gemma-4"},{"type":"embedding","modelKey":"embedding-only"},{"type":"llm","modelKey":" "}]"#)
            .write(to: catalogURL, atomically: true, encoding: .utf8)
        service = LMStudioService(environment: [
            "ZISLA_TEST_LMS_LOG": directory.appendingPathComponent("commands.txt").path,
            "ZISLA_TEST_LMS_STATUS": statusURL.path,
            "ZISLA_TEST_LMS_CATALOG": catalogURL.path,
        ], homeDirectory: directory, timeout: timeout)
    }

    var commands: [String] {
        let contents = try? String(contentsOf: directory.appendingPathComponent("commands.txt"), encoding: .utf8)
        return contents?.split(separator: "\n").map(String.init) ?? []
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
