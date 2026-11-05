import Combine
import Foundation
import Testing
import ZislaCore

@testable import Zisla
@testable import ZislaKit

@MainActor
struct UserCarePomodoroNoticeTests {
    @Test(arguments: ["allowed", "care-disabled", "side-disabled", "muted", "hidden"], [false, true])
    func completionNoticeRequiresAllLivePresentationGates(reason: String, petEnabled: Bool) throws {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        var settings = FeatureSettings(userCareEnabled: true, petEnabled: petEnabled)
        switch reason {
        case "care-disabled": settings.userCareEnabled = false
        case "side-disabled": settings.sideNoticesEnabled = false
        case "muted": settings.notificationsMuted = true
        default: break
        }
        AppModel.presentPomodoroCareReminder(.focusCompleted, settings: settings,
            presentationAllowed: reason != "hidden", queue: queue, language: .english)
        if reason == "allowed" {
            let notice = try #require(queue.right.first)
            #expect(notice.id == UserCareService.noticeID && notice.style == .message && notice.side == .right)
            #expect(notice.title == UserCareReminder.focusCompleted.localizedMessage(petEnabled: petEnabled, language: .english))
            #expect(queue.left.isEmpty && queue.right.count == 1)
        } else {
            #expect(queue.left.isEmpty && queue.right.isEmpty)
        }
    }

    @Test
    func completionsReplaceTheExistingCareMessageWithoutAccumulatingOrRemovingOtherNotices() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let settings = FeatureSettings(userCareEnabled: true, petEnabled: true)
        queue.enqueue(IslandNotice(id: "unrelated", title: "Keep this notice"), expiresAfter: nil)
        queue.enqueue(IslandNotice(id: UserCareService.noticeID, title: "Previous routine reminder", style: .message))
        for reminder in [UserCareReminder.focusCompleted, .restCompleted] {
            AppModel.presentPomodoroCareReminder(reminder, settings: settings,
                presentationAllowed: true, queue: queue, language: .simplifiedChinese)
            #expect(queue.right.count == 2)
            #expect(queue.right.first?.id == "unrelated")
            #expect(queue.right.last?.title == reminder.localizedMessage(petEnabled: true, language: .simplifiedChinese))
        }
    }

    @Test
    func completionUsesTheExistingSixSecondExpiry() async {
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
        AppModel.presentPomodoroCareReminder(.restCompleted, settings: FeatureSettings(userCareEnabled: true),
            presentationAllowed: true, queue: queue, language: .english)
        #expect(queue.right.count == 1)
        var scheduledIterator = scheduled.makeAsyncIterator()
        #expect(await scheduledIterator.next() == .seconds(6))
        expiryContinuation.yield(())
        for await notices in queue.$right.values {
            if notices.isEmpty { break }
        }
        #expect(queue.right.isEmpty)
    }
}
