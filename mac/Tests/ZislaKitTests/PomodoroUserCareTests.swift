import Foundation
import Testing
import UserNotifications
import ZislaCore

@testable import ZislaKit

@MainActor
struct PomodoroUserCareTests {
    @Test(arguments: [false, true])
    func realCompletionUsesOneSoundAndCareEventsReplaceSystemBanners(careEnabled: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        #expect(!service.userCareEnabled)
        service.userCareEnabled = careEnabled
        for index in 0..<2 {
            let completedMode = service.mode
            service.start()
            fixture.now += completedMode == .focus ? service.focusDuration : service.restDuration
            service.tick()
            #expect(service.phase == .idle && service.mode == completedMode.next)
            #expect(fixture.sounds == index + 1)
            #expect(fixture.requests.count == (careEnabled ? 0 : index + 1))
            if !careEnabled {
                let request = fixture.requests[index]
                #expect(request.content.title == AppLocalization.string(
                    completedMode == .focus ? "专注结束" : "休息结束", language: .english))
                #expect(request.content.body == (completedMode == .focus
                    ? AppLocalization.format("休息 %ld 分钟吧", locale: AppLanguage.english.locale, [7])
                    : AppLocalization.string("开始下一段专注", language: .english)))
                #expect(request.content.sound == nil, "The custom melody must not be doubled by a notification sound")
            }
            service.tick()
            #expect(fixture.sounds == index + 1)
            #expect(fixture.requests.count == (careEnabled ? 0 : index + 1))
        }
        #expect(fixture.reminders == (careEnabled ? [.focusCompleted, .restCompleted] : []))
    }

    @Test(arguments: [false, true])
    func mutedCompletionsSuppressSoundSystemNotificationsAndCareEvents(careEnabled: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.userCareEnabled = careEnabled
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
    func ordinaryCompletionTitlesKeepTheirRequestedLanguage(language: AppLanguage) throws {
        let fixture = try Fixture(language: language)
        defer { fixture.close() }
        let service = fixture.service
        for mode in [PomodoroMode.focus, .rest] {
            service.start()
            fixture.now += mode == .focus ? service.focusDuration : service.restDuration
            service.tick()
            #expect(fixture.requests.last?.content.title == AppLocalization.string(
                mode == .focus ? "专注结束" : "休息结束", language: language))
        }
        #expect(fixture.sounds == 2 && fixture.reminders.isEmpty)
    }

    @Test
    func changesDuringTheCountdownUseTheLatestCareAndMuteSettings() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let service = fixture.service
        service.start()
        service.userCareEnabled = true
        fixture.now += service.focusDuration
        service.tick()
        #expect(fixture.requests.isEmpty && fixture.reminders == [.focusCompleted] && fixture.sounds == 1)
        service.start()
        service.userCareEnabled = false
        fixture.now += service.restDuration
        service.tick()
        #expect(fixture.requests.count == 1 && fixture.sounds == 2 && fixture.reminders == [.focusCompleted])
        service.start()
        service.notificationsMuted = true
        fixture.now += service.focusDuration
        service.tick()
        #expect(fixture.requests.count == 1 && fixture.sounds == 2 && fixture.reminders == [.focusCompleted])
    }

    @Test
    func unavailableIslandHandlerNeverFallsBackToAnExternalCareBanner() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.service.userCareEnabled = true
        fixture.service.onUserCareReminder = nil
        fixture.service.start()
        fixture.now += fixture.service.focusDuration
        fixture.service.tick()
        #expect(fixture.requests.isEmpty && fixture.reminders.isEmpty && fixture.sounds == 1)
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
