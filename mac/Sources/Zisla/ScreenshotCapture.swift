import AppKit
import ZislaCore
import ZislaKit
import os.log
import ScreenCaptureKit
import SwiftUI

enum ScreenshotCaptureError: LocalizedError, Equatable {
    case screenUnavailable
    case permissionRequired

    var errorDescription: String? {
        switch self {
        case .screenUnavailable:
            "无法读取当前显示器"
        case .permissionRequired:
            "请在系统设置的“隐私与安全性 > 屏幕录制”中允许 zisla"
        }
    }
}

struct ScreenshotFrameDiagnostics: Equatable, Sendable {
    let api: String
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let colorSpaceName: String?
    let bitmapInfo: UInt32
    let alphaInfo: UInt32
    let sampleHash: UInt64
    let uniqueSampleCount: Int

    var appearsUniform: Bool {
        uniqueSampleCount == 1
    }
}

enum ScreenshotCaptureService {
    private static let logger = Logger(
        subsystem: "dev.wzz.zisla",
        category: "ScreenshotCapture"
    )

    static func requirePermission(
        _ hasAccess: () -> Bool = CGPreflightScreenCaptureAccess
    ) throws {
        guard hasAccess() else {
            throw ScreenshotCaptureError.permissionRequired
        }
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// Starting with macOS 15, `CGDisplayCreateImage` is obsolete. It still links and returns an image
    /// with the correct dimensions, but its contents may come from reclaimed video memory and appear
    /// as a solid-color overlay. Always use ScreenCaptureKit, falling back only on macOS 14.
    @MainActor
    static func capture(screen: NSScreen) async throws -> (image: NSImage, cgImage: CGImage) {
        try requirePermission()
        guard let displayID = displayID(for: screen) else {
            throw ScreenshotCaptureError.screenUnavailable
        }
        do {
            let cgImage = try await captureWithScreenCaptureKit(
                displayID: displayID,
                screen: screen,
                excludingProcessIdentifier: nil
            )
            return (NSImage(cgImage: cgImage, size: screen.frame.size), cgImage)
        } catch {
            if #unavailable(macOS 15.0) {
                guard let rawImage = CGDisplayCreateImage(displayID) else { throw error }
                let cgImage = try detachedImageAndDiagnose(
                    rawImage,
                    api: "CGDisplayCreateImage"
                )
                return (NSImage(cgImage: cgImage, size: screen.frame.size), cgImage)
            }
            throw error
        }
    }

    @MainActor
    static func capture(
        screen: NSScreen,
        excludingApplicationWithProcessIdentifier processIdentifier: pid_t
    ) async throws -> (image: NSImage, cgImage: CGImage) {
        try requirePermission()
        guard let displayID = displayID(for: screen) else {
            throw ScreenshotCaptureError.screenUnavailable
        }
        let cgImage = try await captureWithScreenCaptureKit(
            displayID: displayID,
            screen: screen,
            excludingProcessIdentifier: processIdentifier
        )
        return (NSImage(cgImage: cgImage, size: screen.frame.size), cgImage)
    }

    @MainActor
    private static func captureWithScreenCaptureKit(
        displayID: CGDirectDisplayID,
        screen: NSScreen,
        excludingProcessIdentifier processIdentifier: pid_t?
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenshotCaptureError.screenUnavailable
        }
        let excludedApplications = processIdentifier.map { identifier in
            content.applications.filter { $0.processID == identifier }
        } ?? []

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        // NSScreen may become stale after display reconfiguration; a zero scale would collapse pixel dimensions.
        let scale = max(screen.backingScaleFactor, 1)
        let width = max(1, Int((screen.frame.width * scale).rounded()))
        let height = max(1, Int((screen.frame.height * scale).rounded()))

        if #available(macOS 26.0, *) {
            let configuration = SCScreenshotConfiguration()
            configuration.width = width
            configuration.height = height
            configuration.showsCursor = false
            configuration.displayIntent = .local
            configuration.dynamicRange = .sdr
            let output = try await SCScreenshotManager.captureScreenshot(
                contentFilter: filter,
                configuration: configuration
            )
            guard let image = output.sdrImage else {
                throw ScreenshotCaptureError.screenUnavailable
            }
            return try detachedImageAndDiagnose(image, api: "SCScreenshotConfiguration")
        }

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.captureResolution = .best
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return try detachedImageAndDiagnose(image, api: "SCStreamConfiguration")
    }

    @available(macOS 14.0, *)
    private static func detachedImageAndDiagnose(
        _ image: CGImage,
        api: String
    ) throws -> CGImage {
        let diagnostics = frameDiagnostics(for: image, api: api)
        logger.info(
            "capture api=\(diagnostics.api, privacy: .public) size=\(diagnostics.width)x\(diagnostics.height, privacy: .public) bytesPerRow=\(diagnostics.bytesPerRow, privacy: .public) colorSpace=\(diagnostics.colorSpaceName ?? "unknown", privacy: .public) bitmapInfo=\(diagnostics.bitmapInfo, privacy: .public) alphaInfo=\(diagnostics.alphaInfo, privacy: .public) sampleUnique=\(diagnostics.uniqueSampleCount, privacy: .public) sampleHash=\(String(diagnostics.sampleHash, radix: 16), privacy: .public)"
        )
        if diagnostics.appearsUniform {
            logger.warning(
                "capture frame appears uniform; preserving frame for diagnosis api=\(diagnostics.api, privacy: .public) sampleHash=\(String(diagnostics.sampleHash, radix: 16), privacy: .public)"
            )
        }
        guard let detached = detachedImage(from: image) else {
            throw ScreenshotCaptureError.screenUnavailable
        }
        return detached
    }

    static func detachedImage(from image: CGImage) -> CGImage? {
        guard image.width > 0, image.height > 0 else { return nil }
        let (bytesPerRow, overflow) = image.width.multipliedReportingOverflow(by: 4)
        guard !overflow else { return nil }
        let (_, byteCountOverflow) = bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !byteCountOverflow else { return nil }
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    static func frameDiagnostics(
        for image: CGImage,
        api: String
    ) -> ScreenshotFrameDiagnostics {
        let sampleWidth = min(max(image.width, 0), 8)
        let sampleHeight = min(max(image.height, 0), 8)
        var sampleBytes = [UInt8](repeating: 0, count: max(sampleWidth * sampleHeight * 4, 1))
        if sampleWidth > 0, sampleHeight > 0,
           let context = CGContext(
               data: &sampleBytes,
               width: sampleWidth,
               height: sampleHeight,
               bitsPerComponent: 8,
               bytesPerRow: sampleWidth * 4,
               space: CGColorSpaceCreateDeviceRGB(),
               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
           ) {
            context.interpolationQuality = .none
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
            )
        }

        var hash: UInt64 = 1_469_598_103_934_665_603
        var colors = Set<UInt32>()
        for offset in stride(from: 0, to: sampleBytes.count, by: 4) {
            guard offset + 3 < sampleBytes.count else { break }
            let red = UInt32(sampleBytes[offset])
            let green = UInt32(sampleBytes[offset + 1])
            let blue = UInt32(sampleBytes[offset + 2])
            let alpha = UInt32(sampleBytes[offset + 3])
            colors.insert((red << 24) | (green << 16) | (blue << 8) | alpha)
            for byte in sampleBytes[offset...offset + 3] {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }

        return ScreenshotFrameDiagnostics(
            api: api,
            width: image.width,
            height: image.height,
            bytesPerRow: image.bytesPerRow,
            colorSpaceName: image.colorSpace?.name as String?,
            bitmapInfo: image.bitmapInfo.rawValue,
            alphaInfo: image.alphaInfo.rawValue,
            sampleHash: hash,
            uniqueSampleCount: colors.count
        )
    }

    static func image(from cgImage: CGImage, cropInScreenPoints rect: CGRect, screenSize: CGSize) -> NSImage? {
        let scaleX = CGFloat(cgImage.width) / max(screenSize.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(screenSize.height, 1)
        let normalized = rect.standardized.intersection(CGRect(origin: .zero, size: screenSize))
        guard normalized.width >= 2, normalized.height >= 2 else { return nil }
        let cropRect = CGRect(
            x: normalized.minX * scaleX,
            y: normalized.minY * scaleY,
            width: normalized.width * scaleX,
            height: normalized.height * scaleY
        ).integral.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return NSImage(
            cgImage: cropped,
            size: CGSize(width: normalized.width, height: normalized.height)
        )
    }

    static func pixelColor(
        at point: CGPoint,
        in cgImage: CGImage,
        screenSize: CGSize
    ) -> ScreenshotRGBA? {
        ScreenshotPixelSampler(cgImage: cgImage)?.color(at: point, screenSize: screenSize)
    }
}

// Create the buffer only once when entering screenshot mode to avoid redrawing the entire screen during repeated hover color sampling.
final class ScreenshotPixelSampler {
    private let pixels: [UInt8]
    private let width: Int
    private let height: Int
    private let bytesPerRow: Int

    init?(cgImage: CGImage) {
        let sourceWidth = cgImage.width
        let sourceHeight = cgImage.height
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        let (sourceBytesPerRow, rowOverflow) = sourceWidth.multipliedReportingOverflow(by: 4)
        guard !rowOverflow else { return nil }
        let (byteCount, byteCountOverflow) = sourceBytesPerRow.multipliedReportingOverflow(by: sourceHeight)
        guard !byteCountOverflow else { return nil }

        width = sourceWidth
        height = sourceHeight
        bytesPerRow = sourceBytesPerRow

        var buffer = [UInt8](repeating: 0, count: byteCount)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixels = buffer
    }

    func color(at point: CGPoint, screenSize: CGSize) -> ScreenshotRGBA? {
        guard screenSize.width > 0, screenSize.height > 0,
              point.x >= 0, point.y >= 0,
              point.x < screenSize.width, point.y < screenSize.height,
              width > 0, height > 0
        else { return nil }

        let x = min(
            max(Int((point.x / screenSize.width * CGFloat(width)).rounded(.down)), 0),
            width - 1
        )
        let y = min(
            max(Int((point.y / screenSize.height * CGFloat(height)).rounded(.down)), 0),
            height - 1
        )
        let (rowOffset, rowOverflow) = y.multipliedReportingOverflow(by: bytesPerRow)
        let (columnOffset, columnOverflow) = x.multipliedReportingOverflow(by: 4)
        let (offset, offsetOverflow) = rowOffset.addingReportingOverflow(columnOffset)
        let (endOffset, endOverflow) = offset.addingReportingOverflow(3)
        guard !rowOverflow, !columnOverflow, !offsetOverflow, !endOverflow,
              offset >= 0, endOffset < pixels.count else { return nil }
        return ScreenshotRGBA(
            red: CGFloat(pixels[offset]) / 255,
            green: CGFloat(pixels[offset + 1]) / 255,
            blue: CGFloat(pixels[offset + 2]) / 255,
            alpha: CGFloat(pixels[offset + 3]) / 255
        )
    }
}

extension ScreenshotRGBA {
    var hex: String {
        let components = [red, green, blue].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", components[0], components[1], components[2])
    }

    var rgbText: String {
        let components = [red, green, blue].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return "R " + String(components[0])
            + "  G " + String(components[1])
            + "  B " + String(components[2])
    }
}

struct ScreenshotCaptureResult {
    let image: NSImage
    let selectionRect: CGRect
    let screenImage: NSImage
    let screenCGImage: CGImage
    let screen: NSScreen
}

struct ScreenshotBackingImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        imageView.imageScaling = .scaleAxesIndependently
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        imageView.image = image
    }
}

@MainActor
final class ScreenshotSelectionHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum ScreenshotSelectionHandle: CaseIterable, Hashable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

enum ScreenshotSelectionGeometry {
    static let minimumLength: CGFloat = 24

    static func resized(
        _ rect: CGRect,
        using handle: ScreenshotSelectionHandle,
        translation: CGSize,
        within bounds: CGRect
    ) -> CGRect {
        let source = rect.standardized.intersection(bounds)
        var minX = source.minX
        var maxX = source.maxX
        var minY = source.minY
        var maxY = source.maxY

        switch handle {
        case .topLeft, .left, .bottomLeft:
            minX = min(max(source.minX + translation.width, bounds.minX), source.maxX - minimumLength)
        case .topRight, .right, .bottomRight:
            maxX = max(min(source.maxX + translation.width, bounds.maxX), source.minX + minimumLength)
        case .top, .bottom:
            break
        }

        switch handle {
        case .topLeft, .top, .topRight:
            minY = min(max(source.minY + translation.height, bounds.minY), source.maxY - minimumLength)
        case .bottomLeft, .bottom, .bottomRight:
            maxY = max(min(source.maxY + translation.height, bounds.maxY), source.minY + minimumLength)
        case .left, .right:
            break
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func position(of handle: ScreenshotSelectionHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// Spacing between the size badge and the selection border or resize handles.
    static let badgeInset: CGFloat = 10

    /// Estimated badge size used to determine whether it fits outside the selection.
    static let badgeEstimatedSize = CGSize(width: 104, height: 27)

    /// Places the badge outside the selection's lower-right edge, falling back inside when needed.
    static func badgePosition(for selection: CGRect, in bounds: CGSize) -> CGPoint {
        let badge = badgeEstimatedSize
        let gap: CGFloat = 8
        let rect = selection.standardized

        // Prefer the outside right edge, falling back inside when it does not fit.
        let outsideCenterX = rect.maxX + gap + badge.width / 2
        let fitsOutside = outsideCenterX + badge.width / 2 <= bounds.width
        let centerX: CGFloat
        if fitsOutside {
            centerX = outsideCenterX
        } else {
            centerX = max(badge.width / 2, rect.maxX - gap - badge.width / 2)
        }

        // Align the badge bottom with the selection and clamp it to the screen bounds.
        let preferredCenterY = rect.maxY - badge.height / 2
        let centerY = min(
            max(badge.height / 2, preferredCenterY),
            bounds.height - badge.height / 2
        )

        return CGPoint(x: centerX, y: centerY)
    }
}

enum ScreenshotSnapTargetGeometry {
    static func localRect(_ rect: CGRect, in displayBounds: CGRect) -> CGRect? {
        let localBounds = CGRect(origin: .zero, size: displayBounds.size)
        let local = rect.standardized
            .offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)
            .intersection(localBounds)
        return local.width >= 2 && local.height >= 2 ? local : nil
    }

    static func globalPoint(_ point: CGPoint, in displayBounds: CGRect) -> CGPoint {
        CGPoint(x: displayBounds.minX + point.x, y: displayBounds.minY + point.y)
    }

    static func target(
        at point: CGPoint,
        component: CGRect? = nil,
        in rects: [CGRect]
    ) -> CGRect? {
        if let component, component.contains(point) { return component }
        return rects
            .filter { $0.contains(point) }
            .min { lhs, rhs in
                let lhsArea = max(0, lhs.width) * max(0, lhs.height)
                let rhsArea = max(0, rhs.width) * max(0, rhs.height)
                return lhsArea < rhsArea
            }
    }
}

struct ScreenshotSnapTargetProcessTracker {
    private(set) var lastExternalProcess: pid_t?

    mutating func target(
        frontmost: pid_t?,
        currentProcess: pid_t
    ) -> pid_t? {
        guard let frontmost else { return lastExternalProcess }
        guard frontmost != currentProcess else { return lastExternalProcess }
        lastExternalProcess = frontmost
        return frontmost
    }
}

struct ScreenshotWindowCandidate: Equatable {
    let rect: CGRect
    let layer: Int
    let alpha: Double
    let ownerProcessIdentifier: pid_t?
}

enum ScreenshotSnapTargetProvider {
    static func windowRects(on screen: NSScreen) -> [CGRect] {
        windowRects(on: screen, excludingProcessIdentifier: nil)
    }

    static func windowRects(
        on screen: NSScreen,
        excludingProcessIdentifier processIdentifier: pid_t?
    ) -> [CGRect] {
        guard let displayID = ScreenshotCaptureService.displayID(for: screen),
              let windows = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]]
        else { return [] }

        let displayBounds = CGDisplayBounds(displayID)
        let candidates = windows.compactMap { window -> ScreenshotWindowCandidate? in
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            return ScreenshotWindowCandidate(
                rect: rect,
                layer: (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                alpha: (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                ownerProcessIdentifier: (window[kCGWindowOwnerPID as String] as? NSNumber).map { $0.int32Value }
            )
        }
        let localBounds = CGRect(origin: .zero, size: displayBounds.size)
        return filteredWindowRects(
            candidates,
            excludingProcessIdentifier: processIdentifier,
            within: displayBounds
        )
        .compactMap { ScreenshotSnapTargetGeometry.localRect($0, in: displayBounds) }
        .filter { !isFullDisplayWindow($0, within: localBounds) }
    }

    static func filteredWindowRects(
        _ candidates: [ScreenshotWindowCandidate],
        excludingProcessIdentifier processIdentifier: pid_t?,
        within displayBounds: CGRect? = nil
    ) -> [CGRect] {
        candidates.compactMap { candidate in
            guard candidate.layer == 0,
                  candidate.alpha > 0.01,
                  candidate.rect.width >= 40,
                  candidate.rect.height >= 30,
                  candidate.ownerProcessIdentifier != processIdentifier
            else { return nil }
            if let displayBounds,
               isFullDisplayWindow(candidate.rect, within: displayBounds) {
                return nil
            }
            return candidate.rect
        }
    }

    private static func isFullDisplayWindow(_ rect: CGRect, within displayBounds: CGRect) -> Bool {
        let local = rect.standardized.intersection(displayBounds)
        guard local.width > 0, local.height > 0 else { return false }
        return local.width >= displayBounds.width * 0.98
            && local.height >= displayBounds.height * 0.98
    }

    static func accessibilityRect(
        at localPoint: CGPoint,
        processIdentifier: pid_t,
        displayBounds: CGRect
    ) -> CGRect? {
        guard AXIsProcessTrusted(), processIdentifier > 0 else { return nil }
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.05)
        let point = ScreenshotSnapTargetGeometry.globalPoint(localPoint, in: displayBounds)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            application,
            Float(point.x),
            Float(point.y),
            &element
        ) == .success,
        let element,
        let frame = frame(of: element)
        else { return nil }
        guard let local = ScreenshotSnapTargetGeometry.localRect(frame, in: displayBounds) else {
            return nil
        }
        let displaySize = displayBounds.size
        guard local.width < displaySize.width * 0.98
            || local.height < displaySize.height * 0.98
        else {
            return nil
        }
        return local
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionRef
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeRef
        ) == .success,
        let positionRef,
        let sizeRef,
        CFGetTypeID(positionRef) == AXValueGetTypeID(),
        CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        let positionValue = unsafeDowncast(positionRef, to: AXValue.self)
        let sizeValue = unsafeDowncast(sizeRef, to: AXValue.self)
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}

@MainActor
final class ScreenshotSelectionPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onCopyColor: (() -> Void)?
    var currentColor: ScreenshotRGBA?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isCopyColorEvent(event) {
            onCopyColor?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if Self.isCopyColorEvent(event) {
            onCopyColor?()
            return
        }
        super.keyDown(with: event)
    }

    private static func isCopyColorEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        return modifiers.isEmpty && event.charactersIgnoringModifiers?.lowercased() == "c"
    }
}

@MainActor
final class ScreenshotColorCopyFeedback: ObservableObject {
    @Published private(set) var copiedColor: ScreenshotRGBA?
    private var dismissWorkItem: DispatchWorkItem?

    func show(for color: ScreenshotRGBA) {
        dismissWorkItem?.cancel()
        copiedColor = color
        let workItem = DispatchWorkItem { [weak self] in
            self?.copiedColor = nil
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

}

@MainActor
final class ScreenshotSelectionController: NSObject, NSWindowDelegate {
    typealias CaptureScreen = @MainActor (NSScreen) async throws -> (image: NSImage, cgImage: CGImage)
    typealias PresentPanels = @MainActor ([ScreenshotSelectionPanel]) -> Void
    typealias WillPresentPanels = @MainActor () async -> Void
    typealias SnapTargets = (NSScreen) -> [CGRect]

    private var panels: [ScreenshotSelectionPanel] = []
    private var didFinish = false
    private var didRequestPermission = false
    private var isPreparingPanels = false
    /// Asynchronous capture allows overlapping starts; use a session ID to discard stale captures.
    private var startSessionID = 0
    private var colorCopyMonitor: Any?
    private let captureScreen: CaptureScreen
    private let presentPanels: PresentPanels
    private let snapTargets: SnapTargets
    private let capturedProcessIdentifier: pid_t?

    var onCaptured: ((ScreenshotCaptureResult) -> Void)?
    var onCancelled: (() -> Void)?
    var onSelectionWillPresent: WillPresentPanels?
    var selectionWindowCount: Int { panels.count }

    init(
        capturedProcessIdentifier: pid_t? = nil,
        captureScreen: @escaping CaptureScreen = ScreenshotCaptureService.capture,
        presentPanels: @escaping PresentPanels = ScreenshotSelectionController.present,
        snapTargets: @escaping SnapTargets = {
            ScreenshotSnapTargetProvider.windowRects(
                on: $0,
                excludingProcessIdentifier: ProcessInfo.processInfo.processIdentifier
            )
        }
    ) {
        self.capturedProcessIdentifier = capturedProcessIdentifier
        self.captureScreen = captureScreen
        self.presentPanels = presentPanels
        self.snapTargets = snapTargets
    }

    func start(on screen: NSScreen) async {
        await start(on: [screen])
    }

    func start(on screens: [NSScreen]) async {
        didFinish = false
        isPreparingPanels = false
        closePanels()
        startSessionID += 1
        let sessionID = startSessionID
        guard !screens.isEmpty else {
            didFinish = true
            onCancelled?()
            return
        }

        var captures: [(screen: NSScreen, image: NSImage, cgImage: CGImage)] = []
        do {
            for screen in screens {
                guard sessionID == startSessionID, !didFinish else { return }
                let capture = try await captureScreen(screen)
                guard sessionID == startSessionID, !didFinish else { return }
                captures.append((screen, capture.image, capture.cgImage))
            }
        } catch {
            guard sessionID == startSessionID, !didFinish else { return }
            if case ScreenshotCaptureError.permissionRequired = error,
               !didRequestPermission {
                didRequestPermission = true
                if CGRequestScreenCaptureAccess() {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard sessionID == startSessionID, !didFinish else { return }
                    await start(on: screens)
                    return
                }
            }
            didFinish = true
            onCancelled?()
            presentCaptureError(error)
            return
        }
        didRequestPermission = false
        // Another capture may have started in the meantime; do not present an overlay for this stale capture.
        guard sessionID == startSessionID, !didFinish else { return }

        isPreparingPanels = true
        if let onSelectionWillPresent {
            await onSelectionWillPresent()
        }
        guard sessionID == startSessionID, !didFinish else {
            if sessionID == startSessionID {
                isPreparingPanels = false
            }
            return
        }
        panels = captures.map { capture in
            let copyFeedback = ScreenshotColorCopyFeedback()
            let displayBounds = ScreenshotCaptureService.displayID(for: capture.screen)
                .map(CGDisplayBounds)
                ?? CGRect(origin: .zero, size: capture.screen.frame.size)
            let panel = ScreenshotSelectionPanel(
                contentRect: ScreenshotWindowGeometry.localContentRect(
                    for: capture.screen.frame,
                    on: capture.screen.frame
                ),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: capture.screen
            )
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.onCancel = { [weak self] in self?.cancel() }
            panel.onCopyColor = { [weak panel] in
                guard let color = panel?.currentColor else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(color.hex, forType: .string)
                copyFeedback.show(for: color)
            }
            panel.contentView = ScreenshotSelectionHostingView(
                rootView: ScreenshotSelectionView(
                    image: capture.image,
                    cgImage: capture.cgImage,
                    onCancel: { [weak self] in self?.cancel() },
                    onSelection: { [weak self] rect in
                        self?.finish(
                            selection: rect,
                            on: capture.screen,
                            screenImage: capture.image,
                            screenCGImage: capture.cgImage
                        )
                    },
                    snapTarget: { point in
                        let component = self.capturedProcessIdentifier.flatMap { processIdentifier in
                            ScreenshotSnapTargetProvider.accessibilityRect(
                                at: point,
                                processIdentifier: processIdentifier,
                                displayBounds: displayBounds
                            )
                        }
                        return ScreenshotSnapTargetGeometry.target(
                            at: point,
                            component: component,
                            in: self.snapTargets(capture.screen)
                        )
                    },
                    onColorChange: { [weak panel] color in
                        panel?.currentColor = color
                    },
                    copyFeedback: copyFeedback
                )
            )
            panel.setFrame(capture.screen.frame, display: true)
            return panel
        }
        isPreparingPanels = false
        presentPanels(panels)
        installColorCopyMonitor()
    }

    func cancel() {
        guard !didFinish, (!panels.isEmpty || isPreparingPanels) else { return }
        didFinish = true
        startSessionID += 1
        isPreparingPanels = false
        closePanels()
        onCancelled?()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingPanel = notification.object as? ScreenshotSelectionPanel,
              panels.contains(where: { $0 === closingPanel }),
              !didFinish
        else { return }
        didFinish = true
        panels.removeAll { $0 === closingPanel }
        closingPanel.onCancel = nil
        closingPanel.delegate = nil
        closePanels()
        onCancelled?()
    }

    private func finish(
        selection rect: CGRect,
        on screen: NSScreen,
        screenImage: NSImage,
        screenCGImage: CGImage
    ) {
        guard !didFinish else { return }
        let screenBounds = CGRect(origin: .zero, size: screen.frame.size)
        let normalized = rect.standardized.intersection(screenBounds)
        guard let image = ScreenshotCaptureService.image(
            from: screenCGImage,
            cropInScreenPoints: normalized,
            screenSize: screen.frame.size
        ) else {
            cancel()
            return
        }
        didFinish = true
        closePanels()
        onCaptured?(ScreenshotCaptureResult(
            image: image,
            selectionRect: normalized,
            screenImage: screenImage,
            screenCGImage: screenCGImage,
            screen: screen
        ))
    }

    private func closePanels() {
        if let colorCopyMonitor {
            NSEvent.removeMonitor(colorCopyMonitor)
            self.colorCopyMonitor = nil
        }
        let panelsToClose = panels
        panels.removeAll()
        for panel in panelsToClose {
            panel.delegate = nil
            panel.onCancel = nil
            panel.onCopyColor = nil
            panel.currentColor = nil
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
    }

    private func installColorCopyMonitor() {
        guard colorCopyMonitor == nil else { return }
        colorCopyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            guard modifiers.isEmpty,
                  event.charactersIgnoringModifiers?.lowercased() == "c"
            else { return event }
            self?.copyColor(at: NSEvent.mouseLocation)
            return nil
        }
    }

    private func copyColor(at location: CGPoint) {
        let panel = panels.first(where: { $0.frame.contains(location) })
            ?? panels.first(where: { $0.isKeyWindow })
        panel?.onCopyColor?()
    }

    private static func present(_ panels: [ScreenshotSelectionPanel]) {
        for (index, panel) in panels.enumerated() {
            if index == 0 {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppLocalization.text("截图失败")
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.addButton(withTitle: AppLocalization.text("好"))
        alert.runModal()
    }
}

struct ScreenshotSelectionView: View {
    let image: NSImage?
    let cgImage: CGImage?
    let onCancel: () -> Void
    let onSelection: (CGRect) -> Void
    var snapTarget: (CGPoint) -> CGRect? = { _ in nil }
    var onColorChange: (ScreenshotRGBA?) -> Void = { _ in }
    @ObservedObject private var copyFeedback: ScreenshotColorCopyFeedback

    private let pixelSampler: ScreenshotPixelSampler?

    @State private var startPoint: CGPoint?
    @State private var selection = CGRect.zero
    @State private var snapSelection: CGRect?
    @State private var hoverColor: ScreenshotRGBA?
    @State private var hoverPoint: CGPoint?
    @State private var lastSnapQueryDate: Date?
    @State private var lastSnapQueryPoint: CGPoint?

    init(
        image: NSImage?,
        cgImage: CGImage?,
        onCancel: @escaping () -> Void,
        onSelection: @escaping (CGRect) -> Void,
        snapTarget: @escaping (CGPoint) -> CGRect? = { _ in nil },
        onColorChange: @escaping (ScreenshotRGBA?) -> Void = { _ in },
        copyFeedback: ScreenshotColorCopyFeedback = ScreenshotColorCopyFeedback()
    ) {
        self.image = image
        self.cgImage = cgImage
        self.onCancel = onCancel
        self.onSelection = onSelection
        self.snapTarget = snapTarget
        self.onColorChange = onColorChange
        self.copyFeedback = copyFeedback
        pixelSampler = cgImage.flatMap { ScreenshotPixelSampler(cgImage: $0) }
    }

    var body: some View {
        GeometryReader { proxy in
            let displayedSelection = startPoint == nil ? snapSelection ?? selection : selection
            ZStack(alignment: .topLeading) {
                Group {
                    if let image {
                        ScreenshotBackingImage(image: image)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    } else {
                        Color.black
                    }

                    Color.black.opacity(0.44)

                    if displayedSelection.width > 1, displayedSelection.height > 1, let image {
                        ScreenshotBackingImage(image: image)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .mask(selectionMask(displayedSelection, in: proxy.size))

                        Rectangle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: displayedSelection.width, height: displayedSelection.height)
                            .position(x: displayedSelection.midX, y: displayedSelection.midY)

                        ScreenshotSelectionSizeBadge(
                            selection: displayedSelection,
                            bounds: proxy.size
                        )
                    }
                }
                .allowsHitTesting(false)

                VStack {
                    HStack(spacing: 10) {
                        Text(AppLocalization.text("拖动选择截图区域"))
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button(action: onCancel) {
                            Label(AppLocalization.text("取消"), systemImage: "xmark")
                        }
                            .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .foregroundStyle(.white)
                    Spacer()
                }
                if let hoverColor, let hoverPoint {
                    hoverColorBadge(
                        hoverColor,
                        isCopied: copyFeedback.copiedColor == hoverColor,
                        near: hoverPoint,
                        in: proxy.size
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(selectionGesture)
            .simultaneousGesture(
                TapGesture(count: 2)
                    .exclusively(before: TapGesture())
                    .onEnded { gesture in
                        switch gesture {
                        case .first:
                            onSelection(CGRect(origin: .zero, size: proxy.size))
                        case .second:
                            if let snapSelection { onSelection(snapSelection) }
                        }
                    }
            )
            .onContinuousHover { phase in
                guard startPoint == nil else { return }
                switch phase {
                case .active(let point):
                    let now = Date()
                    let movedDistance = lastSnapQueryPoint.map {
                        hypot(point.x - $0.x, point.y - $0.y)
                    } ?? .infinity
                    if lastSnapQueryDate == nil
                        || now.timeIntervalSince(lastSnapQueryDate ?? .distantPast) >= 0.05
                        || movedDistance >= 12 {
                        snapSelection = snapTarget(point)
                        lastSnapQueryDate = now
                        lastSnapQueryPoint = point
                    }
                    hoverColor = pixelSampler?.color(at: point, screenSize: proxy.size)
                        ?? cgImage.flatMap {
                            ScreenshotCaptureService.pixelColor(
                                at: point,
                                in: $0,
                                screenSize: proxy.size
                            )
                        }
                    hoverPoint = point
                    onColorChange(hoverColor)
                case .ended:
                    snapSelection = nil
                    hoverColor = nil
                    hoverPoint = nil
                    lastSnapQueryDate = nil
                    lastSnapQueryPoint = nil
                    onColorChange(nil)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func hoverColorBadge(
        _ color: ScreenshotRGBA,
        isCopied: Bool,
        near point: CGPoint,
        in size: CGSize
    ) -> some View {
        let horizontalOffset: CGFloat = point.x < size.width / 2 ? 108 : -108
        let verticalOffset: CGFloat = point.y < 70 ? 34 : -34
        let x = min(max(point.x + horizontalOffset, 108), max(108, size.width - 108))
        let y = min(max(point.y + verticalOffset, 26), max(26, size.height - 26))

        return HStack(spacing: 6) {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
            Text(color.hex)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
            Text(color.rgbText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
            if isCopied {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(AppLocalization.text("已复制"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.68), in: Capsule())
        .position(x: x, y: y)
        .allowsHitTesting(false)
    }

    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let origin = startPoint ?? value.startLocation
                if startPoint == nil {
                    startPoint = origin
                    snapSelection = nil
                }
                selection = CGRect(
                    x: min(origin.x, value.location.x),
                    y: min(origin.y, value.location.y),
                    width: abs(value.location.x - origin.x),
                    height: abs(value.location.y - origin.y)
                )
            }
            .onEnded { _ in
                defer { startPoint = nil }
                guard selection.width > 2, selection.height > 2 else { return }
                onSelection(selection)
            }
    }

    private func selectionMask(_ selection: CGRect, in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            context.fill(Path(selection), with: .color(.white))
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Places the selection size badge outside the right edge, falling back inside when space is limited.
struct ScreenshotSelectionSizeBadge: View {
    let selection: CGRect
    let bounds: CGSize

    var body: some View {
        let pos = ScreenshotSelectionGeometry.badgePosition(for: selection, in: bounds)
        Text("\(Int(selection.width.rounded())) × \(Int(selection.height.rounded()))")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.72), in: Capsule())
            .fixedSize()
            .position(x: pos.x, y: pos.y)
            .allowsHitTesting(false)
    }
}
