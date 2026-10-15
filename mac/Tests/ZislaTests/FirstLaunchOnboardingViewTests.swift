import AppKit
import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
private final class OnboardingViewFixture {
    var playCount = 0
    var stopCount = 0
    var audioIsPlaying = false
    var audioIsMuted = false
    var audioCanPlay = true
    var requestCompletion: OnboardingPermissionCoordinator.RequestCompletion?
    var requests: [OnboardingPermissionID] = []
    var openedSettings: [URL] = []
    var outcomes: [Bool] = []
    var statuses: [OnboardingPermissionID: OnboardingPermissionStatus] = [:]
    var permissionResourceIsActive = false

    lazy var permissions = OnboardingPermissionCoordinator(dependencies: .init(
        read: { [unowned self] id, completion in
            completion(self.statuses[id] ?? (id.requiresManualSetup ? .manual : .notDetermined))
        },
        request: { [unowned self] id, completion in
            self.requests.append(id)
            self.permissionResourceIsActive = true
            self.requestCompletion = completion
        },
        cancel: { [unowned self] in self.permissionResourceIsActive = false },
        openSettings: { [unowned self] in self.openedSettings.append($0); return true }
    ))

    func session(
        preferredLanguage: AppLanguage = .english,
        now: @escaping () -> Date = Date.init,
        onEnd: ((Bool) -> Void)? = nil
    ) -> FirstLaunchOnboardingSession {
        FirstLaunchOnboardingSession(
            permissions: permissions,
            audio: .init(
                play: { self.playCount += 1; self.audioIsPlaying = self.audioCanPlay; return self.audioCanPlay },
                stop: { self.stopCount += 1; self.audioIsPlaying = false },
                setMuted: { self.audioIsMuted = $0 }
            ),
            preferredLanguage: preferredLanguage,
            now: now,
            onEnd: { self.outcomes.append($0); onEnd?($0) }
        )
    }

    func item(_ id: OnboardingPermissionID) -> OnboardingPermissionItem {
        permissions.permissions.first { $0.id == id }!
    }
}

@MainActor
struct FirstLaunchOnboardingViewTests {
    @Test func greetingUsesExactlySupportedLanguagesAndRequiredOpening() {
        let languages = FirstLaunchOnboardingSession.greetingLanguages
        #expect(languages.count == 17)
        #expect(Set(languages.map(\.rawValue)) == Set(AppLanguage.allCases.map(\.rawValue)))
        #expect(Array(languages.prefix(3)) == [.english, .simplifiedChinese, .german])
        #expect(languages.prefix(3).map { AppLocalization.string("onboarding.hello", language: $0) } == ["Hello", "你好", "hallo"])
    }

    @Test func reduceMotionHasNoContinuingTaskAndNavigationStopsAudio() {
        let fake = OnboardingViewFixture()
        let session = fake.session()
        defer { session.close() }
        session.start(reduceMotion: true)
        #expect(session.page == .greeting)
        #expect(fake.audioIsPlaying)
        #expect(fake.requests.isEmpty)
        session.isMuted = true
        #expect(fake.audioIsMuted)
        session.advance()
        #expect(session.page == .introduction)
        #expect(!fake.audioIsPlaying)
    }

    @Test func closingCancelsGreetingAndPermissionResourcesWithoutCompletion() {
        let fake = OnboardingViewFixture()
        let session = fake.session()
        session.start(reduceMotion: false)
        session.advance()
        session.advance()
        session.performPermissionAction(fake.item(.microphone))
        #expect(fake.permissionResourceIsActive)
        let lateCompletion = fake.requestCompletion
        session.end(completed: false)
        lateCompletion?(.success(.granted))
        #expect(session.isClosed)
        #expect(fake.permissions.isClosed)
        #expect(!fake.audioIsPlaying)
        #expect(!fake.permissionResourceIsActive)
        #expect(fake.outcomes == [false])
        session.end(completed: true)
        #expect(fake.outcomes == [false])
    }

    @Test func refusedPermissionsAndSettingsNeverBlockCompletion() {
        let fake = OnboardingViewFixture()
        fake.statuses[.microphone] = .denied
        fake.statuses[.camera] = .restricted
        fake.statuses[.calendar] = .granted
        let session = fake.session()
        session.start(reduceMotion: true)
        session.advance()
        session.advance()
        session.performPermissionAction(fake.item(.microphone))
        session.performPermissionAction(fake.item(.camera))
        session.performPermissionAction(fake.item(.files))
        session.performPermissionAction(fake.item(.calendar))
        #expect(fake.requests.isEmpty)
        #expect(fake.openedSettings == [
            OnboardingPermissionID.microphone.settingsURL,
            OnboardingPermissionID.camera.settingsURL,
            OnboardingPermissionID.files.settingsURL,
        ])
        #expect(fake.item(.microphone).status == .denied)
        #expect(fake.item(.files).status == .manual)
        session.advance()
        #expect(session.page == .ready)
        session.advance()
        #expect(fake.outcomes == [true])
    }

    @Test func pendingRequestPreventsConcurrentActionsAndCanBeSkipped() {
        let fake = OnboardingViewFixture()
        let session = fake.session()
        session.start(reduceMotion: true)
        session.advance()
        session.advance()
        session.performPermissionAction(fake.item(.microphone))
        session.performPermissionAction(fake.item(.camera))
        session.performPermissionAction(fake.item(.files))
        #expect(fake.requests == [.microphone])
        #expect(fake.openedSettings.isEmpty)
        #expect(fake.item(.microphone).status == .requesting)
        session.advance()
        #expect(session.page == .ready)
        #expect(fake.permissions.requesting == nil)
        #expect(!fake.permissionResourceIsActive)
        session.advance()
        #expect(fake.outcomes == [true])
    }

    @Test func skippingAnimationKeepsPermissionSetupWhileRuntimeIsRunning() {
        let name = "FirstLaunchOnboardingViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let state = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla", environment: [:], hasExistingInstallation: false)
        var normalApplicationIsRunning = false
        let lifecycle = FirstLaunchOnboardingLifecycle(state: state) { normalApplicationIsRunning = true }
        #expect(lifecycle.begin())
        let fake = OnboardingViewFixture()
        let session = fake.session(onEnd: { lifecycle.finish(completed: $0) })
        session.start(reduceMotion: false)
        session.skipIntroduction()
        #expect(session.page == .permissions)
        #expect(normalApplicationIsRunning)
        #expect(state.shouldPresent)
        #expect(!fake.audioIsPlaying)
        #expect(!fake.permissions.isClosed)
        #expect(fake.requests.isEmpty)
        session.advance()
        session.advance()
        #expect(normalApplicationIsRunning)
        #expect(!state.shouldPresent)
        #expect(fake.permissions.isClosed)
    }

    @Test func repeatedStartPreservesGreetingAndAudio() {
        let fake = OnboardingViewFixture()
        var now = Date(timeIntervalSince1970: 0)
        let session = fake.session(now: { now })
        defer { session.close() }
        session.start(reduceMotion: false)
        let startedAt = session.greetingStartedAt
        now = Date(timeIntervalSince1970: 3600)
        session.start(reduceMotion: false)
        #expect(session.page == .greeting)
        #expect(session.greetingStartedAt == startedAt)
        #expect(fake.playCount == 1)
        #expect(fake.audioIsPlaying)
        #expect(fake.outcomes.isEmpty)
    }

    @Test func laterPagesCannotRestartGreetingAudio() {
        let fake = OnboardingViewFixture()
        let session = fake.session()
        defer { session.close() }
        session.start(reduceMotion: false)
        for page in [FirstLaunchOnboardingSession.Page.introduction, .permissions, .ready] {
            session.advance()
            session.start(reduceMotion: false)
            #expect(session.page == page)
            #expect(session.greetingStartedAt == nil)
            #expect(!fake.audioIsPlaying)
            #expect(fake.playCount == 1)
        }
    }

    @Test func unavailableAudioStillWaitsForExplicitContinue() {
        let fake = OnboardingViewFixture()
        fake.audioCanPlay = false
        let session = fake.session()
        defer { session.close() }
        session.start(reduceMotion: false)
        #expect(session.page == .greeting)
        #expect(session.greetingStartedAt != nil)
        #expect(!fake.audioIsPlaying)
        #expect(fake.requests.isEmpty)
        session.advance(from: session.navigationID)
        #expect(session.page == .introduction)
        #expect(session.greetingStartedAt == nil)
        #expect(fake.outcomes.isEmpty)
    }

    @Test(arguments: [0.0, 7.2, 60.0, 86400.0])
    func elapsedTimeNeverAdvancesGreeting(elapsed: TimeInterval) async {
        let fake = OnboardingViewFixture()
        var now = Date(timeIntervalSince1970: 0)
        let session = fake.session(preferredLanguage: .arabic, now: { now })
        defer { session.close() }
        session.start(reduceMotion: false)
        now = now.addingTimeInterval(elapsed)
        _ = session.greetingTimeline.frame(at: elapsed)
        await Task.yield()
        #expect(session.page == .greeting)
        #expect(fake.audioIsPlaying)
        #expect(fake.requests.isEmpty)
        #expect(fake.outcomes.isEmpty)
        session.advance(from: session.navigationID)
        #expect(session.page == .introduction)
        #expect(session.greetingStartedAt == nil)
        #expect(!fake.audioIsPlaying)
    }

    @Test func repeatedAndLateContinueOnlyMovesOnce() {
        let fake = OnboardingViewFixture()
        let session = fake.session()
        defer { session.close() }
        session.start(reduceMotion: false)
        let greetingEvent = session.navigationID
        session.advance(from: greetingEvent)
        session.advance(from: greetingEvent)
        #expect(session.page == .introduction)
        #expect(fake.stopCount == 1)
        session.back()
        session.start(reduceMotion: false)
        session.advance(from: greetingEvent)
        #expect(session.page == .greeting)
        #expect(fake.playCount == 2)
        #expect(fake.audioIsPlaying)
        session.close()
        session.advance(from: session.navigationID)
        session.start(reduceMotion: false)
        #expect(fake.playCount == 2)
        #expect(!fake.audioIsPlaying)
        #expect(fake.outcomes.isEmpty)
    }

    @Test func reduceMotionCanChangeWithoutRestartingAudio() {
        let fake = OnboardingViewFixture()
        let session = fake.session()
        defer { session.close() }
        session.start(reduceMotion: false)
        session.start(reduceMotion: true)
        #expect(session.greetingStartedAt == nil)
        #expect(session.page == .greeting)
        #expect(fake.playCount == 1)
        #expect(fake.audioIsPlaying)
        session.start(reduceMotion: false)
        #expect(session.greetingStartedAt != nil)
        #expect(fake.playCount == 1)
        session.advance()
        #expect(!fake.audioIsPlaying)
    }

    @Test func latePermissionCompletionCannotFinishOrRestartServices() {
        let fake = OnboardingViewFixture()
        let session = fake.session()
        session.skipIntroduction()
        session.performPermissionAction(fake.item(.microphone))
        let lateCompletion = fake.requestCompletion
        session.end(completed: false)
        lateCompletion?(.success(.granted))
        session.advance()
        session.end(completed: true)
        #expect(fake.outcomes == [false])
        #expect(fake.permissions.isClosed)
        #expect(!fake.permissionResourceIsActive)
        #expect(!fake.audioIsPlaying)
    }
    @Test func islandAndToolFocusDoNotAdvanceOrStopGreeting() {
        let fake = OnboardingViewFixture()
        let session = fake.session()
        let controller = FirstLaunchOnboardingController(session: session, languageStore: AppLanguageStore())
        defer { controller.close() }
        session.start(reduceMotion: false)
        let startedAt = session.greetingStartedAt
        let navigationID = session.navigationID
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        #expect(!session.isClosed)
        #expect(session.page == .greeting)
        #expect(session.greetingStartedAt == startedAt)
        #expect(session.navigationID == navigationID)
        #expect(fake.audioIsPlaying)
        #expect(fake.playCount == 1)
        #expect(fake.stopCount == 0)
        #expect(fake.outcomes.isEmpty)
        session.advance(from: navigationID)
        #expect(session.page == .introduction)
        #expect(!fake.audioIsPlaying)
    }

}
