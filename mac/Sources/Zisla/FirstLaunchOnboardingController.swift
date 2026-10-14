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
    private let now: () -> Date
    private var greetingHasStarted = false
    @Published private(set) var navigationID = UUID()
    private var onEnd: ((Bool) -> Void)?
    private(set) var isClosed = false

    init(
        permissions: OnboardingPermissionCoordinator,
        audio: Audio,
        preferredLanguage: AppLanguage = .english,
        now: @escaping () -> Date = Date.init,
        onEnd: @escaping (Bool) -> Void
    ) {
        self.permissions = permissions
        self.audio = audio
        self.preferredLanguage = preferredLanguage
        greetingTimeline = FirstLaunchGreetingTimeline(preferredLanguage: preferredLanguage)
        self.now = now
        self.onEnd = onEnd
    }

    func start(reduceMotion: Bool) {
        guard !isClosed, page == .greeting else { return }
        if !greetingHasStarted {
            greetingHasStarted = true
            permissions.refresh()
            _ = audio.play()
            greetingStartedAt = reduceMotion ? nil : now()
        } else if reduceMotion {
            greetingStartedAt = nil
        } else if greetingStartedAt == nil {
            greetingStartedAt = now()
        }
    }

    func advance(from navigationID: UUID) {
        guard self.navigationID == navigationID else { return }
        advance()
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
        navigationID = UUID()
        self.page = page
        if page == .permissions { permissions.refresh() }
    }

    private func stopGreeting() {
        greetingHasStarted = false
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

struct FirstLaunchOnboardingPresentation {
    let anchorFrame: CGRect
    let topContentInset: CGFloat
    static let readingWidth: CGFloat = 656

    init(screen: ScreenSnapshot) {
        let frame = screen.frame
        let anchor = ScreenLayoutEngine().layout(for: screen).collapsedFrame
        anchorFrame = CGRect(
            x: anchor.minX - frame.minX, y: frame.maxY - anchor.maxY,
            width: anchor.width, height: anchor.height
        )
        topContentInset = min(frame.height, anchorFrame.maxY + 72)
    }

    static func presentationOptions(
        original: NSApplication.PresentationOptions,
        isActive: Bool, isKey: Bool, isRequesting: Bool
    ) -> NSApplication.PresentationOptions {
        guard isActive, isKey, !isRequesting else { return original }
        return original.subtracting([.hideDock, .hideMenuBar]).union([.autoHideDock, .autoHideMenuBar])
    }
}

@MainActor
final class FirstLaunchOnboardingScreen: ObservableObject {
    @Published var presentation: FirstLaunchOnboardingPresentation?
}

@MainActor
final class FirstLaunchOnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.isARepeat, event.charactersIgnoringModifiers == "\r" { return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class FirstLaunchOnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let session: FirstLaunchOnboardingSession
    private let languageStore: AppLanguageStore
    private let screenState = FirstLaunchOnboardingScreen()
    private var displayID: CGDirectDisplayID?
    private var originalPresentationOptions: NSApplication.PresentationOptions?
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
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.updatePresentationOptions()
                        if NSApp.isActive { self.session.permissions.refresh() }
                    }
                }.store(in: &cancellables)
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateScreen() }
            }.store(in: &cancellables)
        session.permissions.$requesting.sink { [weak self] requesting in
            self?.updatePresentationOptions(isRequesting: requesting != nil)
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.close() } }
            .store(in: &cancellables)
    }

    func show() {
        guard !session.isClosed, let screen = WindowPlacement.screenUnderMouse(),
              let snapshot = ScreenSnapshot(screen: screen) else { return }
        displayID = snapshot.displayID
        if window == nil {
            originalPresentationOptions = NSApp.presentationOptions
            let window = FirstLaunchOnboardingWindow(
                contentRect: snapshot.frame, styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.title = AppLocalization.string("onboarding.introduction.title", language: languageStore.language)
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.animationBehavior = .none
            window.isMovable = false
            window.hasShadow = false
            window.level = .normal
            window.delegate = self
            window.contentView = NSHostingView(rootView: AppLanguageEnvironment(
                languageStore: languageStore,
                content: FirstLaunchOnboardingView(session: session, screen: screenState)
            ))
            self.window = window
        }
        updateScreen()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        updatePresentationOptions()
    }

    private func updateScreen() {
        guard let window else { return }
        let snapshots = NSScreen.screens.compactMap { ScreenSnapshot(screen: $0) }
        guard let snapshot = snapshots.first(where: { $0.displayID == displayID })
            ?? WindowPlacement.screenUnderMouse().flatMap({ ScreenSnapshot(screen: $0) }) else { return }
        displayID = snapshot.displayID
        screenState.presentation = FirstLaunchOnboardingPresentation(screen: snapshot)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            window.setFrame(snapshot.frame, display: true)
        }
    }

    private func updatePresentationOptions(isRequesting: Bool? = nil) {
        guard let originalPresentationOptions else { return }
        NSApp.presentationOptions = FirstLaunchOnboardingPresentation.presentationOptions(
            original: originalPresentationOptions, isActive: NSApp.isActive,
            isKey: window?.isKeyWindow == true,
            isRequesting: isRequesting ?? (session.permissions.requesting != nil)
        )
    }

    func windowDidBecomeKey(_ notification: Notification) { updatePresentationOptions() }
    func windowDidResignKey(_ notification: Notification) { updatePresentationOptions() }

    func windowWillClose(_ notification: Notification) {
        session.end(completed: false)
        close()
    }

    func close() {
        session.close()
        cancellables.removeAll()
        if let originalPresentationOptions { NSApp.presentationOptions = originalPresentationOptions }
        originalPresentationOptions = nil
        window?.delegate = nil
        window?.contentView = nil
        window?.close()
        window = nil
    }
}
