import Testing

@testable import ZislaCore
@testable import ZislaKit

struct SideNoticeQueueTests {
    @Test @MainActor
    func compactAINoticesAreNotLimitedByOrdinaryNoticeCapacity() {
        let queue = SideNoticeQueue(capacityPerSide: 3)

        for index in 0..<5 {
            queue.enqueue(
                IslandNotice(
                    id: "ai-active-codex-\(index)",
                    title: "任务 \(index)",
                    side: .right
                ),
                expiresAfter: nil
            )
        }

        let presentation = SideNoticeLayoutEngine().presentation(for: queue.right)
        #expect(presentation.activeAICount == 5)
    }

    @Test @MainActor
    func persistentNoticeStaysUntilExplicitRemoval() async throws {
        let queue = SideNoticeQueue()
        let notice = IslandNotice(id: "ai-active-test", title: "Codex 正在工作", side: .left)

        queue.enqueue(notice, expiresAfter: nil)
        queue.setHovered(false, id: notice.id)
        try await Task.sleep(for: .milliseconds(80))

        #expect(queue.left.map(\.id) == [notice.id])
        queue.remove(id: notice.id)
        #expect(queue.left.isEmpty)
    }

    @Test @MainActor
    func temporaryNoticeStillExpires() async {
        let gate = ExpiryGate()
        let queue = SideNoticeQueue(
            capacityPerSide: 3,
            expirySleeper: { duration in
                try await gate.sleep(for: duration)
            }
        )
        let notice = IslandNotice(id: "temporary-test", title: "临时通知", side: .right)

        queue.enqueue(notice, expiresAfter: 0.02)
        await gate.waitUntilSleeping()
        await gate.release()
        for _ in 0..<20 where !queue.right.isEmpty {
            await Task.yield()
        }

        #expect(queue.right.isEmpty)
    }

    @Test @MainActor
    func updateIfPresentRefreshesVisibleNoticeContent() {
        let queue = SideNoticeQueue()
        let original = IslandNotice(
            id: "activity-update",
            title: "原始标题",
            detail: "原始详情",
            side: .left,
            progress: 0.2
        )
        queue.enqueue(original, expiresAfter: nil)

        let updated = IslandNotice(
            id: "activity-update",
            title: "新标题",
            detail: "新详情",
            side: .left,
            progress: 0.8
        )
        let didUpdate = queue.updateIfPresent(updated)

        #expect(didUpdate)
        #expect(queue.left.map(\.id) == [updated.id])
        #expect(queue.left.first?.title == "新标题")
        #expect(queue.left.first?.detail == "新详情")
        #expect(queue.left.first?.progress == 0.8)
    }

    @Test @MainActor
    func updateIfPresentDoesNotReinsertAfterExpiry() async {
        let gate = ExpiryGate()
        let queue = SideNoticeQueue(
            capacityPerSide: 3,
            expirySleeper: { duration in
                try await gate.sleep(for: duration)
            }
        )
        let notice = IslandNotice(id: "expired-update", title: "即将过期", side: .right)

        queue.enqueue(notice, expiresAfter: 0.03)
        await gate.waitUntilSleeping()
        await gate.release()
        for _ in 0..<20 where !queue.right.isEmpty {
            await Task.yield()
        }
        #expect(queue.right.isEmpty)

        let didUpdate = queue.updateIfPresent(
            IslandNotice(id: notice.id, title: "不应重现", side: .right)
        )

        #expect(!didUpdate)
        #expect(queue.right.isEmpty)
        #expect(queue.left.isEmpty)
    }

    @Test @MainActor
    func updateIfPresentDoesNotRestartExpiry() async {
        let gate = ExpiryGate()
        let notice = IslandNotice(id: "expiry-preserve", title: "倒计时", side: .left)

        let controlledQueue = SideNoticeQueue(
            capacityPerSide: 3,
            expirySleeper: { duration in
                try await gate.sleep(for: duration)
            }
        )
        controlledQueue.enqueue(notice, expiresAfter: 0.3)
        await gate.waitUntilSleeping()

        #expect(controlledQueue.left.map(\.id) == [notice.id])

        let didUpdate = controlledQueue.updateIfPresent(
            IslandNotice(id: notice.id, title: "已刷新", side: .left)
        )
        #expect(didUpdate)
        #expect(controlledQueue.left.first?.title == "已刷新")

        for _ in 0..<5 {
            await Task.yield()
        }
        let callsAfterUpdate = await gate.callCount
        #expect(callsAfterUpdate == 1)

        await gate.release()
        for _ in 0..<20 where !controlledQueue.left.isEmpty {
            await Task.yield()
        }
        #expect(controlledQueue.left.isEmpty)
    }

    @Test @MainActor
    func removesOnlyNoticesMatchingIDPrefix() {
        let queue = SideNoticeQueue()
        queue.enqueue(
            IslandNotice(id: "mail-notification-batch-left", title: "邮件", side: .left),
            expiresAfter: nil
        )
        queue.enqueue(
            IslandNotice(id: "mail-notification-batch-right", title: "1", side: .right),
            expiresAfter: nil
        )
        queue.enqueue(
            IslandNotice(id: "focus-mode-left", title: "睡眠", side: .left),
            expiresAfter: nil
        )

        queue.removeAll(withIDPrefix: "mail-notification-")

        #expect(queue.left.map(\.id) == ["focus-mode-left"])
        #expect(queue.right.isEmpty)
    }
}

private actor ExpiryGate {
    private var callCountValue = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var sleepWaiters: [CheckedContinuation<Void, Never>] = []

    var callCount: Int { callCountValue }

    func sleep(for _: Duration) async throws {
        callCountValue += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            sleepWaiters.append(continuation)
        }
    }

    func waitUntilSleeping() async {
        guard callCountValue == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        let waiters = sleepWaiters
        sleepWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}
