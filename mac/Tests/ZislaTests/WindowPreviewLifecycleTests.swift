import AppKit
import CoreMedia
import CoreVideo
import ScreenCaptureKit
import Testing
import VideoToolbox

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

    @Test(arguments: [WindowPreviewSource.dock, .switcher])
    func bothEntryPointsPresentAFullscreenWindowOmittedByTheAXList(source: WindowPreviewSource) async throws {
        let system = PreviewSystem()
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let ordinary = PreviewSystem.snapshot(11)
        let image = try #require(PreviewSystem.snapshot(12).image)
        let fullscreen = WindowPreviewSnapshot(
            id: 12, title: "Fullscreen", frame: CGRect(x: 0, y: 33, width: 1512, height: 949),
            image: image
        )
        let ghost = WindowPreviewSnapshot(
            id: 13, title: "Auxiliary surface", frame: ordinary.frame.offsetBy(dx: 100, dy: 80), image: nil
        )
        let selection = PreviewSystem.selection(1, source: source)
        var dependencies = system.dependencies()
        dependencies.dockSelection = { selection }
        dependencies.captureWindows = { _ in
            [ordinary, fullscreen, ghost].filter {
                WindowPreviewWindowMatch.isPreviewCandidate(
                    frame: $0.frame, isOnScreen: false, accessibleWindows: [ordinary.frame],
                    screenFrames: [screen]
                )
            }
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)

        if source == .dock {
            let event = try #require(NSEvent.mouseEvent(
                with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 1,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 0, pressure: 0
            ))
            system.globalHandler?(event)
            try #require(system.timers.last).fire()
        } else {
            system.switcher = selection
            controller.beginSwitcher()
        }
        await controller.captureTask?.value

        #expect(controller.windows.map(\.id) == [11, 12],
                "Both preview entry points must retain the off-Space fullscreen window without admitting auxiliary surfaces")
        #expect(controller.windows.last?.image === image)
        #expect(system.presentationAnchors.last == selection.anchor)
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

    @Test(arguments: [WindowPreviewSource.dock, .switcher], [false, true])
    func coldFullscreenPreviewDoesNotRequireVisitingItsSpace(
        source: WindowPreviewSource, browser: Bool
    ) async throws {
        let system = PreviewSystem()
        system.foregroundPID = 3
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = CGRect(x: 0, y: 0, width: 1512, height: browser ? 868 : 949)
        let headers = browser ? [CGRect(x: 0, y: 868, width: 1512, height: 81)] : []
        let sample = try PreviewSystem.videoSampleBuffer()
        let selection = PreviewSystem.selection(2, source: source)
        var dependencies = system.dependencies()
        dependencies.dockSelection = { selection }
        dependencies.captureWindows = { pid in
            let image = try? await WindowPreviewCapture.image(
                for: frame, screenFrames: [screen], companionFrames: headers,
                captureImage: {
                    throw NSError(domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain", code: -3811)
                },
                captureSampleBuffer: { sample }
            )
            return [WindowPreviewSnapshot(id: CGWindowID(pid), title: "Fullscreen", frame: frame, image: image)]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        if source == .dock {
            let event = try #require(NSEvent.mouseEvent(
                with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 1,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 0, pressure: 0
            ))
            system.globalHandler?(event)
            try #require(system.timers.last).fire()
        } else {
            system.switcher = selection
            controller.beginSwitcher()
        }
        await controller.captureTask?.value

        #expect(controller.windows.map(\.id) == [2])
        #expect(controller.windows.first?.image?.size == CGSize(width: 16, height: 10),
                "An inactive fullscreen Space must have a preview on the first request without a foreground cache")
        #expect(system.foregroundPID == 3, "Previewing must not activate the fullscreen application")
    }

    @Test(arguments: [WindowPreviewSource.dock, .switcher])
    func fullscreenPreviewCropsTransparentPaddingAndKeepsOpaqueBlackContent(source: WindowPreviewSource) async throws {
        let system = PreviewSystem()
        system.foregroundPID = 3
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 868)
        let headers = [CGRect(x: 0, y: 868, width: 1512, height: 81)]
        let configuration = WindowPreviewCapture.configuration(for: frame)
        let sample = try PreviewSystem.letterboxedVideoSampleBuffer(configuration: configuration)
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            let image = try await WindowPreviewCapture.image(
                for: frame, screenFrames: [screen], companionFrames: headers,
                captureImage: { throw PreviewCaptureGate.Failure.unavailable },
                captureSampleBuffer: { sample }
            )
            return [WindowPreviewSnapshot(id: CGWindowID(pid), title: "Fullscreen", frame: frame, image: image)]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(2, source: source))
        await controller.captureTask?.value

        let image = try #require(controller.windows.first?.image)
        #expect(image.size == CGSize(width: configuration.width - 4, height: configuration.height),
                "Transparent right margin: expected \(configuration.width - 4)x\(configuration.height), got \(image.size)")
        let bitmap = NSBitmapImageRep(cgImage: try #require(image.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        )))
        let white = try #require(bitmap.colorAt(x: 0, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        let black = try #require(bitmap.colorAt(x: configuration.width - 5, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        #expect(white.redComponent > 0.95 && white.greenComponent > 0.95 && white.blueComponent > 0.95)
        #expect(black.redComponent == 0 && black.greenComponent == 0 && black.blueComponent == 0 && black.alphaComponent == 1,
                "Opaque black page content beside the transparent margin must remain visible")
        #expect(system.foregroundPID == 3)
    }

    @Test
    func ordinaryWindowPreviewKeepsUsingImageCapture() async throws {
        let capture = try #require(PreviewSystem.snapshot(11).image?.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ))
        let image = try await WindowPreviewCapture.image(
            for: CGRect(x: 20, y: 20, width: 300, height: 200),
            screenFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)], companionFrames: [],
            captureImage: { capture },
            captureSampleBuffer: { throw PreviewCaptureGate.Failure.unavailable }
        )
        #expect(image?.size == CGSize(width: 2, height: 2))
    }

    @Test(arguments: [WindowPreviewSource.dock, .switcher], ["transparent", "no-image-buffer", "error"])
    func unavailableFullscreenSamplesRecoverWithoutVisitingTheSpace(
        source: WindowPreviewSource, failure: String
    ) async throws {
        let system = PreviewSystem()
        system.foregroundPID = 3
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let available = try PreviewSystem.videoSampleBuffer()
        let unavailable = try failure == "no-image-buffer"
            ? PreviewSystem.emptySampleBuffer() : PreviewSystem.videoSampleBuffer(alpha: 0)
        var captures = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            captures += 1
            let image = try? await WindowPreviewCapture.image(
                for: frame, screenFrames: [screen], companionFrames: [],
                captureImage: { throw PreviewCaptureGate.Failure.unavailable },
                captureSampleBuffer: {
                    if captures == 2 { return available }
                    if failure == "error" { throw PreviewCaptureGate.Failure.unavailable }
                    return unavailable
                }
            )
            return [WindowPreviewSnapshot(id: CGWindowID(pid), title: "Fullscreen", frame: frame, image: image)]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(2, source: source))
        await controller.captureTask?.value
        #expect(controller.windows.map(\.id) == [2])
        #expect(controller.windows.first?.image == nil, "An unavailable sample must not fabricate a thumbnail")
        let refresh = try #require(system.timers.first { $0.timeInterval == 1 })

        refresh.fire()
        await controller.captureTask?.value
        let image = try #require(controller.windows.first?.image)
        #expect(image.size == CGSize(width: 16, height: 10))
        refresh.fire()
        await controller.captureTask?.value
        #expect(controller.windows.first?.image === image,
                "A later unavailable sample must retain the last valid thumbnail of the same window")
        #expect(system.foregroundPID == 3)
    }

    @Test(arguments: [WindowPreviewSource.dock, .switcher],
          [(captureThrows: false, browser: false), (captureThrows: true, browser: false),
           (captureThrows: false, browser: true), (captureThrows: true, browser: true)])
    func foregroundCaptureWithAnIncompleteAXListSeedsBothPreviewEntryPoints(
        source: WindowPreviewSource, scenario: (captureThrows: Bool, browser: Bool)
    ) async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        system.existingWindowIDs = [11, 12]
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let ordinary = PreviewSystem.snapshot(11)
        let image = try #require(PreviewSystem.snapshot(12).image)
        let frame = scenario.browser ? CGRect(x: 0, y: 0, width: 1512, height: 868)
            : CGRect(x: 0, y: 33, width: 1512, height: 949)
        let headers = scenario.browser ? [CGRect(x: 0, y: 949, width: 1512, height: 33),
                                         CGRect(x: 0, y: 868, width: 1512, height: 81)] : []
        let selection = PreviewSystem.selection(1, source: source)
        var dependencies = system.dependencies()
        dependencies.dockSelection = { selection }
        dependencies.captureWindows = { _ in
            if system.foregroundPID != 1 && scenario.captureThrows {
                throw NSError(domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain", code: -3811)
            }
            let fullscreen = WindowPreviewSnapshot(
                id: 12, title: "Fullscreen", frame: frame, image: system.foregroundPID == 1 ? image : nil
            )
            return [ordinary, fullscreen].filter {
                WindowPreviewWindowMatch.isPreviewCandidate(
                    frame: $0.frame, isOnScreen: system.foregroundPID == 1,
                    accessibleWindows: [ordinary.frame], screenFrames: [screen], companionFrames: headers
                )
            }
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        try #require(system.timers.last).fire()
        await controller.prefetchTask?.value

        system.foregroundPID = 2
        if source == .dock {
            let event = try #require(NSEvent.mouseEvent(
                with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 1,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 0, pressure: 0
            ))
            system.globalHandler?(event)
            try #require(system.timers.last).fire()
        } else {
            system.switcher = selection
            controller.beginSwitcher()
        }
        await controller.captureTask?.value

        #expect(controller.windows.first { $0.id == 12 }?.image === image,
                "Foreground prefetch must cache the AX-omitted fullscreen image before capture becomes unavailable off-Space")
        #expect(system.presentationAnchors.last == selection.anchor)
    }

    @Test(arguments: ["empty", "transparent", "partial", "error"])
    func foregroundCaptureRetriesUntilTheFullscreenImageCanBeCached(failure: String) async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        let visible = PreviewSystem.snapshot(11)
        var captures = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            captures += 1
            guard system.foregroundPID == pid else { return [PreviewSystem.snapshot(11, alpha: nil)] }
            if captures == 1 {
                switch failure {
                case "error": throw PreviewCaptureGate.Failure.unavailable
                case "transparent": return [PreviewSystem.snapshot(11, alpha: nil)]
                case "partial": return [PreviewSystem.snapshot(12), PreviewSystem.snapshot(11, alpha: nil)]
                default: return []
                }
            }
            return [visible]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        system.applicationActivated?()
        try #require(system.timers.last).fire()
        await controller.prefetchTask?.value

        let retry = try #require(system.timers.last)
        #expect(retry.isValid, "A missing full-screen image must be retried while its application is visible")
        retry.fire()
        await controller.prefetchTask?.value
        #expect(captures == 2)
        #expect(!retry.isValid)
        #expect(system.timers.allSatisfy { !$0.isValid }, "A successful capture must end background retries")

        system.foregroundPID = 2
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        #expect(controller.windows.first?.image === visible.image,
                "The successful foreground retry must supply the preview after leaving the full-screen Space")
    }

    @Test
    func unavailableForegroundImagesHaveABoundedRetryBudget() async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        var captures = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { _ in
            captures += 1
            return []
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        system.applicationActivated?()

        for _ in 0..<10 {
            guard let timer = system.timers.last, timer.isValid else { break }
            timer.fire()
            await controller.prefetchTask?.value
        }
        #expect(captures == 4, "One foreground event permits an initial attempt and at most three retries")
        #expect(system.timers.allSatisfy { !$0.isValid })
        #expect(controller.prefetchTask == nil)
    }

    @Test(arguments: ["activation", "selection", "stop", "permission", "termination", "silent-switch"])
    func obsoleteForegroundRetriesCannotCaptureAfterTheirContextEnds(reason: String) async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        var captures: [pid_t] = []
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            captures.append(pid)
            return []
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        try #require(system.timers.last).fire()
        await controller.prefetchTask?.value
        let retry = try #require(system.timers.last)
        try #require(retry.isValid)

        switch reason {
        case "activation":
            system.foregroundPID = 2
            system.applicationActivated?()
        case "selection":
            controller.select(PreviewSystem.selection(1, source: .dock))
            await controller.captureTask?.value
        case "permission":
            system.authorized = false
            controller.refreshPermissions()
        case "termination":
            system.applicationTerminated?(1)
        case "silent-switch":
            system.foregroundPID = 2
        default:
            controller.stop()
        }
        if reason != "silent-switch" { #expect(!retry.isValid) }
        let completedCaptures = captures
        retry.fire()
        await controller.prefetchTask?.value
        #expect(captures == completedCaptures, "An obsolete retry must not capture a departed or newly restoring app")
    }

    @Test
    func aSpaceChangeWithoutAForegroundAppCancelsQueuedPrefetch() async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        var captures: [pid_t] = []
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            captures.append(pid)
            return [PreviewSystem.snapshot(pid)]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        try #require(system.timers.last).fire()
        let queued = try #require(controller.prefetchTask)

        system.foregroundPID = nil
        system.spaceChanged?()
        await queued.value
        #expect(queued.isCancelled)
        #expect(captures.isEmpty, "A transiently missing foreground app must not leave old capture work running")

        system.foregroundPID = 2
        try #require(system.timers.last).fire()
        await controller.prefetchTask?.value
        #expect(captures == [2])
    }

    @Test(arguments: [WindowPreviewSource.dock, .switcher], [false, true])
    func applicationActivationDefersSelectedAndForegroundCapturesUntilTheAnimationSettles(
        source: WindowPreviewSource, spaceChange: Bool
    ) async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        var captures: [pid_t] = []
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            captures.append(pid)
            return [PreviewSystem.snapshot(pid)]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)

        if spaceChange { system.spaceChanged?() } else { system.applicationActivated?() }
        let settling = try #require(system.timers.last)
        #expect(try #require(system.timerDelays.last) >= 0.8,
                "The activation delay must cover the Dock restore animation")
        controller.select(PreviewSystem.selection(1, source: source))
        await controller.captureTask?.value
        let refresh = try #require(system.timers.first { $0.timeInterval == 1 })
        refresh.fire()
        await controller.captureTask?.value
        #expect(captures.isEmpty, "Hovering or polling must not capture an application that is restoring")
        #expect(controller.windows.isEmpty)

        settling.fire()
        await controller.captureTask?.value
        #expect(captures == [1])
        #expect(controller.windows.map(\.id) == [1])
    }

    @Test(arguments: [false, true])
    func aTransitionRejectsAnInFlightCaptureWithoutCachingItsIntermediateImage(
        foreground: Bool
    ) async throws {
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
        defer { controller.stop() }
        controller.configure(enabled: true)
        if foreground {
            try #require(system.timers.last).fire()
        } else {
            controller.select(PreviewSystem.selection(1, source: .dock))
        }
        let old = try #require(foreground ? controller.prefetchTask : controller.captureTask)
        await gate.waitForRequests(1)

        system.applicationActivated?()
        let settling = try #require(system.timers.last)
        gate.finish(0, snapshots: [PreviewSystem.snapshot(11)])
        await old.value
        #expect(old.isCancelled)
        #expect(controller.windows.isEmpty)
        #expect(system.presentations.allSatisfy { $0.isEmpty })

        controller.select(PreviewSystem.selection(1, source: .dock))
        settling.fire()
        await controller.captureTask?.value
        #expect(controller.windows.map(\.id) == [11])
        #expect(controller.windows.first?.image == nil, "A cancelled animation frame must never seed the cache")
    }

    @Test
    func aQueuedForegroundCaptureCannotStartAfterARestoreBegins() async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        var captures = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            captures += 1
            return [PreviewSystem.snapshot(pid)]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        try #require(system.timers.last).fire()
        let queued = try #require(controller.prefetchTask)

        system.applicationActivated?()
        await queued.value
        #expect(captures == 0, "Cancellation must prevent a queued task from even requesting an animation frame")
        #expect(controller.prefetchTask == nil)
        try #require(system.timers.last).fire()
        await controller.prefetchTask?.value
        #expect(captures == 1)
    }

    @Test
    func anOldCaptureCannotClearTheTaskStartedAfterSettling() async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        let gate = PreviewCaptureGate()
        var dependencies = system.dependencies()
        dependencies.captureWindows = { try await gate.capture($0) }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        let old = try #require(controller.captureTask)
        await gate.waitForRequests(1)

        system.applicationActivated?()
        try #require(system.timers.last).fire()
        let pending = controller.captureTask
        #expect(pending != nil && pending != old, "A restore must cancel the old capture before starting another one")
        if pending == nil || pending == old {
            gate.finish(0)
            await old.value
            return
        }
        let settled = try #require(pending)
        await gate.waitForRequests(2)
        gate.finish(0)
        await old.value
        #expect(controller.captureTask == settled, "A cancelled task must not clear a newer refresh")
        try #require(system.timers.first { $0.timeInterval == 1 }).fire()
        #expect(gate.requests.count == 2, "Polling must not duplicate the still-running stable capture")

        gate.finish(1)
        await settled.value
        #expect(controller.windows.map(\.id) == [1])
    }

    @Test
    func activatingAnAlreadyVisiblePreviewHidesItAndRestartsTheSettlingDelay() async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        var captures = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            captures += 1
            return [PreviewSystem.snapshot(pid)]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value

        system.applicationActivated?()
        let first = try #require(system.timers.last)
        #expect(controller.windows.isEmpty)
        #expect((system.presentationAnchors.last ?? nil) == nil)
        system.applicationActivated?()
        let second = try #require(system.timers.last)
        #expect(!first.isValid)
        first.fire()
        await controller.captureTask?.value
        await controller.prefetchTask?.value
        #expect(captures == 1)

        second.fire()
        await controller.captureTask?.value
        #expect(captures == 2)
        #expect(controller.windows.map(\.id) == [1])
    }

    @Test(arguments: [NSEvent.EventType.leftMouseDown, .rightMouseDown], [false, true])
    func onlyADockLeftClickDefersCaptureWithoutAnActivationNotification(
        type: NSEvent.EventType, onDock: Bool
    ) async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        var captures = 0
        var dependencies = system.dependencies()
        dependencies.dockSelection = { onDock ? PreviewSystem.selection(1, source: .dock) : nil }
        dependencies.captureWindows = { pid in
            captures += 1
            return [PreviewSystem.snapshot(pid)]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        let click = try #require(NSEvent.mouseEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: 1,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))

        system.globalHandler?(click)
        let settling = try #require(system.timers.last)
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        #expect(captures == (type == .leftMouseDown && onDock ? 0 : 1))
        settling.fire()
        await controller.captureTask?.value
        #expect(captures == 1)
        #expect(controller.windows.map(\.id) == [1])
    }

    @Test
    func restoringAWindowFromItsPreviewDefersCaptureEvenWhenTheAppIsAlreadyFrontmost() async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        var captures = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            captures += 1
            return [PreviewSystem.snapshot(pid)]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        controller.activate(try #require(controller.windows.first))
        let settling = try #require(system.timers.last)

        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        #expect(captures == 1)
        #expect(controller.windows.isEmpty)
        settling.fire()
        await controller.captureTask?.value
        #expect(captures == 2)
        #expect(system.activations == [1])
    }

    @Test(arguments: ["stop", "permission", "termination"])
    func transitionTimersAreReleasedWhenMonitoringOrTheApplicationEnds(reason: String) async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        let controller = WindowPreviewController(dependencies: system.dependencies())
        defer { controller.stop() }
        controller.configure(enabled: true)
        system.applicationActivated?()
        let settling = try #require(system.timers.last)

        switch reason {
        case "permission":
            system.authorized = false
            controller.refreshPermissions()
        case "termination":
            system.applicationTerminated?(1)
        default:
            controller.stop()
        }
        #expect(!settling.isValid, "A pending transition must not outlive its application or monitoring")
        #expect(controller.captureTask == nil)
        #expect(controller.prefetchTask == nil)

        system.authorized = true
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        #expect(controller.windows.map(\.id) == [1], "A stopped transition must not block later previews")
    }

    @Test
    func aDifferentApplicationCanStillBePreviewedDuringARestoreAnimation() async throws {
        let system = PreviewSystem()
        system.foregroundPID = 1
        var captures: [pid_t] = []
        var dependencies = system.dependencies()
        dependencies.captureWindows = { pid in
            captures.append(pid)
            return [PreviewSystem.snapshot(pid)]
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        system.applicationActivated?()
        let first = try #require(system.timers.last)
        controller.select(PreviewSystem.selection(3, source: .dock))
        await controller.captureTask?.value
        system.foregroundPID = 2
        system.applicationActivated?()
        let second = try #require(system.timers.last)
        #expect(first.isValid, "A second application must not cancel the first application's waiting period")
        #expect(controller.windows.map(\.id) == [3])
        first.fire()
        await controller.prefetchTask?.value
        #expect(captures == [3], "Finishing one restore must not prefetch another application still restoring")
        controller.select(PreviewSystem.selection(1, source: .dock))
        await controller.captureTask?.value
        #expect(controller.windows.map(\.id) == [1])
        controller.select(PreviewSystem.selection(2, source: .dock))
        await controller.captureTask?.value
        #expect(controller.windows.isEmpty)
        second.fire()
        await controller.captureTask?.value
        #expect(controller.windows.map(\.id) == [2])
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
        #expect(controller.windows.map(\.id) == [11])
        #expect(controller.windows.first?.image === first.image,
                "A live off-Space window must retain its preview even when temporarily absent from capture candidates")
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

    @Test(arguments: [WindowPreviewSource.dock, .switcher])
    func captureErrorsRetainTheCachedImageOfALiveOffSpaceWindow(source: WindowPreviewSource) async throws {
        let system = PreviewSystem()
        system.existingWindowIDs = [11]
        let visible = PreviewSystem.snapshot(11)
        var captures = 0
        var dependencies = system.dependencies()
        dependencies.captureWindows = { _ in
            captures += 1
            if captures == 1 { return [visible] }
            throw PreviewCaptureGate.Failure.unavailable
        }
        let controller = WindowPreviewController(dependencies: dependencies)
        defer { controller.stop() }
        controller.configure(enabled: true)
        controller.select(PreviewSystem.selection(1, source: source))
        await controller.captureTask?.value
        let refresh = try #require(system.timers.first { $0.timeInterval == 1 })

        refresh.fire()
        await controller.captureTask?.value
        #expect(controller.windows.map(\.id) == [11])
        #expect(controller.windows.first?.image === visible.image)
        #expect(system.presentationAnchors.last == PreviewSystem.selection(1, source: source).anchor)

        system.existingWindowIDs = []
        refresh.fire()
        await controller.captureTask?.value
        #expect(controller.windows.isEmpty, "A closed window must not survive through the cached fallback")
    }

    @Test(arguments: [Optional(Set<CGWindowID>([11])), Set<CGWindowID>(), nil])
    func missingCaptureCandidatesOnlyUseCacheWhenWindowLivenessIsConfirmed(liveIDs: Set<CGWindowID>?) {
        var cache = WindowPreviewImageCache()
        let first = PreviewSystem.snapshot(11)
        let other = PreviewSystem.snapshot(11, alpha: 0.5)
        _ = cache.reconcile([first], processIdentifier: 1, presentWindowIDs: { _ in [11] })
        _ = cache.reconcile([other], processIdentifier: 2, presentWindowIDs: { _ in [11] })

        let result = cache.reconcile([], processIdentifier: 1, presentWindowIDs: { _ in liveIDs })
        #expect(result.map(\.id) == (liveIDs == [11] ? [11] : []))
        if liveIDs == [11] { #expect(result.first?.image === first.image) }
        let otherResult = cache.reconcile([], processIdentifier: 2, presentWindowIDs: { _ in [11] })
        #expect(otherResult.first?.image === other.image, "Cached windows must remain isolated by process")
    }

    @Test
    func cachedFallbackDoesNotDuplicateFreshlyCapturedWindows() {
        var cache = WindowPreviewImageCache()
        let first = PreviewSystem.snapshot(11)
        let offSpace = PreviewSystem.snapshot(12)
        let refreshed = PreviewSystem.snapshot(11, alpha: 0.5)
        _ = cache.reconcile([first, offSpace], processIdentifier: 1, presentWindowIDs: { _ in [11, 12] })

        let result = cache.reconcile([refreshed], processIdentifier: 1, presentWindowIDs: { _ in [11, 12] })
        #expect(result.map(\.id) == [11, 12])
        #expect(result.first?.image === refreshed.image)
        #expect(result.last?.image === offSpace.image)
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
    var timerDelays: [TimeInterval] = []
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
            self.timerDelays.append(interval)
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

    static func videoSampleBuffer(alpha: CGFloat = 1, size: CGSize = CGSize(width: 16, height: 10)) throws -> CMSampleBuffer {
        let width = Int(size.width)
        let height = Int(size.height)
        var pixel: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                   [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel) == kCVReturnSuccess)
        let buffer = try #require(pixel)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let context = try #require(CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ))
        context.setBlendMode(.copy)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try videoSampleBuffer(from: buffer)
    }

    static func letterboxedVideoSampleBuffer(configuration: SCStreamConfiguration) throws -> CMSampleBuffer {
        let size = CGSize(width: configuration.width, height: configuration.height)
        let source = try #require(CMSampleBufferGetImageBuffer(videoSampleBuffer(size: size)))
        do {
            CVPixelBufferLockBaseAddress(source, [])
            defer { CVPixelBufferUnlockBaseAddress(source, []) }
            let context = try #require(CGContext(
                data: CVPixelBufferGetBaseAddress(source), width: configuration.width, height: configuration.height,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(source),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            ))
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: configuration.width - 6, height: configuration.height))
            context.clear(CGRect(x: configuration.width - 4, y: 0, width: 4, height: configuration.height))
        }
        var destination: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, configuration.width, configuration.height, configuration.pixelFormat,
                                   [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &destination) == kCVReturnSuccess)
        let buffer = try #require(destination)
        var transfer: VTPixelTransferSession?
        #expect(VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &transfer) == noErr)
        let session = try #require(transfer)
        defer { VTPixelTransferSessionInvalidate(session) }
        #expect(VTPixelTransferSessionTransferImage(session, from: source, to: buffer) == noErr)
        return try videoSampleBuffer(from: buffer)
    }

    private static func videoSampleBuffer(from buffer: CVPixelBuffer) throws -> CMSampleBuffer {
        var format: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                            formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                        formatDescription: try #require(format), sampleTiming: &timing,
                                                        sampleBufferOut: &sample) == noErr)
        return try #require(sample)
    }

    static func emptySampleBuffer() throws -> CMSampleBuffer {
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: nil, formatDescription: nil, sampleCount: 0,
            sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 0,
            sampleSizeArray: nil, sampleBufferOut: &sample
        ) == noErr)
        return try #require(sample)
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
