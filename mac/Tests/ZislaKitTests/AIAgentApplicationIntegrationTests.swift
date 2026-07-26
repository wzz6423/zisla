import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@MainActor
struct AIAgentApplicationIntegrationTests {
    @Test
    func claudeCodeSettingsMergeProviderValuesWithoutCopyingSecretsAndRestoreOnDisable() throws {
        let root = temporaryDirectory(named: "claude-code-settings")
        defer { try? FileManager.default.removeItem(at: root) }
        let settingsURL = root.appendingPathComponent("Code/User/settings.json")
        try writeJSON([
            "workbench.colorTheme": "Light",
            "claudeCode.environmentVariables": [
                ["name": "UNRELATED", "value": "kept"],
                ["name": "ANTHROPIC_BASE_URL", "value": "https://official.example"],
            ],
            "claudeCode.hideOnboarding": false,
        ], to: settingsURL)
        let configuration = try JSONSerialization.data(withJSONObject: [
            "env": [
                "ANTHROPIC_BASE_URL": "https://gateway.example",
                "ANTHROPIC_API_KEY": "must-not-be-written",
                "ANTHROPIC_AUTH_TOKEN": "must-not-be-written",
            ],
        ])
        let service = ClaudeCodeVSCodeSettingsService(settingsURL: settingsURL)

        let enabled = try service.reconcile(
            configuration: configuration,
            enhancements: AgentApplicationEnhancements(
                claudeCodeVSCodeFollowsProvider: true,
                skipsClaudeCodeOnboarding: true
            )
        )
        let during = try json(at: settingsURL)
        let settingsEnvironment = try #require(environment(in: during))

        #expect(settingsEnvironment["UNRELATED"] == "kept")
        #expect(settingsEnvironment["ANTHROPIC_BASE_URL"] == "https://gateway.example")
        #expect(settingsEnvironment["ANTHROPIC_API_KEY"] == nil)
        #expect(settingsEnvironment["ANTHROPIC_AUTH_TOKEN"] == nil)
        #expect(during["claudeCode.hideOnboarding"] as? Bool == true)
        #expect(enabled.claudeCodeVSCodeSettingsSnapshot != nil)

        let restored = try service.reconcile(
            configuration: nil,
            enhancements: AgentApplicationEnhancements(
                claudeCodeVSCodeSettingsSnapshot: enabled.claudeCodeVSCodeSettingsSnapshot
            )
        )
        let after = try json(at: settingsURL)
        let restoredEnvironment = try #require(environment(in: after))

        #expect(restoredEnvironment["UNRELATED"] == "kept")
        #expect(restoredEnvironment["ANTHROPIC_BASE_URL"] == "https://official.example")
        #expect(after["claudeCode.hideOnboarding"] as? Bool == false)
        #expect(restored.claudeCodeVSCodeSettingsSnapshot == nil)
    }

    @Test
    func codexHistoryImporterCreatesStableUnifiedThreadsWithoutReadingReasoningPayloads() throws {
        let root = temporaryDirectory(named: "codex-history")
        defer { try? FileManager.default.removeItem(at: root) }
        let rollout = root.appendingPathComponent("2026/07/28/rollout-example.jsonl")
        try FileManager.default.createDirectory(at: rollout.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lines = [
            #"{"timestamp":"2026-07-28T01:00:00.000Z","type":"session_meta","payload":{"id":"codex-session-1"}}"#,
            #"{"timestamp":"2026-07-28T01:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"请修复测试"}}"#,
            #"{"timestamp":"2026-07-28T01:00:02.000Z","type":"response_item","payload":{"type":"reasoning","encrypted_content":"not imported"}}"#,
            #"{"timestamp":"2026-07-28T01:00:03.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"已修复"}]}}"#,
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: rollout)
        let index = root.appendingPathComponent("session_index.jsonl")
        try Data(#"{"id":"codex-session-1","thread_name":"测试修复"}"#.utf8).write(to: index)

        let threads = CodexSessionHistoryImporter(
            sessionsDirectory: root,
            sessionIndexURL: index
        ).importThreads()
        let thread = try #require(threads.first)

        #expect(thread.externalHistoryID == "codex:codex-session-1")
        #expect(thread.title == "测试修复")
        #expect(thread.cliKind == .codex)
        #expect(thread.messages.map(\.role) == [.user, .assistant])
        #expect(thread.messages.map(\.content) == ["请修复测试", "已修复"])
    }

    @Test
    func configurationOnlyProfileActivationLeavesAuthenticationUntouched() throws {
        let root = temporaryDirectory(named: "codex-profile")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configurationURL = root.appendingPathComponent("config.toml")
        let authenticationURL = root.appendingPathComponent("auth.json")
        try Data("old-route".utf8).write(to: configurationURL)
        try Data("official-login".utf8).write(to: authenticationURL)
        let profile = AgentCLIProfile(
            cliKind: .codex,
            configurationFilePath: configurationURL.path,
            authenticationFilePath: authenticationURL.path
        )

        try AIAgentCLIProfileService().activateConfiguration(
            profile: profile,
            configuration: Data("third-party-route".utf8)
        )

        #expect(try String(decoding: Data(contentsOf: configurationURL), as: UTF8.self) == "third-party-route")
        #expect(try String(decoding: Data(contentsOf: authenticationURL), as: UTF8.self) == "official-login")
    }

    @Test
    func routeTakeoverAlwaysPreservesCodexAuthentication() {
        #expect(CodexOfficialLoginPolicy.preservesAuthentication(
            for: .codex,
            userPreference: false,
            isRouteTakeover: true
        ))
        #expect(!CodexOfficialLoginPolicy.preservesAuthentication(
            for: .codex,
            userPreference: false,
            isRouteTakeover: false
        ))
        #expect(!CodexOfficialLoginPolicy.preservesAuthentication(
            for: .claude,
            userPreference: true,
            isRouteTakeover: true
        ))
    }

    @Test
    func importedCodexHistoryIsDeduplicatedAndRemovedWithoutTouchingLocalThreads() throws {
        let root = temporaryDirectory(named: "codex-history-store")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIAgentStore(
            storageURL: root.appendingPathComponent("state.json"),
            secretStore: TestSecretStore()
        )
        let local = store.createThread(title: "本地会话")
        let imported = AgentChatThread(
            title: "Codex 会话",
            cliKind: .codex,
            externalHistoryID: "codex:session-1",
            messages: [AgentChatMessage(role: .user, content: "历史消息")]
        )

        store.importCodexHistory([imported])
        store.importCodexHistory([imported])
        #expect(store.state.chatThreads.filter { $0.externalHistoryID == "codex:session-1" }.count == 1)

        store.removeImportedCodexHistory()
        #expect(store.state.chatThreads.map(\.id) == [local.id])
    }
}

private func temporaryDirectory(named name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func writeJSON(_ object: [String: Any], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: object)
    try data.write(to: url)
}

private func json(at url: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

private func environment(in settings: [String: Any]) -> [String: String]? {
    guard let values = settings["claudeCode.environmentVariables"] as? [[String: Any]] else { return nil }
    return Dictionary(uniqueKeysWithValues: values.compactMap { value in
        guard let name = value["name"] as? String, let content = value["value"] as? String else { return nil }
        return (name, content)
    })
}

private final class TestSecretStore: AIAgentSecretStoring, @unchecked Sendable {
    func secret(for reference: String) throws -> String? { nil }
    func setSecret(_ secret: String, for reference: String) throws {}
    func removeSecret(for reference: String) throws {}
}
