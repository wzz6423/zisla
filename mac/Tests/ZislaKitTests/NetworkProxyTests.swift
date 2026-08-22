import Foundation
import Testing

@testable import ZislaKit
@testable import ZislaCore

struct NetworkProxyTests {
    @Test
    func acceptsCompleteHTTPProxyURL() throws {
        let url = try #require(NetworkProxy.url(from: " http://127.0.0.1:7897 "))
        #expect(url.scheme == "http")
        #expect(url.host == "127.0.0.1")
        #expect(url.port == 7897)
    }

    @Test
    func rejectsIncompleteOrUnsupportedProxyURL() {
        #expect(NetworkProxy.url(from: "127.0.0.1:7897") == nil)
        #expect(NetworkProxy.url(from: "ftp://127.0.0.1:7897") == nil)
        #expect(NetworkProxy.url(from: "") == nil)
    }

    @Test
    func appliesProxyToBothShellVariableCases() {
        let environment = NetworkProxy.environment(
            from: "http://127.0.0.1:7897",
            base: ["PATH": "/bin", "http_proxy": "old"]
        )
        #expect(environment["PATH"] == "/bin")
        #expect(environment["http_proxy"] == "http://127.0.0.1:7897")
        #expect(environment["https_proxy"] == "http://127.0.0.1:7897")
        #expect(environment["HTTP_PROXY"] == "http://127.0.0.1:7897")
        #expect(environment["HTTPS_PROXY"] == "http://127.0.0.1:7897")
    }

    @Test
    func leavesEnvironmentUnchangedWhenProxyIsEmpty() {
        let environment = ["PATH": "/bin", "http_proxy": "system"]
        #expect(NetworkProxy.environment(from: "", base: environment) == environment)
    }

    @Test
    func disablesConfiguredProxyForShellCommands() {
        let environment = NetworkProxy.environment(
            from: "http://127.0.0.1:7897",
            enabled: false,
            base: [
                "PATH": "/bin",
                "http_proxy": "http://127.0.0.1:7897",
                "https_proxy": "http://127.0.0.1:7897",
                "ALL_PROXY": "socks5://127.0.0.1:7897",
            ]
        )
        #expect(environment == ["PATH": "/bin"])
    }

    @Test @MainActor
    func reportsDisabledAndInvalidProxyStates() {
        let monitor = NetworkProxyAvailabilityMonitor()

        monitor.check(urlString: "http://127.0.0.1:7897", enabled: false)
        #expect(monitor.availability == .disabled)

        monitor.check(urlString: "", enabled: true)
        #expect(monitor.availability == .notConfigured)

        monitor.check(urlString: "127.0.0.1:7897", enabled: true)
        #expect(monitor.availability == .invalid)
    }

    @Test
    func cliCommandReceivesConfiguredProxyEnvironment() async throws {
        let service = AIAgentCLIService(
            environment: ["PATH": "/usr/bin:/bin"],
            networkProxyURL: "http://127.0.0.1:7897"
        )
        let output = try await service.run(AIAgentCLICommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '%s|%s' \"$http_proxy\" \"$https_proxy\""]
        ))
        #expect(String(decoding: output.standardOutput, as: UTF8.self) == "http://127.0.0.1:7897|http://127.0.0.1:7897")
    }

    @Test
    func legacyProxyURLEnablesProxyByDefault() throws {
        let data = Data(#"{"activityNoticeDisplayDuration":"threeSeconds","networkProxyURL":"http://127.0.0.1:7897"}"#.utf8)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(settings.networkProxyEnabled)
    }
}
