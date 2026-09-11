import AppKit
import CoreImage
import QuartzCore

/// A click-through, full-screen window that holds the display image while the
/// MacBook lid closes. The picture pivots away from its bottom edge, matching
/// the physical hinge direction, then progressively blurs and darkens.
@MainActor
final class LidCloseOverlay {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var window: LidCloseOverlayWindow?
    private var imageView: NSImageView?
    private var dimView: NSView?
    private var sourceImage: CGImage?
    private var sourceSize: CGSize = .zero
    private var lastBlurProgress: CGFloat = -1
    private var fadingWindow: NSWindow?

    var hostWindow: NSWindow? { window }
    var isVisible: Bool { window != nil }

    func present(image: CGImage, on screen: NSScreen) {
        dismiss(animated: false)

        let rootView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.black.cgColor

        let imageView = NSImageView(frame: rootView.bounds)
        imageView.image = NSImage(cgImage: image, size: screen.frame.size)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        imageView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0)
        imageView.layer?.position = CGPoint(x: rootView.bounds.midX, y: 0)
        rootView.addSubview(imageView)

        let dimView = NSView(frame: rootView.bounds)
        dimView.autoresizingMask = [.width, .height]
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.cgColor
        dimView.layer?.opacity = 0
        rootView.addSubview(dimView)

        let window = LidCloseOverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = rootView
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        window.setFrame(screen.frame, display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()

        self.window = window
        self.imageView = imageView
        self.dimView = dimView
        sourceImage = image
        sourceSize = screen.frame.size
        lastBlurProgress = -1

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.06
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func update(progress: CGFloat, lidTravelDegrees: CGFloat) {
        guard let imageLayer = imageView?.layer else { return }
        let clampedProgress = min(max(progress, 0), 1)
        let rotation = min(lidTravelDegrees * 0.72, 58) * .pi / 180

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var transform = CATransform3DIdentity
        transform.m34 = -1 / 1_150
        transform = CATransform3DTranslate(transform, 0, -12 * clampedProgress, 0)
        transform = CATransform3DRotate(transform, rotation, 1, 0, 0)
        transform = CATransform3DScale(
            transform,
            1 - 0.018 * clampedProgress,
            1 - 0.018 * clampedProgress,
            1
        )
        imageLayer.transform = transform
        dimView?.layer?.opacity = Float(0.16 + 0.72 * clampedProgress)
        CATransaction.commit()

        updateBlurIfNeeded(progress: clampedProgress)
    }

    func dismiss(animated: Bool) {
        if !animated, let fadingWindow {
            self.fadingWindow = nil
            fadingWindow.orderOut(nil)
            fadingWindow.close()
        }
        guard let window else { return }
        self.window = nil
        imageView = nil
        dimView = nil
        sourceImage = nil
        lastBlurProgress = -1

        guard animated else {
            window.orderOut(nil)
            window.close()
            return
        }

        fadingWindow?.orderOut(nil)
        fadingWindow?.close()
        fadingWindow = window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                window.orderOut(nil)
                window.close()
                if self?.fadingWindow === window {
                    self?.fadingWindow = nil
                }
            }
        }
    }

    private func updateBlurIfNeeded(progress: CGFloat) {
        guard let sourceImage, let imageView else { return }
        guard abs(progress - lastBlurProgress) >= 0.075 || (progress == 0 && lastBlurProgress != 0) else {
            return
        }
        lastBlurProgress = progress

        guard progress > 0.025 else {
            imageView.image = NSImage(cgImage: sourceImage, size: sourceSize)
            return
        }

        let radius = max(1, progress * 28)
        let source = CIImage(cgImage: sourceImage)
        let blurred = source
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: source.extent)
        guard let output = ciContext.createCGImage(blurred, from: source.extent) else { return }
        imageView.image = NSImage(cgImage: output, size: sourceSize)
    }
}

private final class LidCloseOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
