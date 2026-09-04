import Combine
import Foundation
import ZislaCore

private actor AIAgentCLIRelayLock {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard locked else {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            locked = false
        }
    }
}

public enum AIAgentCLICommandProgressState: Equatable, Sendable {
    case running
    case succeeded
    case failed
}

public struct AIAgentCLICommandProgress: Equatable, Sendable {
    public let title: String
    public let kinds: [AgentCLIKind]
    public let completedCount: Int
    public let totalCount: Int
    public let state: AIAgentCLICommandProgressState
    public let detail: String?

    public init(
        title: String,
        kinds: [AgentCLIKind],
        completedCount: Int,
        totalCount: Int,
        state: AIAgentCLICommandProgressState,
        detail: String? = nil
    ) {
        self.title = title
        self.kinds = kinds
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.state = state
        self.detail = detail
    }

    public var fractionCompleted: Double {
        guard totalCount > 0 else { return 0 }
        return min(1, Double(completedCount) / Double(totalCount))
    }
}

@MainActor
public final class AIAgentWorkspace: ObservableObject {
    private struct CLICommandRun {
        let commands: [AIAgentCLICommand]
        let title: String
        let kinds: [AgentCLIKind]
    }

    public let store: AIAgentStore

    @Published public private(set) var lastError: String?
    @Published public private(set) var cliUpdates: [AIAgentCLIUpdate] = []
    @Published public private(set) var grokUpdateState: AIAgentGrokUpdateState = .unknown
    @Published public private(set) var cliCommandProgress: AIAgentCLICommandProgress?
    @Published public private(set) var isCheckingCLIs = false

    private let balanceService: AIAgentBalanceService
    private let channelProbeService: AIAgentChannelProbeService
    private let modelCatalogService: AIAgentModelCatalogService
    private var cliService: AIAgentCLIService
    private let cliUpdateService: AIAgentCLIUpdateService
    private let cliProfileService: AIAgentCLIProfileService
    private let skillService: AIAgentSkillService
    private let skillSynchronizationService: AIAgentSkillSynchronizationService
    private let relayLock = AIAgentCLIRelayLock()
    private var cliAutoUpdateTask: Task<Void, Never>?
    private var cliCommandTask: Task<Void, Never>?
    private var cliRefreshTask: Task<Void, Never>?
    private var pendingCLICommandRuns: [CLICommandRun] = []
    private var runtimeEnabled = false
    private var skillRefreshGeneration = 0
    private var cancellables: Set<AnyCancellable> = []

    public init(
        store: AIAgentStore = AIAgentStore(),
        balanceService: AIAgentBalanceService = AIAgentBalanceService(),
        channelProbeService: AIAgentChannelProbeService = AIAgentChannelProbeService(),
        modelCatalogService: AIAgentModelCatalogService = AIAgentModelCatalogService(),
        cliService: AIAgentCLIService = AIAgentCLIService(),
        cliUpdateService: AIAgentCLIUpdateService = AIAgentCLIUpdateService(),
        cliProfileService: AIAgentCLIProfileService = AIAgentCLIProfileService(),
        skillService: AIAgentSkillService = AIAgentSkillService(),
        skillSynchronizationService: AIAgentSkillSynchronizationService = AIAgentSkillSynchronizationService()
    ) {
        self.store = store
        self.balanceService = balanceService
        self.channelProbeService = channelProbeService
        self.modelCatalogService = modelCatalogService
        self.cliService = cliService
        self.cliUpdateService = cliUpdateService
        self.cliProfileService = cliProfileService
        self.skillService = skillService
        self.skillSynchronizationService = skillSynchronizationService
        store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    deinit {
        cliAutoUpdateTask?.cancel()
        cliCommandTask?.cancel()
        cliRefreshTask?.cancel()
    }

    /// Starts background work used by CLI management.
    public func start() {
        guard !runtimeEnabled else { return }
        runtimeEnabled = true
        Task { [weak self] in
            await self?.refreshCLIs()
        }
        updateCLIAutoUpdateLoop(enabled: store.state.cliAutoUpdateEnabled)
    }

    /// Stops CLI management work while preserving user configuration.
    public func stop() {
        runtimeEnabled = false
        cliAutoUpdateTask?.cancel()
        cliAutoUpdateTask = nil
        cliCommandTask?.cancel()
        cliCommandTask = nil
        pendingCLICommandRuns.removeAll()
        cliRefreshTask?.cancel()
        cliRefreshTask = nil
        isCheckingCLIs = false
        cliCommandProgress = nil
    }

    public func refreshBalances() async {
        for account in store.state.accounts where account.balanceProbe != nil {
            do {
                let snapshot: AgentBalanceSnapshot
                switch account.credentialKind {
                case .apiKey:
                    guard let target = balanceTarget(for: account),
                          let apiKey = try store.secret(for: account),
                          !apiKey.isEmpty else {
                        continue
                    }
                    snapshot = try await balanceService.check(
                        account: account,
                        baseURL: target.baseURL,
                        apiKey: apiKey
                    )
                case .cliProfile:
                    guard account.balanceProbe?.kind == .customScript,
                          let contents = try store.cliProfileContents(for: account) else {
                        continue
                    }
                    snapshot = try await balanceService.check(
                        account: account,
                        baseURL: balanceTarget(for: account)?.baseURL ?? "",
                        apiKey: "",
                        cliProfileContents: contents
                    )
                }
                store.recordBalance(snapshot, for: account.id)
            } catch {
                store.recordBalance(
                    AgentBalanceSnapshot(
                        available: nil,
                        detail: error.localizedDescription
                    ),
                    for: account.id
                )
            }
        }
    }

    public func refreshChannelHealth() async {
        let channels = store.state.channels
        let accounts = store.state.accounts
        for channel in channels where channel.isEnabled {
            for group in channel.endpointGroups where group.isEnabled {
                guard let account = group.accountIDs.compactMap({ id in accounts.first { $0.id == id } }).first,
                      account.credentialKind == .apiKey,
                      let apiKey = try? store.secret(for: account),
                      !apiKey.isEmpty else {
                    continue
                }
                for baseURL in group.baseURLs {
                    let route = AgentRoute(
                        channelID: channel.id,
                        endpointGroupID: group.id,
                        accountID: account.id,
                        baseURL: baseURL,
                        protocolKind: channel.protocolKind,
                        model: channel.defaultModel
                    )
                    store.replaceProbe(await channelProbeService.probe(route: route, apiKey: apiKey))
                    store.replaceModelCatalog(await modelCatalogService.fetch(route: route, apiKey: apiKey))
                }
            }
        }
    }

    public func refreshModels(for channelID: UUID) async {
        guard let channel = store.channel(id: channelID), channel.isEnabled else { return }
        let accounts = store.state.accounts
        for group in channel.endpointGroups where group.isEnabled {
            guard let account = group.accountIDs.compactMap({ id in accounts.first { $0.id == id } }).first,
                  account.credentialKind == .apiKey,
                  let apiKey = try? store.secret(for: account),
                  !apiKey.isEmpty else {
                continue
            }
            for baseURL in group.baseURLs {
                let route = AgentRoute(
                    channelID: channel.id,
                    endpointGroupID: group.id,
                    accountID: account.id,
                    baseURL: baseURL,
                    protocolKind: channel.protocolKind,
                    model: channel.defaultModel
                )
                store.replaceModelCatalog(await modelCatalogService.fetch(route: route, apiKey: apiKey))
            }
        }
    }

    public func refreshCLIs() async {
        if let cliCommandTask {
            await cliCommandTask.value
            return
        }
        await refreshCLIsNow()
    }

    private func refreshCLIsNow() async {
        if let cliRefreshTask {
            await cliRefreshTask.value
            return
        }

        isCheckingCLIs = true
        let refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.performCLIRefresh()
        }
        cliRefreshTask = refreshTask
        await refreshTask.value
        cliRefreshTask = nil
        isCheckingCLIs = false
        startNextCLICommandRunIfNeeded()
    }

    private func performCLIRefresh() async {
        let statuses = await cliService.statuses()
        store.replaceCLIStatuses(statuses)
        async let registryUpdates = cliUpdateService.availableUpdates(for: statuses)
        async let managedUpdates = cliService.homebrewUpdates(for: statuses)
        async let checkedGrokUpdateState = cliService.grokUpdateState()
        var updates = await registryUpdates + managedUpdates
        let checkedState = await checkedGrokUpdateState
        if case let .updateAvailable(update) = checkedState {
            updates.append(update)
        }
        if case .unknown = checkedState {
            // Preserve a completed Grok update while its remote check is temporarily unreachable.
        } else {
            grokUpdateState = checkedState
        }
        cliUpdates = updates.sorted { AIAgentCLIService.cliKindOrder($0.kind, $1.kind) }
        startAutomaticCLIUpdateIfNeeded(for: cliUpdates)
    }

    private func startAutomaticCLIUpdateIfNeeded(for updates: [AIAgentCLIUpdate]) {
        guard runtimeEnabled,
              store.state.cliAutoUpdateEnabled,
              !Task.isCancelled,
              !isRunningCLICommands,
              cliCommandTask == nil else { return }
        let kinds = updates.map(\.kind)
        let commands = commandsForCLIInstallation(kinds, update: true)
        guard !commands.isEmpty else { return }
        let names = kinds.map(\.displayName).joined(separator: AppLocalization.text("、"))
        startCLICommands(commands, title: AppLocalization.text("自动更新 %@", names), kinds: kinds)
    }

    public func refreshSkills() async {
        skillRefreshGeneration &+= 1
        let generation = skillRefreshGeneration
        let disabledPaths = Set(store.state.skills.filter { !$0.isEnabled }.map(\.path))
        let roots = [managedSkillsDirectory] + AIAgentSkillService.defaultRoots
        let skills = await Task.detached(priority: .utility) { [skillService] in
            skillService.scan(roots: roots, enabledPaths: disabledPaths)
        }.value
        guard generation == skillRefreshGeneration else { return }
        store.replaceSkills(skills)
    }

    public var managedSkillsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zisla/skills", isDirectory: true)
    }

    public var managedSkillBackupRootDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zisla/skill-backups", isDirectory: true)
    }

    public func managedSkillBackupDirectory(for destination: AgentSkillSyncDestination) -> URL {
        managedSkillBackupRootDirectory.appendingPathComponent(destination.rawValue, isDirectory: true)
    }

    public var managedSkills: [AgentSkill] {
        let managedPath = managedSkillsDirectory.path
        return store.state.skills.filter {
            $0.path == managedPath || $0.path.hasPrefix(managedPath + "/")
        }
    }

    public func managedSkillDestinationDirectory(for destination: AgentSkillSyncDestination) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root: URL
        switch destination {
        case .codex:
            root = home.appendingPathComponent(".codex/skills", isDirectory: true)
        case .claude:
            root = home.appendingPathComponent(".claude/skills", isDirectory: true)
        case .agents:
            root = home.appendingPathComponent(".agents/skills", isDirectory: true)
        }
        return root
    }

    @discardableResult
    public func ensureManagedSkillsDirectory() -> URL? {
        do {
            try skillSynchronizationService.ensureManagedDirectory(at: managedSkillsDirectory)
            Task { [weak self] in await self?.refreshSkills() }
            return managedSkillsDirectory
        } catch {
            lastError = "无法创建 Skills 受管库：\(error.localizedDescription)"
            return nil
        }
    }

    public func updateManagedSkillSyncMode(_ mode: AgentSkillSyncMode) {
        store.state.skillSyncConfiguration.mode = mode
        synchronizeManagedSkills()
    }

    public func setManagedSkillDestination(_ destination: AgentSkillSyncDestination, enabled: Bool) {
        if enabled {
            store.state.skillSyncConfiguration.enabledDestinations.insert(destination)
        } else {
            store.state.skillSyncConfiguration.enabledDestinations.remove(destination)
        }
        synchronizeManagedSkills()
    }

    public func setSkill(path: String, enabled: Bool) {
        guard let index = store.state.skills.firstIndex(where: { $0.path == path }) else { return }
        store.state.skills[index].isEnabled = enabled
    }

    public func uninstallSkill(path: String) async -> Bool {
        guard store.state.skills.contains(where: { $0.path == path }) else {
            lastError = AppLocalization.text("未找到要卸载的 Skill")
            return false
        }
        let fileManager = FileManager.default
        let skillURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let resolvedURL = skillURL.resolvingSymlinksInPath().standardizedFileURL
        if let installation = AgentSkillPackageInstallation.detect(at: resolvedURL) {
            guard let command = cliService.uninstallationCommand(for: installation) else {
                lastError = "找不到 \(installation.manager.executableName) 命令"
                return false
            }
            guard let output = await runCLICommand(command), output.status == 0 else {
                if lastError == nil {
                    lastError = "\(installation.manager.rawValue) 卸载失败"
                }
                return false
            }
            if (try? fileManager.destinationOfSymbolicLink(atPath: skillURL.path)) != nil {
                var trashedURL: NSURL?
                try? fileManager.trashItem(at: skillURL, resultingItemURL: &trashedURL)
            }
            await refreshSkills()
            lastError = nil
            return true
        }

        do {
            var trashedURL: NSURL?
            try fileManager.trashItem(at: skillURL, resultingItemURL: &trashedURL)
            await refreshSkills()
            lastError = nil
            return true
        } catch {
            lastError = "无法卸载 Skill：\(error.localizedDescription)"
            return false
        }
    }

    public func synchronizeManagedSkills() {
        let configuration = store.state.skillSyncConfiguration
        let mode: AIAgentSkillSynchronizationMode = switch configuration.mode {
        case .symbolicLink: .symbolicLink
        case .fileCopy: .fileCopy
        }

        do {
            for destination in AgentSkillSyncDestination.allCases {
                let directory = managedSkillDestinationDirectory(for: destination)
                if configuration.enabledDestinations.contains(destination) {
                    try skillSynchronizationService.synchronize(
                        managedDirectory: managedSkillsDirectory,
                        to: directory,
                        mode: mode,
                        backupRoot: managedSkillBackupDirectory(for: destination)
                    )
                } else {
                    try skillSynchronizationService.disable(
                        at: directory,
                        managedDirectory: managedSkillsDirectory,
                        backupRoot: managedSkillBackupDirectory(for: destination)
                    )
                }
            }
            Task { [weak self] in await self?.refreshSkills() }
        } catch {
            lastError = "Skills 同步失败：\(error.localizedDescription)"
        }
    }

    public func commandForCLIInstallation(_ kind: AgentCLIKind, update: Bool) -> AIAgentCLICommand? {
        cliService.installationCommand(for: kind, update: update)
    }

    public func commandsForCLIInstallation(
        _ kinds: [AgentCLIKind],
        update: Bool
    ) -> [AIAgentCLICommand] {
        cliService.installationCommands(for: kinds, update: update)
    }

    public func commandForCLIUninstallation(_ kind: AgentCLIKind) -> AIAgentCLICommand? {
        cliService.uninstallationCommand(for: kind)
    }

    public func commandsForCLIUninstallation(_ kinds: [AgentCLIKind]) -> [AIAgentCLICommand] {
        cliService.uninstallationCommands(for: kinds)
    }

    public func runCLICommand(_ command: AIAgentCLICommand) async -> AIAgentProcessOutput? {
        await runCLICommands([command]).first
    }

    public var isRunningCLICommands: Bool {
        cliCommandProgress?.state == .running
    }

    public func startCLICommands(
        _ commands: [AIAgentCLICommand],
        title: String,
        kinds: [AgentCLIKind]
    ) {
        guard !commands.isEmpty else { return }
        let run = CLICommandRun(commands: commands, title: title, kinds: kinds)
        guard cliCommandTask == nil, cliRefreshTask == nil else {
            pendingCLICommandRuns.append(run)
            return
        }
        startCLICommandRun(run)
    }

    private func startCLICommandRun(_ run: CLICommandRun) {
        lastError = nil
        cliCommandProgress = AIAgentCLICommandProgress(
            title: run.title,
            kinds: run.kinds,
            completedCount: 0,
            totalCount: run.commands.count,
            state: .running
        )
        cliCommandTask = Task { [weak self] in
            await self?.performCLICommands(run.commands, title: run.title, kinds: run.kinds)
        }
    }

    private func startNextCLICommandRunIfNeeded() {
        guard cliCommandTask == nil,
              cliRefreshTask == nil,
              !pendingCLICommandRuns.isEmpty else { return }
        startCLICommandRun(pendingCLICommandRuns.removeFirst())
    }

    public func runCLICommands(_ commands: [AIAgentCLICommand]) async -> [AIAgentProcessOutput] {
        var outputs: [AIAgentProcessOutput] = []
        lastError = nil
        for command in commands {
            do {
                let output = try await cliService.run(command)
                outputs.append(output)
                guard output.status == 0 else {
                    lastError = Self.cliCommandFailureMessage(for: command, output: output)
                    break
                }
            } catch {
                lastError = error.localizedDescription
                break
            }
        }
        await refreshCLIsNow()
        return outputs
    }

    private func performCLICommands(
        _ commands: [AIAgentCLICommand],
        title: String,
        kinds: [AgentCLIKind]
    ) async {
        defer {
            cliCommandTask = nil
            startNextCLICommandRunIfNeeded()
        }
        let cliService = cliService
        var failures: [String] = []
        var completedCount = 0

        await withTaskGroup(of: String?.self) { group in
            for command in commands {
                group.addTask {
                    do {
                        let output = try await cliService.run(command)
                        guard output.status != 0 else { return nil }
                        return Self.cliCommandFailureMessage(for: command, output: output)
                    } catch {
                        return error.localizedDescription
                    }
                }
            }
            for await failure in group {
                completedCount += 1
                if let failure { failures.append(failure) }
                cliCommandProgress = AIAgentCLICommandProgress(
                    title: title,
                    kinds: kinds,
                    completedCount: completedCount,
                    totalCount: commands.count,
                    state: .running,
                    detail: "正在并行执行 · \(completedCount)/\(commands.count) 已完成"
                )
            }
        }

        let failureDetail: String?
        if failures.isEmpty {
            failureDetail = nil
        } else if failures.count == 1, let failure = failures.first {
            failureDetail = failure
        } else {
            failureDetail = "\(failures.count) 项命令失败：\(failures.joined(separator: "；"))"
        }
        if failureDetail == nil, kinds.contains(.grok) {
            grokUpdateState = .upToDate
        }
        cliCommandProgress = AIAgentCLICommandProgress(
            title: title,
            kinds: kinds,
            completedCount: commands.count,
            totalCount: commands.count,
            state: .running,
            detail: "正在重新检测 CLI 版本"
        )
        await refreshCLIsNow()
        cliCommandProgress = AIAgentCLICommandProgress(
            title: title,
            kinds: kinds,
            completedCount: commands.count,
            totalCount: commands.count,
            state: failureDetail == nil ? .succeeded : .failed,
            detail: failureDetail ?? AppLocalization.text("已重新检测 CLI 版本")
        )
        lastError = failureDetail
    }

    nonisolated private static func cliCommandFailureMessage(
        for command: AIAgentCLICommand,
        output: AIAgentProcessOutput
    ) -> String {
        if output.didTimeout {
            return "CLI 命令超时（超过 \(Int(command.timeout / 60)) 分钟），请检查网络后重试"
        }
        let detail = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.contains("untrusted tap"),
           let trustCommand = detail.components(separatedBy: "`").dropFirst().first,
           !trustCommand.isEmpty {
            return "Homebrew 需要先信任该公式：\(trustCommand)"
        }
        return detail.isEmpty ? "CLI 命令执行失败（退出码 \(output.status)）" : detail
    }

    public func importCLIProfileFile(_ data: Data, for accountID: UUID, authentication: Bool) {
        do {
            if authentication {
                try store.replaceCLIAuthentication(data, for: accountID)
            } else {
                try store.replaceCLIConfiguration(data, for: accountID)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Runs a short, non-persistent completion through an imported official CLI profile.
    public func completeWithCLIProfile(
        accountID: UUID,
        systemPrompt: String,
        messages: [AIOutboundMessage],
        model: String
    ) async throws -> String {
        guard let account = store.account(id: accountID),
              account.credentialKind == .cliProfile,
              account.isEligible(),
              let profile = account.cliProfile,
              let contents = try store.cliProfileContents(for: account) else {
            throw AIAgentCLIRelayError.failed(AppLocalization.text("CLI 登录档案尚未配置完整"))
        }

        await relayLock.acquire()
        do {
            try activateCLIProfile(for: account, profile: profile, contents: contents)
            let relayMessages = [AIOutboundMessage(role: .system, content: systemPrompt)] + messages
            let response = try await cliService.relay(
                messages: relayMessages,
                model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : model,
                to: profile.cliKind
            )
            await relayLock.release()
            return response
        } catch {
            await relayLock.release()
            store.recordRouteFailure(for: accountID)
            throw error
        }
    }

    public func setCLIAutoUpdateEnabled(_ enabled: Bool) {
        store.setCLIAutoUpdateEnabled(enabled)
        updateCLIAutoUpdateLoop(enabled: enabled)
    }

    public func setNetworkProxyURL(_ value: String) {
        cliService.setNetworkProxyURL(value)
        Task { await cliUpdateService.setNetworkProxyURL(value) }
    }

    public func setNetworkProxy(url: String, enabled: Bool) {
        cliService.setNetworkProxy(url: url, enabled: enabled)
        Task { await cliUpdateService.setNetworkProxy(url: url, enabled: enabled) }
    }

    private func updateCLIAutoUpdateLoop(enabled: Bool) {
        guard runtimeEnabled, enabled else {
            cliAutoUpdateTask?.cancel()
            cliAutoUpdateTask = nil
            return
        }
        guard cliAutoUpdateTask == nil else { return }
        cliAutoUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshCLIs()
                do {
                    try await Task.sleep(for: .seconds(600))
                } catch {
                    return
                }
            }
        }
    }

    private func balanceTarget(for account: AgentAccount) -> (baseURL: String, channel: AgentChannel)? {
        for channel in store.state.channels where channel.isEnabled {
            for group in channel.endpointGroups where group.isEnabled && group.accountIDs.contains(account.id) {
                if let baseURL = group.baseURLs.first { return (baseURL, channel) }
            }
        }
        return nil
    }

    private func activateCLIProfile(
        for account: AgentAccount,
        profile: AgentCLIProfile,
        contents: (configuration: Data, authentication: Data)
    ) throws {
        if let activeID = store.state.activeCLIProfileAccountID, activeID != account.id {
            if let activeAccount = store.account(id: activeID),
               let activeProfile = activeAccount.cliProfile {
                let refreshedContents = try cliProfileService.syncBack(profile: activeProfile)
                try store.replaceCLIProfile(
                    configuration: refreshedContents.configuration,
                    authentication: refreshedContents.authentication,
                    for: activeID
                )
            } else {
                store.setActiveCLIProfileAccountID(nil)
            }
        }
        guard store.state.activeCLIProfileAccountID != account.id else { return }
        try cliProfileService.activate(profile: profile, contents: contents)
        store.setActiveCLIProfileAccountID(account.id)
    }
}
