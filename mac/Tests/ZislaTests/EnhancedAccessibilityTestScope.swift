import AppKit

@MainActor
enum EnhancedAccessibilityTestScope {
    private static let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    // Async rendering tests can overlap while sharing this process-wide AX state.
    private static var activeScopes = 0
    private static var previousValue: Any?

    static func acquire() -> @MainActor () -> Void {
        _ = NSApplication.shared
        if activeScopes == 0 {
            previousValue = NSApp.accessibilityAttributeValue(attribute)
            NSApp.accessibilitySetValue(true, forAttribute: attribute)
        }
        activeScopes += 1
        return {
            activeScopes -= 1
            if activeScopes == 0 {
                NSApp.accessibilitySetValue(previousValue, forAttribute: attribute)
                previousValue = nil
            }
        }
    }
}
