import AppKit
import QuartzCore

/// A click-through, full-screen window that holds the display picture while the
/// MacBook lid closes.
///
/// Adapted for Zisla from Mac Duo's Apache-2.0 `DepthOverlay`: the picture is a
/// sheet hinged to the bottom edge of the screen and turned back in world space,
/// so it recedes the way the glass does. Each frame projects the sheet's four
/// corners from a fixed eye onto the screen, and the fragment pass in
/// `DepthRenderer` maps every screen pixel back through the inverse of that
/// projection to sample the picture, blurring and dimming it by height.
@MainActor
final class LidCloseOverlay {

    private var window: LidCloseOverlayWindow?
    /// The window of the previous run while it fades out. AppKit keeps it
    /// alive past the fade, so a new run has to take it down itself.
    private var fadingWindow: LidCloseOverlayWindow?

    /// Built once and kept.
    private var renderer: DepthRenderer?
    private var hasTriedToBuildRenderer = false
    private var buildToken = 0
    private let buildQueue = DispatchQueue(label: "dev.wzz.zisla.lidClosePicture", qos: .userInteractive)

    private var screenSize: CGSize = .zero
    private var startAngle: Double = 0
    private var geometry = DepthGeometry()
    private var gradient = BlurGradient()
    private var tuning = DepthTuning()
    private var hasRevealed = false

    private static let fadeInDuration: TimeInterval = 0.07
    private static let fadeOutDuration: TimeInterval = 0.16

    var hostWindow: NSWindow? { window }
    var isVisible: Bool { window != nil }
    var isPictureReady: Bool { renderer?.isReady ?? false }

    /// Builds the Metal pipeline ahead of the first close, since compiling the
    /// fragment shader at the trigger angle would delay the first frame.
    @discardableResult
    func warmUp() -> Bool {
        if !hasTriedToBuildRenderer {
            hasTriedToBuildRenderer = true
            renderer = DepthRenderer()
        }
        return renderer != nil
    }

    /// Puts the picture up, hinged at the bottom edge of `screen` and starting
    /// from the lid angle the effect begins at.
    func present(image: CGImage, on screen: NSScreen, startAngle: Double) {
        dismiss(animated: false)
        guard warmUp(), let renderer else { return }
        self.startAngle = startAngle
        screenSize = screen.frame.size

        let pixelScale = screen.frame.width > 0
            ? Double(image.width) / Double(screen.frame.width)
            : Double(screen.backingScaleFactor)

        makeWindow(on: screen, pixelScale: pixelScale)
        guard let window else { return }

        buildToken += 1
        let token = buildToken
        let size = screenSize
        // The upload and the pyramid are too slow for the main thread, and the
        // first frame is wanted as soon as the lid moves.
        buildQueue.async { [weak self, weak renderer] in
            guard let renderer else { return }
            let picture = renderer.makePicture(image: image, screenSize: size, pixelScale: CGFloat(pixelScale))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.buildToken == token, self.window === window,
                          let picture else { return }
                    renderer.adopt(picture)
                    self.update(progress: 0, currentAngle: self.startAngle)
                    self.reveal()
                }
            }
        }
    }

    func update(progress: Double, currentAngle: Double) {
        guard let renderer, renderer.isReady else { return }
        renderer.render(
            corners: geometry.corners(
                startAngle: startAngle,
                currentAngle: currentAngle,
                viewingDistanceRatio: tuning.viewingDistance,
                recession: tuning.recession,
                screenSize: screenSize
            ),
            blurStrength: gradient.blurStrength(progress: progress),
            dimStrength: gradient.dimStrength(progress: progress),
            hingeFloor: tuning.blurEvenness,
            dimHingeFloor: gradient.dimHingeFloor,
            dimReach: tuning.dimReach,
            maxBlurRadius: tuning.maxBlurRadius,
            maxDim: tuning.maxDim
        )
    }

    func dismiss(animated: Bool) {
        closeFadingWindow()
        guard let window else { return }
        self.window = nil
        buildToken += 1
        renderer?.release()
        hasRevealed = false

        guard animated else {
            window.orderOut(nil)
            window.close()
            return
        }

        fadingWindow = window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
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

    private func makeWindow(on screen: NSScreen, pixelScale: Double) {
        guard let renderer else { return }
        let view = MetalHostView(layer: renderer.makeLayer(), scale: CGFloat(pixelScale))
        view.frame = NSRect(origin: .zero, size: screenSize)
        view.autoresizingMask = [.width, .height]

        let window = LidCloseOverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
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
        hasRevealed = false
        self.window = window
    }

    /// Fades the window in once, and only once the picture has something to
    /// draw.
    private func reveal() {
        guard let window, !hasRevealed, renderer?.isReady == true else { return }
        hasRevealed = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    /// Takes down a window that is still fading.
    private func closeFadingWindow() {
        guard let fadingWindow else { return }
        self.fadingWindow = nil
        fadingWindow.orderOut(nil)
        fadingWindow.close()
    }
}

/// A view whose backing layer is the one the renderer draws into, so the
/// drawable keeps the size of the screen.
private final class MetalHostView: NSView {
    init(layer metalLayer: CALayer, scale: CGFloat) {
        super.init(frame: .zero)
        metalLayer.contentsScale = scale
        self.layer = metalLayer
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layout() {
        super.layout()
        layer?.frame = bounds
    }
}

private final class LidCloseOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
