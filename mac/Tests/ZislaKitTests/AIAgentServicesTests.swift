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
    func cliCommandProgressPersistsOutsideTheSettingsView() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-command-progress-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = AIAgentWorkspace(
            store: AIAgentStore(storageURL: directory.appendingPathComponent("state.json")),
            cliService: AIAgentCLIService(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: directory),
            cliUpdateService: AIAgentCLIUpdateService(loadLatestVersion: { _ in nil })
        )
        let command = AIAgentCLICommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 0.15"]
        )

        workspace.startCLICommands([command], title: "更新测试 CLI", kinds: [.codex])

        #expect(workspace.isRunningCLICommands)
        #expect(workspace.cliCommandProgress?.state == .running)
        #expect(workspace.cliCommandProgress?.completedCount == 0)
        try await Task.sleep(for: .milliseconds(25))
        #expect(workspace.isRunningCLICommands)
        await waitForCLICommandRunToFinish(workspace)

        #expect(!workspace.isRunningCLICommands)
        #expect(workspace.cliCommandProgress?.state == .succeeded)
        #expect(workspace.cliCommandProgress?.completedCount == 1)
        #expect(workspace.cliCommandProgress?.detail == "已重新检测 CLI 版本")
    }

    @Test
    func cliCommandProgressKeepsTheFailureDetail() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-command-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = AIAgentWorkspace(
            store: AIAgentStore(storageURL: directory.appendingPathComponent("state.json")),
            cliService: AIAgentCLIService(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: directory),
            cliUpdateService: AIAgentCLIUpdateService(loadLatestVersion: { _ in nil })
        )
        let command = AIAgentCLICommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo upgrade-failed >&2; exit 9"]
        )

        workspace.startCLICommands([command], title: "更新测试 CLI", kinds: [.gemini])
        await waitForCLICommandRunToFinish(workspace)

        #expect(workspace.cliCommandProgress?.state == .failed)
        #expect(workspace.cliCommandProgress?.detail == "upgrade-failed")
        #expect(workspace.lastError == "upgrade-failed")
    }

    @Test
    func cliCommandProgressExplainsTheHomebrewTrustRequirement() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-command-homebrew-trust-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = AIAgentWorkspace(
            store: AIAgentStore(storageURL: directory.appendingPathComponent("state.json")),
            cliService: AIAgentCLIService(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: directory),
            cliUpdateService: AIAgentCLIUpdateService(loadLatestVersion: { _ in nil })
        )
        let command = AIAgentCLICommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '%s\\n' 'Error: Refusing to load formula anomalyco/tap/opencode from untrusted tap anomalyco/tap.' 'Run `brew trust --formula anomalyco/tap/opencode` or `brew trust anomalyco/tap` to trust it.' >&2; exit 1"]
        )

        workspace.startCLICommands([command], title: "更新测试 CLI", kinds: [.opencode])
        await waitForCLICommandRunToFinish(workspace)

        #expect(workspace.cliCommandProgress?.detail == "Homebrew 需要先信任该公式：brew trust --formula anomalyco/tap/opencode")
    }

    @Test
    func cliCommandProgressRunsIndependentCommandsInParallel() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-command-parallel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let workspace = AIAgentWorkspace(
            store: AIAgentStore(storageURL: directory.appendingPathComponent("state.json")),
            cliService: AIAgentCLIService(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: directory),
            cliUpdateService: AIAgentCLIUpdateService(loadLatestVersion: { _ in nil })
        )
        let firstStarted = directory.appendingPathComponent("first-started")
        let secondStarted = directory.appendingPathComponent("second-started")
        let commands = [
            AIAgentCLICommand(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", parallelCommand(startedAt: firstStarted, waitingFor: secondStarted)]
            ),
            AIAgentCLICommand(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", parallelCommand(startedAt: secondStarted, waitingFor: firstStarted)]
            ),
        ]

        workspace.startCLICommands(commands, title: "更新测试 CLI", kinds: [.claude, .codex])
        await waitForCLICommandRunToFinish(workspace)

        #expect(workspace.cliCommandProgress?.state == .succeeded)
        #expect(workspace.cliCommandProgress?.completedCount == 2)
    }

    @Test
    func cliCommandProgressWaitsForOtherCommandsAfterAFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-command-independent-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let completionFile = directory.appendingPathComponent("successful-update")
        let workspace = AIAgentWorkspace(
            store: AIAgentStore(storageURL: directory.appendingPathComponent("state.json")),
            cliService: AIAgentCLIService(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: directory),
            cliUpdateService: AIAgentCLIUpdateService(loadLatestVersion: { _ in nil })
        )
        let commands = [
            AIAgentCLICommand(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo failed-update >&2; exit 9"]),
            AIAgentCLICommand(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 0.1; touch \(completionFile.path)"]),
        ]

        workspace.startCLICommands(commands, title: "更新测试 CLI", kinds: [.gemini, .grok])
        await waitForCLICommandRunToFinish(workspace)

        #expect(FileManager.default.fileExists(atPath: completionFile.path))
        #expect(workspace.cliCommandProgress?.state == .failed)
        #expect(workspace.cliCommandProgress?.completedCount == 2)
        #expect(workspace.lastError == "failed-update")
    }

    @Test
    func processRunnerMarksTimedOutCommands() async throws {
        let output = try await AIAgentProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 0.2"],
            timeout: 0.02
        )

        #expect(output.didTimeout)
        #expect(output.status != 0)
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
    func cliVersionDetectionUsesTheDiscoveredNodeRuntime() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-version-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtimeDirectory = root.appendingPathComponent("toolchain/bin", isDirectory: true)
        let node = runtimeDirectory.appendingPathComponent("node")
        try writeExecutable(at: node, contents: "#!/bin/sh\necho 'codex-cli 0.145.0'\n")

        let packageRoot = root.appendingPathComponent(".npm-global/lib/node_modules/@openai/codex", isDirectory: true)
        let target = packageRoot.appendingPathComponent("bin/codex.js")
        try writeExecutable(at: target, contents: "#!/usr/bin/env node\n")
        try Data(#"{"name":"@openai/codex","version":"0.145.0"}"#.utf8)
            .write(to: packageRoot.appendingPathComponent("package.json"))
        let launcher = root.appendingPathComponent(".npm-global/bin/codex")
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: target)

        let service = AIAgentCLIService(
            environment: ["PATH": "/usr/bin", "NPM_CONFIG_PREFIX": runtimeDirectory.deletingLastPathComponent().path],
            homeDirectory: root
        )

        let status = await service.status(for: .codex)

        #expect(status.executablePath == target.path)
        #expect(status.version == "codex-cli 0.145.0")
    }

    @Test
    func cliVersionDetectionFallsBackToInstalledPackageMetadata() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-package-version-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let packageRoot = root.appendingPathComponent(".npm-global/lib/node_modules/@google/gemini-cli", isDirectory: true)
        let target = packageRoot.appendingPathComponent("bundle/gemini.js")
        try writeExecutable(at: target, contents: "#!/usr/bin/env unavailable-node\n")
        try Data(#"{"name":"@google/gemini-cli","version":"0.46.0"}"#.utf8)
            .write(to: packageRoot.appendingPathComponent("package.json"))
        let launcher = root.appendingPathComponent(".npm-global/bin/gemini")
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: target)

        let status = await AIAgentCLIService(environment: ["PATH": "/usr/bin"], homeDirectory: root)
            .status(for: .gemini)

        #expect(status.executablePath == target.path)
        #expect(status.version == "0.46.0")
    }

    @Test
    func grokUpdateCheckDistinguishesCurrentAndAvailableVersions() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-grok-update-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let grok = root.appendingPathComponent(".grok/bin/grok")
        try writeExecutable(
            at: grok,
            contents: "#!/bin/sh\nprintf '%s' '{\"currentVersion\":\"1.0.0\",\"latestVersion\":\"1.0.0\",\"updateAvailable\":false,\"error\":null}'\n"
        )
        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin"], homeDirectory: root)

        #expect(await service.grokUpdateState() == .upToDate)

        try writeExecutable(
            at: grok,
            contents: "#!/bin/sh\nprintf '%s' '{\"currentVersion\":\"1.0.0\",\"latestVersion\":\"1.1.0\",\"updateAvailable\":true,\"error\":null}'\n"
        )

        #expect(await service.grokUpdateState() == .updateAvailable(AIAgentCLIUpdate(
            kind: .grok,
            installedVersion: "1.0.0",
            latestVersion: "1.1.0"
        )))
    }

    @Test
    func homebrewUpdateCheckUsesHomebrewReportedVersion() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-homebrew-update-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let brew = root.appendingPathComponent("toolchain/bin/brew")
        try writeExecutable(
            at: brew,
            contents: "#!/bin/sh\nprintf '%s' '{\"formulae\":[{\"name\":\"opencode\",\"current_version\":\"1.18.15\"}],\"casks\":[]}'\n"
        )
        let executable = root.appendingPathComponent("Cellar/opencode/1.18.14/bin/opencode")
        try writeExecutable(at: executable)
        let service = AIAgentCLIService(
            environment: ["PATH": "/usr/bin", "NPM_CONFIG_PREFIX": root.appendingPathComponent("toolchain").path],
            homeDirectory: root
        )

        let updates = await service.homebrewUpdates(for: [
            AgentCLIStatus(kind: .opencode, executablePath: executable.path, version: "1.18.14"),
        ])

        #expect(updates == [
            AIAgentCLIUpdate(kind: .opencode, installedVersion: "1.18.14", latestVersion: "1.18.15"),
        ])
    }

    @Test
    func cliUpdateUsesTheDetectedPackageManager() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-update-manager-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let toolDirectory = root.appendingPathComponent("toolchain/bin", isDirectory: true)
        let brew = toolDirectory.appendingPathComponent("brew")
        try writeExecutable(at: brew)
        let target = root.appendingPathComponent("Cellar/opencode/1.4.6/bin/opencode")
        try writeExecutable(at: target)
        let launcher = root.appendingPathComponent(".local/bin/opencode")
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: target)
        let service = AIAgentCLIService(
            environment: ["PATH": "/usr/bin", "NPM_CONFIG_PREFIX": toolDirectory.deletingLastPathComponent().path],
            homeDirectory: root
        )

        let commands = service.installationCommands(for: [.opencode], update: true)

        #expect(commands == [AIAgentCLICommand(
            executableURL: brew,
            arguments: ["upgrade", "opencode"],
            timeout: 600
        )])
        #expect(commands.first?.timeout == 600)
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
        #expect(updateNPM.timeout == 600)
        #expect(updateGrok.timeout == 600)

        let uninstalls = service.uninstallationCommands(for: [.claude, .codex, .grok])
        let uninstallNPM = try #require(uninstalls.first { $0.executableURL == npm })
        let uninstallGrok = try #require(uninstalls.first { $0.executableURL.path == "/bin/rm" })
        #expect(uninstallNPM.arguments == ["uninstall", "--global", "@anthropic-ai/claude-code", "@openai/codex"])
        #expect(uninstallGrok.arguments == [grok.path])
    }

    private func writeExecutable(at url: URL, contents: String = "#!/bin/sh\nexit 0\n") throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func waitForCLICommandRunToFinish(_ workspace: AIAgentWorkspace) async {
        for _ in 0..<100 where workspace.isRunningCLICommands {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func parallelCommand(startedAt: URL, waitingFor peer: URL) -> String {
        "touch '\(startedAt.path)'; for _ in $(seq 1 50); do [ -f '\(peer.path)' ] && exit 0; sleep 0.01; done; exit 1"
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
