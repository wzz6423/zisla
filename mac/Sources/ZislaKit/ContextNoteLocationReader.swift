import AppKit
import ApplicationServices
import ZislaCore

public enum ContextNoteObservation: Equatable, Sendable {
    case location(ContextNoteLocation)
    case ignored
    case unavailable
}

@MainActor
public enum ContextNoteLocationReader {
    struct WindowSnapshot {
        let frame: CGRect
        let layer: Int
        let ownerProcessIdentifier: pid_t
        var ownerName: String? = nil

        var isDesktop: Bool {
            layer <= CGWindowLevelForKey(.desktopIconWindow)
                || (ownerName == "Window Server" && layer == CGWindowLevelForKey(.desktopIconWindow) + 1)
        }

        func matches(_ windowFrame: CGRect?, processIdentifier: pid_t) -> Bool {
            ownerProcessIdentifier == processIdentifier
                && layer == CGWindowLevelForKey(.normalWindow)
                && frame == windowFrame
        }
    }

    public static func capture(at point: CGPoint) -> ContextNoteObservation {
        let screens = NSScreen.screens
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        return observe(isTrusted: AccessibilityPermission.isTrusted, desktopLocation: {
            desktopLocation(at: point, screens: screens, windowInfo: windows)
        }) {
            let quartzPoint = CGPoint(x: point.x, y: (screens.first?.frame.maxY ?? 0) - point.y)
            return captureWindow(at: quartzPoint, windowInfo: windows, screenFrames: screens.map(\.frame)) { surface in
                desktopLocation(at: point, screens: screens, windowInfo: windows, capturedSurface: surface)
            }
        }
    }

    private static func captureWindow(at point: CGPoint, windowInfo: [[String: Any]]?, screenFrames: [CGRect],
                                      desktopLocation: (WindowSnapshot) -> ContextNoteLocation?) -> ContextNoteObservation {
        let hit = hitElement(at: point).map { hit in
            let direct = attribute(kAXRoleAttribute, from: hit.element) as? String == kAXWindowRole
                ? hit.element : attribute(kAXWindowAttribute, from: hit.element).flatMap(asElement)
            return (processIdentifier: hit.processIdentifier, window: direct)
        }
        let surface = captureSurface(at: point, windowInfo: windowInfo, screenFrames: screenFrames,
            hitProcessIdentifier: hit?.processIdentifier,
            bundleIdentifier: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier })
        return captureWindow(surface: surface, hit: hit, readAttribute: { pid, name in
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.1)
            return attribute(name, from: application)
        }, frame: windowFrame, desktopLocation: desktopLocation) { pid, window in
            guard let app = NSRunningApplication(processIdentifier: pid) else { return .unavailable }
            return read(app: app, window: window)
        }
    }

    private static func hitElement(at point: CGPoint) -> (processIdentifier: pid_t, element: AXUIElement)? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var element: AXUIElement?
        var pid: pid_t = 0
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success,
              let element, AXUIElementGetPid(element, &pid) == .success else { return nil }
        return (pid, element)
    }

    static func captureWindow(surface: WindowSnapshot?, hit: (processIdentifier: pid_t, window: AXUIElement?)?,
                              readAttribute: (pid_t, String) -> CFTypeRef?, frame: (AXUIElement) -> CGRect?,
                              desktopLocation: (WindowSnapshot) -> ContextNoteLocation?,
                              read: (pid_t, AXUIElement?) -> ContextNoteObservation) -> ContextNoteObservation {
        guard let pid = surface?.ownerProcessIdentifier ?? hit?.processIdentifier else { return .unavailable }
        guard pid != ProcessInfo.processInfo.processIdentifier else { return .ignored }
        if let surface, surface.isDesktop {
            return desktopLocation(surface).map(ContextNoteObservation.location) ?? .unavailable
        }
        let direct = hit?.processIdentifier == pid ? hit?.window : nil
        if let direct, surface == nil || surface?.matches(frame(direct), processIdentifier: pid) == true {
            let observation = read(pid, direct)
            if observation != .unavailable { return observation }
        }
        let window = findWindow(direct: nil, candidates: {
            ContextNoteNavigator.windowElements(readAttribute: { readAttribute(pid, $0) })?.map(\.element)
        }, matches: { surface?.matches(frame($0), processIdentifier: pid) == true })
        return read(pid, window)
    }

    static func captureSurface(at point: CGPoint, windowInfo: [[String: Any]]?, screenFrames: [CGRect],
                               hitProcessIdentifier: pid_t?, bundleIdentifier: (pid_t) -> String?,
                               excludingProcessIdentifier: pid_t? = nil, skippingMenuBar: Bool = false) -> WindowSnapshot? {
        guard let surface = topWindow(at: point, windowInfo: windowInfo, excludingProcessIdentifier: excludingProcessIdentifier,
                                      skippingMenuBar: skippingMenuBar) else { return nil }
        // Dock can publish a full-screen surface while passing pointer input to another app.
        guard let hitProcessIdentifier, hitProcessIdentifier != surface.ownerProcessIdentifier,
              surface.layer == CGWindowLevelForKey(.dockWindow),
              bundleIdentifier(surface.ownerProcessIdentifier) == "com.apple.dock",
              screenFrames.contains(where: {
                  CGRect(x: $0.minX, y: screenFrames[0].maxY - $0.maxY, width: $0.width, height: $0.height) == surface.frame
              }) else { return surface }
        guard let underlying = topWindow(at: point, windowInfo: windowInfo, excludingProcessIdentifier: excludingProcessIdentifier,
                                         skippingMenuBar: skippingMenuBar, excludingSurface: surface),
              underlying.layer == CGWindowLevelForKey(.normalWindow) || underlying.isDesktop,
              underlying.ownerProcessIdentifier == hitProcessIdentifier
                || (underlying.isDesktop && underlying.ownerName == "Window Server"
                    && bundleIdentifier(hitProcessIdentifier) == "com.apple.finder") else { return surface }
        return underlying
    }

    public static func current(at point: CGPoint) -> ContextNoteObservation {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unavailable }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .ignored }
        let trusted = AccessibilityPermission.isTrusted
        if app.bundleIdentifier == "com.apple.finder" {
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
            let screens = NSScreen.screens
            return observeFinder(isTrusted: trusted, focusedWindowLocation: {
                let application = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(application, 0.1)
                guard let window = attribute(kAXFocusedWindowAttribute, from: application).flatMap(asElement),
                      !focusedWindowIsDesktop(frame: windowFrame(window), processIdentifier: app.processIdentifier,
                                              windowInfo: windows) else { return nil }
                return read(app: app, window: window)
            }) { skippingMenuBar in
                // The island opens over the menu bar before capturing the underlying Finder context.
                desktopLocation(at: point, screens: screens, windowInfo: windows,
                                hitProcessIdentifier: skippingMenuBar ? {
                                    hitElement(at: CGPoint(x: point.x, y: (screens.first?.frame.maxY ?? 0) - point.y))?.processIdentifier
                                } : nil,
                                excludingProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
                                skippingMenuBar: skippingMenuBar)
            }
        }
        return observe(isTrusted: trusted, desktopLocation: { nil }) {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.1)
            let direct = attribute(kAXFocusedWindowAttribute, from: application).flatMap(asElement)
            let window = findWindow(direct: direct, candidates: {
                attribute(kAXWindowsAttribute, from: application) as? [AXUIElement]
            }, matches: { _ in true })
            return read(app: app, window: window)
        }
    }

    static func observe(isTrusted: Bool, desktopLocation: () -> ContextNoteLocation?,
                        windowLocation: () -> ContextNoteObservation) -> ContextNoteObservation {
        if let desktop = desktopLocation() { return .location(desktop) }
        guard isTrusted else { return .unavailable }
        return windowLocation()
    }

    static func observeFinder(isTrusted: Bool, focusedWindowLocation: () -> ContextNoteObservation?,
                              desktopLocation: (Bool) -> ContextNoteLocation?) -> ContextNoteObservation {
        let focused = isTrusted ? focusedWindowLocation() : nil
        if case let .location(location)? = focused { return .location(location) }
        if let desktop = desktopLocation(isTrusted) { return .location(desktop) }
        return focused ?? .unavailable
    }

    static func focusedWindowIsDesktop(frame: CGRect?, processIdentifier: pid_t, windowInfo: [[String: Any]]?) -> Bool {
        guard let frame, let windowInfo else { return false }
        for window in windowInfo {
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let candidate = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = window[kCGWindowLayer as String] as? NSNumber else { return false }
            guard owner.int32Value == processIdentifier, candidate == frame else { continue }
            return WindowSnapshot(frame: candidate, layer: layer.intValue, ownerProcessIdentifier: owner.int32Value,
                                  ownerName: window[kCGWindowOwnerName as String] as? String).isDesktop
        }
        return false
    }

    static func findWindow<Window>(direct: Window?, candidates: () -> [Window]?,
                                   matches: (Window) -> Bool) -> Window? {
        if let direct { return direct }
        let matches = candidates()?.filter(matches) ?? []
        return matches.count == 1 ? matches[0] : nil
    }

    static func topWindow(at point: CGPoint, windowInfo: [[String: Any]]?,
                          excludingProcessIdentifier: pid_t? = nil, skippingMenuBar: Bool = false,
                          excludingSurface: WindowSnapshot? = nil) -> WindowSnapshot? {
        guard let windowInfo else { return nil }
        for window in windowInfo {
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber,
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  let owner = window[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
            guard alpha.doubleValue > 0, frame.contains(point), owner.int32Value != excludingProcessIdentifier else { continue }
            // A pass-through overlay can retain its visible Window Server surface after collapsing.
            if owner.int32Value == ProcessInfo.processInfo.processIdentifier,
               let number = window[kCGWindowNumber as String] as? NSNumber,
               NSApp.window(withWindowNumber: number.intValue)?.ignoresMouseEvents == true { continue }
            if let excludingSurface, owner.int32Value == excludingSurface.ownerProcessIdentifier,
               layer.intValue == excludingSurface.layer, frame == excludingSurface.frame { continue }
            let ownerName = window[kCGWindowOwnerName as String] as? String
            if skippingMenuBar, layer.intValue == CGWindowLevelForKey(.mainMenuWindow), ownerName == "Window Server" { continue }
            return WindowSnapshot(frame: frame, layer: layer.intValue, ownerProcessIdentifier: owner.int32Value, ownerName: ownerName)
        }
        return nil
    }

    static func desktopDisplay(at point: CGPoint, screens: [ScreenSnapshot], windowInfo: [[String: Any]]?,
                               capturedSurface: WindowSnapshot? = nil,
                               hitProcessIdentifier: (() -> pid_t?)? = nil,
                               bundleIdentifier: (pid_t) -> String? = { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
                               excludingProcessIdentifier: pid_t? = nil, skippingMenuBar: Bool = false) -> CGDirectDisplayID? {
        guard let main = screens.first, let screen = screens.first(where: { $0.frame.contains(point) }) else { return nil }
        let quartzPoint = CGPoint(x: point.x, y: main.frame.maxY - point.y)
        var surface = capturedSurface ?? topWindow(at: quartzPoint, windowInfo: windowInfo,
                                                   excludingProcessIdentifier: excludingProcessIdentifier, skippingMenuBar: skippingMenuBar)
        if surface?.isDesktop != true, let hitProcessIdentifier {
            surface = captureSurface(at: quartzPoint, windowInfo: windowInfo, screenFrames: screens.map(\.frame),
                hitProcessIdentifier: hitProcessIdentifier(), bundleIdentifier: bundleIdentifier,
                excludingProcessIdentifier: excludingProcessIdentifier, skippingMenuBar: skippingMenuBar)
        }
        guard surface?.isDesktop == true else { return nil }
        return screen.displayID
    }

    private static func desktopLocation(at point: CGPoint, screens: [NSScreen], windowInfo: [[String: Any]]?,
                                        capturedSurface: WindowSnapshot? = nil,
                                        hitProcessIdentifier: (() -> pid_t?)? = nil,
                                        excludingProcessIdentifier: pid_t? = nil, skippingMenuBar: Bool = false) -> ContextNoteLocation? {
        let snapshots = screens.compactMap { ScreenSnapshot(screen: $0) }
        guard let display = desktopDisplay(at: point, screens: snapshots, windowInfo: windowInfo,
                                          capturedSurface: capturedSurface, hitProcessIdentifier: hitProcessIdentifier,
                                          excludingProcessIdentifier: excludingProcessIdentifier, skippingMenuBar: skippingMenuBar),
              let screen = screens.first(where: { ScreenSnapshot(screen: $0)?.displayID == display }),
              let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return .desktop(displayID: CFUUIDCreateString(nil, uuid) as String, displayName: screen.localizedName)
    }

    private static func windowFrame(_ window: AXUIElement) -> CGRect? {
        AXUIElementSetMessagingTimeout(window, 0.1)
        guard let position = attribute(kAXPositionAttribute, from: window), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(kAXSizeAttribute, from: window), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private static func read(app: NSRunningApplication, window: AXUIElement?) -> ContextNoteObservation {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .ignored }
        guard let bundle = app.bundleIdentifier else { return .unavailable }
        let appName = app.localizedName ?? bundle
        guard let window else { return .unavailable }
        AXUIElementSetMessagingTimeout(window, 0.1)
        let title = attribute(kAXTitleAttribute, from: window) as? String ?? ""
        let browser = BrowserDownloadAgent.allCases.contains { $0 != .airDrop && $0.bundleIdentifiers.contains(bundle) }
        let pageURL = browser ? pageAddress(in: window) : nil
        return resolve(bundleIdentifier: bundle, applicationName: appName, windowTitle: title,
                       isBrowser: browser, pageAddress: pageURL)
    }

    static func resolve(bundleIdentifier: String, applicationName: String, windowTitle: String,
                        isBrowser: Bool, pageAddress: String?) -> ContextNoteObservation {
        if isBrowser {
            guard let pageAddress, let url = webURL(pageAddress) else { return .unavailable }
            return .location(.webPage(url: url, title: windowTitle, applicationName: applicationName))
        }
        guard !windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .unavailable }
        return .location(.window(bundleIdentifier: bundleIdentifier, applicationName: applicationName, title: windowTitle))
    }

    static func webURL(_ value: String) -> URL? {
        guard var components = URLComponents(string: value),
              ["https", "http"].contains(components.scheme?.lowercased()),
              let host = components.host, !host.isEmpty else { return nil }
        components.user = nil
        components.password = nil
        return components.url
    }

    private static func pageAddress(in window: AXUIElement) -> String? {
        findPageAddress(in: window,
            document: { address(attribute(kAXDocumentAttribute, from: $0)) },
            role: {
                AXUIElementSetMessagingTimeout($0, 0.05)
                return attribute(kAXRoleAttribute, from: $0) as? String
            },
            url: { address(attribute(kAXURLAttribute, from: $0)) },
            children: {
                var values: CFArray?
                guard AXUIElementCopyAttributeValues($0, kAXChildrenAttribute as CFString, 0, 80, &values) == .success
                else { return [] }
                return values as? [AXUIElement] ?? []
            }
        )
    }

    static func findPageAddress<Node>(in root: Node, document: (Node) -> String?, role: (Node) -> String?,
                                     url: (Node) -> String?, children: (Node) -> [Node],
                                     now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) -> String? {
        if let document = document(root), webURL(document) != nil { return document }
        // Stop at web areas: traversing the page DOM would read unrelated content and grow without bound.
        var queue = [root]
        var index = 0
        let deadline = now() + 0.2
        while index < queue.count, now() < deadline {
            let element = queue[index]
            index += 1
            if role(element) == "AXWebArea" {
                if let url = url(element), webURL(url) != nil { return url }
                continue
            }
            queue.append(contentsOf: children(element).prefix(80 - queue.count))
        }
        return nil
    }

    private static func address(_ value: CFTypeRef?) -> String? {
        if let url = value as? URL { return url.absoluteString }
        return value as? String
    }

    private static func asElement(_ value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
