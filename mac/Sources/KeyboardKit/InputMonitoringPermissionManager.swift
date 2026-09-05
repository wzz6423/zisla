import AppKit
import Combine
import CoreGraphics
import ZislaKit

@MainActor
final class InputMonitoringPermissionManager: ObservableObject {
    private enum Key {
        /// Renaming this key re-arms the automatic prompt for every existing install.
        static let didRequest = "inputMonitoringDidRequestAutomatically"
    }

    @Published private(set) var isGranted = CGPreflightListenEventAccess()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// TCC records the decision the first time the dialog is shown, after which
    /// `CGRequestListenEventAccess` returns silently — and `CGPreflightListenEventAccess` only ever
    /// answers granted or not, so "never asked" cannot be told apart from "denied". Remember that
    /// the single prompt was spent, or every launch would activate the app for a dialog that can no
    /// longer appear.
    var hasRequestedOnce: Bool {
        defaults.bool(forKey: Key.didRequest)
    }

    @discardableResult
    func refresh() -> Bool {
        let current = CGPreflightListenEventAccess()
        if current != isGranted { isGranted = current }
        return current
    }

    /// Zisla runs as an accessory app and is not frontmost when the keyboard listener starts, so the
    /// prompt goes through the shared authorization host: without an activated host window the one
    /// dialog can surface behind another app and be spent unseen.
    func request() {
        defaults.set(true, forKey: Key.didRequest)
        isGranted = GlobalHotkeyManager.requestInputMonitoringAccess()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }
}
