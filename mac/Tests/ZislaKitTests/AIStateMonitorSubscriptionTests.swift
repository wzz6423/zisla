import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct AIStateMonitorSubscriptionTests {
    @Test @MainActor func defaultActivityDetectorsIncludeCursor() {
        #expect(AIStateMonitor.defaultActivityDetectors().contains { $0 is CursorSessionActivityDetector })
    }

    @Test @MainActor func refreshPublishesIndependentQuotasAndDeduplicatesUsageWithoutBlockingActivity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-subscription-monitor-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var currentTime = Date(timeIntervalSince1970: 1_910_000_000)
        let sample = AIUsageSample(sourceID: "fixture-remote", provider: .cursor, timestamp: currentTime, inputTokens: 10, outputTokens: 5)
        let quota = AIQuotaSnapshot(provider: .cursor, window: .plan, usedPercent: 20, resetsAt: nil, checkedAt: currentTime)
        let subscription = SubscriptionGate(result: .init(quotas: [quota], usageSamples: [sample],
            failedProviders: [.grokBot], failedUsageProviders: [.muse]))
        let task = AIProgressTask(id: "fixture-active", provider: .cursor, title: "fixture", progress: nil, updatedAt: currentTime)
        let activity = SubscriptionActivityFixture(task: task)
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [activity],
            subscriptionUsageDetector: subscription, usageRefreshInterval: 180, now: { currentTime })
        defer { monitor.stop() }
        monitor.refresh()
        #expect(await waitFor { monitor.state.tasks.map(\.id) == [task.id] })
        #expect(monitor.quotas.isEmpty)
        #expect(await subscription.calls == 1)
        await subscription.release()
        #expect(await waitFor { monitor.quotas == [quota] })
        #expect(monitor.failedQuotaProviders == [.grokBot] && monitor.failedUsageProviders == [.muse])
        let repository = AIStateRepository(directoryURL: root)
        #expect(await waitFor { (try? repository.load().usageSamples.reduce(0) { $0 + $1.totalTokens }) == 15 })
        monitor.loadUsageHistory()
        #expect(await waitFor { monitor.state.usageSamples.reduce(0) { $0 + $1.totalTokens } == 15 })
        monitor.refresh()
        try await Task.sleep(for: .milliseconds(40))
        #expect(await subscription.calls == 1)
        currentTime = currentTime.addingTimeInterval(180)
        monitor.refresh()
        #expect(await waitFor { monitor.quotas == [quota] && monitor.state.usageSamples.reduce(0) { $0 + $1.totalTokens } == 15 })
        #expect(await subscription.waitForCalls(2))
        #expect(try repository.load().usageSamples.reduce(0) { $0 + $1.totalTokens } == 15)
    }

    @Test @MainActor func stopCancelsPendingFetchAndPreventsLatePublicationOrPersistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-subscription-cancel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_910_000_000)
        let quota = AIQuotaSnapshot(provider: .muse, window: .weekly, usedPercent: 50, resetsAt: nil, checkedAt: now)
        let subscription = SubscriptionGate(result: .init(quotas: [quota], usageSamples: [
            AIUsageSample(sourceID: "late", provider: .cursor, timestamp: now, inputTokens: 10, outputTokens: 1)]))
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], subscriptionUsageDetector: subscription)
        monitor.refresh()
        #expect(await subscription.waitForCalls(1))
        monitor.stop()
        await subscription.release()
        #expect(await subscription.waitForCompletion())
        try await Task.sleep(for: .milliseconds(40))
        #expect(monitor.quotas.isEmpty && monitor.failedQuotaProviders.isEmpty && monitor.failedUsageProviders.isEmpty)
        #expect(await subscription.sawCancellation)
        let repository = AIStateRepository(directoryURL: root)
        #expect(try repository.load().usageSamples.isEmpty)
        monitor.refresh()
        #expect(await subscription.waitForCalls(2))
        #expect(await waitFor { monitor.quotas == [quota] })
        monitor.stop()
        #expect(monitor.quotas.isEmpty)
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
