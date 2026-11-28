import AppKit
import ApplicationServices

// AXUIElement is an immutable Core Foundation reference; the inventory crosses executors without mutating it.
struct MenuBarIcon: Identifiable, @unchecked Sendable {
    let id: AXUIElement
    let app: String
    let title: String
    let frame: CGRect
    let isFixed: Bool

    private static let systemHosts: Set<String> = ["com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.MenuBarAgent"]

    static func isFixed(identifier: String?, owner: String?) -> Bool {
        guard let owner, systemHosts.contains(owner) else { return false }
        return ["com.apple.menuextra.clock", "com.apple.menuextra.controlcenter"].contains(identifier)
    }

    static func attribute(_ key: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    static func children(of application: AXUIElement) -> [AXUIElement] {
        guard let bar = attribute(kAXExtrasMenuBarAttribute, of: application),
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        let element = unsafeDowncast(bar, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.15)
        return attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }

    @MainActor
    static func inventory() async -> [MenuBarIcon] {
        guard AXIsProcessTrusted() else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String, String?)? in
            guard app.processIdentifier != ownPID,
                  !(["appex", "xpc"].contains(app.bundleURL?.pathExtension ?? "")),
                  let name = app.localizedName ?? app.bundleIdentifier else { return nil }
            return (app.processIdentifier, name, app.bundleIdentifier)
        }
        let read = Task.detached(priority: .userInitiated) {
            var items: [MenuBarIcon] = []
            for (pid, app, bundle) in apps {
                if Task.isCancelled { break }
                let application = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(application, 0.15)
                for element in children(of: application) {
                    AXUIElementSetMessagingTimeout(element, 0.15)
                    guard let frame = AccessibilityGeometry.frame(of: element), !frame.isEmpty else { continue }
                    let identifier = attribute(kAXIdentifierAttribute, of: element) as? String
                    let description = attribute(kAXDescriptionAttribute, of: element) as? String
                    let title = [description, attribute(kAXTitleAttribute, of: element) as? String]
                        .compactMap { $0 }.first { !$0.isEmpty } ?? app
                    items.append(MenuBarIcon(id: element, app: app, title: title, frame: frame,
                                             isFixed: isFixed(identifier: identifier, owner: bundle)))
                }
            }
            return items
        }
        return await withTaskCancellationHandler { await read.value } onCancel: { read.cancel() }
    }

    @MainActor func isAt(_ point: CGPoint) -> Bool {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return false }
        // A status button may expose an image or text child at its center.
        for _ in 0..<4 {
            if CFEqual(element, id) { return true }
            // A single host draws other apps' status buttons on macOS 27.
            if Self.attribute(kAXRoleAttribute, of: element) as? String == kAXMenuBarItemRole,
               let hitFrame = AccessibilityGeometry.frame(of: element), hitFrame == AccessibilityGeometry.frame(of: id) {
                var pid: pid_t = 0
                if AXUIElementGetPid(element, &pid) == .success,
                   let host = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                   host == "com.apple.MenuBarAgent" { return true }
            }
            guard let parent = Self.attribute(kAXParentAttribute, of: element),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            element = unsafeDowncast(parent, to: AXUIElement.self)
        }
        return false
    }
}
