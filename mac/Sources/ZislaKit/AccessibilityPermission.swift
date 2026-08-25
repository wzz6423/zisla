import ApplicationServices

/// Accessibility (AX) trust helpers used by features that post synthetic keyboard events,
/// e.g. the clipboard assistant's hold-left + right-click quick copy gesture.
public enum AccessibilityPermission {
    /// Global constant name for the prompt option key; referenced as a string literal because
    /// `kAXTrustedCheckOptionPrompt` is not exposed as concurrency-safe in the C bridge.
    private static let promptOptionKey = "AXTrustedCheckOptionPrompt"

    /// Whether the app is currently trusted for accessibility.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Checks trust and, when missing, asks the system to show the grant prompt pointing at
    /// System Settings. Returns the current trust state.
    @discardableResult
    public static func promptIfNeeded() -> Bool {
        let options = [promptOptionKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
