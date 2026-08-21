import Foundation
import Testing
@testable import ZislaCore

struct AIAgentModelsTests {
    @Test
    func skillSyncConfigurationDefaultsWhenLoadingExistingState() throws {
        let state = try JSONDecoder().decode(AIAgentState.self, from: Data("{}".utf8))

        #expect(state.skillSyncConfiguration == AgentSkillSyncConfiguration())
        #expect(state.skillSyncConfiguration.mode == .symbolicLink)
        #expect(state.skillSyncConfiguration.enabledDestinations == Set(AgentSkillSyncDestination.allCases))
        #expect(state.cliAutoUpdateEnabled)
    }

    @Test
    func cliAutoUpdateSettingDefaultsOnForLegacyStateAndRoundTrips() throws {
        let legacy = try JSONDecoder().decode(
            AIAgentState.self,
            from: Data(#"{"accounts":[],"channels":[],"cliStatuses":[]}"#.utf8)
        )
        let disabled = AIAgentState(cliAutoUpdateEnabled: false)
        let roundTripped = try JSONDecoder().decode(
            AIAgentState.self,
            from: JSONEncoder().encode(disabled)
        )

        #expect(legacy.cliAutoUpdateEnabled)
        #expect(!roundTripped.cliAutoUpdateEnabled)
    }

    @Test
    func channelEffortDefaultsForLegacyDataAndRoundTrips() throws {
        let legacy = try JSONDecoder().decode(
            AgentChannel.self,
            from: Data(#"{"id":"00000000-0000-0000-0000-000000000001","name":"远端","protocolKind":"openAICompatible","defaultModel":"gpt-test","endpointGroups":[],"isEnabled":true}"#.utf8)
        )
        let configured = AgentChannel(name: "远端", defaultModel: "gpt-test", effort: .ultra)
        let roundTripped = try JSONDecoder().decode(
            AgentChannel.self,
            from: JSONEncoder().encode(configured)
        )

        #expect(legacy.effort == .high)
        #expect(roundTripped.effort == .ultra)
        #expect(AgentModelEffort.allCases == [.low, .medium, .high, .xhigh, .max, .ultra])
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
    func legacyAgentStateIgnoresRemovedConversationFields() throws {
        let data = Data(#"{"accounts":[],"channels":[],"chatThreads":[],"automations":[],"messageConnections":[]}"#.utf8)
        let state = try JSONDecoder().decode(AIAgentState.self, from: data)

        #expect(state.localModels.isEmpty)
        #expect(state.skills.isEmpty)
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
        #expect(AgentCLIKind.copilot.displayName == "GitHub Copilot")
        #expect(AgentCLIKind.copilot.executableName == "copilot")
        #expect(AgentCLIKind.dsh.displayName == "DeepSeek Harness")
        #expect(AgentCLIKind.dsh.executableName == "dsh")
        #expect(AgentCLIKind.dsh.npmPackageName == "@deepseek-ai/dsh")
        #expect(AgentCLIKind.allCases.last == .pi)
        #expect(AgentCLIKind.pi.displayName == "Pi")
        #expect(AgentCLIKind.pi.executableName == "pi")
        #expect(AgentCLIKind.pi.npmPackageName == "@earendil-works/pi-coding-agent")

        #expect(AgentCLIKind.detectableCases.contains(.kimi))
        #expect(AgentCLIKind.detectableCases.contains(.qwen))
        #expect(AgentCLIKind.detectableCases.contains(.qoder))
        #expect(AgentCLIKind.detectableCases.contains(.copilot))
        #expect(AgentCLIKind.detectableCases.contains(.dsh))
        #expect(!AgentCLIKind.relayCases.contains(.kimi))
        #expect(!AgentCLIKind.profileCases.contains(.kimi))
        #expect(AgentCLIKind.managedCases.contains(.kimi))
        #expect(AgentCLIKind.managedCases.contains(.qwen))
        #expect(AgentCLIKind.managedCases.contains(.qoder))
        #expect(AgentCLIKind.managedCases.contains(.copilot))
        #expect(AgentCLIKind.managedCases.contains(.dsh))
        #expect(AgentCLIKind.allCases.prefix(5) == [.claude, .codex, .gemini, .grok, .opencode])
    }

    @Test
    func glmCLIKindUsesOfficialPackageMetadata() throws {
        let glm = try #require(AgentCLIKind(rawValue: "glm"))

        #expect(glm.displayName == "GLM Coding")
        #expect(glm.executableName == "chelper")
        #expect(glm.npmPackageName == "@z_ai/coding-helper")
        #expect(AgentCLIKind.detectableCases.contains(glm))
        #expect(AgentCLIKind.managedCases.contains(glm))
        #expect(!AgentCLIKind.relayCases.contains(glm))
        #expect(!AgentCLIKind.profileCases.contains(glm))
    }
}
