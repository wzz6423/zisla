import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
private final class OnboardingViewFixture {
    var audioIsPlaying = false
    var audioIsMuted = false
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
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onEnd: ((Bool) -> Void)? = nil
    ) -> FirstLaunchOnboardingSession {
        FirstLaunchOnboardingSession(
            permissions: permissions,
            audio: .init(
                play: { self.audioIsPlaying = true; return true },
                stop: { self.audioIsPlaying = false },
                setMuted: { self.audioIsMuted = $0 }
            ),
            preferredLanguage: preferredLanguage,
            sleep: sleep,
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
        #expect(!session.hasGreetingTask)
        #expect(fake.audioIsPlaying)
        #expect(fake.requests.isEmpty)
        session.isMuted = true
        #expect(fake.audioIsMuted)
        session.advance()
        #expect(session.page == .introduction)
        #expect(!fake.audioIsPlaying)
        #expect(!session.hasGreetingTask)
    }

    @Test func closingCancelsGreetingAndPermissionResourcesWithoutCompletion() {
        let fake = OnboardingViewFixture()
        let session = fake.session()
        session.start(reduceMotion: false)
        #expect(session.hasGreetingTask)
        session.advance()
        #expect(!session.hasGreetingTask)
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
        #expect(!session.hasGreetingTask)
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

    @Test func skippingAnimationKeepsPermissionSetupBeforeNormalStartup() {
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
        #expect(!normalApplicationIsRunning)
        #expect(state.shouldPresent)
        #expect(!fake.audioIsPlaying)
        #expect(!session.hasGreetingTask)
        #expect(!fake.permissions.isClosed)
        #expect(fake.requests.isEmpty)
        session.advance()
        session.advance()
        #expect(normalApplicationIsRunning)
        #expect(!state.shouldPresent)
        #expect(fake.permissions.isClosed)
    }

    @Test func enablingReduceMotionCancelsExistingGreetingTask() {
        let fake = OnboardingViewFixture()
        let session = fake.session()
        defer { session.close() }
        session.start(reduceMotion: false)
        #expect(session.hasGreetingTask)
        session.start(reduceMotion: true)
        #expect(!session.hasGreetingTask)
        #expect(session.greetingStartedAt == nil)
    }

    @Test func greetingAutoAdvancesWithScoreWithoutRequestingPermissions() async throws {
        let fake = OnboardingViewFixture()
        let delay = GreetingDelay()
        let session = fake.session(preferredLanguage: .arabic, sleep: { try await delay.sleep($0) })
        defer { session.close() }
        let task = try #require(session.start(reduceMotion: false))
        await delay.waitUntilStarted()
        #expect(delay.durations == [.seconds(FirstLaunchOnboardingScore.duration)])
        #expect(session.page == .greeting)
        #expect(session.greetingStartedAt != nil)
        #expect(session.greetingTimeline.languages.last == .arabic)
        delay.release()
        await task.value
        #expect(session.page == .introduction)
        #expect(!session.hasGreetingTask)
        #expect(session.greetingStartedAt == nil)
        #expect(!fake.audioIsPlaying)
        #expect(fake.requests.isEmpty)
        #expect(fake.outcomes.isEmpty)
    }

    @Test(arguments: [false, true])
    func lateGreetingCompletionCannotNavigateAfterSkippingOrClosing(close: Bool) async throws {
        let fake = OnboardingViewFixture()
        let delay = GreetingDelay()
        let session = fake.session(sleep: { try await delay.sleep($0) })
        defer { session.close() }
        let task = try #require(session.start(reduceMotion: false))
        await delay.waitUntilStarted()
        if close { session.close() } else { session.skipIntroduction() }
        let page = session.page
        delay.release()
        await task.value
        #expect(session.page == page)
        #expect(session.isClosed == close)
        #expect(!session.hasGreetingTask)
        #expect(session.greetingStartedAt == nil)
        #expect(!fake.audioIsPlaying)
        #expect(fake.outcomes.isEmpty)
        #expect(fake.requests.isEmpty)
    }

    @Test func reduceMotionIgnoresAlreadyScheduledCompletion() async throws {
        let fake = OnboardingViewFixture()
        let delay = GreetingDelay()
        let session = fake.session(sleep: { try await delay.sleep($0) })
        defer { session.close() }
        let task = try #require(session.start(reduceMotion: false))
        await delay.waitUntilStarted()
        #expect(session.start(reduceMotion: true) == nil)
        delay.release()
        await task.value
        #expect(session.page == .greeting)
        #expect(session.greetingStartedAt == nil)
        #expect(!session.hasGreetingTask)
        #expect(fake.audioIsPlaying)
    }

    @Test(arguments: [false, true])
    func returningToGreetingReplaysMusicAndIgnoresOldCompletion(failed: Bool) async throws {
        let fake = OnboardingViewFixture()
        let delay = GreetingDelay()
        let session = fake.session(sleep: { try await delay.sleep($0) })
        defer { session.close() }
        let old = try #require(session.start(reduceMotion: false))
        await delay.waitUntilStarted()
        session.advance()
        #expect(!fake.audioIsPlaying)
        session.back()
        let current = try #require(session.start(reduceMotion: false))
        await delay.waitUntilStarted(count: 2)
        #expect(fake.audioIsPlaying)
        delay.release(error: failed ? CancellationError() : nil)
        await old.value
        #expect(session.page == .greeting)
        #expect(session.hasGreetingTask)
        delay.release()
        await current.value
        #expect(session.page == .introduction)
        #expect(!fake.audioIsPlaying)
    }

    @Test func failedGreetingDelayLeavesStaticGreetingAndManualNavigation() async throws {
        let fake = OnboardingViewFixture()
        let session = fake.session(sleep: { _ in throw CancellationError() })
        defer { session.close() }
        let task = try #require(session.start(reduceMotion: false))
        await task.value
        #expect(session.page == .greeting)
        #expect(!session.hasGreetingTask)
        #expect(session.greetingStartedAt == nil)
        #expect(!fake.audioIsPlaying)
        session.advance()
        #expect(session.page == .introduction)
    }
}

@MainActor
private final class GreetingDelay {
    private(set) var durations: [Duration] = []
    private var continuations: [CheckedContinuation<Void, Error>] = []
    private var started: CheckedContinuation<Void, Never>?

    func sleep(_ duration: Duration) async throws {
        durations.append(duration)
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted(count: Int = 1) async {
        if durations.count >= count { return }
        await withCheckedContinuation { started = $0 }
    }

    func release(error: Error? = nil) {
        let continuation = continuations.removeFirst()
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }
}
