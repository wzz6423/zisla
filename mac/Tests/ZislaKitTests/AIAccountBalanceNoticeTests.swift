import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@MainActor
struct AIAccountBalanceNoticeTests {
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

    @Test func displayedOffStillAlertsMonitoredOffClearsAndReenabledAlertRearms() {
        let queue = SideNoticeQueue()
        let notices = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        var settings = FeatureSettings(aiAccountBalanceDisplayedProviders: [])
        notices.update(balances: [balance(10)], settings: settings, language: .english)
        #expect(queue.left.count == 1)
        settings.aiAccountBalanceMonitoredProviders = []
        notices.update(balances: [balance(10)], settings: settings, language: .english)
        #expect(queue.left.isEmpty)
        settings.aiAccountBalanceMonitoredProviders = [.claude]
        notices.update(balances: [balance(10)], settings: settings, language: .english)
        #expect(queue.left.count == 1)
        settings.aiAccountBalanceNoticeEnabled = false
        notices.update(balances: [balance(10)], settings: settings, language: .english)
        #expect(queue.left.isEmpty)
        settings.aiAccountBalanceNoticeEnabled = true
        notices.update(balances: [balance(10)], settings: settings, language: .english)
        #expect(queue.left.count == 1)
        settings.aiProgressEnabled = false
        notices.update(balances: [balance(10)], settings: settings, language: .english)
        settings.aiProgressEnabled = true
        notices.update(balances: [balance(10)], settings: settings, language: .english)
        #expect(queue.left.count == 1)
    }

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
        #expect(notice.title == "GPT · Codex 账户额度")
        #expect(notice.metadata?["quotaLine0"] != nil && notice.metadata?["quotaLine2"] == nil)
        #expect(queue.left.count == 1)
    }

    @Test func compactModeIdentifiesExhaustedCreditsWhenPercentageWindowsAreHealthy() {
        let queue = SideNoticeQueue(), controller = AIAccountBalanceNoticeController(queue: queue)
        defer { queue.removeAll() }
        var reading = balance(70)
        reading.windows.append(.init(id: "credits", kind: .credits, remaining: 0, unit: .credits))
        controller.update(balances: [reading], settings: FeatureSettings(), language: .simplifiedChinese)
        #expect(queue.left.first?.metadata?["quotaSeverity"] == String(AIAccountQuotaSeverity.exhausted.rawValue))
        #expect(queue.left.first?.metadata?["quotaLine0"] == "积分余额 0 积分")
    }

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
        #expect(first.width > selectedBattery.width)
        let presentation = engine.compactPillPresentations(for: [low, battery], settings: settings).first
        #expect(presentation?.notice.id == battery.id)
    }

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
