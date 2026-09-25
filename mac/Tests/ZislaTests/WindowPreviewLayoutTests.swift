import CoreGraphics
import ScreenCaptureKit
import SwiftUI
import Testing

@testable import Zisla

struct WindowPreviewLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    private let panel = CGSize(width: 420, height: 188)

    @Test
    func quartzWindowCoordinatesMatchAccessibilityCoordinates() {
        let quartz = CGRect(x: -800, y: 100, width: 400, height: 250)
        let result = WindowPreviewLayout.appKitFrame(for: quartz, mainScreenTop: 800)

        #expect(result == CGRect(x: -800, y: 450, width: 400, height: 250))
    }

    @Test
    func dockHitTestingUsesQuartzPointerCoordinatesAcrossDisplays() {
        #expect(WindowPreviewLayout.quartzPoint(for: CGPoint(x: 40, y: 50), mainScreenTop: 800)
            == CGPoint(x: 40, y: 750))
        #expect(WindowPreviewLayout.quartzPoint(for: CGPoint(x: -600, y: -100), mainScreenTop: 800)
            == CGPoint(x: -600, y: 900))
    }

    @Test
    func bottomDockPreviewAppearsAboveItsIcon() {
        let icon = CGRect(x: 550, y: 5, width: 48, height: 48)
        let result = WindowPreviewLayout.frame(anchor: icon, size: panel, visibleFrame: screen, isSwitcher: false)

        #expect(result.minY == icon.maxY + 10)
        #expect(result.midX == icon.midX)
    }

    @Test
    func sideDockPreviewAppearsInsideTheDisplay() {
        let icon = CGRect(x: 0, y: 370, width: 48, height: 48)
        let result = WindowPreviewLayout.frame(anchor: icon, size: panel, visibleFrame: screen, isSwitcher: false)

        #expect(result.minX == icon.maxX + 10)
        #expect(result.minY >= screen.minY)
        #expect(result.maxY <= screen.maxY)
    }

    @Test
    func switcherPreviewMovesBelowWhenThereIsNoRoomAbove() {
        let switcher = CGRect(x: 300, y: 620, width: 600, height: 120)
        let result = WindowPreviewLayout.frame(anchor: switcher, size: panel, visibleFrame: screen, isSwitcher: true)

        #expect(result.maxY == switcher.minY - 10)
    }

    @Test
    func switcherPreviewTracksTheSelectedIconAcrossTheList() {
        let leftIcon = CGRect(x: 300, y: 380, width: 48, height: 48)
        let rightIcon = CGRect(x: 820, y: 380, width: 48, height: 48)
        let left = WindowPreviewLayout.frame(anchor: leftIcon, size: panel, visibleFrame: screen, isSwitcher: true)
        let right = WindowPreviewLayout.frame(anchor: rightIcon, size: panel, visibleFrame: screen, isSwitcher: true)

        #expect(left.midX == leftIcon.midX)
        #expect(right.midX == rightIcon.midX)
        #expect(left.minX != right.minX)
        #expect(left.minY == leftIcon.maxY + 10)
    }

    @Test
    func switcherPreviewClearsTheWholeSwitcherBarWhileFollowingTheSelectedIcon() {
        let icon = CGRect(x: 550, y: 370, width: 48, height: 48)
        let switcherBar = CGRect(x: 280, y: 340, width: 640, height: 110)
        let anchor = WindowPreviewLayout.switcherAnchor(icon: icon, list: switcherBar)
        let result = WindowPreviewLayout.frame(anchor: anchor, size: panel, visibleFrame: screen, isSwitcher: true)

        #expect(result.minY == switcherBar.maxY + 10)
        #expect(result.midX == icon.midX)
        #expect(WindowPreviewLayout.switcherAnchor(icon: icon, list: nil) == icon)
        #expect(WindowPreviewLayout.switcherAnchor(icon: icon, list: .zero) == icon)
        #expect(WindowPreviewLayout.switcherAnchor(
            icon: icon, list: CGRect(x: 0, y: 0, width: 100, height: 100)
        ) == icon)
        #expect(WindowPreviewLayout.switcherAnchor(
            icon: icon, list: CGRect(x: 0, y: 0, width: 1200, height: 800)
        ) == icon)
    }

    @Test
    func previewIsClampedToOffsetScreenBounds() {
        let external = CGRect(x: -1600, y: -200, width: 1600, height: 900)
        let icon = CGRect(x: -20, y: -195, width: 48, height: 48)
        let result = WindowPreviewLayout.frame(anchor: icon, size: panel, visibleFrame: external, isSwitcher: false)

        #expect(result.minX >= external.minX)
        #expect(result.maxX <= external.maxX)
        #expect(result.minY >= external.minY)
        #expect(result.maxY <= external.maxY)
    }
}

struct WindowPreviewTitleTests {
    @Test(arguments: ["", "  ", "Clash Verge", " Clash Verge "])
    func emptyOrRepeatedAppNameHasNoCardCaption(title: String) {
        let snapshot = WindowPreviewSnapshot(id: 1, title: title, frame: .zero, image: nil)

        #expect(snapshot.visibleTitle(for: "Clash Verge") == nil)
    }

    @Test
    func distinctWindowTitleRemainsVisible() {
        let snapshot = WindowPreviewSnapshot(id: 1, title: "Settings", frame: .zero, image: nil)

        #expect(snapshot.visibleTitle(for: "Clash Verge") == "Settings")
    }
}

struct WindowPreviewCaptureTests {
    @Test
    func captureRequestsRetinaDetailWithoutDistortingTheWindow() {
        let small = WindowPreviewCapture.configuration(for: CGRect(x: 0, y: 0, width: 160, height: 90))
        #expect(small.width == 320)
        #expect(small.height == 180)
        #expect(small.captureResolution == .best)
        #expect(small.ignoreShadowsSingleWindow)

        let large = WindowPreviewCapture.configuration(for: CGRect(x: 0, y: 0, width: 1600, height: 900))
        #expect(large.width == 840)
        #expect(large.height == 472)
    }

    @Test
    func previewUsesCapturedPixelAspectRatioRatherThanWindowMetadata() throws {
        let context = try #require(CGContext(
            data: nil, width: 400, height: 100, bitsPerComponent: 8, bytesPerRow: 1600,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 100))
        let capturedImage = try #require(context.makeImage())
        let image = try #require(WindowPreviewCapture.image(from: capturedImage))

        #expect(image.size == CGSize(width: 400, height: 100))
    }

    @Test
    func transparentCaptureMarginsAreCroppedWithoutHidingOpaqueBlackContent() throws {
        let context = try #require(CGContext(
            data: nil, width: 100, height: 60, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 20, y: 15, width: 60, height: 30))
        let capture = try #require(context.makeImage())
        let image = try #require(WindowPreviewCapture.image(from: capture))

        #expect(image.size == CGSize(width: 60, height: 30))
    }

    @Test
    func fullyTransparentCaptureHasNoPreviewImage() throws {
        let context = try #require(CGContext(
            data: nil, width: 100, height: 60, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let capture = try #require(context.makeImage())

        #expect(WindowPreviewCapture.image(from: capture) == nil)
    }
}

struct WindowPreviewWindowMatchTests {
    @Test @MainActor
    func minimizedSameTitleWindowsKeepTheirOwnActivationTargets() async throws {
        let first = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 300, height: 200),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
        )
        let second = NSWindow(
            contentRect: CGRect(x: 500, y: 100, width: 300, height: 200),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
        )
        first.isReleasedWhenClosed = false
        second.isReleasedWhenClosed = false
        first.alphaValue = 0
        second.alphaValue = 0
        first.title = "Same title"
        second.title = "Same title"
        defer {
            first.orderOut(nil)
            second.orderOut(nil)
            first.close()
            second.close()
        }
        first.orderFrontRegardless()
        second.orderFrontRegardless()
        let firstID = CGWindowID(first.windowNumber)
        let secondID = CGWindowID(second.windowNumber)
        let processIdentifier = getpid()
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0

        func target(_ id: CGWindowID) -> (title: String, frame: CGRect)? {
            WindowPreviewWindowMatch.currentTarget(
                windowID: id, processIdentifier: processIdentifier, mainScreenTop: screenTop
            )
        }
        for _ in 0..<100 where (target(firstID)?.frame.width ?? 0) == 0
            || (target(secondID)?.frame.width ?? 0) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        let visibleFirst = try #require(target(firstID))
        let visibleSecond = try #require(target(secondID))
        #expect(visibleFirst.title == "Same title")
        #expect(visibleSecond.title == "Same title")
        #expect(visibleFirst.frame != visibleSecond.frame)

        first.miniaturize(nil)
        second.miniaturize(nil)
        for _ in 0..<100 where !first.isMiniaturized || !second.isMiniaturized {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(first.isMiniaturized && second.isMiniaturized)
        #expect(target(firstID)?.frame == visibleFirst.frame)
        #expect(target(secondID)?.frame == visibleSecond.frame)
        let candidates = [(title: Optional("Same title"), frame: Optional(visibleFirst.frame)),
                          (title: Optional("Same title"), frame: Optional(visibleSecond.frame))]
        #expect(WindowPreviewWindowMatch.index(
            title: "Same title", frame: try #require(target(firstID)).frame, candidates: candidates
        ) == 0)
        #expect(WindowPreviewWindowMatch.index(
            title: "Same title", frame: try #require(target(secondID)).frame, candidates: candidates
        ) == 1)
    }

    @Test
    func onlyManageableWindowsBecomePreviewCandidatesAcrossSpaces() {
        let chromeWindow = CGRect(x: 1512, y: 111, width: 1920, height: 969)
        let chromeStrip = CGRect(x: 0, y: 30, width: 1920, height: 81)
        let weChatWindow = CGRect(x: 204, y: 150, width: 1104, height: 650)
        let weChatGhost = CGRect(x: 406, y: 161, width: 700, height: 640)
        let fullScreenChatGPT = CGRect(x: 0, y: 33, width: 1512, height: 949)

        #expect(WindowPreviewWindowMatch.isPreviewCandidate(
            frame: chromeWindow, isOnScreen: true, accessibleWindows: [chromeWindow, chromeStrip]
        ))
        #expect(!WindowPreviewWindowMatch.isPreviewCandidate(
            frame: chromeStrip, isOnScreen: true, accessibleWindows: [chromeWindow, chromeStrip]
        ))
        #expect(WindowPreviewWindowMatch.isPreviewCandidate(
            frame: weChatWindow, isOnScreen: false, accessibleWindows: [weChatWindow]
        ))
        #expect(!WindowPreviewWindowMatch.isPreviewCandidate(
            frame: weChatGhost, isOnScreen: false, accessibleWindows: [weChatWindow]
        ))
        #expect(WindowPreviewWindowMatch.isPreviewCandidate(
            frame: fullScreenChatGPT, isOnScreen: false, accessibleWindows: [fullScreenChatGPT]
        ))
        #expect(WindowPreviewWindowMatch.isPreviewCandidate(
            frame: fullScreenChatGPT.offsetBy(dx: 3, dy: -2),
            isOnScreen: false, accessibleWindows: [fullScreenChatGPT]
        ))
        #expect(!WindowPreviewWindowMatch.isPreviewCandidate(
            frame: fullScreenChatGPT.offsetBy(dx: 30, dy: 0),
            isOnScreen: false, accessibleWindows: [fullScreenChatGPT]
        ))
        #expect(!WindowPreviewWindowMatch.isPreviewCandidate(
            frame: weChatGhost, isOnScreen: false, accessibleWindows: nil
        ))
        #expect(WindowPreviewWindowMatch.isPreviewCandidate(
            frame: fullScreenChatGPT, isOnScreen: true, accessibleWindows: []
        ))
        #expect(!WindowPreviewWindowMatch.isPreviewCandidate(
            frame: chromeStrip, isOnScreen: true, accessibleWindows: []
        ))
    }

    @Test
    func inaccessibleFullscreenWindowInAnotherSpaceRemainsAPreviewCandidate() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let fullScreenWindow = CGRect(x: 0, y: 33, width: 1512, height: 949)
        let phantomWindow = CGRect(x: 406, y: 161, width: 700, height: 640)
        let toolbar = CGRect(x: 0, y: 33, width: 1512, height: 81)

        #expect(WindowPreviewWindowMatch.isPreviewCandidate(
            frame: fullScreenWindow, isOnScreen: false, accessibleWindows: [],
            hasUnmeasuredAccessibleWindow: true, screenFrames: [screen]
        ))
        #expect(WindowPreviewWindowMatch.isPreviewCandidate(
            frame: fullScreenWindow, isOnScreen: false, accessibleWindows: [],
            hasUnmeasuredAccessibleWindow: false, screenFrames: [screen]
        ))
        #expect(WindowPreviewWindowMatch.isPreviewCandidate(
            frame: fullScreenWindow, isOnScreen: false, accessibleWindows: nil,
            screenFrames: [screen]
        ))
        #expect(!WindowPreviewWindowMatch.isPreviewCandidate(
            frame: phantomWindow, isOnScreen: false, accessibleWindows: [],
            hasUnmeasuredAccessibleWindow: true, screenFrames: [screen]
        ))
        #expect(!WindowPreviewWindowMatch.isPreviewCandidate(
            frame: phantomWindow, isOnScreen: false, accessibleWindows: nil,
            screenFrames: [screen]
        ))
        #expect(!WindowPreviewWindowMatch.isPreviewCandidate(
            frame: toolbar, isOnScreen: false, accessibleWindows: [],
            hasUnmeasuredAccessibleWindow: true, screenFrames: [screen]
        ))
    }

    @Test
    func currentWindowMetadataTracksRenamedAndMovedWindows() throws {
        let info: [[String: Any]] = [[
            kCGWindowNumber as String: 42,
            kCGWindowOwnerPID as String: 123,
            kCGWindowName as String: "Renamed document",
            kCGWindowBounds as String: CGRect(x: 500, y: 100, width: 300, height: 200).dictionaryRepresentation,
        ]]
        let target = try #require(WindowPreviewWindowMatch.currentTarget(
            windowID: 42, processIdentifier: 123, windowInfo: info, mainScreenTop: 800
        ))

        #expect(target.title == "Renamed document")
        #expect(target.frame == CGRect(x: 500, y: 500, width: 300, height: 200))
    }

    @Test(arguments: [[:], [kCGWindowNumber as String: 41, kCGWindowOwnerPID as String: 123],
                      [kCGWindowNumber as String: 42, kCGWindowOwnerPID as String: 999]])
    func closedOrReassignedWindowsAreNotActivationTargets(metadata: [String: Int]) {
        var info: [String: Any] = metadata
        info[kCGWindowBounds as String] = CGRect(x: 0, y: 0, width: 300, height: 200).dictionaryRepresentation
        #expect(WindowPreviewWindowMatch.currentTarget(
            windowID: 42, processIdentifier: 123, windowInfo: [info], mainScreenTop: 800
        ) == nil)
    }

    @Test
    func unavailableWindowGeometryDoesNotSelectAnotherWindow() {
        #expect(WindowPreviewWindowMatch.currentTarget(
            windowID: 42, processIdentifier: 123,
            windowInfo: [[kCGWindowNumber as String: 42, kCGWindowOwnerPID as String: 123]],
            mainScreenTop: 800
        ) == nil)
    }

    @Test
    func sameCenterWindowsResolveBySize() {
        let candidates: [(title: String?, frame: CGRect?)] = [
            ("Document", CGRect(x: 100, y: 100, width: 200, height: 100)),
            ("Document", CGRect(x: 0, y: 0, width: 400, height: 300)),
        ]

        #expect(WindowPreviewWindowMatch.index(
            title: "Document",
            frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            candidates: candidates
        ) == 1)
    }

    @Test
    func indistinguishableWindowsDoNotRaiseAnArbitraryWindow() {
        let frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        let candidates: [(title: String?, frame: CGRect?)] = [
            ("Document", frame),
            ("Document", frame),
        ]

        #expect(WindowPreviewWindowMatch.index(title: "Document", frame: frame, candidates: candidates) == nil)
    }

    @Test
    func missingFramesDoNotResolveDuplicateTitles() {
        let candidates: [(title: String?, frame: CGRect?)] = [("Document", nil), ("Document", nil)]

        #expect(WindowPreviewWindowMatch.index(
            title: "Document",
            frame: CGRect(x: 0, y: 0, width: 300, height: 200),
            candidates: candidates
        ) == nil)
    }

    @Test
    func aSingleUnmeasurableFullscreenWindowCanBeActivatedWithoutGuessingAmongOthers() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let fullScreenWindow = CGRect(x: 0, y: 33, width: 1512, height: 949)
        let oneWindow: [(title: String?, frame: CGRect?)] = [("ChatGPT", nil)]

        #expect(WindowPreviewWindowMatch.index(
            title: "ChatGPT", frame: fullScreenWindow, candidates: oneWindow,
            screenFrames: [screen], isOnlyPreview: true
        ) == 0)
        #expect(WindowPreviewWindowMatch.index(
            title: "Other", frame: fullScreenWindow, candidates: oneWindow,
            screenFrames: [screen], isOnlyPreview: true
        ) == 0)
        #expect(WindowPreviewWindowMatch.index(
            title: "Other", frame: fullScreenWindow, candidates: oneWindow,
            screenFrames: [screen], isOnlyPreview: false
        ) == nil)
        #expect(WindowPreviewWindowMatch.index(
            title: "ChatGPT", frame: CGRect(x: 50, y: 50, width: 700, height: 500),
            candidates: oneWindow, screenFrames: [screen], isOnlyPreview: true
        ) == nil)
        #expect(WindowPreviewWindowMatch.index(
            title: "ChatGPT", frame: fullScreenWindow,
            candidates: [("ChatGPT", nil), ("ChatGPT", nil)], screenFrames: [screen], isOnlyPreview: true
        ) == nil)
    }

    @Test
    func fullscreenAppActivationWithoutAXRequiresOneVerifiedPreview() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let fullScreenWindow = CGRect(x: 0, y: 33, width: 1512, height: 949)

        #expect(WindowPreviewWindowMatch.canActivateWithoutAccessibilityWindow(
            frame: fullScreenWindow, isOnlyPreview: true, screenFrames: [screen]
        ))
        #expect(!WindowPreviewWindowMatch.canActivateWithoutAccessibilityWindow(
            frame: fullScreenWindow, isOnlyPreview: false, screenFrames: [screen]
        ))
        #expect(!WindowPreviewWindowMatch.canActivateWithoutAccessibilityWindow(
            frame: CGRect(x: 40, y: 40, width: 700, height: 500),
            isOnlyPreview: true, screenFrames: [screen]
        ))
    }

    @Test
    func sameTitleWindowsResolveByPosition() {
        let candidates: [(title: String?, frame: CGRect?)] = [
            ("Document", CGRect(x: 20, y: 20, width: 300, height: 200)),
            ("Document", CGRect(x: 600, y: 20, width: 300, height: 200)),
        ]

        #expect(WindowPreviewWindowMatch.index(
            title: "Document",
            frame: CGRect(x: 590, y: 20, width: 300, height: 200),
            candidates: candidates
        ) == 1)
    }

    @Test
    func uniqueGeometryMatchesWhenWindowTitlesDiffer() {
        let candidates: [(title: String?, frame: CGRect?)] = [
            ("Other", CGRect(x: 0, y: 0, width: 300, height: 200)),
        ]

        #expect(WindowPreviewWindowMatch.index(
            title: "Document",
            frame: CGRect(x: 0, y: 0, width: 300, height: 200),
            candidates: candidates
        ) == 0)
    }

    @Test
    func mismatchedTitleAndGeometryDoNotRaiseAnotherWindow() {
        let candidates: [(title: String?, frame: CGRect?)] = [
            ("Other", CGRect(x: 400, y: 0, width: 300, height: 200)),
        ]

        #expect(WindowPreviewWindowMatch.index(
            title: "Document",
            frame: CGRect(x: 0, y: 0, width: 300, height: 200),
            candidates: candidates
        ) == nil)
    }

    @Test
    func staleWindowMetadataDoesNotRaiseAnotherMinimizedWindowWithTheSameTitle() {
        let candidates: [(title: String?, frame: CGRect?)] = [
            ("Document", CGRect(x: 500, y: 0, width: 300, height: 200)),
        ]

        #expect(WindowPreviewWindowMatch.index(
            title: "Document",
            frame: CGRect(x: 0, y: 0, width: 300, height: 200),
            candidates: candidates
        ) == nil)
    }

    @Test
    func uniqueGeometryWinsWhenAnotherWindowHasTheSameTitle() {
        let candidates: [(title: String?, frame: CGRect?)] = [
            ("Document", CGRect(x: 400, y: 0, width: 300, height: 200)),
            ("Renamed", CGRect(x: 0, y: 0, width: 300, height: 200)),
        ]

        #expect(WindowPreviewWindowMatch.index(
            title: "Document",
            frame: CGRect(x: 0, y: 0, width: 300, height: 200),
            candidates: candidates
        ) == 1)
    }

    @Test
    func untitledWindowMatchesMissingAccessibilityTitle() {
        let candidates: [(title: String?, frame: CGRect?)] = [
            (nil, CGRect(x: 10, y: 10, width: 300, height: 200)),
        ]

        #expect(WindowPreviewWindowMatch.index(
            title: "",
            frame: CGRect(x: 10, y: 10, width: 300, height: 200),
            candidates: candidates
        ) == 0)
    }
}

@MainActor
struct WindowPreviewPanelTests {
    @Test
    func previewPanelUsesNativeGlassOnSupportedSystems() throws {
        guard #available(macOS 26.0, *) else { return }
        let controller = WindowPreviewController()
        let panel = controller.makePanel()
        defer { panel.close() }
        panel.setFrame(CGRect(x: 100, y: 100, width: 226, height: 168), display: true)
        let content = try #require(panel.contentView)
        content.layoutSubtreeIfNeeded()

        let glass = try #require(nativeGlass(in: content))
        #expect(abs(glass.frame.width - content.bounds.width) < 1)
        #expect(abs(glass.frame.height - content.bounds.height) < 1)
        #expect(glass.style == .clear)
        #expect(glass.cornerRadius == 12)
    }

    @available(macOS 26.0, *)
    private func nativeGlass(in view: NSView) -> NSGlassEffectView? {
        if let glass = view as? NSGlassEffectView { return glass }
        return view.subviews.compactMap(nativeGlass(in:)).first
    }

    @Test
    func reducedTransparencyUsesAnOpaqueBackgroundWithoutNativeGlass() throws {
        let host = NSHostingView(rootView: WindowPreviewView.previewBackground(reduceTransparency: true))
        host.frame = CGRect(x: 0, y: 0, width: 226, height: 168)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        if #available(macOS 26.0, *) {
            #expect(nativeGlass(in: host) == nil)
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let pixel = try #require(bitmap.colorAt(x: 30, y: 30))
        #expect(pixel.alphaComponent > 0.99)
    }

    @Test
    func switcherPanelShrinksWhenItsApplicationHeaderIsHidden() async throws {
        let screen = try #require(NSScreen.screens.first)
        var dependencies = WindowPreviewController.Dependencies()
        dependencies.hasPermissions = { true }
        dependencies.addGlobalMonitor = { _ in NSObject() }
        dependencies.addLocalMonitor = { _ in NSObject() }
        dependencies.removeMonitor = { _ in }
        dependencies.timer = { interval, repeats, _ in
            Timer(timeInterval: interval, repeats: repeats) { _ in }
        }
        dependencies.captureWindows = { _ in [
            WindowPreviewSnapshot(id: 42, title: "App", frame: screen.frame, image: nil),
        ] }
        let controller = WindowPreviewController(dependencies: dependencies)
        let panel = controller.makePanel()
        panel.alphaValue = 0
        defer {
            controller.stop()
            panel.orderOut(nil)
            panel.close()
        }
        let anchor = CGRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY, width: 48, height: 48)
        controller.configure(enabled: true)

        controller.select(WindowPreviewSelection(
            processIdentifier: 42, appName: "App", icon: nil, anchor: anchor, source: .dock
        ))
        await controller.captureTask?.value
        #expect(panel.frame.height == 168)

        controller.select(WindowPreviewSelection(
            processIdentifier: 42, appName: "App", icon: nil, anchor: anchor, source: .switcher
        ))
        await controller.captureTask?.value
        #expect(panel.frame.height == 141)
    }

    @Test
    func anAlreadyVisiblePreviewReassertsItsOrderOnlyAfterChangingSpaces() async throws {
        let screen = try #require(NSScreen.screens.first)
        var dependencies = WindowPreviewController.Dependencies()
        var onSpaceChange: (@MainActor () -> Void)?
        var observerRemoved = false
        var orderFrontCount = 0
        dependencies.hasPermissions = { true }
        dependencies.addGlobalMonitor = { _ in NSObject() }
        dependencies.addLocalMonitor = { _ in NSObject() }
        dependencies.removeMonitor = { _ in }
        dependencies.addSpaceChangeObserver = { action in
            onSpaceChange = action
            return NSObject()
        }
        dependencies.removeWorkspaceObserver = { _ in
            observerRemoved = true
            onSpaceChange = nil
        }
        dependencies.orderPanelFront = { panel in
            orderFrontCount += 1
            panel.orderFrontRegardless()
        }
        dependencies.timer = { interval, repeats, _ in
            Timer(timeInterval: interval, repeats: repeats) { _ in }
        }
        dependencies.captureWindows = { _ in [
            WindowPreviewSnapshot(
                id: 42, title: "Document", frame: CGRect(x: 20, y: 20, width: 300, height: 200), image: nil
            ),
        ] }
        let controller = WindowPreviewController(dependencies: dependencies)
        let panel = controller.makePanel()
        panel.alphaValue = 0
        defer {
            controller.stop()
            panel.orderOut(nil)
            panel.close()
        }

        let anchor = CGRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 8, width: 48, height: 48)
        controller.configure(enabled: true)
        controller.select(WindowPreviewSelection(
            processIdentifier: 42, appName: "App", icon: nil, anchor: anchor, source: .dock
        ))
        await controller.captureTask?.value
        #expect(panel.isVisible)
        #expect(orderFrontCount == 1)

        controller.select(WindowPreviewSelection(
            processIdentifier: 42, appName: "App", icon: nil,
            anchor: anchor.offsetBy(dx: 1, dy: 0), source: .dock
        ))
        #expect(orderFrontCount == 1)

        let notifySpaceChange = try #require(onSpaceChange)
        notifySpaceChange()
        controller.select(WindowPreviewSelection(
            processIdentifier: 42, appName: "App", icon: nil,
            anchor: anchor.offsetBy(dx: 2, dy: 0), source: .dock
        ))
        #expect(orderFrontCount == 2)

        controller.select(WindowPreviewSelection(
            processIdentifier: 42, appName: "App", icon: nil,
            anchor: anchor.offsetBy(dx: 3, dy: 0), source: .dock
        ))
        #expect(orderFrontCount == 2)

        controller.stop()
        #expect(observerRemoved)
        #expect(onSpaceChange == nil)
        #expect(!panel.isVisible)
        #expect(orderFrontCount == 2)
    }

    @Test
    func previewPanelCanAppearAboveOtherAppsFullScreenSpaces() {
        let controller = WindowPreviewController()
        let panel = controller.makePanel()
        defer { panel.close() }

        #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
        #expect(panel.collectionBehavior.contains(.stationary))
    }

    @Test
    func previewPanelCanBecomeKeyWithoutBecomingMain() {
        let panel = WindowPreviewPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }

        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.ignoresMouseEvents)
    }

    @Test
    func previewContentAcceptsTheFirstClick() throws {
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let view = WindowPreviewHostingView(rootView: Button("Preview") {})

        #expect(view.acceptsFirstMouse(for: event))
    }
}
