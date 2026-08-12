import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct AIAgentStoreTests {
    @Test
    func createGoalTrimsTitleRejectsBlankAndInsertsNewestFirst() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try #require(store.createGoal(title: "  上线预览版  "))
        let second = try #require(store.createGoal(title: "整理发布说明"))

        #expect(store.createGoal(title: "   ") == nil)
        #expect(first.title == "上线预览版")
        #expect(store.state.goals.map(\.id) == [second.id, first.id])
        #expect(store.goal(id: first.id)?.status == .active)
    }

    @Test
    func updateGoalStatusOnlyTouchesMatchingGoal() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try #require(store.createGoal(title: "目标 A"))
        let other = try #require(store.createGoal(title: "目标 B"))

        store.updateGoalStatus(.completed, for: target.id)
        store.updateGoalStatus(.abandoned, for: UUID())

        #expect(store.goal(id: target.id)?.status == .completed)
        #expect(store.goal(id: other.id)?.status == .active)
        #expect(try #require(store.goal(id: target.id)).updatedAt >= target.updatedAt)
    }

    @Test
    func goalModeIsIndependentSwitchAndNeverCreatesExternalGoal() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let thread = store.createThread(title: "会话")

        // Off by default: plain send is the default behaviour, not a mode.
        #expect(store.state.chatThreads.first?.goalPrompt == nil)

        store.setThreadGoalMode(true, for: thread.id)
        #expect(store.state.chatThreads.first?.goalPrompt == "")

        store.updateThreadGoalPrompt("  完成 v0.1.1 发布  ", for: thread.id)
        #expect(store.state.chatThreads.first?.goalPrompt == "完成 v0.1.1 发布")
        #expect(store.state.goals.isEmpty)
        #expect(store.state.chatThreads.first?.goalID == nil)
        // Plan mode is a separate switch and must stay untouched.
        #expect(store.state.chatThreads.first?.mode == .standard)

        store.setThreadGoalMode(false, for: thread.id)
        #expect(store.state.chatThreads.first?.goalPrompt == nil)

        // Writes are ignored while 目标模式 is off.
        store.updateThreadGoalPrompt("不应写入", for: thread.id)
        #expect(store.state.chatThreads.first?.goalPrompt == nil)
        #expect(store.state.goals.isEmpty)
    }

    @Test
    func planModeTogglesWithoutClearingSessionGoalPrompt() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let thread = store.createThread(title: "会话")

        store.setThreadGoalMode(true, for: thread.id)
        store.updateThreadGoalPrompt("推进发布", for: thread.id)
        store.updateThreadMode(.plan, for: thread.id)

        #expect(store.state.chatThreads.first?.mode == .plan)
        #expect(store.state.chatThreads.first?.goalPrompt == "推进发布")

        store.updateThreadMode(.standard, for: thread.id)
        #expect(store.state.chatThreads.first?.goalPrompt == "推进发布")
    }

    @Test
    func updateThreadGoalIgnoresUnknownGoal() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let goal = try #require(store.createGoal(title: "目标"))
        let thread = store.createThread(title: "会话")

        store.updateThreadGoal(goal.id, for: thread.id)
        #expect(store.state.chatThreads.first?.goalID == goal.id)

        store.updateThreadGoal(UUID(), for: thread.id)
        #expect(store.state.chatThreads.first?.goalID == nil)
    }

    @Test
    func selectingThreadChannelClearsPreviousModelAndFixedProfile() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = AgentChannel(name: "OpenAI", defaultModel: "gpt-5.6")
        store.upsertChannel(provider)
        let thread = store.createThread(title: "会话")
        let fixedAccountID = UUID()
        store.updateThreadTarget(id: thread.id, cliKind: .claude, accountID: fixedAccountID)
        store.updateThreadModel("claude-opus", for: thread.id)
        let previousUpdate = try #require(store.state.chatThreads.first?.updatedAt)

        store.updateThreadChannel(provider.id, for: thread.id)

        let updatedThread = try #require(store.state.chatThreads.first)
        #expect(updatedThread.channelID == provider.id)
        #expect(updatedThread.cliKind == nil)
        #expect(updatedThread.accountID == nil)
        #expect(updatedThread.selectedModel == nil)
        #expect(updatedThread.updatedAt >= previousUpdate)

        store.updateThreadModel("gpt-5.6", for: thread.id)
        store.updateThreadChannel(provider.id, for: thread.id)
        #expect(store.state.chatThreads.first?.selectedModel == "gpt-5.6")
    }

    @Test
    func selectingLocalModelClearsRemoteTargetAndRemovingItClearsTheReference() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localModel = AIAgentLocalModel(
            name: "本地 Qwen",
            endpoint: AIEndpoint(
                name: "Ollama",
                baseURL: "http://127.0.0.1:11434/v1",
                kind: .ollama
            ),
            modelName: "qwen3:8b"
        )
        let channel = AgentChannel(name: "OpenAI", defaultModel: "gpt-5.6")
        let thread = store.createThread(channelID: channel.id, title: "会话")
        store.upsertLocalModel(localModel)
        store.upsertChannel(channel)
        store.updateThreadTarget(id: thread.id, cliKind: .codex, accountID: UUID())
        store.updateThreadModel("gpt-5.6", for: thread.id)

        store.updateThreadLocalModel(localModel.id, for: thread.id)

        let selectedThread = try #require(store.state.chatThreads.first)
        #expect(selectedThread.localModelID == localModel.id)
        #expect(selectedThread.channelID == nil)
        #expect(selectedThread.cliKind == nil)
        #expect(selectedThread.accountID == nil)
        #expect(selectedThread.selectedModel == nil)

        store.removeLocalModel(id: localModel.id)
        #expect(store.state.chatThreads.first?.localModelID == nil)
    }

    @Test
    func newThreadUsesTheMostRecentlyUsedEnabledModel() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let channel = AgentChannel(name: "OpenAI", defaultModel: "gpt-5.6")
        store.upsertChannel(channel)
        let previousThread = store.createThread(title: "已选模型")
        store.updateThreadChannel(channel.id, for: previousThread.id)
        store.updateThreadModel("gpt-5.6-mini", for: previousThread.id)

        let thread = store.createThread(useMostRecentModel: true, title: "新对话")

        #expect(thread.channelID == channel.id)
        #expect(thread.localModelID == nil)
        #expect(thread.selectedModel == "gpt-5.6-mini")
    }

    @Test
    func newThreadWithoutModelHistoryKeepsModelUnselected() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.upsertChannel(AgentChannel(name: "OpenAI", defaultModel: "gpt-5.6"))

        let thread = store.createThread(useMostRecentModel: true, title: "首次对话")

        #expect(thread.channelID == nil)
        #expect(thread.localModelID == nil)
        #expect(thread.selectedModel == nil)
    }

    @Test
    func remoteChannelConfigurationSurvivesReload() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = AgentAccount(
            name: "生产 OpenAI",
            provider: "OpenAI"
        )
        let channel = AgentChannel(
            name: "生产 OpenAI",
            defaultModel: "gpt-4.1-mini",
            endpointGroups: [AgentEndpointGroup(
                name: "主端点",
                baseURLs: ["https://api.example.com/v1"],
                accountIDs: [account.id]
            )]
        )

        try store.upsertAccount(account, secret: "sk-test")
        store.upsertChannel(channel)
        store.flushPendingChanges()

        let restored = AIAgentStore(
            storageURL: directory.appendingPathComponent("state.json"),
            secretStore: StubSecretStore()
        )
        #expect(restored.account(id: account.id) == account)
        #expect(restored.channel(id: channel.id) == channel)
    }

    @Test
    func creatingRemoteProviderCreatesAnAccountAndDefaultEndpointTogether() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let provider = store.createRemoteProvider(
            name: "测试 Provider",
            defaultModel: "gpt-test",
            baseURL: "https://api.example.com/v1"
        )

        let group = try #require(provider.endpointGroups.first)
        let accountID = try #require(group.accountIDs.first)
        let account = try #require(store.account(id: accountID))

        #expect(store.state.channels == [provider])
        #expect(store.state.accounts == [account])
        #expect(provider.name == "测试 Provider")
        #expect(provider.defaultModel == "gpt-test")
        #expect(group.baseURLs == ["https://api.example.com/v1"])
        #expect(account.name == provider.name)
        #expect(account.provider == provider.name)
    }

    @Test
    func deletingProjectKeepsItsConversationsUngrouped() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = try #require(store.createProject(name: "发布", instructions: "保持兼容性"))
        let thread = store.createThread(projectID: project.id, title: "发布准备")

        store.updateProjectInstructions("先验证升级路径", for: project.id)
        store.deleteProject(id: project.id)

        #expect(store.project(id: project.id) == nil)
        #expect(store.state.chatThreads.first { $0.id == thread.id }?.projectID == nil)
    }

    @Test
    func projectDirectoryPinAndCollapsedStatePersistAndSortForTheSidebar() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try #require(store.createProject(name: "文档", directoryPath: "/tmp/docs"))
        let second = try #require(store.createProject(name: "应用", directoryPath: "/tmp/app"))

        store.toggleProjectPinned(id: first.id)
        store.setProjectCollapsed(true, for: first.id)
        store.flushPendingChanges()

        #expect(store.sortedProjects().map(\.id) == [first.id, second.id])
        #expect(store.project(id: first.id)?.directoryPath == "/tmp/docs")
        #expect(store.project(id: first.id)?.isPinned == true)
        #expect(store.project(id: first.id)?.isCollapsed == true)

        let reloaded = AIAgentStore(
            storageURL: directory.appendingPathComponent("state.json"),
            secretStore: StubSecretStore()
        )
        #expect(reloaded.sortedProjects().map(\.id) == [first.id, second.id])
        #expect(reloaded.project(id: first.id)?.directoryPath == "/tmp/docs")
        #expect(reloaded.project(id: first.id)?.isPinned == true)
        #expect(reloaded.project(id: first.id)?.isCollapsed == true)
    }

    @Test
    func forkCopiesHistoryAndAnnotationsRemainAttachedToTheOriginalThread() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let thread = store.createThread(title: "原会话")
        let first = AgentChatMessage(role: .user, content: "需求")
        let reply = AgentChatMessage(role: .assistant, content: "回复")
        store.append(first, to: thread.id)
        store.append(reply, to: thread.id)
        _ = store.addAnnotation(
            threadID: thread.id,
            messageID: reply.id,
            selectedText: "回复",
            comment: "需要补充"
        )

        let fork = try #require(store.forkThread(at: reply.id, in: thread.id))

        #expect(fork.messages.map(\.content) == ["需求", "回复"])
        #expect(fork.messages.map(\.id) != [first.id, reply.id])
        #expect(store.annotations(for: reply.id).count == 1)
        #expect(store.annotations(for: fork.messages[1].id).isEmpty)
    }

    @Test
    func forkPreservesContextReferencesAndAppReferences() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let refThread = store.createThread(title: "引用会话")
        store.append(AgentChatMessage(role: .user, content: "上下文"), to: refThread.id)
        let thread = store.createThread(title: "主会话")
        let contextRef = AgentChatContextReference(
            threadID: refThread.id,
            title: "引用会话",
            messages: [AgentChatContextMessage(role: .user, content: "上下文")]
        )
        let appRef = AgentChatAppReference(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", processIdentifier: 1234)
        let message = AgentChatMessage(
            role: .user,
            content: "带引用的消息",
            contextReferences: [contextRef],
            appReferences: [appRef]
        )
        store.append(message, to: thread.id)

        let fork = try #require(store.forkThread(at: message.id, in: thread.id))

        #expect(fork.messages.count == 1)
        let forkedMessage = fork.messages[0]
        #expect(forkedMessage.contextReferences.count == 1)
        #expect(forkedMessage.contextReferences[0].threadID == refThread.id)
        #expect(forkedMessage.appReferences.count == 1)
        #expect(forkedMessage.appReferences[0].bundleIdentifier == "com.apple.dt.Xcode")
    }

    @Test
    func archiveAndRestoreThreadTogglesArchivedAtOnly() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let thread = store.createThread(title: "会话")
        let kept = store.createThread(title: "另一个会话")

        store.archiveThread(id: thread.id)
        let archivedAt = try #require(store.state.chatThreads.first { $0.id == thread.id }?.archivedAt)
        #expect(store.state.chatThreads.first { $0.id == kept.id }?.archivedAt == nil)
        #expect(store.state.chatThreads.count == 2)

        store.restoreThread(id: thread.id)
        #expect(store.state.chatThreads.first { $0.id == thread.id }?.archivedAt == nil)
        #expect(try #require(store.state.chatThreads.first { $0.id == thread.id }).updatedAt >= archivedAt)
    }

    @Test
    func archivedThreadSurvivesReload() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let thread = store.createThread(title: "会话")
        store.archiveThread(id: thread.id)
        store.flushPendingChanges()

        let reloaded = AIAgentStore(
            storageURL: directory.appendingPathComponent("state.json"),
            secretStore: StubSecretStore()
        )

        #expect(reloaded.state.chatThreads.first { $0.id == thread.id }?.archivedAt != nil)
    }

    @Test
    func deleteThreadCascadesConfirmationsAndConversations() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let thread = store.createThread(title: "会话")
        let kept = store.createThread(title: "保留")
        let connectionID = UUID()
        store.addConfirmation(AgentConfirmation(threadID: thread.id, title: "确认"))
        store.addConfirmation(AgentConfirmation(threadID: kept.id, title: "保留确认"))
        store.upsertMessageConversation(AgentMessageConversation(
            connectionID: connectionID,
            externalConversationID: "oc_chat",
            threadID: thread.id
        ))

        store.deleteThread(id: thread.id)

        #expect(store.state.chatThreads.map(\.id) == [kept.id])
        #expect(store.state.confirmations.map(\.threadID) == [kept.id])
        #expect(store.state.messageConversations.isEmpty)
    }

    @Test
    func contextSnapshotSkipsCurrentThreadDuplicatesAndEmptyHistory() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = store.createThread(title: "当前会话")
        let referenced = store.createThread(title: "被引用会话")
        let empty = store.createThread(title: "空会话")
        store.append(AgentChatMessage(role: .user, content: "问题"), to: referenced.id)
        store.append(AgentChatMessage(role: .assistant, content: "回答"), to: referenced.id)
        store.append(AgentChatMessage(role: .user, content: "   "), to: empty.id)

        let references = store.contextReferences(
            for: [current.id, referenced.id, referenced.id, empty.id, UUID()],
            excluding: current.id
        )

        #expect(references.map(\.threadID) == [referenced.id])
        #expect(references.first?.messages.map(\.content) == ["问题", "回答"])
    }

    @Test
    func contextSnapshotKeepsLastTwelveMessagesAndClipsContent() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = store.createThread(title: "当前会话")
        let referenced = store.createThread(title: "长会话")
        for index in 0..<15 {
            store.append(AgentChatMessage(role: .user, content: "消息-\(index)"), to: referenced.id)
        }
        store.append(
            AgentChatMessage(role: .assistant, content: String(repeating: "长", count: 1_500)),
            to: referenced.id
        )

        let reference = try #require(
            store.contextReferences(for: [referenced.id], excluding: current.id).first
        )

        #expect(reference.messages.count == 12)
        #expect(reference.messages.first?.content == "消息-4")
        #expect(reference.messages.last?.content.count == 1_200)
    }

    @Test
    func attachmentURLRejectsEscapingAbsoluteAndDeletedPaths() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        for path in ["../../etc/passwd", "/etc/passwd", "active/../../escape.png", "   ", ""] {
            let attachment = AgentChatAttachment(
                fileName: "shot.png",
                mimeType: "image/png",
                byteCount: 8,
                storagePath: path,
                kind: .image
            )
            #expect(store.attachmentURL(for: attachment) == nil, "路径应被拒绝：\(path)")
        }

        let deleted = AgentChatAttachment(
            fileName: "shot.png",
            mimeType: "image/png",
            byteCount: 8,
            storagePath: "active/shot.png",
            kind: .image,
            state: .deleted
        )
        #expect(store.attachmentURL(for: deleted) == nil)
    }

    @Test
    func importingTextAttachmentCreatesPrivateFileWithoutCreatingChatHistory() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let attachment = try store.importTextAttachment("整理发布说明", fileName: "随记.txt")
        defer { store.discardImportedAttachments([attachment]) }

        #expect(attachment.fileName == "随记.txt")
        #expect(attachment.mimeType == "text/plain")
        #expect(attachment.kind == .file)
        #expect(store.state.chatThreads.isEmpty)
        let url = try #require(store.attachmentURL(for: attachment))
        #expect(try String(contentsOf: url, encoding: .utf8) == "整理发布说明")
    }

    @Test
    func activeAndArchivedThreadQueriesPartitionHistoryNewestFirst() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldest = store.createThread(title: "最早")
        let middle = store.createThread(title: "中间")
        let newest = store.createThread(title: "最新")
        // createThread stamps every thread at "now"; append re-stamps updatedAt from the message so
        // the recency order under test cannot depend on wall-clock ties.
        store.append(AgentChatMessage(role: .user, content: "1", createdAt: Date(timeIntervalSince1970: 100)), to: oldest.id)
        store.append(AgentChatMessage(role: .user, content: "2", createdAt: Date(timeIntervalSince1970: 200)), to: middle.id)
        store.append(AgentChatMessage(role: .user, content: "3", createdAt: Date(timeIntervalSince1970: 300)), to: newest.id)

        #expect(store.activeThreads().map(\.id) == [newest.id, middle.id, oldest.id])
        #expect(store.archivedThreads().isEmpty)

        store.archiveThread(id: newest.id)

        // Archiving pulls the thread out of the chat list and into the settings list, and the chat
        // view's selection fallback takes the next most recent active thread.
        #expect(store.activeThreads().map(\.id) == [middle.id, oldest.id])
        #expect(store.activeThreads().first?.id == middle.id)
        #expect(store.archivedThreads().map(\.id) == [newest.id])

        store.restoreThread(id: newest.id)

        #expect(store.archivedThreads().isEmpty)
        #expect(store.activeThreads().first?.id == newest.id)
    }

    @Test
    func pinnedThreadSurvivesReloadAndSortsBeforeNewerHistory() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pinned = store.createThread(title: "置顶")
        let recent = store.createThread(title: "最新")
        store.append(AgentChatMessage(role: .user, content: "旧", createdAt: Date(timeIntervalSince1970: 100)), to: pinned.id)
        store.append(AgentChatMessage(role: .user, content: "新", createdAt: Date(timeIntervalSince1970: 200)), to: recent.id)

        store.toggleThreadPinned(id: pinned.id)
        store.flushPendingChanges()

        #expect(store.activeThreads().map(\.id) == [pinned.id, recent.id])
        let reloaded = AIAgentStore(
            storageURL: directory.appendingPathComponent("state.json"),
            secretStore: StubSecretStore()
        )
        #expect(reloaded.state.chatThreads.first { $0.id == pinned.id }?.isPinned == true)
        #expect(reloaded.activeThreads().first?.id == pinned.id)

        store.toggleThreadPinned(id: pinned.id)

        #expect(store.activeThreads().map(\.id) == [recent.id, pinned.id])
    }

    @Test
    func persistenceCoalescesRapidChangesAndWritesTheLatestSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-persistence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writes = PersistenceWriteCounter()
        let storageURL = directory.appendingPathComponent("state.json")
        let store = AIAgentStore(
            storageURL: storageURL,
            secretStore: StubSecretStore(),
            persistenceDelay: 0.05,
            persistenceWriter: { state, url in
                try AIAgentStore.write(state, to: url)
                writes.record(state)
            }
        )

        _ = store.createGoal(title: "第一个")
        _ = store.createGoal(title: "第二个")
        _ = store.createGoal(title: "最终目标")

        for _ in 0..<50 where writes.count == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(writes.count == 1)
        #expect(writes.lastState?.goals.first?.title == "最终目标")
        let persisted = try JSONDecoder().decode(AIAgentState.self, from: Data(contentsOf: storageURL))
        #expect(persisted.goals.first?.title == "最终目标")
        #expect(store.persistenceError == nil)
    }

    @Test
    func persistenceFailureIsObservable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-persistence-error-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let parentFile = directory.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: parentFile)
        let store = AIAgentStore(
            storageURL: parentFile.appendingPathComponent("state.json"),
            secretStore: StubSecretStore()
        )

        _ = store.createGoal(title: "无法落盘")
        store.flushPendingChanges()

        #expect(store.persistenceError != nil)
    }

    @Test
    func deletingAnActiveThreadFromSettingsRemovesItFromBothQueries() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = store.createThread(title: "待删除")
        let kept = store.createThread(title: "保留")

        // The settings page deletes without archiving first, so an active thread must be removable
        // straight out of activeThreads().
        store.deleteThread(id: target.id)

        #expect(store.activeThreads().map(\.id) == [kept.id])
        #expect(store.archivedThreads().isEmpty)
    }

    @Test
    func deletingAnArchivedThreadLeavesActiveHistoryUntouched() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archived = store.createThread(title: "已归档")
        let kept = store.createThread(title: "活动")
        store.archiveThread(id: archived.id)

        store.deleteThread(id: archived.id)

        #expect(store.archivedThreads().isEmpty)
        #expect(store.activeThreads().map(\.id) == [kept.id])
    }

    private func makeStore() -> (AIAgentStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-store-\(UUID().uuidString)", isDirectory: true)
        let store = AIAgentStore(
            storageURL: directory.appendingPathComponent("state.json"),
            secretStore: StubSecretStore()
        )
        return (store, directory)
    }

    /// Only builds state; writes no attachment files into the user's application data directory. The random file name guarantees the path does not exist in the real directory.
    private func makeAttachment(
        fileName: String,
        kind: AgentChatAttachmentKind,
        state: AgentChatAttachmentState = .active
    ) -> AgentChatAttachment {
        let folder = state == .archived ? "archive" : "active"
        return AgentChatAttachment(
            fileName: fileName,
            mimeType: kind == .image ? "image/png" : "audio/mp4",
            byteCount: 16,
            storagePath: state == .deleted ? "" : "\(folder)/\(UUID().uuidString.lowercased())-\(fileName)",
            kind: kind,
            state: state
        )
    }

    private func makeThread(title: String, attachments: [AgentChatAttachment]) -> AgentChatThread {
        AgentChatThread(
            title: title,
            messages: [AgentChatMessage(role: .user, content: "看图", attachments: attachments)]
        )
    }

    private func storedAttachment(in store: AIAgentStore, id: UUID) -> AgentChatAttachment? {
        store.state.chatThreads
            .flatMap(\.messages)
            .flatMap(\.attachments)
            .first { $0.id == id }
    }
}

private struct StubSecretStore: AIAgentSecretStoring {
    func secret(for reference: String) throws -> String? { nil }
    func setSecret(_ secret: String, for reference: String) throws {}
    func removeSecret(for reference: String) throws {}
}

private final class PersistenceWriteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [AIAgentState] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return states.count
    }

    var lastState: AIAgentState? {
        lock.lock()
        defer { lock.unlock() }
        return states.last
    }

    func record(_ state: AIAgentState) {
        lock.lock()
        defer { lock.unlock() }
        states.append(state)
    }
}
