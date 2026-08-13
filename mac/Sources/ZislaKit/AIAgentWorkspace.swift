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
    public let store: AIAgentStore

    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var cliUpdates: [AIAgentCLIUpdate] = []
    @Published public private(set) var grokUpdateState: AIAgentGrokUpdateState = .unknown
    @Published public private(set) var cliCommandProgress: AIAgentCLICommandProgress?
    @Published public private(set) var activeThreadIDs: Set<UUID> = []

    private let balanceService: AIAgentBalanceService
    private let channelProbeService: AIAgentChannelProbeService
    private let modelCatalogService: AIAgentModelCatalogService
    private let chatClient: AIChatClient
    private let cliService: AIAgentCLIService
    private let cliUpdateService: AIAgentCLIUpdateService
    private let cliProfileService: AIAgentCLIProfileService
    private let claudeCodeVSCodeSettingsService: ClaudeCodeVSCodeSettingsService
    private let codexHistoryImporter: CodexSessionHistoryImporter
    private let skillService: AIAgentSkillService
    private let skillSynchronizationService: AIAgentSkillSynchronizationService
    private let messageConnectionService: AIAgentMessageConnectionService
    private let relayLock = AIAgentCLIRelayLock()
    private var messageConnectionServer: AIAgentMessageConnectionServer?
    private var relayCursors: [UUID: Int] = [:]
    private var apiRouteRouter = AgentRouteRouter()
    private var automationTask: Task<Void, Never>?
    private var cliAutoUpdateTask: Task<Void, Never>?
    private var cliCommandTask: Task<Void, Never>?
    private var automationMonitoringRequested = false
    private var skillRefreshGeneration = 0
    private var cancellables: Set<AnyCancellable> = []
    private var activeThreadStartedAt: [UUID: Date] = [:]
    private var activeThreadReferenceCounts: [UUID: Int] = [:]

    public init(
        store: AIAgentStore = AIAgentStore(),
        balanceService: AIAgentBalanceService = AIAgentBalanceService(),
        channelProbeService: AIAgentChannelProbeService = AIAgentChannelProbeService(),
        modelCatalogService: AIAgentModelCatalogService = AIAgentModelCatalogService(),
        chatClient: AIChatClient = AIChatClient(),
        cliService: AIAgentCLIService = AIAgentCLIService(),
        cliUpdateService: AIAgentCLIUpdateService = AIAgentCLIUpdateService(),
        cliProfileService: AIAgentCLIProfileService = AIAgentCLIProfileService(),
        claudeCodeVSCodeSettingsService: ClaudeCodeVSCodeSettingsService = ClaudeCodeVSCodeSettingsService(),
        codexHistoryImporter: CodexSessionHistoryImporter = CodexSessionHistoryImporter(),
        skillService: AIAgentSkillService = AIAgentSkillService(),
        skillSynchronizationService: AIAgentSkillSynchronizationService = AIAgentSkillSynchronizationService(),
        messageConnectionService: AIAgentMessageConnectionService = AIAgentMessageConnectionService()
    ) {
        self.store = store
        self.balanceService = balanceService
        self.channelProbeService = channelProbeService
        self.modelCatalogService = modelCatalogService
        self.chatClient = chatClient
        self.cliService = cliService
        self.cliUpdateService = cliUpdateService
        self.cliProfileService = cliProfileService
        self.claudeCodeVSCodeSettingsService = claudeCodeVSCodeSettingsService
        self.codexHistoryImporter = codexHistoryImporter
        self.skillService = skillService
        self.skillSynchronizationService = skillSynchronizationService
        self.messageConnectionService = messageConnectionService
        self.messageConnectionServer = AIAgentMessageConnectionServer { [weak self] request in
            guard let self else { return .text("service unavailable", statusCode: 503) }
            return await self.handleMessageConnectionRequest(request)
        }
        store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        store.$state
            .map { $0.automations.contains(where: \.isEnabled) }
            .removeDuplicates()
            .sink { [weak self] hasEnabledAutomations in
                self?.updateAutomationLoop(hasEnabledAutomations: hasEnabledAutomations)
            }
            .store(in: &cancellables)
        refreshMessageConnections()
        updateCLIAutoUpdateLoop(enabled: store.state.cliAutoUpdateEnabled)
    }

    deinit {
        automationTask?.cancel()
        cliAutoUpdateTask?.cancel()
        cliCommandTask?.cancel()
    }

    public func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        refreshMessageConnections()
        await refreshSkills()
        await refreshBalances()
        await refreshChannelHealth()
        await refreshCLIs()
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
        cliUpdates = updates.sorted {
            AgentCLIKind.allCases.firstIndex(of: $0.kind)! < AgentCLIKind.allCases.firstIndex(of: $1.kind)!
        }
        startAutomaticCLIUpdateIfNeeded(for: cliUpdates)
    }

    private func startAutomaticCLIUpdateIfNeeded(for updates: [AIAgentCLIUpdate]) {
        guard store.state.cliAutoUpdateEnabled,
              !Task.isCancelled,
              !isRunningCLICommands,
              cliCommandTask == nil else { return }
        let kinds = updates.map(\.kind)
        let commands = commandsForCLIInstallation(kinds, update: true)
        guard !commands.isEmpty else { return }
        let names = kinds.map(\.displayName).joined(separator: "、")
        startCLICommands(commands, title: "正在自动更新 \(names)", kinds: kinds)
    }

    public func refreshSkills() async {
        skillRefreshGeneration &+= 1
        let generation = skillRefreshGeneration
        let disabledPaths = Set(store.state.skills.filter { !$0.isEnabled }.map(\.path))
        let roots = AIAgentSkillService.defaultRoots + [managedSkillsDirectory]
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
        return root.appendingPathComponent("zisla-managed", isDirectory: true)
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
            lastError = "未找到要卸载的 Skill"
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
                        mode: mode
                    )
                } else {
                    try skillSynchronizationService.disable(
                        at: directory,
                        managedDirectory: managedSkillsDirectory
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
        guard !commands.isEmpty, !isRunningCLICommands else { return }
        lastError = nil
        cliCommandProgress = AIAgentCLICommandProgress(
            title: title,
            kinds: kinds,
            completedCount: 0,
            totalCount: commands.count,
            state: .running
        )
        cliCommandTask = Task { [weak self] in
            await self?.performCLICommands(commands, title: title, kinds: kinds)
        }
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
        await refreshCLIs()
        return outputs
    }

    private func performCLICommands(
        _ commands: [AIAgentCLICommand],
        title: String,
        kinds: [AgentCLIKind]
    ) async {
        defer { cliCommandTask = nil }
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
        await refreshCLIs()
        cliCommandProgress = AIAgentCLICommandProgress(
            title: title,
            kinds: kinds,
            completedCount: commands.count,
            totalCount: commands.count,
            state: failureDetail == nil ? .succeeded : .failed,
            detail: failureDetail ?? "已重新检测 CLI 版本"
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
            throw AIAgentCLIRelayError.failed("CLI 登录档案尚未配置完整")
        }

        await relayLock.acquire()
        do {
            try activateCLIProfile(for: account, profile: profile, contents: contents)
            let relayMessages = [AgentChatMessage(role: .system, content: systemPrompt)]
                + messages.map { message in
                    let role: AgentChatRole
                    switch message.role {
                    case .system: role = .system
                    case .user: role = .user
                    case .assistant, .tool: role = .assistant
                    }
                    return AgentChatMessage(role: role, content: message.content)
                }
            let response = try await cliService.relay(
                messages: relayMessages,
                accessMode: .readOnly,
                model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : model,
                thinkingDepth: .medium,
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

    public func setCodexOfficialLoginPreserved(_ enabled: Bool) {
        var enhancements = store.state.applicationEnhancements
        enhancements.preservesCodexOfficialLogin = enabled
        store.updateApplicationEnhancements(enhancements)
        if let accountID = store.state.activeCLIProfileAccountID,
           store.account(id: accountID)?.cliProfile?.cliKind == .codex {
            store.setActiveCLIProfilePreservesAuthentication(enabled)
        }
    }

    public func setCodexHistoryUnified(_ enabled: Bool) {
        var enhancements = store.state.applicationEnhancements
        enhancements.unifiesCodexHistory = enabled
        store.updateApplicationEnhancements(enhancements)
        guard enabled else {
            store.removeImportedCodexHistory()
            return
        }
        let importer = codexHistoryImporter
        Task { [weak self] in
            let threads = await Task.detached(priority: .utility) {
                importer.importThreads()
            }.value
            guard let self, self.store.state.applicationEnhancements.unifiesCodexHistory else { return }
            self.store.importCodexHistory(threads)
        }
    }

    public func setClaudeCodeVSCodeFollowsProvider(_ enabled: Bool) {
        var enhancements = store.state.applicationEnhancements
        enhancements.claudeCodeVSCodeFollowsProvider = enabled
        reconcileClaudeCodeVSCodeSettings(enhancements: enhancements)
    }

    public func setClaudeCodeOnboardingSkipped(_ enabled: Bool) {
        var enhancements = store.state.applicationEnhancements
        enhancements.skipsClaudeCodeOnboarding = enabled
        reconcileClaudeCodeVSCodeSettings(enhancements: enhancements)
    }

    public func setCLIAutoUpdateEnabled(_ enabled: Bool) {
        store.setCLIAutoUpdateEnabled(enabled)
        updateCLIAutoUpdateLoop(enabled: enabled)
    }

    private func updateCLIAutoUpdateLoop(enabled: Bool) {
        guard enabled else {
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

    public func refreshMessageConnections() {
        let ports = Set(store.state.messageConnections.filter(\.isEnabled).map(\.listenerPort))
        let failures = messageConnectionServer?.update(ports: ports) ?? [:]
        for connection in store.state.messageConnections where connection.isEnabled {
            if let failure = failures[connection.listenerPort] {
                store.recordMessageConnectionError("本地监听启动失败：\(failure)", for: connection.id)
            }
        }
    }

    public func send(
        _ content: String,
        attachments: [AgentChatAttachment] = [],
        referencedThreadIDs: [UUID] = [],
        appReferences: [AgentChatAppReference] = [],
        skillReferences: [AgentChatSkillReference] = [],
        to threadID: UUID
    ) async {
        beginThreadActivity(threadID)
        defer { endThreadActivity(threadID) }
        await relayLock.acquire()
        _ = await sendLocked(
            content,
            attachments: attachments,
            referencedThreadIDs: referencedThreadIDs,
            appReferences: appReferences,
            skillReferences: skillReferences,
            to: threadID
        )
        await relayLock.release()
    }

    public func activeTasks(now: Date = Date()) -> [AIProgressTask] {
        activeThreadIDs.compactMap { threadID in
            guard let thread = store.state.chatThreads.first(where: { $0.id == threadID }) else {
                return nil
            }
            let startedAt = activeThreadStartedAt[threadID] ?? now
            return AIProgressTask(
                id: "zisla-agent-thread-\(threadID.uuidString.lowercased())",
                provider: Self.provider(for: thread),
                title: thread.title,
                detail: Self.detail(for: thread),
                progress: nil,
                status: .running,
                updatedAt: now,
                startedAt: startedAt
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func beginThreadActivity(_ threadID: UUID) {
        activeThreadIDs.insert(threadID)
        activeThreadReferenceCounts[threadID, default: 0] += 1
        if activeThreadStartedAt[threadID] == nil {
            activeThreadStartedAt[threadID] = Date()
        }
    }

    func endThreadActivity(_ threadID: UUID) {
        guard let count = activeThreadReferenceCounts[threadID] else { return }
        if count > 1 {
            activeThreadReferenceCounts[threadID] = count - 1
        } else {
            activeThreadReferenceCounts.removeValue(forKey: threadID)
            activeThreadIDs.remove(threadID)
            activeThreadStartedAt.removeValue(forKey: threadID)
        }
    }

    private static func provider(for thread: AgentChatThread) -> AIProvider {
        if let cliKind = thread.cliKind {
            switch cliKind {
            case .claude: return .claude
            case .codex: return .codex
            case .gemini: return .gemini
            case .grok: return .grok
            case .opencode: return .opencode
            case .kimi: return .kimi
            case .qwen: return .qwen
            case .qoder: return .coder
            case .copilot: return .copilot
            }
        }
        return .gpt
    }

    private static func detail(for thread: AgentChatThread) -> String? {
        if let model = thread.selectedModel?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            return model
        }
        return thread.cliKind?.displayName
    }

    private func sendLocked(
        _ content: String,
        attachments: [AgentChatAttachment] = [],
        referencedThreadIDs: [UUID] = [],
        appReferences: [AgentChatAppReference] = [],
        skillReferences: [AgentChatSkillReference] = [],
        to threadID: UUID
    ) async -> String? {
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!content.isEmpty || !attachments.isEmpty),
              let thread = store.state.chatThreads.first(where: { $0.id == threadID }) else {
            return nil
        }
        // 目标模式将 Prompt 保存在会话内；旧会话仍可回退到关联的历史目标。
        let sessionGoal = thread.goalPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let goalTitle = (sessionGoal?.isEmpty == false ? sessionGoal : nil)
            ?? thread.goalID.flatMap { store.goal(id: $0)?.title }
        let contextReferences = store.contextReferences(for: referencedThreadIDs, excluding: threadID)
        store.append(
            AgentChatMessage(
                role: .user,
                content: content,
                attachments: attachments,
                contextReferences: contextReferences,
                appReferences: appReferences,
                skillReferences: skillReferences,
                mode: thread.mode,
                goalTitle: goalTitle
            ),
            to: threadID
        )
        let messages = store.state.chatThreads.first(where: { $0.id == threadID })?.messages ?? []
        let localAttempt = await relayThroughLocalModel(thread: thread, messages: messages)
        if let response = localAttempt.response {
            return response
        }
        let apiAttempt = await relayThroughAPIChannel(thread: thread, messages: messages)
        if let response = apiAttempt.response {
            return response
        }
        let candidates = relayCandidates(for: thread)
        guard !candidates.isEmpty else {
            if !localAttempt.attempted && !apiAttempt.attempted {
                lastError = "请先添加 API Key 或 CLI 登录档案"
            }
            return nil
        }
        for account in candidates {
            guard let profile = account.cliProfile,
                  let contents = try? store.cliProfileContents(for: account) else {
                store.recordRouteFailure(for: account.id)
                continue
            }
            do {
                try activateCLIProfile(for: account, profile: profile, contents: contents)
                let project = thread.projectID.flatMap { store.project(id: $0) }
                let response = try await cliService.relay(
                    messages: messages,
                    project: project,
                    accessMode: thread.accessMode,
                    model: thread.selectedModel,
                    thinkingDepth: thread.thinkingDepth,
                    to: profile.cliKind
                )
                store.append(AgentChatMessage(role: .assistant, content: response, accountID: account.id), to: threadID)
                store.updateThreadTarget(id: threadID, cliKind: profile.cliKind, accountID: account.id)
                lastError = nil
                return response
            } catch {
                store.recordRouteFailure(for: account.id)
                lastError = error.localizedDescription
            }
        }
        if lastError == nil { lastError = "没有可用 CLI 登录档案；请检查余额和认证文件" }
        return nil
    }

    private func relaySystemPrompt(
        for thread: AgentChatThread,
        messages: [AgentChatMessage]
    ) -> String {
        let messagePrompt = messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")
        let planPrompt = thread.mode == .plan
            ? "[计划模式]\n请给出可执行计划、当前进展和下一步。"
            : ""
        let goal = thread.goalPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let goalPrompt = goal.isEmpty
            ? ""
            : "[目标模式]\n当前会话目标：\(goal)\n请围绕该目标推进，不要偏离。"
        return [messagePrompt, planPrompt, goalPrompt]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func relayThroughLocalModel(
        thread: AgentChatThread,
        messages: [AgentChatMessage]
    ) async -> (attempted: Bool, response: String?) {
        guard let localModelID = thread.localModelID else { return (false, nil) }
        guard let localModel = store.localModel(id: localModelID), localModel.isEnabled else {
            lastError = "所选本地模型已不可用"
            return (true, nil)
        }
        let model = localModel.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            lastError = "所选本地模型未填写模型 ID"
            return (true, nil)
        }
        do {
            let systemPrompt = relaySystemPrompt(for: thread, messages: messages)
            let outbound = cliService.outboundMessages(messages.filter { $0.role != .system })
            let response = try await chatClient.complete(
                endpoint: localModel.endpoint,
                model: model,
                systemPrompt: systemPrompt,
                messages: outbound
            ).content
            store.append(AgentChatMessage(role: .assistant, content: response), to: thread.id)
            lastError = nil
            return (true, response)
        } catch {
            lastError = error.localizedDescription
            return (true, nil)
        }
    }

    private func relayThroughAPIChannel(
        thread: AgentChatThread,
        messages: [AgentChatMessage]
    ) async -> (attempted: Bool, response: String?) {
        guard let channelID = thread.channelID,
              let channel = store.channel(id: channelID),
              channel.isEnabled else {
            return (false, nil)
        }
        let apiAccounts = store.state.accounts.filter { $0.credentialKind == .apiKey }
        let routes = apiRouteRouter.routes(
            for: channel,
            accounts: apiAccounts,
            model: thread.selectedModel
        )
        guard !routes.isEmpty else {
            return (false, nil)
        }
        let systemPrompt = relaySystemPrompt(for: thread, messages: messages)
        let outbound = cliService.outboundMessages(messages.filter { $0.role != .system })
        for route in routes {
            guard let account = store.account(id: route.accountID) else { continue }
            let apiKey: String
            do {
                guard let storedKey = try store.secret(for: account),
                      !storedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    lastError = "渠道账号尚未配置 API Key"
                    continue
                }
                apiKey = storedKey
            } catch {
                lastError = error.localizedDescription
                continue
            }
            do {
                let response = try await chatClient.complete(
                    endpoint: AIEndpoint(
                        name: channel.name,
                        baseURL: route.baseURL,
                        kind: .openAICompatible
                    ),
                    protocolKind: route.protocolKind,
                    model: route.model,
                    systemPrompt: systemPrompt,
                    messages: outbound,
                    apiKey: apiKey
                ).content
                apiRouteRouter.recordSuccess(for: route)
                store.append(
                    AgentChatMessage(role: .assistant, content: response, accountID: account.id),
                    to: thread.id
                )
                store.updateThreadTarget(id: thread.id, cliKind: nil, accountID: account.id)
                lastError = nil
                return (true, response)
            } catch {
                if shouldQuarantineAPIEndpoint(after: error) {
                    apiRouteRouter.recordFailure(for: route)
                }
                lastError = error.localizedDescription
            }
        }
        return (true, nil)
    }

    private func shouldQuarantineAPIEndpoint(after error: Error) -> Bool {
        if error is URLError || (error as NSError).domain == NSURLErrorDomain {
            return true
        }
        guard let chatError = error as? AIChatClientError,
              case let .http(statusCode) = chatError else {
            return false
        }
        return statusCode == 429 || (500...599).contains(statusCode)
    }

    private func handleMessageConnectionRequest(
        _ request: AIAgentInboundHTTPRequest
    ) async -> AIAgentInboundHTTPResponse {
        let pathParts = request.path.split(separator: "/")
        guard let last = pathParts.last,
              let connectionID = UUID(uuidString: String(last)),
              let connection = store.messageConnection(id: connectionID),
              connection.isEnabled else {
            return .text("not found", statusCode: 404)
        }
        guard let credentials = try? store.messageConnectionCredentials(for: connection) else {
            store.recordMessageConnectionError("连接凭证尚未配置", for: connection.id)
            return .text("service unavailable", statusCode: 503)
        }
        let result = messageConnectionService.process(request, for: connection, credentials: credentials)
        switch result {
        case let .response(response):
            return response
        case let .message(message, acknowledgement):
            Task { [weak self] in await self?.relayMessageConnection(message) }
            return acknowledgement
        }
    }

    private func relayMessageConnection(_ message: AIAgentInboundMessage) async {
        guard let connection = store.messageConnection(id: message.connectionID),
              connection.isEnabled,
              let credentials = try? store.messageConnectionCredentials(for: connection) else {
            return
        }
        let threadID = threadID(for: message, connection: connection)
        await relayLock.acquire()
        let response = await sendLocked(message.content, to: threadID)
        await relayLock.release()
        guard let response else { return }
        do {
            try await messageConnectionService.send(response, replyingTo: message, via: connection, credentials: credentials)
            store.recordMessageConnectionError(nil, for: connection.id)
        } catch {
            store.recordMessageConnectionError(error.localizedDescription, for: connection.id)
        }
    }

    private func threadID(
        for message: AIAgentInboundMessage,
        connection: AgentMessageConnection
    ) -> UUID {
        if let conversation = store.messageConversation(
            connectionID: message.connectionID,
            externalConversationID: message.conversationID
        ), store.state.chatThreads.contains(where: { $0.id == conversation.threadID }) {
            store.upsertMessageConversation(AgentMessageConversation(
                connectionID: conversation.connectionID,
                externalConversationID: conversation.externalConversationID,
                threadID: conversation.threadID
            ))
            return conversation.threadID
        }
        let sender = message.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        let thread = store.createThread(
            cliKind: connection.cliKind,
            accountID: connection.accountID,
            title: "\(connection.kind.displayName) · \(sender.isEmpty ? "新会话" : sender)"
        )
        store.upsertMessageConversation(AgentMessageConversation(
            connectionID: connection.id,
            externalConversationID: message.conversationID,
            threadID: thread.id
        ))
        return thread.id
    }

    public func reply(to confirmationID: UUID, approved: Bool) async {
        guard let confirmation = store.state.confirmations.first(where: { $0.id == confirmationID }),
              confirmation.state == .pending else {
            return
        }
        store.resolveConfirmation(id: confirmationID, state: approved ? .confirmed : .declined)
        let answer = approved ? "确认执行" : "拒绝执行"
        let detail = confirmation.detail.map { "\n\($0)" } ?? ""
        await send("\(answer)：\(confirmation.title)\(detail)", to: confirmation.threadID)
    }

    public func startAutomation() {
        automationMonitoringRequested = true
        updateAutomationLoop(
            hasEnabledAutomations: store.state.automations.contains(where: \.isEnabled)
        )
    }

    public func stopAutomation() {
        automationMonitoringRequested = false
        updateAutomationLoop(hasEnabledAutomations: false)
    }

    var isAutomationLoopRunning: Bool {
        automationTask != nil
    }

    private func updateAutomationLoop(hasEnabledAutomations: Bool) {
        guard automationMonitoringRequested, hasEnabledAutomations else {
            automationTask?.cancel()
            automationTask = nil
            return
        }
        guard automationTask == nil else { return }
        automationTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runDueAutomations()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    public func runDueAutomations(now: Date = Date()) async {
        let due = store.state.automations.filter {
            $0.isEnabled && ($0.nextRunAt == nil || $0.nextRunAt! <= now)
        }
        for automation in due {
            switch automation.task {
            case .balanceCheck: await refreshBalances()
            case .channelProbe: await refreshChannelHealth()
            case .cliCheck: await refreshCLIs()
            case .skillScan: await refreshSkills()
            }
            var updated = automation
            updated.lastRunAt = now
            updated.nextRunAt = now.addingTimeInterval(Double(updated.intervalMinutes) * 60)
            store.updateAutomation(updated)
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

    private func relayCandidates(for thread: AgentChatThread) -> [AgentAccount] {
        guard thread.localModelID == nil else { return [] }
        let eligible: (AgentAccount) -> Bool = { account in
            guard account.credentialKind == .cliProfile,
                  account.cliProfile != nil,
                  account.isEligible(),
                  self.store.hasCLIProfile(for: account) else {
                return false
            }
            return thread.cliKind.map { account.cliProfile?.cliKind == $0 } ?? true
        }
        var candidates: [AgentAccount] = []
        if let channelID = thread.channelID,
           let channel = store.channel(id: channelID), channel.isEnabled {
            let groups = channel.endpointGroups.enumerated().filter { $0.element.isEnabled }.sorted {
                if $0.element.priority != $1.element.priority {
                    return $0.element.priority > $1.element.priority
                }
                return $0.offset < $1.offset
            }
            for group in groups {
                for accountID in group.element.accountIDs where !candidates.contains(where: { $0.id == accountID }) {
                    if let account = store.account(id: accountID), eligible(account) {
                        candidates.append(account)
                    }
                }
            }
        }
        if candidates.isEmpty {
            candidates = store.state.accounts.filter(eligible)
        }
        if let selectedID = thread.accountID,
           let selectedIndex = candidates.firstIndex(where: { $0.id == selectedID }) {
            candidates.swapAt(0, selectedIndex)
        } else if !candidates.isEmpty {
            let cursor = relayCursors[thread.id, default: 0] % candidates.count
            candidates = Array(candidates[cursor...] + candidates[..<cursor])
            relayCursors[thread.id] = (cursor + 1) % candidates.count
        }
        return candidates
    }

    private func activateCLIProfile(
        for account: AgentAccount,
        profile: AgentCLIProfile,
        contents: (configuration: Data, authentication: Data)
    ) throws {
        if let activeID = store.state.activeCLIProfileAccountID, activeID != account.id {
            if let activeAccount = store.account(id: activeID),
               let activeProfile = activeAccount.cliProfile {
                if store.state.activeCLIProfilePreservesAuthentication {
                    try store.replaceCLIConfiguration(
                        cliProfileService.syncBackConfiguration(profile: activeProfile),
                        for: activeID
                    )
                } else {
                    let refreshedContents = try cliProfileService.syncBack(profile: activeProfile)
                    try store.replaceCLIProfile(
                        configuration: refreshedContents.configuration,
                        authentication: refreshedContents.authentication,
                        for: activeID
                    )
                }
            } else {
                store.setActiveCLIProfileAccountID(nil)
            }
        }
        guard store.state.activeCLIProfileAccountID != account.id else { return }
        let preservesAuthentication = CodexOfficialLoginPolicy.preservesAuthentication(
            for: profile.cliKind,
            userPreference: store.state.applicationEnhancements.preservesCodexOfficialLogin,
            isRouteTakeover: true
        )
        if preservesAuthentication {
            try cliProfileService.activateConfiguration(profile: profile, configuration: contents.configuration)
        } else {
            try cliProfileService.activate(profile: profile, contents: contents)
        }
        store.setActiveCLIProfileAccountID(account.id)
        store.setActiveCLIProfilePreservesAuthentication(preservesAuthentication)
        if profile.cliKind == .claude {
            reconcileClaudeCodeVSCodeSettings(
                enhancements: store.state.applicationEnhancements,
                configuration: contents.configuration
            )
        }
    }

    private func reconcileClaudeCodeVSCodeSettings(
        enhancements: AgentApplicationEnhancements,
        configuration: Data? = nil
    ) {
        let activeConfiguration = configuration ?? activeClaudeCodeConfiguration()
        do {
            let updated = try claudeCodeVSCodeSettingsService.reconcile(
                configuration: activeConfiguration,
                enhancements: enhancements
            )
            store.updateApplicationEnhancements(updated)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func activeClaudeCodeConfiguration() -> Data? {
        guard let accountID = store.state.activeCLIProfileAccountID,
              let account = store.account(id: accountID),
              account.cliProfile?.cliKind == .claude else {
            return nil
        }
        return try? store.cliProfileContents(for: account)?.configuration
    }
}
