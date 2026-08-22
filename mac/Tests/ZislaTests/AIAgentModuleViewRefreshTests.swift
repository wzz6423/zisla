import Testing
import SwiftUI
@testable import Zisla
@testable import ZislaKit
@testable import ZislaCore

@Suite(.serialized)
@MainActor
struct AIAgentModuleViewRefreshTests {
    @Test
    func refreshButtonRemainsEnabledDuringRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-refresh-button-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = AIAgentWorkspace(
            store: AIAgentStore(storageURL: directory.appendingPathComponent("state.json")),
            cliService: AIAgentCLIService(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: directory),
            cliUpdateService: AIAgentCLIUpdateService(loadLatestVersion: { _ in nil })
        )

        let refreshTask = Task { await workspace.refreshCLIs() }
        try await Task.sleep(for: .milliseconds(10))

        #expect(workspace.isCheckingCLIs)

        await refreshTask.value
        #expect(!workspace.isCheckingCLIs)
    }

    @Test
    func concurrentRefreshRequestsMergeIntoOneOperation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-refresh-merge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let refreshStarted = directory.appendingPathComponent("refresh-started")
        let releaseRefresh = directory.appendingPathComponent("release-refresh")
        let toolDirectory = directory.appendingPathComponent("bin", isDirectory: true)
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

        let firstRefresh = Task { await workspace.refreshCLIs() }
        await waitForFile(at: refreshStarted)
        #expect(workspace.isCheckingCLIs)

        let secondRefresh = Task { await workspace.refreshCLIs() }
        try await Task.sleep(for: .milliseconds(50))

        try Data().write(to: releaseRefresh)
        await firstRefresh.value
        await secondRefresh.value

        #expect(!workspace.isCheckingCLIs)
    }

    @Test
    func refreshDuringCLICommandWaitsForCommandCompletion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-refresh-during-command-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let commandStarted = directory.appendingPathComponent("command-started")
        let releaseCommand = directory.appendingPathComponent("release-command")
        let workspace = AIAgentWorkspace(
            store: AIAgentStore(storageURL: directory.appendingPathComponent("state.json")),
            cliService: AIAgentCLIService(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: directory),
            cliUpdateService: AIAgentCLIUpdateService(loadLatestVersion: { _ in nil })
        )
        let command = AIAgentCLICommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "touch '\(commandStarted.path)'; while [ ! -f '\(releaseCommand.path)' ]; do sleep 0.01; done"]
        )

        workspace.startCLICommands([command], title: "测试命令", kinds: [.codex])
        await waitForFile(at: commandStarted)
        #expect(workspace.isRunningCLICommands)

        let refreshTask = Task { await workspace.refreshCLIs() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(workspace.isRunningCLICommands)

        try Data().write(to: releaseCommand)
        await waitForCLICommandRunToFinish(workspace)
        await refreshTask.value

        #expect(!workspace.isCheckingCLIs)
        #expect(!workspace.isRunningCLICommands)
    }

    @Test
    func refreshButtonIsNotDisabledByCLICommandState() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Zisla/AIAgentModuleView.swift"),
            encoding: .utf8
        )
        let refreshBlock = try #require(source.range(of: "Task { await agent.refreshCLIs() }"))
        let blockStart = source.index(refreshBlock.lowerBound, offsetBy: -300, limitedBy: source.startIndex) ?? source.startIndex
        let block = source[blockStart..<refreshBlock.upperBound]
        #expect(!block.contains("disabled(agent.isRunningCLICommands"))
        #expect(!block.contains("disabled(agent.isCheckingCLIs"))
    }

    @Test
    func cliCommandRowsIncludeBatchCommandsAndCopyAction() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Zisla/AIAgentModuleView.swift"),
            encoding: .utf8
        )
        #expect(source.contains("cliCommandGroup(title: \"下载命令\", commands: installCommands)"))
        #expect(source.contains("cliCommandGroup(title: \"更新命令\", commands: updateCommands)"))
        #expect(source.contains("let updateKinds = installedKinds"))
        #expect(source.contains("commands: agent.commandsForCLIInstallation([kind], update: false)"))
        #expect(source.contains("NSPasteboard.general.setString(commandText, forType: .string)"))
        #expect(source.contains("argument.replacingOccurrences(of: \"'\", with:"))
    }

    private func writeExecutable(at url: URL, contents: String = "#!/bin/sh\nexit 0\n") throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func waitForFile(at url: URL) async {
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: url.path) {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func waitForCLICommandRunToFinish(_ workspace: AIAgentWorkspace) async {
        for _ in 0..<100 where workspace.isRunningCLICommands {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
}
