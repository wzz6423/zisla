import SwiftUI
import ZislaCore
import ZislaKit

struct AIAgentModuleView: View {
    private static let configurableRemoteProtocols: [AgentChannelProtocol] = [
        .openAICompatible,
        .anthropicMessages,
    ]

    enum ConfigurationScope {
        case tools
        case localModels
        case remoteModels
    }

    @ObservedObject private var agent: AIAgentWorkspace
    private let configurationScope: ConfigurationScope
    @State private var pendingCLICommands: [AIAgentCLICommand] = []
    @State private var pendingCLIActionTitle = ""
    @State private var pendingCLIActionMessage = ""
    @State private var pendingCLIKinds: [AgentCLIKind] = []
    @State private var showCLIConfirmation = false

    init(model: AppModel, configurationScope: ConfigurationScope) {
        _agent = ObservedObject(wrappedValue: model.aiAgent)
        self.configurationScope = configurationScope
    }

    var body: some View {
        configurationContent
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .alert(pendingCLIActionTitle, isPresented: $showCLIConfirmation) {
            Button("取消", role: .cancel) {
                pendingCLICommands = []
                pendingCLIKinds = []
            }
            Button("继续") {
                let commands = pendingCLICommands
                guard !commands.isEmpty else { return }
                pendingCLICommands = []
                agent.startCLICommands(commands, title: pendingCLIActionTitle, kinds: pendingCLIKinds)
                pendingCLIKinds = []
            }
        } message: {
            Text(pendingCLIActionMessage)
        }
    }

    @ViewBuilder
    private var configurationContent: some View {
        switch configurationScope {
        case .tools:
            toolsContent
        case .localModels:
            localModelContent
        case .remoteModels:
            channelContent
        }
    }

    private var channelContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(agent.store.state.channels) { channel in
                remoteModelRow(channel)
            }
            emptyModelRow(
                title: agent.store.state.channels.isEmpty ? "尚未配置远端模型" : "添加远端模型",
                symbol: "cloud.slash",
                help: "添加远端模型",
                action: addProvider
            )
        }
        .padding(3)
    }

    private func remoteModelRow(_ channel: AgentChannel) -> some View {
        HStack(spacing: 7) {
            Toggle("", isOn: channelEnabledBinding(channel.id))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel("启用远端模型")
            Picker("协议", selection: channelProtocolBinding(channel.id)) {
                ForEach(Self.configurableRemoteProtocols, id: \.self) { proto in
                    Text(proto == .openAICompatible ? "OpenAI" : "Anthropic").tag(proto)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 92)
            .accessibilityLabel("协议")
            TextField("URL", text: channelURLBinding(channel.id))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
                .frame(minWidth: 140)
                .layoutPriority(1)
            SecureField("Key", text: channelSecretBinding(channel.id))
                .textFieldStyle(.roundedBorder)
                .frame(width: 125)
            TextField("模型名", text: channelModelBinding(channel.id))
                .textFieldStyle(.roundedBorder)
                .frame(width: 125)
            Picker("Effort", selection: channelEffortBinding(channel.id)) {
                ForEach(AgentModelEffort.allCases, id: \.self) { effort in
                    Text(effort.displayName).tag(effort)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 84)
            .accessibilityLabel("Effort")
            Button {
                agent.store.removeChannel(id: channel.id)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除远端模型")
            .help("删除远端模型")
        }
        .padding(7)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func addProvider() {
        _ = agent.store.createRemoteProvider(
            name: "远端模型 \(agent.store.state.channels.count + 1)"
        )
    }

    private func primaryAccount(for channel: AgentChannel) -> AgentAccount? {
        guard let accountID = channel.endpointGroups.first?.accountIDs.first else { return nil }
        return agent.store.account(id: accountID)
    }

    private func attachAccount(_ accountID: UUID, to channelID: UUID) {
        guard agent.store.account(id: accountID) != nil else { return }
        updateChannel(channelID) { channel in
            if channel.endpointGroups.isEmpty {
                channel.endpointGroups.append(AgentEndpointGroup(
                    name: "默认端点",
                    baseURLs: ["https://api.openai.com/v1"],
                    accountIDs: [accountID]
                ))
            } else if !channel.endpointGroups[0].accountIDs.contains(accountID) {
                channel.endpointGroups[0].accountIDs.insert(accountID, at: 0)
            }
        }
    }

    private var localModelContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(agent.store.state.localModels) { localModel in
                localModelRow(localModel)
            }
            emptyModelRow(
                title: agent.store.state.localModels.isEmpty ? "尚未配置本地模型" : "添加本地模型",
                symbol: "cpu",
                help: "添加本地模型",
                action: addLocalModelConfiguration
            )
        }
        .padding(3)
    }

    private func emptyModelRow(
        title: String,
        symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: action) {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(help)
            .help(help)
        }
        .padding(7)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func localModelRow(_ localModel: AIAgentLocalModel) -> some View {
        HStack(spacing: 7) {
            Toggle("", isOn: localModelEnabledBinding(localModel.id))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel("启用本地模型")
            TextField("URL / IP:端口", text: localModelURLBinding(localModel.id))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
                .frame(minWidth: 240)
                .layoutPriority(1)
            TextField("模型名", text: localModelIDBinding(localModel.id))
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button { agent.store.removeLocalModel(id: localModel.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .accessibilityLabel("删除本地模型")
                .help("删除本地模型")
        }
        .padding(7)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var toolsContent: some View {
        let installedKinds = cliKinds(installed: true)
        let missingKinds = cliKinds(installed: false)
        let installCommands = agent.commandsForCLIInstallation(missingKinds, update: false)
        let updateKinds = agent.cliUpdates.map(\.kind)
        let updateCommands = agent.commandsForCLIInstallation(updateKinds, update: true)
        let uninstallCommands = agent.commandsForCLIUninstallation(installedKinds)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Text("CLI")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button {
                    Task { await agent.refreshCLIs() }
                } label: {
                    Group {
                        if agent.isCheckingCLIs {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help("重新检测本机 CLI")
                Button {
                    queueCLIAction(
                        title: "下载缺失 CLI？",
                        message: cliActionMessage("将下载并安装", kinds: missingKinds),
                        kinds: missingKinds,
                        commands: installCommands
                    )
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .disabled(installCommands.isEmpty)
                .help("一键下载所有未安装的 CLI")
                Button {
                    queueCLIAction(
                        title: "更新已安装 CLI？",
                        message: cliActionMessage("将更新", kinds: installedKinds),
                        kinds: installedKinds,
                        commands: updateCommands
                    )
                } label: {
                    Image(systemName: "arrow.up.circle")
                }
                .buttonStyle(.borderless)
                .disabled(updateCommands.isEmpty)
                .help("一键更新所有已安装的 CLI")
                Button(role: .destructive) {
                    queueCLIAction(
                        title: "卸载已安装 CLI？",
                        message: cliActionMessage("将卸载", kinds: installedKinds),
                        kinds: installedKinds,
                        commands: uninstallCommands
                    )
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(uninstallCommands.isEmpty)
                .help("一键卸载所有受支持的 CLI")
            }
            cliCommandGroup(title: "下载命令", commands: installCommands)
            cliCommandGroup(title: "更新命令", commands: updateCommands)

            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.fillControl)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("自动更新 CLI")
                        .font(.system(size: 11, weight: .semibold))
                    Text("检测到新版本后自动执行更新；关闭后不再启动新任务，已开始的更新会完成")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { agent.store.state.cliAutoUpdateEnabled },
                    set: { agent.setCLIAutoUpdateEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            if let progress = agent.cliCommandProgress {
                cliCommandProgressView(progress)
            }
            ForEach(AgentCLIKind.detectableCases, id: \.self) { kind in
                let status = agent.store.state.cliStatuses.first { $0.kind == kind }
                let isInstalled = status?.executablePath != nil
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(kind.displayName).frame(width: 80, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            if isInstalled {
                                Text(status?.version ?? "已安装（版本未知）")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.primary)
                                if let path = status?.executablePath {
                                    Text(path)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            } else {
                                HStack(spacing: 5) {
                                    Text("未安装")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    cliCommandRows(
                                        commands: agent.commandsForCLIInstallation([kind], update: false),
                                        paddingLeading: 0
                                    )
                                }
                            }
                        }
                        Spacer()
                        if AgentCLIKind.managedCases.contains(kind), isInstalled {
                            let update = agent.commandsForCLIInstallation([kind], update: true)
                            let availableUpdate = agent.cliUpdates.first { $0.kind == kind }
                            if agent.isCheckingCLIs {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 16, height: 16)
                                    .help("正在检查 \(kind.displayName) 更新")
                            } else if let availableUpdate {
                                Button {
                                    queueCLIAction(
                                        title: "更新 \(kind.displayName)？",
                                        message: "将 \(kind.displayName) 从 \(availableUpdate.installedVersion) 更新到 \(availableUpdate.latestVersion)",
                                        kinds: [kind],
                                        commands: update
                                    )
                                } label: {
                                    Image(systemName: "arrow.up.circle")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(Color.zislaInfo)
                                .disabled(agent.isRunningCLICommands || update.isEmpty)
                                .help("已确认新版本 \(availableUpdate.latestVersion)，更新 \(kind.displayName)")
                            } else if status?.version != nil, kind != .kimi {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(kind == .grok && agent.grokUpdateState == .upToDate ? .green : .secondary)
                                    .help(kind == .grok && agent.grokUpdateState == .upToDate ? "Grok 已是最新版本" : "当前未检测到可用更新")
                            } else {
                                Button {
                                    queueCLIAction(
                                        title: "更新 \(kind.displayName)？",
                                        message: cliActionMessage("将更新", kinds: [kind]),
                                        kinds: [kind],
                                        commands: update
                                    )
                                } label: {
                                    Image(systemName: "arrow.up.circle")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .disabled(agent.isRunningCLICommands || update.isEmpty)
                                .help(status?.version == nil ? "版本未知，可尝试更新 \(kind.displayName)" : "检查并升级 \(kind.displayName)")
                            }
                            let uninstall = agent.commandsForCLIUninstallation([kind])
                            Button(role: .destructive) {
                                queueCLIAction(
                                    title: "卸载 \(kind.displayName)？",
                                    message: cliActionMessage("将卸载", kinds: [kind]),
                                    kinds: [kind],
                                    commands: uninstall
                                )
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(agent.isRunningCLICommands || uninstall.isEmpty)
                            .help("卸载 \(kind.displayName)")
                        } else if AgentCLIKind.managedCases.contains(kind) {
                            let install = agent.commandsForCLIInstallation([kind], update: false)
                            Button {
                                queueCLIAction(
                                    title: "下载 \(kind.displayName)？",
                                    message: cliActionMessage("将下载并安装", kinds: [kind]),
                                    kinds: [kind],
                                    commands: install
                                )
                            } label: {
                                Image(systemName: "arrow.down.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(install.isEmpty)
                            .help("下载并安装 \(kind.displayName)")
                        }
                    }
                    if AgentCLIKind.managedCases.contains(kind), isInstalled {
                        cliCommandRows(
                            commands: agent.commandsForCLIInstallation([kind], update: true),
                            paddingLeading: 88
                        )
                    }
                }
                Divider()
            }

            SkillManagementView(agent: agent)
        }
        .padding(3)
        .task {
            await agent.refreshCLIs()
        }
    }

    private func cliKinds(installed: Bool) -> [AgentCLIKind] {
        AgentCLIKind.managedCases.filter { kind in
            let isInstalled = agent.store.state.cliStatuses.first { $0.kind == kind }?.executablePath != nil
            return isInstalled == installed
        }
    }

    private func cliActionMessage(_ action: String, kinds: [AgentCLIKind]) -> String {
        let names = kinds.map(\.displayName).joined(separator: "、")
        let standaloneKinds = kinds.filter { $0 == .grok || $0 == .kimi }
        let uninstallNote = !standaloneKinds.isEmpty && action.contains("卸载")
            ? "\(standaloneKinds.map(\.displayName).joined(separator: "、")) 只会移除 CLI 可执行文件，保留账号和本地配置。"
            : "命令会在本机执行，完成后将重新检测安装状态。"
        return "\(action)：\(names)。\(uninstallNote)"
    }

    private func queueCLIAction(
        title: String,
        message: String,
        kinds: [AgentCLIKind],
        commands: [AIAgentCLICommand]
    ) {
        guard !commands.isEmpty else { return }
        pendingCLIActionTitle = title
        pendingCLIActionMessage = message
        pendingCLIKinds = kinds
        pendingCLICommands = commands
        showCLIConfirmation = true
    }

    private func cliCommandProgressView(_ progress: AIAgentCLICommandProgress) -> some View {
        HStack(spacing: 6) {
            switch progress.state {
            case .running:
                Image(systemName: "clock")
            case .succeeded:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(cliCommandProgressTitle(progress))
                    .font(.system(size: 10, weight: .medium))
            }
            Spacer(minLength: 6)
            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)
                .frame(width: 72)
            Text("\(progress.completedCount)/\(progress.totalCount)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func cliCommandProgressTitle(_ progress: AIAgentCLICommandProgress) -> String {
        let action = progress.title.replacingOccurrences(of: "？", with: "")
        switch progress.state {
        case .running: return "正在\(action)"
        case .succeeded: return "\(action) 已完成"
        case .failed: return "\(action) 失败"
        }
    }

    @ViewBuilder
    private func cliCommandGroup(title: String, commands: [AIAgentCLICommand]) -> some View {
        if !commands.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                cliCommandRows(commands: commands, paddingLeading: 0)
            }
        }
    }

    @ViewBuilder
    private func cliCommandRows(
        commands: [AIAgentCLICommand],
        paddingLeading: CGFloat
    ) -> some View {
        ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
            let commandText = formatCommandForDisplay(command)
            HStack(spacing: 4) {
                Text(commandText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(commandText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                }
                .buttonStyle(.borderless)
                .help("复制命令")
            }
            .padding(.leading, paddingLeading)
        }
    }

    private func formatCommandForDisplay(_ command: AIAgentCLICommand) -> String {
        let executable = command.executableURL.lastPathComponent
        let args = command.arguments.map(shellArgument).joined(separator: " ")
        return "\(executable) \(args)".trimmingCharacters(in: .whitespaces)
    }

    private func shellArgument(_ argument: String) -> String {
        let shellCharacters = CharacterSet(charactersIn: " \\t\\n\\\\'\\\"$`;&|<>*?()[]{}!~")
        guard argument.rangeOfCharacter(from: shellCharacters) != nil else { return argument }
        return "'\(argument.replacingOccurrences(of: "'", with: "'\\\\''"))'"
    }

    private func updateAccount(_ id: UUID, _ update: (inout AgentAccount) -> Void) {
        guard var account = agent.store.account(id: id) else { return }
        update(&account)
        try? agent.store.upsertAccount(account)
    }

    private func updateChannel(_ id: UUID, _ update: (inout AgentChannel) -> Void) {
        guard var channel = agent.store.channel(id: id) else { return }
        update(&channel)
        agent.store.upsertChannel(channel)
    }

    private func updateLocalModel(_ id: UUID, _ update: (inout AIAgentLocalModel) -> Void) {
        guard var localModel = agent.store.localModel(id: id) else { return }
        update(&localModel)
        agent.store.upsertLocalModel(localModel)
    }

    private func addLocalModelConfiguration() {
        let endpoint = AIEndpoint(
            name: "Ollama / LM Studio",
            baseURL: AIEndpointKind.ollama.defaultBaseURL,
            kind: .openAICompatible
        )
        agent.store.upsertLocalModel(AIAgentLocalModel(
            name: "qwen3:8b",
            endpoint: endpoint,
            modelName: "qwen3:8b"
        ))
    }

    private func channelModelBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { agent.store.channel(id: id)?.defaultModel ?? "" }, set: { value in updateChannel(id) { $0.defaultModel = value } })
    }

    private func channelProtocolBinding(_ id: UUID) -> Binding<AgentChannelProtocol> {
        Binding(get: { agent.store.channel(id: id)?.protocolKind ?? .openAICompatible }, set: { value in updateChannel(id) { $0.protocolKind = value } })
    }

    private func channelEffortBinding(_ id: UUID) -> Binding<AgentModelEffort> {
        Binding(get: { agent.store.channel(id: id)?.effort ?? .high }, set: { value in updateChannel(id) { $0.effort = value } })
    }

    private func channelEnabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { agent.store.channel(id: id)?.isEnabled ?? false }, set: { value in updateChannel(id) { $0.isEnabled = value } })
    }

    private func channelURLBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { agent.store.channel(id: id)?.endpointGroups.first?.baseURLs.first ?? "" },
            set: { value in
                let baseURLs = AgentEndpointGroup.normalizedURLs([value])
                updateChannel(id) { channel in
                    if channel.endpointGroups.isEmpty {
                        channel.endpointGroups.append(AgentEndpointGroup(
                            name: "默认端点",
                            baseURLs: baseURLs,
                            accountIDs: []
                        ))
                    } else {
                        channel.endpointGroups[0].baseURLs = baseURLs
                    }
                }
            }
        )
    }

    private func channelSecretBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let channel = agent.store.channel(id: id),
                      let account = primaryAccount(for: channel) else { return "" }
                return (try? agent.store.secret(for: account)) ?? ""
            },
            set: { value in
                guard !value.isEmpty,
                      let channel = agent.store.channel(id: id) else { return }
                let account: AgentAccount
                if let existing = primaryAccount(for: channel) {
                    account = existing
                } else {
                    let created = AgentAccount(name: channel.name, provider: channel.name)
                    do {
                        try agent.store.upsertAccount(created)
                    } catch {
                        return
                    }
                    attachAccount(created.id, to: id)
                    account = created
                }
                if account.credentialKind != .apiKey {
                    updateAccount(account.id) { $0.credentialKind = .apiKey }
                }
                try? agent.store.replaceSecret(value, for: account.id)
            }
        )
    }

    private func localModelIDBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { agent.store.localModel(id: id)?.modelName ?? "" }, set: { value in updateLocalModel(id) { $0.modelName = value } })
    }

    private func localModelURLBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { agent.store.localModel(id: id)?.endpoint.baseURL ?? "" }, set: { value in updateLocalModel(id) { $0.endpoint.baseURL = value } })
    }

    private func localModelEnabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { agent.store.localModel(id: id)?.isEnabled ?? false }, set: { value in updateLocalModel(id) { $0.isEnabled = value } })
    }

    private func skillEnabledBinding(_ path: String) -> Binding<Bool> {
        Binding(
            get: { agent.store.state.skills.first { $0.path == path }?.isEnabled ?? false },
            set: { enabled in
                var skills = agent.store.state.skills
                guard let index = skills.firstIndex(where: { $0.path == path }) else { return }
                skills[index].isEnabled = enabled
                agent.store.replaceSkills(skills)
            }
        )
    }
}
