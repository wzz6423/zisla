import Combine
import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

@MainActor
struct ScenarioNotificationQueueTests {
    @Test
    func anUnconfiguredQueuePreservesExistingVisibilityAndNeverCreatesAReview() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        queue.setNotificationScenarios([.focus, .meeting, .screenRecording])
        let notice = IslandNotice(id: "old-behavior", title: "Notice")
        queue.enqueue(notice, expiresAfter: nil)
        #expect(queue.presentationNotices(queue.right, displayIdentifier: "display") == [notice])
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReviewNotice(displayIdentifier: "display") == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func delayedTemporaryNoticesSurviveOrdinaryExpiryWithoutReplayingTheOriginalRow() async {
        let gate = ScenarioExpiryGate(expectedSleepers: 2)
        let queue = SideNoticeQueue(capacityPerSide: 3, expirySleeper: { _ in await gate.sleep() })
        defer { queue.removeAll(); Task { await gate.release() } }
        queue.configureNotificationScenarios(.init(enabled: true), displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.focus])
        queue.enqueue(IslandNotice(id: "saved", title: "Saved"), expiresAfter: 1)
        queue.enqueue(IslandNotice(id: "media-active-expiring", title: "Music", side: .left), expiresAfter: 1)
        let (expired, continuation) = AsyncStream<Void>.makeStream()
        let subscription = queue.$left.combineLatest(queue.$right)
            .filter { $0.0.isEmpty && $0.1.isEmpty }
            .sink { _ in continuation.yield(()) }
        defer { subscription.cancel(); continuation.finish() }
        var expiration = expired.makeAsyncIterator()
        await gate.waitUntilSleeping()
        await gate.release()
        #expect(await expiration.next() != nil)
        #expect(queue.right.isEmpty && queue.left.isEmpty, "Scenario filtering preserves the existing display duration")
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReview(displayIdentifier: "display").map(\.title) == ["Saved"])
        #expect(queue.scenarioReviewNotice(displayIdentifier: "display")?.title == AppLocalization.text("已延后 %ld 条提示", 1))
        #expect(queue.right.isEmpty, "Ending a scene publishes one review entry, never the original expired notice")
    }

    @Test
    func differentDisplayPoliciesDoNotMutateTheSharedVisibleQueue() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let show = NotificationScenarioRules(focus: .init(ordinary: .show))
        queue.configureNotificationScenarios(.init(enabled: true, displayOverrides: ["showing": show]),
            displayIdentifiers: ["quiet", "showing"])
        queue.setNotificationScenarios([.focus])
        let notice = IslandNotice(id: "update", title: "Update")
        queue.enqueue(notice, expiresAfter: nil)
        #expect(queue.right == [notice])
        #expect(queue.presentationNotices(queue.right, displayIdentifier: "quiet").isEmpty)
        #expect(queue.presentationNotices(queue.right, displayIdentifier: "showing") == [notice])
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReview(displayIdentifier: "quiet").count == 1)
        #expect(queue.scenarioReview(displayIdentifier: "showing").isEmpty)
        #expect(queue.presentationNotices(queue.right, displayIdentifier: "quiet").isEmpty)
        #expect(queue.presentationNotices(queue.right, displayIdentifier: "showing") == [notice])
    }

    @Test
    func importantAIAndBatteryEventsPassThroughUntilTheUserOptsOut() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        var settings = NotificationScenarioSettings(enabled: true)
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.meeting])
        let notices = [IslandNotice(id: "ai-active-blocked", title: "Approval", kind: .warning),
            .init(id: "failed", title: "Failure", kind: .error),
            .init(id: "permission", title: "Safety", kind: .warning),
            .init(id: "battery-low", title: "Battery", kind: .warning)]
        notices.forEach { queue.enqueue($0, expiresAfter: nil) }
        #expect(queue.presentationNotices(notices, displayIdentifier: "display") == notices)
        settings.rules.meeting.keepsImportant = false
        queue.configureNotificationScenarios(settings)
        #expect(queue.presentationNotices(notices, displayIdentifier: "display").isEmpty)
        queue.setNotificationScenarios([])
        #expect(queue.presentationNotices(notices, displayIdentifier: "display").contains { $0.id == "ai-active-blocked" })
    }

    @Test
    func sceneOverlapAndConfigurationUpdatesDoNotRefreshOrDuplicateAnOldEvent() {
        let clock = ScenarioTestClock()
        let queue = SideNoticeQueue(now: { clock.date })
        defer { queue.removeAll() }
        let settings = NotificationScenarioSettings(enabled: true)
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.focus])
        queue.enqueue(.init(id: "saved", title: "Saved"), expiresAfter: nil)
        let recorded = clock.date
        clock.date += 30
        queue.setNotificationScenarios([.focus, .meeting])
        queue.configureNotificationScenarios(settings)
        queue.setNotificationScenarios([.meeting])
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty)
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReview(displayIdentifier: "display").count == 1)
        #expect(queue.scenarioReview(displayIdentifier: "display").first?.recordedAt == recorded)
        queue.dismissScenarioReview(displayIdentifier: "display")
        queue.setNotificationScenarios([.meeting])
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty)
        #expect(queue.presentationNotices(queue.right, displayIdentifier: "display").isEmpty)
    }

    @Test
    func anExistingExternalSuccessSweepAndFocusTransitionCannotResurfaceAfterAQuietScene() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let settings = NotificationScenarioSettings(enabled: true,
            displayOverrides: ["showing": .init(meeting: .init(ordinary: .show))])
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["quiet", "showing"])
        let success = IslandNotice(id: "ai-active-finished", title: "Finished", kind: .success)
        queue.recordScenarioEvent(success)
        #expect(queue.isScenarioNoticeVisible(success, displayIdentifier: "quiet"))
        queue.setNotificationScenario(.meeting, active: true)
        #expect(!queue.isScenarioNoticeVisible(success, displayIdentifier: "quiet"))
        #expect(queue.isScenarioNoticeVisible(success, displayIdentifier: "showing"))
        queue.setNotificationScenarios([])
        #expect(!queue.isScenarioNoticeVisible(success, displayIdentifier: "quiet"))
        #expect(queue.isScenarioNoticeVisible(success, displayIdentifier: "showing"))
        queue.setNotificationScenario(.meeting, active: true)
        let transition = IslandNotice(id: "focus-transition", title: "Focus changed", side: .left)
        queue.enqueue(transition, expiresAfter: nil)
        queue.setNotificationScenarios([])
        #expect(queue.presentationNotices(queue.left, displayIdentifier: "quiet").isEmpty)
        #expect(queue.scenarioReview(displayIdentifier: "quiet").map(\.id) == ["focus-transition"])
        #expect(queue.scenarioReview(displayIdentifier: "showing").isEmpty)
        queue.releaseScenarioEventVisibility(id: success.id)
    }

    @Test
    func liveStatusesResumeOnSceneEndAndChangingRulesToShowWithoutOldSuccessRows() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        var settings = NotificationScenarioSettings(enabled: true)
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.focus])
        let statuses = [IslandNotice(id: "media-active-left", title: "Music", side: .left),
            .init(id: "focus-countdown-left", title: "Focus", side: .left),
            .init(id: "focus-mode-right", title: "ON", kind: .success),
            .init(id: "ai-active-running", title: "Working"),
            .init(id: "meeting-countdown-left", title: "Meeting", side: .left)]
        statuses.forEach { queue.enqueue($0, expiresAfter: nil) }
        let saved = IslandNotice(id: "saved", title: "Saved", kind: .success)
        queue.enqueue(saved, expiresAfter: nil)
        #expect(queue.presentationNotices(statuses + [saved], displayIdentifier: "display").isEmpty)
        settings.rules.focus.ordinary = .show
        queue.configureNotificationScenarios(settings)
        #expect(queue.presentationNotices(statuses + [saved], displayIdentifier: "display") == statuses)
        #expect(queue.scenarioReview(displayIdentifier: "display").map(\.id) == ["saved"])
        queue.setNotificationScenarios([])
        #expect(queue.presentationNotices(statuses + [saved], displayIdentifier: "display") == statuses)
    }

    @Test
    func explicitRemovalCancelsDeferredActivitiesIncludingAlreadyExpiredSourcePrefixes() async {
        let gate = ScenarioExpiryGate()
        let queue = SideNoticeQueue(capacityPerSide: 3, expirySleeper: { _ in await gate.sleep() })
        defer { queue.removeAll() }
        var settings = NotificationScenarioSettings(enabled: true)
        settings.rules.focus.keepsImportant = false
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.focus])
        queue.enqueue(.init(id: "ai-active-ended", title: "Blocked", kind: .warning), expiresAfter: nil)
        queue.enqueue(.init(id: "mail-notification-old-left", title: "Mail", side: .left), expiresAfter: 1)
        await gate.waitUntilSleeping()
        await gate.release()
        for _ in 0..<20 where queue.left.contains(where: { $0.id == "mail-notification-old-left" }) { await Task.yield() }
        queue.remove(id: "ai-active-ended")
        queue.removeAll(withIDPrefix: "mail-notification-")
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty)
        #expect(queue.scenarioReviewNotice(displayIdentifier: "display") == nil)
    }

    @Test
    func pairUpdatesAreDeduplicatedAndFiftyNewestItemsBoundTheReview() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        queue.configureNotificationScenarios(.init(enabled: true), displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.screenRecording])
        queue.enqueue(.init(id: "mail-notification-pair-left", title: "Sender", side: .left), expiresAfter: nil)
        queue.enqueue(.init(id: "mail-notification-pair-right", title: "Body"), expiresAfter: nil)
        queue.enqueue(.init(id: "mail-notification-pair-right", title: "Updated body"), expiresAfter: nil)
        queue.setNotificationScenarios([])
        let pair = queue.scenarioReview(displayIdentifier: "display")
        #expect(pair.count == 1 && pair.first?.title == "Sender" && pair.first?.detail == "Updated body")
        queue.setNotificationScenarios([.focus])
        for index in 0..<80 { queue.recordScenarioEvent(.init(id: "event-\(index)", title: "Event \(index)")) }
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReview(displayIdentifier: "display").count == 50)
        #expect(queue.scenarioReview(displayIdentifier: "display").first?.id == "event-30")
        #expect(queue.scenarioReview(displayIdentifier: "display").last?.id == "event-79")
    }

    @Test
    func disconnectedDisplayDropsItsBacklogWhileStablePoliciesSurviveDisplayIDChanges() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let settings = NotificationScenarioSettings(enabled: true,
            displayOverrides: ["stable-external": .init(focus: .init(ordinary: .mute))])
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["stable-external", "built-in"])
        queue.setNotificationScenarios([.focus])
        queue.enqueue(.init(id: "saved", title: "Saved"), expiresAfter: nil)
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["stable-external"])
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["stable-external", "built-in"])
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReview(displayIdentifier: "built-in").isEmpty)
        #expect(queue.scenarioReview(displayIdentifier: "stable-external").isEmpty)
        let frame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let before = ScreenSnapshot(displayID: 10, frame: frame, visibleFrame: frame, notificationPolicyIdentifier: "stable-external")
        let after = ScreenSnapshot(displayID: 99, frame: frame, visibleFrame: frame, notificationPolicyIdentifier: "stable-external")
        #expect(before.notificationScopeIdentifier == after.notificationScopeIdentifier)
        queue.setNotificationScenarios([.focus])
        #expect(queue.notificationBehavior(for: .ordinary, displayIdentifier: after.notificationScopeIdentifier) == .mute)
        #expect(ScreenSnapshot(displayID: 99, frame: frame, visibleFrame: frame).notificationScopeIdentifier == "session:99")
    }

    @Test
    func staleItemsExpireAndDisableClearsTheBacklogWithoutReplay() {
        let clock = ScenarioTestClock()
        let queue = SideNoticeQueue(now: { clock.date })
        defer { queue.removeAll() }
        var settings = NotificationScenarioSettings(enabled: true)
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.focus])
        queue.enqueue(.init(id: "old", title: "Old"), expiresAfter: nil)
        clock.date += 4 * 60 * 60
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty)
        queue.setNotificationScenarios([.focus])
        queue.enqueue(.init(id: "new", title: "New"), expiresAfter: nil)
        settings.enabled = false
        queue.configureNotificationScenarios(settings)
        #expect(queue.presentationNotices(queue.right, displayIdentifier: "display") == queue.right)
        #expect(queue.scenarioReviewNotice(displayIdentifier: "display") == nil)
        settings.enabled = true
        queue.configureNotificationScenarios(settings)
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty)
    }

    @Test
    func suppressedCareFeedbackUsesTheCurrentDisplayRuleAndNeverReappearsByItself() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let settings = NotificationScenarioSettings(enabled: true,
            displayOverrides: ["showing": .init(meeting: .init(ordinary: .show))])
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["quiet", "showing"])
        queue.setNotificationScenarios([.meeting])
        let care = IslandNotice(id: "user-care-water", title: "Water")
        #expect(!queue.suppressScenarioFeedback(care, displayIdentifier: "showing"))
        #expect(queue.suppressScenarioFeedback(care, displayIdentifier: "quiet"))
        #expect(queue.suppressScenarioFeedback(care, displayIdentifier: nil), "An unknown active display uses the global rule")
        queue.setNotificationScenarios([])
        #expect(queue.left.isEmpty && queue.right.isEmpty)
        #expect(queue.scenarioReview(displayIdentifier: "quiet").map(\.id) == [care.id])
        #expect(queue.scenarioReview(displayIdentifier: "showing").isEmpty)
        queue.dismissScenarioReview(displayIdentifier: "quiet")
        queue.setNotificationScenarios([.meeting])
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReview(displayIdentifier: "quiet").isEmpty)
    }

    @Test
    func switchingFromDeferredToMutedDiscardsTheBacklogAndOnlyNewEventsCanShowLater() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        var settings = NotificationScenarioSettings(enabled: true)
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.meeting])
        queue.enqueue(.init(id: "old", title: "Old"), expiresAfter: nil)
        settings.rules.meeting.ordinary = .mute
        queue.configureNotificationScenarios(settings)
        queue.enqueue(.init(id: "muted", title: "Muted"), expiresAfter: nil)
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty)
        #expect(queue.presentationNotices(queue.right, displayIdentifier: "display").isEmpty)
        let fresh = IslandNotice(id: "fresh", title: "Fresh")
        queue.enqueue(fresh, expiresAfter: nil)
        #expect(queue.presentationNotices(queue.right, displayIdentifier: "display") == [fresh])
    }

    @Test
    func boundedTextAndReviewExpiryPreventLargePayloadRetention() {
        let clock = ScenarioTestClock()
        let queue = SideNoticeQueue(now: { clock.date })
        defer { queue.removeAll() }
        queue.configureNotificationScenarios(.init(enabled: true), displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.meeting])
        queue.recordScenarioEvent(.init(id: "large", title: String(repeating: "字", count: 5_000),
            detail: String(repeating: "x", count: 10_000), artworkData: Data(repeating: 42, count: 1_024)))
        queue.releaseScenarioEventVisibility(id: "large")
        queue.setNotificationScenarios([])
        let item = queue.scenarioReview(displayIdentifier: "display").first
        #expect(item?.title.count == 160 && item?.detail?.count == 320)
        clock.date += 4 * 60 * 60
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty)
        #expect(queue.scenarioReviewNotice(displayIdentifier: "display") == nil)
    }

    @Test
    func anOverlappingMutedSceneDiscardsExpiredDeferredEventsWhileLiveFailuresResume() async {
        let gate = ScenarioExpiryGate()
        let queue = SideNoticeQueue(capacityPerSide: 3, expirySleeper: { _ in await gate.sleep() })
        defer { queue.removeAll() }
        var settings = NotificationScenarioSettings(enabled: true)
        settings.rules.screenRecording = .init(ordinary: .mute, keepsImportant: false)
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.focus])
        queue.enqueue(.init(id: "expired", title: "Expired"), expiresAfter: 1)
        await gate.waitUntilSleeping()
        await gate.release()
        for _ in 0..<20 where !queue.right.isEmpty { await Task.yield() }
        #expect(queue.right.isEmpty)
        let failure = IslandNotice(id: "ai-active-error", title: "Failed", kind: .error)
        queue.enqueue(failure, expiresAfter: nil)
        queue.setNotificationScenarios([.focus, .screenRecording])
        #expect(queue.presentationNotices(queue.right, displayIdentifier: "display").isEmpty)
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty)
        #expect(queue.presentationNotices(queue.right, displayIdentifier: "display") == [failure])
    }

    @Test
    func aCancelledOldExpiryCannotRemoveAReplacementNotice() async {
        let gate = ScenarioExpiryGate()
        let queue = SideNoticeQueue(capacityPerSide: 3, expirySleeper: { _ in await gate.sleep() })
        defer { queue.removeAll() }
        let original = IslandNotice(id: "replace", title: "Original")
        let replacement = IslandNotice(id: original.id, title: "Replacement")
        queue.enqueue(original, expiresAfter: 1)
        await gate.waitUntilSleeping()
        queue.enqueue(replacement, expiresAfter: nil)
        await gate.release()
        for _ in 0..<20 { await Task.yield() }
        #expect(queue.right == [replacement])
    }

    @Test
    func sceneReconfigurationIsIdempotentAndPublishesChangesOutsideTheVisibleQueue() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        var publications = 0
        let observer = queue.objectWillChange.sink { publications += 1 }
        let settings = NotificationScenarioSettings(enabled: true)
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.meeting])
        let configuredCount = publications
        queue.configureNotificationScenarios(settings, displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.meeting])
        #expect(publications == configuredCount)
        queue.recordScenarioEvent(.init(id: "external", title: "External"))
        #expect(publications > configuredCount && queue.right.isEmpty)
        queue.setNotificationScenarios([])
        let endedCount = publications
        queue.dismissScenarioReview(displayIdentifier: "display")
        #expect(publications > endedCount && queue.scenarioReview(displayIdentifier: "display").isEmpty)
        withExtendedLifetime(observer) {}
    }
}

@MainActor
private final class ScenarioTestClock { var date = Date(timeIntervalSince1970: 10_000) }

private actor ScenarioExpiryGate {
    private let expectedSleepers: Int
    private var sleeping: [AsyncStream<Void>.Continuation] = []
    private let entered = AsyncStream<Int>.makeStream()
    private var released = false

    init(expectedSleepers: Int = 1) { self.expectedSleepers = expectedSleepers }

    func sleep() async {
        guard !released else { return }
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        sleeping.append(continuation)
        entered.continuation.yield(sleeping.count)
        var iterator = stream.makeAsyncIterator()
        await iterator.next()
    }
    func waitUntilSleeping() async {
        if sleeping.count == expectedSleepers { return }
        for await count in entered.stream where count == expectedSleepers { return }
    }
    func release() {
        released = true
        sleeping.forEach { $0.finish() }
        sleeping.removeAll()
        entered.continuation.finish()
    }
}
