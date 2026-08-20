import AppKit
import SwiftUI
import Testing

@testable import Zisla

@MainActor
@Suite(.serialized)
struct TeleprompterViewTests {
    @Test
    func editingTextViewPersistsScript() async throws {
        let key = "toolbox.teleprompterScript"
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: key)
        defaults.set("原文", forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let hostingView = NSHostingView(rootView:
            TeleprompterView(onClose: {})
                .frame(width: 760, height: 640)
        )
        let textView = try await waitForTextView(in: hostingView)
        #expect(textView.isEditable)

        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        textView.insertText(" 新增", replacementRange: textView.selectedRange())

        for _ in 0..<20 where defaults.string(forKey: key) != "原文 新增" {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(defaults.string(forKey: key) == "原文 新增")
    }

    private func waitForTextView(in view: NSView) async throws -> NSTextView {
        for _ in 0..<100 {
            view.layoutSubtreeIfNeeded()
            if let textView = findTextView(in: view) {
                return textView
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TestError.textViewNotCreated
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }
        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }
        return nil
    }
}

private enum TestError: Error {
    case textViewNotCreated
}
