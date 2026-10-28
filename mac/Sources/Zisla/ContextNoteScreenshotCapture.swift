import AppKit
import ScreenCaptureKit
import ZislaCore

enum ContextNoteScreenshotSource: Equatable, Sendable {
    case window(CGWindowID, processIdentifier: pid_t)
    case display(CGDirectDisplayID)
}

@MainActor
enum ContextNoteScreenshotCapture {
    struct WindowReference {
        let processIdentifier: pid_t
        let frame: CGRect?
        let title: String
    }

    static func source(
        for location: ContextNoteLocation,
        window: WindowReference?,
        hasPermission: () -> Bool = CGPreflightScreenCaptureAccess,
        windowInfo: () -> [[String: Any]]? = {
            CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        },
        displayIdentifier: (String) -> CGDirectDisplayID? = { identifier in
            NSScreen.screens.compactMap(ScreenshotCaptureService.displayID).first { display in
                guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return false }
                return CFUUIDCreateString(nil, uuid) as String == identifier
            }
        }
    ) throws -> ContextNoteScreenshotSource {
        try ScreenshotCaptureService.requirePermission(hasPermission)
        switch location {
        case .desktop(let identifier, _):
            guard let display = displayIdentifier(identifier) else { throw ScreenshotCaptureError.screenUnavailable }
            return .display(display)
        case .window, .webPage:
            guard let window, let frame = window.frame, let info = windowInfo() else {
                throw ScreenshotCaptureError.windowUnavailable
            }
            var candidates = info.compactMap { entry -> (id: CGWindowID, title: String?)? in
                guard let owner = entry[kCGWindowOwnerPID as String] as? NSNumber,
                      owner.int32Value == window.processIdentifier,
                      let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                      CGRect(dictionaryRepresentation: bounds as CFDictionary) == frame,
                      let layer = entry[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0,
                      let number = entry[kCGWindowNumber as String] as? NSNumber,
                      number.uint32Value != kCGNullWindowID else { return nil }
                return (number.uint32Value, entry[kCGWindowName as String] as? String)
            }
            if candidates.count > 1 {
                candidates = candidates.filter { $0.title == window.title }
            }
            guard candidates.count == 1 else { throw ScreenshotCaptureError.windowUnavailable }
            return .window(candidates[0].id, processIdentifier: window.processIdentifier)
        }
    }

    static func capture(
        _ source: ContextNoteScreenshotSource,
        hasPermission: () -> Bool = CGPreflightScreenCaptureAccess,
        windowCapture: (CGWindowID, pid_t) async throws -> CGImage = captureWindow,
        displayCapture: (CGDirectDisplayID) async throws -> CGImage = captureDisplay,
        encode: (CGImage) -> Data? = { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    ) async throws -> Data {
        try ScreenshotCaptureService.requirePermission(hasPermission)
        try Task.checkCancellation()
        let image: CGImage
        switch source {
        case .window(let identifier, let processIdentifier):
            image = try await windowCapture(identifier, processIdentifier)
        case .display(let identifier):
            image = try await displayCapture(identifier)
        }
        try Task.checkCancellation()
        guard let data = encode(image) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    static func configuration(for frame: CGRect, scale: CGFloat) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(frame.width * scale)
        configuration.height = Int(frame.height * scale)
        configuration.captureResolution = .best
        configuration.showsCursor = false
        return configuration
    }

    private static func captureWindow(identifier: CGWindowID, processIdentifier: pid_t) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: {
            $0.windowID == identifier && $0.owningApplication?.processID == processIdentifier
        }) else { throw ScreenshotCaptureError.windowUnavailable }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try await SCScreenshotManager.captureImage(contentFilter: filter,
            configuration: configuration(for: filter.contentRect, scale: CGFloat(filter.pointPixelScale)))
    }

    private static func captureDisplay(identifier: CGDirectDisplayID) async throws -> CGImage {
        guard let screen = NSScreen.screens.first(where: { ScreenshotCaptureService.displayID(for: $0) == identifier }) else {
            throw ScreenshotCaptureError.screenUnavailable
        }
        return try await ScreenshotCaptureService.capture(screen: screen,
            excludingApplicationWithProcessIdentifier: ProcessInfo.processInfo.processIdentifier).cgImage
    }
}
