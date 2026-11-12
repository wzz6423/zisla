import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@MainActor
struct AIAccountBalanceNoticeTests {
    @Test func chatGPTNoticeUsesTheChatGPTMarkAndPerWindowRemainingColors() throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let reading = AIAccountBalance(id: "shared", providers: [.codex, .gpt], status: .available,
            windows: [.init(id: "5h", kind: .fiveHours, remainingPercent: 10, durationSeconds: 18_000),
                .init(id: "weekly", kind: .weekly, remainingPercent: 51, durationSeconds: 604_800)])
        controller.update(balances: [reading], settings: FeatureSettings(aiAccountBalanceCompactStyle: .detailed), language: .english)
        let notice = try #require(queue.left.first)
        #expect(notice.title == "ChatGPT" && notice.metadata?["quotaProviderID"] == "gpt")
        #expect(notice.metadata?["quotaLine0"] == "5h 10%" && notice.metadata?["quotaLine1"] == "7d 51%")
        #expect(notice.metadata?["quotaLineSeverity0"] == "2" && notice.metadata?["quotaLineSeverity1"] == "0")
        #expect(notice.metadata?["quotaRemainingFraction"] == "0.1")
    }


    @Test(arguments: [false, true])
    func additionalAndNamedWindowsNeverReplaceCanonicalRingMetadata(hasCanonical: Bool) throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        var windows = [AIAccountQuotaWindow(id: "additional:spark:primary_window", kind: .fiveHours,
            remainingPercent: 20, durationSeconds: 18_000, name: "Codex Spark"),
            .init(id: "additional:spark:secondary_window", kind: .weekly, remainingPercent: 70,
                durationSeconds: 604_800, name: "Codex Spark"),
            .init(id: "named-weekly", kind: .weekly, remainingPercent: 30, durationSeconds: 604_800, name: "Sonnet"),
            .init(id: "localized-weekly", kind: .weekly, remainingPercent: 40, nameKey: "模型额度")]
        if hasCanonical {
            windows += [.init(id: "primary_window", kind: .fiveHours, remainingPercent: 10, durationSeconds: 18_000),
                .init(id: "secondary_window", kind: .weekly, remainingPercent: 51, durationSeconds: 604_800)]
        }
        controller.update(balances: [.init(id: "shared", providers: [.codex], status: .available, windows: windows)],
            settings: FeatureSettings(aiAccountBalanceCompactStyle: .detailed), language: .simplifiedChinese)
        let notice = try #require(queue.left.first)
        #expect(notice.metadata?["quota5hSeverity"] == (hasCanonical ? "2" : nil))
        #expect(notice.metadata?["quota5hFraction"] == (hasCanonical ? "0.1" : nil))
        #expect(notice.metadata?["quota7dSeverity"] == (hasCanonical ? "0" : nil))
        #expect(notice.metadata?["quota7dFraction"] == (hasCanonical ? "0.51" : nil))
        let all = "全部 Codex Spark · 5h 20% · Codex Spark · 每周额度 70% · Sonnet · 每周额度 30% · 模型额度 40%"
        #expect(notice.metadata?["quotaLine0"] == (hasCanonical ? "5h 10%" : all))
        #expect(notice.metadata?["quotaLine1"] == (hasCanonical ? "7d 51% · " + all : nil))
    }

    @Test func sparseRealWindowsKeepMissingRingsAbsentAndSummaryColorsIndependent() throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let fiveHours = AIAccountBalance(id: "5h-only", providers: [.gpt], status: .available,
            windows: [.init(id: "primary_window", kind: .fiveHours, remainingPercent: 10, durationSeconds: 18_000)])
        let settings = FeatureSettings(aiAccountBalanceCompactStyle: .detailed)
        controller.update(balances: [fiveHours], settings: settings, language: .simplifiedChinese)
        let short = try #require(queue.left.first)
        #expect(short.metadata?["quotaLine0"] == "5h 10%" && short.metadata?["quotaLine1"] == nil)
        #expect(short.metadata?["quota5hFraction"] == "0.1" && short.metadata?["quota5hSeverity"] == "2")
        #expect(short.metadata?["quota7dFraction"] == nil && short.metadata?["quota7dSeverity"] == nil)

        let weekly = AIAccountBalance(id: "weekly-credits", providers: [.gpt], status: .available,
            windows: [.init(id: "secondary_window", kind: .weekly, remainingPercent: 51, durationSeconds: 604_800),
                .init(id: "credits", kind: .credits, remaining: 0, unit: .credits)])
        controller.update(balances: [weekly], settings: settings, language: .simplifiedChinese)
        let week = try #require(queue.left.first)
        #expect(week.metadata?["quotaLine0"] == "7d 51%" && week.metadata?["quotaLine1"] == "全部 积分余额 0 积分")
        #expect(week.metadata?["quotaLineSeverity0"] == "0" && week.metadata?["quotaLineSeverity1"] == "3")
        #expect(week.metadata?["quota7dFraction"] == "0.51" && week.metadata?["quota7dSeverity"] == "0")
        #expect(week.metadata?["quota5hFraction"] == nil && week.metadata?["quota5hSeverity"] == nil)
    }

    @Test func longPinnedReadingBeginsAfterTheSelectedReminderDisappears() throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let windowNames = ["Weekly", "Opus", "Sonnet", "OAuth", "Routines", "Extra"]
        let claude = AIAccountBalance(id: "claude", providers: [.claude], status: .available,
            windows: [.init(id: "5h", kind: .fiveHours, remainingPercent: 70, durationSeconds: 18_000)]
                + windowNames.enumerated().map { .init(id: "window\($0.offset)", kind: .model,
                    remainingPercent: 70, name: $0.element) })
        let codex = AIAccountBalance(id: "codex", providers: [.codex], status: .available,
            windows: [.init(id: "weekly", kind: .weekly, remainingPercent: 10)]
                + (0..<3).map { .init(id: "additional:\($0)", kind: .model, remainingPercent: 70, name: "Codex additional \($0)") })
        var settings = FeatureSettings(aiAccountBalanceCompactStyle: .detailed, aiAccountBalancePinnedInCustomIsland: true,
            aiAccountBalanceMonitoredProviders: [.claude, .codex], aiAccountBalanceDisplayedProviders: [.claude, .codex])
        settings.islandPlacement = IslandPlacement(mode: .custom, edge: .left)
        controller.update(balances: [claude, codex], settings: settings, language: .english, at: Date(timeIntervalSince1970: 100))
        let pinned = try #require(queue.left.first { $0.id == AIAccountBalanceNoticeController.pinnedID })
        let reading = max(5, CompactPillStatusPresentation(priority: .aiAccountBalance, notice: pinned, text: "")
            .accountBalanceReadingSeconds(thickness: 34, edge: .left))
        #expect(reading > 10)
        controller.updatePinned(at: Date(timeIntervalSince1970: 100 + reading * 2))
        #expect(queue.left.first { $0.id == AIAccountBalanceNoticeController.pinnedID }?.metadata?["quotaAccountID"] == "claude")
        queue.removeAll(withIDPrefix: "ai-balance-low-")
        let exposed = 100 + reading * 2 + 1
        controller.updatePinned(at: Date(timeIntervalSince1970: exposed))
        controller.updatePinned(at: Date(timeIntervalSince1970: exposed + reading - 0.1))
        #expect(queue.left.first { $0.id == AIAccountBalanceNoticeController.pinnedID }?.metadata?["quotaAccountID"] == "claude",
            "The long account must retain its entire reading budget after it becomes selected")
        controller.updatePinned(at: Date(timeIntervalSince1970: exposed + reading + 0.1))
        #expect(queue.left.first { $0.id == AIAccountBalanceNoticeController.pinnedID }?.metadata?["quotaAccountID"] == "codex")
    }

    @Test func lowReminderCoverageCannotConsumeThePinnedAccountReading() throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        var settings = FeatureSettings(aiAccountBalanceCompactStyle: .detailed, aiAccountBalancePinnedInCustomIsland: true)
        settings.islandPlacement = IslandPlacement(mode: .custom, edge: .left)
        let rows = [balance(70), balance(10, provider: .codex)]
        controller.update(balances: rows, settings: settings, language: .english, at: Date(timeIntervalSince1970: 100))
        #expect(SideNoticeLayoutEngine.selectedCompactStatusPriority(for: queue.left, settings: settings) == .transient)
        controller.updatePinned(at: Date(timeIntervalSince1970: 120))
        #expect(queue.left.first { $0.id == AIAccountBalanceNoticeController.pinnedID }?.title == "Claude",
            "An invisible pinned account must not rotate while its low reminder is selected")
        queue.removeAll(withIDPrefix: "ai-balance-low-")
        controller.updatePinned(at: Date(timeIntervalSince1970: 121))
        controller.updatePinned(at: Date(timeIntervalSince1970: 125))
        #expect(queue.left.first { $0.id == AIAccountBalanceNoticeController.pinnedID }?.title == "Claude",
            "The newly exposed account receives its complete five-second reading")
        controller.updatePinned(at: Date(timeIntervalSince1970: 126))
        #expect(queue.left.first { $0.id == AIAccountBalanceNoticeController.pinnedID }?.title == "ChatGPT")
    }

    /// Mandatory voice and recording surfaces must not consume an account's pinned reading budget.
    @Test(arguments: ["voice-processing-fixture", "screen-recording-operation-fixture"])
    func operationCoverageCannotConsumeThePinnedAccountReading(operationID: String) throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        var settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalancePinnedInCustomIsland: true,
            aiAccountBalanceMonitoredProviders: [.claude, .codex], aiAccountBalanceDisplayedProviders: [.claude, .codex])
        settings.islandPlacement = IslandPlacement(mode: .custom, edge: .left)
        controller.update(balances: [balance(70), balance(70, provider: .codex)], settings: settings,
            language: .english, at: Date(timeIntervalSince1970: 100))
        queue.enqueue(IslandNotice(id: operationID, title: "Fixture", side: .left,
            createdAt: Date(timeIntervalSince1970: 101)), expiresAfter: nil)
        controller.updatePinned(at: Date(timeIntervalSince1970: 120))
        #expect(queue.left.first { $0.id == AIAccountBalanceNoticeController.pinnedID }?.metadata?["quotaAccountID"] == "claude")
        queue.remove(id: operationID)
        controller.updatePinned(at: Date(timeIntervalSince1970: 121))
        controller.updatePinned(at: Date(timeIntervalSince1970: 125))
        #expect(queue.left.first { $0.id == AIAccountBalanceNoticeController.pinnedID }?.metadata?["quotaAccountID"] == "claude")
        controller.updatePinned(at: Date(timeIntervalSince1970: 126))
        #expect(queue.left.first { $0.id == AIAccountBalanceNoticeController.pinnedID }?.metadata?["quotaAccountID"] == "codex")
    }

    @Test func equalSummariesKeepAStableAccountIdentityAcrossPollsAndChangeItOnRotation() throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let windows = [AIAccountQuotaWindow(id: "5h", kind: .fiveHours, remainingPercent: 70, durationSeconds: 18_000),
            .init(id: "weekly", kind: .weekly, remainingPercent: 70)]
        let rows = [AIProvider.claude, .codex].map { AIAccountBalance(id: $0.rawValue, providers: [$0], status: .available, windows: windows) }
        var settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalanceCompactStyle: .detailed,
            aiAccountBalancePinnedInCustomIsland: true, aiAccountBalanceMonitoredProviders: [.claude, .codex],
            aiAccountBalanceDisplayedProviders: [.claude, .codex])
        settings.islandPlacement = IslandPlacement(mode: .custom, edge: .left)
        controller.update(balances: rows, settings: settings, language: .english, at: Date(timeIntervalSince1970: 100))
        let first = try #require(queue.left.first)
        controller.update(balances: rows, settings: settings, language: .english, at: Date(timeIntervalSince1970: 101))
        #expect(queue.left.first?.metadata?["quotaAccountID"] == first.metadata?["quotaAccountID"])
        controller.updatePinned(at: Date(timeIntervalSince1970: 120))
        let second = try #require(queue.left.first)
        #expect(first.metadata?["quotaLine0"] == second.metadata?["quotaLine0"]
            && first.metadata?["quotaLine1"] == second.metadata?["quotaLine1"])
        #expect(first.metadata?["quotaAccountID"] == "claude" && second.metadata?["quotaAccountID"] == "codex")
    }

    @Test func repeatedPollAndUnrelatedAccountChangesCannotRestartOrSkipThePinnedReading() throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        var settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalancePinnedInCustomIsland: true)
        settings.islandPlacement.mode = .custom
        let claude = balance(70), gemini = balance(80, provider: .gemini)
        controller.update(balances: [claude, gemini], settings: settings, language: .english,
            at: Date(timeIntervalSince1970: 100))
        controller.update(balances: [claude, gemini], settings: settings, language: .english,
            at: Date(timeIntervalSince1970: 104))
        #expect(queue.left.first?.title == "Claude")
        controller.update(balances: [claude, balance(10, provider: .gemini)], settings: settings, language: .english,
            at: Date(timeIntervalSince1970: 105))
        #expect(queue.left.first?.title == "Gemini", "The same reading must finish five seconds after its first appearance")
        controller.update(balances: [claude, balance(20, provider: .gemini)], settings: settings, language: .english,
            at: Date(timeIntervalSince1970: 109))
        controller.updatePinned(at: Date(timeIntervalSince1970: 110))
        #expect(queue.left.first?.title == "Gemini", "A changed quota must get a complete new reading before rotation")
    }

    @Test func gptSelectionUsesOnlyTheChatGPTBalanceIdentity() throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let reading = AIAccountBalance(id: "shared", providers: [.codex, .gpt], status: .available,
            windows: [.init(id: "weekly", kind: .weekly, remainingPercent: 10)])
        let settings = FeatureSettings(aiAccountBalanceMonitoredProviders: [.gpt], aiAccountBalanceDisplayedProviders: [.gpt])
        controller.update(balances: [reading], settings: settings, language: .simplifiedChinese)
        let notice = try #require(queue.left.first)
        #expect(notice.title == "ChatGPT")
        #expect(notice.metadata?["quotaProviderID"] == "gpt")
        #expect(notice.metadata?["quotaLine0"] == "每周额度 10%")
        #expect(notice.metadata?["quotaLine2"] == nil)
    }

    @Test func longSummaryGetsAFullReadingBeforeExpiryAndPinnedRotation() async throws {
        let expiry = BalanceExpiryClock()
        let queue = SideNoticeQueue(capacityPerSide: 3, expirySleeper: { try await expiry.wait($0) })
        let controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let reading = AIAccountBalance(id: "claude", providers: [.claude], status: .available,
            windows: [.init(id: "5h", kind: .fiveHours, remainingPercent: 70, durationSeconds: 18_000)]
                + (0..<7).map { .init(id: "model\($0)", kind: .model, remainingPercent: 70, name: "claude-opus-long-model-\($0)") }
                + [.init(id: "extra", kind: .budget, remaining: 0, unit: .usd)])
        var settings = FeatureSettings(aiAccountBalanceCompactStyle: .detailed, aiAccountBalancePinnedInCustomIsland: true)
        settings.islandPlacement = IslandPlacement(mode: .custom, edge: .left)
        controller.update(balances: [reading, balance(70, provider: .gemini)], settings: settings,
            language: .english, at: Date(timeIntervalSinceReferenceDate: 119))
        for _ in 0..<400 { if await expiry.duration != nil { break }; await Task.yield() }
        #expect(await expiry.duration ?? .zero > .seconds(20), "The long real summary cannot expire on the default six-second timer")
        queue.removeAll(withIDPrefix: "ai-balance-low-")
        controller.updatePinned(at: Date(timeIntervalSinceReferenceDate: 124))
        #expect(queue.left.first { $0.id == AIAccountBalanceNoticeController.pinnedID }?.title == "Claude")
        controller.updatePinned(at: Date(timeIntervalSinceReferenceDate: 10_000))
        #expect(queue.left.first { $0.id == AIAccountBalanceNoticeController.pinnedID }?.title == "Gemini")
        await expiry.release()
    }

    @Test(arguments: [IslandLayoutStyle.notch, .pill], [CGFloat(0), 80, 180])
    func actualBalanceFramesFitTheRingAndQuotaForEveryCameraGap(style: IslandLayoutStyle, gap: CGFloat) throws {
        var settings = FeatureSettings(islandLayoutStyle: style)
        settings.compactStatusPriority = [.transient]
        let notice = IslandNotice(id: "ai-balance-low-layout", title: "Claude", style: .status,
            metadata: ["quotaSeverity": "2", "quotaRemainingFraction": "0.1", "quotaLine0": "5h 10%"])
        let screenFrame = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let screen = ScreenSnapshot(displayID: 1, frame: screenFrame, visibleFrame: screenFrame,
            safeAreaInsets: ScreenInsets(top: gap > 0 ? 34 : 0),
            auxiliaryTopLeftArea: gap > 0 ? CGRect(x: -1440, y: 866, width: 720 - gap / 2, height: 34) : nil,
            auxiliaryTopRightArea: gap > 0 ? CGRect(x: -720 + gap / 2, y: 866, width: 720 - gap / 2, height: 34) : nil,
            menuBarHeightFallback: 24)
        let engine = SideNoticeLayoutEngine()
        let actual = try #require(engine.compactBarFrame(for: screen, notices: [notice], settings: settings))
        var configuration = settings.islandScreenConfiguration
        let sizing = try #require(engine.compactBarSizing(for: [notice], settings: settings))
        configuration.expandsForDetailedStatus = sizing.expandsForDetailedStatus
        configuration.compactStatusLength = sizing.customPillLength
        configuration.compactStatusSideWidth = sizing.compactStatusSideWidth
        let layout = ScreenLayoutEngine(configuration: configuration).layout(for: screen)
        let throughLayout = try #require(engine.compactBarFrame(for: layout, notices: [notice], settings: settings))
        #expect(actual == throughLayout, "Both real layout entry points must reserve the same balance bounds")
        if style == .pill || gap > 0 {
            let center = style == .pill ? max(120, gap) : gap
            #expect(actual.width - center >= 96, "Both camera wings need room for the ring or short quota and insets")
        } else {
            #expect(actual.width < 150, "A short reading on a simulated notch must use its ring and text's natural width")
        }
        #expect(actual.width <= screen.frame.width && actual.minX >= screen.frame.minX && actual.maxX <= screen.frame.maxX)
    }

    @Test func ringMetadataUsesTheLimitingWindowInBothSummaryStyles() throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let reading = AIAccountBalance(id: "fixture", providers: [.claude], status: .available,
            windows: [.init(id: "5h", kind: .fiveHours, remainingPercent: 70, durationSeconds: 18_000),
                .init(id: "weekly", kind: .weekly, remainingPercent: 10)])
        var settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalancePinnedInCustomIsland: true)
        settings.islandPlacement.mode = .custom
        for style in MediaCompactStyle.allCases {
            settings.aiAccountBalanceCompactStyle = style
            controller.update(balances: [reading], settings: settings, language: .simplifiedChinese)
            let notice = try #require(queue.left.first)
            #expect(notice.metadata?["quotaProviderID"] == "claude")
            #expect(notice.metadata?["quotaRemainingFraction"] == "0.1")
            #expect(notice.metadata?["quotaLine0"] == (style == .detailed ? "5h 70%" : "每周额度 10%"))
            #expect(notice.metadata?["quotaLine1"] == (style == .detailed ? "7d 10%" : nil))
        }
    }

    @Test func unsupportedAvailableFixtureCannotCreateCardsPinOrLowAlert() {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        var settings = FeatureSettings(aiAccountBalancePinnedInCustomIsland: true)
        settings.islandPlacement.mode = .custom
        controller.update(balances: [balance(0, provider: .qwen)], settings: settings, language: .english)
        #expect(queue.left.isEmpty)
    }

    /// Every compact consumer must classify urgent events alike while leaving persistent quota in its own priority.
    @Test func transientClassificationRecognizesAlertsWithoutIncludingPersistentBalance() {
        for notice in [IslandNotice(id: "focus-transition-fixture", title: "Focus"),
            IslandNotice(id: "headphone-fixture", title: "Audio", style: .headphone),
            IslandNotice(id: "battery-low", title: "Battery"),
            IslandNotice(id: "ai-balance-low-fixture", title: "Quota")] {
            #expect(SideNoticeLayoutEngine.isTransientCompactNotice(notice))
        }
        for notice in [IslandNotice(id: AIAccountBalanceNoticeController.pinnedID, title: "Quota"),
            IslandNotice(id: "media-active-fixture", title: "Media"),
            IslandNotice(id: "ordinary-fixture", title: "Ordinary")] {
            #expect(!SideNoticeLayoutEngine.isTransientCompactNotice(notice))
        }
    }

    /// Polling and dismissal must not repeat one episode; escalation and recovery must remain observable transitions.
    @Test func remainingThresholdsEscalateToZeroOnceAndRecoveryRearms() throws {
        let queue = SideNoticeQueue()
        let notices = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let settings = FeatureSettings()
        for (index, percent) in [21.0, 20, 19, 10, 0].enumerated() {
            notices.update(balances: [balance(percent)], settings: settings, language: .english, at: Date(timeIntervalSince1970: Double(index)))
            if percent > 20 { #expect(queue.left.isEmpty) }
            else { #expect(queue.left.first?.metadata?["quotaSeverity"] == String(AIAccountQuotaSeverity(remainingPercent: percent).rawValue)) }
            if percent == 19 { #expect(queue.left.first?.createdAt == Date(timeIntervalSince1970: 1)) }
        }
        queue.removeAll()
        notices.update(balances: [balance(0)], settings: settings, language: .english)
        #expect(queue.left.isEmpty, "A dismissed exhausted reading must not reappear on every poll")
        notices.update(balances: [balance(70)], settings: settings, language: .english)
        notices.update(balances: [balance(0)], settings: settings, language: .english)
        #expect(queue.left.count == 1)
    }

    /// Display choice must not disable alerts, while monitoring and master toggles must clear and rearm episodes.
    @Test(arguments: AIProvider.allCases.filter(AIAccountBalanceCatalog.supportsBalanceQuery))
    func displayedOffStillAlertsMonitoredOffClearsAndReenabledAlertRearms(provider: AIProvider) {
        let queue = SideNoticeQueue()
        let notices = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        var settings = FeatureSettings(aiAccountBalanceDisplayedProviders: [])
        notices.update(balances: [balance(10, provider: provider)], settings: settings, language: .english)
        #expect(queue.left.count == 1)
        settings.aiAccountBalanceMonitoredProviders = []
        notices.update(balances: [balance(10, provider: provider)], settings: settings, language: .english)
        #expect(queue.left.isEmpty)
        settings.aiAccountBalanceMonitoredProviders = [provider]
        notices.update(balances: [balance(10, provider: provider)], settings: settings, language: .english)
        #expect(queue.left.count == 1)
        settings.aiAccountBalanceNoticeEnabled = false
        notices.update(balances: [balance(10, provider: provider)], settings: settings, language: .english)
        #expect(queue.left.isEmpty)
        settings.aiAccountBalanceNoticeEnabled = true
        notices.update(balances: [balance(10, provider: provider)], settings: settings, language: .english)
        #expect(queue.left.count == 1)
        settings.aiProgressEnabled = false
        notices.update(balances: [balance(10, provider: provider)], settings: settings, language: .english)
        settings.aiProgressEnabled = true
        notices.update(balances: [balance(10, provider: provider)], settings: settings, language: .english)
        #expect(queue.left.count == 1)
    }

    /// An unavailable poll neither fabricates exhaustion nor resets a dismissed episode for the same shared account.
    @Test func unavailableDoesNotFabricateZeroOrRearmSameEpisodeAndSharedAliasesUseSelection() throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        var reading = balance(10)
        controller.update(balances: [reading], settings: FeatureSettings(), language: .english)
        reading.status = .unavailable
        controller.update(balances: [reading], settings: FeatureSettings(), language: .english)
        #expect(queue.left.isEmpty)
        reading.status = .available
        controller.update(balances: [reading], settings: FeatureSettings(), language: .english)
        #expect(queue.left.isEmpty)
        reading.id = "shared-codex"; reading.providers = [.codex, .gpt]
        var settings = FeatureSettings(aiAccountBalanceMonitoredProviders: [.gpt], aiAccountBalanceDisplayedProviders: [.gpt])
        settings.aiAccountBalanceCompactStyle = .detailed
        controller.update(balances: [reading], settings: settings, language: .simplifiedChinese)
        let notice = try #require(queue.left.first)
        #expect(notice.title == "ChatGPT")
        #expect(notice.metadata?["quotaLine0"] != nil && notice.metadata?["quotaLine2"] == nil)
        #expect(queue.left.count == 1)
    }

    /// Amount-only exhaustion must be the limiting compact line even when every percentage window is healthy.
    @Test func compactModeIdentifiesExhaustedCreditsWhenPercentageWindowsAreHealthy() {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        var reading = balance(70)
        reading.windows.append(.init(id: "credits", kind: .credits, remaining: 0, unit: .credits))
        controller.update(balances: [reading], settings: FeatureSettings(), language: .simplifiedChinese)
        #expect(queue.left.first?.metadata?["quotaSeverity"] == String(AIAccountQuotaSeverity.exhausted.rawValue))
        #expect(queue.left.first?.metadata?["quotaLine0"] == "积分余额 0 积分")
    }

    /// Fixed-time rotation covers all selected valid accounts while respecting placement and always-visible policy.
    @Test func persistentBalancesRequireCustomPlacementAndRotateAllValidSelectedAccounts() throws {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        let rows = [balance(70), balance(50, provider: .gemini), balance(10, provider: .gpt)]
        var settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalancePinnedInCustomIsland: true)
        controller.update(balances: rows, settings: settings, language: .english)
        #expect(queue.left.isEmpty)
        settings.islandPlacement.mode = .custom
        controller.update(balances: rows, settings: settings, language: .english, at: Date(timeIntervalSinceReferenceDate: 0))
        var providers: Set<String> = []
        for second in [0.0, 5, 10] {
            controller.updatePinned(at: Date(timeIntervalSinceReferenceDate: second))
            providers.insert(try #require(queue.left.first?.metadata?["quotaProvider"]))
            #expect(queue.left.first?.id == AIAccountBalanceNoticeController.pinnedID && queue.left.count == 1)
        }
        #expect(providers.count == rows.count)
        settings.aiAccountBalanceDisplayedProviders = [.gemini]
        controller.update(balances: rows, settings: settings, language: .english)
        #expect(queue.left.first?.title == "Gemini")
        settings.islandPlacement.mode = .camera
        controller.update(balances: rows, settings: settings, language: .english)
        #expect(queue.left.isEmpty)
    }

    /// A queued detailed balance must not alter the geometry of a newer headphone or focus transient.
    @Test func queuedBalanceCannotExpandTheNewerUnrelatedTransientNotice() throws {
        var settings = FeatureSettings(aiAccountBalanceCompactStyle: .detailed)
        settings.compactStatusPriority = [.transient]
        let low = IslandNotice(id: "ai-balance-low-fixture", title: "Claude", createdAt: Date(timeIntervalSince1970: 1),
            style: .status, metadata: ["quotaProvider": "Claude", "quotaLine0": "5h 10%", "quotaLine1": "Weekly 70%"])
        let battery = IslandNotice(id: "battery-low", title: "Battery", detail: "20%", createdAt: Date(timeIntervalSince1970: 2), style: .status)
        let screen = ScreenSnapshot(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let engine = SideNoticeLayoutEngine()
        let first = try #require(engine.compactBarFrame(for: screen, notices: [low], settings: settings))
        let selectedBattery = try #require(engine.compactBarFrame(for: screen, notices: [low, battery], settings: settings))
        let batteryOnly = try #require(engine.compactBarFrame(for: screen, notices: [battery], settings: settings))
        #expect(selectedBattery == batteryOnly)
        #expect(first.width < 150, "The short quota now uses its ring and actual summary's natural width")
        let presentation = engine.compactPillPresentations(for: [low, battery], settings: settings).first
        #expect(presentation?.notice.id == battery.id)
    }

    /// An injected suspension point proves rotation cancellation and release without removing unrelated notices.
    @Test func disablingPinnedBalanceCancelsRotationAndDeinitClearsOnlyBalanceNotices() async throws {
        let queue = SideNoticeQueue(), clock = BalanceRotationClock()
        let ordinary = IslandNotice(id: "ordinary", title: "Fixture", side: .left)
        queue.enqueue(ordinary, expiresAfter: nil)
        var controller: AIAccountBalanceNoticeController? = AIAccountBalanceNoticeController(queue: queue, sleep: { _ in try await clock.wait() })
        var settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalancePinnedInCustomIsland: true)
        settings.islandPlacement.mode = .custom
        controller?.update(balances: [balance(70), balance(80, provider: .gemini)], settings: settings, language: .english)
        for _ in 0..<400 {
            if await clock.waiting { break }
            await Task.yield()
        }
        #expect(await clock.waiting)
        settings.aiAccountBalancePinnedInCustomIsland = false
        controller?.update(balances: [balance(70), balance(80, provider: .gemini)], settings: settings, language: .english)
        #expect(queue.left == [ordinary])
        await clock.advance()
        for _ in 0..<400 {
            if await clock.cancelled { break }
            await Task.yield()
        }
        #expect(await clock.cancelled)
        settings.aiAccountBalanceNoticeEnabled = true
        controller?.update(balances: [balance(10)], settings: settings, language: .english)
        #expect(queue.left.count == 2)
        weak let retained = controller
        controller = nil
        #expect(retained == nil)
        #expect(queue.left == [ordinary], "Releasing the controller must not leave pinned content or clear other events")
        queue.removeAll()
    }

    private func balance(_ percent: Double, provider: AIProvider = .claude) -> AIAccountBalance {
        .init(id: provider.rawValue, providers: [provider], status: .available,
            windows: [.init(id: "quota", kind: .all, remainingPercent: percent)])
    }
}

private actor BalanceExpiryClock {
    private(set) var duration: Duration?
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(_ duration: Duration) async throws {
        self.duration = duration
        await withCheckedContinuation { continuation = $0 }
        try Task.checkCancellation()
    }
    func release() { continuation?.resume(); continuation = nil }
}

private actor BalanceRotationClock {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var waiting = false
    private(set) var cancelled = false
    func wait() async throws {
        waiting = true
        await withCheckedContinuation { continuation = $0 }
        cancelled = Task.isCancelled
        try Task.checkCancellation()
    }
    func advance() { continuation?.resume(); continuation = nil }
}
