import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct UserCarePomodoroNoticeTests {
    @Test(arguments: AppLanguage.allCases, [false, true])
    func islandCompletionAndNoteMessagesUseTheCurrentLanguageAndPetVoice(language: AppLanguage, petEnabled: Bool) {
        let fixture = UserCareFeedbackFixture()
        fixture.language = language
        fixture.settings.petEnabled = petEnabled
        for reminder in [UserCareReminder.focusCompleted, .restCompleted, .noteCreated, .noteUpdated] {
            fixture.uptime += 30
            #expect(fixture.present(reminder))
            #expect(fixture.message == reminder.localizedMessage(petEnabled: petEnabled, language: language))
        }
    }

    @Test(arguments: [UserCareReminder.focusCompleted, .restCompleted])
    func mutedCompletionCannotBypassTheExistingNotificationPreference(reminder: UserCareReminder) {
        let fixture = UserCareFeedbackFixture()
        fixture.settings.notificationsMuted = true
        #expect(!fixture.present(reminder))
        #expect(fixture.message == nil)
        #expect(fixture.present(.rest), "Silent periodic care remains available while notification sounds are muted")
        #expect(fixture.present(.noteCreated), "A direct save acknowledgement is silent interface feedback")
    }

    @Test
    func successiveCompletionsReplaceCareWithoutTakingOverAnOrdinaryError() {
        let fixture = UserCareFeedbackFixture()
        #expect(fixture.present(.rest))
        #expect(fixture.present(.focusCompleted))
        #expect(fixture.message == UserCareReminder.focusCompleted.localizedMessage(petEnabled: true, language: .english))
        #expect(fixture.present(.restCompleted))
        fixture.message = "A system error"
        #expect(!fixture.present(.focusCompleted))
        fixture.dismiss()
        #expect(fixture.message == "A system error")
    }
}
