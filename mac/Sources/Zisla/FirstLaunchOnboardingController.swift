import AppKit
import Combine
import SwiftUI
import ZislaCore
import ZislaKit

@MainActor
final class FirstLaunchOnboardingLifecycle {
    private let state: FirstLaunchOnboardingState
    private var startApplication: (() -> Void)?
    private var hasBegun = false
    private var hasEnded = false

    init(state: FirstLaunchOnboardingState, startApplication: @escaping () -> Void) {
        self.state = state
        self.startApplication = startApplication
    }

    func begin() -> Bool {
        guard !hasBegun, !hasEnded else { return false }
        hasBegun = true
        if state.shouldPresent {
            state.recordStarted()
            return true
        }
        finish(completed: false)
        return false
    }

    func finish(completed: Bool) {
        guard hasBegun, !hasEnded else { return }
        hasEnded = true
        if completed { state.recordCompleted() }
        let start = startApplication
        startApplication = nil
        start?()
    }

    func terminate() {
        hasEnded = true
        startApplication = nil
    }
}

@MainActor
final class FirstLaunchOnboardingSession: ObservableObject {
    enum Page: Int { case greeting, introduction, permissions, ready }

    struct Audio {
        var play: () -> Bool
        var stop: () -> Void
        var setMuted: (Bool) -> Void
    }

    nonisolated static let greetingLanguages: [AppLanguage] = {
        let first: [AppLanguage] = [.english, .simplifiedChinese, .german]
        return first + AppLanguage.allCases.filter { !first.contains($0) }
    }()

    @Published private(set) var page: Page = .greeting
    @Published private(set) var greetingStartedAt: Date?
    @Published var isMuted = false {
        didSet { audio.setMuted(isMuted) }
    }
    let permissions: OnboardingPermissionCoordinator
    let greetingTimeline: FirstLaunchGreetingTimeline
    let preferredLanguage: AppLanguage
    private let audio: Audio
    private let sleep: (Duration) async throws -> Void
    private var onEnd: ((Bool) -> Void)?
    private var greetingTask: Task<Void, Never>?
    private(set) var isClosed = false
    var hasGreetingTask: Bool { greetingTask != nil }

    init(
        permissions: OnboardingPermissionCoordinator,
        audio: Audio,
        preferredLanguage: AppLanguage = .english,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onEnd: @escaping (Bool) -> Void
    ) {
        self.permissions = permissions
        self.audio = audio
        self.preferredLanguage = preferredLanguage
        greetingTimeline = FirstLaunchGreetingTimeline(preferredLanguage: preferredLanguage)
        self.sleep = sleep
        self.onEnd = onEnd
    }

    @discardableResult
    func start(reduceMotion: Bool) -> Task<Void, Never>? {
        guard !isClosed, page == .greeting else { return nil }
        greetingTask?.cancel()
        greetingTask = nil
        permissions.refresh()
        _ = audio.play()
        greetingStartedAt = reduceMotion ? nil : Date()
        guard !reduceMotion else { return nil }
        greetingTask = Task { @MainActor [weak self, sleep] in
            do {
                try await sleep(.seconds(FirstLaunchOnboardingScore.duration))
            } catch {
                guard !Task.isCancelled else { return }
                self?.stopGreeting()
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.advance()
        }
        return greetingTask
    }

    func advance() {
        guard !isClosed else { return }
        switch page {
        case .greeting: move(to: .introduction)
        case .introduction: move(to: .permissions)
        case .permissions: move(to: .ready)
        case .ready: end(completed: true)
        }
    }

    func back() {
        guard !isClosed else { return }
        switch page {
        case .greeting: break
        case .introduction: move(to: .greeting)
        case .permissions: move(to: .introduction)
        case .ready: move(to: .permissions)
        }
    }

    func skipIntroduction() {
        guard !isClosed, page == .greeting || page == .introduction else { return }
        move(to: .permissions)
    }

    func performPermissionAction(_ item: OnboardingPermissionItem) {
        guard !isClosed, page == .permissions, permissions.requesting == nil else { return }
        switch item.status {
        case .granted, .requesting: break
        case .denied, .restricted, .manual: _ = permissions.openSettings(for: item.id)
        case .notDetermined, .unavailable: _ = permissions.request(item.id)
        }
    }

    private func move(to page: Page) {
        stopGreeting()
        if permissions.requesting != nil { permissions.cancelCurrentRequest() }
        self.page = page
        if page == .permissions { permissions.refresh() }
    }

    private func stopGreeting() {
        greetingTask?.cancel()
        greetingTask = nil
        greetingStartedAt = nil
        audio.stop()
    }

    func end(completed: Bool) {
        guard !isClosed else { return }
        let callback = onEnd
        close()
        callback?(completed)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        onEnd = nil
        stopGreeting()
        permissions.close()
    }
}

@MainActor
final class FirstLaunchOnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let session: FirstLaunchOnboardingSession
    private let languageStore: AppLanguageStore
    private var cancellables = Set<AnyCancellable>()

    init(onEnd: @escaping (Bool) -> Void) {
        let audio = FirstLaunchOnboardingAudio()
        let languageStore = AppLanguageStore()
        session = FirstLaunchOnboardingSession(
            permissions: OnboardingPermissionCoordinator(),
            audio: .init(play: { audio.play() }, stop: { audio.stop() }, setMuted: { audio.isMuted = $0 }),
            preferredLanguage: languageStore.language,
            onEnd: onEnd
        )
        self.languageStore = languageStore
        super.init()
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.session.permissions.refresh() }
            }.store(in: &cancellables)
        languageStore.$language.sink { [weak self] language in
            self?.window?.title = AppLocalization.string("onboarding.introduction.title", language: language)
        }.store(in: &cancellables)
    }

    func show() {
        guard !session.isClosed else { return }
        let screen = WindowPlacement.screenUnderMouse()
        if window == nil {
            let available = screen?.visibleFrame.size ?? CGSize(width: 720, height: 640)
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: min(720, available.width - 32), height: min(640, available.height - 32)),
                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false
            )
            window.title = AppLocalization.string("onboarding.introduction.title", language: languageStore.language)
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.delegate = self
            window.contentView = NSHostingView(rootView: AppLanguageEnvironment(
                languageStore: languageStore,
                content: FirstLaunchOnboardingView(session: session)
            ))
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            WindowPlacement.center(window, on: screen)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        session.end(completed: false)
        close()
    }

    func close() {
        session.close()
        cancellables.removeAll()
        window?.delegate = nil
        window?.contentView = nil
        window?.close()
        window = nil
    }
}
