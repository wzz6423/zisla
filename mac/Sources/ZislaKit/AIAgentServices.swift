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
        case let .invalidScript(path): AppLocalization.text("余额脚本不可执行：%@", path)
        case let .scriptFailed(status): AppLocalization.text("余额脚本执行失败（退出状态 %ld）", Int(status))
        case .invalidResponse: "渠道返回了无法识别的结果"
        case let .http(statusCode): AppLocalization.text("渠道请求失败（HTTP %ld）", statusCode)
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
           isVersionComponent(url.lastPathComponent) {
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
        if !existing.contains(where: isVersionComponent) {
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

    private static func isVersionComponent(_ component: String) -> Bool {
        let suffix = component.lowercased().dropFirst()
        guard component.lowercased().first == "v" else { return false }
        let digits = suffix.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return false }
        let qualifier = suffix.dropFirst(digits.count)
        guard !qualifier.isEmpty else { return true }
        return ["alpha", "beta"].contains { name in
            guard qualifier.hasPrefix(name) else { return false }
            return qualifier.dropFirst(name.count).allSatisfy(\.isNumber)
        }
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
                detail: health == .healthy ? nil : AppLocalization.text("渠道请求失败（HTTP %ld）", http.statusCode)
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
        let scannedSkills = roots.flatMap { root -> [AgentSkill] in
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
                    description: skillDescription(at: url),
                    path: parent.path,
                    source: root.lastPathComponent,
                    isEnabled: !enabledPaths.contains(parent.path),
                    modifiedAt: values?.contentModificationDate
                ))
            }
            return skills
        }
        var seenNames = Set<String>()
        return scannedSkills
            .filter { seenNames.insert($0.name.lowercased()).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func skillDescription(at url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = contents.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return nil }

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" { break }
            guard trimmed.hasPrefix("description:") else { continue }
            let value = trimmed.dropFirst("description:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            if value.first == "\"", value.last == "\"", value.count >= 2 {
                return String(value.dropFirst().dropLast())
            }
            return String(value)
        }
        return nil
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
    case unableToRestore(String)

    public var errorDescription: String? {
        switch self {
        case .incompleteProfile: "CLI 档案必须同时配置两个不同的绝对路径"
        case .emptyProfile: "配置文件和认证文件都不能为空"
        case let .unableToRestore(path): AppLocalization.text("切换失败且无法恢复原文件：%@", path)
        }
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
        case let .unsupportedRelay(kind): AppLocalization.text("%@ 暂不支持语音整理", kind.displayName)
        case let .unavailable(kind): AppLocalization.text("未找到 %@ CLI", kind.displayName)
        case let .failed(detail): AppLocalization.text("CLI 执行失败：%@", detail)
        case .emptyResponse: AppLocalization.text("CLI 没有返回内容")
        }
    }
}

public struct AIAgentCLIService: Sendable {
    private static let updateCommandTimeout: TimeInterval = 10 * 60

    private let environment: [String: String]
    private let homeDirectory: URL
    private var networkProxyURL = ""
    private var networkProxyEnabled = false

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        networkProxyURL: String = ""
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.networkProxyURL = networkProxyURL
        self.networkProxyEnabled = !networkProxyURL.isEmpty
    }

    public mutating func setNetworkProxyURL(_ value: String) {
        networkProxyURL = value
        networkProxyEnabled = true
    }

    public mutating func setNetworkProxy(url: String, enabled: Bool) {
        networkProxyURL = url
        networkProxyEnabled = enabled
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
            return updates.sorted { Self.cliKindOrder($0.kind, $1.kind) }
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
            if let npm = executable(named: "npm", resolveSymlinks: false) {
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
            guard !packages.isEmpty,
                  let executableURL = executable(named: manager.executableName, resolveSymlinks: false)
            else {
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
        if !fallbackPackages.isEmpty, let npm = executable(named: "npm", resolveSymlinks: false) {
            commands.append(AIAgentCLICommand(
                executableURL: npm,
                arguments: ["install", "--global"] + fallbackPackages,
                timeout: Self.updateCommandTimeout
            ))
        }
        if requested.contains(.grok), let grok = executableURL(for: .grok, resolveSymlinks: false) {
            commands.append(AIAgentCLICommand(
                executableURL: grok,
                arguments: ["update"],
                timeout: Self.updateCommandTimeout
            ))
        }
        if requested.contains(.kimi), let kimi = executableURL(for: .kimi, resolveSymlinks: false) {
            commands.append(AIAgentCLICommand(
                executableURL: kimi,
                arguments: ["upgrade"],
                timeout: Self.updateCommandTimeout
            ))
        }
        for kind in [AgentCLIKind.qwen, .qoder, .copilot] where requested.contains(kind) && !managedKinds.contains(kind) {
            if let executable = executableURL(for: kind, resolveSymlinks: false) {
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
                  let managerExecutable = executable(
                      named: manager.executableName,
                      resolveSymlinks: false
                  )
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

    static func cliKindOrder(_ lhs: AgentCLIKind, _ rhs: AgentCLIKind) -> Bool {
        guard let left = AgentCLIKind.allCases.firstIndex(of: lhs),
              let right = AgentCLIKind.allCases.firstIndex(of: rhs)
        else { return lhs.rawValue < rhs.rawValue }
        return left < right
    }

    func uninstallationCommand(
        for installation: AgentSkillPackageInstallation
    ) -> AIAgentCLICommand? {
        guard let executableURL = executable(
            named: installation.manager.executableName,
            resolveSymlinks: false
        ) else {
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

    /// Runs one bounded, read-only completion for voice transcript cleanup.
    public func relay(
        messages: [AIOutboundMessage],
        model: String? = nil,
        to kind: AgentCLIKind
    ) async throws -> String {
        guard AgentCLIKind.relayCases.contains(kind) else {
            throw AIAgentCLIRelayError.unsupportedRelay(kind)
        }
        guard let executableURL = executableURL(for: kind) else {
            throw AIAgentCLIRelayError.unavailable(kind)
        }
        let prompt = relayPrompt(messages)
        let output = try await AIAgentProcessRunner.run(
            executableURL: executableURL,
            arguments: relayArguments(for: kind, model: model),
            standardInput: Data(prompt.utf8),
            environment: commandEnvironment,
            workingDirectoryURL: homeDirectory,
            timeout: 300
        )
        guard output.status == 0 else {
            throw AIAgentCLIRelayError.failed(AppLocalization.text("退出状态 %ld", Int(output.status)))
        }
        let response = String(decoding: output.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty else { throw AIAgentCLIRelayError.emptyResponse }
        return response
    }

    public func relayArguments(for kind: AgentCLIKind, model: String? = nil) -> [String] {
        var arguments: [String] = []
        let model = model?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .claude:
            arguments.append("-p")
            appendModel(model, to: &arguments)
            arguments.append(contentsOf: ["--effort", "medium", "--permission-mode", "plan"])
        case .codex:
            arguments.append(contentsOf: ["exec", "--skip-git-repo-check"])
            appendModel(model, to: &arguments)
            arguments.append(contentsOf: [
                "--config",
                "model_reasoning_effort=\"medium\"",
                "--sandbox",
                "read-only",
                "-",
            ])
        case .gemini:
            arguments.append("-p")
            appendModel(model, to: &arguments)
            arguments.append(contentsOf: ["--approval-mode", "plan", "-"])
        case .grok:
            appendModel(model, to: &arguments)
            arguments.append(contentsOf: [
                "--reasoning-effort",
                "medium",
                "--permission-mode",
                "plan",
                "--prompt-file",
                "-",
            ])
        case .opencode:
            arguments.append("run")
            appendModel(model, to: &arguments)
            arguments.append("-")
        case .kimi, .qwen, .qoder, .copilot, .glm, .dsh, .pi:
            return []
        }

        return arguments
    }

    func relayPrompt(_ messages: [AIOutboundMessage]) -> String {
        let serialized = messages.suffix(32).map { message in
            let role = switch message.role {
            case .system: "系统"
            case .user: "用户"
            case .assistant: "助手"
            case .tool: "工具"
            }
            return "[\(role)]\n\(message.content)"
        }
        var remainingCharacters = 96_000
        var bounded: [String] = []
        for message in serialized.reversed() where remainingCharacters > 0 {
            let content = String(message.prefix(remainingCharacters))
            bounded.append(content)
            remainingCharacters -= content.count
        }
        return bounded.reversed().joined(separator: "\n\n")
    }

    private func appendModel(_ model: String?, to arguments: inout [String]) {
        guard let model, !model.isEmpty else { return }
        arguments.append(contentsOf: ["--model", model])
    }

    func executableURL(for kind: AgentCLIKind, resolveSymlinks: Bool = true) -> URL? {
        if kind == .kimi {
            if let executable = kimiExecutableURL(resolveSymlinks: resolveSymlinks) { return executable }
        }
        return executable(named: kind.executableName, resolveSymlinks: resolveSymlinks)
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

    func executable(named name: String, resolveSymlinks: Bool = true) -> URL? {
        let fileManager = FileManager.default
        return Self.executableSearchDirectories(
            environment: environment,
            homeDirectory: homeDirectory
        )
        .map { $0.appendingPathComponent(name) }
        .first { fileManager.isExecutableFile(atPath: $0.path) }
        .map { executable in
            resolveSymlinks
                ? executable.resolvingSymlinksInPath().standardizedFileURL
                : executable
        }
    }

    private var commandEnvironment: [String: String] {
        var environment = NetworkProxy.environment(
            from: networkProxyURL,
            enabled: networkProxyEnabled,
            base: self.environment
        )
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
    public static let defaultMaximumOutputBytes = Int.max
    public static let defaultMaximumErrorBytes = Int.max

    private static let readerDrainGrace: DispatchTimeInterval = .milliseconds(250)

    public static func run(
        executableURL: URL,
        arguments: [String] = [],
        standardInput: Data? = nil,
        environment: [String: String]? = nil,
        workingDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeout: TimeInterval? = 15,
        maximumOutputBytes: Int = AIAgentProcessRunner.defaultMaximumOutputBytes,
        maximumErrorBytes: Int = AIAgentProcessRunner.defaultMaximumErrorBytes
    ) async throws -> AIAgentProcessOutput {
        let channels = AIAgentProcessChannels()
        let capture = AIAgentProcessCapture()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let resumed = AIAgentProcessResumeGuard()
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Result {
                        try execute(
                            channels: channels,
                            capture: capture,
                            executableURL: executableURL,
                            arguments: arguments,
                            standardInput: standardInput,
                            environment: environment,
                            workingDirectoryURL: workingDirectoryURL,
                            timeout: timeout,
                            maximumOutputBytes: maximumOutputBytes,
                            maximumErrorBytes: maximumErrorBytes
                        )
                    }
                    resumed.resume {
                        if capture.wasCancelled() {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(with: result)
                        }
                    }
                }
            }
        } onCancel: {
            capture.markCancelled()
            terminate(channels, escalationDelay: 0.5)
        }
    }

    /// Runs the subprocess directly on the calling thread instead of the Swift concurrency cooperative pool, preventing thread starvation while a caller waits inside a `Task`.
    public static func runSynchronously(
        executableURL: URL,
        arguments: [String] = [],
        standardInput: Data? = nil,
        environment: [String: String]? = nil,
        workingDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeout: TimeInterval? = 15,
        maximumOutputBytes: Int = AIAgentProcessRunner.defaultMaximumOutputBytes,
        maximumErrorBytes: Int = AIAgentProcessRunner.defaultMaximumErrorBytes
    ) throws -> AIAgentProcessOutput {
        try execute(
            channels: AIAgentProcessChannels(),
            capture: AIAgentProcessCapture(),
            executableURL: executableURL,
            arguments: arguments,
            standardInput: standardInput,
            environment: environment,
            workingDirectoryURL: workingDirectoryURL,
            timeout: timeout,
            maximumOutputBytes: maximumOutputBytes,
            maximumErrorBytes: maximumErrorBytes
        )
    }

    private static func execute(
        channels: AIAgentProcessChannels,
        capture: AIAgentProcessCapture,
        executableURL: URL,
        arguments: [String],
        standardInput: Data?,
        environment: [String: String]?,
        workingDirectoryURL: URL,
        timeout: TimeInterval?,
        maximumOutputBytes: Int,
        maximumErrorBytes: Int
    ) throws -> AIAgentProcessOutput {
        channels.process.executableURL = executableURL
        channels.process.arguments = arguments
        channels.process.environment = environment
        channels.process.currentDirectoryURL = workingDirectoryURL
        channels.process.standardOutput = channels.output
        channels.process.standardError = channels.error
        if standardInput != nil {
            channels.process.standardInput = channels.input
            _ = fcntl(channels.input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        }

        guard !capture.wasCancelled() else { throw CancellationError() }
        try channels.process.run()
        if capture.wasCancelled() {
            terminate(channels, escalationDelay: 0.5)
        }

        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            capture.setOutput(readLimited(
                channels.output.fileHandleForReading,
                maximumBytes: maximumOutputBytes
            ))
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            capture.setError(readLimited(
                channels.error.fileHandleForReading,
                maximumBytes: maximumErrorBytes
            ))
            readers.leave()
        }
        if let standardInput {
            DispatchQueue.global(qos: .userInitiated).async {
                try? channels.input.fileHandleForWriting.write(contentsOf: standardInput)
                try? channels.input.fileHandleForWriting.close()
            }
        }
        let timeoutWork = timeout.map { _ in
            DispatchWorkItem {
                // Reader threads may still be draining after the process exits, so closing the pipes here would truncate valid output.
                guard channels.process.isRunning else { return }
                capture.markTimedOut()
                terminate(channels, escalationDelay: 3)
            }
        }
        if let timeout, let timeoutWork {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        }
        channels.process.waitUntilExit()
        timeoutWork?.cancel()
        // The write ends close when the process exits, leaving at most the buffered data in the pipes.
        // If draining still does not finish, a descendant process is holding a write end open, so close the read ends to unblock.
        if readers.wait(timeout: .now() + readerDrainGrace) == .timedOut {
            closeReadEnds(channels)
            readers.wait()
        }

        guard !capture.wasCancelled() else { throw CancellationError() }
        let (standardOutput, standardErrorData, didTimeout) = capture.values()
        return AIAgentProcessOutput(
            status: channels.process.terminationStatus,
            standardOutput: standardOutput,
            standardError: String(decoding: standardErrorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            didTimeout: didTimeout
        )
    }

    private static func terminate(
        _ channels: AIAgentProcessChannels,
        escalationDelay: TimeInterval
    ) {
        closeReadEnds(channels)
        guard channels.process.isRunning else { return }
        channels.process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + escalationDelay) {
            if channels.process.isRunning {
                Darwin.kill(channels.process.processIdentifier, SIGKILL)
            }
        }
    }

    private static func closeReadEnds(_ channels: AIAgentProcessChannels) {
        try? channels.output.fileHandleForReading.close()
        try? channels.error.fileHandleForReading.close()
    }

    private static func readLimited(_ handle: FileHandle, maximumBytes: Int) -> Data {
        let limit = max(1, maximumBytes)
        var result = Data()
        while let chunk = try? handle.read(upToCount: 64 * 1024),
              !chunk.isEmpty {
            if result.count < limit {
                result.append(chunk.prefix(limit - result.count))
            }
        }
        return result
    }
}

private final class AIAgentProcessChannels: @unchecked Sendable {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    let input = Pipe()
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
