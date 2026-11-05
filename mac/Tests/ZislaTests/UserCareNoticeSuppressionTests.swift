import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct UserCareNoticeSuppressionTests {
    @Test(arguments: [UserCareReminder.rest, .focusCompleted, .noteCreated])
    func optInAndCurrentIslandAvailabilityGateEveryCareMessage(reminder: UserCareReminder) {
        let fixture = UserCareFeedbackFixture()
        fixture.settings.userCareEnabled = false
        #expect(!fixture.present(reminder))
        fixture.settings.userCareEnabled = true
        fixture.allowed = false
        #expect(!fixture.present(reminder))
        fixture.allowed = true
        fixture.settings.sideNoticesEnabled = false
        #expect(fixture.present(reminder), "Island care must remain independent of side-wing notifications")
    }

    @Test(arguments: [UserCareReminder.rest, .focusCompleted, .noteCreated])
    func ordinaryMessagesKeepPriorityAndRevokeCareOwnershipEvenForIdenticalText(reminder: UserCareReminder) {
        let fixture = UserCareFeedbackFixture()
        fixture.message = "An ordinary error"
        #expect(!fixture.present(reminder))
        fixture.dismiss()
        #expect(fixture.message == "An ordinary error")
        fixture.message = nil
        #expect(fixture.present(reminder))
        let sameText = fixture.message
        fixture.message = sameText
        fixture.dismiss()
        #expect(fixture.message == sameText, "An external setter owns its message even when its text is identical")
        #expect(!fixture.present(.water))
    }

    @Test(arguments: [UserCareReminder.focusCompleted, .restCompleted, .noteCreated, .noteUpdated])
    func routineCancellationPreservesEventFeedbackAndExplicitSuppressionClearsIt(reminder: UserCareReminder) {
        let fixture = UserCareFeedbackFixture()
        #expect(fixture.present(reminder))
        let message = fixture.message
        fixture.dismiss(routineOnly: true)
        #expect(fixture.message == message)
        fixture.dismiss()
        #expect(fixture.message == nil)
        fixture.dismiss()
        #expect(fixture.message == nil)
    }

    @Test
    func routineCancellationClearsOnlyItsCurrentCareMessage() {
        let fixture = UserCareFeedbackFixture()
        #expect(fixture.present(.rest))
        fixture.dismiss(routineOnly: true)
        #expect(fixture.message == nil)
        #expect(fixture.present(.water))
        fixture.message = "A later save error"
        fixture.dismiss(routineOnly: true)
        #expect(fixture.message == "A later save error")
        fixture.allowed = false
        fixture.message = nil
        #expect(!fixture.present(.eyes))
        fixture.allowed = true
        #expect(fixture.message == nil, "Ending suppression must not replay discarded care")
    }

    @Test
    func noteAutosavesAreThrottledFromActualFeedbackAndCreationCanPresentImmediately() {
        let fixture = UserCareFeedbackFixture()
        #expect(fixture.present(.noteCreated))
        fixture.message = nil
        fixture.uptime = 29.999
        #expect(!fixture.present(.noteUpdated, throttlesNoteUpdates: true))
        #expect(fixture.message == nil)
        fixture.uptime = 30
        #expect(fixture.present(.noteUpdated, throttlesNoteUpdates: true))
        fixture.message = nil
        fixture.uptime = 31
        #expect(!fixture.present(.noteUpdated, throttlesNoteUpdates: true))
        #expect(fixture.present(.noteCreated))
        fixture.message = nil
        fixture.uptime = 60.999
        #expect(!fixture.present(.noteUpdated, throttlesNoteUpdates: true))
        fixture.uptime = 61
        #expect(fixture.present(.noteUpdated, throttlesNoteUpdates: true))
    }

    @Test
    func explicitContextNoteSavesAreNotThrottledLikeAutomaticQuickNoteSaves() {
        let fixture = UserCareFeedbackFixture()
        #expect(fixture.present(.noteCreated))
        fixture.uptime = 1
        #expect(fixture.present(.noteUpdated))
        #expect(fixture.message == UserCareReminder.noteUpdated.localizedMessage(petEnabled: true, language: .english))
    }

    @Test
    func suppressedOrBlockedUpdatesDoNotConsumeTheNextFeedbackWindow() {
        let fixture = UserCareFeedbackFixture()
        fixture.message = "Existing error"
        #expect(!fixture.present(.noteUpdated, throttlesNoteUpdates: true))
        fixture.message = nil
        fixture.allowed = false
        #expect(!fixture.present(.noteUpdated, throttlesNoteUpdates: true))
        fixture.allowed = true
        #expect(fixture.present(.noteUpdated, throttlesNoteUpdates: true))
    }
}

final class UserCareFeedbackFixture {
    var feedback = UserCareFeedback()
    var settings = FeatureSettings(userCareEnabled: true, petEnabled: true)
    var allowed = true
    var uptime: TimeInterval = 0
    var language = AppLanguage.english
    var message: String? {
        didSet { feedback.messageDidChange() }
    }

    @discardableResult
    func present(_ reminder: UserCareReminder, throttlesNoteUpdates: Bool = false) -> Bool {
        guard let message = feedback.message(for: reminder, settings: settings,
            presentationAllowed: allowed, currentMessage: self.message, uptime: uptime, language: language,
            throttlesNoteUpdates: throttlesNoteUpdates) else { return false }
        self.message = message
        feedback.didPresent(reminder, at: uptime)
        return true
    }

    func dismiss(routineOnly: Bool = false) {
        if feedback.dismiss(routineOnly: routineOnly) { message = nil }
    }
}
