import AppKit
import SwiftUI

struct ScreenRecordingTimelineMagnification: NSViewRepresentable {
    @Binding var zoom: Double
    var isEnabled: Bool
    var onBegan: () -> Void

    func makeNSView(context: Context) -> ScreenRecordingTimelineMagnificationView {
        ScreenRecordingTimelineMagnificationView()
    }

    func updateNSView(_ view: ScreenRecordingTimelineMagnificationView, context: Context) {
        view.configure(zoom: zoom, isEnabled: isEnabled, onZoom: { zoom = $0 }, onBegan: onBegan)
    }

    static func dismantleNSView(_ view: ScreenRecordingTimelineMagnificationView, coordinator: ()) {
        view.detach()
    }
}

final class ScreenRecordingTimelineMagnificationView: NSView, NSGestureRecognizerDelegate {
    private struct Anchor {
        let zoom: Double
        let contentX: CGFloat
        let viewportX: CGFloat
        let contentWidth: CGFloat
    }

    private static let contentInset: CGFloat = 8
    private var zoom = 1.0
    private var onZoom: (Double) -> Void = { _ in }
    private var onBegan: () -> Void = {}
    private var anchor: Anchor?
    private var pendingScroll: (anchor: Anchor, zoom: Double)?
    private var applyScheduled = false
    private weak var scrollView: NSScrollView?
    private(set) lazy var magnificationRecognizer: NSMagnificationGestureRecognizer = {
        let recognizer = NSMagnificationGestureRecognizer(target: self, action: #selector(magnifyTimeline(_:)))
        recognizer.delegate = self
        return recognizer
    }()

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(zoom: Double, isEnabled: Bool, onZoom: @escaping (Double) -> Void, onBegan: @escaping () -> Void) {
        self.zoom = zoom
        self.onZoom = onZoom
        self.onBegan = onBegan
        if !isEnabled { anchor = nil; pendingScroll = nil }
        magnificationRecognizer.isEnabled = isEnabled
        attach()
        scheduleScroll()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attach()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { detach() } else { attach() }
    }

    override func layout() {
        super.layout()
        attach()
        scheduleScroll()
    }

    private func attach() {
        let enclosing = enclosingScrollView
        guard scrollView !== enclosing else { return }
        detach()
        scrollView = enclosing
        enclosing?.addGestureRecognizer(magnificationRecognizer)
    }

    func detach() {
        scrollView?.removeGestureRecognizer(magnificationRecognizer)
        scrollView = nil
        anchor = nil
        pendingScroll = nil
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool { true }

    @objc private func magnifyTimeline(_ recognizer: NSMagnificationGestureRecognizer) {
        guard let scrollView else { return }
        magnify(by: recognizer.magnification, phase: recognizer.state,
                location: recognizer.location(in: scrollView.contentView).x)
    }

    func magnify(by magnification: CGFloat, phase: NSGestureRecognizer.State, location: CGFloat) {
        defer { if phase == .ended { anchor = nil } }
        if phase == .cancelled || phase == .failed {
            anchor = nil
            pendingScroll = nil
            return
        }
        guard magnificationRecognizer.isEnabled, magnification.isFinite, location.isFinite,
              let scrollView, let document = scrollView.documentView else { return }
        if phase == .began {
            anchor = Anchor(zoom: zoom, contentX: location - Self.contentInset,
                            viewportX: location - scrollView.contentView.bounds.minX,
                            contentWidth: document.frame.width - 2 * Self.contentInset)
            onBegan()
        }
        guard let anchor, phase == .began || phase == .changed || phase == .ended else { return }
        let proposed = Double(ScreenshotPinnedInteraction.scale(current: anchor.zoom,
            magnification: magnification, range: 1...16))
        zoom = proposed
        pendingScroll = (anchor, proposed)
        onZoom(proposed)
        scheduleScroll()
    }

    private func scheduleScroll() {
        guard pendingScroll != nil, !applyScheduled else { return }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.applyScheduled = false
            self?.applyPendingScroll()
        }
    }

    func applyPendingScroll() {
        guard let pendingScroll, let scrollView, let document = scrollView.documentView else { return }
        let ratio = pendingScroll.zoom / pendingScroll.anchor.zoom
        let expectedWidth = pendingScroll.anchor.contentWidth * ratio + 2 * Self.contentInset
        // SwiftUI may update the binding before its hosting view has resized the document.
        guard abs(document.frame.width - expectedWidth) < 1 else { return }
        let clip = scrollView.contentView
        let proposed = pendingScroll.anchor.contentX * ratio + Self.contentInset - pendingScroll.anchor.viewportX
        let offset = min(max(0, proposed), max(0, document.frame.width - clip.bounds.width))
        self.pendingScroll = nil
        clip.scroll(to: CGPoint(x: offset, y: clip.bounds.minY))
        scrollView.reflectScrolledClipView(clip)
    }
}
