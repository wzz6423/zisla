import AppKit

@objc private protocol TextUndoActionTarget {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}

@MainActor
public enum TextEditingCommands {
    public static func handle(_ event: NSEvent) -> NSEvent? {
        guard let window = event.window,
              window.firstResponder is NSTextView,
              performKeyEquivalent(with: event, in: window)
        else { return event }
        return nil
    }

    public static func performKeyEquivalent(with event: NSEvent, in window: NSWindow) -> Bool {
        guard let action = editingAction(for: event), let responder = window.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            // UndoManager edits text storage without notifying SwiftUI bindings or text delegates.
            switch action {
            case #selector(TextUndoActionTarget.undo(_:)):
                if textView.isEditable, let manager = textView.undoManager, manager.canUndo {
                    manager.undo()
                    textView.didChangeText()
                }
                return true
            case #selector(TextUndoActionTarget.redo(_:)):
                if textView.isEditable, let manager = textView.undoManager, manager.canRedo {
                    manager.redo()
                    textView.didChangeText()
                }
                return true
            default: break
            }
        }
        guard responder.responds(to: action) else { return false }
        return NSApp.sendAction(action, to: responder, from: window)
    }

    private static func editingAction(for event: NSEvent) -> Selector? {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased()

        return switch (key, modifiers) {
        case ("a", .command): #selector(NSResponder.selectAll(_:))
        case ("c", .command): #selector(NSText.copy(_:))
        case ("v", .command): #selector(NSText.paste(_:))
        case ("x", .command): #selector(NSText.cut(_:))
        case ("z", .command): #selector(TextUndoActionTarget.undo(_:))
        case ("z", [.command, .shift]): #selector(TextUndoActionTarget.redo(_:))
        default: nil
        }
    }
}
