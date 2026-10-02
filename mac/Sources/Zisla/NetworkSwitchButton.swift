import SwiftUI
import ZislaKit

struct NetworkSwitchButton<Content: View>: View {
    @StateObject private var controller = SystemWiFiPanelController()
    @StateObject private var region = WiFiPopoverRegionTracker()
    @Environment(\.islandTransientWindowChanged) private var onTransientWindowChanged
    private let content: (@escaping () -> Void) -> Content

    init(@ViewBuilder content: @escaping (@escaping () -> Void) -> Content) {
        self.content = content
    }

    var body: some View {
        content { controller.openPanel() }
            .background(WiFiPopoverRegionProbe(tracker: region, role: .anchor, onChange: onTransientWindowChanged))
            .popover(
                isPresented: Binding(
                    get: { controller.isPresented },
                    set: { if !$0 { controller.closePanel() } }
                ),
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                WiFiNetworkPanelView(controller: controller)
                    .background(WiFiPopoverRegionProbe(tracker: region, role: .popover, onChange: onTransientWindowChanged))
            }
            .onChange(of: controller.isPresented) { _, presented in
                if !presented { region.detachPopover() }
            }
            .onDisappear {
                region.detachPopover()
                controller.closePanel()
            }
    }
}

typealias IslandTransientWindowHandler = @MainActor @Sendable (UUID, NSWindow?, NSView?) -> Void

private struct IslandTransientWindowKey: EnvironmentKey {
    static let defaultValue: IslandTransientWindowHandler = { _, _, _ in }
}

extension EnvironmentValues {
    var islandTransientWindowChanged: IslandTransientWindowHandler {
        get { self[IslandTransientWindowKey.self] }
        set { self[IslandTransientWindowKey.self] = newValue }
    }
}

struct WiFiPopoverRegionProbe: NSViewRepresentable {
    let tracker: WiFiPopoverRegionTracker
    let role: WiFiPopoverRegionTracker.Role
    let onChange: IslandTransientWindowHandler

    func makeNSView(context: Context) -> WiFiPopoverRegionView {
        WiFiPopoverRegionView(tracker: tracker, role: role)
    }

    func updateNSView(_ view: WiFiPopoverRegionView, context: Context) {
        tracker.onChange = onChange
        tracker.attach(view, role: role)
    }

    static func dismantleNSView(_ view: WiFiPopoverRegionView, coordinator: ()) {
        view.tracker.detach(view, role: view.role)
    }
}

@MainActor
final class WiFiPopoverRegionView: NSView {
    let tracker: WiFiPopoverRegionTracker
    let role: WiFiPopoverRegionTracker.Role

    init(tracker: WiFiPopoverRegionTracker, role: WiFiPopoverRegionTracker.Role) {
        self.tracker = tracker
        self.role = role
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tracker.attach(self, role: role)
    }
}

@MainActor
final class WiFiPopoverRegionTracker: NSObject, ObservableObject {
    enum Role { case anchor, popover }
    let id = UUID()
    var onChange: IslandTransientWindowHandler = { _, _, _ in }
    private weak var anchor: NSView?
    private weak var popover: NSView?

    func attach(_ view: NSView, role: Role) {
        guard view.window != nil else {
            detach(view, role: role)
            return
        }
        switch role {
        case .anchor: anchor = view
        case .popover: popover = view
        }
        let window = popover?.window
        NotificationCenter.default.removeObserver(self)
        if let window {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                         NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(windowChanged), name: name, object: window)
            }
        }
        publish()
    }

    func detach(_ view: NSView, role: Role) {
        switch role {
        case .anchor:
            guard anchor === view else { return }
            anchor = nil
        case .popover:
            guard popover === view else { return }
            detachPopover()
            return
        }
        publish()
    }

    func detachPopover() {
        NotificationCenter.default.removeObserver(self)
        popover = nil
        publish()
    }

    @objc private func windowChanged(_ notification: Notification) {
        if notification.name == NSWindow.willCloseNotification {
            detachPopover()
        } else {
            publish()
        }
    }

    private func publish() {
        onChange(id, popover?.window, anchor)
    }
}
