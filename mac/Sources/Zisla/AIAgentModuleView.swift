import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit

struct AIAgentModuleView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case chat
        case channels
        case connections
        case localModels
        case applications
        case automation
        case tools
        case storage

        var id: Self { self }

        var title: String {
            switch self {
            case .chat: "对话"
            case .channels: "远端模型与凭据"
            case .connections: "消息连接"
            case .localModels: "本地模型"
            case .applications: "应用增强"
            case .automation: "自动化"
            case .tools: "CLI 与 Skills"
            case .storage: "会话存储"
            }
        }

        static func sections(for scope: ConfigurationScope) -> [Self] {
            switch scope {
            case .agent: [.connections, .applications, .automation, .tools, .storage]
            case .localModels: [.localModels]
            case .remoteModels: [.channels]
            }
        }
    }

    /// 模型与凭据只在模型页维护，AI 页只展示 Agent 行为设置。
    enum ConfigurationScope {
        case agent
        case localModels
        case remoteModels
    }

    @ObservedObject var model: AppModel
    @ObservedObject private var agent: AIAgentWorkspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let configurationScope: ConfigurationScope?
    @Namespace private var sectionSelectionNamespace
    @State private var section: Section = .chat
    @State private var selectedThreadID: UUID?
    @State private var draft = ""
    @State private var draftAttachments: [AgentChatAttachment] = []
    @State private var referencedThreadIDs: [UUID] = []
    @State private var referencedApps: [AgentChatAppReference] = []
    @State private var selectedProjectID: UUID?
    @State private var projectDirectoryError: String?
    @State private var attachmentImportError: String?
    @State private var chatCommandError: String?
    @State private var annotationSelection: AnnotationSelection?
    @State private var annotationDraft = ""
    @State private var hoveredMessageID: UUID?
    @State private var expandedMessageIDs = Set<UUID>()
    @State private var pendingThreadDeletion: AgentChatThread?
    @State private var pendingProjectDeletion: AgentChatProject?
    @State private var pendingCLICommands: [AIAgentCLICommand] = []
    @State private var pendingCLIActionTitle = ""
    @State private var pendingCLIActionMessage = ""
    @State private var pendingCLIKinds: [AgentCLIKind] = []
    @State private var showCLIConfirmation = false
    @State private var profileImportRequest: ProfileImportRequest?
    @State private var isChatTransferTarget = false
    @State private var isModelPickerPresented = false

    private enum ProfileFileKind {
        case configuration
        case authentication
    }

    private struct ProfileImportRequest: Identifiable {
        let id = UUID()
        let accountID: UUID
        let fileKind: ProfileFileKind
    }

    private struct AnnotationSelection: Equatable {
        let threadID: UUID
        let messageID: UUID
        let text: String
    }

    private enum ComposerSuggestion: Equatable {
        case reference(query: String)
        case command(query: String)
    }

    private struct ComposerCommandSuggestion: Identifiable {
        let insertion: String
        let title: String
        let detail: String
        let symbolName: String

        var id: String { insertion }
    }

    init(model: AppModel, configurationScope: ConfigurationScope? = nil) {
        _model = ObservedObject(wrappedValue: model)
        _agent = ObservedObject(wrappedValue: model.aiAgent)
        self.configurationScope = configurationScope
        _section = State(
            initialValue: configurationScope.map { Section.sections(for: $0)[0] } ?? .chat
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            if let configurationScope {
                configurationContent(for: configurationScope)
            } else {
                header
                chatContent
            }
        }
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
        .fileImporter(
            isPresented: Binding(
                get: { profileImportRequest != nil },
                set: { if !$0 { profileImportRequest = nil } }
            ),
            allowedContentTypes: [.data],
            allowsMultipleSelection: false,
            onCompletion: importCLIProfileFile
        )
        .alert(
            "无法添加附件",
            isPresented: Binding(
                get: { attachmentImportError != nil },
                set: { if !$0 { attachmentImportError = nil } }
            )
        ) {
            Button("好") { attachmentImportError = nil }
        } message: {
            Text(attachmentImportError ?? "")
        }
        .alert(
            "无法执行斜杠命令",
            isPresented: Binding(
                get: { chatCommandError != nil },
                set: { if !$0 { chatCommandError = nil } }
            )
        ) {
            Button("好") { chatCommandError = nil }
        } message: {
            Text(chatCommandError ?? "")
        }
        .alert(
            "无法添加项目",
            isPresented: Binding(
                get: { projectDirectoryError != nil },
                set: { if !$0 { projectDirectoryError = nil } }
            )
        ) {
            Button("好") { projectDirectoryError = nil }
        } message: {
            Text(projectDirectoryError ?? "")
        }
        .alert("永久删除会话？", isPresented: Binding(
            get: { pendingThreadDeletion != nil },
            set: { if !$0 { pendingThreadDeletion = nil } }
        )) {
            Button("取消", role: .cancel) { pendingThreadDeletion = nil }
            Button("删除", role: .destructive) {
                if let thread = pendingThreadDeletion {
                    agent.store.deleteThread(id: thread.id)
                }
                pendingThreadDeletion = nil
            }
        } message: {
            Text("会话及其附件私有副本将被永久删除。")
        }
        .alert("删除项目？", isPresented: Binding(
            get: { pendingProjectDeletion != nil },
            set: { if !$0 { pendingProjectDeletion = nil } }
        )) {
            Button("取消", role: .cancel) { pendingProjectDeletion = nil }
            Button("删除", role: .destructive) {
                if let project = pendingProjectDeletion {
                    agent.store.deleteProject(id: project.id)
                    if selectedProjectID == project.id {
                        selectedProjectID = nil
                    }
                }
                pendingProjectDeletion = nil
            }
        } message: {
            Text("项目下的会话会保留，并移回未归类对话。")
        }
    }

    private func configurationContent(for scope: ConfigurationScope) -> some View {
        let sections = Section.sections(for: scope)
        return VStack(spacing: 8) {
            // A single-section scope needs no switcher; the settings group title already names it.
            if sections.count > 1 {
                sectionPicker(sections)
            }

            Group {
                switch section {
                case .chat:
                    EmptyView()
                case .channels:
                    channelContent
                case .connections:
                    messageConnectionContent
                case .localModels:
                    localModelContent
                case .applications:
                    applicationEnhancementsContent
                case .automation:
                    automationContent
                case .tools:
                    toolsContent
                case .storage:
                    storageContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func sectionPicker(_ sections: [Section]) -> some View {
        HStack(spacing: 8) {
            Text("行为分类")

            HStack(spacing: 0) {
                ForEach(sections) { candidate in
                    let isSelected = section == candidate
                    Button {
                        guard !isSelected else { return }
                        if reduceMotion {
                            section = candidate
                        } else {
                            withAnimation(ZislaMotion.selection) {
                                section = candidate
                            }
                        }
                    } label: {
                        Text(candidate.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .background {
                                if isSelected {
                                    SelectionGlassBackground(cornerRadius: 5)
                                        .matchedGeometryEffect(
                                            id: "ai-agent-section-selection",
                                            in: sectionSelectionNamespace
                                        )
                                }
                            }
                    }
                    .buttonStyle(PressableStyle(hoverScale: 1.025, pressedScale: 0.95))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(2)
            .background(Color.fillControl)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : ZislaMotion.selection, value: section)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("AI Agent", systemImage: "sparkles")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            if let error = headerErrorText {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Button {
                Task { await agent.refreshAll() }
            } label: {
                if agent.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("刷新余额、渠道、CLI 和 Skills")
            .disabled(agent.isRefreshing)
        }
    }

    private var headerErrorText: String? {
        guard let error = agent.lastError, !error.isEmpty else { return nil }
        guard let progress = agent.cliCommandProgress,
              progress.state == .failed,
              progress.detail == error else {
            return error
        }
        return "CLI 操作失败"
    }

    private var chatContent: some View {
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                HStack {
                    Text("统一历史")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Button {
                        let profileAccount = agent.store.state.accounts.first { agent.store.hasCLIProfile(for: $0) }
                        let thread = agent.store.createThread(
                            useMostRecentModel: true,
                            cliKind: profileAccount?.cliProfile?.cliKind,
                            accountID: profileAccount?.id,
                            projectID: selectedProjectID ?? selectedThread?.projectID
                        )
                        selectedThreadID = thread.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("新建对话")
                }
                Menu {
                    Button {
                        chooseProjectDirectory(canCreateDirectory: false)
                    } label: {
                        Label("添加现有文件夹…", systemImage: "folder.badge.plus")
                    }
                    Button {
                        chooseProjectDirectory(canCreateDirectory: true)
                    } label: {
                        Label("新建文件夹并添加…", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("添加项目", systemImage: "folder.badge.plus")
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
                .help("将本地文件夹添加为项目")
                List {
                    let activeThreads = agent.store.activeThreads()
                    let ungroupedThreads = activeThreads.filter { $0.projectID == nil }
                    if !ungroupedThreads.isEmpty {
                        SwiftUI.Section("未归类") {
                            ForEach(ungroupedThreads) { thread in
                                chatThreadRow(thread)
                            }
                        }
                    }
                    ForEach(agent.store.sortedProjects()) { project in
                        let projectThreads = activeThreads.filter { $0.projectID == project.id }
                        SwiftUI.Section {
                            if !project.isCollapsed {
                                ForEach(projectThreads) { thread in
                                    chatThreadRow(thread)
                                }
                            }
                        } header: {
                            HStack(spacing: 4) {
                                Button {
                                    agent.store.setProjectCollapsed(!project.isCollapsed, for: project.id)
                                } label: {
                                    Image(systemName: project.isCollapsed ? "chevron.right" : "chevron.down")
                                        .frame(width: 14, height: 14)
                                }
                                .buttonStyle(.borderless)
                                .help(project.isCollapsed ? "展开项目会话" : "收起项目会话")
                                .accessibilityLabel(project.isCollapsed ? "展开 \(project.name) 会话" : "收起 \(project.name) 会话")
                                Button {
                                    selectedProjectID = project.id
                                } label: {
                                    Label(project.name, systemImage: "folder")
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                .help("选择项目；新建对话会归入此项目")
                                .foregroundStyle(selectedProjectID == project.id ? Color.primary : Color.secondary)
                                Spacer(minLength: 0)
                                Button {
                                    agent.store.toggleProjectPinned(id: project.id)
                                } label: {
                                    Image(systemName: project.isPinned ? "pin.fill" : "pin")
                                }
                                .buttonStyle(.borderless)
                                .help(project.isPinned ? "取消置顶项目" : "置顶项目")
                                .accessibilityLabel(project.isPinned ? "取消置顶 \(project.name)" : "置顶 \(project.name)")
                                Button {
                                    pendingProjectDeletion = project
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("删除项目")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .thinScrollChrome()
            }
            .frame(width: 170)

            Divider()

            VStack(spacing: 7) {
                if let thread = selectedThread {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            confirmationRows(for: thread.id)
                            ForEach(thread.messages) { message in
                                chatMessage(message, in: thread.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .thinScrollChrome()
                    composer(for: thread.id)
                } else {
                    ContentUnavailableView("选择或新建对话", systemImage: "bubble.left.and.bubble.right")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if isChatTransferTarget {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: TransferDropDelegate.supportedTypes,
            delegate: TransferDropDelegate(isTargeted: $isChatTransferTarget) {
                handleDroppedItems($0)
            }
        )
    }

    private func chooseProjectDirectory(canCreateDirectory: Bool) {
        let panel = NSOpenPanel()
        panel.title = canCreateDirectory ? "新建项目文件夹" : "添加现有项目文件夹"
        panel.message = canCreateDirectory
            ? "在目标位置新建文件夹，然后选择它作为项目。"
            : "选择要作为项目的本地文件夹。"
        panel.prompt = canCreateDirectory ? "添加新文件夹" : "添加项目"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = canCreateDirectory
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let directory = panel.url else { return }
        addProjectDirectory(directory)
    }

    private func addProjectDirectory(_ directory: URL) {
        let normalizedURL = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            projectDirectoryError = "所选位置不是可用的文件夹。"
            return
        }
        if agent.store.state.projects.contains(where: {
            !$0.directoryPath.isEmpty
                && URL(fileURLWithPath: $0.directoryPath).standardizedFileURL.path == normalizedURL.path
        }) {
            projectDirectoryError = "该文件夹已经作为项目添加。"
            return
        }
        guard let project = agent.store.createProject(
            name: normalizedURL.lastPathComponent,
            directoryPath: normalizedURL.path
        ) else {
            projectDirectoryError = "无法使用所选文件夹创建项目。"
            return
        }
        selectedProjectID = project.id
    }

    /// Codex-style transcript: no bubbles or avatars, one full-width column, the speaker named in a
    /// small caption, and the user's turn marked by a rule instead of a filled card.
    private func chatMessage(_ message: AgentChatMessage, in threadID: UUID) -> some View {
        let isUser = message.role == .user
        let imageAttachments = message.attachments.filter { $0.kind == .image }
        let detailAttachments = message.attachments.filter { $0.kind != .image }
        let hasExecutionDetails = !detailAttachments.isEmpty
            || !message.contextReferences.isEmpty
            || !message.appReferences.isEmpty
        let assistantImages = message.role == .assistant
            ? ChatMessageMarkdown.imageReferences(in: message.content)
            : []
        return HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(isUser ? Color.primary.opacity(0.22) : Color.clear)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(isUser ? "你" : chatSpeakerName(for: message))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                if message.role == .assistant {
                    SelectableChatMessageText(content: message.content) { selectedText in
                        let normalized = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !normalized.isEmpty {
                            annotationSelection = AnnotationSelection(threadID: threadID, messageID: message.id, text: normalized)
                        } else if annotationSelection?.messageID == message.id {
                            // 只有持有当前选区的消息取消选区才收起批注框；误点其他消息不应丢掉输入中的草稿。
                            annotationSelection = nil
                            annotationDraft = ""
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(message.content)
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(imageAttachments) { attachment in
                    if let url = agent.store.attachmentURL(for: attachment) {
                        chatImage(url: url, label: attachment.fileName)
                    }
                }
                ForEach(assistantImages) { image in
                    chatImage(url: image.url, label: image.alt)
                }
                if hasExecutionDetails {
                    Button {
                        if expandedMessageIDs.contains(message.id) {
                            expandedMessageIDs.remove(message.id)
                        } else {
                            expandedMessageIDs.insert(message.id)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: expandedMessageIDs.contains(message.id) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                            Text("执行细节")
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if message.mode == .plan {
                    Label("计划模式", systemImage: "list.bullet.clipboard")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                }
                if let goal = message.goalTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !goal.isEmpty {
                    Label(goal, systemImage: "target")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                if !message.skillReferences.isEmpty {
                    Label(
                        message.skillReferences.map(\.name).joined(separator: "、"),
                        systemImage: "puzzlepiece.extension"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                // 执行细节内容区（可展开/收起）
                if expandedMessageIDs.contains(message.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        if !detailAttachments.isEmpty {
                            ForEach(detailAttachments) { attachment in
                                messageAttachment(attachment)
                            }
                        }
                        if !message.contextReferences.isEmpty {
                            Label(
                                "引用 \(message.contextReferences.map(\.title).joined(separator: "、"))",
                                systemImage: "at"
                            )
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        }
                        if !message.appReferences.isEmpty {
                            Label(
                                "本机 App：\(message.appReferences.map(\.name).joined(separator: "、"))",
                                systemImage: "app"
                            )
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 12)
                }
                if message.role == .assistant {
                    HStack(spacing: 8) {
                        Button {
                            copyMessageContent(message.content)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("复制回复")
                        Button {
                            guard let fork = agent.store.forkThread(at: message.id, in: threadID) else { return }
                            selectedThreadID = fork.id
                        } label: {
                            Image(systemName: "arrow.triangle.branch")
                        }
                        .buttonStyle(.borderless)
                        .help("从此回复分叉会话")
                        if annotationSelection?.messageID == message.id {
                            Image(systemName: "text.badge.plus")
                                .foregroundStyle(.secondary)
                            TextField("批注", text: $annotationDraft)
                                .islandGlassField()
                                .font(.system(size: 9))
                            Button {
                                guard let selection = annotationSelection,
                                      agent.store.addAnnotation(
                                        threadID: selection.threadID,
                                        messageID: selection.messageID,
                                        selectedText: selection.text,
                                        comment: annotationDraft
                                      ) != nil else {
                                    return
                                }
                                annotationSelection = nil
                                annotationDraft = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .disabled(annotationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("添加批注")
                            Button {
                                guard let selection = annotationSelection else { return }
                                sendAnnotationAsMessage(
                                    selectedText: selection.text,
                                    comment: annotationDraft,
                                    to: threadID
                                )
                                annotationSelection = nil
                                annotationDraft = ""
                            } label: {
                                Image(systemName: "paperplane.fill")
                            }
                            .buttonStyle(.borderless)
                            .disabled(annotationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("将引用和评论发送为新消息")
                        }
                    }
                    .font(.system(size: 10))
                    // Keep the transcript free of permanent chrome; the row still reserves its height
                    // so revealing the actions never reflows the messages below.
                    .opacity(showsActions(for: message) ? 1 : 0)
                    .allowsHitTesting(showsActions(for: message))
                    let annotations = agent.store.annotations(for: message.id)
                    ForEach(annotations) { annotation in
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "text.quote")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(annotation.selectedText)
                                    .lineLimit(2)
                                Text(annotation.comment)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                agent.store.deleteAnnotation(id: annotation.id)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("删除批注")
                        }
                        .font(.system(size: 9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, 4)
        .contentShape(.rect)
        .onHover { hovering in
            // enter/exit 事件到达顺序无保证：旧行的 exit 可能晚于新行的 enter，无条件置 nil 会清掉新行的 hover。
            if hovering {
                hoveredMessageID = message.id
            } else if hoveredMessageID == message.id {
                hoveredMessageID = nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: showsActions(for: message))
    }

    private func showsActions(for message: AgentChatMessage) -> Bool {
        hoveredMessageID == message.id || annotationSelection?.messageID == message.id
    }

    private func chatSpeakerName(for message: AgentChatMessage) -> String {
        guard let accountID = message.accountID,
              let account = agent.store.account(id: accountID)
        else { return "助手" }
        return account.name
    }

    @ViewBuilder
    private func messageAttachment(_ attachment: AgentChatAttachment) -> some View {
        if attachment.state == .deleted {
            Label("已删除：\(attachment.fileName)", systemImage: "trash")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        } else if let url = agent.store.attachmentURL(for: attachment) {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: attachmentSymbol(for: attachment.kind))
                        .frame(width: 18)
                    Text(attachment.fileName)
                        .lineLimit(1)
                }
                .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("在访达中打开 \(attachment.fileName)")
        } else {
            Label("不可用：\(attachment.fileName)", systemImage: "exclamationmark.triangle")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func chatImage(url: URL, label: String) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            if url.isFileURL, let image = NSImage(contentsOf: url) {
                chatImageContent(Image(nsImage: image))
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        chatImageContent(image)
                    case .failure:
                        Label(label.isEmpty ? "无法加载图片" : label, systemImage: "photo")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    default:
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 48, height: 36)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .help(label.isEmpty ? "打开图片" : "打开 \(label)")
        .accessibilityLabel(label.isEmpty ? "图片" : label)
    }

    private func chatImageContent(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 440, maxHeight: 360, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    @ViewBuilder
    private func confirmationRows(for threadID: UUID) -> some View {
        let confirmations = agent.store.state.confirmations.filter {
            $0.threadID == threadID && $0.state == .pending
        }
        ForEach(confirmations) { confirmation in
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(confirmation.title).font(.system(size: 10, weight: .semibold))
                    if let detail = confirmation.detail {
                        Text(detail).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("拒绝") {
                    Task { await agent.reply(to: confirmation.id, approved: false) }
                }
                .controlSize(.mini)
                Button("确认") {
                    Task { await agent.reply(to: confirmation.id, approved: true) }
                }
                .controlSize(.mini)
            }
            .padding(6)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func composer(for threadID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !draftAttachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(draftAttachments) { attachment in
                            HStack(spacing: 3) {
                                Image(systemName: attachmentSymbol(for: attachment.kind))
                                Text(attachment.fileName).lineLimit(1)
                                Button {
                                    removeDraftAttachment(attachment)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.borderless)
                                .help("移除附件")
                            }
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                }
                .thinScrollChrome()
            }
            if !referencedThreadIDs.isEmpty || !referencedApps.isEmpty {
                HStack(spacing: 5) {
                    ForEach(referencedThreadIDs, id: \.self) { id in
                        if let thread = agent.store.state.chatThreads.first(where: { $0.id == id }) {
                            HStack(spacing: 3) {
                                Image(systemName: "at")
                                Text(thread.title).lineLimit(1)
                                Button {
                                    referencedThreadIDs.removeAll { $0 == id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.borderless)
                                .help("移除会话引用")
                            }
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                    ForEach(referencedApps) { app in
                        HStack(spacing: 3) {
                            Image(systemName: "app")
                            Text(app.name).lineLimit(1)
                            Button {
                                referencedApps.removeAll { $0.id == app.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("移除本机 App 引用")
                        }
                        .font(.system(size: 9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    Spacer(minLength: 0)
                }
            }
            if let suggestion = composerSuggestion(for: threadID) {
                composerSuggestionMenu(suggestion, in: threadID)
            }
            if let thread = agent.store.state.chatThreads.first(where: { $0.id == threadID }) {
                VStack(spacing: 0) {
                    TextField("发送消息", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(2...2)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .onPasteCommand(of: [.fileURL]) { providers in
                            importPastedAttachments(from: providers)
                        }
                        .onPasteCommand(of: [.plainText]) { providers in
                            importPastedText(from: providers)
                        }
                        .onSubmit { sendDraft(to: threadID) }
                    Divider()
                        .overlay(Color.primary.opacity(0.08))
                    ViewThatFits(in: .horizontal) {
                        composerToolbar(for: thread, threadID: threadID, isCompact: false)
                        composerToolbar(for: thread, threadID: threadID, isCompact: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .islandGlassSurface(.input, cornerRadius: 14)
                .environment(\.islandVisualStyle, .frosted)
            }
        }
    }

    private func composerToolbar(
        for thread: AgentChatThread,
        threadID: UUID,
        isCompact: Bool
    ) -> some View {
        let canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftAttachments.isEmpty
        let isGoalMode = thread.goalPrompt != nil
        return HStack(spacing: isCompact ? 6 : 8) {
            Menu {
                Button {
                    presentAttachmentPicker()
                } label: {
                    Label("添加文件", systemImage: "paperclip")
                }
                Divider()
                // 直接发送是默认行为，所以菜单里只有两个互相独立的开关。
                Toggle(isOn: Binding(
                    get: { thread.mode == .plan },
                    set: { agent.store.updateThreadMode($0 ? .plan : .standard, for: threadID) }
                )) {
                    Label("计划模式", systemImage: "list.bullet.clipboard")
                }
                Toggle(isOn: Binding(
                    get: { isGoalMode },
                    set: { agent.store.setThreadGoalMode($0, for: threadID) }
                )) {
                    Label("目标模式", systemImage: "target")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .help("添加文件、切换计划模式或目标模式")

            Menu {
                ForEach(AgentChatAccessMode.allCases, id: \.self) { mode in
                    Button {
                        agent.store.updateThreadAccessMode(mode, for: threadID)
                    } label: {
                        Label(mode.displayName, systemImage: mode.symbolName)
                    }
                }
            } label: {
                Group {
                    if isCompact {
                        Image(systemName: thread.accessMode.symbolName)
                            .frame(width: 26, height: 26)
                    } else {
                        Label(thread.accessMode.displayName, systemImage: thread.accessMode.symbolName)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(thread.accessMode == .fullAccess ? Color.orange : Color.primary)
                .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .help("设置外部 CLI 的访问偏好")

            Spacer(minLength: 0)
            modelTargetControl(for: thread, threadID: threadID, isCompact: isCompact)

            Menu {
                ForEach(AgentChatThinkingDepth.allCases, id: \.self) { depth in
                    Button(depth.displayName) {
                        agent.store.updateThreadThinkingDepth(depth, for: threadID)
                    }
                }
            } label: {
                Group {
                    if isCompact {
                        Image(systemName: "brain")
                            .frame(width: 26, height: 26)
                    } else {
                        Text(thread.thinkingDepth.displayName)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .help("选择思考深度偏好")

            Button {
                sendDraft(to: threadID)
            } label: {
                // The island forces dark mode, so `Color.primary` is white — a white arrow on it was
                // invisible. Codex style: bright pill with a dark glyph, dimmed until sendable.
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(canSend ? Color.black.opacity(0.85) : Color.white.opacity(0.45))
                    .frame(width: 30, height: 30)
                    .background(canSend ? Color.white.opacity(0.92) : Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("发送")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
    }

    private var channelContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("远端 Provider", systemImage: "cloud")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button {
                        addProvider()
                    } label: {
                        Label("添加 Provider", systemImage: "plus")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("添加远端 Provider")
                }

                ForEach(agent.store.state.channels) { channel in
                    providerCard(channel)
                }

                if agent.store.state.channels.isEmpty {
                    ContentUnavailableView("尚未配置远端 Provider", systemImage: "cloud.slash")
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
        }
        .thinScrollChrome()
    }

    private func providerCard(_ channel: AgentChannel) -> some View {
        let account = primaryAccount(for: channel)
        let primaryGroup = channel.endpointGroups.first
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Toggle("", isOn: channelEnabledBinding(channel.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                TextField("Provider 名称", text: channelNameBinding(channel.id))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Picker("", selection: channelProtocolBinding(channel.id)) {
                    ForEach(AgentChannelProtocol.allCases, id: \.self) { proto in
                        Text(proto.displayName).tag(proto)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                channelModelControl(channel)
                Spacer()
                Button {
                    Task { await agent.refreshModels(for: channel.id) }
                } label: { Image(systemName: "arrow.down.to.line") }
                    .buttonStyle(.borderless)
                    .help("获取可用模型")
                Button {
                    agent.store.removeChannel(id: channel.id)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("删除 Provider")
            }

            if let primaryGroup {
                HStack(spacing: 7) {
                    Text("端点")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    TextField("API Base URL", text: endpointGroupURLsBinding(channel.id, primaryGroup.id))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                }
            }

            if let account {
                HStack(spacing: 7) {
                    Text("凭据")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: credentialKindBinding(for: channel.id)) {
                        ForEach(AgentAccountCredentialKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    Picker("", selection: accountProbeBinding(account.id)) {
                        ForEach(AgentBalanceProbeKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    balanceText(account)
                }
                if account.credentialKind == .apiKey {
                    HStack(spacing: 7) {
                        Text("")
                            .frame(width: 60)
                        SecureField("API Key", text: accountSecretBinding(account.id))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 520)
                    }
                } else if account.credentialKind == .cliProfile {
                    cliProfileSection(account)
                }
            }

            if primaryGroup == nil || account == nil {
                providerConfigurationAction(channel)
            }

            DisclosureGroup("高级路由") {
                ForEach(channel.endpointGroups) { group in
                    endpointGroupRow(group, channelID: channel.id)
                }
                Button {
                    addGroup(to: channel.id)
                } label: {
                    Label("添加端点组", systemImage: "plus.circle")
                        .font(.system(size: 9))
                }
                .buttonStyle(.borderless)
                .help("添加额外的 URL/Key 轮换组（高级）")
            }
            .font(.system(size: 10))
        }
        .padding(9)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func providerConfigurationAction(_ channel: AgentChannel) -> some View {
        HStack(spacing: 7) {
            Label("尚未关联凭据", systemImage: "key.slash")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)
            Menu {
                ForEach(unlinkedAccounts()) { account in
                    Button(account.name) {
                        attachAccount(account.id, to: channel.id)
                    }
                }
                if !unlinkedAccounts().isEmpty {
                    Divider()
                }
                Button("新建 API Key 凭据") {
                    addCredential(to: channel.id)
                }
            } label: {
                Label("关联凭据", systemImage: "key.badge.plus")
            }
            .menuStyle(.borderlessButton)
            .help("选择已有凭据，或为此 Provider 新建 API Key 凭据")
        }
    }

    /// CLI Profile 配置区块
    private func cliProfileSection(_ account: AgentAccount) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text("")
                    .frame(width: 60)
                Picker("", selection: accountCLIKindBinding(account.id)) {
                    ForEach(AgentCLIKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                TextField("配置文件路径", text: accountConfigurationPathBinding(account.id))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 9, design: .monospaced))
                    .frame(maxWidth: 200)
                TextField("认证文件路径", text: accountAuthenticationPathBinding(account.id))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 9, design: .monospaced))
                    .frame(maxWidth: 200)
            }
            HStack(spacing: 7) {
                Text("")
                    .frame(width: 60)
                Button("导入配置") {
                    profileImportRequest = ProfileImportRequest(accountID: account.id, fileKind: .configuration)
                }
                .controlSize(.mini)
                Button("导入认证") {
                    profileImportRequest = ProfileImportRequest(accountID: account.id, fileKind: .authentication)
                }
                .controlSize(.mini)
                Text("配置 \(agent.store.hasCLIConfiguration(for: account) ? "✓" : "✗") · 认证 \(agent.store.hasCLIAuthentication(for: account) ? "✓" : "✗")")
                    .font(.system(size: 9))
                    .foregroundStyle(agent.store.hasCLIProfile(for: account) ? Color.secondary : Color.orange)
            }
        }
    }

    private func addProvider() {
        _ = agent.store.createRemoteProvider(
            name: "Provider \(agent.store.state.channels.count + 1)"
        )
    }

    private func primaryAccount(for channel: AgentChannel) -> AgentAccount? {
        for group in channel.endpointGroups {
            for accountID in group.accountIDs {
                if let account = agent.store.account(id: accountID) {
                    return account
                }
            }
        }
        return nil
    }

    private func unlinkedAccounts() -> [AgentAccount] {
        let linkedAccountIDs = Set(agent.store.state.channels.flatMap { $0.endpointGroups.flatMap(\.accountIDs) })
        return agent.store.state.accounts.filter { !linkedAccountIDs.contains($0.id) }
    }

    private func addCredential(to channelID: UUID) {
        guard let channel = agent.store.channel(id: channelID) else { return }
        let account = AgentAccount(
            name: "\(channel.name) 凭据",
            provider: channel.name,
            balanceProbe: AgentBalanceProbe()
        )
        try? agent.store.upsertAccount(account)
        attachAccount(account.id, to: channelID)
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

    private func credentialKindBinding(for channelID: UUID) -> Binding<AgentAccountCredentialKind> {
        Binding(
            get: {
                if let channel = agent.store.channel(id: channelID),
                   let account = primaryAccount(for: channel) {
                    return account.credentialKind
                }
                return .apiKey
            },
            set: { kind in
                guard let channel = agent.store.channel(id: channelID),
                      let account = primaryAccount(for: channel) else { return }
                updateAccount(account.id) { account in
                    account.credentialKind = kind
                    if kind == .cliProfile, account.cliProfile == nil {
                        account.cliProfile = AgentCLIProfile(cliKind: .codex)
                    }
                }
            }
        )
    }


    private func balanceText(_ account: AgentAccount) -> some View {
        let snapshot = account.balance
        return Text(snapshot?.available.map { String(format: "%.2f", $0) } ?? "--")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(account.isEligible() ? Color.secondary : Color.orange)
            .frame(width: 44, alignment: .trailing)
    }


    private func endpointGroupRow(_ group: AgentEndpointGroup, channelID: UUID) -> some View {
        let canRemove = (agent.store.channel(id: channelID)?.endpointGroups.count ?? 0) > 1
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Toggle("", isOn: endpointGroupEnabledBinding(channelID, group.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                TextField("端点组名称", text: endpointGroupNameBinding(channelID, group.id))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                TextField("Base URLs（逗号分隔）", text: endpointGroupURLsBinding(channelID, group.id))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                Stepper("优先级 \(group.priority)", value: endpointGroupPriorityBinding(channelID, group.id), in: -9...9)
                    .font(.system(size: 9))
                if canRemove {
                    Button {
                        removeGroup(channelID: channelID, groupID: group.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("删除端点组")
                }
            }

            HStack(spacing: 7) {
                Text("使用凭据")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                ForEach(agent.store.state.accounts) { account in
                    Toggle(account.name, isOn: endpointGroupAccountBinding(channelID, group.id, accountID: account.id))
                        .font(.system(size: 9))
                        .toggleStyle(.checkbox)
                }
            }
            .padding(.leading, 24)
        }
        .padding(.leading, 12)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var messageConnectionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("消息连接", systemImage: "bubble.left.and.bubble.right")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Menu {
                        ForEach(AgentMessageConnectionKind.allCases, id: \.self) { kind in
                            Button(kind.displayName) { addMessageConnection(kind) }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .help("添加消息连接")
                }
                ForEach(agent.store.state.messageConnections) { connection in
                    messageConnectionRow(connection)
                }
                if agent.store.state.messageConnections.isEmpty {
                    ContentUnavailableView("尚未配置消息连接", systemImage: "point.3.connected.trianglepath.dotted")
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
        }
        .thinScrollChrome()
    }

    private func messageConnectionRow(_ connection: AgentMessageConnection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Toggle("", isOn: messageConnectionEnabledBinding(connection.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                TextField("连接名称", text: messageConnectionNameBinding(connection.id))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Picker("", selection: messageConnectionKindBinding(connection.id)) {
                    ForEach(AgentMessageConnectionKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                Stepper("端口 \(connection.listenerPort)", value: messageConnectionPortBinding(connection.id), in: 1_024...65_535)
                    .font(.system(size: 9))
                Spacer()
                Button {
                    try? agent.store.removeMessageConnection(id: connection.id)
                    agent.refreshMessageConnections()
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("删除消息连接")
            }
            HStack(spacing: 7) {
                TextField("公网回调地址", text: messageConnectionCallbackBaseURLBinding(connection.id))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                Text(connection.callbackURL ?? connection.callbackPath)
                    .font(.system(size: 9, design: .monospaced))
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                Picker("", selection: messageConnectionCLIKindBinding(connection.id)) {
                    Text("自动选择 Agent").tag(Optional<AgentCLIKind>.none)
                    ForEach(AgentCLIKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(Optional(kind))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 146)
                Picker("", selection: messageConnectionAccountBinding(connection.id)) {
                    Text("自动选择登录档案").tag(Optional<UUID>.none)
                    ForEach(agent.store.state.accounts.filter { $0.credentialKind == .cliProfile }) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 210)
                Spacer()
            }
            messageConnectionCredentials(connection)
            if let error = connection.lastError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(7)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func messageConnectionCredentials(_ connection: AgentMessageConnection) -> some View {
        switch connection.kind {
        case .feishu:
            HStack(spacing: 7) {
                TextField("App ID", text: messageConnectionCredentialBinding(connection.id, \.appID))
                    .textFieldStyle(.roundedBorder)
                SecureField("App Secret", text: messageConnectionCredentialBinding(connection.id, \.appSecret))
                    .textFieldStyle(.roundedBorder)
                SecureField("Verification Token", text: messageConnectionCredentialBinding(connection.id, \.verificationToken))
                    .textFieldStyle(.roundedBorder)
            }
        case .weChatOfficial:
            HStack(spacing: 7) {
                TextField("App ID", text: messageConnectionCredentialBinding(connection.id, \.appID))
                    .textFieldStyle(.roundedBorder)
                SecureField("App Secret", text: messageConnectionCredentialBinding(connection.id, \.appSecret))
                    .textFieldStyle(.roundedBorder)
                SecureField("Token", text: messageConnectionCredentialBinding(connection.id, \.verificationToken))
                    .textFieldStyle(.roundedBorder)
            }
        case .webhook:
            HStack(spacing: 7) {
                TextField("回复 Webhook", text: messageConnectionCredentialBinding(connection.id, \.outboundURL))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                SecureField("Bearer Token", text: messageConnectionCredentialBinding(connection.id, \.verificationToken))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var localModelContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button {
                        addLocalModelConfiguration()
                    } label: {
                        Label("添加本地模型", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                    .help("添加本地模型")
                }
                ForEach(agent.store.state.localModels) { localModel in
                    localModelRow(localModel)
                }
                if agent.store.state.localModels.isEmpty {
                    ContentUnavailableView("尚未配置本地模型", systemImage: "cpu")
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(3)
        }
        .thinScrollChrome()
    }

    private func localModelRow(_ localModel: AIAgentLocalModel) -> some View {
        HStack(spacing: 7) {
            Toggle("", isOn: localModelEnabledBinding(localModel.id))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            TextField("显示名称", text: localModelNameBinding(localModel.id))
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
            Picker("", selection: localModelKindBinding(localModel.id)) {
                ForEach(AIEndpointKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            TextField("服务地址", text: localModelURLBinding(localModel.id))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
            TextField("模型 ID", text: localModelIDBinding(localModel.id))
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
            Button { agent.store.removeLocalModel(id: localModel.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("删除本地模型")
        }
        .padding(7)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var applicationEnhancementsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                applicationEnhancementRow(
                    symbol: "key",
                    title: "非接管切换时保留官方登录",
                    detail: "控制未开启路由接管时切换第三方供应商是否保留 Codex 官方登录；路由接管期间始终保留",
                    isOn: Binding(
                        get: { agent.store.state.applicationEnhancements.preservesCodexOfficialLogin },
                        set: { agent.setCodexOfficialLoginPreserved($0) }
                    )
                )
                applicationEnhancementRow(
                    symbol: "clock.arrow.circlepath",
                    title: "统一 Codex 会话历史",
                    detail: "将本机 Codex 会话导入同一历史列表；关闭时移除应用副本，原始会话不变",
                    isOn: Binding(
                        get: { agent.store.state.applicationEnhancements.unifiesCodexHistory },
                        set: { agent.setCodexHistoryUnified($0) }
                    )
                )
                if agent.store.state.applicationEnhancements.unifiesCodexHistory {
                    Text("跨供应商继续旧会话时，目标后端可能无法解密历史推理内容而导致继续失败。")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 5)
                }
                applicationEnhancementRow(
                    symbol: "rectangle.connected.to.line.below",
                    title: "应用到 Claude Code 插件",
                    detail: "VS Code Claude Code 插件跟随当前 Claude 档案的路由设置；不会写入密钥或令牌",
                    isOn: Binding(
                        get: { agent.store.state.applicationEnhancements.claudeCodeVSCodeFollowsProvider },
                        set: { agent.setClaudeCodeVSCodeFollowsProvider($0) }
                    )
                )
                applicationEnhancementRow(
                    symbol: "checkmark.seal",
                    title: "跳过 Claude Code 初次安装确认",
                    detail: "隐藏 VS Code Claude Code 插件的首次引导确认",
                    isOn: Binding(
                        get: { agent.store.state.applicationEnhancements.skipsClaudeCodeOnboarding },
                        set: { agent.setClaudeCodeOnboardingSkipped($0) }
                    )
                )
            }
            .padding(3)
        }
        .thinScrollChrome()
    }

    private func applicationEnhancementRow(
        symbol: String,
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.fillControl)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(8)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var automationContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("应用运行期间执行")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button {
                    agent.store.updateAutomation(AgentAutomation(
                        name: "余额检测",
                        task: .balanceCheck,
                        intervalMinutes: 30
                    ))
                } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("添加定时任务")
            }
            ForEach(agent.store.state.automations) { automation in
                HStack(spacing: 8) {
                    Toggle("", isOn: automationEnabledBinding(automation.id))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    TextField("名称", text: automationNameBinding(automation.id))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    Picker("", selection: automationTaskBinding(automation.id)) {
                        ForEach(AgentAutomationTask.allCases, id: \.self) { task in
                            Text(task.displayName).tag(task)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    Stepper("\(automation.intervalMinutes) 分钟", value: automationIntervalBinding(automation.id), in: 1...1_440)
                        .font(.system(size: 10))
                    Text(automation.nextRunAt?.formatted(date: .omitted, time: .shortened) ?? "待执行")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(7)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Spacer()
        }
    }

    private var toolsContent: some View {
        let installedKinds = cliKinds(installed: true)
        let missingKinds = cliKinds(installed: false)
        let installCommands = agent.commandsForCLIInstallation(missingKinds, update: false)
        let updateKinds = agent.cliUpdates.map(\.kind)
        let updateCommands = agent.commandsForCLIInstallation(updateKinds, update: true)
        let uninstallCommands = agent.commandsForCLIUninstallation(installedKinds)
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Text("CLI")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button {
                        Task { await agent.refreshCLIs() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(agent.isRunningCLICommands)
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
                    .disabled(agent.isRunningCLICommands || installCommands.isEmpty)
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
                    .disabled(agent.isRunningCLICommands || updateCommands.isEmpty)
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
                    .disabled(agent.isRunningCLICommands || uninstallCommands.isEmpty)
                    .help("一键卸载所有受支持的 CLI")
                }

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
                ForEach(AgentCLIKind.allCases, id: \.self) { kind in
                    let status = agent.store.state.cliStatuses.first { $0.kind == kind }
                    let isInstalled = status?.executablePath != nil
                    HStack(spacing: 8) {
                        Text(kind.displayName).frame(width: 80, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isInstalled ? (status?.version ?? "已安装（版本未知）") : "未安装")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(isInstalled ? .primary : .secondary)
                            if let path = status?.executablePath {
                                Text(path)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer()
                        if isInstalled {
                            let update = agent.commandsForCLIInstallation([kind], update: true)
                            let availableUpdate = agent.cliUpdates.first { $0.kind == kind }
                            if let availableUpdate {
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
                            } else if status?.version != nil {
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
                                .help("版本未知，可尝试更新 \(kind.displayName)")
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
                        } else {
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
                            .disabled(agent.isRunningCLICommands || install.isEmpty)
                            .help("下载并安装 \(kind.displayName)")
                        }
                    }
                    Divider()
                }

                SkillManagementView(agent: agent)
            }
            .padding(3)
        }
        .thinScrollChrome()
    }

    private func cliKinds(installed: Bool) -> [AgentCLIKind] {
        AgentCLIKind.allCases.filter { kind in
            let isInstalled = agent.store.state.cliStatuses.first { $0.kind == kind }?.executablePath != nil
            return isInstalled == installed
        }
    }

    private func cliActionMessage(_ action: String, kinds: [AgentCLIKind]) -> String {
        let names = kinds.map(\.displayName).joined(separator: "、")
        let grokNote = kinds.contains(.grok) && action.contains("卸载")
            ? "Grok 只会移除 CLI 可执行文件，保留账号和本地配置。"
            : "命令会在本机执行，完成后将重新检测安装状态。"
        return "\(action)：\(names)。\(grokNote)"
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
                ProgressView().controlSize(.small)
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

    private var storageContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Label("活动会话", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 11, weight: .semibold))
                let activeThreads = agent.store.activeThreads()
                ForEach(activeThreads) { thread in
                    threadStorageRow(thread) {
                        Button {
                            archiveThread(thread)
                        } label: {
                            Image(systemName: "archivebox")
                        }
                        .buttonStyle(.borderless)
                        .help("归档会话")
                        Button {
                            pendingThreadDeletion = thread
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("永久删除会话")
                    }
                }
                if activeThreads.isEmpty {
                    Text("当前没有活动会话，新建对话后会在这里列出。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Divider()
                Label("已归档会话", systemImage: "archivebox")
                    .font(.system(size: 11, weight: .semibold))
                let archivedThreads = agent.store.archivedThreads()
                ForEach(archivedThreads) { thread in
                    threadStorageRow(thread) {
                        Button {
                            agent.store.restoreThread(id: thread.id)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderless)
                        .help("恢复会话")
                        Button {
                            pendingThreadDeletion = thread
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("永久删除会话")
                    }
                }
                if archivedThreads.isEmpty {
                    Text("归档后的会话只会在设置中显示，可在此恢复或永久删除。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(3)
        }
        .thinScrollChrome()
    }

    private func threadStorageRow<Actions: View>(
        _ thread: AgentChatThread,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text(thread.title).font(.system(size: 10))
                Text("\(thread.messages.count) 条消息")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            actions()
        }
        .padding(6)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var selectedThread: AgentChatThread? {
        if let selectedThreadID,
           let thread = agent.store.state.chatThreads.first(where: { $0.id == selectedThreadID && $0.archivedAt == nil }) {
            return thread
        }
        return agent.store.activeThreads().first
    }

    /// 会话行自己承担选中态：`List(selection:)` 的系统蓝高亮无法在 macOS 上被安全改色，
    /// 改成自定义选中按钮与直接操作按钮后，可保留中性描边并提供置顶、归档入口。
    private func chatThreadRow(_ thread: AgentChatThread) -> some View {
        let isSelected = selectedThreadID == thread.id
        return HStack(spacing: 0) {
            Button {
                selectedThreadID = thread.id
                selectedProjectID = thread.projectID
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.title)
                        .lineLimit(1)
                    Text("\(thread.messages.count) 条消息")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.leading, 6)
            }
            .buttonStyle(PressableStyle(hoverScale: 1, pressedScale: 0.97))

            Button {
                agent.store.toggleThreadPinned(id: thread.id)
            } label: {
                Image(systemName: thread.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(thread.isPinned ? "取消置顶" : "置顶会话")
            .accessibilityLabel(thread.isPinned ? "取消置顶会话" : "置顶会话")

            Button {
                archiveThread(thread)
            } label: {
                Image(systemName: "archivebox")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("归档会话")
            .accessibilityLabel("归档会话")
            .padding(.trailing, 2)
        }
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.50), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .listRowInsets(EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2))
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button(thread.isPinned ? "取消置顶" : "置顶会话") {
                agent.store.toggleThreadPinned(id: thread.id)
            }
            Button("归档会话") { archiveThread(thread) }
        }
    }

    /// 归档当前选中的会话后，选中态必须跟着交给下一条活动会话，
    /// 否则 `selectedThreadID` 会指向已从列表消失的会话，行高亮与右侧记录不一致。
    private func archiveThread(_ thread: AgentChatThread) {
        agent.store.archiveThread(id: thread.id)
        if selectedThreadID == thread.id {
            selectedThreadID = agent.store.activeThreads().first?.id
        }
    }

    private func sendDraft(to threadID: UUID) {
        let command: AgentChatSlashCommand
        do {
            command = try AgentChatSlashCommandParser.parse(
                draft,
                skills: agent.store.state.skills
            )
        } catch {
            chatCommandError = error.localizedDescription
            return
        }

        let isGoalMode = agent.store.state.chatThreads
            .first { $0.id == threadID }?.goalPrompt != nil

        switch command {
        case let .setMode(mode, content):
            agent.store.updateThreadMode(mode, for: threadID)
            draft = ""
            guard !content.isEmpty else { return }
            sendAsGoalPromptIfNeeded(content, isGoalMode: isGoalMode, to: threadID)
            consumeDraftAndSend(content, to: threadID)
        case let .setGoalPrompt(content):
            agent.store.setThreadGoalMode(true, for: threadID)
            draft = ""
            guard !content.isEmpty else { return }
            agent.store.updateThreadGoalPrompt(content, for: threadID)
            consumeDraftAndSend(content, to: threadID)
        case let .message(content, skillReferences):
            guard !content.isEmpty || !draftAttachments.isEmpty else {
                chatCommandError = "请在命令后输入需要转发的消息，或添加附件。"
                return
            }
            sendAsGoalPromptIfNeeded(content, isGoalMode: isGoalMode, to: threadID)
            consumeDraftAndSend(content, skillReferences: skillReferences, to: threadID)
        }
    }

    private func sendAsGoalPromptIfNeeded(_ content: String, isGoalMode: Bool, to threadID: UUID) {
        guard isGoalMode, !content.isEmpty else { return }
        agent.store.updateThreadGoalPrompt(content, for: threadID)
    }

    private func consumeDraftAndSend(
        _ content: String,
        skillReferences: [AgentChatSkillReference] = [],
        to threadID: UUID
    ) {
        let attachments = draftAttachments
        let references = referencedThreadIDs
        let apps = referencedApps
        draft = ""
        draftAttachments = []
        referencedThreadIDs = []
        referencedApps = []
        Task {
            await agent.send(
                content,
                attachments: attachments,
                referencedThreadIDs: references,
                appReferences: apps,
                skillReferences: skillReferences,
                to: threadID
            )
        }
    }

    private func composerSuggestion(for threadID: UUID) -> ComposerSuggestion? {
        guard let token = activeComposerToken() else { return nil }
        if token.hasPrefix("@") {
            return .reference(query: String(token.dropFirst()))
        }
        let normalized = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("/"), token.hasPrefix("/") else { return nil }
        return .command(query: String(token.dropFirst()))
    }

    @ViewBuilder
    private func composerSuggestionMenu(_ suggestion: ComposerSuggestion, in threadID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch suggestion {
            case let .reference(query):
                let threads = agent.store.state.chatThreads
                    .filter { $0.id != threadID && $0.archivedAt == nil }
                    .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
                    .sorted { $0.updatedAt > $1.updatedAt }
                if !threads.isEmpty {
                    Text("会话")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.top, 3)
                    ForEach(threads) { thread in
                        Button {
                            if !referencedThreadIDs.contains(thread.id) {
                                referencedThreadIDs.append(thread.id)
                            }
                            replaceActiveComposerToken(with: "")
                        } label: {
                            composerSuggestionRow(
                                title: thread.title,
                                detail: "\(thread.messages.count) 条消息",
                                symbolName: referencedThreadIDs.contains(thread.id) ? "checkmark" : "at"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                let apps = runningApplicationReferences().filter {
                    query.isEmpty
                        || $0.name.localizedCaseInsensitiveContains(query)
                        || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
                }
                if !apps.isEmpty {
                    if !threads.isEmpty { Divider() }
                    Text("正在运行的 App")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.top, 3)
                    ForEach(apps) { app in
                        Button {
                            if !referencedApps.contains(where: { $0.id == app.id }) {
                                referencedApps.append(app)
                            }
                            replaceActiveComposerToken(with: "")
                        } label: {
                            composerSuggestionRow(
                                title: app.name,
                                detail: app.bundleIdentifier,
                                symbolName: referencedApps.contains(where: { $0.id == app.id }) ? "checkmark" : "app"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if threads.isEmpty && apps.isEmpty {
                    Text("没有匹配的会话或正在运行的 App")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(7)
                }
            case let .command(query):
                ForEach(commandSuggestions(matching: query)) { command in
                    Button {
                        replaceActiveComposerToken(with: command.insertion)
                    } label: {
                        composerSuggestionRow(
                            title: command.title,
                            detail: command.detail,
                            symbolName: command.symbolName
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
        .padding(4)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private func composerSuggestionRow(
        title: String,
        detail: String,
        symbolName: String
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func commandSuggestions(matching query: String) -> [ComposerCommandSuggestion] {
        let builtIns = [
            ComposerCommandSuggestion(
                insertion: "/plan ",
                title: "/plan",
                detail: "进入计划模式",
                symbolName: "list.bullet.clipboard"
            ),
            ComposerCommandSuggestion(
                insertion: "/goal ",
                title: "/goal",
                detail: "将输入设为当前会话目标",
                symbolName: "target"
            ),
        ]
        let skills = agent.store.state.skills
            .filter(\.isEnabled)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { skill in
                let insertion = skill.name.contains(" ") ? "/skill \(skill.name) " : "/\(skill.name) "
                return ComposerCommandSuggestion(
                    insertion: insertion,
                    title: insertion.trimmingCharacters(in: .whitespaces),
                    detail: "Skill",
                    symbolName: "puzzlepiece.extension"
                )
            }
        let candidates = builtIns + skills
        guard !query.isEmpty else { return candidates }
        return candidates.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query)
        }
    }

    private func activeComposerToken() -> String? {
        draft.split(whereSeparator: { $0.isWhitespace }).last.map(String.init)
    }

    private func replaceActiveComposerToken(with replacement: String) {
        guard let token = activeComposerToken(),
              let range = draft.range(of: token, options: .backwards) else {
            return
        }
        draft.replaceSubrange(range, with: replacement)
    }

    private func runningApplicationReferences() -> [AgentChatAppReference] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .compactMap { application in
                guard let name = application.localizedName,
                      let bundleIdentifier = application.bundleIdentifier else {
                    return nil
                }
                return AgentChatAppReference(
                    name: name,
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: Int(application.processIdentifier)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func presentAttachmentPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .audio, .data]
        panel.prompt = "添加"
        panel.begin { response in
            guard response == .OK else { return }
            importChatAttachmentURLs(panel.urls)
        }
    }

    private func importPastedAttachments(from providers: [NSItemProvider]) {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return }
        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = (item as? URL) ?? (item as? NSURL).map({ $0 as URL }) else { return }
                DispatchQueue.main.async {
                    importChatAttachmentURLs([url])
                }
            }
        }
    }

    private func importPastedText(from providers: [NSItemProvider]) {
        let textProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }
        guard !textProviders.isEmpty else { return }
        for provider in textProviders {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                guard let text = item as? String else { return }
                DispatchQueue.main.async {
                    guard text.count > 200 else {
                        draft.append(text)
                        return
                    }
                    do {
                        let attachment = try agent.store.importTextAttachment(text)
                        draftAttachments.append(attachment)
                    } catch {
                        attachmentImportError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func importChatAttachmentURLs(_ urls: [URL]) {
        do {
            draftAttachments.append(contentsOf: try agent.store.importAttachments(from: urls))
        } catch {
            attachmentImportError = error.localizedDescription
        }
    }

    private func handleDroppedItems(_ items: [TransferDropItem]) {
        let fileURLs = items.compactMap { item -> URL? in
            if case .file(let url) = item { return url }
            return nil
        }

        if !fileURLs.isEmpty {
            importChatAttachmentURLs(fileURLs)
        }

        let textItems = items.compactMap { item -> String? in
            switch item {
            case .text(let value): return value
            case .link(let url): return url.absoluteString
            case .file: return nil
            }
        }

        if !textItems.isEmpty {
            let combined = textItems.joined(separator: "\n\n")
            guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            do {
                draftAttachments.append(try agent.store.importTextAttachment(combined))
            } catch {
                attachmentImportError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func modelTargetControl(
        for thread: AgentChatThread,
        threadID: UUID,
        isCompact: Bool
    ) -> some View {
        let hasConfiguredModel = agent.store.state.localModels.contains(where: \.isEnabled)
            || agent.store.state.channels.contains(where: \.isEnabled)
        if !hasConfiguredModel {
            Text("暂未配置模型")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            Button {
                isModelPickerPresented.toggle()
            } label: {
                HStack(spacing: 4) {
                    if !isCompact {
                        Text(displayedModelName(for: thread) ?? "选择模型")
                            .foregroundStyle(displayedModelName(for: thread) == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 10, weight: .medium))
                .frame(minWidth: isCompact ? 26 : 126, maxWidth: isCompact ? 26 : 210, minHeight: 26, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .help("选择模型")
            .popover(isPresented: $isModelPickerPresented, arrowEdge: .bottom) {
                providerModelPicker(for: thread, threadID: threadID)
            }
        }
    }

    private func providerModelPicker(for thread: AgentChatThread, threadID: UUID) -> some View {
        let localModels = agent.store.state.localModels.filter(\.isEnabled)
        let providers = agent.store.state.channels.filter(\.isEnabled)
        return VStack(alignment: .leading, spacing: 9) {
            if localModels.isEmpty && providers.isEmpty {
                Text("尚未配置模型")
                    .font(.system(size: 12, weight: .semibold))
                Text("请先在模型页添加本地模型或远端 Provider。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(localModels) { localModel in
                            Button {
                                agent.store.updateThreadLocalModel(localModel.id, for: threadID)
                            } label: {
                                Text("本地 · \(localModel.name)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        localModel.id == thread.localModelID
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.fillControl
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(providers) { provider in
                            Button {
                                agent.store.updateThreadChannel(provider.id, for: threadID)
                            } label: {
                                Text(provider.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        provider.id == thread.channelID
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.fillControl
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                if let localModel = selectedLocalModel(for: thread) {
                    Text("模型 ID")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(localModel.modelName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                } else if let provider = selectedProvider(for: thread) {
                    let models = availableModels(for: thread)
                    Text("模型")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if models.isEmpty {
                        Text("该 Provider 暂无可选模型")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(models, id: \.self) { model in
                            Button {
                                agent.store.updateThreadModel(model, for: threadID)
                                isModelPickerPresented = false
                            } label: {
                                HStack(spacing: 8) {
                                    Text(model)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    if effectiveModel(for: thread) == model {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    effectiveModel(for: thread) == model
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.fillControl
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !provider.defaultModel.isEmpty {
                        Button("使用 \(provider.name) 默认模型") {
                            agent.store.updateThreadModel(nil, for: threadID)
                            isModelPickerPresented = false
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text("从上方选定一个模型。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(width: 290, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func selectedProvider(for thread: AgentChatThread) -> AgentChannel? {
        thread.channelID.flatMap { agent.store.channel(id: $0) }
    }

    private func selectedLocalModel(for thread: AgentChatThread) -> AIAgentLocalModel? {
        thread.localModelID.flatMap { agent.store.localModel(id: $0) }
    }

    private func displayedModelName(for thread: AgentChatThread) -> String? {
        if let localModel = selectedLocalModel(for: thread) {
            return "本地 · \(localModel.name)"
        }
        if let provider = selectedProvider(for: thread) {
            if let model = effectiveModel(for: thread) {
                return "\(provider.name) · \(model)"
            }
            return provider.name
        }
        return nil
    }

    private func effectiveModel(for thread: AgentChatThread) -> String? {
        if let localModel = selectedLocalModel(for: thread) {
            let model = localModel.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
            return model.isEmpty ? nil : model
        }
        if let selectedModel = thread.selectedModel, !selectedModel.isEmpty {
            return selectedModel
        }
        let defaultModel = selectedProvider(for: thread)?.defaultModel ?? ""
        return defaultModel.isEmpty ? nil : defaultModel
    }

    private func availableModels(for thread: AgentChatThread) -> [String] {
        var models: [String] = []
        if let channelID = thread.channelID,
           let channel = agent.store.channel(id: channelID),
           !channel.defaultModel.isEmpty {
            models.append(channel.defaultModel)
            models.append(contentsOf: agent.store.models(for: channelID))
        }
        if let selected = thread.selectedModel, !selected.isEmpty {
            models.append(selected)
        }
        return Array(Set(models)).sorted()
    }

    private func copyMessageContent(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    private func sendAnnotationAsMessage(selectedText: String, comment: String, to threadID: UUID) {
        let quotedText = selectedText.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n")
        let content = "\(quotedText)\n\n\(comment)"
        Task {
            await agent.send(
                content,
                attachments: [],
                referencedThreadIDs: [],
                appReferences: [],
                skillReferences: [],
                to: threadID
            )
        }
    }

    @ViewBuilder
    private func channelModelControl(_ channel: AgentChannel) -> some View {
        let discovered = agent.store.models(for: channel.id)
        let models = channel.defaultModel.isEmpty || discovered.contains(channel.defaultModel)
            ? discovered
            : [channel.defaultModel] + discovered
        if models.isEmpty {
            TextField("默认模型", text: channelModelBinding(channel.id))
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
        } else {
            Picker("", selection: channelModelBinding(channel.id)) {
                ForEach(models, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150)
        }
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
            name: "Ollama",
            baseURL: AIEndpointKind.ollama.defaultBaseURL,
            kind: .ollama
        )
        agent.store.upsertLocalModel(AIAgentLocalModel(
            name: "Ollama · qwen3:8b",
            endpoint: endpoint,
            modelName: "qwen3:8b"
        ))
    }

    private func addMessageConnection(_ kind: AgentMessageConnectionKind) {
        agent.store.upsertMessageConnection(AgentMessageConnection(
            name: "\(kind.displayName) \(agent.store.state.messageConnections.count + 1)",
            kind: kind
        ))
        agent.refreshMessageConnections()
    }

    private func updateMessageConnection(_ id: UUID, _ update: (inout AgentMessageConnection) -> Void) {
        guard var connection = agent.store.messageConnection(id: id) else { return }
        update(&connection)
        agent.store.upsertMessageConnection(connection)
        agent.refreshMessageConnections()
    }

    private func updateAutomation(_ id: UUID, _ update: (inout AgentAutomation) -> Void) {
        guard var automation = agent.store.state.automations.first(where: { $0.id == id }) else { return }
        update(&automation)
        agent.store.updateAutomation(automation)
    }

    private func updateEndpointGroup(_ channelID: UUID, _ groupID: UUID, _ update: (inout AgentEndpointGroup) -> Void) {
        updateChannel(channelID) { channel in
            guard let index = channel.endpointGroups.firstIndex(where: { $0.id == groupID }) else { return }
            update(&channel.endpointGroups[index])
        }
    }

    private func addGroup(to channelID: UUID) {
        updateChannel(channelID) { channel in
            let primaryGroup = channel.endpointGroups.first
            channel.endpointGroups.append(AgentEndpointGroup(
                name: "URL / Key 组 \(channel.endpointGroups.count + 1)",
                baseURLs: primaryGroup?.baseURLs.first.map { [$0] } ?? ["https://api.openai.com/v1"],
                accountIDs: primaryGroup?.accountIDs.first.map { [$0] } ?? []
            ))
        }
    }

    private func removeGroup(channelID: UUID, groupID: UUID) {
        updateChannel(channelID) { channel in
            guard channel.endpointGroups.count > 1 else { return }
            channel.endpointGroups.removeAll { $0.id == groupID }
        }
    }

    private func accountNameBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { agent.store.account(id: id)?.name ?? "" }, set: { value in updateAccount(id) { $0.name = value } })
    }

    private func accountProviderBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { agent.store.account(id: id)?.provider ?? "" }, set: { value in updateAccount(id) { $0.provider = value } })
    }

    private func accountEnabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { agent.store.account(id: id)?.isEnabled ?? false }, set: { value in updateAccount(id) { $0.isEnabled = value } })
    }

    private func accountCredentialBinding(_ id: UUID) -> Binding<AgentAccountCredentialKind> {
        Binding(
            get: { agent.store.account(id: id)?.credentialKind ?? .apiKey },
            set: { kind in
                updateAccount(id) { account in
                    account.credentialKind = kind
                    if kind == .cliProfile, account.cliProfile == nil {
                        account.cliProfile = AgentCLIProfile(cliKind: .codex)
                    }
                }
            }
        )
    }

    private func accountCLIKindBinding(_ id: UUID) -> Binding<AgentCLIKind> {
        Binding(
            get: { agent.store.account(id: id)?.cliProfile?.cliKind ?? .codex },
            set: { kind in
                updateAccount(id) { account in
                    account.credentialKind = .cliProfile
                    account.cliProfile = AgentCLIProfile(cliKind: kind)
                }
            }
        )
    }

    private func accountConfigurationPathBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { agent.store.account(id: id)?.cliProfile?.configurationFilePath ?? "" },
            set: { value in
                updateAccount(id) { account in
                    var profile = account.cliProfile ?? AgentCLIProfile(cliKind: .codex)
                    profile.configurationFilePath = value
                    account.cliProfile = profile
                }
            }
        )
    }

    private func accountAuthenticationPathBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { agent.store.account(id: id)?.cliProfile?.authenticationFilePath ?? "" },
            set: { value in
                updateAccount(id) { account in
                    var profile = account.cliProfile ?? AgentCLIProfile(cliKind: .codex)
                    profile.authenticationFilePath = value
                    account.cliProfile = profile
                }
            }
        )
    }

    private func accountProbeBinding(_ id: UUID) -> Binding<AgentBalanceProbeKind> {
        Binding(
            get: { agent.store.account(id: id)?.balanceProbe?.kind ?? .newAPIQuota },
            set: { kind in updateAccount(id) { $0.balanceProbe = AgentBalanceProbe(kind: kind, minimumBalance: $0.balanceProbe?.minimumBalance) } }
        )
    }

    private func accountSecretBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { "" }, set: { value in if !value.isEmpty { try? agent.store.replaceSecret(value, for: id) } })
    }

    private func messageConnectionNameBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { agent.store.messageConnection(id: id)?.name ?? "" }, set: { value in updateMessageConnection(id) { $0.name = value } })
    }

    private func messageConnectionKindBinding(_ id: UUID) -> Binding<AgentMessageConnectionKind> {
        Binding(get: { agent.store.messageConnection(id: id)?.kind ?? .feishu }, set: { value in updateMessageConnection(id) { $0.kind = value } })
    }

    private func messageConnectionEnabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { agent.store.messageConnection(id: id)?.isEnabled ?? false }, set: { value in updateMessageConnection(id) { $0.isEnabled = value } })
    }

    private func messageConnectionPortBinding(_ id: UUID) -> Binding<Int> {
        Binding(get: { agent.store.messageConnection(id: id)?.listenerPort ?? 8_787 }, set: { value in updateMessageConnection(id) { $0.listenerPort = value } })
    }

    private func messageConnectionCallbackBaseURLBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { agent.store.messageConnection(id: id)?.callbackBaseURL ?? "" }, set: { value in updateMessageConnection(id) { $0.callbackBaseURL = value } })
    }

    private func messageConnectionCLIKindBinding(_ id: UUID) -> Binding<AgentCLIKind?> {
        Binding(
            get: { agent.store.messageConnection(id: id)?.cliKind },
            set: { kind in updateMessageConnection(id) { $0.cliKind = kind } }
        )
    }

    private func messageConnectionAccountBinding(_ id: UUID) -> Binding<UUID?> {
        Binding(
            get: { agent.store.messageConnection(id: id)?.accountID },
            set: { accountID in
                let cliKind = accountID.flatMap { agent.store.account(id: $0)?.cliProfile?.cliKind }
                updateMessageConnection(id) {
                    $0.accountID = accountID
                    if let cliKind { $0.cliKind = cliKind }
                }
            }
        )
    }

    private func messageConnectionCredentialBinding(
        _ id: UUID,
        _ keyPath: WritableKeyPath<AgentMessageConnectionCredentials, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let connection = agent.store.messageConnection(id: id),
                      let credentials = try? agent.store.messageConnectionCredentials(for: connection) else {
                    return ""
                }
                return credentials[keyPath: keyPath]
            },
            set: { value in
                guard let connection = agent.store.messageConnection(id: id) else { return }
                var credentials = (try? agent.store.messageConnectionCredentials(for: connection)) ?? AgentMessageConnectionCredentials()
                credentials[keyPath: keyPath] = value
                try? agent.store.replaceMessageConnectionCredentials(credentials, for: id)
            }
        )
    }

    private func channelNameBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { agent.store.channel(id: id)?.name ?? "" }, set: { value in updateChannel(id) { $0.name = value } })
    }

    private func channelModelBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { agent.store.channel(id: id)?.defaultModel ?? "" }, set: { value in updateChannel(id) { $0.defaultModel = value } })
    }

    private func channelProtocolBinding(_ id: UUID) -> Binding<AgentChannelProtocol> {
        Binding(get: { agent.store.channel(id: id)?.protocolKind ?? .openAICompatible }, set: { value in updateChannel(id) { $0.protocolKind = value } })
    }

    private func channelEnabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { agent.store.channel(id: id)?.isEnabled ?? false }, set: { value in updateChannel(id) { $0.isEnabled = value } })
    }

    private func endpointGroupNameBinding(_ channelID: UUID, _ groupID: UUID) -> Binding<String> {
        Binding(get: { endpointGroup(channelID, groupID)?.name ?? "" }, set: { value in updateEndpointGroup(channelID, groupID) { $0.name = value } })
    }

    private func endpointGroupURLsBinding(_ channelID: UUID, _ groupID: UUID) -> Binding<String> {
        Binding(
            get: { endpointGroup(channelID, groupID)?.baseURLs.joined(separator: ", ") ?? "" },
            set: { value in updateEndpointGroup(channelID, groupID) { $0.baseURLs = AgentEndpointGroup.normalizedURLs(value.split(separator: ",").map(String.init)) } }
        )
    }

    private func endpointGroupEnabledBinding(_ channelID: UUID, _ groupID: UUID) -> Binding<Bool> {
        Binding(get: { endpointGroup(channelID, groupID)?.isEnabled ?? false }, set: { value in updateEndpointGroup(channelID, groupID) { $0.isEnabled = value } })
    }

    private func endpointGroupPriorityBinding(_ channelID: UUID, _ groupID: UUID) -> Binding<Int> {
        Binding(get: { endpointGroup(channelID, groupID)?.priority ?? 0 }, set: { value in updateEndpointGroup(channelID, groupID) { $0.priority = value } })
    }

    private func endpointGroupAccountBinding(_ channelID: UUID, _ groupID: UUID, accountID: UUID) -> Binding<Bool> {
        Binding(
            get: { endpointGroup(channelID, groupID)?.accountIDs.contains(accountID) ?? false },
            set: { enabled in
                updateEndpointGroup(channelID, groupID) { group in
                    if enabled {
                        if !group.accountIDs.contains(accountID) { group.accountIDs.append(accountID) }
                    } else {
                        group.accountIDs.removeAll { $0 == accountID }
                    }
                }
            }
        )
    }

    private func endpointGroup(_ channelID: UUID, _ groupID: UUID) -> AgentEndpointGroup? {
        agent.store.channel(id: channelID)?.endpointGroups.first { $0.id == groupID }
    }

    private func localModelNameBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { agent.store.localModel(id: id)?.name ?? "" }, set: { value in updateLocalModel(id) { $0.name = value } })
    }

    private func localModelIDBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { agent.store.localModel(id: id)?.modelName ?? "" }, set: { value in updateLocalModel(id) { $0.modelName = value } })
    }

    private func localModelURLBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { agent.store.localModel(id: id)?.endpoint.baseURL ?? "" }, set: { value in updateLocalModel(id) { $0.endpoint.baseURL = value } })
    }

    private func localModelKindBinding(_ id: UUID) -> Binding<AIEndpointKind> {
        Binding(
            get: { agent.store.localModel(id: id)?.endpoint.kind ?? .ollama },
            set: { kind in
                updateLocalModel(id) { model in
                    model.endpoint.kind = kind
                    if model.endpoint.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        model.endpoint.baseURL = kind.defaultBaseURL
                    }
                }
            }
        )
    }


    private func localModelEnabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { agent.store.localModel(id: id)?.isEnabled ?? false }, set: { value in updateLocalModel(id) { $0.isEnabled = value } })
    }

    private func automationNameBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { automation(id)?.name ?? "" }, set: { value in updateAutomation(id) { $0.name = value } })
    }

    private func automationTaskBinding(_ id: UUID) -> Binding<AgentAutomationTask> {
        Binding(get: { automation(id)?.task ?? .balanceCheck }, set: { value in updateAutomation(id) { $0.task = value } })
    }

    private func automationEnabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { automation(id)?.isEnabled ?? false }, set: { value in updateAutomation(id) { $0.isEnabled = value } })
    }

    private func automationIntervalBinding(_ id: UUID) -> Binding<Int> {
        Binding(get: { automation(id)?.intervalMinutes ?? 30 }, set: { value in updateAutomation(id) { $0.intervalMinutes = max(1, value) } })
    }

    private func automation(_ id: UUID) -> AgentAutomation? {
        agent.store.state.automations.first { $0.id == id }
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

    private func attachmentSymbol(for kind: AgentChatAttachmentKind) -> String {
        switch kind {
        case .image: "photo"
        case .audio: "speaker.wave.2"
        case .file: "doc"
        }
    }

    private func removeDraftAttachment(_ attachment: AgentChatAttachment) {
        draftAttachments.removeAll { $0.id == attachment.id }
        agent.store.discardImportedAttachments([attachment])
    }

    private func importCLIProfileFile(_ result: Result<[URL], Error>) {
        guard let request = profileImportRequest else { return }
        profileImportRequest = nil
        guard case let .success(urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url) else { return }
        agent.importCLIProfileFile(
            data,
            for: request.accountID,
            authentication: request.fileKind == .authentication
        )
    }
}
