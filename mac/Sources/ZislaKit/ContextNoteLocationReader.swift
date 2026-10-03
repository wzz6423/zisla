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
    public static func capture(at point: CGPoint) -> ContextNoteObservation {
        guard AccessibilityPermission.isTrusted else { return .unavailable }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var element: AXUIElement?
        let quartzY = (NSScreen.screens.first?.frame.maxY ?? 0) - point.y
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(quartzY), &element) == .success,
              let element else { return .unavailable }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid) else { return .unavailable }
        let window = attribute(kAXRoleAttribute, from: element) as? String == kAXWindowRole
            ? element : attribute(kAXWindowAttribute, from: element).flatMap(asElement)
        return read(app: app, window: window, at: point)
    }

    public static func current(at point: CGPoint) -> ContextNoteObservation {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unavailable }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .ignored }
        guard AccessibilityPermission.isTrusted else { return .unavailable }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.1)
        let window = attribute(kAXFocusedWindowAttribute, from: application).flatMap(asElement)
        return read(app: app, window: window, at: point)
    }

    private static func read(app: NSRunningApplication, window: AXUIElement?, at point: CGPoint) -> ContextNoteObservation {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .ignored }
        guard let bundle = app.bundleIdentifier else { return .unavailable }
        let appName = app.localizedName ?? bundle
        guard let window else {
            guard bundle == "com.apple.finder",
                  let screen = WindowPlacement.screenUnderMouse(point: point),
                  let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(display.uint32Value)?.takeRetainedValue()
            else { return .unavailable }
            return .location(.desktop(displayID: CFUUIDCreateString(nil, uuid) as String, displayName: screen.localizedName))
        }
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
