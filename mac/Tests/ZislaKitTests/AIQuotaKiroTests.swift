import Darwin
import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
struct AIQuotaKiroTests {
    @Test
    func fakeClientHandshakesBeforeUsageDrainsStderrAndExits() async throws {
        let fixture = try AIQuotaFakeKiro.make(mode: "stderr")
        defer { fixture.cleanUp() }
        let client = AIQuotaKiroClient(executable: fixture.executable, requestTimeout: .seconds(10), environment: fixture.environment)
        let data = try await client.usage()
        #expect(try AIQuotaResponseParser.parse(.kiro, replies: ["main": data], now: AIQuotaFixtures.now).windows.count == 2)
        let log = try String(contentsOf: fixture.directory.appendingPathComponent("requests"), encoding: .utf8)
        let messages = try log.split(separator: "\n").map { try AIQuotaResponseParser.object(Data($0.utf8)) }
        #expect(messages.compactMap { $0["method"] as? String } == ["initialize", "_kiro/account/getUsage"])
        let initialization = try #require(messages.first?["params"] as? [String: Any])
        #expect((initialization["clientInfo"] as? [String: Any])?["name"] as? String == "Zisla")
        #expect(try String(contentsOf: fixture.directory.appendingPathComponent("arguments"), encoding: .utf8) == "acp --agent-engine v3 --auth-method cli")
        #expect(await fixture.waitUntilExited())
    }

    @Test
    func providerReaderUsesItsConfiguredExecutableWithoutReadingCredentials() async throws {
        let fixture = try AIQuotaFakeKiro.make(mode: "normal")
        defer { fixture.cleanUp() }
        let credentials = AIQuotaMemoryCredentials()
        credentials.rejectReads = true
        var configuration = AIQuotaConfiguration(id: "kiro-test", provider: .kiro)
        configuration.localPath = fixture.executable.path
        let http = AIQuotaMockHTTP([])
        let reader = AIQuotaProviderReader(configuration: configuration, credentials: credentials, http: http, processEnvironment: fixture.environment)
        #expect(try await reader.read().first?.windows.count == 2)
        #expect(credentials.readIDs.isEmpty)
        #expect(await http.requests.isEmpty)
        #expect(await fixture.waitUntilExited())
    }

    @Test
    func cancellationKillsAnOwnedClientThatIgnoresTermination() async throws {
        let fixture = try AIQuotaFakeKiro.make(mode: "cancel")
        defer { fixture.cleanUp() }
        var configuration = AIQuotaConfiguration(provider: .kiro)
        configuration.localPath = fixture.executable.path
        let reader = AIQuotaProviderReader(configuration: configuration, credentials: AIQuotaMemoryCredentials(), http: AIQuotaMockHTTP([]), processEnvironment: fixture.environment)
        let task = Task { try await reader.read() }
        #expect(await fixture.waitForUsageRequest())
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await fixture.waitUntilExited())
    }

    @Test
    func timedOutClientIsStoppedEvenWhenItIgnoresTermination() async throws {
        let fixture = try AIQuotaFakeKiro.make(mode: "timeout")
        defer { fixture.cleanUp() }
        let client = AIQuotaKiroClient(executable: fixture.executable, requestTimeout: .milliseconds(500), environment: fixture.environment)
        await #expect(throws: AIQuotaKiroClient.Failure.timedOut) { try await client.usage() }
        #expect(await fixture.waitUntilExited())
    }

    @Test
    func oversizedClientOutputIsBoundedAndItsProcessExits() async throws {
        let fixture = try AIQuotaFakeKiro.make(mode: "oversize")
        defer { fixture.cleanUp() }
        let client = AIQuotaKiroClient(executable: fixture.executable, requestTimeout: .seconds(10), environment: fixture.environment)
        await #expect(throws: AIQuotaKiroClient.Failure.closed) { try await client.usage() }
        #expect(await fixture.waitUntilExited())
    }

    @Test
    func serverMessagesDoNotEscapeIntoTheUserFacingFailure() async throws {
        let fixture = try AIQuotaFakeKiro.make(mode: "server")
        defer { fixture.cleanUp() }
        var configuration = AIQuotaConfiguration(provider: .kiro)
        configuration.localPath = fixture.executable.path
        let reader = AIQuotaProviderReader(configuration: configuration, credentials: AIQuotaMemoryCredentials(), http: AIQuotaMockHTTP([]), processEnvironment: fixture.environment)
        await #expect(throws: AIQuotaError.server) { try await reader.read() }
        #expect(!AIQuotaError.server.localizedDescription.contains("fictional-sensitive"))
        #expect(await fixture.waitUntilExited())
    }
}

private struct AIQuotaFakeKiro: Sendable {
    let directory: URL
    let executable: URL
    let environment: [String: String]

    static func make(mode: String) throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AIQuotaFakeKiro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("kiro-cli")
        let script = #"""
        #!/bin/sh
        printf '%s' "$$" > "$AIQUOTA_PID"
        printf '%s' "$*" > "$AIQUOTA_ARGUMENTS"
        if [ "$AIQUOTA_MODE" = stderr ]; then
          i=0
          while [ "$i" -lt 3000 ]; do printf '%096d\n' "$i" >&2; i=$((i + 1)); done
        fi
        while IFS= read -r line; do
          printf '%s\n' "$line" >> "$AIQUOTA_REQUESTS"
          case "$line" in
            *'"method":"initialize"'*)
              if [ "$AIQUOTA_MODE" = timeout ]; then
                trap '' TERM
                while :; do :; done
              fi
              if [ "$AIQUOTA_MODE" = oversize ]; then /bin/cat "$AIQUOTA_BLOB"; continue; fi
              if [ "$AIQUOTA_MODE" = server ]; then
                printf '%s\n' '{"jsonrpc":"2.0","id":1,"error":{"message":"fictional-sensitive-server-error"}}'
              else
                printf '%s\n' '{"jsonrpc":"2.0","id":99,"result":{}}'
                printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}'
              fi
              ;;
            *getUsage*)
              if [ "$AIQUOTA_MODE" = cancel ]; then
                trap '' TERM
                while :; do :; done
              fi
              printf '{"jsonrpc":"2.0","id":2,"result":%s}\n' "$AIQUOTA_USAGE"
              ;;
          esac
        done
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let blob = directory.appendingPathComponent("oversize-data")
        if mode == "oversize" { try Data(repeating: 65, count: 2 * 1_024 * 1_024 + 1).write(to: blob) }
        let environment = [
            "HOME": directory.path, "PATH": "/usr/bin:/bin", "AIQUOTA_MODE": mode,
            "AIQUOTA_PID": directory.appendingPathComponent("pid").path,
            "AIQUOTA_ARGUMENTS": directory.appendingPathComponent("arguments").path,
            "AIQUOTA_REQUESTS": directory.appendingPathComponent("requests").path,
            "AIQUOTA_BLOB": blob.path,
            "AIQUOTA_USAGE": String(decoding: AIQuotaFixtures.reference["kiro-pro-plus-usage"]!, as: UTF8.self),
        ]
        return Self(directory: directory, executable: executable, environment: environment)
    }

    private var pid: Int32? {
        guard let value = try? String(contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8) else { return nil }
        return Int32(value)
    }

    func waitForUsageRequest() async -> Bool {
        for _ in 0..<200 {
            let value = try? String(contentsOf: directory.appendingPathComponent("requests"), encoding: .utf8)
            if value?.contains("getUsage") == true { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    func waitUntilExited() async -> Bool {
        for _ in 0..<1_000 {
            if let pid, Darwin.kill(pid, 0) != 0 && errno == ESRCH { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    func cleanUp() {
        if let pid, Darwin.kill(pid, 0) == 0 { Darwin.kill(pid, SIGKILL) }
        try? FileManager.default.removeItem(at: directory)
    }
}
