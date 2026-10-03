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
                            ownerName: String? = nil) -> [String: Any] {
        var info: [String: Any] = [kCGWindowBounds as String: frame.dictionaryRepresentation,
                                  kCGWindowLayer as String: layer,
                                  kCGWindowOwnerPID as String: owner,
                                  kCGWindowAlpha as String: alpha]
        if let ownerName { info[kCGWindowOwnerName as String] = ownerName }
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
                               main: CaptureWindow? = nil) -> ContextNoteObservation {
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
        }) { _, element in
            guard let element, let window = fixtures.first(where: { CFEqual($0.element, element) })?.window else { return .unavailable }
            return ContextNoteLocationReader.resolve(bundleIdentifier: "test.chat", applicationName: "Chat",
                windowTitle: window.title, isBrowser: false, pageAddress: nil)
        }
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
        #expect(captureWindow(surface: nil, hit: (42, window), windows: nil)
                == .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation")))
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
        }, frame: { _ in bounds }) { _, _ in
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
        }, frame: { _ in bounds }) { _, element in
            guard let element, CFEqual(element, window) else { return .unavailable }
            return .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation"))
        }
        #expect(result == .location(.window(bundleIdentifier: "test.chat", applicationName: "Chat", title: "Conversation")))
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
