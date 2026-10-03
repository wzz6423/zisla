import AppKit
import ApplicationServices
import ZislaCore

@MainActor
public struct ContextNoteNavigator {
    struct Window {
        let title: String
        let isMinimized: Bool?
        var requiresExactTitle = false
        var restore: @MainActor () -> Bool
        var activate: @MainActor () -> Bool
        var raise: @MainActor () -> Bool
    }

    struct Display {
        let id: String
        let pointerPosition: CGPoint

        init(id: String, visibleFrame: CGRect, mainScreenTop: CGFloat) {
            self.id = id
            pointerPosition = CGPoint(x: visibleFrame.midX, y: mainScreenTop - visibleFrame.midY)
        }
    }

    @MainActor
    struct Dependencies {
        var isTrusted: @MainActor () -> Bool
        var openURL: @MainActor (URL) -> Bool
        var windows: @MainActor (String) -> [Window]?
        var displays: @MainActor () -> [Display]
        var movePointer: @MainActor (CGPoint) -> Bool
        var desktopDirectory: @MainActor () -> URL?

        static var live: Self {
            Self(
                isTrusted: { AccessibilityPermission.isTrusted },
                openURL: { NSWorkspace.shared.open($0) },
                windows: { bundle in
                    var windows: [Window] = []
                    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundle) {
                        let application = AXUIElementCreateApplication(app.processIdentifier)
                        AXUIElementSetMessagingTimeout(application, 0.2)
                        guard let elements = windowElements(readAttribute: { attribute($0, from: application) }) else { return nil }
                        windows += elements.map { candidate in
                            let element = candidate.element
                            AXUIElementSetMessagingTimeout(element, 0.2)
                            return Window(
                                title: attribute(kAXTitleAttribute, from: element) as? String ?? "",
                                isMinimized: attribute(kAXMinimizedAttribute, from: element) as? Bool,
                                requiresExactTitle: candidate.requiresExactTitle,
                                restore: { AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success },
                                activate: { app.activate() },
                                raise: { AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success }
                            )
                        }
                    }
                    return windows
                },
                displays: {
                    let screens = NSScreen.screens
                    let mainTop = screens.first?.frame.maxY ?? 0
                    return screens.compactMap { screen in
                        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
                        return Display(id: CFUUIDCreateString(nil, uuid) as String,
                                       visibleFrame: screen.visibleFrame, mainScreenTop: mainTop)
                    }
                },
                movePointer: { CGWarpMouseCursorPosition($0) == .success },
                desktopDirectory: { FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first }
            )
        }
    }

    private let dependencies: Dependencies

    public init() { dependencies = .live }
    init(dependencies: Dependencies) { self.dependencies = dependencies }

    public func navigate(to location: ContextNoteLocation) -> Bool {
        switch location {
        case let .webPage(url, _, _):
            guard let address = ContextNoteLocationReader.webURL(url.absoluteString) else { return false }
            return dependencies.openURL(address)
        case let .window(bundleIdentifier, _, title):
            guard dependencies.isTrusted(), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let windows = dependencies.windows(bundleIdentifier) else { return false }
            let matches = windows.filter { $0.title == title || (windows.count == 1 && !$0.requiresExactTitle) }
            guard matches.count == 1, let window = matches.first, let minimized = window.isMinimized else { return false }
            if minimized, !window.restore() { return false }
            return window.activate() && window.raise()
        case let .desktop(displayID, _):
            guard dependencies.isTrusted() else { return false }
            let matches = dependencies.displays().filter { $0.id == displayID }
            guard matches.count == 1, let display = matches.first,
                  let directory = dependencies.desktopDirectory(),
                  dependencies.movePointer(display.pointerPosition) else { return false }
            return dependencies.openURL(directory)
        }
    }

    private static func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func windowElements(readAttribute: (String) -> CFTypeRef?) -> [(element: AXUIElement, requiresExactTitle: Bool)]? {
        let listed = readAttribute(kAXWindowsAttribute) as? [AXUIElement]
        var elements = (listed ?? []).map { (element: $0, requiresExactTitle: false) }
        for name in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            guard let value = readAttribute(name), CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
            let element = value as! AXUIElement
            guard !elements.contains(where: { CFEqual($0.element, element) }) else { continue }
            // A window omitted from AXWindows does not prove this is the application's only window.
            elements.append((element, true))
        }
        return listed == nil && elements.isEmpty ? nil : elements
    }
}
