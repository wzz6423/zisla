import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

#if DEBUG
struct AIModelUsageDebugTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// An empty Makefile default must leave real history available without opting into simulation.
    @Test
    func absentOrEmptyEnvironmentDoesNotRequestAFixture() {
        #expect(AIModelUsageDebug.history(environment: [:], now: now) == nil)
        #expect(AIModelUsageDebug.history(environment: ["ZISLA_DEBUG_AI_MODEL_USAGE": ""], now: now) == nil)
    }

    /// The trend and model list must agree when several providers and repeated model entries share a day.
    @Test
    func modelFixturesAggregateByCalendarDayAndProvider() throws {
        let history = try #require(AIModelUsageDebug.history(environment: ["ZISLA_DEBUG_AI_MODEL_USAGE":
            "codex:gpt-model:100:20,claude:claude-model:30:5,codex:gpt-model:10:2:0,codex:older-model:50:10:1"], now: now))
        let calendar = Calendar.current
        let rows = AIUsageAnalytics.dailyModelUsage(history: history, endingAt: now)
        #expect(rows.map(\.totalTokens) == [167, 60])
        #expect(rows[0].models.map(\.totalTokens) == [132, 35])
        #expect(rows[0].models.map(\.provider) == [.codex, .claude])
        #expect(rows[1].date == calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)))
        #expect(history.modelUsageSamples.allSatisfy { $0.sourceID == nil })
    }

    /// Invalid explicit input must clear the preview instead of silently falling back to real usage.
    @Test(arguments: [" ", "invalid:model:10:2", "codex::10:2", "codex:m:-1:2", "codex:m:1:-2",
        "codex:m:nan:2", "codex:m:1:2:-1", "codex:m:1:2:168", "codex:m:1:2:no",
        "codex:m:1:2:1:extra", "codex:m:1:2,", "codex:m:1:2,claude:m:bad:2",
        "codex:m:9223372036854775808:2"])
    func malformedFixturesStayIsolated(raw: String) {
        #expect(AIModelUsageDebug.history(environment: ["ZISLA_DEBUG_AI_MODEL_USAGE": raw], now: now) == AIUsageHistory())
    }

    /// Bounded input can still exercise long labels, the oldest visible day, and saturated token counts.
    @Test
    func inputBudgetAndCountBoundariesRemainDeterministic() throws {
        let prefix = "codex:"
        let suffix = ":1:2"
        let exact = prefix + String(repeating: "m", count: 65_536 - prefix.utf8.count - suffix.utf8.count) + suffix
        #expect(AIModelUsageDebug.history(environment: ["ZISLA_DEBUG_AI_MODEL_USAGE": exact], now: now)?.usageSamples.first?.totalTokens == 3)
        #expect(AIModelUsageDebug.history(environment: ["ZISLA_DEBUG_AI_MODEL_USAGE": "codex:m" + exact.dropFirst(6)], now: now) == AIUsageHistory())
        let history = try #require(AIModelUsageDebug.history(environment: ["ZISLA_DEBUG_AI_MODEL_USAGE":
            "codex:m:\(Int.max):2:167,codex:m:1:3:167,claude:zero:0:0"], now: now))
        #expect(history.usageSamples.first?.totalTokens == Int.max)
        #expect(history.modelUsageSamples.first?.inputTokens == Int.max)
        #expect(history.usageSamples.last?.totalTokens == 0)
    }

    /// Loading fixtures must bypass an unusable database; unload and stop must release both history arrays.
    @Test @MainActor
    func fixtureLoadsWithoutStorageAndClearsWhenThePanelUnloads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-model-debug-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not-a-directory".utf8).write(to: root)
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [],
            environment: ["ZISLA_DEBUG_AI_MODEL_USAGE": "codex:gpt-model:100:20"], now: { now })
        monitor.loadUsageHistory()
        #expect(monitor.usageHistoryState == .loaded)
        #expect(monitor.state.usageSamples.map(\.totalTokens) == [120])
        #expect(monitor.state.modelUsageSamples.map(\.model) == ["gpt-model"])
        monitor.unloadUsageHistory()
        #expect(monitor.state.usageSamples.isEmpty && monitor.state.modelUsageSamples.isEmpty)
        monitor.loadUsageHistory()
        #expect(monitor.state.usageSamples.map(\.totalTokens) == [120])
        monitor.stop()
        #expect(monitor.usageHistoryState == .idle)
        #expect(monitor.state.usageSamples.isEmpty && monitor.state.modelUsageSamples.isEmpty)
        #expect(try Data(contentsOf: root) == Data("not-a-directory".utf8))
    }

    /// Complete detector reloads and task-only reloads must preserve simulation without persisting its tokens.
    @Test @MainActor
    func persistedAndDetectorReloadsKeepFixturesOutOfTheDatabase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-model-debug-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        try repository.recordUsage(AIUsageSample(provider: .claude, timestamp: now, inputTokens: 3, outputTokens: 2, model: "real-model"))
        let detector = ModelDebugUsageFixture(timestamp: now)
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], usageDetectors: [detector],
            environment: ["ZISLA_DEBUG_AI_MODEL_USAGE": "codex:preview-model:100:20"], now: { now })
        monitor.reload()
        #expect(monitor.state.usageSamples.map(\.totalTokens) == [120])
        #expect(monitor.state.modelUsageSamples.map(\.model) == ["preview-model"])
        #expect(try repository.loadUsageHistory().usageSamples.map(\.totalTokens) == [20])
        #expect(try repository.loadUsageHistory().modelUsageSamples.map(\.model).sorted { ($0 ?? "") < ($1 ?? "") } == ["detected-model", "real-model"])
        monitor.reload(includeUsageSamples: false)
        #expect(monitor.state.usageSamples.isEmpty && monitor.state.modelUsageSamples.isEmpty)
        monitor.loadUsageHistory()
        #expect(monitor.state.modelUsageSamples.map(\.model) == ["preview-model"])
        monitor.unloadUsageHistory()
        let live = AIStateMonitor(directoryURL: root, activityDetectors: [], environment: [:], now: { now })
        live.reload()
        #expect(live.state.usageSamples.map(\.totalTokens) == [20])
    }

    /// Invalid requested previews must not expose the stored history during either loading path.
    @Test @MainActor
    func malformedFixtureNeverFallsBackToPersistedTokens() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-model-debug-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AIStateRepository(directoryURL: root)
        try repository.recordUsage(AIUsageSample(provider: .codex, timestamp: now, inputTokens: 10, outputTokens: 2))
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [],
            environment: ["ZISLA_DEBUG_AI_MODEL_USAGE": "invalid"], now: { now })
        monitor.reload()
        #expect(monitor.state.usageSamples.isEmpty && monitor.state.modelUsageSamples.isEmpty)
        monitor.unloadUsageHistory()
        monitor.loadUsageHistory()
        #expect(monitor.usageHistoryState == .loaded)
        #expect(monitor.state.usageSamples.isEmpty && monitor.state.modelUsageSamples.isEmpty)
        #expect(try repository.loadUsageHistory().usageSamples.map(\.totalTokens) == [12])
    }
}

private struct ModelDebugUsageFixture: AIUsageDetecting {
    let timestamp: Date

    func usageSamples() throws -> [AIUsageSample] {
        [AIUsageSample(sourceID: "debug-test-detector", provider: .claude, timestamp: timestamp,
            inputTokens: 10, outputTokens: 5, model: "detected-model")]
    }
}
#endif
