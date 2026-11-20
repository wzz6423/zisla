import AppKit
import CoreGraphics
import Testing
import ZislaCore

@testable import ZislaKit

@MainActor
@Suite(.serialized)
struct PermissionSettingsAssistantTests {
    @Test
    func settingsWindowMustBeVisibleBeforeAssistantAppears() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.settingsFrame = nil
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        await fixture.settle()
        #expect(fixture.assistant.panel == nil, "Opening Settings must not present a helper before its window appears")
        fixture.assistant.settingsDidActivate()
        #expect(fixture.assistant.panel == nil)
        fixture.settingsFrame = CGRect(x: 50, y: 200, width: 700, height: 600)
        fixture.tickSettings()
        #expect(fixture.assistant.panel != nil)
        #expect(fixture.settingsTimers.allSatisfy { !$0.isValid }, "Stop watching Settings once the helper appears")
    }

    @Test
    func closingSettingsAndReturningToTheAppKeepsTheAssistantAtItsLastPosition() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        await fixture.settle()
        let panel = try #require(fixture.assistant.panel)
        let frame = panel.frame
        fixture.settingsFrame = nil
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        fixture.workspaceCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        #expect(fixture.assistant.panel === panel, "Returning to the app must preserve the drag helper")
        fixture.assistant.settingsDidActivate()
        #expect(fixture.assistant.panel === panel && panel.frame == frame,
            "A missing Settings window must not close or reposition the helper")
    }

    @Test
    func supportedSettingsPresentTheRunningBundleWithoutChangingPermission() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        for id in [OnboardingPermissionID.accessibility, .inputMonitoring, .screenRecording, .systemAudio, .fullDiskAccess] {
            #expect(fixture.assistant.openSettings(id.settingsURL))
            await fixture.settle()
            let panel = try #require(fixture.assistant.panel)
            #expect(fixture.opened.last == id.settingsURL)
            #expect(!panel.canBecomeKey && !panel.canBecomeMain)
            #expect(panel.styleMask.contains(.nonactivatingPanel))
            #expect(!panel.hidesOnDeactivate && !panel.isReleasedWhenClosed)
            let image = try #require(panel.contentView?.subviews.compactMap { $0 as? NSStackView }.first?
                .arrangedSubviews.compactMap { $0 as? FileShelfDraggingView }.first)
            #expect(image.payload == .file(fixture.applicationURL))
            #expect(image.sourceOperationMask(for: .outsideApplication) == .copy)
            #expect(image.acceptsFirstMouse(for: nil))
            let item = try #require(image.draggingItems().first)
            #expect(item.item as? NSURL == fixture.applicationURL as NSURL)
            let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0))
            #expect(image.menu(for: event)?.items.isEmpty == true)
        }
        #expect(fixture.presentations == 5)
    }

    @Test
    func failedSettingsNavigationAndUnsupportedPanesLeaveNoAssistant() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.canOpen = false
        #expect(!fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        await fixture.settle()
        #expect(fixture.assistant.panel == nil && fixture.presentations == 0)
        fixture.canOpen = true
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        await fixture.settle()
        #expect(fixture.assistant.panel != nil)
        for id in OnboardingPermissionID.allCases where !PermissionSettingsAssistant.supportsDragging(for: id) {
            #expect(fixture.assistant.openSettings(id.settingsURL))
            await fixture.settle()
            #expect(fixture.assistant.panel == nil)
        }
        #expect(fixture.presentations == 1)
    }

    @Test
    func aCommandLineHostAndMissingBundleCannotAdvertiseADraggableApplication() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        var remote = URLComponents(url: fixture.applicationURL, resolvingAgainstBaseURL: false)!
        remote.scheme = "https"
        remote.host = "example.invalid"
        for applicationURL in [fixture.root, fixture.root.appendingPathComponent("missing.app"), remote.url!] {
            let assistant = fixture.makeAssistant(applicationURL: applicationURL)
            defer { assistant.dismiss() }
            #expect(assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
            await fixture.settle()
            #expect(assistant.panel == nil)
        }
        #expect(fixture.presentations == 0)
    }

    @Test
    func closingBeforePresentationAndExplicitCloseCancelPendingWork() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        fixture.assistant.dismiss()
        await fixture.settle()
        #expect(fixture.assistant.panel == nil && fixture.presentations == 0)
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        #expect(fixture.assistant.prepare(for: .accessibility))
        await fixture.settle()
        #expect(fixture.assistant.panel == nil && fixture.presentations == 0)
        fixture.assistant.cancelPreparation()
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        await fixture.settle()
        let panel = try #require(fixture.assistant.panel)
        panel.close()
        #expect(fixture.assistant.panel == nil)
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.accessibility.settingsURL))
        await fixture.settle()
        let reopened = try #require(fixture.assistant.panel)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(fixture.assistant.panel === reopened)
    }

    @Test
    func placementUsesTheSettingsWindowAndUpdatesWhenSettingsActivates() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        await fixture.settle()
        let panel = try #require(fixture.assistant.panel)
        #expect(panel.frame.minX == fixture.settingsFrame!.maxX + 12)
        fixture.settingsFrame = CGRect(x: 900, y: 200, width: 500, height: 600)
        fixture.assistant.settingsDidActivate()
        #expect(panel.frame.maxX == fixture.settingsFrame!.minX - 12)
        #expect(fixture.presentations == 1)
    }

    @Test
    func canceledNativePreparationCannotResurfaceAndDoesNotCloseAPresentedAssistant() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        #expect(fixture.assistant.prepare(for: .accessibility))
        fixture.assistant.cancelPreparation()
        fixture.assistant.settingsDidActivate()
        #expect(fixture.assistant.panel == nil && fixture.presentations == 0)
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        await fixture.settle()
        let panel = try #require(fixture.assistant.panel)
        fixture.assistant.cancelPreparation()
        #expect(fixture.assistant.panel === panel)
        fixture.assistant.dismiss()
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        fixture.assistant.cancelPreparation()
        await fixture.settle()
        #expect(fixture.assistant.panel == nil)
    }

    @Test(arguments: AppLanguage.allCases)
    func instructionsUseTheSelectedLanguageAndWritingDirection(language: AppLanguage) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let assistant = fixture.makeAssistant(applicationURL: fixture.applicationURL, language: language)
        defer { assistant.dismiss() }
        #expect(assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        await fixture.settle()
        let panel = try #require(assistant.panel)
        let label = try #require(panel.contentView?.subviews.compactMap { $0 as? NSStackView }.first?
            .arrangedSubviews.compactMap { $0 as? NSTextField }.first)
        #expect(label.stringValue == AppLocalization.string("permission.drag_app.body", language: language))
        #expect(label.baseWritingDirection == (language.isRightToLeft ? .rightToLeft : .leftToRight))
        #expect(panel.title == AppLocalization.string("权限", language: language))
        #expect(label.frame.height > 0 && panel.frame.height < 350)
    }

    @Test
    func preparingANativeRequestWaitsForSettingsWithoutOpeningIt() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        #expect(fixture.assistant.prepare(for: .accessibility))
        await fixture.settle()
        #expect(fixture.opened.isEmpty && fixture.assistant.panel == nil)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        fixture.assistant.settingsDidActivate()
        #expect(fixture.assistant.panel != nil && fixture.presentations == 1)
        fixture.assistant.settingsDidActivate()
        #expect(fixture.presentations == 1)
        fixture.assistant.dismiss()
        fixture.assistant.settingsDidActivate()
        #expect(fixture.assistant.panel == nil)
        #expect(!fixture.assistant.prepare(for: .camera))
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        fixture.assistant.settingsDidActivate()
        await fixture.settle()
        #expect(fixture.presentations == 2)
    }

    @Test
    func aNativeRequestWaitsForTheWindowAfterSettingsActivates() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.settingsFrame = nil
        #expect(fixture.assistant.prepare(for: .accessibility))
        fixture.assistant.settingsDidActivate()
        fixture.tickSettings()
        #expect(fixture.assistant.panel == nil)
        fixture.settingsFrame = CGRect(x: 50, y: 200, width: 700, height: 600)
        fixture.tickSettings()
        #expect(fixture.assistant.panel != nil && fixture.presentations == 1)
        #expect(fixture.opened.isEmpty)
        #expect(fixture.settingsTimers.allSatisfy { !$0.isValid })
    }

    @Test
    func delayedWindowChecksCannotReviveClosedOrSupersededRequests() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.settingsFrame = nil
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        let timer = try #require(fixture.settingsTimers.first)
        let delayed = try #require(fixture.timerHandlers.first)
        fixture.assistant.settingsDidActivate()
        #expect(fixture.settingsTimers.count == 1)
        fixture.assistant.dismiss()
        #expect(!timer.isValid)
        fixture.settingsFrame = CGRect(x: 50, y: 200, width: 700, height: 600)
        delayed(timer)
        #expect(fixture.assistant.panel == nil)
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.accessibility.settingsURL))
        delayed(timer)
        #expect(fixture.assistant.panel == nil, "A stale check must not present the replacement request")
        await fixture.settle()
        #expect(fixture.assistant.panel != nil && fixture.presentations == 1)
    }

    @Test
    func theMainRunLoopPresentsOnceAndStopsPollingWhenSettingsAppears() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.settingsFrame = nil
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        let timer = try #require(fixture.settingsTimers.first)
        #expect(timer.isValid && fixture.assistant.panel == nil)
        fixture.settingsFrame = CGRect(x: 50, y: 200, width: 700, height: 600)
        timer.fireDate = .distantPast
        let deadline = Date(timeIntervalSinceNow: 0.2)
        while fixture.assistant.panel == nil && Date() < deadline {
            RunLoop.main.run(mode: .default, before: deadline)
        }
        #expect(fixture.assistant.panel != nil && fixture.presentations == 1,
            "A Settings window that appears after activation must be found without another activation event")
        #expect(!timer.isValid)
        fixture.tickSettings()
        #expect(fixture.presentations == 1)
    }

    @Test
    func aWindowWaitDoesNotOutliveItsAssistant() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.settingsFrame = nil
        var assistant: PermissionSettingsAssistant? = fixture.makeAssistant(applicationURL: fixture.applicationURL)
        #expect(assistant?.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL) == true)
        assistant = nil
        fixture.tickSettings()
        #expect(fixture.settingsTimers.allSatisfy { !$0.isValid })
        #expect(fixture.presentations == 0)
    }

    @Test
    func onlyAnAcceptedDropDismissesTheAssistant() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        await fixture.settle()
        let panel = try #require(fixture.assistant.panel)
        let image = try #require(panel.contentView?.subviews.compactMap { $0 as? NSStackView }.first?
            .arrangedSubviews.compactMap { $0 as? FileShelfDraggingView }.first)
        let session = NSDraggingSession()
        let frame = panel.frame
        #expect(image.draggingItems().count == 1)
        #expect(fixture.assistant.panel === panel)
        image.draggingSession(session, endedAt: .zero, operation: .copy)
        #expect(fixture.assistant.panel === panel, "An accepted drop outside Settings must not dismiss the helper")
        fixture.settingsFrame = nil
        for operation: NSDragOperation in [[], .generic, .copy] {
            image.draggingSession(session, endedAt: CGPoint(x: 100, y: 400), operation: operation)
            #expect(fixture.assistant.panel === panel && panel.frame == frame,
                "A drag without a Settings destination must preserve the helper and its position")
        }
        fixture.settingsFrame = CGRect(x: 50, y: 200, width: 700, height: 600)
        image.draggingSession(session, endedAt: CGPoint(x: 100, y: 400), operation: [])
        #expect(fixture.assistant.panel === panel, "A rejected drop inside Settings must not dismiss the helper")
        image.draggingSession(session, endedAt: CGPoint(x: 100, y: 400), operation: .copy)
        #expect(fixture.assistant.panel == nil, "Dismiss only after the destination accepts the app bundle")
        fixture.settingsFrame = CGRect(x: 50, y: 200, width: 700, height: 600)
        fixture.assistant.settingsDidActivate()
        fixture.tickSettings()
        #expect(fixture.assistant.panel == nil)
    }

    @Test
    func anOldDragCannotDismissAReplacementAssistantOrCancelItsPreparation() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        await fixture.settle()
        let oldPanel = try #require(fixture.assistant.panel)
        let image = try #require(oldPanel.contentView?.subviews.compactMap { $0 as? NSStackView }.first?
            .arrangedSubviews.compactMap { $0 as? FileShelfDraggingView }.first)
        image.removeFromSuperview()
        fixture.settingsFrame = nil
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.accessibility.settingsURL))
        let session = NSDraggingSession()
        fixture.settingsFrame = CGRect(x: 50, y: 200, width: 700, height: 600)
        image.draggingSession(session, endedAt: CGPoint(x: 100, y: 400), operation: .copy)
        await fixture.settle()
        let replacement = try #require(fixture.assistant.panel)
        image.draggingSession(session, endedAt: CGPoint(x: 100, y: 400), operation: .copy)
        #expect(fixture.assistant.panel === replacement)
    }

    @Test
    func acceptedDropsUseTheSettingsWindowAtTheTimeOfTheDrop() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        #expect(fixture.assistant.openSettings(OnboardingPermissionID.fullDiskAccess.settingsURL))
        await fixture.settle()
        let panel = try #require(fixture.assistant.panel)
        let image = try #require(panel.contentView?.subviews.compactMap { $0 as? NSStackView }.first?
            .arrangedSubviews.compactMap { $0 as? FileShelfDraggingView }.first)
        fixture.settingsFrame = CGRect(x: 900, y: 200, width: 500, height: 600)
        let session = NSDraggingSession()
        image.draggingSession(session, endedAt: CGPoint(x: 100, y: 400), operation: .copy)
        #expect(fixture.assistant.panel === panel, "The old Settings position is not an accepted destination")
        image.draggingSession(session, endedAt: CGPoint(x: 1000, y: 400), operation: .copy)
        #expect(fixture.assistant.panel == nil)
    }

    @Test
    func adjacentPlacementKeepsTheHelperVisibleOnNegativeAndSmallScreens() {
        let screen = CGRect(x: -1600, y: -300, width: 1600, height: 1000)
        let size = CGSize(width: 250, height: 190)
        let right = PermissionSettingsAssistant.frame(size: size,
            settingsFrame: CGRect(x: -1450, y: -100, width: 700, height: 800), visibleFrame: screen)
        #expect(right.minX == -738 && screen.contains(right))
        let left = PermissionSettingsAssistant.frame(size: size,
            settingsFrame: CGRect(x: -700, y: -100, width: 650, height: 800), visibleFrame: screen)
        #expect(left.maxX == -712 && screen.contains(left))
        let unavailable = PermissionSettingsAssistant.frame(size: size, settingsFrame: nil, visibleFrame: screen)
        #expect(unavailable.maxX == screen.maxX - 12 && screen.contains(unavailable))
        let fullScreen = PermissionSettingsAssistant.frame(size: size, settingsFrame: screen, visibleFrame: screen)
        #expect(screen.contains(fullScreen))
        for y in [CGFloat(-900), 1200] {
            let clipped = PermissionSettingsAssistant.frame(size: size,
                settingsFrame: CGRect(x: -1450, y: y, width: 700, height: 800), visibleFrame: screen)
            #expect(screen.contains(clipped))
        }
    }

    @Test
    func systemSettingsBoundsIgnoreOtherAppsAndConvertThePrimaryScreenOrigin() {
        let settingsBounds = CGRect(x: -1200, y: 100, width: 800, height: 900)
        let windows: [[String: Any]] = [
            [kCGWindowOwnerPID as String: 9, kCGWindowLayer as String: 0,
             kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 1400, height: 1200).dictionaryRepresentation],
            [kCGWindowOwnerPID as String: 10, kCGWindowLayer as String: 1,
             kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 900, height: 1000).dictionaryRepresentation],
            [kCGWindowOwnerPID as String: 10, kCGWindowLayer as String: 0,
             kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 2, height: 2).dictionaryRepresentation],
            [kCGWindowOwnerPID as String: 10, kCGWindowLayer as String: 0,
             kCGWindowBounds as String: settingsBounds.dictionaryRepresentation],
        ]
        #expect(PermissionSettingsAssistant.systemSettingsFrame(windowInfo: windows, processIdentifier: 10, mainScreenTop: 1080)
            == CGRect(x: -1200, y: 80, width: 800, height: 900))
        #expect(PermissionSettingsAssistant.systemSettingsFrame(windowInfo: windows, processIdentifier: 11, mainScreenTop: 1080) == nil)
        #expect(PermissionSettingsAssistant.systemSettingsFrame(windowInfo: [], processIdentifier: 10, mainScreenTop: 1080) == nil)
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let applicationURL: URL
        let workspaceCenter = NotificationCenter()
        var canOpen = true
        var opened: [URL] = []
        var presentations = 0
        var settingsFrame: CGRect? = CGRect(x: 50, y: 200, width: 700, height: 600)
        var settingsTimers: [Timer] = []
        var timerHandlers: [@Sendable (Timer) -> Void] = []
        lazy var assistant = makeAssistant(applicationURL: applicationURL)

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-permission-drag-\(UUID().uuidString)")
            applicationURL = root.appendingPathComponent("zisla.app", isDirectory: true)
            try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)
        }

        func makeAssistant(applicationURL: URL, language: AppLanguage = .english) -> PermissionSettingsAssistant {
            PermissionSettingsAssistant(applicationURL: applicationURL,
                openURL: { [unowned self] in self.opened.append($0); return self.canOpen },
                icon: { _ in NSImage(size: NSSize(width: 64, height: 64)) },
                placement: { [unowned self] in (self.settingsFrame, CGRect(x: 0, y: 0, width: 1600, height: 1000)) },
                orderFront: { [unowned self] _ in self.presentations += 1 },
                language: { language },
                timerFactory: { [unowned self] interval, block in
                    let timer = Timer(timeInterval: interval, repeats: true, block: block)
                    timer.fireDate = .distantFuture
                    self.settingsTimers.append(timer)
                    self.timerHandlers.append(block)
                    return timer
                },
                workspaceNotificationCenter: workspaceCenter)
        }

        func settle() async {
            for _ in 0..<3 {
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
            tickSettings()
        }

        func tickSettings() {
            for timer in settingsTimers where timer.isValid { timer.fire() }
        }

        func close() {
            assistant.dismiss()
            try? FileManager.default.removeItem(at: root)
        }
    }
}
