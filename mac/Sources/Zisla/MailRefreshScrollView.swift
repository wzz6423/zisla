import AppKit
import SwiftUI

struct MailRefreshScrollView<Content: View>: View {
    let isEnabled: Bool
    let onRefresh: @MainActor () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                content()
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .background(MailPullToRefresh(isEnabled: isEnabled, onRefresh: onRefresh))
            }
            .scrollIndicators(.visible)
            .thinScrollChrome()
        }
    }
}

private struct MailPullToRefresh: NSViewRepresentable {
    let isEnabled: Bool
    let onRefresh: @MainActor () -> Void

    func makeNSView(context: Context) -> MailPullToRefreshHost {
        MailPullToRefreshHost(isEnabled: isEnabled, onRefresh: onRefresh)
    }

    func updateNSView(_ nsView: MailPullToRefreshHost, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onRefresh = onRefresh
    }
}

@MainActor
final class MailPullToRefreshHost: NSView {
    var isEnabled: Bool
    var onRefresh: @MainActor () -> Void
    private var monitor: Any?
    private var gesture = MailPullToRefreshGesture()

    init(isEnabled: Bool, onRefresh: @escaping @MainActor () -> Void) {
        self.isEnabled = isEnabled
        self.onRefresh = onRefresh
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        gesture = MailPullToRefreshGesture()
    }

    func handle(_ event: NSEvent) {
        guard isEnabled, let window, event.window === window,
              let scrollView = enclosingScrollView,
              scrollView.bounds.contains(scrollView.convert(event.locationInWindow, from: nil)) else { return }
        if gesture.consume(
            deltaY: event.scrollingDeltaY,
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            isAtTop: scrollView.contentView.bounds.minY <= 0
        ) {
            onRefresh()
        }
    }
}

struct MailPullToRefreshGesture {
    private var distance: CGFloat = 0
    private var hasTriggered = false

    mutating func consume(deltaY: CGFloat, phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, isAtTop: Bool) -> Bool {
        if phase == .began { self = Self() }
        if phase == .ended || phase == .cancelled {
            self = Self()
            return false
        }
        guard momentumPhase.isEmpty else { return false }
        guard isAtTop, deltaY > 0 else {
            distance = 0
            return false
        }
        guard !hasTriggered else { return false }
        distance += deltaY
        guard distance >= 60 else { return false }
        if phase.isEmpty {
            distance = 0
        } else {
            hasTriggered = true
        }
        return true
    }
}
