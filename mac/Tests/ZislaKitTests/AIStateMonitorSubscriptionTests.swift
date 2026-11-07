import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct AIStateMonitorSubscriptionTests {
    @Test @MainActor func defaultActivityDetectorsIncludeCursor() {
        #expect(AIStateMonitor.defaultActivityDetectors().contains { $0 is CursorSessionActivityDetector })
    }

    @Test @MainActor func defaultActivityDetectorsExcludeUnavailableGrokBotAndRetainGrokCLI() {
        let detectors = AIStateMonitor.defaultActivityDetectors()
        #expect(!detectors.contains { String(describing: type(of: $0)) == "GrokBotSessionActivityDetector" })
        #expect(detectors.contains { $0 is GrokSessionActivityDetector })
    }

    @Test @MainActor func refreshDeduplicatesTokenHistoryWithoutBlockingActivity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-subscription-monitor-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var currentTime = Date(timeIntervalSince1970: 1_910_000_000)
        let sample = AIUsageSample(sourceID: "fixture-remote", provider: .cursor, timestamp: currentTime, inputTokens: 10, outputTokens: 5)
        let subscription = SubscriptionGate(result: .init(usageSamples: [sample], failedUsageProviders: [.cursor]))
        let task = AIProgressTask(id: "fixture-active", provider: .cursor, title: "fixture", progress: nil, updatedAt: currentTime)
        let activity = SubscriptionActivityFixture(task: task)
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [activity],
            subscriptionUsageDetector: subscription, usageRefreshInterval: 180, now: { currentTime })
        defer { monitor.stop() }
        monitor.refresh()
        #expect(await waitFor { monitor.state.tasks.map(\.id) == [task.id] })
        #expect(monitor.failedUsageProviders.isEmpty)
        #expect(await subscription.calls == 1)
        await subscription.release()
        #expect(await waitFor { monitor.failedUsageProviders == [.cursor] })
        let repository = AIStateRepository(directoryURL: root)
        #expect(await waitFor { (try? repository.load().usageSamples.reduce(0) { $0 + $1.totalTokens }) == 15 })
        monitor.loadUsageHistory()
        #expect(await waitFor { monitor.state.usageSamples.reduce(0) { $0 + $1.totalTokens } == 15 })
        monitor.refresh()
        try await Task.sleep(for: .milliseconds(40))
        #expect(await subscription.calls == 1)
        currentTime = currentTime.addingTimeInterval(180)
        monitor.refresh()
        #expect(await waitFor { monitor.state.usageSamples.reduce(0) { $0 + $1.totalTokens } == 15 })
        #expect(await subscription.waitForCalls(2))
        #expect(try repository.load().usageSamples.reduce(0) { $0 + $1.totalTokens } == 15)
    }

    @Test @MainActor func backgroundCursorAndMuseUsageJoinsOtherProvidersInOneDailyTotal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-daily-background-usage-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_910_000_000)
        let calendar = Calendar.current
        let sessions = root.appendingPathComponent("muse")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let event: [String: Any] = [
            "schema_version": 1, "record_type": "event", "payload_type": "runtime.session",
            "payload_schema_version": 1, "recorded_at": Int64(now.timeIntervalSince1970 * 1_000_000),
            "id": "fixture-muse", "payload": ["event": ["kind": "model_completed",
                "usage": ["input_tokens": 100, "output_tokens": 20, "cache_read_tokens": 30]]],
        ]
        try (JSONSerialization.data(withJSONObject: event) + Data([10]))
            .write(to: sessions.appendingPathComponent("session.jsonl"))
        let repository = AIStateRepository(directoryURL: root.appendingPathComponent("zisla"))
        try repository.recordUsage(AIUsageSample(provider: .claude, timestamp: now, inputTokens: 3, outputTokens: 2))
        let localUsage = AIUsageLogDetector(museSessionsDirectory: sessions, scanInterval: 0, enabledProviders: [.muse])
        let subscription = SubscriptionGate(result: .init(usageSamples: [
            AIUsageSample(sourceID: "fixture-cursor", provider: .cursor, timestamp: now, inputTokens: 10, outputTokens: 5),
        ]))
        let monitor = AIStateMonitor(directoryURL: repository.directoryURL, activityDetectors: [],
            usageDetectors: [localUsage], subscriptionUsageDetector: subscription, now: { now })
        defer { monitor.stop() }

        monitor.reload(includeUsageSamples: false)
        #expect(try repository.load().usageSamples.map(\.totalTokens) == [125])
        monitor.refresh()
        #expect(await subscription.waitForCalls(1))
        await subscription.release()
        #expect(await waitFor { (try? repository.load().usageSamples.map(\.totalTokens)) == [140] })
        #expect(monitor.usageHistoryState == .idle && monitor.state.usageSamples.isEmpty,
            "Background collection must persist consumption without loading panel history")
        let stored = try repository.load().usageSamples
        #expect(stored.count == 1, "All providers must contribute to one daily total")
        let daily = try #require(stored.first)
        #expect(daily.timestamp == calendar.startOfDay(for: now))
        #expect(daily.inputTokens == 113 && daily.outputTokens == 27)

        monitor.reload(includeUsageSamples: false)
        #expect(try repository.load().usageSamples == stored, "Repeated local scans must not double-count consumption")
        monitor.loadUsageHistory()
        #expect(await waitFor { monitor.usageHistoryState == .loaded && monitor.state.usageSamples == stored })
        let trend = AIUsageAnalytics.dailyUsageSeries(samples: monitor.state.usageSamples,
            endingAt: now, days: 1, calendar: calendar)
        #expect(trend.map(\.totalTokens) == [140])
        let today = AIUsageAnalytics.contributionCalendar(samples: monitor.state.usageSamples,
            endingAt: now, weeks: 1, calendar: calendar).flatMap { $0 }.compactMap { $0 }.first {
                calendar.isDate($0.date, inSameDayAs: now)
            }
        #expect(today?.tokens == 140)
        monitor.unloadUsageHistory()
        #expect(monitor.state.usageSamples.isEmpty)
        #expect(try repository.load().usageSamples == stored)
    }

    @Test @MainActor func stopCancelsPendingFetchAndPreventsLatePublicationOrPersistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-subscription-cancel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_910_000_000)
        let subscription = SubscriptionGate(result: .init(usageSamples: [
            AIUsageSample(sourceID: "late", provider: .cursor, timestamp: now, inputTokens: 10, outputTokens: 1)],
            failedUsageProviders: [.cursor]))
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], subscriptionUsageDetector: subscription)
        monitor.refresh()
        #expect(await subscription.waitForCalls(1))
        monitor.stop()
        await subscription.release()
        #expect(await subscription.waitForCompletion())
        try await Task.sleep(for: .milliseconds(40))
        #expect(monitor.failedUsageProviders.isEmpty)
        #expect(await subscription.sawCancellation)
        let repository = AIStateRepository(directoryURL: root)
        #expect(try repository.load().usageSamples.isEmpty)
        monitor.refresh()
        #expect(await subscription.waitForCalls(2))
        #expect(await waitFor { monitor.failedUsageProviders == [.cursor] })
        monitor.stop()
        #expect(monitor.failedUsageProviders.isEmpty)
    }

    @MainActor private func waitFor(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private actor SubscriptionGate: AISubscriptionUsageDetecting {
    private let result: AISubscriptionUsageRefresh
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var calls = 0
    private(set) var completed = false
    private(set) var sawCancellation = false
    init(result: AISubscriptionUsageRefresh) { self.result = result }
    func subscriptionUsage() async -> AISubscriptionUsageRefresh {
        calls += 1
        if !released { await withCheckedContinuation { continuation = $0 } }
        sawCancellation = Task.isCancelled
        completed = true
        return result
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
    func waitForCalls(_ count: Int) async -> Bool {
        for _ in 0..<100 {
            if calls >= count { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return calls >= count
    }
    func waitForCompletion() async -> Bool {
        for _ in 0..<100 {
            if completed { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return completed
    }
}

private final class SubscriptionActivityFixture: AIActivityDetecting {
    let task: AIProgressTask
    init(task: AIProgressTask) { self.task = task }
    func activeTasks() throws -> [AIProgressTask] { [task] }
}
