import Foundation
import SQLite3
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct AIAgentConfigurationImporterTests {
    @Test
    func codexPlusPlusImportReadsRelayProfilesAndFiltersInvalidEntries() throws {
        let data = Data("""
        {
          "relayProfiles": [
            {
              "name": "Codex++ 中转",
              "configContents": "model = \\\"gpt-5.6\\\"",
              "upstreamBaseUrl": "https://api.example.com/codex",
              "authContents": "{\\\"OPENAI_API_KEY\\\":\\\"sk-imported\\\"}"
            },
            {
              "name": "无效",
              "baseUrl": "https://invalid.example",
              "apiKey": ""
            }
          ]
        }
        """.utf8)

        let providers = try AIAgentConfigurationImporter().importCodexPlusPlus(data: data)

        #expect(providers == [AIAgentImportedProvider(
            source: .codexPlusPlus,
            name: "Codex++ 中转",
            baseURL: "https://api.example.com/codex",
            apiKey: "sk-imported",
            defaultModel: "gpt-5.6"
        )])
    }

    @Test
    func ccSwitchImportReadsCodexAndClaudeProviders() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("cc-switch.db")
        try createCCSwitchDatabase(at: databaseURL)

        let providers = try AIAgentConfigurationImporter().importCCSwitch(databaseURL: databaseURL)

        #expect(providers.count == 3)
        #expect(providers.first { $0.name == "Codex 中转" } == AIAgentImportedProvider(
            source: .ccSwitch,
            name: "Codex 中转",
            baseURL: "https://codex.example/v1",
            apiKey: "codex-secret",
            defaultModel: "gpt-5.6",
            protocolKind: .openAICompatible
        ))
        #expect(providers.first { $0.name == "Claude 中转" } == AIAgentImportedProvider(
            source: .ccSwitch,
            name: "Claude 中转",
            baseURL: "https://claude.example",
            apiKey: "claude-secret",
            defaultModel: "claude-opus-4-6",
            protocolKind: .anthropicMessages
        ))
        #expect(providers.first { $0.name == "Gemini 中转" } == AIAgentImportedProvider(
            source: .ccSwitch,
            name: "Gemini 中转",
            baseURL: "https://gemini.example",
            apiKey: "gemini-secret",
            defaultModel: "gemini-3-pro",
            protocolKind: .geminiGenerateContent
        ))
    }

    @Test
    func importedSecretsStayOutOfAgentStateAndExistingProviderKeyIsUpdated() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = DatabaseAIAgentSecretStore(storageURL: directory.appendingPathComponent("secrets.sqlite"))
        let stateURL = directory.appendingPathComponent("agent.json")
        let store = AIAgentStore(storageURL: stateURL, secretStore: secrets)
        let provider = AIAgentImportedProvider(
            source: .ccSwitch,
            name: "中转",
            baseURL: "https://gateway.example/v1",
            apiKey: "super-secret",
            defaultModel: "gpt-5.6"
        )

        #expect(try store.importProviders([provider]) == 1)
        var updatedProvider = provider
        updatedProvider.apiKey = "updated-secret"
        #expect(try store.importProviders([updatedProvider]) == 1)
        store.flushPendingChanges()

        let account = try #require(store.state.accounts.first)
        #expect(store.state.accounts.count == 1)
        #expect(store.state.channels.count == 1)
        #expect(try secrets.secret(for: account.secretReference) == "updated-secret")
        #expect(!String(decoding: try Data(contentsOf: stateURL), as: UTF8.self).contains("super-secret"))
        #expect(!String(decoding: try Data(contentsOf: stateURL), as: UTF8.self).contains("updated-secret"))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-provider-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func createCCSwitchDatabase(at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database else {
            sqlite3_close(database)
            Issue.record("无法创建测试数据库")
            return
        }
        defer { sqlite3_close(database) }
        try execute("CREATE TABLE providers (id TEXT, app_type TEXT, name TEXT, settings_config TEXT, sort_index INTEGER)", database: database)
        try execute("CREATE TABLE provider_endpoints (provider_id TEXT, app_type TEXT, url TEXT)", database: database)
        try execute("INSERT INTO providers VALUES ('codex-1', 'codex', 'Codex 中转', '{\"auth\":{\"OPENAI_API_KEY\":\"codex-secret\"},\"config\":\"model = \\\"gpt-5.6\\\"\\n[model_providers.custom]\\nbase_url = \\\"https://codex.example/v1\\\"\"}', 0)", database: database)
        try execute("INSERT INTO providers VALUES ('claude-1', 'claude', 'Claude 中转', '{\"env\":{\"ANTHROPIC_AUTH_TOKEN\":\"claude-secret\",\"ANTHROPIC_BASE_URL\":\"https://claude.example\"},\"model\":\"claude-opus-4-6\"}', 1)", database: database)
        try execute("INSERT INTO providers VALUES ('gemini-1', 'gemini', 'Gemini 中转', '{\"env\":{\"GEMINI_API_KEY\":\"gemini-secret\",\"GOOGLE_GEMINI_BASE_URL\":\"https://gemini.example\"},\"model\":\"gemini-3-pro\"}', 2)", database: database)
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            defer { sqlite3_free(error) }
            let detail = error.map { String(cString: $0) } ?? "SQLite 测试失败"
            throw NSError(domain: "AIAgentConfigurationImporterTests", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
        }
    }
}
