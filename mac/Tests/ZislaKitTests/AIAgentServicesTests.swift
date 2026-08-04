import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct AIAgentServicesTests {
    @Test
    func skillPackageInstallationDetectsGlobalManagersAndScopedPackages() throws {
        let npm = try #require(AgentSkillPackageInstallation.detect(
            at: URL(fileURLWithPath: "/Users/test/.nvm/versions/node/v24/lib/node_modules/@scope/tool/skills/review")
        ))
        #expect(npm.manager == .npm)
        #expect(npm.packageName == "@scope/tool")
        #expect(npm.uninstallArguments == ["uninstall", "--global", "@scope/tool"])

        let pnpm = try #require(AgentSkillPackageInstallation.detect(
            at: URL(fileURLWithPath: "/Users/test/Library/pnpm/global/5/node_modules/tool/skills/review")
        ))
        #expect(pnpm.manager == .pnpm)
        #expect(pnpm.packageName == "tool")

        let brew = try #require(AgentSkillPackageInstallation.detect(
            at: URL(fileURLWithPath: "/opt/homebrew/Cellar/tool/1.2.3/share/skills/review")
        ))
        #expect(brew.manager == .brew)
        #expect(brew.packageName == "tool")
        #expect(brew.uninstallArguments == ["uninstall", "tool"])

        #expect(AgentSkillPackageInstallation.detect(
            at: URL(fileURLWithPath: "/Users/test/.codex/skills/local-skill")
        ) == nil)
    }

    @Test
    func automationLoopOnlyRunsWhileAnEnabledAutomationExists() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-automation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIAgentStore(storageURL: directory.appendingPathComponent("state.json"))
        let workspace = AIAgentWorkspace(store: store)

        workspace.startAutomation()
        #expect(!workspace.isAutomationLoopRunning)

        var automation = AgentAutomation(
            name: "定时检测",
            task: .cliCheck,
            isEnabled: true,
            nextRunAt: .distantFuture
        )
        store.updateAutomation(automation)
        await Task.yield()
        #expect(workspace.isAutomationLoopRunning)

        automation.isEnabled = false
        store.updateAutomation(automation)
        await Task.yield()
        #expect(!workspace.isAutomationLoopRunning)
    }

    @Test
    func newAPIQuotaProbeUsesRootUserEndpointAndParsesAvailableQuota() async throws {
        AIAgentURLProtocol.responseData = Data(#"{"data":{"quota":100,"used_quota":25}}"#.utf8)
        AIAgentURLProtocol.statusCode = 200
        AIAgentURLProtocol.lastRequest = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIAgentURLProtocol.self]
        let service = AIAgentBalanceService(session: URLSession(configuration: configuration))
        let account = AgentAccount(
            name: "测试账号",
            provider: "New API",
            balanceProbe: AgentBalanceProbe(kind: .newAPIQuota)
        )

        let balance = try await service.check(
            account: account,
            baseURL: "https://gateway.example/v1",
            apiKey: "test-key"
        )

        #expect(balance.available == 75)
        #expect(balance.used == 25)
        #expect(balance.currency == "quota")
        let request = try #require(AIAgentURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://gateway.example/api/user/self")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    }

    @Test
    func providerModelCatalogUsesVersionedModelsEndpoint() async throws {
        AIAgentURLProtocol.responseData = Data(#"{"data":[{"id":"gpt-5"},{"id":"gpt-4.1"}]}"#.utf8)
        AIAgentURLProtocol.statusCode = 200
        AIAgentURLProtocol.lastRequest = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIAgentURLProtocol.self]
        let service = AIAgentModelCatalogService(session: URLSession(configuration: configuration))
        let route = AgentRoute(
            channelID: UUID(),
            endpointGroupID: UUID(),
            accountID: UUID(),
            baseURL: "https://gateway.example/v1",
            protocolKind: .openAICompatible,
            model: "placeholder"
        )

        let catalog = await service.fetch(route: route, apiKey: "test-key")

        #expect(catalog.models == ["gpt-4.1", "gpt-5"])
        #expect(AIAgentURLProtocol.lastRequest?.url?.absoluteString == "https://gateway.example/v1/models")
    }

    @Test
    func failedModelRefreshKeepsExistingCatalog() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-catalog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let channelID = UUID()
        let groupID = UUID()
        let store = AIAgentStore(storageURL: directory.appendingPathComponent("state.json"))
        let cached = AgentChannelModelCatalog(
            channelID: channelID,
            endpointGroupID: groupID,
            baseURL: "https://gateway.example/v1",
            models: ["gpt-5"]
        )

        store.replaceModelCatalog(cached)
        store.replaceModelCatalog(AgentChannelModelCatalog(
            channelID: channelID,
            endpointGroupID: groupID,
            baseURL: "https://gateway.example/v1",
            models: [],
            detail: "渠道请求失败"
        ))

        #expect(store.models(for: channelID) == ["gpt-5"])
    }

    @Test
    func cliProfileSwitchRestoresFirstFileWhenSecondWriteFails() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-profile-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blockedParent = directory.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blockedParent)
        let configurationURL = blockedParent.appendingPathComponent("config.toml")
        let authenticationURL = directory.appendingPathComponent("auth.json")
        try Data("old-auth".utf8).write(to: authenticationURL)
        let profile = AgentCLIProfile(
            cliKind: .codex,
            configurationFilePath: configurationURL.path,
            authenticationFilePath: authenticationURL.path
        )

        #expect(throws: Error.self) {
            try AIAgentCLIProfileService().activate(
                profile: profile,
                contents: (Data("new-config".utf8), Data("new-auth".utf8))
            )
        }

        #expect(String(decoding: try Data(contentsOf: authenticationURL), as: UTF8.self) == "old-auth")
        #expect(!FileManager.default.fileExists(atPath: configurationURL.path))
    }

    @Test
    func cliProfileSwitchReplacesConfigurationAndAuthenticationTogether() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-profile-success-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configurationURL = directory.appendingPathComponent("config.toml")
        let authenticationURL = directory.appendingPathComponent("auth.json")
        try Data("old-config".utf8).write(to: configurationURL)
        try Data("old-auth".utf8).write(to: authenticationURL)
        let profile = AgentCLIProfile(
            cliKind: .codex,
            configurationFilePath: configurationURL.path,
            authenticationFilePath: authenticationURL.path
        )

        try AIAgentCLIProfileService().activate(
            profile: profile,
            contents: (Data("new-config".utf8), Data("new-auth".utf8))
        )

        #expect(String(decoding: try Data(contentsOf: configurationURL), as: UTF8.self) == "new-config")
        #expect(String(decoding: try Data(contentsOf: authenticationURL), as: UTF8.self) == "new-auth")
    }

    @Test
    func applicationDatabaseStoresCLIProfileContent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-secrets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("secrets.sqlite")
        let store = DatabaseAIAgentSecretStore(storageURL: storageURL)

        try store.setSecret("auth-token", for: "account.auth")

        #expect(try store.secret(for: "account.auth") == "auth-token")
        #expect(FileManager.default.fileExists(atPath: storageURL.path))
    }

    @Test
    func relayPromptIncludesMultipleExplicitSkillAndAppReferences() {
        let message = AgentChatMessage(
            role: .user,
            content: "检查发布风险",
            appReferences: [
                AgentChatAppReference(name: "Codex", bundleIdentifier: "com.openai.codex", processIdentifier: 42),
                AgentChatAppReference(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", processIdentifier: 84),
            ],
            skillReferences: [
                AgentChatSkillReference(name: "release-plan", path: "/skills/release-plan"),
                AgentChatSkillReference(name: "code-review", path: "/skills/code-review"),
            ]
        )

        let project = AgentChatProject(name: "发布", instructions: "保持兼容性")
        let prompt = AIAgentCLIService().relayPrompt(
            [AgentChatMessage(role: .user, content: "先前消息", skillReferences: message.skillReferences), message],
            project: project,
            accessMode: .fullAccess,
            model: "gpt-5.6",
            thinkingDepth: .extraHigh
        )

        #expect(prompt.contains("[调用 Skills]"))
        #expect(prompt.contains("release-plan：/skills/release-plan"))
        #expect(prompt.contains("code-review：/skills/code-review"))
        #expect(prompt.contains("不要假设本应用执行了该 Skill"))
        #expect(prompt.contains("[项目：发布]"))
        #expect(prompt.contains("项目说明：保持兼容性"))
        #expect(prompt.contains("[@本机 App]"))
        #expect(prompt.contains("Codex（com.openai.codex，PID 42）"))
        #expect(prompt.contains("Xcode（com.apple.dt.Xcode，PID 84）"))
        #expect(prompt.contains("访问模式：完全访问"))
        #expect(prompt.contains("模型：gpt-5.6"))
        #expect(prompt.contains("思考深度：极高"))
        #expect(prompt.components(separatedBy: "[调用 Skills]").count == 2)
    }

    @Test
    func relayUsesTheExistingProjectDirectoryAsItsWorkingDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-project-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let service = AIAgentCLIService()

        let project = AgentChatProject(name: "项目", directoryPath: root.path)
        let missingProject = AgentChatProject(
            name: "失效项目",
            directoryPath: root.appendingPathComponent("missing", isDirectory: true).path
        )

        #expect(service.relayWorkingDirectory(for: project) == root)
        #expect(service.relayWorkingDirectory(for: missingProject) == FileManager.default.homeDirectoryForCurrentUser)
    }

    @Test
    func relayPromptEmitsGoalSectionWithoutPlanMode() {
        let service = AIAgentCLIService()
        let goalOnly = service.relayPrompt([
            AgentChatMessage(role: .user, content: "继续推进", mode: .standard, goalTitle: "完成 v0.1.1 发布"),
        ])

        #expect(goalOnly.contains("[目标模式]"))
        #expect(goalOnly.contains("当前会话目标：完成 v0.1.1 发布"))
        #expect(!goalOnly.contains("[计划模式]"))

        let planOnly = service.relayPrompt([
            AgentChatMessage(role: .user, content: "拆分里程碑", mode: .plan),
        ])

        #expect(planOnly.contains("[计划模式]"))
        #expect(!planOnly.contains("[目标模式]"))

        let both = service.relayPrompt([
            AgentChatMessage(role: .user, content: "拆分里程碑", mode: .plan, goalTitle: "完成 v0.1.1 发布"),
        ])

        #expect(both.contains("[计划模式]"))
        #expect(both.contains("[目标模式]"))
    }

    @Test
    func cliDiscoveryUsesNPMGlobalPathAndResolvesSymlinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-discovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("tools/codex")
        try writeExecutable(at: target)
        let launcher = root.appendingPathComponent(".npm-global/bin/codex")
        try FileManager.default.createDirectory(
            at: launcher.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: target)

        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin"], homeDirectory: root)

        #expect(try #require(service.executableURL(for: .codex)).path == target.path)
    }

    @Test
    func cliDiscoveryIncludesFNMAndNVMVersionDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-node-managers-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fnmGemini = root.appendingPathComponent(".fnm/node-versions/v24/installation/bin/gemini")
        let nvmClaude = root.appendingPathComponent(".nvm/versions/node/v22/bin/claude")
        try writeExecutable(at: fnmGemini)
        try writeExecutable(at: nvmClaude)

        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin"], homeDirectory: root)

        #expect(try #require(service.executableURL(for: .gemini)).path == fnmGemini.path)
        #expect(try #require(service.executableURL(for: .claude)).path == nvmClaude.path)
    }

    @Test
    func cliManagementBuildsBatchInstallUpdateAndUninstallCommands() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-commands-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let npm = root.appendingPathComponent(".npm-global/bin/npm")
        let grok = root.appendingPathComponent(".grok/bin/grok")
        try writeExecutable(at: npm)
        try writeExecutable(at: grok)
        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin"], homeDirectory: root)

        let installs = service.installationCommands(for: [.claude, .codex, .grok], update: false)
        let installNPM = try #require(installs.first { $0.executableURL == npm })
        let installGrok = try #require(installs.first { $0.executableURL.path == "/bin/bash" })
        #expect(installNPM.arguments == ["install", "--global", "@anthropic-ai/claude-code", "@openai/codex"])
        #expect(installGrok.arguments == ["-c", "curl -fsSL https://x.ai/cli/install.sh | bash"])

        let updates = service.installationCommands(for: [.claude, .grok], update: true)
        let updateNPM = try #require(updates.first { $0.executableURL == npm })
        let updateGrok = try #require(updates.first { $0.executableURL == grok })
        #expect(updateNPM.arguments == ["install", "--global", "@anthropic-ai/claude-code@latest"])
        #expect(updateGrok.arguments == ["update"])

        let uninstalls = service.uninstallationCommands(for: [.claude, .codex, .grok])
        let uninstallNPM = try #require(uninstalls.first { $0.executableURL == npm })
        let uninstallGrok = try #require(uninstalls.first { $0.executableURL.path == "/bin/rm" })
        #expect(uninstallNPM.arguments == ["uninstall", "--global", "@anthropic-ai/claude-code", "@openai/codex"])
        #expect(uninstallGrok.arguments == [grok.path])
    }

    private func writeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

private final class AIAgentURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var lastRequest: URLRequest?

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
