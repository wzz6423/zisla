import Foundation
import ZislaCore

struct UserCareFeedback {
    private var ownedReminder: UserCareReminder?
    private var lastNoteFeedbackUptime: TimeInterval?

    func message(
        for reminder: UserCareReminder,
        settings: FeatureSettings,
        presentationAllowed: Bool,
        currentMessage: String?,
        uptime: TimeInterval,
        language: AppLanguage,
        throttlesNoteUpdates: Bool = false
    ) -> String? {
        guard settings.userCareEnabled, presentationAllowed,
              currentMessage == nil || ownedReminder != nil else { return nil }
        if [.focusCompleted, .restCompleted].contains(reminder), settings.notificationsMuted { return nil }
        if throttlesNoteUpdates, reminder == .noteUpdated, let lastNoteFeedbackUptime,
           uptime < lastNoteFeedbackUptime + 30 { return nil }
        return reminder.localizedMessage(petEnabled: settings.petEnabled, language: language)
    }

    mutating func didPresent(_ reminder: UserCareReminder, at uptime: TimeInterval) {
        ownedReminder = reminder
        if [.noteCreated, .noteUpdated].contains(reminder) { lastNoteFeedbackUptime = uptime }
    }

    mutating func messageDidChange() {
        ownedReminder = nil
    }

    mutating func dismiss(routineOnly: Bool = false) -> Bool {
        guard let ownedReminder else { return false }
        if routineOnly, [.focusCompleted, .restCompleted, .noteCreated, .noteUpdated].contains(ownedReminder) {
            return false
        }
        self.ownedReminder = nil
        return true
    }
}
