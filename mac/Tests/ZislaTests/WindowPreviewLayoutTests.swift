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
