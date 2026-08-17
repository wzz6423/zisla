import AppKit
import Testing

@testable import Zisla

struct SettingsWindowShortcutTests {
    @Test @MainActor
    func routesStandardEditingShortcutsToTheFocusedInput() throws {
        let window = SettingsWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let probe = EditingActionProbe(frame: window.contentLayoutRect)
        window.contentView = probe
        #expect(window.makeFirstResponder(probe))

        let shortcuts: [(String, NSEvent.ModifierFlags, UInt16, String)] = [
            ("a", .command, 0, "selectAll:"),
            ("c", .command, 8, "copy:"),
            ("v", .command, 9, "paste:"),
            ("x", .command, 7, "cut:"),
            ("z", .command, 6, "undo:"),
            ("z", [.command, .shift], 6, "redo:"),
        ]

        for (key, modifiers, keyCode, expectedAction) in shortcuts {
            probe.receivedAction = nil
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: key,
                charactersIgnoringModifiers: key,
                isARepeat: false,
                keyCode: keyCode
            ))

            #expect(window.performKeyEquivalent(with: event))
            #expect(probe.receivedAction == expectedAction)
        }
    }
}

private final class EditingActionProbe: NSView {
    var receivedAction: String?

    override var acceptsFirstResponder: Bool { true }

    override func selectAll(_ sender: Any?) { receivedAction = "selectAll:" }
    @objc func copy(_ sender: Any?) { receivedAction = "copy:" }
    @objc func paste(_ sender: Any?) { receivedAction = "paste:" }
    @objc func cut(_ sender: Any?) { receivedAction = "cut:" }
    @objc func undo(_ sender: Any?) { receivedAction = "undo:" }
    @objc func redo(_ sender: Any?) { receivedAction = "redo:" }
}
