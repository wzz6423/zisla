import Combine
import Foundation
import Testing
import ZislaCore

@testable import ZislaKit

@MainActor
struct LowBatteryNoticeTests {
    @Test
    func crossingTwentyPercentQueuesCompactBatteryWarning() throws {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let controller = LowBatteryNoticeController(queue: queue)

        controller.update(snapshot: snapshot(0.201), enabled: true)
        #expect(queue.left.isEmpty)
        controller.update(snapshot: snapshot(0.2), enabled: true)

        let notice = try #require(queue.left.first)
        #expect(queue.left.count == 1)
        #expect(queue.right.isEmpty)
        #expect(notice.id == LowBatteryNoticeController.noticeID)
        #expect(notice.title == "电池电量低")
        #expect(notice.detail == "20%")
        #expect(notice.kind == .warning)
        #expect(notice.style == .status)
    }

    @Test
    func startupBelowThresholdIncludesZeroPercent() {
        for level in [0.0, 0.05, 0.1, 0.19] {
            let queue = SideNoticeQueue()
            defer { queue.removeAll() }
            LowBatteryNoticeController(queue: queue).update(snapshot: snapshot(level), enabled: true)
            #expect(queue.left.first?.detail == "\(Int((level * 100).rounded()))%")
        }
    }

    @Test
    func duplicateUpdatesDoNotExtendExpiryOrReappearAfterExpiry() async throws {
        let (scheduled, scheduledContinuation) = AsyncStream<Duration>.makeStream()
        let (expiry, expiryContinuation) = AsyncStream<Void>.makeStream()
        let queue = SideNoticeQueue(capacityPerSide: 3, expirySleeper: { duration in
            scheduledContinuation.yield(duration)
            var iterator = expiry.makeAsyncIterator()
            _ = await iterator.next()
        })
        defer {
            queue.removeAll()
            scheduledContinuation.finish()
            expiryContinuation.finish()
        }
        let controller = LowBatteryNoticeController(queue: queue)
        let began = Date(timeIntervalSince1970: 1_000)
        controller.update(snapshot: snapshot(0.2), enabled: true, at: began)
        try #require(queue.left.first != nil)
        var scheduledIterator = scheduled.makeAsyncIterator()
        #expect(await scheduledIterator.next() == .seconds(6))

        controller.update(snapshot: snapshot(0.18), enabled: true, at: began.addingTimeInterval(3))
        #expect(queue.left.count == 1)
        #expect(queue.left.first?.detail == "18%")
        #expect(queue.left.first?.createdAt == began)

        expiryContinuation.yield(())
        for await notices in queue.$left.values {
            if notices.isEmpty { break }
        }
        controller.update(snapshot: snapshot(0.17), enabled: true)
        #expect(queue.left.isEmpty)
    }

    @Test
    func powerConnectionAndChargeHoldSuppressWarningWithoutConsumingFirstAlert() {
        for (pluggedIn, charging) in [(true, true), (true, false), (false, true)] {
            let queue = SideNoticeQueue()
            defer { queue.removeAll() }
            let controller = LowBatteryNoticeController(queue: queue)
            controller.update(
                snapshot: snapshot(0.1, pluggedIn: pluggedIn, charging: charging),
                enabled: true
            )
            #expect(queue.left.isEmpty)
            controller.update(snapshot: snapshot(0.1), enabled: true)
            #expect(queue.left.first?.detail == "10%")
        }
    }

    @Test
    func pluggingInClearsWarningWithoutRepeatingWhenUnpluggedAtSameLowLevel() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let controller = LowBatteryNoticeController(queue: queue)
        controller.update(snapshot: snapshot(0.2), enabled: true)
        controller.update(snapshot: snapshot(0.2, pluggedIn: true), enabled: true)
        #expect(queue.left.isEmpty)
        controller.update(snapshot: snapshot(0.19), enabled: true)
        #expect(queue.left.isEmpty)
    }

    @Test
    func recoveredBatteryArmsNextLowBatteryEpisode() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let controller = LowBatteryNoticeController(queue: queue)
        controller.update(snapshot: snapshot(0.2), enabled: true)
        controller.update(snapshot: snapshot(0.4, pluggedIn: true), enabled: true)
        #expect(queue.left.isEmpty)
        controller.update(snapshot: snapshot(0.2), enabled: true)
        #expect(queue.left.first?.detail == "20%")
    }

    @Test
    func disabledNoticesStaySilentAndDoNotConsumeFirstAlert() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let controller = LowBatteryNoticeController(queue: queue)
        controller.update(snapshot: snapshot(0.15), enabled: false)
        #expect(queue.left.isEmpty)
        controller.update(snapshot: snapshot(0.15), enabled: true)
        #expect(queue.left.first?.detail == "15%")
        controller.update(snapshot: snapshot(0.15), enabled: false)
        #expect(queue.left.isEmpty)
        controller.update(snapshot: snapshot(0.15), enabled: true)
        #expect(queue.left.isEmpty)
    }

    @Test
    func missingAndInvalidReadingsDoNotCreateOrRearmWarnings() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let controller = LowBatteryNoticeController(queue: queue)
        let invalid = [Double.nan, Double.infinity, -Double.infinity, -0.1, 1.1].map { level in
            var value = snapshot(0.1)
            value.level = level
            return value
        }
        for reading in [nil] + invalid.map(Optional.some) {
            controller.update(snapshot: reading, enabled: true)
            #expect(queue.left.isEmpty)
        }
        controller.update(snapshot: snapshot(0.1), enabled: true)
        #expect(queue.left.count == 1)
        for reading in [nil] + invalid.map(Optional.some) {
            controller.update(snapshot: reading, enabled: true)
            #expect(queue.left.isEmpty)
            controller.update(snapshot: snapshot(0.1), enabled: true)
            #expect(queue.left.isEmpty)
        }
    }

    @Test
    func clearingBatteryWarningPreservesUnrelatedNotices() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let controller = LowBatteryNoticeController(queue: queue)
        let ordinary = IslandNotice(id: "ordinary", title: "Other event", side: .left)
        queue.enqueue(ordinary, expiresAfter: nil)
        controller.update(snapshot: snapshot(0.1), enabled: true)
        controller.update(snapshot: nil, enabled: true)
        #expect(queue.left == [ordinary])
    }

    @Test
    func lowBatteryWarningDoesNotEvictOrdinaryNoticeAtCapacity() {
        let queue = SideNoticeQueue(capacityPerSide: 1)
        defer { queue.removeAll() }
        let ordinary = IslandNotice(id: "ordinary", title: "Other event", side: .left)
        queue.enqueue(ordinary, expiresAfter: nil)
        LowBatteryNoticeController(queue: queue).update(snapshot: snapshot(0.2), enabled: true)
        #expect(queue.left.map(\.id) == [ordinary.id, LowBatteryNoticeController.noticeID])
    }

    @Test
    func lowBatteryUsesTransientPriorityAndStaysOutOfOrdinaryRows() throws {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        LowBatteryNoticeController(queue: queue).update(snapshot: snapshot(0.2), enabled: true)
        let engine = SideNoticeLayoutEngine()
        var settings = FeatureSettings.default
        settings.compactStatusPriority = [.media, .transient]
        let media = IslandNotice(id: "media-active-left", title: "Music", side: .left)
        #expect(SideNoticeLayoutEngine.selectedCompactStatusPriority(
            for: [media] + queue.left,
            settings: settings
        ) == .transient)
        let compact = engine.presentation(for: queue.left)
        #expect(compact.ordinaryNotices.isEmpty)
        let hidden = engine.presentation(for: queue.left, compactWingsEnabled: false)
        #expect(hidden.panelSize == .zero)

        let physical = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )
        let simulated = ScreenSnapshot(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        for screen in [physical, simulated] {
            let frame = try #require(engine.compactBarFrame(for: screen, notices: queue.left, settings: settings))
            #expect(frame.width == 240)
        }

        let olderHeadphones = IslandNotice(
            id: "headphone-connection-test",
            title: "Headphones",
            createdAt: .distantPast,
            style: .headphone
        )
        let frame = try #require(engine.compactBarFrame(
            for: physical,
            notices: [olderHeadphones] + queue.left,
            settings: settings
        ))
        #expect(frame.width == 240)
    }

    private func snapshot(_ level: Double, pluggedIn: Bool = false, charging: Bool = false) -> BatterySnapshot {
        BatterySnapshot(
            level: level,
            isCharging: charging,
            isPluggedIn: pluggedIn,
            isCharged: false,
            timeRemainingMinutes: nil
        )
    }
}
