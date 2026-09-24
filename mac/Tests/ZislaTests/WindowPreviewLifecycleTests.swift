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
        #expect(system.timers.allSatisfy { !$0.isValid })
        #expect(controller.windows.isEmpty)
        #expect(controller.appName.isEmpty)
        #expect(controller.captureTask == nil)
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
        #expect(system.timers.allSatisfy { !$0.isValid })
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
    var timers: [Timer] = []
    var switcher: WindowPreviewSelection?
    var commandPressed = true
    var presentations: [[CGWindowID]] = []
    var activations: [pid_t] = []

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
        value.present = { controller, _ in self.presentations.append(controller.windows.map(\.id)) }
        value.activate = { identifier, _ in self.activations.append(identifier) }
        return value
    }

    static func selection(_ identifier: pid_t, source: WindowPreviewSource) -> WindowPreviewSelection {
        WindowPreviewSelection(
            processIdentifier: identifier, appName: "App \(identifier)", icon: nil,
            anchor: CGRect(x: 100, y: 0, width: 48, height: 48), source: source
        )
    }

    static func snapshot(_ identifier: pid_t) -> WindowPreviewSnapshot {
        WindowPreviewSnapshot(
            id: CGWindowID(identifier), title: "Document \(identifier)",
            frame: CGRect(x: 20, y: 20, width: 300, height: 200), image: nil
        )
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

    func finish(_ index: Int, fails: Bool = false) {
        if fails {
            requests[index].1.resume(throwing: Failure.unavailable)
        } else {
            requests[index].1.resume(returning: [PreviewSystem.snapshot(requests[index].0)])
        }
    }
}
