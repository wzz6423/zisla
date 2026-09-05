import AppKit
import SwiftUI
import ZislaKit

@MainActor
final class TypingStatsWindowController: NSWindowController, NSWindowDelegate {
    private weak var appModel: KeyboardAppModel?

    init(appModel: KeyboardAppModel) {
        self.appModel = appModel

        let content = TypingStatsView(
            model: appModel.typingStats,
            settings: appModel.settings
        )
        .keyboardUserPreferences(
            appModel.settings,
            windowTitleKey: "Keyboard · 输入统计"
        )
        let hostingController = KeyboardGlassHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = L10n.tr("Keyboard · 输入统计")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        KeyboardWindowChrome.apply(to: window)
        window.setContentSize(NSSize(width: 1_040, height: 760))
        window.contentMinSize = NSSize(width: 820, height: 600)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        appModel?.typingStatsWindowDidClose(self)
    }
}
