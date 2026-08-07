import AppKit
import SwiftUI

/// Narrows only the native scroller behind SwiftUI's `ScrollView`; does not change the system display policy.
extension View {
    func thinScrollChrome() -> some View {
        background(ThinScrollChromeConfigurator())
    }
}

private struct ThinScrollChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ThinScrollChromeHost {
        ThinScrollChromeHost()
    }

    func updateNSView(_ nsView: ThinScrollChromeHost, context: Context) {
        nsView.scheduleApply()
    }
}

@MainActor
final class ThinScrollChromeHost: NSView {
    private weak var configuredScrollView: NSScrollView?
    private var pendingApply = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleApply()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleApply()
    }

    override func layout() {
        super.layout()
        scheduleApply()
    }

    func scheduleApply() {
        guard !pendingApply else { return }
        pendingApply = true
        DispatchQueue.main.async { [weak self] in
            self?.pendingApply = false
            self?.applyIfNeeded()
        }
    }

    func applyIfNeeded() {
        guard let scrollView = nearestScrollView() else { return }
        if configuredScrollView === scrollView,
           isThinScroller(scrollView.verticalScroller),
           isThinScroller(scrollView.horizontalScroller) {
            return
        }
        ThinScrollChrome.apply(to: scrollView)
        configuredScrollView = scrollView
    }

    private func isThinScroller(_ scroller: NSScroller?) -> Bool {
        scroller == nil || scroller is ThinScroller
    }

    private func nearestScrollView() -> NSScrollView? {
        if let scrollView = ancestor(ofType: NSScrollView.self) {
            return scrollView
        }
        // SwiftUI often attaches the background to a sibling of the ScrollView wrapper; walk up then scan downward.
        var node: NSView? = superview
        while let view = node {
            if let found = firstDescendant(ofType: NSScrollView.self, in: view) {
                return found
            }
            node = view.superview
        }
        return nil
    }

    private func ancestor<T: NSView>(ofType type: T.Type) -> T? {
        var current: NSView? = superview
        while let view = current {
            if let match = view as? T { return match }
            current = view.superview
        }
        return nil
    }

    private func firstDescendant<T: NSView>(ofType type: T.Type, in root: NSView) -> T? {
        var queue = ArraySlice(root.subviews)
        while let view = queue.popFirst() {
            if let match = view as? T { return match }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }
}

@MainActor
enum ThinScrollChrome {
    /// Noticeably narrower than the system default width.
    static let width: CGFloat = 3

    static func apply(to scrollView: NSScrollView) {
        scrollView.scrollerKnobStyle = .default

        if scrollView.verticalScroller != nil, !(scrollView.verticalScroller is ThinScroller) {
            let scroller = ThinScroller()
            scroller.controlSize = .mini
            scrollView.verticalScroller = scroller
        }
        if scrollView.horizontalScroller != nil, !(scrollView.horizontalScroller is ThinScroller) {
            let scroller = ThinScroller()
            scroller.controlSize = .mini
            scrollView.horizontalScroller = scroller
        }

        scrollView.verticalScroller?.controlSize = .mini
        scrollView.horizontalScroller?.controlSize = .mini
    }
}

@MainActor
final class ThinScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        ThinScrollChrome.width
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Do not draw the slot background to avoid a wide color band beside the thin bar.
    }
}
