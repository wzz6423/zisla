import Foundation
import Testing
@testable import ZislaCore

struct AIAgentModelsTests {
    @Test
    func skillSyncConfigurationDefaultsWhenLoadingExistingState() throws {
        let state = try JSONDecoder().decode(AIAgentState.self, from: Data("{}".utf8))

        #expect(state.skillSyncConfiguration == AgentSkillSyncConfiguration())
        #expect(state.skillSyncConfiguration.mode == .symbolicLink)
        #expect(state.skillSyncConfiguration.enabledDestinations.isEmpty)
        #expect(!state.cliAutoUpdateEnabled)
    }

    @Test
    func cliAutoUpdateSettingDefaultsOffForLegacyStateAndRoundTrips() throws {
        let legacy = try JSONDecoder().decode(
            AIAgentState.self,
            from: Data(#"{"accounts":[],"channels":[],"cliStatuses":[]}"#.utf8)
        )
        let enabled = AIAgentState(cliAutoUpdateEnabled: true)
        let roundTripped = try JSONDecoder().decode(
            AIAgentState.self,
            from: JSONEncoder().encode(enabled)
        )

        #expect(!legacy.cliAutoUpdateEnabled)
        #expect(roundTripped.cliAutoUpdateEnabled)
    }

    @Test
    func routeRouterRotatesURLAndKeyPairsAndSkipsInsufficientBalance() {
        let lowBalance = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "余额不足",
            provider: "OpenAI",
            balanceProbe: AgentBalanceProbe(minimumBalance: 5),
            balance: AgentBalanceSnapshot(available: 1)
        )
        let first = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "账号一",
            provider: "OpenAI"
        )
        let second = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "账号二",
            provider: "OpenAI"
        )
        let group = AgentEndpointGroup(
            name: "主组",
            baseURLs: ["https://one.example/v1", "https://two.example/v1"],
            accountIDs: [lowBalance.id, first.id, second.id],
            priority: 10
        )
        let channel = AgentChannel(
            name: "主渠道",
            defaultModel: "gpt-test",
            endpointGroups: [group]
        )
        var router = AgentRouteRouter()

        guard let route1 = router.nextRoute(for: channel, accounts: [lowBalance, first, second]),
              let route2 = router.nextRoute(for: channel, accounts: [lowBalance, first, second]),
              let route3 = router.nextRoute(for: channel, accounts: [lowBalance, first, second]) else {
            Issue.record("路由器应返回可用 URL / Key 组合")
            return
        }

        #expect(route1.baseURL == "https://one.example/v1")
        #expect(route1.accountID == first.id)
        #expect(route2.baseURL == "https://one.example/v1")
        #expect(route2.accountID == second.id)
        #expect(route3.baseURL == "https://two.example/v1")
        #expect(route3.accountID == first.id)
    }

    @Test
    func routerFallsBackToLowerPriorityGroupWhenPrimaryAccountsAreUnavailable() {
        let unavailable = AgentAccount(
            name: "主账号",
            provider: "OpenAI",
            balanceProbe: AgentBalanceProbe(minimumBalance: 1),
            balance: AgentBalanceSnapshot(available: 0)
        )
        let backup = AgentAccount(name: "备用账号", provider: "OpenAI")
        let primary = AgentEndpointGroup(
            name: "主",
            baseURLs: ["https://primary.example/v1"],
            accountIDs: [unavailable.id],
            priority: 10
        )
        let secondary = AgentEndpointGroup(
            name: "备",
            baseURLs: ["https://backup.example/v1"],
            accountIDs: [backup.id],
            priority: 0
        )
        let channel = AgentChannel(
            name: "渠道",
            defaultModel: "model",
            endpointGroups: [primary, secondary]
        )
        var router = AgentRouteRouter()

        guard let route = router.nextRoute(for: channel, accounts: [unavailable, backup]) else {
            Issue.record("路由器应回退到低优先级渠道")
            return
        }
        #expect(route.endpointGroupID == secondary.id)
        #expect(route.accountID == backup.id)
    }

    @Test
    func routerProvidesAllCombinationsAndIsolatesFailuresByURL() throws {
        let first = AgentAccount(name: "账号一", provider: "OpenAI")
        let second = AgentAccount(name: "账号二", provider: "OpenAI")
        let group = AgentEndpointGroup(
            name: "主组",
            baseURLs: ["https://one.example/v1", "https://two.example/v1"],
            accountIDs: [first.id, second.id]
        )
        let channel = AgentChannel(
            name: "渠道",
            defaultModel: "model",
            endpointGroups: [group]
        )
        let now = Date(timeIntervalSinceReferenceDate: 700_000_000)
        var router = AgentRouteRouter()

        let initial = router.routes(for: channel, accounts: [first, second], at: now)

        #expect(initial.count == 4)
        let failed = try #require(initial.first { $0.baseURL == "https://one.example/v1" })
        router.recordFailure(for: failed, at: now)
        router.recordFailure(for: failed, at: now)

        let remaining = router.routes(
            for: channel,
            accounts: [first, second],
            at: now.addingTimeInterval(1)
        )
        #expect(remaining.count == 2)
        #expect(remaining.allSatisfy { $0.baseURL == "https://two.example/v1" })
        #expect(Set(remaining.map(\.accountID)) == Set([first.id, second.id]))

        let recovered = router.routes(
            for: channel,
            accounts: [first, second],
            at: now.addingTimeInterval(301)
        )
        #expect(recovered.count == 4)
    }

    @Test
    func legacyAgentStateWithoutLocalModelsRemainsReadable() throws {
        let data = Data(#"{"accounts":[],"channels":[]}"#.utf8)
        let state = try JSONDecoder().decode(AIAgentState.self, from: data)

        #expect(state.localModels.isEmpty)
        #expect(state.chatThreads.isEmpty)
        #expect(state.automations.isEmpty)
    }

    @Test
    func legacyChatHistoryUsesDefaultsForPlanAndAttachmentFields() throws {
        let threadID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let messageID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let data = Data("""
        {
          "accounts": [],
          "channels": [],
          "chatThreads": [{
            "id": "\(threadID.uuidString)",
            "title": "旧会话",
            "messages": [{
              "id": "\(messageID.uuidString)",
              "role": "user",
              "content": "历史消息"
            }]
          }]
        }
        """.utf8)

        let state = try JSONDecoder().decode(AIAgentState.self, from: data)
        let thread = try #require(state.chatThreads.first)
        let message = try #require(thread.messages.first)

        #expect(state.goals.isEmpty)
        #expect(state.projects.isEmpty)
        #expect(state.annotations.isEmpty)
        #expect(thread.mode == .standard)
        #expect(thread.goalID == nil)
        #expect(thread.goalPrompt == nil)
        #expect(thread.projectID == nil)
        #expect(thread.accessMode == .autoReview)
        #expect(thread.selectedModel == nil)
        #expect(thread.thinkingDepth == .high)
        #expect(thread.isPinned == false)
        #expect(thread.archivedAt == nil)
        #expect(message.attachments.isEmpty)
        #expect(message.contextReferences.isEmpty)
        #expect(message.appReferences.isEmpty)
        #expect(message.skillReferences.isEmpty)
        #expect(message.mode == .standard)
        #expect(message.goalTitle == nil)
    }

    @Test
    func legacyProjectDefaultsToAnUnpinnedExpandedProjectWithoutDirectory() throws {
        let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000030")!
        let data = Data("""
        {
          "id": "\(projectID.uuidString)",
          "name": "旧项目",
          "instructions": "沿用原有上下文"
        }
        """.utf8)

        let project = try JSONDecoder().decode(AgentChatProject.self, from: data)

        #expect(project.directoryPath.isEmpty)
        #expect(project.isPinned == false)
        #expect(project.isCollapsed == false)
    }

    @Test
    func threadGoalPromptRoundTripsIndependentlyFromPlanMode() throws {
        let thread = AgentChatThread(title: "会话", mode: .standard, goalPrompt: "完成 v0.1.1 发布")
        let decoded = try JSONDecoder().decode(
            AgentChatThread.self,
            from: JSONEncoder().encode(thread)
        )

        #expect(decoded.goalPrompt == "完成 v0.1.1 发布")
        #expect(decoded.mode == .standard)
        #expect(decoded.goalID == nil)
    }

    @Test
    func planConversationAttachmentsAndContextReferencesRoundTrip() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let archivedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let goal = AgentGoal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            title: "整理发布计划",
            status: .active,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let project = AgentChatProject(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000026")!,
            name: "发布项目",
            instructions: "保持兼容性",
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let attachment = AgentChatAttachment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            fileName: "草图.png",
            mimeType: "image/png",
            byteCount: 1_024,
            storagePath: "00000000-0000-0000-0000-000000000022.png",
            kind: .image,
            state: .archived,
            createdAt: createdAt
        )
        let reference = AgentChatContextReference(
            threadID: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
            title: "需求讨论",
            messages: [AgentChatContextMessage(role: .user, content: "沿用上次的发布范围")]
        )
        let skill = AgentChatSkillReference(name: "release-plan", path: "/tmp/release-plan/SKILL.md")
        let app = AgentChatAppReference(
            name: "Codex",
            bundleIdentifier: "com.openai.codex",
            processIdentifier: 42
        )
        let message = AgentChatMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000024")!,
            role: .user,
            content: "请根据目标继续",
            attachments: [attachment],
            contextReferences: [reference],
            appReferences: [app],
            skillReferences: [skill],
            mode: .plan,
            goalTitle: goal.title,
            createdAt: createdAt
        )
        let thread = AgentChatThread(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000025")!,
            title: "发布准备",
            mode: .plan,
            goalID: goal.id,
            projectID: project.id,
            accessMode: .fullAccess,
            selectedModel: "gpt-5.6",
            thinkingDepth: .extraHigh,
            isPinned: true,
            archivedAt: archivedAt,
            messages: [message],
            createdAt: createdAt,
            updatedAt: archivedAt
        )
        let annotation = AgentChatAnnotation(
            threadID: thread.id,
            messageID: message.id,
            selectedText: "根据目标",
            comment: "补充验证步骤",
            createdAt: createdAt
        )
        let state = AIAgentState(
            goals: [goal],
            projects: [project],
            chatThreads: [thread],
            annotations: [annotation]
        )

        let decoded = try JSONDecoder().decode(AIAgentState.self, from: JSONEncoder().encode(state))

        #expect(decoded == state)
    }

    @Test
    func slashCommandsSelectEnabledSkillsAndConversationModes() throws {
        let skill = AgentSkill(name: "release-plan", path: "/skills/release-plan", source: "用户")
        let review = AgentSkill(name: "code-review", path: "/skills/code-review", source: "用户")
        let spacedReview = AgentSkill(name: "code review", path: "/skills/code-review-spaced", source: "用户")

        #expect(
            try AgentChatSlashCommandParser.parse("/plan 拆分里程碑", skills: [skill, review, spacedReview])
                == .setMode(.plan, content: "拆分里程碑")
        )
        #expect(
            try AgentChatSlashCommandParser.parse("继续讨论", skills: [skill, review, spacedReview])
                == .message(content: "继续讨论", skillReferences: [])
        )
        #expect(
            try AgentChatSlashCommandParser.parse("/goal 完成发布", skills: [skill, review, spacedReview])
                == .setGoalPrompt(content: "完成发布")
        )
        #expect(
            try AgentChatSlashCommandParser.parse("/release-plan 检查风险", skills: [skill, review, spacedReview])
                == .message(
                    content: "检查风险",
                    skillReferences: [AgentChatSkillReference(name: "release-plan", path: "/skills/release-plan")]
                )
        )
        #expect(
            try AgentChatSlashCommandParser.parse("/skill code review 生成计划", skills: [skill, review, spacedReview])
                == .message(
                    content: "生成计划",
                    skillReferences: [AgentChatSkillReference(name: "code review", path: "/skills/code-review-spaced")]
                )
        )
        #expect(
            try AgentChatSlashCommandParser.parse("/release-plan /code-review 检查风险", skills: [skill, review, spacedReview])
                == .message(
                    content: "检查风险",
                    skillReferences: [
                        AgentChatSkillReference(name: "release-plan", path: "/skills/release-plan"),
                        AgentChatSkillReference(name: "code-review", path: "/skills/code-review"),
                    ]
                )
        )
        #expect(
            try AgentChatSlashCommandParser.parse("/skill code review /release-plan 检查风险", skills: [skill, review, spacedReview])
                == .message(
                    content: "检查风险",
                    skillReferences: [
                        AgentChatSkillReference(name: "code review", path: "/skills/code-review-spaced"),
                        AgentChatSkillReference(name: "release-plan", path: "/skills/release-plan"),
                    ]
                )
        )
        #expect(
            try AgentChatSlashCommandParser.parse("/release-plan /skill code review /release-plan 检查风险", skills: [skill, review, spacedReview])
                == .message(
                    content: "检查风险",
                    skillReferences: [
                        AgentChatSkillReference(name: "release-plan", path: "/skills/release-plan"),
                        AgentChatSkillReference(name: "code review", path: "/skills/code-review-spaced"),
                    ]
                )
        )
        #expect(
            try AgentChatSlashCommandParser.parse("/Users/wzz/notes.txt", skills: [skill, review, spacedReview])
                == .message(content: "/Users/wzz/notes.txt", skillReferences: [])
        )
    }

    @Test
    func slashCommandsRejectUnavailableSkillsAndAllowEmptyGoalMode() throws {
        let disabled = AgentSkill(name: "disabled", path: "/skills/disabled", source: "用户", isEnabled: false)

        #expect(throws: AgentChatSlashCommandError.unavailableSkill("disabled")) {
            try AgentChatSlashCommandParser.parse("/disabled 运行", skills: [disabled])
        }
        #expect(try AgentChatSlashCommandParser.parse("/goal", skills: []) == .setGoalPrompt(content: ""))
    }

    @Test
    func detectableCLIKindsIncludeSupportedCodingAgents() {
        #expect(AgentCLIKind.kimi.displayName == "Kimi Code")
        #expect(AgentCLIKind.kimi.executableName == "kimi")
        #expect(AgentCLIKind.qwen.npmPackageName == "@qwen-code/qwen-code")
        #expect(AgentCLIKind.qoder.npmPackageName == "@qoder-ai/qodercli")
        #expect(AgentCLIKind.copilot.npmPackageName == "@github/copilot")
        #expect(AgentCLIKind.qwen.displayName == "Qwen Code")
        #expect(AgentCLIKind.qwen.executableName == "qwen")
        #expect(AgentCLIKind.qoder.displayName == "Qoder CLI")
        #expect(AgentCLIKind.qoder.executableName == "qodercli")
        #expect(AgentCLIKind.copilot.displayName == "Copilot")
        #expect(AgentCLIKind.copilot.executableName == "copilot")

        #expect(AgentCLIKind.detectableCases.contains(.kimi))
        #expect(AgentCLIKind.detectableCases.contains(.qwen))
        #expect(AgentCLIKind.detectableCases.contains(.qoder))
        #expect(AgentCLIKind.detectableCases.contains(.copilot))
        #expect(!AgentCLIKind.relayCases.contains(.kimi))
        #expect(!AgentCLIKind.profileCases.contains(.kimi))
        #expect(AgentCLIKind.managedCases.contains(.kimi))
        #expect(AgentCLIKind.managedCases.contains(.qwen))
        #expect(AgentCLIKind.managedCases.contains(.qoder))
        #expect(AgentCLIKind.managedCases.contains(.copilot))
        #expect(AgentCLIKind.allCases.prefix(5) == [.claude, .codex, .gemini, .grok, .opencode])
    }
}
