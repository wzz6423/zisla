import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

@MainActor
struct AIQuotaNoticeTests {
    private let now = AIQuotaFixtures.now

    private func snapshot(_ percentages: [Double], at date: Date? = nil) -> AIQuotaSnapshot {
        AIQuotaSnapshot(accounts: percentages.enumerated().map { index, percent in
            AIQuotaAccount(id: "account-\(index)", providerID: "codex", label: "Account \(index)", windows: [
                AIQuotaWindow(id: "weekly", label: "每周", remainingPercent: percent),
            ], observedAt: date ?? now)
        })
    }

    @Test
    func bothWingsShareProviderAndPercentageForExactlyFiveSecondsThenRestoreActivity() async throws {
        let gate = AIQuotaSleepGate()
        let expiry = AIQuotaSleepGate()
        let queue = SideNoticeQueue(capacityPerSide: 1, expirySleeper: { await expiry.sleep($0) })
        let controller = AIQuotaNoticeController(queue: queue, sleeper: { await gate.sleep($0) }, clock: { AIQuotaFixtures.now })
        queue.enqueue(IslandNotice(id: "ai-active-existing", title: "Running", side: .left), expiresAfter: nil)
        controller.consume(snapshot([100]), enabled: true, at: now)
        #expect(queue.right.isEmpty)
        controller.consume(snapshot([79]), enabled: true, at: now)
        #expect(await aiQuotaEventually { await gate.durations.count == 1 })
        let left = try #require(queue.left.first { $0.id.hasPrefix("ai-quota-") })
        let right = try #require(queue.right.first)
        #expect(left.side == .left && right.side == .right)
        #expect(left.metadata == right.metadata)
        #expect(left.metadata?["providerID"] == "codex")
        #expect(left.metadata?["remaining"] == "79%")
        #expect(right.title == "79%")
        #expect(await gate.durations == [.seconds(5)])
        #expect(await aiQuotaEventually { await expiry.durations.count == 2 })
        #expect(await expiry.durations == [.seconds(5), .seconds(5)])
        let layout = SideNoticeLayoutEngine()
        #expect(SideNoticeLayoutEngine.selectedCompactStatusPriority(for: queue.left + queue.right, settings: FeatureSettings()) == .transient)
        #expect(layout.presentation(for: queue.left).ordinaryNotices.isEmpty)
        let onlyQuota = layout.presentation(for: [left])
        #expect(layout.presentation(for: queue.left).panelSize.width == onlyQuota.panelSize.width)
        await gate.release(0)
        #expect(await aiQuotaEventually { @MainActor in queue.right.isEmpty })
        #expect(queue.left.map(\.id) == ["ai-active-existing"])
        #expect(SideNoticeLayoutEngine.selectedCompactStatusPriority(for: queue.left, settings: FeatureSettings()) == .aiActivity)
        controller.stop()
        queue.removeAll()
        await expiry.releaseAll()
    }

    @Test
    func anOldSleeperIgnoringCancellationCannotDeleteANewNotice() async throws {
        let gate = AIQuotaSleepGate()
        let expiry = AIQuotaSleepGate()
        let queue = SideNoticeQueue(capacityPerSide: 3, expirySleeper: { await expiry.sleep($0) })
        let controller = AIQuotaNoticeController(queue: queue, sleeper: { await gate.sleep($0) }, clock: { AIQuotaFixtures.now })
        controller.consume(snapshot([100]), enabled: true, at: now)
        controller.consume(snapshot([79]), enabled: true, at: now)
        #expect(await aiQuotaEventually { await gate.durations.count == 1 })
        controller.stop()
        controller.consume(snapshot([100]), enabled: true, at: now)
        controller.consume(snapshot([59]), enabled: true, at: now)
        #expect(await aiQuotaEventually { await gate.durations.count == 2 })
        let newIDs = (queue.left + queue.right).map(\.id)
        await gate.release(0)
        for _ in 0..<50 { await Task.yield() }
        #expect((queue.left + queue.right).map(\.id) == newIDs)
        #expect(queue.right.first?.title == "59%")
        controller.stop()
        #expect(queue.left.isEmpty && queue.right.isEmpty)
        await gate.releaseAll()
        await expiry.releaseAll()
    }

    @Test
    func disablingClearsPendingAlertsAndReenablingStartsWithABaseline() async {
        let gate = AIQuotaSleepGate()
        let expiry = AIQuotaSleepGate()
        let queue = SideNoticeQueue(capacityPerSide: 3, expirySleeper: { await expiry.sleep($0) })
        let controller = AIQuotaNoticeController(queue: queue, sleeper: { await gate.sleep($0) }, clock: { AIQuotaFixtures.now })
        controller.consume(snapshot([100, 100]), enabled: true, at: now)
        controller.consume(snapshot([10, 5]), enabled: true, at: now)
        #expect(await aiQuotaEventually { await gate.durations.count == 1 })
        #expect(queue.right.first?.title == "5%")
        controller.consume(snapshot([10, 5]), enabled: false, at: now)
        #expect(queue.left.isEmpty && queue.right.isEmpty)
        controller.consume(snapshot([0, 0]), enabled: true, at: now)
        #expect(queue.left.isEmpty && queue.right.isEmpty)
        controller.stop()
        await gate.releaseAll()
        await expiry.releaseAll()
    }

    @Test
    func pendingAlertsAreBoundedAndExpireAfterSleep() async {
        let gate = AIQuotaSleepGate()
        let expiry = AIQuotaSleepGate()
        let clock = AIQuotaTestClock(now)
        let queue = SideNoticeQueue(capacityPerSide: 3, expirySleeper: { await expiry.sleep($0) })
        let controller = AIQuotaNoticeController(queue: queue, sleeper: { await gate.sleep($0) }, clock: { clock.now })
        controller.consume(snapshot(Array(repeating: 100, count: 100)), enabled: true, at: now)
        controller.consume(snapshot(Array(repeating: 79, count: 100)), enabled: true, at: now)
        for index in 0..<AIQuotaNoticeController.maximumPending {
            #expect(await aiQuotaEventually { await gate.durations.count == index + 1 })
            await gate.release(index)
        }
        #expect(await aiQuotaEventually { @MainActor in queue.right.isEmpty })
        #expect(await gate.durations.count == AIQuotaNoticeController.maximumPending)
        controller.stop()
        controller.consume(snapshot([100, 100]), enabled: true, at: now)
        controller.consume(snapshot([20, 10]), enabled: true, at: now)
        let count = AIQuotaNoticeController.maximumPending + 1
        #expect(await aiQuotaEventually { await gate.durations.count == count })
        clock.advance(601)
        await gate.release(count - 1)
        #expect(await aiQuotaEventually { @MainActor in queue.right.isEmpty })
        #expect(await gate.durations.count == count)
        controller.stop()
        await gate.releaseAll()
        await expiry.releaseAll()
    }
}

private final class AIQuotaTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ date: Date) { value = date }
    var now: Date { lock.withLock { value } }
    func advance(_ interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
}
