import Foundation
import Darwin
import ZislaCore

public enum AIAgentServiceError: LocalizedError, Sendable {
    case invalidBaseURL(String)
    case missingAPIKey
    case unsupportedBalanceProbe
    case invalidScript(String)
    case scriptFailed(Int32)
    case invalidResponse
    case http(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "渠道地址无效"
        case .missingAPIKey: "账号未配置 API Key"
        case .unsupportedBalanceProbe: "当前余额检测方式不支持该渠道"
        case let .invalidScript(path): "余额脚本不可执行：\(path)"
        case let .scriptFailed(status): "余额脚本执行失败（退出状态 \(status)）"
        case .invalidResponse: "渠道返回了无法识别的结果"
        case let .http(statusCode): "渠道请求失败（HTTP \(statusCode)）"
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
        guard var url = URL(string: raw), AIEndpointSecurity.permits(url) else {
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
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
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
            throw AIAgentServiceError.scriptFailed(output.status)
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
            throw AIAgentServiceError.http(statusCode: http.statusCode)
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
                let url = try AIAgentURLBuilder.url(baseURL: route.baseURL, pathComponents: ["v1beta", "models"])
                request = AIAgentURLBuilder.request(url: url, apiKey: apiKey, protocolKind: route.protocolKind)
            }
            let (_, response) = try await session.data(for: request)
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
                detail: health == .healthy ? nil : "渠道请求失败（HTTP \(http.statusCode)）"
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
                throw AIAgentServiceError.http(statusCode: http.statusCode)
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
            let url = try AIAgentURLBuilder.url(baseURL: route.baseURL, pathComponents: ["v1beta", "models"])
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

enum AgentSkillPackageManager: String, Equatable, Sendable {
    case npm
    case pnpm
    case yarn
    case bun
    case brew

    var executableName: String { rawValue }
}

struct AgentSkillPackageInstallation: Equatable, Sendable {
    let manager: AgentSkillPackageManager
    let packageName: String

    var uninstallArguments: [String] {
        switch manager {
        case .npm:
            ["uninstall", "--global", packageName]
        case .pnpm, .bun:
            ["remove", "--global", packageName]
        case .yarn:
            ["global", "remove", packageName]
        case .brew:
            ["uninstall", packageName]
        }
    }

    static func detect(at url: URL) -> AgentSkillPackageInstallation? {
        let standardized = url.standardizedFileURL
        let components = standardized.pathComponents
        if let cellarIndex = components.firstIndex(of: "Cellar"),
           cellarIndex + 1 < components.count {
            return AgentSkillPackageInstallation(
                manager: .brew,
                packageName: components[cellarIndex + 1]
            )
        }
        if let caskroomIndex = components.firstIndex(of: "Caskroom"),
           caskroomIndex + 1 < components.count {
            return AgentSkillPackageInstallation(
                manager: .brew,
                packageName: components[caskroomIndex + 1]
            )
        }

        guard let nodeModulesIndex = components.lastIndex(of: "node_modules"),
              let packageName = packageName(
                in: components,
                after: nodeModulesIndex
              ) else {
            return nil
        }

        let path = standardized.path
        let manager: AgentSkillPackageManager
        if path.contains("/.bun/install/global/") {
            manager = .bun
        } else if path.contains("/Library/pnpm/global/")
                    || path.contains("/.local/share/pnpm/global/")
                    || path.contains("/pnpm/global/") {
            manager = .pnpm
        } else if path.contains("/.config/yarn/global/") {
            manager = .yarn
        } else if path.contains("/lib/node_modules/") {
            manager = .npm
        } else {
            return nil
        }
        return AgentSkillPackageInstallation(manager: manager, packageName: packageName)
    }

    private static func packageName(in components: [String], after index: Int) -> String? {
        let firstIndex = index + 1
        guard firstIndex < components.count else { return nil }
        let first = components[firstIndex]
        if first.hasPrefix("@") {
            guard firstIndex + 1 < components.count else { return nil }
            return "\(first)/\(components[firstIndex + 1])"
        }
        return first.isEmpty ? nil : first
    }
}

public struct AIAgentCLICommand: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var timeout: TimeInterval

    public init(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval = 120
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.timeout = timeout
    }
}

public enum AIAgentGrokUpdateState: Equatable, Sendable {
    case unknown
    case upToDate
    case updateAvailable(AIAgentCLIUpdate)
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
    case unsupportedRelay(AgentCLIKind)
    case unavailable(AgentCLIKind)
    case failed(String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case let .unsupportedRelay(kind): "\(kind.displayName) 暂不支持消息中继"
        case let .unavailable(kind): "未找到 \(kind.displayName) CLI"
        case let .failed(detail): "Agent CLI 执行失败：\(detail)"
        case .emptyResponse: "Agent CLI 没有返回消息"
        }
    }
}

public struct AIAgentCLIService: Sendable {
    private static let updateCommandTimeout: TimeInterval = 10 * 60

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
        for kind in AgentCLIKind.detectableCases {
            results.append(await status(for: kind))
        }
        return results
    }

    public func status(for kind: AgentCLIKind) async -> AgentCLIStatus {
        guard let executableURL = executableURL(for: kind) else {
            return AgentCLIStatus(kind: kind)
        }
        let packageVersion = installedPackageVersion(for: kind, executableURL: executableURL)
        do {
            let output = try await AIAgentProcessRunner.run(
                executableURL: executableURL,
                arguments: ["--version"],
                environment: commandEnvironment,
                timeout: 8
            )
            return AgentCLIStatus(
                kind: kind,
                executablePath: executableURL.path,
                version: output.status == 0 ? version(in: output) ?? packageVersion : packageVersion
            )
        } catch {
            return AgentCLIStatus(kind: kind, executablePath: executableURL.path, version: packageVersion)
        }
    }

    public func grokUpdateState() async -> AIAgentGrokUpdateState {
        guard let grok = executableURL(for: .grok) else { return .unknown }
        do {
            let output = try await AIAgentProcessRunner.run(
                executableURL: grok,
                arguments: ["update", "--check", "--json"],
                environment: commandEnvironment,
                timeout: 15
            )
            if output.status == 0,
               let check = try? JSONDecoder().decode(GrokUpdateCheck.self, from: output.standardOutput),
               check.error == nil {
                guard check.updateAvailable else { return .upToDate }
                return .updateAvailable(AIAgentCLIUpdate(
                    kind: .grok,
                    installedVersion: check.currentVersion,
                    latestVersion: check.latestVersion
                ))
            }
        } catch {}

        guard let installedVersion = await currentVersion(of: .grok, at: grok),
              let latestVersion = cachedGrokLatestVersion(),
              let installed = semanticVersion(in: installedVersion),
              let latest = semanticVersion(in: latestVersion)
        else { return .unknown }
        return latest > installed
            ? .updateAvailable(AIAgentCLIUpdate(
                kind: .grok,
                installedVersion: installedVersion,
                latestVersion: latestVersion
            ))
            : .upToDate
    }

    public func homebrewUpdates(for statuses: [AgentCLIStatus]) async -> [AIAgentCLIUpdate] {
        guard let brew = executable(named: AgentSkillPackageManager.brew.executableName) else { return [] }
        let candidates = statuses.compactMap { status -> (AgentCLIStatus, AgentSkillPackageInstallation)? in
            guard status.kind != .kimi,
                  AgentCLIKind.managedCases.contains(status.kind),
                  let executablePath = status.executablePath,
                  let installation = AgentSkillPackageInstallation.detect(at: URL(fileURLWithPath: executablePath)),
                  installation.manager == .brew,
                  status.version != nil
            else { return nil }
            return (status, installation)
        }
        guard !candidates.isEmpty else { return [] }

        return await withTaskGroup(of: AIAgentCLIUpdate?.self, returning: [AIAgentCLIUpdate].self) { group in
            for (status, installation) in candidates {
                group.addTask {
                    await homebrewUpdate(for: status, installation: installation, brew: brew)
                }
            }
            var updates: [AIAgentCLIUpdate] = []
            for await update in group {
                if let update { updates.append(update) }
            }
            return updates.sorted {
                AgentCLIKind.allCases.firstIndex(of: $0.kind)! < AgentCLIKind.allCases.firstIndex(of: $1.kind)!
            }
        }
    }

    private func homebrewUpdate(
        for status: AgentCLIStatus,
        installation: AgentSkillPackageInstallation,
        brew: URL
    ) async -> AIAgentCLIUpdate? {
        do {
            let output = try await AIAgentProcessRunner.run(
                executableURL: brew,
                arguments: ["outdated", "--json=v2", installation.packageName],
                environment: commandEnvironment,
                timeout: 15
            )
            guard output.status == 0,
                  let outdated = try? JSONDecoder().decode(HomebrewOutdatedPackages.self, from: output.standardOutput),
                  let package = outdated.packages.first(where: { $0.packageName == installation.packageName }),
                  let installedVersion = status.version
            else { return nil }
            return AIAgentCLIUpdate(
                kind: status.kind,
                installedVersion: installedVersion,
                latestVersion: package.currentVersion
            )
        } catch {
            return nil
        }
    }

    private func installedPackageVersion(for kind: AgentCLIKind, executableURL: URL) -> String? {
        guard let packageName = kind.npmPackageName else { return nil }
        var directory = executableURL.deletingLastPathComponent()
        for _ in 0..<4 {
            let packageURL = directory.appendingPathComponent("package.json")
            if let data = try? Data(contentsOf: packageURL),
               let metadata = try? JSONDecoder().decode(InstalledNPMPackageMetadata.self, from: data),
               metadata.name == packageName,
               !metadata.version.isEmpty {
                return metadata.version
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    private func version(in output: AIAgentProcessOutput) -> String? {
        let stdout = String(decoding: output.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty { return stdout }
        let stderr = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return stderr.isEmpty ? nil : stderr
    }

    private func currentVersion(of kind: AgentCLIKind, at executableURL: URL) async -> String? {
        guard let output = try? await AIAgentProcessRunner.run(
            executableURL: executableURL,
            arguments: ["--version"],
            environment: commandEnvironment,
            timeout: 8
        ), output.status == 0 else { return nil }
        return version(in: output)
    }

    private func cachedGrokLatestVersion() -> String? {
        let cache = homeDirectory.appendingPathComponent(".grok/version.json")
        guard let data = try? Data(contentsOf: cache) else { return nil }
        return try? JSONDecoder().decode(GrokVersionCache.self, from: data).version
    }

    private func semanticVersion(in rawValue: String) -> SemanticVersion? {
        let candidates = rawValue.split { character in
            !(character.isNumber || character == "." || character == "-" || character == "+" || character == "v")
        }
        return candidates.compactMap { try? SemanticVersion(String($0)) }.first
    }

    /// Returns an installation command for later confirmation without modifying the system.
    public func installationCommand(for kind: AgentCLIKind, update: Bool) -> AIAgentCLICommand? {
        installationCommands(for: [kind], update: update).first
    }

    /// Updates managed CLIs with the installer that owns the discovered executable.
    public func installationCommands(for kinds: [AgentCLIKind], update: Bool) -> [AIAgentCLICommand] {
        let requested = Set(kinds)
        if update {
            return updateCommands(for: requested)
        }
        let packages = AgentCLIKind.managedCases.compactMap { kind -> String? in
            guard requested.contains(kind), let package = npmPackage(for: kind) else { return nil }
            return package
        }
        var commands: [AIAgentCLICommand] = []
        if !packages.isEmpty {
            if let npm = executable(named: "npm") {
                commands.append(AIAgentCLICommand(
                    executableURL: npm,
                    arguments: ["install", "--global"] + packages
                ))
            } else {
                for kind in requested.sorted(by: Self.cliKindOrder) {
                    guard let script = standaloneInstallScript(for: kind) else { continue }
                    commands.append(AIAgentCLICommand(
                        executableURL: URL(fileURLWithPath: "/bin/bash"),
                        arguments: ["-c", script]
                    ))
                }
            }
        }
        if requested.contains(.grok) {
            commands.append(AIAgentCLICommand(
                executableURL: URL(fileURLWithPath: "/bin/bash"),
                arguments: ["-c", "curl -fsSL https://x.ai/cli/install.sh | bash"]
            ))
        }
        if requested.contains(.kimi) {
            commands.append(AIAgentCLICommand(
                executableURL: URL(fileURLWithPath: "/bin/bash"),
                arguments: ["-c", "curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash"]
            ))
        }
        if requested.contains(.qwen), !packages.contains("@qwen-code/qwen-code"), let script = standaloneInstallScript(for: .qwen) {
            commands.append(AIAgentCLICommand(executableURL: URL(fileURLWithPath: "/bin/bash"), arguments: ["-c", script]))
        }
        if requested.contains(.qoder), !packages.contains("@qoder-ai/qodercli"), let script = standaloneInstallScript(for: .qoder) {
            commands.append(AIAgentCLICommand(executableURL: URL(fileURLWithPath: "/bin/bash"), arguments: ["-c", script]))
        }
        if requested.contains(.copilot), !packages.contains("@github/copilot"), let script = standaloneInstallScript(for: .copilot) {
            commands.append(AIAgentCLICommand(executableURL: URL(fileURLWithPath: "/bin/bash"), arguments: ["-c", script]))
        }
        return commands
    }

    private func updateCommands(for requested: Set<AgentCLIKind>) -> [AIAgentCLICommand] {
        var commands: [AIAgentCLICommand] = []
        var managedKinds = Set<AgentCLIKind>()

        for manager in [AgentSkillPackageManager.npm, .pnpm, .yarn, .bun, .brew] {
            let packages = AgentCLIKind.managedCases.compactMap { kind -> String? in
                guard kind != .kimi,
                      kind != .grok,
                      requested.contains(kind),
                      let executableURL = executableURL(for: kind),
                      let installation = AgentSkillPackageInstallation.detect(at: executableURL),
                      installation.manager == manager
                else { return nil }
                managedKinds.insert(kind)
                return installation.packageName
            }
            guard !packages.isEmpty, let executableURL = executable(named: manager.executableName) else {
                continue
            }
            commands.append(AIAgentCLICommand(
                executableURL: executableURL,
                arguments: updateArguments(for: manager, packages: packages),
                timeout: Self.updateCommandTimeout
            ))
        }

        let fallbackPackages = AgentCLIKind.managedCases.compactMap { kind -> String? in
            guard kind != .qwen,
                  kind != .qoder,
                  kind != .copilot,
                  requested.contains(kind),
                  !managedKinds.contains(kind),
                  let package = npmPackage(for: kind)
            else {
                return nil
            }
            return "\(package)@latest"
        }
        if !fallbackPackages.isEmpty, let npm = executable(named: "npm") {
            commands.append(AIAgentCLICommand(
                executableURL: npm,
                arguments: ["install", "--global"] + fallbackPackages,
                timeout: Self.updateCommandTimeout
            ))
        }
        if requested.contains(.grok), let grok = executableURL(for: .grok) {
            commands.append(AIAgentCLICommand(
                executableURL: grok,
                arguments: ["update"],
                timeout: Self.updateCommandTimeout
            ))
        }
        if requested.contains(.kimi), let kimi = executableURL(for: .kimi) {
            commands.append(AIAgentCLICommand(
                executableURL: kimi,
                arguments: ["upgrade"],
                timeout: Self.updateCommandTimeout
            ))
        }
        for kind in [AgentCLIKind.qwen, .qoder, .copilot] where requested.contains(kind) && !managedKinds.contains(kind) {
            if let executable = executableURL(for: kind) {
                commands.append(AIAgentCLICommand(
                    executableURL: executable,
                    arguments: ["update"],
                    timeout: Self.updateCommandTimeout
                ))
            }
        }
        return commands
    }

    private func updateArguments(for manager: AgentSkillPackageManager, packages: [String]) -> [String] {
        switch manager {
        case .npm:
            ["install", "--global"] + packages.map { "\($0)@latest" }
        case .pnpm, .bun:
            ["update", "--global"] + packages.map { "\($0)@latest" }
        case .yarn:
            ["global", "add"] + packages.map { "\($0)@latest" }
        case .brew:
            ["upgrade"] + packages
        }
    }

    public func uninstallationCommand(for kind: AgentCLIKind) -> AIAgentCLICommand? {
        uninstallationCommands(for: [kind]).first
    }

    /// Removes only trusted standalone CLI executables, retaining account and local configuration data.
    public func uninstallationCommands(for kinds: [AgentCLIKind]) -> [AIAgentCLICommand] {
        let requested = Set(kinds)
        var commands: [AIAgentCLICommand] = []
        var managedKinds = Set<AgentCLIKind>()
        for manager in [AgentSkillPackageManager.npm, .pnpm, .yarn, .bun, .brew] {
            var packages = AgentCLIKind.managedCases.compactMap { kind -> String? in
                guard requested.contains(kind),
                      let executableURL = executableURL(for: kind),
                      let installation = AgentSkillPackageInstallation.detect(at: executableURL),
                      installation.manager == manager
                else { return nil }
                managedKinds.insert(kind)
                return installation.packageName
            }
            if manager == .npm {
                let legacyPackages = [AgentCLIKind.claude, .codex, .gemini, .opencode].compactMap { kind -> String? in
                    guard requested.contains(kind), !managedKinds.contains(kind) else { return nil }
                    return npmPackage(for: kind)
                }
                packages.append(contentsOf: legacyPackages)
            }
            guard !packages.isEmpty,
                  let managerExecutable = executable(named: manager.executableName)
            else { continue }
            let arguments: [String]
            switch manager {
            case .npm:
                arguments = ["uninstall", "--global"] + packages
            case .pnpm, .bun:
                arguments = ["remove", "--global"] + packages
            case .yarn:
                arguments = ["global", "remove"] + packages
            case .brew:
                arguments = ["uninstall"] + packages
            }
            commands.append(AIAgentCLICommand(executableURL: managerExecutable, arguments: arguments))
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
        if requested.contains(.kimi), let managedKimi = managedKimiExecutable() {
            commands.append(AIAgentCLICommand(
                executableURL: URL(fileURLWithPath: "/bin/rm"),
                arguments: [managedKimi.path]
            ))
        }
        if requested.contains(.qwen), !managedKinds.contains(.qwen), executableURL(for: .qwen) != nil {
            commands.append(AIAgentCLICommand(
                executableURL: URL(fileURLWithPath: "/bin/bash"),
                arguments: [
                    "-c",
                    "curl -fsSL https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/uninstall-qwen-standalone.sh | bash",
                ]
            ))
        }
        for kind in [AgentCLIKind.qoder, .copilot] where requested.contains(kind) && !managedKinds.contains(kind) {
            guard let executable = executableURL(for: kind), isTrustedStandaloneExecutable(executable, for: kind) else {
                continue
            }
            commands.append(AIAgentCLICommand(
                executableURL: URL(fileURLWithPath: "/bin/rm"),
                arguments: [executable.path]
            ))
        }
        return commands
    }

    private func isTrustedStandaloneExecutable(_ executable: URL, for kind: AgentCLIKind) -> Bool {
        executable.standardizedFileURL.path == homeDirectory
            .appendingPathComponent(".local/bin", isDirectory: true)
            .appendingPathComponent(kind.executableName)
            .standardizedFileURL
            .path
    }

    private func standaloneInstallScript(for kind: AgentCLIKind) -> String? {
        switch kind {
        case .qwen:
            "curl -fsSL https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen-standalone.sh | bash"
        case .qoder:
            "curl -fsSL https://qoder.com/install | bash"
        case .copilot:
            "curl -fsSL https://gh.io/copilot-install | bash"
        default:
            nil
        }
    }

    private static func cliKindOrder(_ lhs: AgentCLIKind, _ rhs: AgentCLIKind) -> Bool {
        guard let left = AgentCLIKind.allCases.firstIndex(of: lhs),
              let right = AgentCLIKind.allCases.firstIndex(of: rhs)
        else { return lhs.rawValue < rhs.rawValue }
        return left < right
    }

    func uninstallationCommand(
        for installation: AgentSkillPackageInstallation
    ) -> AIAgentCLICommand? {
        guard let executableURL = executable(named: installation.manager.executableName) else {
            return nil
        }
        return AIAgentCLICommand(
            executableURL: executableURL,
            arguments: installation.uninstallArguments
        )
    }

    public func run(_ command: AIAgentCLICommand) async throws -> AIAgentProcessOutput {
        try await AIAgentProcessRunner.run(
            executableURL: command.executableURL,
            arguments: command.arguments,
            environment: commandEnvironment,
            timeout: command.timeout
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
        guard AgentCLIKind.relayCases.contains(kind) else {
            throw AIAgentCLIRelayError.unsupportedRelay(kind)
        }
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
            arguments: relayArguments(
                for: kind,
                prompt: prompt,
                model: model,
                thinkingDepth: thinkingDepth,
                accessMode: accessMode
            ),
            standardInput: Data(prompt.utf8),
            environment: commandEnvironment,
            workingDirectoryURL: relayWorkingDirectory(for: project),
            timeout: 300
        )
        guard output.status == 0 else {
            throw AIAgentCLIRelayError.failed("退出状态 \(output.status)")
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

    public func relayArguments(
        for kind: AgentCLIKind,
        prompt: String,
        model: String? = nil,
        thinkingDepth: AgentChatThinkingDepth = .high,
        accessMode: AgentChatAccessMode = .autoReview
    ) -> [String] {
        var args: [String] = []

        switch kind {
        case .claude:
            args.append("-p")
            if let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedModel.isEmpty {
                args.append(contentsOf: ["--model", trimmedModel])
            }
            args.append(contentsOf: ["--effort", effortLevel(for: thinkingDepth)])
            if accessMode == .fullAccess {
                args.append("--dangerously-skip-permissions")
            } else {
                args.append(contentsOf: ["--permission-mode", claudePermissionMode(for: accessMode)])
            }

        case .codex:
            args.append(contentsOf: ["exec", "--skip-git-repo-check"])
            if let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedModel.isEmpty {
                args.append(contentsOf: ["--model", trimmedModel])
            }
            args.append(contentsOf: [
                "--config",
                "model_reasoning_effort=\"\(effortLevel(for: thinkingDepth))\"",
            ])
            switch accessMode {
            case .autoReview:
                args.append("--approve-for-me")
            case .readOnly:
                args.append(contentsOf: ["--sandbox", "read-only"])
            case .workspaceWrite:
                args.append(contentsOf: ["--sandbox", "workspace-write"])
            case .fullAccess:
                args.append("--dangerously-bypass-approvals-and-sandbox")
            }
            args.append("-")

        case .gemini:
            args.append("-p")
            if let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedModel.isEmpty {
                args.append(contentsOf: ["--model", trimmedModel])
            }
            args.append(contentsOf: ["--approval-mode", geminiApprovalMode(for: accessMode)])
            args.append("-")

        case .grok:
            if let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedModel.isEmpty {
                args.append(contentsOf: ["--model", trimmedModel])
            }
            args.append(contentsOf: ["--reasoning-effort", effortLevel(for: thinkingDepth)])
            args.append(contentsOf: ["--permission-mode", grokPermissionMode(for: accessMode)])
            args.append(contentsOf: ["--prompt-file", "-"])

        case .opencode:
            args.append("run")
            if let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedModel.isEmpty {
                args.append(contentsOf: ["--model", trimmedModel])
            }
            let variant = opencodeVariant(for: thinkingDepth)
            if !variant.isEmpty {
                args.append(contentsOf: ["--variant", variant])
            }
            if accessMode == .fullAccess {
                args.append("--auto")
            }
            args.append("-")

        case .kimi, .qwen, .qoder, .copilot:
            return []
        }

        return args
    }

    private func effortLevel(for depth: AgentChatThinkingDepth) -> String {
        switch depth {
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .extraHigh: "xhigh"
        }
    }

    private func claudePermissionMode(for accessMode: AgentChatAccessMode) -> String {
        switch accessMode {
        case .fullAccess: "bypassPermissions"
        case .autoReview: "auto"
        case .readOnly: "plan"
        case .workspaceWrite: "acceptEdits"
        }
    }

    private func grokPermissionMode(for accessMode: AgentChatAccessMode) -> String {
        switch accessMode {
        case .fullAccess: "bypassPermissions"
        case .autoReview: "auto"
        case .readOnly: "plan"
        case .workspaceWrite: "acceptEdits"
        }
    }

    private func geminiApprovalMode(for accessMode: AgentChatAccessMode) -> String {
        switch accessMode {
        case .fullAccess: "yolo"
        case .autoReview: "auto_edit"
        case .readOnly: "plan"
        case .workspaceWrite: "auto_edit"
        }
    }

    private func opencodeVariant(for depth: AgentChatThinkingDepth) -> String {
        switch depth {
        case .low: "minimal"
        case .medium: ""
        case .high: "high"
        case .extraHigh: "max"
        }
    }

    func executableURL(for kind: AgentCLIKind) -> URL? {
        if kind == .kimi {
            if let executable = kimiExecutableURL(resolveSymlinks: true) { return executable }
        }
        return executable(named: kind.executableName)
    }

    private func managedKimiExecutable() -> URL? {
        kimiExecutableURL(resolveSymlinks: false)
    }

    private func kimiExecutableURL(resolveSymlinks: Bool) -> URL? {
        let fileManager = FileManager.default
        guard let executable = Self.kimiInstallationRoots(
            environment: environment,
            homeDirectory: homeDirectory
        )
        .map({ $0.appendingPathComponent("bin/kimi").standardizedFileURL })
        .first(where: { fileManager.isExecutableFile(atPath: $0.path) })
        else { return nil }
        return resolveSymlinks ? executable.resolvingSymlinksInPath().standardizedFileURL : executable
    }

    private func npmPackage(for kind: AgentCLIKind) -> String? {
        kind.npmPackageName
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

    private var commandEnvironment: [String: String] {
        var environment = environment
        let directories = Self.executableSearchDirectories(
            environment: environment,
            homeDirectory: homeDirectory
        ).map(\.path)
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        environment["PATH"] = (directories + existing).filter { seen.insert($0).inserted }.joined(separator: ":")
        return environment
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
        let kimiDirectories = kimiInstallationRoots(
            environment: environment,
            homeDirectory: homeDirectory
        ).map { $0.appendingPathComponent("bin", isDirectory: true) }
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
            + kimiDirectories + defaults + fnmDirectories + nvmDirectories
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func kimiInstallationRoots(
        environment: [String: String],
        homeDirectory: URL
    ) -> [URL] {
        let configured = [environment["KIMI_INSTALL_DIR"]].compactMap { value -> URL? in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            let path = value == "~"
                ? homeDirectory.path
                : value.replacingOccurrences(of: "~/", with: "\(homeDirectory.path)/", options: .anchored)
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        let defaults = [homeDirectory.appendingPathComponent(".kimi-code", isDirectory: true)]
        var seen = Set<String>()
        return (configured + defaults).filter { seen.insert($0.path).inserted }
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

    func outboundMessages(_ messages: [AgentChatMessage]) -> [AIOutboundMessage] {
        boundedSerializedMessages(messages).map { item in
            let role: AIChatRole = switch item.message.role {
            case .system: .system
            case .user: .user
            case .assistant: .assistant
            }
            return AIOutboundMessage(role: role, content: item.content)
        }
    }

    func relayPrompt(
        _ messages: [AgentChatMessage],
        project: AgentChatProject? = nil,
        accessMode: AgentChatAccessMode = .autoReview,
        model: String? = nil,
        thinkingDepth: AgentChatThinkingDepth = .high
    ) -> String {
        let history = boundedSerializedMessages(messages)
            .map(\.content)
            .joined(separator: "\n\n")
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

    private func boundedSerializedMessages(
        _ messages: [AgentChatMessage]
    ) -> [(message: AgentChatMessage, content: String)] {
        let retained = Array(messages.suffix(32))
        let serialized = retained.enumerated().map { index, message in
            (message, serializedMessage(message, includesSkills: index == retained.count - 1))
        }
        var remainingCharacters = 96_000
        var bounded: [(message: AgentChatMessage, content: String)] = []
        for item in serialized.reversed() where remainingCharacters > 0 {
            let content = String(item.1.prefix(remainingCharacters))
            bounded.append((item.0, content))
            remainingCharacters -= content.count
        }
        return Array(bounded.reversed())
    }

    private func serializedMessage(_ message: AgentChatMessage, includesSkills: Bool) -> String {
        let role: String = switch message.role {
        case .system: "系统"
        case .user: "用户"
        case .assistant: "Agent"
        }
        var sections = ["[\(role)]\n\(message.content)"]
        if message.mode == .plan {
            sections.append("[计划模式]\n请给出可执行计划、当前进展和下一步。")
        }
        if let goal = message.goalTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !goal.isEmpty {
            sections.append("[目标模式]\n当前会话目标：\(goal)\n请围绕该目标推进，不要偏离。")
        }
        let attachments = message.attachments.compactMap { attachment -> String? in
            guard attachment.state != .deleted, !attachment.storagePath.isEmpty else { return nil }
            let path = AppPaths.aiAgentAttachments
                .appendingPathComponent(attachment.storagePath, isDirectory: false).path
            return "- \(attachment.kind.displayName)：\(attachment.fileName)（\(attachment.mimeType)，\(path)）"
        }
        if !attachments.isEmpty {
            sections.append("[附件]\n\(attachments.joined(separator: "\n"))\n可在本机路径读取附件；不要假设附件内容已写入本条文本。")
        }
        let apps = message.appReferences.map {
            "- \($0.name)（\($0.bundleIdentifier)，PID \($0.processIdentifier)）"
        }
        if !apps.isEmpty {
            sections.append("[@本机 App]\n\(apps.joined(separator: "\n"))\n这些应用正在用户本机运行；仅在本机环境允许时读取它们的公开上下文。")
        }
        let skills = includesSkills ? message.skillReferences.compactMap { skill -> String? in
            let name = skill.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let path = skill.path.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty || path.isEmpty ? nil : "- \(name)：\(path)"
        } : []
        if !skills.isEmpty {
            sections.append("[调用 Skills]\n\(skills.joined(separator: "\n"))\n这是用户显式选择的 Skill。仅当本机可读取对应路径时加载其 SKILL.md；不要假设本应用执行了该 Skill。")
        }
        for reference in message.contextReferences {
            let context = reference.messages.map { contextMessage in
                let contextRole: String = switch contextMessage.role {
                case .system: "系统"
                case .user: "用户"
                case .assistant: "Agent"
                }
                return "[\(contextRole)] \(contextMessage.content)"
            }.joined(separator: "\n")
            sections.append("[@会话：\(reference.title)]\n\(context)")
        }
        return sections.joined(separator: "\n\n")
    }
}

public struct AIAgentProcessOutput: Sendable {
    public var status: Int32
    public var standardOutput: Data
    public var standardError: String
    public var didTimeout: Bool
}

private struct InstalledNPMPackageMetadata: Decodable {
    let name: String
    let version: String
}

private struct GrokUpdateCheck: Decodable {
    let currentVersion: String
    let latestVersion: String
    let updateAvailable: Bool
    let error: String?
}

private struct GrokVersionCache: Decodable {
    let version: String
}

private struct HomebrewOutdatedPackages: Decodable {
    let formulae: [HomebrewOutdatedFormula]
    let casks: [HomebrewOutdatedFormula]

    var packages: [HomebrewOutdatedFormula] { formulae + casks }
}

private struct HomebrewOutdatedFormula: Decodable {
    let name: String
    let currentVersion: String

    var packageName: String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case currentVersion = "current_version"
    }
}

private final class AIAgentProcessCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var error = Data()
    private var didTimeout = false
    private var cancelled = false

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

    func markTimedOut() {
        lock.lock()
        didTimeout = true
        lock.unlock()
    }

    func markCancelled() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func wasCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func values() -> (Data, Data, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (output, error, didTimeout)
    }
}

private final class AIAgentProcessResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        block()
    }
}

public enum AIAgentProcessRunner {
    public static func run(
        executableURL: URL,
        arguments: [String] = [],
        standardInput: Data? = nil,
        environment: [String: String]? = nil,
        workingDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeout: TimeInterval = 15
    ) async throws -> AIAgentProcessOutput {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        let input = Pipe()
        let capture = AIAgentProcessCapture()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectoryURL
        process.standardOutput = output
        process.standardError = error
        if standardInput != nil { process.standardInput = input }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let resumed = AIAgentProcessResumeGuard()
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        guard !capture.wasCancelled() else { throw CancellationError() }
                        try process.run()
                        if capture.wasCancelled() {
                            terminate(process, escalationDelay: 0.5)
                        }
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
                            capture.markTimedOut()
                            process.terminate()
                            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                            }
                        }
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
                        process.waitUntilExit()
                        timeoutWork.cancel()
                        readers.wait()

                        resumed.resume {
                            if capture.wasCancelled() {
                                continuation.resume(throwing: CancellationError())
                            } else {
                                let (standardOutput, standardErrorData, didTimeout) = capture.values()
                                let standardError = String(decoding: standardErrorData, as: UTF8.self)
                                continuation.resume(returning: AIAgentProcessOutput(
                                    status: process.terminationStatus,
                                    standardOutput: standardOutput,
                                    standardError: standardError.trimmingCharacters(in: .whitespacesAndNewlines),
                                    didTimeout: didTimeout
                                ))
                            }
                        }
                    } catch {
                        resumed.resume {
                            continuation.resume(throwing: capture.wasCancelled() ? CancellationError() : error)
                        }
                    }
                }
            }
        } onCancel: {
            capture.markCancelled()
            terminate(process, escalationDelay: 0.5)
        }
    }

    private static func terminate(_ process: Process, escalationDelay: TimeInterval) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + escalationDelay) {
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
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
