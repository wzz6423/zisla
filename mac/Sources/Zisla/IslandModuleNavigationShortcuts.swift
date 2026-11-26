import AppKit
import SwiftUI
import ZislaKit

struct IslandModuleNavigationShortcuts: NSViewRepresentable {
    let onNavigate: (IslandModuleNavigation.Direction) -> Void

    func makeNSView(context: Context) -> KeyView {
        KeyView(onNavigate: onNavigate)
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onNavigate = onNavigate
    }

    final class KeyView: NSView {
        var onNavigate: (IslandModuleNavigation.Direction) -> Void

        init(onNavigate: @escaping (IslandModuleNavigation.Direction) -> Void) {
            self.onNavigate = onNavigate
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if let panel = window as? IslandPanel, panel.pageNavigationShortcutView === self {
                panel.pageNavigationShortcutView = nil
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            (window as? IslandPanel)?.pageNavigationShortcutView = self
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            guard event.window === window, modifiers == .command else { return false }
            switch event.keyCode {
            case 123: onNavigate(.previous)
            case 124: onNavigate(.next)
            default: return false
            }
            return true
        }
    }
}
