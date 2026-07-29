import Foundation
import Darwin
import ZislaCore

public enum AIAgentServiceError: LocalizedError, Sendable {
    case invalidBaseURL(String)
    case missingAPIKey
    case unsupportedBalanceProbe
    case invalidScript(String)
    case scriptFailed(String)
    case invalidResponse
    case http(statusCode: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidBaseURL(value): "渠道地址无效：\(value)"
        case .missingAPIKey: "账号未配置 API Key"
        case .unsupportedBalanceProbe: "当前余额检测方式不支持该渠道"
        case let .invalidScript(path): "余额脚本不可执行：\(path)"
        case let .scriptFailed(detail): "余额脚本执行失败：\(detail)"
        case .invalidResponse: "渠道返回了无法识别的结果"
        case let .http(statusCode, body): "渠道请求失败（HTTP \(statusCode)）：\(body.prefix(180))"
        }
    }
}

private enum AIAgentURLBuilder {
    static func url(
        baseURL: String,
        pathComponents: [String],
        dropVersionComponent: Bool = false
    ) throws -> URL {
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URL(string: raw), let scheme = url.scheme,
              scheme == "http" || scheme == "https" else {
            throw AIAgentServiceError.invalidBaseURL(raw)
        }
        if dropVersionComponent,
           url.lastPathComponent.lowercased().hasPrefix("v") {
            url.deleteLastPathComponent()
        }
        let existing = url.path.split(separator: "/").map(String.init)
        for component in pathComponents {
            if existing.last?.lowercased() == component.lowercased() { continue }
            url.appendPathComponent(component)
        }
        return url
    }

    static func versionedURL(baseURL: String, pathComponents: [String]) throws -> URL {
        var url = try url(baseURL: baseURL, pathComponents: [])
        let existing = url.path.split(separator: "/").map(String.init)
        if !existing.contains(where: { $0.lowercased().hasPrefix("v") }) {
            url.appendPathComponent("v1", isDirectory: true)
        }
        for component in pathComponents {
            url.appendPathComponent(component)
        }
        return url
    }

    static func request(
        url: URL,
        apiKey: String,
        protocolKind: AgentChannelProtocol,
        method: String = "GET"
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch protocolKind {
        case .openAICompatible:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropicMessages:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .geminiGenerateContent:
            break
        }
        return request
    }
}

public struct AIAgentBalanceService: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func check(
        account: AgentAccount,
        baseURL: String,
        apiKey: String,
        cliProfileContents: (configuration: Data, authentication: Data)? = nil
    ) async throws -> AgentBalanceSnapshot {
        guard let probe = account.balanceProbe else {
            throw AIAgentServiceError.unsupportedBalanceProbe
        }
        switch probe.kind {
        case .openAICredits:
            return try await openAICredits(baseURL: baseURL, apiKey: apiKey)
        case .anthropicUsage:
            return try await anthropicUsage(baseURL: baseURL, apiKey: apiKey)
        case .newAPIQuota:
            return try await newAPIQuota(baseURL: baseURL, apiKey: apiKey)
        case .customScript:
            guard let path = probe.scriptPath else {
                throw AIAgentServiceError.invalidScript("")
            }
            return try await customScript(
                path: path,
                account: account,
                baseURL: baseURL,
                apiKey: apiKey,
                cliProfileContents: cliProfileContents
            )
        }
    }

    private func openAICredits(baseURL: String, apiKey: String) async throws -> AgentBalanceSnapshot {
        let url = try AIAgentURLBuilder.url(
            baseURL: baseURL,
            pathComponents: ["dashboard", "billing", "credit_grants"],
            dropVersionComponent: true
        )
        var request = AIAgentURLBuilder.request(
            url: url,
            apiKey: apiKey,
            protocolKind: .openAICompatible
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let object = try await jsonObject(for: request)
        let total = Self.number(in: object, keys: ["total_available", "total_granted"])
        let used = Self.number(in: object, keys: ["total_used"])
        let available = Self.number(in: object, keys: ["total_available"]) ?? total.map { ($0 - (used ?? 0)).rounded(toPlaces: 6) }
        return AgentBalanceSnapshot(available: available, used: used, currency: "USD")
    }

    private func anthropicUsage(baseURL: String, apiKey: String) async throws -> AgentBalanceSnapshot {
        var url = try AIAgentURLBuilder.versionedURL(
            baseURL: baseURL,
            pathComponents: ["organizations", "usage_report"]
        )
        let now = Date()
        let start = now.addingTimeInterval(-24 * 60 * 60)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let formatter = ISO8601DateFormatter()
        components?.queryItems = [
            URLQueryItem(name: "starting_at", value: formatter.string(from: start)),
            URLQueryItem(name: "ending_at", value: formatter.string(from: now)),
        ]
        url = components?.url ?? url
        let request = AIAgentURLBuilder.request(
            url: url,
            apiKey: apiKey,
            protocolKind: .anthropicMessages
        )
        let object = try await jsonObject(for: request)
        let used = Self.sumNumbers(named: "input_tokens", in: object)
            + Self.sumNumbers(named: "output_tokens", in: object)
        return AgentBalanceSnapshot(
            available: nil,
            used: used == 0 ? nil : used,
            currency: "tokens",
            detail: "最近 24 小时官方用量；Anthropic 不提供余额字段"
        )
    }

    private func newAPIQuota(baseURL: String, apiKey: String) async throws -> AgentBalanceSnapshot {
        let url = try AIAgentURLBuilder.url(
            baseURL: baseURL,
            pathComponents: ["api", "user", "self"],
            dropVersionComponent: true
        )
        let request = AIAgentURLBuilder.request(
            url: url,
            apiKey: apiKey,
            protocolKind: .openAICompatible
        )
        let object = try await jsonObject(for: request)
        let data = (object["data"] as? [String: Any]) ?? object
        let quota = Self.number(in: data, keys: ["quota", "balance", "available_quota"])
        let used = Self.number(in: data, keys: ["used_quota", "used", "consumed_quota"])
        let available: Double?
        if data["balance"] != nil || data["available_quota"] != nil {
            available = quota
        } else if let quota {
            available = quota - (used ?? 0)
        } else {
            available = nil
        }
        guard available != nil || used != nil else { throw AIAgentServiceError.invalidResponse }
        return AgentBalanceSnapshot(
            available: available,
            used: used,
            currency: "quota",
            detail: "渠道原始 quota 单位"
        )
    }

    private func customScript(
        path: String,
        account: AgentAccount,
        baseURL: String,
        apiKey: String,
        cliProfileContents: (configuration: Data, authentication: Data)?
    ) async throws -> AgentBalanceSnapshot {
        let executable = URL(fileURLWithPath: path)
        guard executable.path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AIAgentServiceError.invalidScript(path)
        }
        var payload: [String: String] = [
            "accountID": account.id.uuidString,
            "baseURL": baseURL,
            "apiKey": apiKey,
        ]
        if let cliProfileContents {
            payload["configuration"] = String(decoding: cliProfileContents.configuration, as: UTF8.self)
            payload["authentication"] = String(decoding: cliProfileContents.authentication, as: UTF8.self)
        }
        let output = try await AIAgentProcessRunner.run(
            executableURL: executable,
            standardInput: try JSONSerialization.data(withJSONObject: payload),
            timeout: 15
        )
        guard output.status == 0 else {
            throw AIAgentServiceError.scriptFailed(output.standardError)
        }
        guard let object = try JSONSerialization.jsonObject(with: output.standardOutput) as? [String: Any] else {
            throw AIAgentServiceError.invalidResponse
        }
        let available = Self.number(in: object, keys: ["available", "balance"])
        let used = Self.number(in: object, keys: ["used"])
        guard available != nil || used != nil else { throw AIAgentServiceError.invalidResponse }
        return AgentBalanceSnapshot(
            available: available,
            used: used,
            currency: (object["currency"] as? String) ?? "USD",
            detail: object["detail"] as? String
        )
    }

    private func jsonObject(for request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIAgentServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIAgentServiceError.http(
                statusCode: http.statusCode,
                body: String(decoding: data, as: UTF8.self)
            )
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIAgentServiceError.invalidResponse
        }
        return object
    }

    private static func number(in object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key] as? Double { return value }
            if let value = object[key] as? Int { return Double(value) }
            if let value = object[key] as? NSNumber { return value.doubleValue }
            if let value = object[key] as? String, let number = Double(value) { return number }
        }
        return nil
    }

    private static func sumNumbers(named key: String, in value: Any) -> Double {
        if let object = value as? [String: Any] {
            let ownValue = number(in: object, keys: [key]) ?? 0
            return ownValue + object.values.reduce(0) { $0 + sumNumbers(named: key, in: $1) }
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + sumNumbers(named: key, in: $1) }
        }
        return 0
    }
}

public struct AIAgentChannelProbeService: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func probe(route: AgentRoute, apiKey: String) async -> AgentChannelProbe {
        let startedAt = Date()
        do {
            var request: URLRequest
            switch route.protocolKind {
            case .openAICompatible:
                request = AIAgentURLBuilder.request(
                    url: try AIAgentURLBuilder.versionedURL(baseURL: route.baseURL, pathComponents: ["models"]),
                    apiKey: apiKey,
                    protocolKind: route.protocolKind
                )
            case .anthropicMessages:
                var url = try AIAgentURLBuilder.versionedURL(baseURL: route.baseURL, pathComponents: ["models"])
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.queryItems = [URLQueryItem(name: "limit", value: "1")]
                url = components?.url ?? url
                request = AIAgentURLBuilder.request(url: url, apiKey: apiKey, protocolKind: route.protocolKind)
            case .geminiGenerateContent:
                var url = try AIAgentURLBuilder.url(baseURL: route.baseURL, pathComponents: ["v1beta", "models"])
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
                url = components?.url ?? url
                request = AIAgentURLBuilder.request(url: url, apiKey: apiKey, protocolKind: route.protocolKind)
            }
            let (data, response) = try await session.data(for: request)
            let latency = Int(Date().timeIntervalSince(startedAt) * 1_000)
            guard let http = response as? HTTPURLResponse else { throw AIAgentServiceError.invalidResponse }
            let health: AgentChannelHealth
            switch http.statusCode {
            case 200..<300: health = .healthy
            case 401, 403, 429: health = .degraded
            default: health = .unavailable
            }
            return AgentChannelProbe(
                channelID: route.channelID,
                endpointGroupID: route.endpointGroupID,
                baseURL: route.baseURL,
                health: health,
                latencyMilliseconds: latency,
                detail: health == .healthy ? nil : String(decoding: data, as: UTF8.self).prefixString(180)
            )
        } catch {
            return AgentChannelProbe(
                channelID: route.channelID,
                endpointGroupID: route.endpointGroupID,
                baseURL: route.baseURL,
                health: .unavailable,
                detail: error.localizedDescription
            )
        }
    }
}

/// Fetches available models from provider model-list APIs. OpenAI-compatible channels use `/v1/models`.
public struct AIAgentModelCatalogService: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(route: AgentRoute, apiKey: String) async -> AgentChannelModelCatalog {
        do {
            let request = try request(for: route, apiKey: apiKey)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIAgentServiceError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw AIAgentServiceError.http(statusCode: http.statusCode, body: String(decoding: data, as: UTF8.self))
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AIAgentServiceError.invalidResponse
            }
            let models = Self.models(from: object)
            guard !models.isEmpty else { throw AIAgentServiceError.invalidResponse }
            return AgentChannelModelCatalog(
                channelID: route.channelID,
                endpointGroupID: route.endpointGroupID,
                baseURL: route.baseURL,
                models: models
            )
        } catch {
            return AgentChannelModelCatalog(
                channelID: route.channelID,
                endpointGroupID: route.endpointGroupID,
                baseURL: route.baseURL,
                models: [],
                detail: error.localizedDescription
            )
        }
    }

    private func request(for route: AgentRoute, apiKey: String) throws -> URLRequest {
        switch route.protocolKind {
        case .openAICompatible, .anthropicMessages:
            return AIAgentURLBuilder.request(
                url: try AIAgentURLBuilder.versionedURL(baseURL: route.baseURL, pathComponents: ["models"]),
                apiKey: apiKey,
                protocolKind: route.protocolKind
            )
        case .geminiGenerateContent:
            var url = try AIAgentURLBuilder.url(baseURL: route.baseURL, pathComponents: ["v1beta", "models"])
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
            url = components?.url ?? url
            return AIAgentURLBuilder.request(url: url, apiKey: apiKey, protocolKind: route.protocolKind)
        }
    }

    private static func models(from object: [String: Any]) -> [String] {
        let data = (object["data"] as? [[String: Any]]) ?? (object["models"] as? [[String: Any]]) ?? []
        return data.compactMap { item in
            let name = (item["id"] as? String) ?? (item["name"] as? String)
            return name?.replacingOccurrences(of: "models/", with: "")
        }
    }
}

public struct AIAgentSkillService: Sendable {
    public init() {}

    public func scan(
        roots: [URL] = Self.defaultRoots,
        enabledPaths: Set<String> = []
    ) -> [AgentSkill] {
        roots.flatMap { root -> [AgentSkill] in
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            var skills: [AgentSkill] = []
            for case let url as URL in enumerator where url.lastPathComponent == "SKILL.md" {
                let parent = url.deletingLastPathComponent()
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                skills.append(AgentSkill(
                    name: parent.lastPathComponent,
                    path: parent.path,
                    source: root.lastPathComponent,
                    isEnabled: !enabledPaths.contains(parent.path),
                    modifiedAt: values?.contentModificationDate
                ))
            }
            return skills
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".codex/skills", isDirectory: true),
            home.appendingPathComponent(".agents/skills", isDirectory: true),
            home.appendingPathComponent(".claude/skills", isDirectory: true),
        ]
    }
}

public struct AIAgentCLICommand: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]

    public init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }
}

public enum AIAgentCLIProfileError: LocalizedError, Sendable {
    case incompleteProfile
    case emptyProfile
    case emptyConfiguration
    case unableToRestore(String)

    public var errorDescription: String? {
        switch self {
        case .incompleteProfile: "CLI 档案必须同时配置两个不同的绝对路径"
        case .emptyProfile: "配置文件和认证文件都不能为空"
        case .emptyConfiguration: "配置文件不能为空"
        case let .unableToRestore(path): "切换失败且无法恢复原文件：\(path)"
        }
    }
}

enum CodexOfficialLoginPolicy {
    static func preservesAuthentication(
        for cliKind: AgentCLIKind,
        userPreference: Bool,
        isRouteTakeover: Bool
    ) -> Bool {
        cliKind == .codex && (userPreference || isRouteTakeover)
    }
}

/// A switch writes both files to temporary locations before replacing the targets in a recoverable order.
/// The file system cannot atomically commit multiple paths, so a failure in the second step restores the first file.
public struct AIAgentCLIProfileService: Sendable {
    public init() {}

    public func activate(
        profile: AgentCLIProfile,
        contents: (configuration: Data, authentication: Data)
    ) throws {
        guard profile.isComplete else { throw AIAgentCLIProfileError.incompleteProfile }
        guard !contents.configuration.isEmpty, !contents.authentication.isEmpty else {
            throw AIAgentCLIProfileError.emptyProfile
        }
        let (configurationURL, authenticationURL) = try targetURLs(for: profile)
        let configurationPrevious = try existingData(at: configurationURL)
        let authenticationPrevious = try existingData(at: authenticationURL)
        do {
            try writeSecurely(contents.authentication, to: authenticationURL)
            try writeSecurely(contents.configuration, to: configurationURL)
        } catch {
            var unrestored: [String] = []
            for (data, url) in [
                (configurationPrevious, configurationURL),
                (authenticationPrevious, authenticationURL),
            ] {
                do {
                    try restore(data, at: url)
                } catch {
                    unrestored.append(url.path)
                }
            }
            if !unrestored.isEmpty {
                throw AIAgentCLIProfileError.unableToRestore(unrestored.joined(separator: ", "))
            }
            throw error
        }
    }

    /// Saves configuration and credentials that the current CLI may have refreshed before switching accounts.
    public func syncBack(profile: AgentCLIProfile) throws -> (configuration: Data, authentication: Data) {
        let (configurationURL, authenticationURL) = try targetURLs(for: profile)
        guard let configuration = try existingData(at: configurationURL),
              let authentication = try existingData(at: authenticationURL) else {
            throw AIAgentCLIProfileError.emptyProfile
        }
        return (configuration, authentication)
    }

    /// Replaces only the route configuration, leaving an official CLI authentication file untouched.
    public func activateConfiguration(
        profile: AgentCLIProfile,
        configuration: Data
    ) throws {
        guard profile.isComplete else { throw AIAgentCLIProfileError.incompleteProfile }
        guard !configuration.isEmpty else { throw AIAgentCLIProfileError.emptyConfiguration }
        let (configurationURL, _) = try targetURLs(for: profile)
        let previous = try existingData(at: configurationURL)
        do {
            try writeSecurely(configuration, to: configurationURL)
        } catch {
            do {
                try restore(previous, at: configurationURL)
            } catch {
                throw AIAgentCLIProfileError.unableToRestore(configurationURL.path)
            }
            throw error
        }
    }

    /// Reads only the route configuration after a profile that preserves external authentication was active.
    public func syncBackConfiguration(profile: AgentCLIProfile) throws -> Data {
        let (configurationURL, _) = try targetURLs(for: profile)
        guard let configuration = try existingData(at: configurationURL), !configuration.isEmpty else {
            throw AIAgentCLIProfileError.emptyConfiguration
        }
        return configuration
    }

    private func existingData(at url: URL) throws -> Data? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func writeSecurely(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        let parent = url.deletingLastPathComponent()
        if !manager.fileExists(atPath: parent.path) {
            try manager.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func restore(_ data: Data?, at url: URL) throws {
        let manager = FileManager.default
        if let data {
            try writeSecurely(data, to: url)
        } else if manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
    }

    private func targetURLs(for profile: AgentCLIProfile) throws -> (URL, URL) {
        guard profile.isComplete else { throw AIAgentCLIProfileError.incompleteProfile }
        let configuration = URL(fileURLWithPath: profile.configurationFilePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let authentication = URL(fileURLWithPath: profile.authenticationFilePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard configuration.path != authentication.path else {
            throw AIAgentCLIProfileError.incompleteProfile
        }
        return (configuration, authentication)
    }
}

public enum AIAgentCLIRelayError: LocalizedError, Sendable {
    case unavailable(AgentCLIKind)
    case failed(String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case let .unavailable(kind): "未找到 \(kind.displayName) CLI"
        case let .failed(detail): "Agent CLI 执行失败：\(detail)"
        case .emptyResponse: "Agent CLI 没有返回消息"
        }
    }
}

public struct AIAgentCLIService: Sendable {
    private let environment: [String: String]
    private let homeDirectory: URL

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    public func statuses() async -> [AgentCLIStatus] {
        var results: [AgentCLIStatus] = []
        for kind in AgentCLIKind.allCases {
            results.append(await status(for: kind))
        }
        return results
    }

    public func status(for kind: AgentCLIKind) async -> AgentCLIStatus {
        guard let executableURL = executableURL(for: kind) else {
            return AgentCLIStatus(kind: kind)
        }
        do {
            let output = try await AIAgentProcessRunner.run(
                executableURL: executableURL,
                arguments: ["--version"],
                timeout: 8
            )
            let version = String(decoding: output.standardOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return AgentCLIStatus(
                kind: kind,
                executablePath: executableURL.path,
                version: output.status == 0 ? version : nil
            )
        } catch {
            return AgentCLIStatus(kind: kind, executablePath: executableURL.path)
        }
    }

    /// Returns an npm command for later confirmation without modifying the system.
    public func installationCommand(for kind: AgentCLIKind, update: Bool) -> AIAgentCLICommand? {
        installationCommands(for: [kind], update: update).first
    }

    /// Groups npm-managed CLIs into one invocation while preserving the official Grok installer/updater.
    public func installationCommands(for kinds: [AgentCLIKind], update: Bool) -> [AIAgentCLICommand] {
        let requested = Set(kinds)
        let packages = AgentCLIKind.allCases.compactMap { kind -> String? in
            guard requested.contains(kind), let package = npmPackage(for: kind) else { return nil }
            return update ? "\(package)@latest" : package
        }
        var commands: [AIAgentCLICommand] = []
        if !packages.isEmpty, let npm = executable(named: "npm") {
            commands.append(AIAgentCLICommand(
                executableURL: npm,
                arguments: ["install", "--global"] + packages
            ))
        }
        if requested.contains(.grok) {
            if update, let grok = executableURL(for: .grok) {
                commands.append(AIAgentCLICommand(executableURL: grok, arguments: ["update"]))
            } else if !update {
                commands.append(AIAgentCLICommand(
                    executableURL: URL(fileURLWithPath: "/bin/bash"),
                    arguments: ["-c", "curl -fsSL https://x.ai/cli/install.sh | bash"]
                ))
            }
        }
        return commands
    }

    public func uninstallationCommand(for kind: AgentCLIKind) -> AIAgentCLICommand? {
        uninstallationCommands(for: [kind]).first
    }

    /// Removes only the CLI executable for Grok, retaining its account and local configuration data.
    public func uninstallationCommands(for kinds: [AgentCLIKind]) -> [AIAgentCLICommand] {
        let requested = Set(kinds)
        let packages = AgentCLIKind.allCases.compactMap { kind -> String? in
            guard requested.contains(kind) else { return nil }
            return npmPackage(for: kind)
        }
        var commands: [AIAgentCLICommand] = []
        if !packages.isEmpty, let npm = executable(named: "npm") {
            commands.append(AIAgentCLICommand(
                executableURL: npm,
                arguments: ["uninstall", "--global"] + packages
            ))
        }
        if requested.contains(.grok) {
            let managedGrok = homeDirectory.appendingPathComponent(".grok/bin/grok")
            if FileManager.default.isExecutableFile(atPath: managedGrok.path) {
                commands.append(AIAgentCLICommand(
                    executableURL: URL(fileURLWithPath: "/bin/rm"),
                    arguments: [managedGrok.path]
                ))
            }
        }
        return commands
    }

    public func run(_ command: AIAgentCLICommand) async throws -> AIAgentProcessOutput {
        try await AIAgentProcessRunner.run(
            executableURL: command.executableURL,
            arguments: command.arguments,
            timeout: 120
        )
    }

    /// Passes unified history as plain text to a local CLI without calling model HTTP APIs from this app.
    public func relay(
        messages: [AgentChatMessage],
        project: AgentChatProject? = nil,
        accessMode: AgentChatAccessMode = .autoReview,
        model: String? = nil,
        thinkingDepth: AgentChatThinkingDepth = .high,
        to kind: AgentCLIKind
    ) async throws -> String {
        guard let executableURL = executableURL(for: kind) else {
            throw AIAgentCLIRelayError.unavailable(kind)
        }
        let prompt = relayPrompt(
            messages,
            project: project,
            accessMode: accessMode,
            model: model,
            thinkingDepth: thinkingDepth
        )
        let output = try await AIAgentProcessRunner.run(
            executableURL: executableURL,
            arguments: relayArguments(for: kind, prompt: prompt),
            standardInput: Data(prompt.utf8),
            workingDirectoryURL: relayWorkingDirectory(for: project),
            timeout: 300
        )
        guard output.status == 0 else {
            let detail = output.standardError.isEmpty
                ? String(decoding: output.standardOutput, as: UTF8.self)
                : output.standardError
            throw AIAgentCLIRelayError.failed(String(detail.prefix(500)))
        }
        let response = String(decoding: output.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty else { throw AIAgentCLIRelayError.emptyResponse }
        return response
    }

    func relayWorkingDirectory(for project: AgentChatProject?) -> URL {
        guard let path = project?.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            return FileManager.default.homeDirectoryForCurrentUser
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public func relayArguments(for kind: AgentCLIKind, prompt: String) -> [String] {
        switch kind {
        case .claude:
            ["-p"]
        case .codex:
            ["exec", "--skip-git-repo-check", "-"]
        case .gemini:
            ["-p", "-"]
        case .grok:
            ["--prompt-file", "-"]
        case .opencode:
            ["run", "-"]
        }
    }

    func executableURL(for kind: AgentCLIKind) -> URL? {
        executable(named: kind.executableName)
    }

    private func npmPackage(for kind: AgentCLIKind) -> String? {
        switch kind {
        case .claude: "@anthropic-ai/claude-code"
        case .codex: "@openai/codex"
        case .gemini: "@google/gemini-cli"
        case .opencode: "opencode-ai"
        case .grok: nil
        }
    }

    func executable(named name: String) -> URL? {
        let fileManager = FileManager.default
        return Self.executableSearchDirectories(
            environment: environment,
            homeDirectory: homeDirectory
        )
        .map { $0.appendingPathComponent(name) }
        .first { fileManager.isExecutableFile(atPath: $0.path) }
        .map { $0.resolvingSymlinksInPath().standardizedFileURL }
    }

    static func executableSearchDirectories(
        environment: [String: String],
        homeDirectory: URL
    ) -> [URL] {
        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: String($0), isDirectory: true).standardizedFileURL }
        let configuredPrefix = environment["NPM_CONFIG_PREFIX"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
        }
        let nvmDirectories = versionDirectories(
            in: homeDirectory.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        ).map { $0.appendingPathComponent("bin", isDirectory: true) }
        let fnmDirectories = versionDirectories(
            in: homeDirectory.appendingPathComponent(".fnm/node-versions", isDirectory: true)
        ).map { $0.appendingPathComponent("installation/bin", isDirectory: true) }
        let defaults = [
            homeDirectory.appendingPathComponent(".npm-global/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".npm/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".volta/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".fnm/aliases/default/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".asdf/shims", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/pnpm", isDirectory: true),
            homeDirectory.appendingPathComponent(".bun/bin", isDirectory: true),
            homeDirectory.appendingPathComponent(".grok/bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        ]
        let candidates = pathDirectories + (configuredPrefix.map { [$0] } ?? [])
            + defaults + fnmDirectories + nvmDirectories
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func versionDirectories(in root: URL) -> [URL] {
        let values = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return (values ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
    }

    func relayPrompt(
        _ messages: [AgentChatMessage],
        project: AgentChatProject? = nil,
        accessMode: AgentChatAccessMode = .autoReview,
        model: String? = nil,
        thinkingDepth: AgentChatThinkingDepth = .high
    ) -> String {
        let retainedMessages = Array(messages.suffix(32))
        let history = retainedMessages.enumerated().map { index, message in
            let role: String
            switch message.role {
            case .system: role = "系统"
            case .user: role = "用户"
            case .assistant: role = "Agent"
            }
            var sections = ["[\(role)]\n\(message.content)"]
            if message.mode == .plan {
                sections.append("[计划模式]\n请给出可执行计划、当前进展和下一步。")
            }
            // 计划模式与目标模式互相独立，目标存在时都要单独声明当前会话的 Prompt。
            if let goal = message.goalTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !goal.isEmpty {
                sections.append("[目标模式]\n当前会话目标：\(goal)\n请围绕该目标推进，不要偏离。")
            }
            let attachments = message.attachments.compactMap { attachment -> String? in
                guard attachment.state != .deleted,
                      !attachment.storagePath.isEmpty else { return nil }
                let path = AppPaths.aiAgentAttachments
                    .appendingPathComponent(attachment.storagePath, isDirectory: false)
                    .path
                return "- \(attachment.kind.displayName)：\(attachment.fileName)（\(attachment.mimeType)，\(path)）"
            }
            if !attachments.isEmpty {
                sections.append("[附件]\n\(attachments.joined(separator: "\n"))\n可在本机路径读取附件；不要假设附件内容已写入本条文本。")
            }
            let apps = message.appReferences.map { app in
                "- \(app.name)（\(app.bundleIdentifier)，PID \(app.processIdentifier)）"
            }
            if !apps.isEmpty {
                sections.append("[@本机 App]\n\(apps.joined(separator: "\n"))\n这些应用正在用户本机运行；仅在本机环境允许时读取它们的公开上下文。")
            }
            let skills = index == retainedMessages.count - 1 ? message.skillReferences.compactMap { skill -> String? in
                let name = skill.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let path = skill.path.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !path.isEmpty else { return nil }
                return "- \(name)：\(path)"
            } : []
            if !skills.isEmpty {
                sections.append("[调用 Skills]\n\(skills.joined(separator: "\n"))\n这是用户显式选择的 Skill。仅当本机可读取对应路径时加载其 SKILL.md；不要假设本应用执行了该 Skill。")
            }
            for reference in message.contextReferences {
                let context = reference.messages.map { contextMessage in
                    let contextRole: String
                    switch contextMessage.role {
                    case .system: contextRole = "系统"
                    case .user: contextRole = "用户"
                    case .assistant: contextRole = "Agent"
                    }
                    return "[\(contextRole)] \(contextMessage.content)"
                }.joined(separator: "\n")
                sections.append("[@会话：\(reference.title)]\n\(context)")
            }
            return sections.joined(separator: "\n\n")
        }.joined(separator: "\n\n")
        let projectContext: String
        if let project {
            let instructions = project.instructions.isEmpty ? "" : "\n项目说明：\(project.instructions)"
            projectContext = "[项目：\(project.name)]\(instructions)\n请将项目说明作为本项目所有会话的共享上下文。"
        } else {
            projectContext = ""
        }
        let selectedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelPreference = selectedModel?.isEmpty == false ? "\n模型：\(selectedModel!)" : ""
        let relayPreferences = "[转发偏好]\n访问模式：\(accessMode.displayName)\(modelPreference)\n思考深度：\(thinkingDepth.displayName)\n请在外部 CLI 自身允许的权限范围内遵守这些偏好。"
        let sections = [relayPreferences, projectContext, history].filter { !$0.isEmpty }.joined(separator: "\n\n")
        return "以下是从统一聊天历史转发的消息。请直接回复最后一条用户消息；不要声称此应用本身是 Agent。\n\n\(sections)"
    }
}

public struct AIAgentProcessOutput: Sendable {
    public var status: Int32
    public var standardOutput: Data
    public var standardError: String
}

private final class AIAgentProcessCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var error = Data()

    func setOutput(_ data: Data) {
        lock.lock()
        output = data
        lock.unlock()
    }

    func setError(_ data: Data) {
        lock.lock()
        error = data
        lock.unlock()
    }

    func values() -> (Data, Data) {
        lock.lock()
        defer { lock.unlock() }
        return (output, error)
    }
}

public enum AIAgentProcessRunner {
    public static func run(
        executableURL: URL,
        arguments: [String] = [],
        standardInput: Data? = nil,
        workingDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeout: TimeInterval = 15
    ) async throws -> AIAgentProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                let error = Pipe()
                let input = Pipe()
                process.executableURL = executableURL
                process.arguments = arguments
                process.currentDirectoryURL = workingDirectoryURL
                process.standardOutput = output
                process.standardError = error
                if standardInput != nil { process.standardInput = input }
                do {
                    try process.run()
                    let capture = AIAgentProcessCapture()
                    let readers = DispatchGroup()
                    readers.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        capture.setOutput(output.fileHandleForReading.readDataToEndOfFile())
                        readers.leave()
                    }
                    readers.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        capture.setError(error.fileHandleForReading.readDataToEndOfFile())
                        readers.leave()
                    }
                    if let standardInput {
                        DispatchQueue.global(qos: .userInitiated).async {
                            input.fileHandleForWriting.write(standardInput)
                            try? input.fileHandleForWriting.close()
                        }
                    }
                    let timeoutWork = DispatchWorkItem {
                        guard process.isRunning else { return }
                        process.terminate()
                        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                        }
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
                    process.waitUntilExit()
                    timeoutWork.cancel()
                    readers.wait()
                    let (standardOutput, standardErrorData) = capture.values()
                    let standardError = String(decoding: standardErrorData, as: UTF8.self)
                    continuation.resume(returning: AIAgentProcessOutput(
                        status: process.terminationStatus,
                        standardOutput: standardOutput,
                        standardError: standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

private extension String {
    func prefixString(_ length: Int) -> String {
        String(prefix(length))
    }
}
