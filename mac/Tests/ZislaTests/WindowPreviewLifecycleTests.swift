import AppKit
import Testing

@testable import Zisla

@Suite @MainActor
struct WindowPreviewLifecycleTests {
    @Test
    func restoringSettingsOnlyChecksPermissionsAndRepeatedConfigurationIsIdempotent() {
        let system = PreviewSystem()
        system.authorized = false
        let controller = WindowPreviewController(dependencies: system.dependencies())
        defer { controller.stop() }

        controller.configure(enabled: true)
        controller.configure(enabled: true, requestPermissions: true)
        #expect(system.permissionRequests == 0)
        #expect(system.monitors.isEmpty)

        system.authorized = true
        controller.refreshPermissions()
        controller.configure(enabled: true)
        #expect(system.monitors.count == 2)
        #expect(system.permissionRequests == 0)

        controller.stop()
        controller.refreshPermissions()
        #expect(system.monitors.isEmpty)
    }

    @Test
    func explicitEnableRequestsPermissionsOnlyOnTheDisabledToEnabledTransition() {
        let system = PreviewSystem()
        system.authorized = false
        let controller = WindowPreviewController(dependencies: system.dependencies())
        defer { controller.stop() }

        controller.configure(enabled: true, requestPermissions: true)
        controller.configure(enabled: true, requestPermissions: true)
        #expect(system.permissionRequests == 1)
        #expect(system.monitors.isEmpty)

        controller.configure(enabled: false, requestPermissions: true)
        controller.configure(enabled: true, requestPermissions: true)
        #expect(system.permissionRequests == 2)
    }

    @Test(arguments: [true, false])
    func partialMonitorInstallationIsCleanedUpAndCanRecover(globalFails: Bool) {
        let system = PreviewSystem()
        system.globalMonitorFails = globalFails
        system.localMonitorFails = !globalFails
        let controller = WindowPreviewController(dependencies: system.dependencies())
        defer { controller.stop() }

        controller.configure(enabled: true)
        #expect(system.monitors.isEmpty)
        controller.refreshPermissions()
        #expect(system.monitors.isEmpty)

        system.globalMonitorFails = false
        system.localMonitorFails = false
        controller.refreshPermissions()
        #expect(system.monitors.count == 2)
    }

    @Test
    func switchingFromDockCancelsItsPendingDismissal() async throws {
        let system = PreviewSystem()
        let controller = WindowPreviewController(dependencies: system.dependencies())
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        controller.scheduleDismiss()
        let dismissal = try #require(system.timers.last)

        system.switcher = PreviewSystem.selection(2, source: .switcher)
        controller.beginSwitcher()
        await controller.captureTask?.value
        dismissal.fire()

        #expect(!dismissal.isValid)
        #expect(controller.windows.map(\.id) == [2])
        #expect(controller.appName == "App 2")
    }

    @Test
    func clickingSwitcherPreviewStopsPollingAndCannotReopenIt() async throws {
        let system = PreviewSystem()
        system.switcher = PreviewSystem.selection(2, source: .switcher)
        let controller = WindowPreviewController(dependencies: system.dependencies())
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.beginSwitcher()
        await controller.captureTask?.value
        let snapshot = try #require(controller.windows.first)

        controller.activate(snapshot)
        system.timers.forEach { $0.fire() }

        #expect(system.activations == [2])
        #expect(system.solePreviewActivations == [true])
        #expect(system.timers.allSatisfy { !$0.isValid })
        #expect(controller.windows.isEmpty)
        #expect(controller.appName.isEmpty)
        #expect(controller.captureTask == nil)
    }

    @Test
    func switcherOmitsTheApplicationHeaderWhileDockKeepsIt() {
        let system = PreviewSystem()
        let controller = WindowPreviewController(dependencies: system.dependencies())
        defer { controller.stop() }
        controller.configure(enabled: true)

        controller.select(PreviewSystem.selection(1, source: .dock))
        #expect(controller.showsAppHeader)

        controller.select(PreviewSystem.selection(2, source: .switcher))
        #expect(!controller.showsAppHeader)
    }

    @Test
    func clickingDockPreviewActivatesTheSelectedWindow() async throws {
        let system = PreviewSystem()
        var dependencies = system.dependencies()
        dependencies.captureWindows = { _ in [PreviewSystem.snapshot(11), PreviewSystem.snapshot(12)] }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(2, source: .dock))
        await controller.captureTask?.value
        let snapshot = try #require(controller.windows.last)

        controller.activate(snapshot)

        #expect(system.activations == [2])
        #expect(system.activatedWindowIDs == [12])
        #expect(system.solePreviewActivations == [false])
        #expect(controller.windows.isEmpty)
    }

    @Test
    func commandModifierDetectsNativeSwitcherWithoutReceivingItsTabKey() async throws {
        let system = PreviewSystem()
        let controller = WindowPreviewController(dependencies: system.dependencies())
        defer { controller.stop() }
        controller.configure(enabled: true)
        let commandDown = try #require(NSEvent.keyEvent(
            with: .flagsChanged, location: .zero, modifierFlags: .command, timestamp: 1,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 55
        ))
        system.globalHandler?(commandDown)
        #expect(controller.windows.isEmpty)
        let poll = try #require(system.timers.first { $0.timeInterval == 0.12 })

        system.switcher = PreviewSystem.selection(3, source: .switcher)
        poll.fire()
        await controller.captureTask?.value
        #expect(controller.windows.map(\.id) == [3])

        system.commandPressed = false
        poll.fire()
        #expect(controller.windows.isEmpty)
        #expect(!poll.isValid)
    }

    @Test
    func disappearingSwitcherHidesItsPreviousPreviewWhileCommandRemainsHeld() async throws {
        let system = PreviewSystem()
        system.switcher = PreviewSystem.selection(3, source: .switcher)
        let controller = WindowPreviewController(dependencies: system.dependencies())
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.beginSwitcher()
        await controller.captureTask?.value

        system.switcher = nil
        try #require(system.timers.first { $0.timeInterval == 0.12 }).fire()
        #expect(controller.windows.isEmpty)
        #expect(controller.appName.isEmpty)
    }

    @Test
    func movingSelectedSwitcherIconRepositionsThePreviewDuringAndAfterCapture() async throws {
        let system = PreviewSystem()
        let capture = PreviewCaptureGate()
        var dependencies = system.dependencies()
        dependencies.captureWindows = { try await capture.capture($0) }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(3, source: .switcher, anchorX: 300))
        let task = try #require(controller.captureTask)
        await capture.waitForRequests(1)

        controller.select(PreviewSystem.selection(3, source: .switcher, anchorX: 600))
        capture.finish(0)
        await task.value
        #expect(system.presentationAnchors.last == CGRect(x: 600, y: 0, width: 48, height: 48))

        controller.select(PreviewSystem.selection(3, source: .switcher, anchorX: 820))
        #expect(system.presentationAnchors.last == CGRect(x: 820, y: 0, width: 48, height: 48))
        #expect(capture.requests.count == 1)

        let presentationCount = system.presentationAnchors.count
        controller.select(PreviewSystem.selection(3, source: .switcher, anchorX: 820))
        #expect(system.presentationAnchors.count == presentationCount)
    }

    @Test(arguments: [false, true])
    func staleCaptureCompletionCannotReplaceOrDismissANewerSelection(fails: Bool) async throws {
        let system = PreviewSystem()
        let capture = PreviewCaptureGate()
        var dependencies = system.dependencies()
        dependencies.captureWindows = { try await capture.capture($0) }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        let first = try #require(controller.captureTask)
        await capture.waitForRequests(1)

        controller.select(PreviewSystem.selection(2, source: .dock))
        let second = try #require(controller.captureTask)
        await capture.waitForRequests(2)
        capture.finish(1)
        await second.value
        capture.finish(0, fails: fails)
        await first.value

        #expect(controller.windows.map(\.id) == [2])
        #expect(controller.appName == "App 2")
        #expect(system.presentations.filter { !$0.isEmpty } == [[2]])
    }

    @Test(arguments: [false, true])
    func disablingOrRevokingPermissionsRejectsACaptureAlreadyInFlight(revoked: Bool) async throws {
        let system = PreviewSystem()
        let capture = PreviewCaptureGate()
        var dependencies = system.dependencies()
        dependencies.captureWindows = { try await capture.capture($0) }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        let task = try #require(controller.captureTask)
        await capture.waitForRequests(1)

        if revoked { system.authorized = false } else { controller.configure(enabled: false) }
        capture.finish(0)
        await task.value

        #expect(controller.windows.isEmpty)
        #expect(controller.appName.isEmpty)
        #expect(system.monitors.isEmpty)
        #expect(system.timers.allSatisfy { !$0.isValid })
        #expect(system.presentations.allSatisfy { $0.isEmpty })
    }

    @Test
    func captureFailureHidesStaleImagesAndNextRefreshRecoversWithoutMovingThePointer() async throws {
        let system = PreviewSystem()
        let capture = PreviewCaptureGate()
        var dependencies = system.dependencies()
        dependencies.captureWindows = { try await capture.capture($0) }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        let first = try #require(controller.captureTask)
        await capture.waitForRequests(1)
        let refresh = try #require(system.timers.first { $0.timeInterval == 1 })
        refresh.fire()
        refresh.fire()
        #expect(capture.requests.count == 1)
        capture.finish(0)
        await first.value
        #expect(controller.windows.map(\.id) == [1])

        refresh.fire()
        let failed = try #require(controller.captureTask)
        await capture.waitForRequests(2)
        capture.finish(1, fails: true)
        await failed.value
        #expect(controller.windows.isEmpty)
        #expect(refresh.isValid)

        refresh.fire()
        let retry = try #require(controller.captureTask)
        await capture.waitForRequests(3)
        capture.finish(2)
        await retry.value
        #expect(controller.windows.map(\.id) == [1])
    }

    @Test
    func verifiedWindowRemainsAvailableWhenItsCaptureTemporarilyFails() async {
        let system = PreviewSystem()
        var dependencies = system.dependencies()
        dependencies.captureWindows = { _ in [
            PreviewSystem.snapshot(11, alpha: nil),
            PreviewSystem.snapshot(12, alpha: 1),
        ] }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value

        #expect(controller.windows.map(\.id) == [11, 12])
        #expect(controller.windows.first?.image == nil)
        #expect(system.presentations.last == [11, 12])
    }

    @Test
    func verifiedFullScreenWindowKeepsACardWhenItsImageIsUnavailable() async {
        let system = PreviewSystem()
        var dependencies = system.dependencies()
        dependencies.captureWindows = { _ in [
            WindowPreviewSnapshot(
                id: 11, title: "ChatGPT", frame: CGRect(x: 0, y: 0, width: 1512, height: 949), image: nil
            ),
        ] }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value

        #expect(controller.windows.map(\.id) == [11])
        #expect(controller.windows.first?.image == nil)
        #expect(system.presentations.last == [11])
    }

    @Test
    func aFailedOffSpaceCaptureUsesTheLastSuccessfulImageAndThenRefreshesIt() async throws {
        let system = PreviewSystem()
        let firstImage = try #require(PreviewSystem.snapshot(11).image)
        let refreshedImage = try #require(PreviewSystem.snapshot(11, alpha: 0.5).image)
        var captures = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { _ in
            captures += 1
            let image: NSImage? = switch captures {
            case 1: firstImage
            case 3: refreshedImage
            default: nil
            }
            return [WindowPreviewSnapshot(
                id: 11, title: "Frame \(captures)",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 949), image: image
            )]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        let refresh = try #require(system.timers.first { $0.timeInterval == 1 })

        refresh.fire()
        await controller.captureTask?.value
        #expect(controller.windows.first?.image === firstImage)
        #expect(controller.windows.first?.title == "Frame 2")

        refresh.fire()
        await controller.captureTask?.value
        #expect(controller.windows.first?.image === refreshedImage)
    }

    @Test
    func cachedImagesAreIsolatedByProcessAndRemovedWithClosedWindows() async throws {
        let system = PreviewSystem()
        let firstImage = try #require(PreviewSystem.snapshot(11).image)
        let secondImage = try #require(PreviewSystem.snapshot(11, alpha: 0.5).image)
        var firstAppCaptures = 0
        var secondAppCaptures = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            if pid == 1 {
                firstAppCaptures += 1
                return firstAppCaptures == 2 ? [] : [WindowPreviewSnapshot(
                    id: 11, title: "First", frame: .zero,
                    image: firstAppCaptures == 1 ? firstImage : nil
                )]
            }
            secondAppCaptures += 1
            return [WindowPreviewSnapshot(
                id: 11, title: "Second", frame: .zero,
                image: secondAppCaptures == 2 ? secondImage : nil
            )]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)

        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        controller.select(PreviewSystem.selection(2, source: .dock))
        await controller.captureTask?.value
        #expect(controller.windows.first?.image == nil)
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        #expect(controller.windows.isEmpty)
        controller.select(PreviewSystem.selection(2, source: .dock))
        await controller.captureTask?.value
        #expect(controller.windows.first?.image === secondImage)
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        #expect(controller.windows.first?.image == nil)
    }

    @Test
    func foregroundCaptureSeedsFullscreenPreviewAndCoalescesWorkspaceEvents() async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        let visible = PreviewSystem.snapshot(11)
        var captures: [pid_t] = []
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            captures.append(pid)
            return [WindowPreviewSnapshot(
                id: 11, title: "Fullscreen", frame: visible.frame,
                image: captures.count == 1 ? visible.image : nil
            )]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        let initial = try #require(system.timers.last)

        system.applicationActivated?()
        system.spaceChanged?()
        let scheduled = system.timers
        #expect(scheduled.count == 3)
        #expect(!initial.isValid)
        #expect(scheduled.filter(\.isValid).count == 1)
        scheduled.last?.fire()
        await controller.prefetchTask?.value
        #expect(captures == [1])

        system.foregroundPID = nil
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        #expect(controller.windows.first?.image === visible.image)
        #expect(captures == [1, 1])
    }

    @Test
    func stoppingCancelsAnInFlightForegroundCaptureAndClearsItsImage() async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        let gate = PreviewCaptureGate()
        var calls = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            calls += 1
            if calls == 1 { return try await gate.capture(pid) }
            return [PreviewSystem.snapshot(11, alpha: nil)]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        controller.configure(enabled: true)
        try #require(system.timers.last).fire()
        let task = try #require(controller.prefetchTask)
        await gate.waitForRequests(1)

        controller.stop()
        gate.finish(0)
        await task.value
        #expect(task.isCancelled)
        #expect(system.workspaceObservers.isEmpty)
        #expect(system.timers.allSatisfy { !$0.isValid })

        system.foregroundPID = nil
        controller.configure(enabled: true)
        defer { controller.stop() }
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        #expect(controller.windows.first?.image == nil)
    }

    @Test
    func applicationTerminationDropsItsCachedWindowImage() async throws {
        let system = PreviewSystem()
        let visible = PreviewSystem.snapshot(11)
        var captures = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { _ in
            captures += 1
            return [WindowPreviewSnapshot(
                id: 11, title: "Fullscreen", frame: visible.frame,
                image: captures == 1 ? visible.image : nil
            )]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value

        system.applicationTerminated?(1)
        #expect(controller.windows.isEmpty)
        #expect(system.presentations.last == [])
        controller.select(PreviewSystem.selection(2, source: .dock))
        await controller.captureTask?.value
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        #expect(controller.windows.first?.image == nil)
    }

    @Test
    func olderForegroundCaptureCannotOverwriteANewerSelectedWindowImage() async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        let gate = PreviewCaptureGate()
        let old = PreviewSystem.snapshot(11)
        let newer = PreviewSystem.snapshot(11, alpha: 0.5)
        var calls = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            calls += 1
            if calls == 1 { return try await gate.capture(pid) }
            return [calls == 2 ? newer : PreviewSystem.snapshot(11, alpha: nil)]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        try #require(system.timers.last).fire()
        let prefetch = try #require(controller.prefetchTask)
        await gate.waitForRequests(1)

        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        gate.finish(0, snapshots: [old])
        await prefetch.value
        try #require(system.timers.first { $0.timeInterval == 1 }).fire()
        await controller.captureTask?.value

        #expect(controller.windows.first?.image === newer.image)
    }

    @Test
    func aTemporaryEmptyCandidateListRetainsALiveOffSpaceWindowImage() async throws {
        let system = PreviewSystem()
        system.existingWindowIDs = [11]
        let first = PreviewSystem.snapshot(11)
        var captures = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { _ in
            captures += 1
            switch captures {
            case 1: return [first]
            case 2, 4: return []
            default: return [PreviewSystem.snapshot(11, alpha: nil)]
            }
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        let refresh = try #require(system.timers.first { $0.timeInterval == 1 })

        refresh.fire()
        await controller.captureTask?.value
        #expect(controller.windows.isEmpty)
        refresh.fire()
        await controller.captureTask?.value
        #expect(controller.windows.first?.image === first.image)

        system.existingWindowIDs = []
        refresh.fire()
        await controller.captureTask?.value
        refresh.fire()
        await controller.captureTask?.value
        #expect(controller.windows.first?.image == nil)
    }

    @Test
    func cacheEvictsTheOldestImageWhenItsLimitIsReached() throws {
        var cache = WindowPreviewImageCache(limit: 2)
        let first = PreviewSystem.snapshot(11)
        let second = PreviewSystem.snapshot(12)
        let third = PreviewSystem.snapshot(13)
        for snapshot in [first, second, third] {
            _ = cache.reconcile([snapshot], processIdentifier: 1, presentWindowIDs: { _ in [11, 12, 13] })
        }
        let missing = [first, second, third].map {
            WindowPreviewSnapshot(id: $0.id, title: $0.title, frame: $0.frame, image: nil)
        }
        let result = cache.reconcile(missing, processIdentifier: 1, presentWindowIDs: { _ in [11, 12, 13] })

        #expect(result[0].image == nil)
        #expect(result[1].image === second.image)
        #expect(result[2].image === third.image)
    }

    @Test
    func disablingTheFeatureClearsPreviouslyCapturedImages() async throws {
        let system = PreviewSystem()
        let visible = PreviewSystem.snapshot(11)
        var captures = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { _ in
            captures += 1
            return [WindowPreviewSnapshot(
                id: 11, title: "Fullscreen", frame: visible.frame,
                image: captures == 1 ? visible.image : nil
            )]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value

        controller.configure(enabled: false)
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        #expect(controller.windows.first?.image == nil)
    }

    @Test
    func aStalePreviewCannotActivateTheNewlySelectedApplication() async {
        let system = PreviewSystem()
        let controller = WindowPreviewController(dependencies: system.dependencies())
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(2, source: .dock))
        await controller.captureTask?.value

        controller.activate(PreviewSystem.snapshot(1))
        #expect(system.activations.isEmpty)
        #expect(controller.windows.map(\.id) == [2])
    }
}

@MainActor
private final class PreviewSystem {
    var authorized = true
    var permissionRequests = 0
    var globalMonitorFails = false
    var localMonitorFails = false
    var monitors: [NSObject] = []
    var globalHandler: ((NSEvent) -> Void)?
    var applicationActivated: (() -> Void)?
    var applicationTerminated: ((pid_t) -> Void)?
    var spaceChanged: (() -> Void)?
    var foregroundPID: pid_t?
    var existingWindowIDs: Set<CGWindowID> = []
    var workspaceObservers: [NSObject] = []
    var timers: [Timer] = []
    var switcher: WindowPreviewSelection?
    var commandPressed = true
    var presentations: [[CGWindowID]] = []
    var presentationAnchors: [CGRect?] = []
    var activations: [pid_t] = []
    var activatedWindowIDs: [CGWindowID] = []
    var solePreviewActivations: [Bool] = []

    func dependencies() -> WindowPreviewController.Dependencies {
        var value = WindowPreviewController.Dependencies()
        value.hasPermissions = { self.authorized }
        value.requestPermissions = { self.permissionRequests += 1 }
        value.addGlobalMonitor = { handler in
            self.globalHandler = handler
            guard !self.globalMonitorFails else { return nil }
            let monitor = NSObject()
            self.monitors.append(monitor)
            return monitor
        }
        value.addLocalMonitor = { _ in
            guard !self.localMonitorFails else { return nil }
            let monitor = NSObject()
            self.monitors.append(monitor)
            return monitor
        }
        value.removeMonitor = { token in self.monitors.removeAll { $0 === token as AnyObject } }
        value.addSpaceChangeObserver = { action in
            self.spaceChanged = action
            let token = NSObject()
            self.workspaceObservers.append(token)
            return token
        }
        value.removeWorkspaceObserver = { token in
            self.workspaceObservers.removeAll { $0 === token as AnyObject }
        }
        value.addApplicationActivationObserver = { action in
            self.applicationActivated = action
            let token = NSObject()
            self.workspaceObservers.append(token)
            return token
        }
        value.addApplicationTerminationObserver = { action in
            self.applicationTerminated = action
            let token = NSObject()
            self.workspaceObservers.append(token)
            return token
        }
        value.frontmostProcessIdentifier = { self.foregroundPID }
        value.presentWindowIDs = { _ in self.existingWindowIDs }
        value.timer = { interval, repeats, action in
            let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
                MainActor.assumeIsolated { action() }
            }
            self.timers.append(timer)
            return timer
        }
        value.captureWindows = { [Self.snapshot($0)] }
        value.dockSelection = { nil }
        value.switcherSelection = { self.switcher }
        value.commandPressed = { self.commandPressed }
        value.present = { controller, selection in
            self.presentations.append(controller.windows.map(\.id))
            self.presentationAnchors.append(selection?.anchor)
        }
        value.activate = { identifier, snapshot, isOnlyPreview in
            self.activations.append(identifier)
            self.activatedWindowIDs.append(snapshot.id)
            self.solePreviewActivations.append(isOnlyPreview)
        }
        return value
    }

    static func selection(
        _ identifier: pid_t,
        source: WindowPreviewSource,
        anchorX: CGFloat = 100
    ) -> WindowPreviewSelection {
        WindowPreviewSelection(
            processIdentifier: identifier, appName: "App \(identifier)", icon: nil,
            anchor: CGRect(x: anchorX, y: 0, width: 48, height: 48), source: source
        )
    }

    static func snapshot(_ identifier: pid_t, alpha: CGFloat? = 1) -> WindowPreviewSnapshot {
        WindowPreviewSnapshot(
            id: CGWindowID(identifier), title: "Document \(identifier)",
            frame: CGRect(x: 20, y: 20, width: 300, height: 200),
            image: alpha.map { image(alpha: $0) }
        )
    }

    private static func image(alpha: CGFloat) -> NSImage {
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: 2, height: 2))
    }
}

@MainActor
private final class PreviewCaptureGate {
    enum Failure: Error { case unavailable }
    var requests: [(pid_t, CheckedContinuation<[WindowPreviewSnapshot], any Error>)] = []
    private var waiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    func capture(_ identifier: pid_t) async throws -> [WindowPreviewSnapshot] {
        try await withCheckedThrowingContinuation { continuation in
            requests.append((identifier, continuation))
            if let waiter, requests.count >= waiter.count {
                self.waiter = nil
                waiter.continuation.resume()
            }
        }
    }

    func waitForRequests(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiter = (count, $0) }
    }

    func finish(_ index: Int, fails: Bool = false, snapshots: [WindowPreviewSnapshot]? = nil) {
        if fails {
            requests[index].1.resume(throwing: Failure.unavailable)
        } else {
            requests[index].1.resume(returning: snapshots ?? [PreviewSystem.snapshot(requests[index].0)])
        }
    }
}
