import AppKit
import ApplicationServices
import Testing
import ZislaCore
@testable import ZislaKit

extension ContextNoteLocationReaderTests {
    private var desktopScreens: [ScreenSnapshot] {
        [
            ScreenSnapshot(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: .zero),
            ScreenSnapshot(displayID: 2, frame: CGRect(x: -1920, y: -300, width: 1920, height: 1080), visibleFrame: .zero),
            ScreenSnapshot(displayID: 3, frame: CGRect(x: 0, y: 900, width: 1440, height: 900), visibleFrame: .zero),
        ]
    }

    private func windowInfo(frame: CGRect, layer: Int = 0, owner: pid_t = 42, alpha: Double = 1,
                            ownerName: String? = nil, number: Int? = nil) -> [String: Any] {
        var info: [String: Any] = [kCGWindowBounds as String: frame.dictionaryRepresentation,
                                  kCGWindowLayer as String: layer,
                                  kCGWindowOwnerPID as String: owner,
                                  kCGWindowAlpha as String: alpha]
        if let ownerName { info[kCGWindowOwnerName as String] = ownerName }
        if let number { info[kCGWindowNumber as String] = number }
        return info
    }

    @Test
    func windowServerDesktopSurfaceAboveTheIconLayerStillBelongsToItsDisplay() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let layer = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        let point = CGPoint(x: 100, y: 200)
        #expect(ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens,
            windowInfo: [windowInfo(frame: bounds, layer: layer, ownerName: "Window Server")]) == 1)
        for owner in [nil, "Finder", "Other"] as [String?] {
            #expect(ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens,
                windowInfo: [windowInfo(frame: bounds, layer: layer, ownerName: owner)]) == nil)
        }
        #expect(ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens,
            windowInfo: [windowInfo(frame: bounds, layer: layer + 1, ownerName: "Window Server")]) == nil)
    }

    @Test(arguments: [CGPoint(x: 720, y: 888), CGPoint(x: 100, y: 200)])
    func finderCurrentPreservesAnIdentifiableFocusedFolderAtTheMenuBarOrDesktop(point: CGPoint) {
        let folder = ContextNoteLocation.window(bundleIdentifier: "com.apple.finder", applicationName: "Finder", title: "Folder")
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let windows = [windowInfo(frame: CGRect(x: 0, y: 0, width: 1440, height: 24),
                                  layer: Int(CGWindowLevelForKey(.mainMenuWindow)), owner: 10, ownerName: "Window Server"),
                       windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.desktopIconWindow)))]
        let result = ContextNoteLocationReader.observeFinder(isTrusted: true, focusedWindowLocation: { .location(folder) }) { skippingMenuBar in
            guard let display = ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens,
                windowInfo: windows, skippingMenuBar: skippingMenuBar) else { return nil }
            return .desktop(displayID: String(display), displayName: "Screen")
        }
        #expect(result == .location(folder))
    }

    @Test
    func finderDesktopAtTheIslandSkipsOnlyTheSystemMenuBarAndOwnOverlay() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let point = CGPoint(x: 720, y: 888)
        let menuBar = windowInfo(frame: CGRect(x: 0, y: 0, width: 1440, height: 24),
                                 layer: Int(CGWindowLevelForKey(.mainMenuWindow)), owner: 10, ownerName: "Window Server")
        let overlay = windowInfo(frame: CGRect(x: 600, y: 0, width: 240, height: 34),
                                 layer: Int(CGWindowLevelForKey(.statusWindow)), owner: 99)
        let folderElsewhere = windowInfo(frame: CGRect(x: 100, y: 100, width: 400, height: 400))
        let desktop = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.desktopIconWindow)))
        let windows = [overlay, menuBar, folderElsewhere, desktop]
        let result = ContextNoteLocationReader.observeFinder(isTrusted: true, focusedWindowLocation: { nil }) { skippingMenuBar in
            guard let display = ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens,
                windowInfo: windows, excludingProcessIdentifier: 99, skippingMenuBar: skippingMenuBar) else { return nil }
            return .desktop(displayID: String(display), displayName: "Screen")
        }
        #expect(result == .location(.desktop(displayID: "1", displayName: "Screen")))
        #expect(ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens, windowInfo: [menuBar, desktop]) == nil)
        for layer in [0, Int(CGWindowLevelForKey(.mainMenuWindow)), Int(CGWindowLevelForKey(.popUpMenuWindow))] {
            let blocker = windowInfo(frame: bounds, layer: layer, ownerName: "Other")
            #expect(ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens,
                windowInfo: [menuBar, blocker, desktop], skippingMenuBar: true) == nil)
        }
    }

    @Test
    func focusedFinderDesktopUsesWindowMetadataWithoutConfusingMaximizedFolders() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let desktop = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.desktopIconWindow)))
        #expect(ContextNoteLocationReader.focusedWindowIsDesktop(frame: bounds, processIdentifier: 42, windowInfo: [desktop]))
        #expect(!ContextNoteLocationReader.focusedWindowIsDesktop(frame: bounds, processIdentifier: 42,
            windowInfo: [windowInfo(frame: bounds), desktop]))
        #expect(!ContextNoteLocationReader.focusedWindowIsDesktop(frame: bounds, processIdentifier: 43, windowInfo: [desktop]))
        #expect(!ContextNoteLocationReader.focusedWindowIsDesktop(frame: bounds.offsetBy(dx: 1, dy: 1), processIdentifier: 42, windowInfo: [desktop]))
        #expect(!ContextNoteLocationReader.focusedWindowIsDesktop(frame: nil, processIdentifier: 42, windowInfo: [desktop]))
        #expect(!ContextNoteLocationReader.focusedWindowIsDesktop(frame: bounds, processIdentifier: 42, windowInfo: nil))
    }

    @Test
    func untrustedFinderDoesNotInspectFocusedWindowsOrSkipMenuBarProtection() {
        let result = ContextNoteLocationReader.observeFinder(isTrusted: false, focusedWindowLocation: {
            Issue.record("Untrusted Finder observation must not inspect accessibility windows")
            return .unavailable
        }) { skippingMenuBar in
            #expect(!skippingMenuBar)
            return .desktop(displayID: "screen-1", displayName: "Screen")
        }
        #expect(result == .location(.desktop(displayID: "screen-1", displayName: "Screen")))
    }

    @Test
    func desktopCaptureKeepsIndependentDisplayIdentitiesAcrossScreenArrangements() {
        let windows = [
            windowInfo(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), layer: Int(CGWindowLevelForKey(.desktopWindow))),
            windowInfo(frame: CGRect(x: -1920, y: 120, width: 1920, height: 1080), layer: Int(CGWindowLevelForKey(.desktopIconWindow))),
            windowInfo(frame: CGRect(x: 0, y: -900, width: 1440, height: 900), layer: Int(CGWindowLevelForKey(.desktopWindow))),
        ]
        for (point, display) in [(CGPoint(x: 100, y: 200), 1), (CGPoint(x: -960, y: 650), 2), (CGPoint(x: 500, y: 1200), 3)] {
            #expect(ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens, windowInfo: windows) == CGDirectDisplayID(display))
        }
        #expect(ContextNoteLocationReader.desktopDisplay(at: CGPoint(x: -1921, y: 650), screens: desktopScreens, windowInfo: windows) == nil)
        #expect(ContextNoteLocationReader.desktopDisplay(at: .zero, screens: [], windowInfo: windows) == nil)
    }

    @Test(arguments: [0, Int(CGWindowLevelForKey(.floatingWindow)), Int(CGWindowLevelForKey(.popUpMenuWindow))])
    func aVisibleApplicationOrMenuCannotBeCapturedAsDesktop(layer: Int) {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let windows = [windowInfo(frame: bounds, layer: layer),
                       windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.desktopIconWindow)))]
        #expect(ContextNoteLocationReader.desktopDisplay(at: CGPoint(x: 100, y: 200), screens: desktopScreens, windowInfo: windows) == nil)
    }

    @Test
    func currentDesktopIgnoresOnlyItsOwnOverlayWhileCaptureStillHitsIt() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let overlay = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.statusWindow)), owner: 99)
        let desktop = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.desktopIconWindow)))
        let point = CGPoint(x: 100, y: 200)
        #expect(ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens, windowInfo: [overlay, desktop],
                                                        excludingProcessIdentifier: 99) == 1)
        #expect(ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens, windowInfo: [overlay, desktop]) == nil)
        for layer in [0, Int(CGWindowLevelForKey(.popUpMenuWindow))] {
            let other = windowInfo(frame: bounds, layer: layer)
            #expect(ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens, windowInfo: [overlay, other, desktop],
                                                            excludingProcessIdentifier: 99) == nil)
        }
    }

    @Test
    func transparentAndDistantWindowsDoNotHideTheDesktopUnderThePointer() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let windows = [windowInfo(frame: bounds, alpha: 0),
                       windowInfo(frame: CGRect(x: 0, y: 0, width: 20, height: 20)),
                       windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.desktopIconWindow)))]
        #expect(ContextNoteLocationReader.desktopDisplay(at: CGPoint(x: 100, y: 200), screens: desktopScreens, windowInfo: windows) == 1)
    }

    @Test
    func missingOrMalformedWindowMetadataDoesNotGuessThatTheDesktopIsVisible() {
        let desktop = windowInfo(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), layer: Int(CGWindowLevelForKey(.desktopWindow)))
        for key in [kCGWindowBounds, kCGWindowAlpha, kCGWindowLayer, kCGWindowOwnerPID] {
            var invalid = desktop
            invalid.removeValue(forKey: key as String)
            #expect(ContextNoteLocationReader.desktopDisplay(at: CGPoint(x: 100, y: 200), screens: desktopScreens, windowInfo: [invalid, desktop]) == nil)
            invalid[key as String] = "invalid"
            #expect(ContextNoteLocationReader.desktopDisplay(at: CGPoint(x: 100, y: 200), screens: desktopScreens, windowInfo: [invalid, desktop]) == nil)
        }
        var invalidBounds = desktop
        invalidBounds[kCGWindowBounds as String] = [:] as [String: Double]
        #expect(ContextNoteLocationReader.desktopDisplay(at: CGPoint(x: 100, y: 200), screens: desktopScreens, windowInfo: [invalidBounds, desktop]) == nil)
        for windows in [nil, []] as [[[String: Any]]?] {
            #expect(ContextNoteLocationReader.desktopDisplay(at: CGPoint(x: 100, y: 200), screens: desktopScreens, windowInfo: windows) == nil)
        }
    }

    @Test
    func missingWindowAttributeRequiresTheSameProcessAndExactVisibleWindowFrame() {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let main = ContextNoteLocationReader.WindowSnapshot(frame: bounds, layer: 0, ownerProcessIdentifier: 42)
        #expect(main.matches(bounds, processIdentifier: 42))
        #expect(!main.matches(bounds, processIdentifier: 43))
        #expect(!main.matches(bounds.insetBy(dx: 1, dy: 1), processIdentifier: 42))
        #expect(!main.matches(nil, processIdentifier: 42))
        let menu = ContextNoteLocationReader.WindowSnapshot(frame: bounds, layer: Int(CGWindowLevelForKey(.popUpMenuWindow)), ownerProcessIdentifier: 42)
        #expect(!menu.matches(bounds, processIdentifier: 42))
    }

    @Test
    func directWindowKeepsPrecedenceAndFailedOrAmbiguousCandidatesAreRejected() {
        #expect(ContextNoteLocationReader.findWindow(direct: 7, candidates: {
            Issue.record("An identified window must not enumerate unrelated candidates")
            return [1]
        }, matches: { _ in false }) == 7)
        for windows in [nil, [], [1, 2]] as [[Int]?] {
            #expect(ContextNoteLocationReader.findWindow(direct: nil, candidates: { windows }, matches: { _ in true }) == nil)
        }
        #expect(ContextNoteLocationReader.findWindow(direct: nil, candidates: { [1] }, matches: { _ in false }) == nil)
    }

    @Test
    func missingWindowAttributeUsesTheUniqueMatchingApplicationWindow() {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let surface = ContextNoteLocationReader.topWindow(at: CGPoint(x: 500, y: 400), windowInfo: [windowInfo(frame: bounds)])
        let windows = [(title: "Other", frame: bounds.offsetBy(dx: 1000, dy: 0)), (title: "Conversation", frame: bounds)]
        let window = ContextNoteLocationReader.findWindow(direct: nil, candidates: { windows }) {
            surface?.matches($0.frame, processIdentifier: 42) == true
        }
        let result = window.map {
            ContextNoteLocationReader.resolve(bundleIdentifier: "test.chat", applicationName: "Chat", windowTitle: $0.title,
                                              isBrowser: false, pageAddress: nil)
        } ?? .unavailable
        #expect(result == .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation")))
    }

    private struct CaptureWindow {
        let title: String
        let frame: CGRect?
    }

    private func captureWindow(surface: ContextNoteLocationReader.WindowSnapshot?,
                               hit: (processIdentifier: pid_t, window: CaptureWindow?)?,
                               windows: [CaptureWindow]?, focused: CaptureWindow? = nil,
                               main: CaptureWindow? = nil, bundleIdentifier: String = "test.chat",
                               applicationName: String = "Chat",
                               desktopLocation: (ContextNoteLocationReader.WindowSnapshot) -> ContextNoteLocation? = { _ in nil }) -> ContextNoteObservation {
        var fixtures: [(element: AXUIElement, window: CaptureWindow)] = []
        func element(for window: CaptureWindow) -> AXUIElement {
            let element = AXUIElementCreateApplication(pid_t(1000 + fixtures.count))
            fixtures.append((element, window))
            return element
        }
        let listed = windows?.map { element(for: $0) }
        let focusedElement = focused.map { element(for: $0) }
        let mainElement = main.map { element(for: $0) }
        let hitElement = hit.map { (processIdentifier: $0.processIdentifier, window: $0.window.map { element(for: $0) }) }
        return ContextNoteLocationReader.captureWindow(surface: surface, hit: hitElement, readAttribute: { pid, name in
            guard pid == 42 else { return nil }
            switch name {
            case kAXWindowsAttribute: return listed as CFArray?
            case kAXFocusedWindowAttribute: return focusedElement
            case kAXMainWindowAttribute: return mainElement
            default: return nil
            }
        }, frame: { element in
            fixtures.first { CFEqual($0.element, element) }?.window.frame
        }, desktopLocation: desktopLocation) { _, element in
            guard let element, let window = fixtures.first(where: { CFEqual($0.element, element) })?.window else { return .unavailable }
            return ContextNoteLocationReader.resolve(bundleIdentifier: bundleIdentifier, applicationName: applicationName,
                windowTitle: window.title, isBrowser: false, pageAddress: nil)
        }
    }

    private func passThroughWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 100, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        return window
    }

    @Test(arguments: ["com.tencent.xinWeChat", "test.editor"], [0, 1])
    func repeatedCapturesThroughOwnPassThroughWindowsKeepTheSameApplication(bundleIdentifier: String, screenIndex: Int) throws {
        let overlays = [passThroughWindow(), passThroughWindow()]
        defer { overlays.forEach { $0.close() } }
        for overlay in overlays {
            try #require(!overlay.isVisible && overlay.windowNumber > 0)
            try #require(NSApp.window(withWindowNumber: overlay.windowNumber) === overlay)
        }
        let screen = dockScreenFrames[screenIndex]
        let quartzFrame = CGRect(x: screen.minX, y: dockScreenFrames[0].maxY - screen.maxY,
                                 width: screen.width, height: screen.height)
        let bounds = CGRect(x: quartzFrame.minX + 204, y: quartzFrame.minY + 150, width: 1104, height: 650)
        let overlayBounds = CGRect(x: quartzFrame.minX + 346, y: quartzFrame.minY, width: 820, height: 504)
        let point = CGPoint(x: quartzFrame.minX + 700, y: quartzFrame.minY + 400)
        let owner = ProcessInfo.processInfo.processIdentifier
        let high = windowInfo(frame: overlayBounds, layer: Int(CGWindowLevelForKey(.statusWindow)),
                              owner: owner, number: overlays[0].windowNumber)
        let low = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.floatingWindow)),
                             owner: owner, number: overlays[1].windowNumber)
        let dock = windowInfo(frame: quartzFrame, layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84)
        let application = windowInfo(frame: bounds)
        let expected = ContextNoteObservation.location(.window(bundleIdentifier: bundleIdentifier,
            applicationName: "Application", title: "Document"))
        for windows in [[application], [application], [high, low, application],
                        [high, dock, low, application], [high, low, application]] {
            let surface = ContextNoteLocationReader.captureSurface(at: point, windowInfo: windows,
                screenFrames: dockScreenFrames, hitProcessIdentifier: 42,
                bundleIdentifier: { $0 == 84 ? "com.apple.dock" : bundleIdentifier })
            #expect(captureWindow(surface: surface, hit: (42, nil), windows: [CaptureWindow(title: "Document", frame: bounds)],
                bundleIdentifier: bundleIdentifier, applicationName: "Application") == expected)
        }
    }

    @Test(arguments: [0, 1, 2], [false, true])
    func repeatedCapturesThroughOwnPassThroughWindowsKeepTheSameDesktop(screenIndex: Int, windowServer: Bool) {
        let overlays = [passThroughWindow(), passThroughWindow()]
        defer { overlays.forEach { $0.close() } }
        let screen = desktopScreens[screenIndex]
        let bounds = CGRect(x: screen.frame.minX, y: desktopScreens[0].frame.maxY - screen.frame.maxY,
                            width: screen.frame.width, height: screen.frame.height)
        let point = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        let quartzPoint = CGPoint(x: bounds.midX, y: bounds.midY)
        let owner = ProcessInfo.processInfo.processIdentifier
        let high = windowInfo(frame: bounds.insetBy(dx: 10, dy: 10), layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
                              owner: owner, number: overlays[0].windowNumber)
        let low = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.floatingWindow)),
                             owner: owner, number: overlays[1].windowNumber)
        let dock = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84)
        let desktop = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.desktopIconWindow)) + (windowServer ? 1 : 0),
                                 owner: windowServer ? 7 : 42, ownerName: windowServer ? "Window Server" : "Finder")
        let captures = [(windows: [desktop], isTrusted: false),
                        (windows: [high, low, desktop], isTrusted: false),
                        (windows: [high, dock, low, desktop], isTrusted: true),
                        (windows: [high, low, desktop], isTrusted: false)]
        for capture in captures {
            let desktopLocation: (ContextNoteLocationReader.WindowSnapshot?) -> ContextNoteLocation? = { surface in
                guard let display = ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens,
                    windowInfo: capture.windows, capturedSurface: surface) else { return nil }
                return .desktop(displayID: String(display), displayName: "Screen")
            }
            let result = ContextNoteLocationReader.observe(isTrusted: capture.isTrusted, desktopLocation: { desktopLocation(nil) }) {
                #expect(capture.isTrusted, "A visible desktop must not need accessibility after excluding pass-through windows")
                let surface = ContextNoteLocationReader.captureSurface(at: quartzPoint, windowInfo: capture.windows,
                    screenFrames: desktopScreens.map(\.frame), hitProcessIdentifier: 42,
                    bundleIdentifier: { $0 == 84 ? "com.apple.dock" : "com.apple.finder" })
                return captureWindow(surface: surface, hit: (42, nil), windows: nil, desktopLocation: { desktopLocation($0) })
            }
            #expect(result == .location(.desktop(displayID: String(screen.displayID), displayName: "Screen")))
        }
    }

    @Test(arguments: [false, true])
    func ownWindowInputPolicyChangesAffectEachCapture(isDesktop: Bool) {
        let overlay = passThroughWindow()
        defer { overlay.close() }
        let bounds = desktopScreens[0].frame
        let point = CGPoint(x: 700, y: 400)
        let own = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.statusWindow)),
                             owner: ProcessInfo.processInfo.processIdentifier, number: overlay.windowNumber)
        let underlying = windowInfo(frame: bounds, layer: isDesktop ? Int(CGWindowLevelForKey(.desktopIconWindow)) : 0)
        let windows = [own, underlying]
        let location: ContextNoteLocation = isDesktop ? .desktop(displayID: "1", displayName: "Screen")
            : .window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Document")
        for passesInput in [true, true, false, true, false, true] {
            overlay.ignoresMouseEvents = passesInput
            let surface = ContextNoteLocationReader.captureSurface(at: point, windowInfo: windows,
                screenFrames: desktopScreens.map(\.frame), hitProcessIdentifier: 42,
                bundleIdentifier: { _ in isDesktop ? "com.apple.finder" : "test.chat" })
            let result = captureWindow(surface: surface, hit: (42, nil), windows: [CaptureWindow(title: "Document", frame: bounds)],
                desktopLocation: { _ in location })
            #expect(result == (passesInput ? .location(location) : .ignored))
            #expect(ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens, windowInfo: windows)
                    == (isDesktop && passesInput ? 1 : nil))
        }
    }

    @Test
    func ownPassThroughFilteringKeepsUnknownAndInteractiveWindows() {
        let passThrough = passThroughWindow()
        let interactive = passThroughWindow()
        interactive.ignoresMouseEvents = false
        defer { passThrough.close(); interactive.close() }
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let owner = ProcessInfo.processInfo.processIdentifier
        let high = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
                              owner: owner, number: passThrough.windowNumber)
        for number in [nil, "invalid", 0, Int.max, interactive.windowNumber] as [Any?] {
            var blocker = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.statusWindow)), owner: owner)
            blocker[kCGWindowNumber as String] = number
            let surface = ContextNoteLocationReader.captureSurface(at: CGPoint(x: 500, y: 400),
                windowInfo: [high, blocker, windowInfo(frame: bounds)], screenFrames: dockScreenFrames,
                hitProcessIdentifier: 42, bundleIdentifier: { _ in "test.chat" })
            #expect(captureWindow(surface: surface, hit: (42, nil), windows: [CaptureWindow(title: "Document", frame: bounds)]) == .ignored)
        }
    }

    @Test
    func foreignWindowsCannotBorrowAnOwnPassThroughWindowNumber() {
        let overlay = passThroughWindow()
        defer { overlay.close() }
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let foreign = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.floatingWindow)),
                                 owner: 43, number: overlay.windowNumber)
        let surface = ContextNoteLocationReader.captureSurface(at: CGPoint(x: 500, y: 400),
            windowInfo: [foreign, windowInfo(frame: bounds)], screenFrames: dockScreenFrames,
            hitProcessIdentifier: 42, bundleIdentifier: { _ in "test.chat" })
        #expect(surface?.ownerProcessIdentifier == 43)
        #expect(captureWindow(surface: surface, hit: (42, nil), windows: [CaptureWindow(title: "Document", frame: bounds)]) == .unavailable)
    }

    @Test(arguments: [nil, 43] as [pid_t?])
    func unavailableOrForeignAccessibilityHitUsesTheVisibleWindowOwner(hitProcessIdentifier: pid_t?) {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let surface = ContextNoteLocationReader.WindowSnapshot(frame: bounds, layer: 0, ownerProcessIdentifier: 42)
        let hit = hitProcessIdentifier.map { (processIdentifier: $0, window: Optional(CaptureWindow(title: "Foreign", frame: bounds))) }
        let windows = [CaptureWindow(title: "Other", frame: bounds.offsetBy(dx: 1000, dy: 0)),
                       CaptureWindow(title: "Conversation", frame: bounds)]
        #expect(captureWindow(surface: surface, hit: hit, windows: windows)
                == .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation")))
    }

    @Test
    func visibleWindowFallbackRejectsMissingAmbiguousAndDifferentFrames() {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let surface = ContextNoteLocationReader.WindowSnapshot(frame: bounds, layer: 0, ownerProcessIdentifier: 42)
        let window = CaptureWindow(title: "Conversation", frame: bounds)
        for windows in [nil, [], [window, window], [CaptureWindow(title: "Other", frame: bounds.offsetBy(dx: 1, dy: 0))],
                        [CaptureWindow(title: "Unknown", frame: nil)]] as [[CaptureWindow]?] {
            #expect(captureWindow(surface: surface, hit: nil, windows: windows) == .unavailable)
        }
        #expect(captureWindow(surface: surface, hit: nil, windows: [window])
                == .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation")))
    }

    @Test(arguments: [Int(CGWindowLevelForKey(.floatingWindow)), Int(CGWindowLevelForKey(.popUpMenuWindow))])
    func inaccessibleFloatingSurfacesCannotCaptureAWindowBehindThem(layer: Int) {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let surface = ContextNoteLocationReader.WindowSnapshot(frame: bounds, layer: layer, ownerProcessIdentifier: 42)
        let window = CaptureWindow(title: "Conversation", frame: bounds)
        #expect(captureWindow(surface: surface, hit: nil, windows: [window]) == .unavailable)
        #expect(captureWindow(surface: surface, hit: (43, window), windows: [window]) == .unavailable)
    }

    @Test
    func capturePreservesDirectAccessibilityWindowsWhenWindowServerMetadataIsUnavailable() {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let window = CaptureWindow(title: "Conversation", frame: bounds)
        for metadata in [nil, []] as [[[String: Any]]?] {
            let surface = ContextNoteLocationReader.captureSurface(at: CGPoint(x: 500, y: 400),
                windowInfo: metadata, screenFrames: dockScreenFrames, hitProcessIdentifier: 42,
                bundleIdentifier: { _ in "test.chat" })
            #expect(surface == nil)
            #expect(captureWindow(surface: surface, hit: (42, window), windows: nil)
                    == .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation")))
        }
        #expect(captureWindow(surface: nil, hit: nil, windows: [window]) == .unavailable)
    }

    @Test
    func ownVisibleWindowIsIgnoredEvenWhenAccessibilityHitsAnotherApplication() {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let surface = ContextNoteLocationReader.WindowSnapshot(frame: bounds, layer: 0,
            ownerProcessIdentifier: ProcessInfo.processInfo.processIdentifier)
        let result = ContextNoteLocationReader.captureWindow(surface: surface, hit: (42, AXUIElementCreateApplication(1000)), readAttribute: { _, _ in
            Issue.record("An own visible surface must not inspect application windows")
            return nil
        }, frame: { _ in bounds }, desktopLocation: { _ in nil }) { _, _ in
            Issue.record("An own visible surface must not read a note location")
            return .unavailable
        }
        #expect(result == .ignored)
    }

    @Test(arguments: [kAXFocusedWindowAttribute, kAXMainWindowAttribute])
    func omittedApplicationWindowCanBeRecoveredOnlyAtItsVisibleSurface(attribute: String) {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let surface = ContextNoteLocationReader.WindowSnapshot(frame: bounds, layer: 0, ownerProcessIdentifier: 42)
        let window = CaptureWindow(title: "Conversation", frame: bounds)
        for listed in [nil, []] as [[CaptureWindow]?] {
            #expect(captureWindow(surface: surface, hit: nil, windows: listed,
                focused: attribute == kAXFocusedWindowAttribute ? window : nil,
                main: attribute == kAXMainWindowAttribute ? window : nil)
                == .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation")))
        }
    }

    @Test(arguments: ["", " \n"])
    func unreadableDirectWindowDoesNotPreventAnExactCanonicalWindowMatch(title: String) {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let surface = ContextNoteLocationReader.WindowSnapshot(frame: bounds, layer: 0, ownerProcessIdentifier: 42)
        let direct = CaptureWindow(title: title, frame: bounds)
        let canonical = CaptureWindow(title: "Conversation", frame: bounds)
        #expect(captureWindow(surface: surface, hit: (42, direct), windows: [canonical])
                == .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation")))
        #expect(captureWindow(surface: surface, hit: (42, direct), windows: nil, focused: canonical)
                == .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation")))
    }

    @Test
    func directWindowFromTheSameProcessMustMatchTheVisibleSurface() {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let surface = ContextNoteLocationReader.WindowSnapshot(frame: bounds, layer: 0, ownerProcessIdentifier: 42)
        let canonical = CaptureWindow(title: "Conversation", frame: bounds)
        let direct = CaptureWindow(title: "Other", frame: bounds.offsetBy(dx: 1000, dy: 0))
        #expect(captureWindow(surface: surface, hit: (42, direct), windows: [canonical])
                == .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation")))
    }

    @Test
    func unreadableDirectWindowCannotFallBackToAnUnrelatedOrAmbiguousFocusedWindow() {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let surface = ContextNoteLocationReader.WindowSnapshot(frame: bounds, layer: 0, ownerProcessIdentifier: 42)
        let direct = CaptureWindow(title: "", frame: bounds)
        let canonical = CaptureWindow(title: "Conversation", frame: bounds)
        for candidate in [CaptureWindow(title: "Other", frame: bounds.offsetBy(dx: 1, dy: 0)),
                          CaptureWindow(title: "Unknown", frame: nil)] {
            #expect(captureWindow(surface: surface, hit: (42, direct), windows: [], focused: candidate) == .unavailable)
        }
        #expect(captureWindow(surface: surface, hit: (42, direct), windows: [], focused: canonical, main: canonical) == .unavailable)
        #expect(captureWindow(surface: nil, hit: (42, direct), windows: nil, focused: canonical) == .unavailable)
        let floating = ContextNoteLocationReader.WindowSnapshot(frame: bounds, layer: Int(CGWindowLevelForKey(.floatingWindow)),
            ownerProcessIdentifier: 42)
        #expect(captureWindow(surface: floating, hit: nil, windows: [], focused: canonical) == .unavailable)
    }

    @Test
    func duplicatedReferencesToTheSameAccessibilityWindowRemainUnambiguous() {
        let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)
        let surface = ContextNoteLocationReader.WindowSnapshot(frame: bounds, layer: 0, ownerProcessIdentifier: 42)
        let window = AXUIElementCreateApplication(1000)
        let result = ContextNoteLocationReader.captureWindow(surface: surface, hit: nil, readAttribute: { _, name in
            if name == kAXWindowsAttribute { return [window] as CFArray }
            return window
        }, frame: { _ in bounds }, desktopLocation: { _ in nil }) { _, element in
            guard let element, CFEqual(element, window) else { return .unavailable }
            return .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation"))
        }
        #expect(result == .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation")))
    }

    private var dockScreenFrames: [CGRect] {
        [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: -98, width: 1920, height: 1080)]
    }

    private func surfaceUnderDock(_ windows: [[String: Any]], hitProcessIdentifier: pid_t?,
                                  dockBundle: String? = "com.apple.dock", screenFrames: [CGRect]? = nil) -> ContextNoteLocationReader.WindowSnapshot? {
        ContextNoteLocationReader.captureSurface(at: CGPoint(x: 625.67578125, y: 523.05078125), windowInfo: windows,
            screenFrames: screenFrames ?? dockScreenFrames, hitProcessIdentifier: hitProcessIdentifier,
            bundleIdentifier: { $0 == 84 ? dockBundle : "test.chat" })
    }

    @Test
    func fullScreenDockSurfaceDoesNotHideTheApplicationActuallyHitByAccessibility() {
        let bounds = CGRect(x: 204, y: 150, width: 1104, height: 650)
        let dock = windowInfo(frame: dockScreenFrames[0], layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84, ownerName: "程序坞")
        let surface = surfaceUnderDock([dock, windowInfo(frame: bounds)], hitProcessIdentifier: 42)
        let result = captureWindow(surface: surface, hit: (42, nil), windows: [CaptureWindow(title: "Conversation", frame: bounds)])
        #expect(result == .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation")))
    }

    @Test(arguments: [0, 1, 2], [false, true])
    func fullScreenDockSurfaceDoesNotHideTheDesktopActuallyHitByAccessibility(screenIndex: Int, windowServer: Bool) {
        let screen = desktopScreens[screenIndex]
        let bounds = CGRect(x: screen.frame.minX, y: desktopScreens[0].frame.maxY - screen.frame.maxY,
                            width: screen.frame.width, height: screen.frame.height)
        let point = CGPoint(x: bounds.midX, y: bounds.midY)
        let dock = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84)
        let desktopOwner: pid_t = windowServer ? 7 : 42
        let desktop = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.desktopIconWindow)) + (windowServer ? 1 : 0),
                                 owner: desktopOwner, ownerName: windowServer ? "Window Server" : "Finder")
        let windows = [dock, desktop]
        let surface = ContextNoteLocationReader.captureSurface(at: point, windowInfo: windows,
            screenFrames: desktopScreens.map(\.frame), hitProcessIdentifier: 42,
            bundleIdentifier: { $0 == 84 ? "com.apple.dock" : "com.apple.finder" })
        #expect(surface?.isDesktop == true)
        #expect(surface?.ownerProcessIdentifier == desktopOwner)
        #expect(surface?.frame == bounds)
        let result = ContextNoteLocationReader.captureWindow(surface: surface, hit: (42, nil), readAttribute: { _, _ in
            Issue.record("A verified desktop must not enumerate accessibility windows")
            return nil
        }, frame: { _ in
            Issue.record("A verified desktop must not inspect accessibility window frames")
            return nil
        }, desktopLocation: { surface in
            let appKitPoint = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            guard let display = ContextNoteLocationReader.desktopDisplay(at: appKitPoint, screens: desktopScreens,
                windowInfo: windows, capturedSurface: surface) else { return nil }
            return .desktop(displayID: String(display), displayName: "Screen")
        }) { _, _ in
            Issue.record("A verified desktop must not use an application's window title")
            return .unavailable
        }
        #expect(result == .location(.desktop(displayID: String(screen.displayID), displayName: "Screen")))
    }

    @Test
    func dockDesktopBypassStillRequiresAnIdentifiableDesktopOwnerAndAccessibilityHit() {
        let bounds = dockScreenFrames[0]
        let dock = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84)
        let desktop = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.desktopIconWindow)), owner: 7)
        for ownerName in [nil, "Finder", "Other"] as [String?] {
            var unmatched = desktop
            if let ownerName { unmatched[kCGWindowOwnerName as String] = ownerName }
            let surface = ContextNoteLocationReader.captureSurface(at: CGPoint(x: 500, y: 400),
                windowInfo: [dock, unmatched], screenFrames: dockScreenFrames, hitProcessIdentifier: 42,
                bundleIdentifier: { $0 == 84 ? "com.apple.dock" : "com.apple.finder" })
            #expect(surface?.ownerProcessIdentifier == 84)
        }
        let windowServer = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1,
                                      owner: 7, ownerName: "Window Server")
        for hit in [nil, 84, 42] as [pid_t?] {
            for hitBundle in [nil, "test.chat"] as [String?] {
                let surface = ContextNoteLocationReader.captureSurface(at: CGPoint(x: 500, y: 400),
                    windowInfo: [dock, windowServer], screenFrames: dockScreenFrames, hitProcessIdentifier: hit,
                    bundleIdentifier: { $0 == 84 ? "com.apple.dock" : hitBundle })
                #expect(surface?.ownerProcessIdentifier == 84)
            }
        }
        for layer in [0, Int(CGWindowLevelForKey(.floatingWindow))] {
            let blocker = windowInfo(frame: bounds, layer: layer, owner: 7, ownerName: "Window Server")
            let surface = ContextNoteLocationReader.captureSurface(at: CGPoint(x: 500, y: 400),
                windowInfo: [dock, blocker, windowServer], screenFrames: dockScreenFrames, hitProcessIdentifier: 42,
                bundleIdentifier: { $0 == 84 ? "com.apple.dock" : "com.apple.finder" })
            #expect(surface?.ownerProcessIdentifier == 84)
        }
    }

    @Test
    func unavailableDesktopIdentityCannotBecomeAFinderWindowNote() {
        let surface = ContextNoteLocationReader.WindowSnapshot(frame: dockScreenFrames[0],
            layer: Int(CGWindowLevelForKey(.desktopIconWindow)), ownerProcessIdentifier: 42)
        let result = ContextNoteLocationReader.captureWindow(surface: surface, hit: (42, nil), readAttribute: { _, _ in
            Issue.record("An unavailable display identity must not enumerate accessibility windows")
            return nil
        }, frame: { _ in nil }, desktopLocation: { _ in nil }) { _, _ in
            Issue.record("An unavailable display identity must not fall back to a Finder window title")
            return .location(.window(bundleIdentifier: "com.apple.finder", applicationName: "Finder", title: "Desktop"))
        }
        #expect(result == .unavailable)
    }

    @Test(arguments: [0, 1, 2])
    func finderCurrentRecoversTheSameDockCoveredDesktopWhileSkippingItsOwnIslandAndMenuBar(screenIndex: Int) {
        let screen = desktopScreens[screenIndex]
        let bounds = CGRect(x: screen.frame.minX, y: desktopScreens[0].frame.maxY - screen.frame.maxY,
                            width: screen.frame.width, height: screen.frame.height)
        let point = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - 12)
        let overlay = windowInfo(frame: CGRect(x: bounds.midX - 120, y: bounds.minY, width: 240, height: 34),
                                 layer: Int(CGWindowLevelForKey(.statusWindow)), owner: 99)
        let menu = windowInfo(frame: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 24),
                              layer: Int(CGWindowLevelForKey(.mainMenuWindow)), owner: 7, ownerName: "Window Server")
        let dock = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84)
        let desktop = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1,
                                 owner: 7, ownerName: "Window Server")
        let windows = [overlay, menu, dock, desktop]
        var hits = 0
        let result = ContextNoteLocationReader.observeFinder(isTrusted: true, focusedWindowLocation: { nil }) { skippingMenuBar in
            guard let display = ContextNoteLocationReader.desktopDisplay(at: point, screens: desktopScreens, windowInfo: windows,
                hitProcessIdentifier: { hits += 1; return 42 },
                bundleIdentifier: { $0 == 84 ? "com.apple.dock" : "com.apple.finder" },
                excludingProcessIdentifier: 99, skippingMenuBar: skippingMenuBar) else { return nil }
            return .desktop(displayID: String(display), displayName: "Screen")
        }
        #expect(result == .location(.desktop(displayID: String(screen.displayID), displayName: "Screen")))
        #expect(hits == 1)
        let captureSurface = ContextNoteLocationReader.captureSurface(at: CGPoint(x: bounds.midX, y: bounds.minY + 12),
            windowInfo: windows, screenFrames: desktopScreens.map(\.frame), hitProcessIdentifier: 42,
            bundleIdentifier: { $0 == 84 ? "com.apple.dock" : "com.apple.finder" })
        #expect(captureSurface?.ownerProcessIdentifier == 99)
    }

    @Test(arguments: [false, true])
    func finderCurrentDockFallbackRejectsUnavailableHitsAndInterveningApplicationWindows(isTrusted: Bool) {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let dock = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84)
        let desktop = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1,
                                 owner: 7, ownerName: "Window Server")
        for hit in [nil, 84, 43] as [pid_t?] {
            var hits = 0
            let result = ContextNoteLocationReader.observeFinder(isTrusted: isTrusted, focusedWindowLocation: {
                #expect(isTrusted)
                return .unavailable
            }) { skippingMenuBar in
                guard let display = ContextNoteLocationReader.desktopDisplay(at: CGPoint(x: 500, y: 400),
                    screens: desktopScreens, windowInfo: [dock, desktop],
                    hitProcessIdentifier: skippingMenuBar ? { hits += 1; return hit } : nil,
                    bundleIdentifier: { $0 == 84 ? "com.apple.dock" : "test.chat" },
                    skippingMenuBar: skippingMenuBar) else { return nil }
                return .desktop(displayID: String(display), displayName: "Screen")
            }
            #expect(result == .unavailable)
            #expect(hits == (isTrusted ? 1 : 0))
        }
        for layer in [0, Int(CGWindowLevelForKey(.floatingWindow)), Int(CGWindowLevelForKey(.popUpMenuWindow))] {
            let blocker = windowInfo(frame: bounds, layer: layer)
            #expect(ContextNoteLocationReader.desktopDisplay(at: CGPoint(x: 500, y: 400), screens: desktopScreens,
                windowInfo: [dock, blocker, desktop], hitProcessIdentifier: { 42 },
                bundleIdentifier: { $0 == 84 ? "com.apple.dock" : "com.apple.finder" }) == nil)
        }
    }

    @Test
    func rawDesktopAndMissingDisplaysDoNotNeedAnAccessibilityHit() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let desktop = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.desktopIconWindow)))
        let hit: () -> pid_t? = {
            Issue.record("A visible desktop or missing display must not require an accessibility hit")
            return nil
        }
        #expect(ContextNoteLocationReader.desktopDisplay(at: CGPoint(x: 500, y: 400), screens: desktopScreens,
            windowInfo: [desktop], hitProcessIdentifier: hit) == 1)
        #expect(ContextNoteLocationReader.desktopDisplay(at: .zero, screens: [], windowInfo: [desktop], hitProcessIdentifier: hit) == nil)
        #expect(ContextNoteLocationReader.desktopDisplay(at: CGPoint(x: 5000, y: 5000), screens: desktopScreens,
            windowInfo: [desktop], hitProcessIdentifier: hit) == nil)
    }

    @Test
    func realDockAccessibilityHitsDoNotExposeWindowsBehindTheDockLayer() {
        let bounds = CGRect(x: 204, y: 150, width: 1104, height: 650)
        let dock = windowInfo(frame: dockScreenFrames[0], layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84)
        for hit in [nil, 84] as [pid_t?] {
            for next in [windowInfo(frame: bounds), windowInfo(frame: bounds, owner: 84)] {
                let surface = surfaceUnderDock([dock, next], hitProcessIdentifier: hit)
                #expect(surface?.ownerProcessIdentifier == 84)
                #expect(surface?.frame == dockScreenFrames[0])
            }
        }
    }

    @Test
    func onlyTheDockBundleAtItsFullScreenDockLevelMayBeBypassed() {
        let bounds = CGRect(x: 204, y: 150, width: 1104, height: 650)
        let app = windowInfo(frame: bounds)
        let dock = windowInfo(frame: dockScreenFrames[0], layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84, ownerName: "Dock")
        for bundle in [nil, "test.overlay"] as [String?] {
            #expect(surfaceUnderDock([dock, app], hitProcessIdentifier: 42, dockBundle: bundle)?.ownerProcessIdentifier == 84)
        }
        for layer in [0, Int(CGWindowLevelForKey(.floatingWindow)), Int(CGWindowLevelForKey(.popUpMenuWindow))] {
            let other = windowInfo(frame: dockScreenFrames[0], layer: layer, owner: 84)
            #expect(surfaceUnderDock([other, app], hitProcessIdentifier: 42)?.ownerProcessIdentifier == 84)
        }
        let partial = windowInfo(frame: dockScreenFrames[0].insetBy(dx: 1, dy: 1),
                                 layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84)
        #expect(surfaceUnderDock([partial, app], hitProcessIdentifier: 42)?.ownerProcessIdentifier == 84)
        #expect(surfaceUnderDock([dock, app], hitProcessIdentifier: 42, screenFrames: [])?.ownerProcessIdentifier == 84)
    }

    @Test
    func bypassedDockSurfaceStillRequiresTheNextVisibleNormalWindowToOwnTheHit() {
        let bounds = CGRect(x: 204, y: 150, width: 1104, height: 650)
        let dock = windowInfo(frame: dockScreenFrames[0], layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84)
        let app = windowInfo(frame: bounds)
        let floating = windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.floatingWindow)))
        let foreign = windowInfo(frame: bounds, owner: 43)
        for tail in [[], [floating, app], [foreign, app]] {
            #expect(surfaceUnderDock([dock] + tail, hitProcessIdentifier: 42)?.ownerProcessIdentifier == 84)
        }
        #expect(surfaceUnderDock([dock, app], hitProcessIdentifier: 43)?.ownerProcessIdentifier == 84)
    }

    @Test
    func bypassOnlyRemovesTheProvenDockSurfaceAndPreservesOtherDockOrApplicationLayers() {
        let bounds = CGRect(x: 204, y: 150, width: 1104, height: 650)
        let dock = windowInfo(frame: dockScreenFrames[0], layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84)
        let app = windowInfo(frame: bounds)
        let blockers = [
            windowInfo(frame: bounds, layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84),
            windowInfo(frame: dockScreenFrames[0], layer: Int(CGWindowLevelForKey(.floatingWindow)), owner: 84),
            windowInfo(frame: dockScreenFrames[0], layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 43),
        ]
        for blocker in blockers {
            let surface = surfaceUnderDock([dock, blocker, app], hitProcessIdentifier: 42)
            #expect(surface?.ownerProcessIdentifier == 84)
            #expect(surface?.frame == dockScreenFrames[0])
            #expect(surface?.layer == Int(CGWindowLevelForKey(.dockWindow)))
        }
    }

    @Test
    func dockBypassKeepsStrictAccessibilityGeometryAndAmbiguityChecks() {
        let bounds = CGRect(x: 204, y: 150, width: 1104, height: 650)
        let dock = windowInfo(frame: dockScreenFrames[0], layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84)
        let surface = surfaceUnderDock([dock, windowInfo(frame: bounds)], hitProcessIdentifier: 42)
        let window = CaptureWindow(title: "Conversation", frame: bounds)
        for windows in [nil, [], [window, window], [CaptureWindow(title: "Other", frame: bounds.offsetBy(dx: 1, dy: 0))]] as [[CaptureWindow]?] {
            #expect(captureWindow(surface: surface, hit: (42, nil), windows: windows) == .unavailable)
        }
    }

    @Test
    func fullScreenDockMatchingUsesQuartzCoordinatesForEveryDisplay() {
        for screen in dockScreenFrames {
            let quartzFrame = CGRect(x: screen.minX, y: dockScreenFrames[0].maxY - screen.maxY,
                                     width: screen.width, height: screen.height)
            let bounds = quartzFrame.insetBy(dx: 100, dy: 100)
            let point = CGPoint(x: bounds.midX, y: bounds.midY)
            let dock = windowInfo(frame: quartzFrame, layer: Int(CGWindowLevelForKey(.dockWindow)), owner: 84)
            let surface = ContextNoteLocationReader.captureSurface(at: point,
                windowInfo: [dock, windowInfo(frame: bounds)], screenFrames: dockScreenFrames,
                hitProcessIdentifier: 42, bundleIdentifier: { $0 == 84 ? "com.apple.dock" : "test.chat" })
            #expect(surface?.ownerProcessIdentifier == 42)
            #expect(surface?.frame == bounds)
        }
    }

    @Test
    func missingFocusedWindowUsesOnlyAnUnambiguousApplicationWindow() {
        #expect(ContextNoteLocationReader.findWindow(direct: nil, candidates: { [1] }, matches: { _ in true }) == 1)
        #expect(ContextNoteLocationReader.findWindow(direct: nil, candidates: { [1, 2] }, matches: { _ in true }) == nil)
    }

    @Test
    func desktopCaptureDoesNotRequireAnAccessibilityWindow() {
        let desktop = ContextNoteLocation.desktop(displayID: "screen-2", displayName: "External")
        let result = ContextNoteLocationReader.observe(isTrusted: true, desktopLocation: { desktop }) {
            .unavailable
        }
        #expect(result == .location(desktop))
    }

    @Test(arguments: ["", "Desktop", "桌面"])
    func finderDesktopWindowTitleDoesNotReplaceDisplayIdentity(title: String) {
        let desktop = ContextNoteLocation.desktop(displayID: "screen-2", displayName: "External")
        let result = ContextNoteLocationReader.observe(isTrusted: true, desktopLocation: { desktop }) {
            ContextNoteLocationReader.resolve(bundleIdentifier: "com.apple.finder", applicationName: "Finder",
                                              windowTitle: title, isBrowser: false, pageAddress: nil)
        }
        #expect(result == .location(desktop))
    }

    @Test
    func verifiedDesktopDoesNotRequireAccessibilityPermission() {
        let desktop = ContextNoteLocation.desktop(displayID: "screen-2", displayName: "External")
        let result = ContextNoteLocationReader.observe(isTrusted: false, desktopLocation: { desktop }) {
            Issue.record("Desktop capture must not inspect accessibility windows")
            return .ignored
        }
        #expect(result == .location(desktop))
    }

    @Test
    func applicationsStillRequireAccessibilityPermission() {
        let result = ContextNoteLocationReader.observe(isTrusted: false, desktopLocation: {
            nil
        }) {
            Issue.record("An untrusted capture must not inspect accessibility windows")
            return .ignored
        }
        #expect(result == .unavailable)
    }

    @Test
    func unidentifiedDesktopPreservesOrdinaryWindowAndBrowserResolution() {
        let folder = ContextNoteLocationReader.observe(isTrusted: true, desktopLocation: { nil }) {
            ContextNoteLocationReader.resolve(bundleIdentifier: "com.apple.finder", applicationName: "Finder",
                                              windowTitle: "Desktop", isBrowser: false, pageAddress: nil)
        }
        #expect(folder == .location(.window(bundleIdentifier: "com.apple.finder", applicationName: "Finder", title: "Desktop")))
        let browser = ContextNoteLocationReader.observe(isTrusted: true, desktopLocation: { nil }) {
            ContextNoteLocationReader.resolve(bundleIdentifier: "browser", applicationName: "Browser",
                                              windowTitle: "Desktop", isBrowser: true, pageAddress: nil)
        }
        #expect(browser == .unavailable)
    }
}
