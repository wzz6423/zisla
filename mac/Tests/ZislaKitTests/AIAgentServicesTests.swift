import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct AIAgentServicesTests {
    @Test
    func skillScanDeduplicatesLinkedRootsUsingManagedPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-skill-scan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let linkedRoot = root.appendingPathComponent("codex/skills", isDirectory: true)
        let skillFile = managed.appendingPathComponent("review/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(
            at: skillFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("review".utf8).write(to: skillFile)
        try FileManager.default.createDirectory(
            at: linkedRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: managed)

        let skills = AIAgentSkillService().scan(roots: [linkedRoot, managed])

        #expect(skills.count == 1)
        #expect(skills.first?.path.hasSuffix("/managed/review") == true)
    }

    @Test
    func skillScanReadsDescriptionFromFrontMatter() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-skill-description-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let skillFile = root.appendingPathComponent("review/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(
            at: skillFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("""
        ---
        name: review
        description: \"A long skill description that should remain available to the UI.\"
        ---
        # Review
        """.utf8).write(to: skillFile)

        let skill = try #require(AIAgentSkillService().scan(roots: [root]).first)

        #expect(skill.description == "A long skill description that should remain available to the UI.")
    }

    @Test
    func skillScanKeepsOneCaseInsensitiveNameUsingRootPriority() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-skill-name-dedup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let claude = root.appendingPathComponent("claude", isDirectory: true)
        let skillFiles = [
            managed.appendingPathComponent("review/SKILL.md"),
            codex.appendingPathComponent("Review/SKILL.md"),
            claude.appendingPathComponent("review/SKILL.md"),
            claude.appendingPathComponent("unique/SKILL.md"),
        ]
        for skillFile in skillFiles {
            try FileManager.default.createDirectory(
                at: skillFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(skillFile.path.utf8).write(to: skillFile)
        }

        let skills = AIAgentSkillService().scan(roots: [managed, codex, claude])

        #expect(skills.count == 2)
        let review = try #require(skills.first { $0.name.lowercased() == "review" })
        #expect(review.path.hasSuffix("/managed/review"))
        #expect(skills.contains { $0.name == "unique" })
    }

    @Test
    func managedSkillDestinationsUseEntireSkillsRoots() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-managed-skill-paths-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = AIAgentWorkspace(
            store: AIAgentStore(storageURL: directory.appendingPathComponent("state.json"))
        )
        let home = FileManager.default.homeDirectoryForCurrentUser

        #expect(workspace.managedSkillDestinationDirectory(for: .codex) == home.appendingPathComponent(".codex/skills", isDirectory: true))
        #expect(workspace.managedSkillDestinationDirectory(for: .claude) == home.appendingPathComponent(".claude/skills", isDirectory: true))
        #expect(workspace.managedSkillDestinationDirectory(for: .agents) == home.appendingPathComponent(".agents/skills", isDirectory: true))
        #expect(workspace.managedSkillBackupRootDirectory == home.appendingPathComponent(".zisla/skill-backups", isDirectory: true))
        #expect(workspace.managedSkillBackupDirectory(for: .codex) == home.appendingPathComponent(".zisla/skill-backups/codex", isDirectory: true))
        #expect(workspace.managedSkillBackupDirectory(for: .claude) == home.appendingPathComponent(".zisla/skill-backups/claude", isDirectory: true))
        #expect(workspace.managedSkillBackupDirectory(for: .agents) == home.appendingPathComponent(".zisla/skill-backups/agents", isDirectory: true))
    }

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

        let cask = try #require(AgentSkillPackageInstallation.detect(
            at: URL(fileURLWithPath: "/opt/homebrew/Caskroom/copilot-cli/1.0.34/copilot")
        ))
        #expect(cask.manager == .brew)
        #expect(cask.packageName == "copilot-cli")

        #expect(AgentSkillPackageInstallation.detect(
            at: URL(fileURLWithPath: "/Users/test/.codex/skills/local-skill")
        ) == nil)
    }

    @Test
    func cliAutoUpdateRunsByDefault() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-auto-update-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let toolDirectory = directory.appendingPathComponent("toolchain/bin", isDirectory: true)
        let updateMarker = directory.appendingPathComponent("updated")
        let codex = toolDirectory.appendingPathComponent("codex")
        let npm = toolDirectory.appendingPathComponent("npm")
        try writeExecutable(at: codex, contents: "#!/bin/sh\nprintf '1.0.0\\n'\n")
        try writeExecutable(at: npm, contents: "#!/bin/sh\ntouch '\(updateMarker.path)'\n")
        let store = AIAgentStore(storageURL: directory.appendingPathComponent("state.json"))
        let workspace = AIAgentWorkspace(
            store: store,
            cliService: AIAgentCLIService(
                environment: ["PATH": "\(toolDirectory.path):/usr/bin:/bin"],
                homeDirectory: directory
            ),
            cliUpdateService: AIAgentCLIUpdateService(loadLatestVersion: { kind in
                kind == .codex ? "1.1.0" : nil
            })
        )

        workspace.start()
        #expect(await waitForCLIUpdate(workspace, kind: .codex))
        await waitForFile(at: updateMarker)
        await waitForCLICommandRunToFinish(workspace)

        #expect(store.state.cliAutoUpdateEnabled)
        #expect(FileManager.default.fileExists(atPath: updateMarker.path))

        workspace.setCLIAutoUpdateEnabled(false)
        #expect(!store.state.cliAutoUpdateEnabled)
    }

    @Test
    func cliAutoUpdateRunsWhenEnabledBeforeWorkspaceStart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-auto-update-on-start-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let toolDirectory = directory.appendingPathComponent("toolchain/bin", isDirectory: true)
        let updateMarker = directory.appendingPathComponent("updated")
        let codex = toolDirectory.appendingPathComponent("codex")
        let npm = toolDirectory.appendingPathComponent("npm")
        try writeExecutable(at: codex, contents: "#!/bin/sh\nprintf '1.0.0\\n'\n")
        try writeExecutable(at: npm, contents: "#!/bin/sh\ntouch '\(updateMarker.path)'\n")
        let store = AIAgentStore(storageURL: directory.appendingPathComponent("state.json"))
        let workspace = AIAgentWorkspace(
            store: store,
            cliService: AIAgentCLIService(
                environment: ["PATH": "\(toolDirectory.path):/usr/bin:/bin"],
                homeDirectory: directory
            ),
            cliUpdateService: AIAgentCLIUpdateService(loadLatestVersion: { kind in
                kind == .codex ? "1.1.0" : nil
            })
        )

        workspace.setCLIAutoUpdateEnabled(true)
        workspace.start()
        await waitForFile(at: updateMarker)
        await waitForCLICommandRunToFinish(workspace)

        #expect(store.state.cliAutoUpdateEnabled)
        #expect(FileManager.default.fileExists(atPath: updateMarker.path))
        #expect(workspace.cliCommandProgress?.title == "自动更新 Codex")
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
    func cliCommandRequestedDuringFailedGrokAutoUpdateRunsAfterIt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-command-queue-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let grokUpdateStarted = directory.appendingPathComponent("grok-update-started")
        let qwenInstalled = directory.appendingPathComponent("qwen-installed")
        let workspace = AIAgentWorkspace(
            store: AIAgentStore(storageURL: directory.appendingPathComponent("state.json")),
            cliService: AIAgentCLIService(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: directory),
            cliUpdateService: AIAgentCLIUpdateService(loadLatestVersion: { _ in nil })
        )
        let grokUpdate = AIAgentCLICommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "touch '\(grokUpdateStarted.path)'; sleep 0.15; echo grok-update-failed >&2; exit 9",
            ]
        )
        let qwenInstall = AIAgentCLICommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "touch '\(qwenInstalled.path)'"]
        )

        workspace.startCLICommands([grokUpdate], title: "自动更新 Grok", kinds: [.grok])
        await waitForFile(at: grokUpdateStarted)
        #expect(FileManager.default.fileExists(atPath: grokUpdateStarted.path))

        workspace.startCLICommands([qwenInstall], title: "下载 Qwen Code", kinds: [.qwen])
        await waitForFile(at: qwenInstalled)
        await waitForCLICommandRunToFinish(workspace)

        #expect(FileManager.default.fileExists(atPath: qwenInstalled.path))
        #expect(workspace.cliCommandProgress?.title == "下载 Qwen Code")
        #expect(workspace.cliCommandProgress?.state == .succeeded)
    }

    @Test
    func cliDownloadRequestedDuringRefreshRunsAfterRefreshCompletes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-refresh-queue-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let toolDirectory = directory.appendingPathComponent("bin", isDirectory: true)
        let refreshStarted = directory.appendingPathComponent("refresh-started")
        let releaseRefresh = directory.appendingPathComponent("release-refresh")
        let installMarker = directory.appendingPathComponent("install-completed")
        let claude = toolDirectory.appendingPathComponent("claude")
        try writeExecutable(
            at: claude,
            contents: "#!/bin/sh\ntouch '\(refreshStarted.path)'\nwhile [ ! -f '\(releaseRefresh.path)' ]; do sleep 0.01; done\nprintf 'Claude Code 1.0.0\\n'\n"
        )
        let workspace = AIAgentWorkspace(
            store: AIAgentStore(storageURL: directory.appendingPathComponent("state.json")),
            cliService: AIAgentCLIService(
                environment: ["PATH": "\(toolDirectory.path):/usr/bin:/bin"],
                homeDirectory: directory
            ),
            cliUpdateService: AIAgentCLIUpdateService(loadLatestVersion: { _ in nil })
        )
        let installCommand = AIAgentCLICommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "touch '\(installMarker.path)'"]
        )

        let refreshTask = Task { await workspace.refreshCLIs() }
        await waitForFile(at: refreshStarted)
        #expect(workspace.isCheckingCLIs)

        workspace.startCLICommands([installCommand], title: "下载 Qwen Code", kinds: [.qwen])
        try await Task.sleep(for: .milliseconds(50))
        #expect(!FileManager.default.fileExists(atPath: installMarker.path))

        try Data().write(to: releaseRefresh)
        await refreshTask.value
        await waitForFile(at: installMarker)
        await waitForCLICommandRunToFinish(workspace)

        #expect(FileManager.default.fileExists(atPath: installMarker.path))
        #expect(workspace.cliCommandProgress?.title == "下载 Qwen Code")
        #expect(workspace.cliCommandProgress?.state == .succeeded)
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
    func processRunnerHandlesChildClosingStandardInputEarly() async throws {
        let output = try await AIAgentProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"),
            standardInput: Data(repeating: 0x61, count: 1_048_576)
        )

        #expect(output.status == 1)
    }

    @Test
    func synchronousProcessRunnerUsesSharedOutputLimit() throws {
        let output = try AIAgentProcessRunner.runSynchronously(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["abcdef"],
            maximumOutputBytes: 3
        )

        #expect(output.status == 0)
        #expect(output.standardOutput == Data("abc".utf8))
    }

    @Test
    func processRunnerReturnsCompleteOutputBeyondFormerDefaultLimit() async throws {
        let byteCount = 4 * 1_024 * 1_024 + 1
        let output = try await AIAgentProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "/usr/bin/yes x | /usr/bin/head -c \(byteCount)"],
            timeout: 10
        )

        #expect(AIAgentProcessRunner.defaultMaximumOutputBytes == .max)
        #expect(AIAgentProcessRunner.defaultMaximumErrorBytes == .max)
        #expect(output.status == 0)
        #expect(output.standardOutput.count == byteCount)
    }

    @Test
    func processRunnerDoesNotWaitForDescendantHoldingPipesAfterParentExits() async throws {
        let startedAt = Date()
        let output = try await AIAgentProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 2 &"],
            timeout: 0.5
        )

        #expect(output.status == 0)
        #expect(!output.didTimeout)
        #expect(Date().timeIntervalSince(startedAt) < 1)
    }

    @Test
    func processRunnerKeepsParentOutputWhenDescendantHoldsPipes() async throws {
        let output = try await AIAgentProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "/usr/bin/printf complete; sleep 2 &"],
            timeout: 0.5
        )

        // Unblocking a pipe held by a grandchild must preserve output already produced by the parent.
        #expect(output.status == 0)
        #expect(!output.didTimeout)
        #expect(output.standardOutput == Data("complete".utf8))
    }

    @Test
    func processRunnerPropagatesTaskCancellation() async throws {
        let task = Task {
            try await AIAgentProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeout: 10
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        let cancellationStartedAt = Date()

        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Cancelled process should throw")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(Date().timeIntervalSince(cancellationStartedAt) < 1)
    }

    @Test
    func processRunnerCancellationDoesNotWaitForDescendantHoldingPipes() async throws {
        let task = Task {
            try await AIAgentProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "sleep 2 &"],
                timeout: 10
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        let cancellationStartedAt = Date()

        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Cancelled process should throw")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(Date().timeIntervalSince(cancellationStartedAt) < 1)
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
    func newAPIQuotaProbeKeepsUnversionedPathStartingWithV() async throws {
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

        _ = try await service.check(
            account: account,
            baseURL: "https://gateway.example/vendor",
            apiKey: "test-key"
        )

        #expect(AIAgentURLProtocol.lastRequest?.url?.absoluteString == "https://gateway.example/vendor/api/user/self")
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
    func providerModelCatalogAddsVersionAfterPathStartingWithV() async {
        AIAgentURLProtocol.responseData = Data(#"{"data":[{"id":"gpt-5"}]}"#.utf8)
        AIAgentURLProtocol.statusCode = 200
        AIAgentURLProtocol.lastRequest = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIAgentURLProtocol.self]
        let service = AIAgentModelCatalogService(session: URLSession(configuration: configuration))
        let route = AgentRoute(
            channelID: UUID(),
            endpointGroupID: UUID(),
            accountID: UUID(),
            baseURL: "https://gateway.example/vendor",
            protocolKind: .openAICompatible,
            model: "placeholder"
        )

        _ = await service.fetch(route: route, apiKey: "test-key")

        #expect(AIAgentURLProtocol.lastRequest?.url?.absoluteString == "https://gateway.example/vendor/v1/models")
    }

    @Test
    func apiFailuresDoNotExposeProviderResponseBody() async throws {
        AIAgentURLProtocol.responseData = Data(#"{"error":"secret-provider-body"}"#.utf8)
        AIAgentURLProtocol.statusCode = 500
        defer {
            AIAgentURLProtocol.responseData = Data()
            AIAgentURLProtocol.statusCode = 200
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIAgentURLProtocol.self]
        let account = AgentAccount(
            name: "测试账号",
            provider: "New API",
            balanceProbe: AgentBalanceProbe(kind: .newAPIQuota)
        )

        do {
            _ = try await AIAgentBalanceService(session: URLSession(configuration: configuration)).check(
                account: account,
                baseURL: "https://gateway.example/v1",
                apiKey: "secret-api-key"
            )
            Issue.record("HTTP 错误应抛出异常")
        } catch {
            #expect(error.localizedDescription == "渠道请求失败（HTTP 500）")
            #expect(!error.localizedDescription.contains("secret-provider-body"))
            #expect(!error.localizedDescription.contains("secret-api-key"))
        }
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
    func relayPromptBoundsAndSerializesVoiceMessages() {
        var messages = (0..<40).map { index in
            AIOutboundMessage(role: .user, content: String(format: "message-%02d-END", index))
        }
        messages.append(AIOutboundMessage(role: .tool, content: "tool-result"))

        let prompt = AIAgentCLIService().relayPrompt(messages)

        #expect(!prompt.contains("message-08-END"))
        #expect(prompt.contains("message-09-END"))
        #expect(prompt.contains("[用户]"))
        #expect(prompt.contains("[工具]\ntool-result"))
    }

    @Test
    func relayArgumentsUseFixedReadOnlyMediumConfiguration() {
        let service = AIAgentCLIService()
        let claude = service.relayArguments(for: .claude, model: "claude-opus-5")
        let codex = service.relayArguments(for: .codex, model: "gpt-5.6")
        let gemini = service.relayArguments(for: .gemini, model: "gemini-2.5-pro")
        let grok = service.relayArguments(for: .grok, model: "grok-4")
        let opencode = service.relayArguments(for: .opencode, model: "anthropic/claude-opus-5")

        for arguments in [claude, codex, gemini, grok, opencode] {
            #expect(arguments.contains("--model"))
            #expect(!arguments.contains("--dangerously-skip-permissions"))
            #expect(!arguments.contains("--dangerously-bypass-approvals-and-sandbox"))
            #expect(!arguments.contains("--auto"))
        }
        #expect(claude.contains("medium"))
        #expect(claude.contains("plan"))
        #expect(codex.contains(#"model_reasoning_effort="medium""#))
        #expect(codex.contains("read-only"))
        #expect(gemini.contains("plan"))
        #expect(grok.contains("medium"))
        #expect(grok.contains("plan"))
        #expect(!service.relayArguments(for: .claude, model: "  ").contains("--model"))
    }

    @Test
    func relayRunsFromConfiguredHomeDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-voice-cli-working-directory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("bin/codex")
        try writeExecutable(
            at: codex,
            contents: "#!/bin/sh\n/usr/bin/touch relay-working-directory-marker\nprintf 'ok\\n'\n"
        )
        let service = AIAgentCLIService(
            environment: ["PATH": codex.deletingLastPathComponent().path],
            homeDirectory: root
        )

        let response = try await service.relay(
            messages: [AIOutboundMessage(role: .user, content: "整理这段语音")],
            to: .codex
        )

        #expect(response == "ok")
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("relay-working-directory-marker").path
        ))
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
    func grokUpdateCheckFallsBackToInstallerVersionCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-grok-update-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let grok = root.appendingPathComponent(".grok/bin/grok")
        try writeExecutable(at: grok, contents: "#!/bin/sh\nprintf 'grok 1.0.0 (build)'\n")
        let cache = root.appendingPathComponent(".grok/version.json")
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"version\":\"1.0.3\"}".utf8).write(to: cache)
        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin"], homeDirectory: root)

        #expect(await service.grokUpdateState() == .updateAvailable(AIAgentCLIUpdate(
            kind: .grok,
            installedVersion: "grok 1.0.0 (build)",
            latestVersion: "1.0.3"
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
            contents: "#!/bin/sh\nprintf '%s' '{\"formulae\":[{\"name\":\"anomalyco/tap/opencode\",\"current_version\":\"1.18.15\"},{\"name\":\"kimi-code\",\"current_version\":\"0.35.0\"}],\"casks\":[]}'\n"
        )
        let executable = root.appendingPathComponent("Cellar/opencode/1.18.14/bin/opencode")
        let detectedOnlyExecutable = root.appendingPathComponent("Cellar/kimi-code/0.34.0/bin/kimi")
        try writeExecutable(at: executable)
        try writeExecutable(at: detectedOnlyExecutable)
        let service = AIAgentCLIService(
            environment: ["PATH": "/usr/bin", "NPM_CONFIG_PREFIX": root.appendingPathComponent("toolchain").path],
            homeDirectory: root
        )

        let updates = await service.homebrewUpdates(for: [
            AgentCLIStatus(kind: .opencode, executablePath: executable.path, version: "1.18.14"),
            AgentCLIStatus(kind: .kimi, executablePath: detectedOnlyExecutable.path, version: "0.34.0"),
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

    @Test
    func cliCommandsKeepLocalLaunchersForCopyableNames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-cli-command-launchers-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let npmLauncher = root.appendingPathComponent("bin/npm")
        let npmTarget = root.appendingPathComponent("lib/node_modules/npm/bin/npm-cli.js")
        try writeExecutable(at: npmTarget)
        try FileManager.default.createDirectory(
            at: npmLauncher.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: npmLauncher, withDestinationURL: npmTarget)

        let grokLauncher = root.appendingPathComponent(".grok/bin/grok")
        let grokTarget = root.appendingPathComponent(".grok/downloads/grok-versioned")
        try writeExecutable(at: grokTarget)
        try FileManager.default.createDirectory(
            at: grokLauncher.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: grokLauncher, withDestinationURL: grokTarget)

        let service = AIAgentCLIService(
            environment: ["PATH": npmLauncher.deletingLastPathComponent().path],
            homeDirectory: root
        )

        let install = try #require(
            service.installationCommands(for: [.claude], update: false).first
        )
        #expect(install.executableURL == npmLauncher)

        let update = try #require(
            service.installationCommands(for: [.grok], update: true).first
        )
        #expect(update.executableURL == grokLauncher)
    }

    @Test
    func additionalManagedCLIsBuildNPMManagementCommands() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-additional-cli-commands-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let npm = root.appendingPathComponent(".npm-global/bin/npm")
        try writeExecutable(at: npm)
        let packages: [(AgentCLIKind, String, String)] = [
            (.qwen, "@qwen-code/qwen-code", "qwen"),
            (.qoder, "@qoder-ai/qodercli", "qodercli"),
            (.copilot, "@github/copilot", "copilot"),
            (.dsh, "@deepseek-ai/dsh", "dsh"),
        ]
        for (_, package, executable) in packages {
            let target = root.appendingPathComponent(".npm-global/lib/node_modules/\(package)/\(executable).js")
            try writeExecutable(at: target)
            let launcher = root.appendingPathComponent(".npm-global/bin/\(executable)")
            try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: target)
        }
        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: root)
        let kinds = packages.map { $0.0 }

        let installs = service.installationCommands(for: kinds, update: false)
        #expect(installs == [AIAgentCLICommand(
            executableURL: npm,
            arguments: [
                "install", "--global",
                "@qwen-code/qwen-code", "@qoder-ai/qodercli", "@github/copilot", "@deepseek-ai/dsh",
            ]
        )])

        let updates = service.installationCommands(for: kinds, update: true)
        #expect(updates == [AIAgentCLICommand(
            executableURL: npm,
            arguments: [
                "install", "--global",
                "@qwen-code/qwen-code@latest", "@qoder-ai/qodercli@latest", "@github/copilot@latest", "@deepseek-ai/dsh@latest",
            ],
            timeout: 600
        )])

        let uninstalls = service.uninstallationCommands(for: kinds)
        #expect(uninstalls == [AIAgentCLICommand(
            executableURL: npm,
            arguments: [
                "uninstall", "--global",
                "@qwen-code/qwen-code", "@qoder-ai/qodercli", "@github/copilot", "@deepseek-ai/dsh",
            ]
        )])
    }

    @Test
    func piCLIUsesNPMForInstallUpdateAndUninstall() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-pi-cli-management-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let npm = root.appendingPathComponent(".npm-global/bin/npm")
        let target = root.appendingPathComponent(
            ".npm-global/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
        )
        let launcher = root.appendingPathComponent(".npm-global/bin/pi")
        try writeExecutable(at: npm)
        try writeExecutable(at: target)
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: target)
        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin"], homeDirectory: root)

        #expect(service.installationCommands(for: [.pi], update: false) == [
            AIAgentCLICommand(
                executableURL: npm,
                arguments: ["install", "--global", "@earendil-works/pi-coding-agent"]
            ),
        ])
        #expect(service.installationCommands(for: [.pi], update: true) == [
            AIAgentCLICommand(
                executableURL: npm,
                arguments: ["install", "--global", "@earendil-works/pi-coding-agent@latest"],
                timeout: 600
            ),
        ])
        #expect(service.uninstallationCommands(for: [.pi]) == [
            AIAgentCLICommand(
                executableURL: npm,
                arguments: ["uninstall", "--global", "@earendil-works/pi-coding-agent"]
            ),
        ])
    }

    @Test
    func glmCLIDiscoveryReadsTheOfficialPackageVersion() async throws {
        let glm = try #require(AgentCLIKind(rawValue: "glm"))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-glm-cli-discovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let packageRoot = root.appendingPathComponent(".npm-global/lib/node_modules/@z_ai/coding-helper")
        let target = packageRoot.appendingPathComponent("dist/cli.js")
        let launcher = root.appendingPathComponent(".npm-global/bin/chelper")
        try writeExecutable(at: target, contents: "#!/bin/sh\nexit 1\n")
        try Data(#"{"name":"@z_ai/coding-helper","version":"0.0.7"}"#.utf8)
            .write(to: packageRoot.appendingPathComponent("package.json"))
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: target)

        let status = await AIAgentCLIService(environment: ["PATH": "/usr/bin"], homeDirectory: root)
            .status(for: glm)

        #expect(status.executablePath == target.path)
        #expect(status.version == "0.0.7")
    }

    @Test
    func glmCLIUsesNPMForInstallUpdateAndUninstall() throws {
        let glm = try #require(AgentCLIKind(rawValue: "glm"))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-glm-cli-management-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let npm = root.appendingPathComponent(".npm-global/bin/npm")
        let target = root.appendingPathComponent(".npm-global/lib/node_modules/@z_ai/coding-helper/dist/cli.js")
        let launcher = root.appendingPathComponent(".npm-global/bin/chelper")
        try writeExecutable(at: npm)
        try writeExecutable(at: target)
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: target)
        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin"], homeDirectory: root)

        #expect(service.installationCommands(for: [glm], update: false) == [
            AIAgentCLICommand(executableURL: npm, arguments: ["install", "--global", "@z_ai/coding-helper"]),
        ])
        #expect(service.installationCommands(for: [glm], update: true) == [
            AIAgentCLICommand(
                executableURL: npm,
                arguments: ["install", "--global", "@z_ai/coding-helper@latest"],
                timeout: 600
            ),
        ])
        #expect(service.uninstallationCommands(for: [glm]) == [
            AIAgentCLICommand(executableURL: npm, arguments: ["uninstall", "--global", "@z_ai/coding-helper"]),
        ])
    }

    @Test
    func additionalManagedCLIsHaveInstallScriptsWithoutNPM() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-additional-cli-install-scripts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: root)

        let commands = service.installationCommands(for: [.qwen, .qoder, .copilot], update: false)
        let scripts = commands.filter { $0.executableURL.path == "/bin/bash" }
        if scripts.isEmpty {
            #expect(commands.count == 1)
            #expect(commands[0].arguments == [
                "install", "--global",
                "@qwen-code/qwen-code", "@qoder-ai/qodercli", "@github/copilot",
            ])
        } else {
            #expect(scripts.map(\.arguments) == [
                ["-c", "curl -fsSL https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen-standalone.sh | bash"],
                ["-c", "curl -fsSL https://qoder.com/install | bash"],
                ["-c", "curl -fsSL https://gh.io/copilot-install | bash"],
            ])
        }
    }

    @Test
    func copilotHomebrewInstallationUsesHomebrewForManagement() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-copilot-cask-management-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let brew = root.appendingPathComponent("toolchain/bin/brew")
        let target = root.appendingPathComponent("Caskroom/copilot-cli/1.0.34/copilot")
        let launcher = root.appendingPathComponent("bin/copilot")
        try writeExecutable(at: brew)
        try writeExecutable(at: target)
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: target)
        let service = AIAgentCLIService(
            environment: ["PATH": "\(root.appendingPathComponent("bin").path):/usr/bin", "NPM_CONFIG_PREFIX": root.appendingPathComponent("toolchain").path],
            homeDirectory: root
        )

        #expect(service.installationCommands(for: [.copilot], update: true) == [
            AIAgentCLICommand(executableURL: brew, arguments: ["upgrade", "copilot-cli"], timeout: 600),
        ])
        #expect(service.uninstallationCommands(for: [.copilot]) == [
            AIAgentCLICommand(executableURL: brew, arguments: ["uninstall", "copilot-cli"]),
        ])
    }

    @Test
    func homebrewUpdateCheckUsesCaskReportedVersion() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-copilot-cask-update-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let brew = root.appendingPathComponent("toolchain/bin/brew")
        try writeExecutable(
            at: brew,
            contents: "#!/bin/sh\nprintf '%s' '{\"formulae\":[],\"casks\":[{\"name\":\"copilot-cli\",\"current_version\":\"1.0.35\"}]}'\n"
        )
        let copilot = root.appendingPathComponent("Caskroom/copilot-cli/1.0.34/copilot")
        try writeExecutable(at: copilot)
        let service = AIAgentCLIService(
            environment: ["PATH": "/usr/bin", "NPM_CONFIG_PREFIX": root.appendingPathComponent("toolchain").path],
            homeDirectory: root
        )

        let updates = await service.homebrewUpdates(for: [
            AgentCLIStatus(kind: .copilot, executablePath: copilot.path, version: "1.0.34"),
        ])

        #expect(updates == [
            AIAgentCLIUpdate(kind: .copilot, installedVersion: "1.0.34", latestVersion: "1.0.35"),
        ])
    }

    @Test
    func standaloneCopilotUninstallRemovesOnlyTheOfficialUserBinary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-copilot-standalone-uninstall-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let copilot = root.appendingPathComponent(".local/bin/copilot")
        try writeExecutable(at: copilot)
        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin"], homeDirectory: root)

        #expect(service.uninstallationCommands(for: [.copilot]) == [
            AIAgentCLICommand(executableURL: URL(fileURLWithPath: "/bin/rm"), arguments: [copilot.path]),
        ])
    }

    @Test
    func standaloneQwenUsesOfficialUninstaller() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-qwen-standalone-uninstall-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let qwen = root.appendingPathComponent(".local/bin/qwen")
        try writeExecutable(at: qwen)
        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin"], homeDirectory: root)

        #expect(service.uninstallationCommands(for: [.qwen]) == [
            AIAgentCLICommand(
                executableURL: URL(fileURLWithPath: "/bin/bash"),
                arguments: ["-c", "curl -fsSL https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/uninstall-qwen-standalone.sh | bash"]
            ),
        ])
    }

    @Test
    func standaloneQoderUninstallRemovesOnlyTheOfficialUserBinary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-qoder-standalone-uninstall-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let qoder = root.appendingPathComponent(".local/bin/qodercli")
        try writeExecutable(at: qoder)
        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin"], homeDirectory: root)

        #expect(service.uninstallationCommands(for: [.qoder]) == [
            AIAgentCLICommand(executableURL: URL(fileURLWithPath: "/bin/rm"), arguments: [qoder.path]),
        ])
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

    private func waitForFile(at url: URL) async {
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: url.path) {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func waitForCLIUpdate(_ workspace: AIAgentWorkspace, kind: AgentCLIKind) async -> Bool {
        for _ in 0..<100 {
            if workspace.cliUpdates.contains(where: { $0.kind == kind }) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    private func parallelCommand(startedAt: URL, waitingFor peer: URL) -> String {
        "touch '\(startedAt.path)'; for _ in $(seq 1 50); do [ -f '\(peer.path)' ] && exit 0; sleep 0.01; done; exit 1"
    }


    @Test
    func additionalCLIDiscoveryAndVersionDetection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-additional-cli-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let kimi = root.appendingPathComponent(".kimi-code/bin/kimi")
        let qwen = root.appendingPathComponent(".local/bin/qwen")
        let qoder = root.appendingPathComponent(".local/bin/qodercli")
        let copilot = root.appendingPathComponent(".npm-global/bin/copilot")
        try writeExecutable(at: kimi, contents: "#!/bin/sh\nprintf '0.34.0\\n'\n")
        try writeExecutable(at: qwen, contents: "#!/bin/sh\nprintf '0.21.10\\n'\n")
        try writeExecutable(at: qoder, contents: "#!/bin/sh\nprintf '0.5.0\\n'\n")
        try writeExecutable(at: copilot, contents: "#!/bin/sh\nprintf 'GitHub Copilot CLI 1.0.34.\\n'\n")

        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: root)

        let statuses = await service.statuses()
        let searchPaths = AIAgentCLIService.executableSearchDirectories(
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectory: root
        ).map(\.path)

        #expect(statuses.first { $0.kind == .kimi }?.executablePath == kimi.path)
        #expect(statuses.first { $0.kind == .kimi }?.version == "0.34.0")
        #expect(statuses.first { $0.kind == .qwen }?.executablePath == qwen.path)
        #expect(statuses.first { $0.kind == .qwen }?.version == "0.21.10")
        #expect(statuses.first { $0.kind == .qoder }?.executablePath == qoder.path)
        #expect(statuses.first { $0.kind == .qoder }?.version == "0.5.0")
        #expect(statuses.first { $0.kind == .copilot }?.executablePath == copilot.path)
        #expect(statuses.first { $0.kind == .copilot }?.version == "GitHub Copilot CLI 1.0.34.")
        #expect(searchPaths.contains(root.appendingPathComponent(".kimi-code/bin").path))
        #expect(!searchPaths.contains(root.appendingPathComponent(".kimi/bin").path))
    }

    @Test
    func kimiDiscoveryUsesConfiguredInstallationDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-kimi-configured-installation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuredInstall = root.appendingPathComponent("configured-install", isDirectory: true)
        let installedKimi = configuredInstall.appendingPathComponent("bin/kimi")
        try writeExecutable(at: installedKimi)

        let installedService = AIAgentCLIService(
            environment: ["PATH": "/usr/bin:/bin", "KIMI_INSTALL_DIR": configuredInstall.path],
            homeDirectory: root
        )

        #expect(try #require(installedService.executableURL(for: .kimi)).path == installedKimi.path)
    }

    @Test
    func kimiManagementBuildsOfficialCommands() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-kimi-management-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let installRoot = root.appendingPathComponent("kimi-install", isDirectory: true)
        let kimi = installRoot.appendingPathComponent("bin/kimi")
        try writeExecutable(at: kimi)
        let service = AIAgentCLIService(
            environment: ["PATH": "/usr/bin:/bin", "KIMI_INSTALL_DIR": installRoot.path],
            homeDirectory: root
        )

        #expect(service.installationCommands(for: [.kimi], update: false) == [
            AIAgentCLICommand(
                executableURL: URL(fileURLWithPath: "/bin/bash"),
                arguments: ["-c", "curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash"]
            ),
        ])
        #expect(service.installationCommands(for: [.kimi], update: true) == [
            AIAgentCLICommand(executableURL: kimi, arguments: ["upgrade"], timeout: 600),
        ])
        #expect(service.uninstallationCommands(for: [.kimi]) == [
            AIAgentCLICommand(executableURL: URL(fileURLWithPath: "/bin/rm"), arguments: [kimi.path]),
        ])
    }

    @Test
    func kimiUninstallRefusesExecutablesOutsideTrustedInstallationRoots() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-kimi-untrusted-uninstall-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untrustedDirectory = root.appendingPathComponent("untrusted/bin", isDirectory: true)
        let kimi = untrustedDirectory.appendingPathComponent("kimi")
        try writeExecutable(at: kimi)
        let service = AIAgentCLIService(
            environment: [
                "PATH": "\(untrustedDirectory.path):/usr/bin:/bin",
                "KIMI_INSTALL_DIR": root.appendingPathComponent("trusted-install").path,
            ],
            homeDirectory: root
        )

        #expect(service.installationCommands(for: [.kimi], update: true) == [
            AIAgentCLICommand(executableURL: kimi, arguments: ["upgrade"], timeout: 600),
        ])
        #expect(service.uninstallationCommands(for: [.kimi]).isEmpty)
    }

    @Test
    func kimiUninstallRemovesTrustedLauncherInsteadOfSymlinkTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-kimi-symlink-uninstall-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let installRoot = root.appendingPathComponent("kimi-install", isDirectory: true)
        let launcher = installRoot.appendingPathComponent("bin/kimi")
        let target = root.appendingPathComponent("external/kimi")
        try writeExecutable(at: target)
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: target)
        let service = AIAgentCLIService(
            environment: ["PATH": "/usr/bin:/bin", "KIMI_INSTALL_DIR": installRoot.path],
            homeDirectory: root
        )

        #expect(service.uninstallationCommands(for: [.kimi]) == [
            AIAgentCLICommand(executableURL: URL(fileURLWithPath: "/bin/rm"), arguments: [launcher.path]),
        ])
    }

    @Test
    func relayRejectsDetectionOnlyCLIBeforeLaunchingIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-detection-only-relay-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("launched")
        let kimi = root.appendingPathComponent(".kimi-code/bin/kimi")
        try writeExecutable(at: kimi, contents: "#!/bin/sh\ntouch '\(marker.path)'\nprintf 'unexpected\\n'\n")
        let service = AIAgentCLIService(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: root)

        do {
            _ = try await service.relay(
                messages: [AIOutboundMessage(role: .user, content: "测试")],
                to: .kimi
            )
            Issue.record("仅检测的 CLI 不应进入语音整理")
        } catch {
            #expect(error.localizedDescription.contains("暂不支持语音整理"))
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test
    func relayFailureDoesNotExposeCommandOutput() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-relay-redaction-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("bin/codex")
        try writeExecutable(
            at: codex,
            contents: "#!/bin/sh\nprintf 'secret-command-output\\n' >&2\nexit 9\n"
        )
        let service = AIAgentCLIService(
            environment: ["PATH": codex.deletingLastPathComponent().path],
            homeDirectory: root
        )

        do {
            _ = try await service.relay(
                messages: [AIOutboundMessage(role: .user, content: "测试")],
                to: .codex
            )
            Issue.record("CLI 失败应抛出异常")
        } catch {
            #expect(error.localizedDescription == "CLI 执行失败：退出状态 9")
            #expect(!error.localizedDescription.contains("secret-command-output"))
        }
    }

    @Test
    func homebrewUpdateCheckSupportsManagedAdditionalCLIs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-detection-only-homebrew-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let brew = root.appendingPathComponent("toolchain/bin/brew")
        try writeExecutable(
            at: brew,
            contents: "#!/bin/sh\nprintf '%s' '{\"formulae\":[{\"name\":\"qwen-code\",\"current_version\":\"0.22.0\"}],\"casks\":[]}'\n"
        )
        let qwen = root.appendingPathComponent("Cellar/qwen-code/0.21.10/bin/qwen")
        try writeExecutable(at: qwen)
        let service = AIAgentCLIService(
            environment: ["PATH": "/usr/bin", "NPM_CONFIG_PREFIX": root.appendingPathComponent("toolchain").path],
            homeDirectory: root
        )

        let updates = await service.homebrewUpdates(for: [
            AgentCLIStatus(kind: .qwen, executablePath: qwen.path, version: "0.21.10"),
        ])

        #expect(updates == [
            AIAgentCLIUpdate(kind: .qwen, installedVersion: "0.21.10", latestVersion: "0.22.0"),
        ])
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
