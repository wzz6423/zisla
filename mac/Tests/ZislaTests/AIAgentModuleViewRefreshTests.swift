import AppKit
import Testing
import SwiftUI
@testable import Zisla
@testable import ZislaKit
@testable import ZislaCore

@Suite(.serialized)
@MainActor
struct AIAgentModuleViewRefreshTests {
    @Test(.serialized, arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    func skillDestinationAndEntrySwitchesKeepNativeMediumHeight(language: AppLanguage) async throws {
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-skill-control-size-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secretURL = directory.appendingPathComponent("secrets.sqlite3")
        let store = AIAgentStore(storageURL: directory.appendingPathComponent("state.json"),
            secretStore: DatabaseAIAgentSecretStore(storageURL: secretURL))
        defer { store.flushPendingChanges() }
        store.replaceSkills([AgentSkill(name: "Fixture skill", path: directory.appendingPathComponent("SKILL.md").path,
            source: "fixture")])
        store.flushPendingChanges()
        let initialState = store.state
        let workspace = AIAgentWorkspace(store: store,
            cliService: AIAgentCLIService(environment: ["PATH": "/usr/bin:/bin"], homeDirectory: directory),
            cliUpdateService: AIAgentCLIUpdateService(loadLatestVersion: { _ in nil }))
        defer { workspace.stop() }
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: VStack {
            Toggle("Reference", isOn: .constant(true))
                .labelsHidden().toggleStyle(.switch).controlSize(.regular)
                .accessibilityIdentifier("reference-switch")
            SkillManagementView(agent: workspace)
        }
        .environment(\.locale, language.locale)
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        host.sizingOptions = []
        let panel = NSPanel(contentRect: .init(x: -100_000, y: -100_000, width: 560, height: 700),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        defer { panel.contentView = nil; panel.close() }
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let controls = accessibilityObjects(host)
        let referenceObject = controls.first {
            value($0, "accessibilityIdentifier") as? String == "reference-switch"
        }
        let reference = try #require(referenceObject as? any NSAccessibilityElementProtocol)
        #expect(reference.accessibilityFrame().height > 0)
        let switches = controls.filter {
            value($0, "accessibilitySubrole") as? String == "AXToggle"
                && value($0, "accessibilityIdentifier") as? String != "reference-switch"
        }.compactMap { $0 as? any NSAccessibilityElementProtocol }
        #expect(switches.count == AgentSkillSyncDestination.allCases.count + initialState.skills.count,
            "Both destination rows and discovered skill entries must expose their native switches")
        for control in switches {
            #expect(abs(control.accessibilityFrame().height - reference.accessibilityFrame().height) < 0.5)
        }
        #expect(store.state == initialState)
        #expect(!workspace.isCheckingCLIs && !workspace.isRunningCLICommands)
        #expect(!FileManager.default.fileExists(atPath: secretURL.path))
        #expect(!panel.isVisible && !panel.isKeyWindow)
    }

    @Test
    func refreshButtonRemainsEnabledDuringRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-refresh-button-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let refreshStarted = directory.appendingPathComponent("refresh-started")
        let releaseRefresh = directory.appendingPathComponent("release-refresh")
        let toolDirectory = directory.appendingPathComponent("bin", isDirectory: true)
        try writeExecutable(
            at: toolDirectory.appendingPathComponent("claude"),
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

        let refreshTask = Task { await workspace.refreshCLIs() }
        await waitForFile(at: refreshStarted)
        #expect(FileManager.default.fileExists(atPath: refreshStarted.path))
        #expect(workspace.isCheckingCLIs)

        try Data().write(to: releaseRefresh)
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

    @Test(arguments: AppLanguage.allCases)
    func cliAutoUpdateLabelsAreLocalized(language: AppLanguage) throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Zisla/AIAgentModuleView.swift"),
            encoding: .utf8
        )
        let pattern = try NSRegularExpression(pattern: #"AppLocalization\.text\("(自动更新[^"\n]*|选中每个cli[^"\n]*)""#)
        let keys = Set(pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        })
        #expect(keys.count == 3)
        #expect(keys.contains("自动更新 %@"))
        #expect(keys.contains("选中每个cli后的自动更新选项后检测到新版本后自动执行更新；关闭后不再启动新任务，已开始的更新会完成"))
        let table = try #require(NSDictionary(contentsOf: packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )) as? [String: String])

        for key in keys {
            let translation = try #require(table[key], "\(language.rawValue) 缺少自动更新文案：\(key)")
            #expect(!translation.isEmpty)
            #expect(translation.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count)
            #expect(AppLocalization.string(key, locale: language.locale) == translation)
        }
        let label = try #require(table["自动更新 %@"])
        for kind in AgentCLIKind.managedCases {
            let name = language.isRightToLeft ? "\u{2068}\(kind.displayName)\u{2069}" : kind.displayName
            #expect(
                AppLocalization.format("自动更新 %@", locale: language.locale, [kind.displayName])
                    == label.replacingOccurrences(of: "%@", with: name)
            )
        }
        if language == .english {
            #expect(AppLocalization.format("自动更新 %@", locale: language.locale, ["Codex"]) == "Auto-update Codex")
        }
    }

    private func writeExecutable(at url: URL, contents: String = "#!/bin/sh\nexit 0\n") throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func accessibilityObjects(_ object: NSObject) -> [NSObject] {
        [object] + (value(object, "accessibilityChildren") as? [NSObject] ?? []).flatMap(accessibilityObjects)
    }

    private func value(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
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
