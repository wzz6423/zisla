import AppKit
import Testing

@testable import Zisla
import ZislaKit

struct SettingsWindowLevelTests {
    @Test @MainActor
    func usesElevatedLevelOnlyWhileKey() {
        let window = SettingsWindow(
            contentRect: CGRect(x: 0, y: 0, width: 548, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.level = .normal

        window.becomeKey()
        #expect(window.level == WindowPlacement.modalWindowLevel)

        window.resignKey()
        #expect(window.level == .normal)

        window.becomeKey()
        #expect(window.level == WindowPlacement.modalWindowLevel)
    }
}
