import Foundation
import SQLite3
import ZislaCore

public enum AIAgentConfigurationImportSource: String, CaseIterable, Sendable {
    case codexPlusPlus
    case ccSwitch

    public var displayName: String {
        switch self {
        case .codexPlusPlus: "Codex++"
        case .ccSwitch: "CC Switch"
        }
    }
}

public struct AIAgentImportedProvider: Equatable, Sendable {
    public var source: AIAgentConfigurationImportSource
    public var name: String
    public var baseURL: String
    public var apiKey: String
    public var defaultModel: String
    public var protocolKind: AgentChannelProtocol

    public init(
        source: AIAgentConfigurationImportSource,
        name: String,
        baseURL: String,
        apiKey: String,
        defaultModel: String = "",
        protocolKind: AgentChannelProtocol = .openAICompatible
    ) {
        self.source = source
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.defaultModel = defaultModel
        self.protocolKind = protocolKind
    }
}

public enum AIAgentConfigurationImportError: LocalizedError, Sendable {
    case unsupportedFile
    case invalidConfiguration
    case noProviders(String)
    case databaseFailure(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile: "不支持的配置文件格式"
        case .invalidConfiguration: "配置内容无效"
        case let .noProviders(source): "未在 \(source) 中找到可导入的 Provider"
        case let .databaseFailure(detail): "读取 CC Switch 数据库失败：\(detail)"
        }
    }
}

public struct AIAgentConfigurationImporter: Sendable {
    public init() {}

    public func importCodexPlusPlus(data: Data) throws -> [AIAgentImportedProvider] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw AIAgentConfigurationImportError.invalidConfiguration
        }
        let values = providerObjects(in: object)
        let providers = values.compactMap { parseCodexPlusPlusProvider($0) }
        guard !providers.isEmpty else {
            throw AIAgentConfigurationImportError.noProviders(AIAgentConfigurationImportSource.codexPlusPlus.displayName)
        }
        return deduplicated(providers)
    }

    public func importCCSwitch(databaseURL: URL) throws -> [AIAgentImportedProvider] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else {
            sqlite3_close(database)
            throw AIAgentConfigurationImportError.databaseFailure("无法打开数据库")
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1_000)

        let sql = """
            SELECT p.app_type, p.name, p.settings_config,
                   GROUP_CONCAT(e.url, char(31))
            FROM providers p
            LEFT JOIN provider_endpoints e
              ON e.provider_id = p.id AND e.app_type = p.app_type
            GROUP BY p.id, p.app_type, p.name, p.settings_config
            ORDER BY p.sort_index, p.name
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw AIAgentConfigurationImportError.databaseFailure("数据库结构不兼容")
        }
        defer { sqlite3_finalize(statement) }

        var providers: [AIAgentImportedProvider] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let appType = stringColumn(statement, 0),
                  let name = stringColumn(statement, 1),
                  let settings = stringColumn(statement, 2),
                  let json = try? JSONSerialization.jsonObject(with: Data(settings.utf8)),
                  let object = json as? [String: Any] else { continue }
            let configured = parseCCSwitchSettings(object, appType: appType)
            let urls = (stringColumn(statement, 3) ?? "")
                .split(separator: "\u{1F}", omittingEmptySubsequences: true)
                .map(String.init)
            let baseURL = configured.baseURL ?? urls.first
            let apiKey = configured.apiKey
            guard let baseURL, isSupportedBaseURL(baseURL), let apiKey, !apiKey.isEmpty else { continue }
            providers.append(AIAgentImportedProvider(
                source: .ccSwitch,
                name: name,
                baseURL: baseURL,
                apiKey: apiKey,
                defaultModel: configured.model ?? "",
                protocolKind: configured.protocolKind
            ))
        }
        guard !providers.isEmpty else {
            throw AIAgentConfigurationImportError.noProviders(AIAgentConfigurationImportSource.ccSwitch.displayName)
        }
        return deduplicated(providers)
    }

    public func automaticURLs(for source: AIAgentConfigurationImportSource, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        switch source {
        case .codexPlusPlus:
            return [
                home.appendingPathComponent(".codex-session-delete/settings.json"),
                home.appendingPathComponent(".codex-plus-plus/settings.json"),
                home.appendingPathComponent("Library/Application Support/Codex++/settings.json"),
            ]
        case .ccSwitch:
            return [home.appendingPathComponent(".cc-switch/cc-switch.db")]
        }
    }

    private func providerObjects(in value: Any) -> [[String: Any]] {
        if let object = value as? [String: Any] {
            for key in ["relayProfiles", "relay_profiles", "providers", "profiles", "items"] {
                if let nested = object[key] { return providerObjects(in: nested) }
            }
            return [object]
        }
        if let array = value as? [[String: Any]] { return array.flatMap(providerObjects(in:)) }
        if let array = value as? [Any] { return array.flatMap(providerObjects(in:)) }
        return []
    }

    private func parseCodexPlusPlusProvider(_ object: [String: Any]) -> AIAgentImportedProvider? {
        let nested = (object["provider"] as? [String: Any]) ?? object
        let name = string(in: nested, keys: ["name", "displayName", "profileName"]) ?? "Codex++ Provider"
        let baseURL = string(in: nested, keys: ["baseUrl", "baseURL", "upstreamBaseUrl", "upstream_base_url"])
        let authContents = string(in: nested, keys: ["authContents", "auth_contents"])
        let configContents = string(in: nested, keys: ["configContents", "config_contents"])
        let apiKey = string(in: nested, keys: ["apiKey", "api_key", "OPENAI_API_KEY"])
            ?? string(in: (nested["auth"] as? [String: Any]) ?? [:], keys: ["OPENAI_API_KEY", "apiKey", "api_key"])
            ?? authContents.flatMap(apiKeyInAuthContents)
            ?? configContents.flatMap(extractConfigValue(named: "experimental_bearer_token"))
        let resolvedBaseURL = baseURL ?? configContents.flatMap(extractConfigValue(named: "base_url"))
        guard let resolvedBaseURL, let apiKey, isSupportedBaseURL(resolvedBaseURL), !apiKey.isEmpty else { return nil }
        let model = string(in: nested, keys: ["model", "defaultModel", "testModel"])
            ?? configContents.flatMap(extractConfigValue(named: "model"))
            ?? ""
        return AIAgentImportedProvider(
            source: .codexPlusPlus,
            name: name,
            baseURL: resolvedBaseURL,
            apiKey: apiKey,
            defaultModel: model,
            protocolKind: .openAICompatible
        )
    }

    private func parseCCSwitchSettings(
        _ object: [String: Any],
        appType: String
    ) -> (baseURL: String?, apiKey: String?, model: String?, protocolKind: AgentChannelProtocol) {
        let auth = (object["auth"] as? [String: Any]) ?? [:]
        let env = (object["env"] as? [String: Any]) ?? [:]
        let config = string(in: object, keys: ["config", "configContents", "config_contents"])
        let protocolKind: AgentChannelProtocol = switch appType {
        case "claude", "claude-desktop": .anthropicMessages
        case "gemini": .geminiGenerateContent
        default: .openAICompatible
        }
        let baseURL = string(in: object, keys: ["baseUrl", "baseURL", "base_url"])
            ?? string(in: env, keys: ["OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "GOOGLE_GEMINI_BASE_URL", "GEMINI_BASE_URL"])
            ?? config.flatMap(extractConfigValue(named: "base_url"))
        let apiKey = string(in: object, keys: ["apiKey", "api_key"])
            ?? string(in: auth, keys: ["OPENAI_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "apiKey", "api_key"])
            ?? string(in: env, keys: ["OPENAI_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "GEMINI_API_KEY"])
        let model = string(in: object, keys: ["model", "defaultModel", "default_model"])
            ?? config.flatMap(extractConfigValue(named: "model"))
        return (baseURL, apiKey, model, protocolKind)
    }

    private func apiKeyInAuthContents(_ contents: String) -> String? {
        guard let value = try? JSONSerialization.jsonObject(with: Data(contents.utf8)) as? [String: Any] else {
            return nil
        }
        return string(in: value, keys: ["OPENAI_API_KEY", "apiKey", "api_key"])
    }

    private func extractConfigValue(named key: String) -> (String) -> String? {
        { config in
            for line in config.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, parts[0] == key else { continue }
                return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            return nil
        }
    }

    private func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func isSupportedBaseURL(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return AIEndpointSecurity.permits(url)
    }

    private func deduplicated(_ providers: [AIAgentImportedProvider]) -> [AIAgentImportedProvider] {
        var seen = Set<String>()
        return providers.filter { provider in
            let key = "\(provider.name.lowercased())\n\(provider.baseURL.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
            return seen.insert(key).inserted
        }
    }

    private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }
}
