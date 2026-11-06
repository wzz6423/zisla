import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct PermissionsSettingsViewTests {
    @Test
    func openingAndReturningRefreshStatusWithoutRequestingAccess() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.statuses[.microphone] = .granted
        fixture.statuses[.camera] = .restricted
        await fixture.layout()
        #expect(fixture.requests.isEmpty && fixture.opened.isEmpty)
        #expect(fixture.button(.microphone) == nil)
        #expect(fixture.button(.camera) != nil)
        #expect(fixture.status(.camera) == .restricted)

        fixture.statuses[.microphone] = .denied
        fixture.statuses[.camera] = .granted
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await fixture.layout()
        #expect(fixture.status(.microphone) == .denied)
        #expect(fixture.button(.microphone) != nil)
        #expect(fixture.button(.camera) == nil)
        #expect(fixture.requests.isEmpty && fixture.opened.isEmpty)
    }

    @Test
    func buttonsSerializeRequestsAndUseSystemSettingsAfterDenial() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        await fixture.layout()
        try await fixture.press(.microphone)
        #expect(fixture.requests == [.microphone])
        #expect(fixture.status(.microphone) == .requesting)
        #expect(try !fixture.isEnabled(.camera))
        #expect(try !fixture.isEnabled(.fullDiskAccess))

        fixture.complete(.microphone, .denied)
        await fixture.layout()
        #expect(try fixture.isEnabled(.camera))
        try await fixture.press(.microphone)
        #expect(fixture.opened == [OnboardingPermissionID.microphone.settingsURL])
        #expect(fixture.status(.microphone) == .denied)
        try await fixture.press(.fullDiskAccess)
        #expect(fixture.opened.last == OnboardingPermissionID.fullDiskAccess.settingsURL)
        #expect(fixture.status(.fullDiskAccess) == .manual)
        #expect(fixture.requests == [.microphone])

        fixture.statuses[.camera] = .unavailable
        fixture.coordinator.refresh()
        await fixture.layout()
        try await fixture.press(.camera)
        fixture.completions.last?(.failure(CancellationError()))
        await fixture.layout()
        #expect(fixture.coordinator.requesting == nil)
        #expect(!fixture.resourceActive)
        #expect(fixture.status(.camera) == .unavailable)
        try await fixture.press(.camera)
        fixture.complete(.camera, .granted)
        await fixture.layout()
        #expect(fixture.button(.camera) == nil)
    }

    @Test
    func leavingCancelsPendingWorkAndReopeningRemainsUsable() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        await fixture.layout()
        try await fixture.press(.location)
        let lateCompletion = try #require(fixture.completions.last)
        fixture.input.visible = false
        await fixture.layout()
        #expect(!fixture.resourceActive)
        #expect(fixture.coordinator.requesting == nil)
        lateCompletion(.success(.granted))
        #expect(fixture.status(.location) == .notDetermined)

        fixture.input.visible = true
        await fixture.layout()
        try await fixture.press(.bluetooth)
        fixture.complete(.bluetooth, .granted)
        await fixture.layout()
        #expect(fixture.status(.bluetooth) == .granted)
    }

    @Test
    func failedSettingsNavigationShowsAnErrorAndCanBeRetried() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.canOpenSettings = false
        await fixture.layout()
        try await fixture.press(.fullDiskAccess)
        #expect(fixture.displayedText().contains(AppLocalization.string("无法打开系统设置，请手动打开。", language: .english)))
        #expect(fixture.status(.fullDiskAccess) == .manual)
        fixture.canOpenSettings = true
        try await fixture.press(.fullDiskAccess)
        #expect(!fixture.displayedText().contains(AppLocalization.string("无法打开系统设置，请手动打开。", language: .english)))
        #expect(fixture.opened.count == 2)
        #expect(fixture.requests.isEmpty)
    }

    @Test(arguments: AppLanguage.allCases)
    func actionsExposeTheRequestedLanguage(language: AppLanguage) async throws {
        let fixture = Fixture(language: language)
        defer { fixture.close() }
        await fixture.layout()
        for permission in OnboardingPermissionID.allCases {
            let button = try #require(fixture.button(permission), "Missing \(permission) action")
            let actionKey = permission.requiresManualSetup ? "onboarding.open_settings" : "onboarding.grant"
            #expect(button.value(forKey: "accessibilityLabel") as? String
                == AppLocalization.string(actionKey, language: language) + " · "
                    + AppLocalization.string(permission.titleKey, language: language))
        }
    }

    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    func searchScrollsToTheFullDiskAccessRow(language: AppLanguage) async throws {
        let fixture = Fixture(language: language)
        defer { fixture.close() }
        await fixture.layout()
        fixture.input.target = .row(OnboardingPermissionID.fullDiskAccess.titleKey).localized(locale: language.locale)
        await fixture.layout()
        let scroll = try #require(fixture.views().compactMap { $0 as? NSScrollView }.first)
        #expect(scroll.contentView.bounds.minY > 100)
    }

    @MainActor
    private final class Input: ObservableObject {
        @Published var visible = true
        @Published var target: SettingsSearchAnchor?
    }

    private struct Host: View {
        @ObservedObject var input: Input
        let coordinator: OnboardingPermissionCoordinator
        let language: AppLanguage

        var body: some View {
            SettingsSearchScrollView(target: input.target, resetID: "") {
                if input.visible { PermissionsSettingsView(coordinator: coordinator) }
            }
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        }
    }

    @MainActor
    private final class Fixture {
        let input = Input()
        var statuses: [OnboardingPermissionID: OnboardingPermissionStatus] = [:]
        var requests: [OnboardingPermissionID] = []
        var completions: [OnboardingPermissionCoordinator.RequestCompletion] = []
        var opened: [URL] = []
        var resourceActive = false
        var canOpenSettings = true
        let window: NSPanel
        private(set) var host: NSView!
        let releaseAccessibility: @MainActor () -> Void
        lazy var coordinator = OnboardingPermissionCoordinator(dependencies: .init(
            read: { [unowned self] id, completion in
                completion(self.statuses[id] ?? (id.requiresManualSetup ? .manual : .notDetermined))
            },
            request: { [unowned self] id, completion in
                self.requests.append(id)
                self.completions.append(completion)
                self.resourceActive = true
            },
            cancel: { [unowned self] in self.resourceActive = false },
            openSettings: { [unowned self] url in self.opened.append(url); return self.canOpenSettings }
        ))

        init(language: AppLanguage = .english) {
            releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
            window = NSPanel(
                contentRect: NSRect(x: -100_000, y: -100_000, width: 640, height: 600),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: Host(input: input, coordinator: coordinator, language: language))
            hosting.sizingOptions = []
            host = hosting
            window.contentView = host
        }

        func close() {
            window.contentView = nil
            window.close()
            coordinator.close()
            releaseAccessibility()
        }

        func layout() async {
            for _ in 0..<10 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }

        func status(_ id: OnboardingPermissionID) -> OnboardingPermissionStatus? {
            coordinator.permissions.first { $0.id == id }?.status
        }

        func complete(_ id: OnboardingPermissionID, _ status: OnboardingPermissionStatus) {
            statuses[id] = status
            completions.last?(.success(status))
        }

        func press(_ id: OnboardingPermissionID) async throws {
            let button = try #require(self.button(id))
            try #require(try isEnabled(id))
            let action = NSSelectorFromString("accessibilityPerformPress")
            try #require(button.responds(to: action))
            _ = button.perform(action)
            await layout()
        }

        func isEnabled(_ id: OnboardingPermissionID) throws -> Bool {
            try #require(button(id)?.value(forKey: "accessibilityEnabled") as? Bool)
        }

        func button(_ id: OnboardingPermissionID) -> NSObject? {
            accessibilityObjects().first { object in
                object.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                    && object.value(forKey: "accessibilityIdentifier") as? String == "permission-\(id.rawValue)"
            }
        }

        func displayedText() -> [String] {
            accessibilityObjects().flatMap { object in
                ["accessibilityLabel", "accessibilityValue"].compactMap { key -> String? in
                    guard object.responds(to: NSSelectorFromString(key)) else { return nil }
                    return object.value(forKey: key) as? String
                }
            }
        }

        func accessibilityObjects() -> [NSObject] {
            func descendants(_ object: NSObject) -> [NSObject] {
                let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
                    ? object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
                return [object] + children.flatMap(descendants)
            }
            return descendants(host)
        }

        func views() -> [NSView] {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            return descendants(host)
        }
    }
}
