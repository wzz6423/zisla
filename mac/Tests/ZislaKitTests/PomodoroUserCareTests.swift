import Foundation
import Testing
import UserNotifications
import ZislaCore

@testable import ZislaKit

@MainActor
struct PomodoroUserCareTests {
    @Test(arguments: [false, true], [false, true])
    func realCompletionKeepsOneSoundAndUsesTheSelectedReminderVoice(careEnabled: Bool, petEnabled: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        #expect(!service.userCareEnabled)
        service.userCareEnabled = careEnabled
        service.petEnabled = petEnabled
        for index in 0..<2 {
            let completedMode = service.mode
            let reminder: UserCareReminder = completedMode == .focus ? .focusCompleted : .restCompleted
            service.start()
            fixture.now += completedMode == .focus ? service.focusDuration : service.restDuration
            service.tick()
            #expect(service.phase == .idle && service.mode == completedMode.next)
            #expect(fixture.sounds == index + 1 && fixture.requests.count == index + 1)
            let request = fixture.requests[index]
            let ordinaryTitle = completedMode == .focus ? "Focus complete" : "Break complete"
            #expect(request.content.title == (careEnabled
                ? reminder.localizedMessage(petEnabled: petEnabled, language: .english)
                : AppLocalization.string(completedMode == .focus ? "专注结束" : "休息结束", language: .english)),
                "\(ordinaryTitle) must use the selected completion voice")
            #expect(request.content.body == (completedMode == .focus
                ? AppLocalization.format("休息 %ld 分钟吧", locale: AppLanguage.english.locale, [7])
                : AppLocalization.string("开始下一段专注", language: .english)))
            #expect(request.content.sound == nil, "The custom melody must not be doubled by a notification sound")
            service.tick()
            #expect(fixture.sounds == index + 1 && fixture.requests.count == index + 1)
        }
        #expect(fixture.reminders == (careEnabled ? [.focusCompleted, .restCompleted] : []))
    }

    @Test(arguments: [false, true])
    func mutedCompletionsSuppressSoundSystemNotificationsAndCareEvents(careEnabled: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.userCareEnabled = careEnabled
        service.petEnabled = true
        service.notificationsMuted = true
        for _ in 0..<2 {
            service.start()
            fixture.now += service.mode == .focus ? service.focusDuration : service.restDuration
            service.tick()
            #expect(service.phase == .idle)
        }
        #expect(fixture.requests.isEmpty && fixture.reminders.isEmpty && fixture.sounds == 0)
    }

    @Test(arguments: ["pause", "reset", "stop"])
    func interruptionNeverFabricatesACompletion(action: String) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.userCareEnabled = true
        service.start()
        switch action {
        case "pause": service.pause()
        case "reset": service.reset()
        default: service.stop()
        }
        fixture.now += 10_000
        service.tick()
        #expect(fixture.requests.isEmpty && fixture.reminders.isEmpty && fixture.sounds == 0)
        #expect(service.mode == .focus)
    }

    @Test(arguments: AppLanguage.allCases)
    func bothCompletionTitlesUseTheCurrentLanguage(language: AppLanguage) throws {
        let fixture = try Fixture(language: language)
        defer { fixture.close() }
        let service = fixture.service
        service.userCareEnabled = true
        service.petEnabled = true
        for reminder in [UserCareReminder.focusCompleted, .restCompleted] {
            service.start()
            fixture.now += service.mode == .focus ? service.focusDuration : service.restDuration
            service.tick()
            #expect(fixture.requests.last?.content.title == reminder.localizedMessage(petEnabled: true, language: language))
            #expect(fixture.reminders.last == reminder)
        }
        #expect(fixture.sounds == 2)
    }

    @Test
    func changesDuringTheCountdownUseTheLatestCareAndPetSettings() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.start()
        service.userCareEnabled = true
        service.petEnabled = true
        fixture.now += service.focusDuration
        service.tick()
        #expect(fixture.requests.last?.content.title == UserCareReminder.focusCompleted.localizedMessage(
            petEnabled: true, language: .english))
        service.start()
        service.notificationsMuted = true
        fixture.now += service.restDuration
        service.tick()
        #expect(fixture.requests.count == 1 && fixture.sounds == 1 && fixture.reminders == [.focusCompleted])
    }

    @MainActor
    private final class Fixture {
        let suiteName = "Zisla.PomodoroCare.\(UUID().uuidString)"
        let defaults: UserDefaults
        let language: AppLanguage
        var now = Date(timeIntervalSince1970: 10_000_000)
        var requests: [UNNotificationRequest] = []
        var sounds = 0
        var reminders: [UserCareReminder] = []
        lazy var service: PomodoroService = {
            let service = PomodoroService(
                notificationRequestHandler: { [unowned self] in requests.append($0) },
                defaults: defaults,
                completionSoundHandler: { [unowned self] in sounds += 1 },
                language: { [unowned self] in language },
                now: { [unowned self] in now }
            )
            service.onUserCareReminder = { [unowned self] in reminders.append($0) }
            service.setFocusDuration(1)
            service.setRestDuration(7 * 60)
            return service
        }()

        init(language: AppLanguage = .english) throws {
            defaults = try #require(UserDefaults(suiteName: suiteName))
            self.language = language
        }

        func close() {
            service.stop()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
