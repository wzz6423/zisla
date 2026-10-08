import Foundation
import ZislaCore

enum LMStudioServiceError: LocalizedError {
    case unavailable
    case commandFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            AppLocalization.text("未找到 LM Studio CLI。请在 LM Studio 中启动 API 服务后重试。")
        case .commandFailed:
            AppLocalization.text("LM Studio 操作失败，请在 LM Studio 中检查本地服务后重试。")
        }
    }
}

struct LMStudioService: Sendable {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let timeout: TimeInterval

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeout: TimeInterval = 15
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.timeout = timeout
    }

    static func serverAddress(for endpoint: AIEndpoint) -> (host: String, port: Int)? {
        guard endpoint.kind == .openAICompatible,
              let components = URLComponents(string: endpoint.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "http",
              let host = components.host?.lowercased(),
              ["127.0.0.1", "localhost", "[::1]", "::1"].contains(host),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              ["", "/", "/v1", "/v1/"].contains(components.path),
              let port = components.port, (1...65535).contains(port) else {
            return nil
        }
        return (host.contains(":") ? "::1" : "127.0.0.1", port)
    }

    func installedModels() async throws -> [AIDiscoveredModel] {
        let data = try await run(["ls", "--llm", "--json"])
        let models = try JSONDecoder().decode([InstalledModel].self, from: data)
        return AIModelDiscoveryService.normalizedModels(models.filter { $0.type == "llm" }.map(\.modelKey))
    }

    func isServerRunning() async throws -> Bool {
        let data = try await run(["server", "status", "--json"])
        return try JSONDecoder().decode(ServerStatus.self, from: data).running
    }

    func startServer(for endpoint: AIEndpoint) async throws {
        guard let address = Self.serverAddress(for: endpoint) else {
            throw AIModelDiscoveryError.invalidEndpoint(endpoint.baseURL)
        }
        // A running server may serve another client on a different port; do not reconfigure it.
        guard try await !isServerRunning() else { return }
        _ = try await run(["server", "start", "--bind", address.host, "--port", String(address.port)])
    }

    private func run(_ arguments: [String]) async throws -> Data {
        let bundled = homeDirectory.appendingPathComponent(".lmstudio/bin/lms")
        let executable = FileManager.default.isExecutableFile(atPath: bundled.path)
            ? bundled
            : AIAgentCLIService(environment: environment, homeDirectory: homeDirectory).executable(named: "lms")
        guard let executable else { throw LMStudioServiceError.unavailable }
        let result = try await AIAgentProcessRunner.run(
            executableURL: executable,
            arguments: arguments,
            environment: environment,
            workingDirectoryURL: homeDirectory,
            timeout: timeout,
            maximumOutputBytes: 4 * 1024 * 1024,
            maximumErrorBytes: 4096
        )
        guard !result.didTimeout, result.status == 0 else { throw LMStudioServiceError.commandFailed }
        return result.standardOutput
    }

    private struct InstalledModel: Decodable {
        var type: String
        var modelKey: String
    }

    private struct ServerStatus: Decodable {
        var running: Bool
    }
}
