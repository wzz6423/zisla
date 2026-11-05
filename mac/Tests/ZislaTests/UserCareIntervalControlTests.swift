import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

@MainActor
@Suite(.serialized)
struct UserCareIntervalControlTests {
    @Test
    func draftDecomposesTheStoredIntervalAndRejectsZeroInvalidAndOverflowingInputs() {
        var draft = UserCareIntervalDraft(interval: 3_723)
        #expect(draft.hours == "1")
        #expect(draft.minutes == "2")
        #expect(draft.seconds == "3")
        #expect(draft.interval == 3_723)
        draft.hours = "0"
        draft.minutes = "0"
        draft.seconds = "0"
        #expect(draft.interval == nil)
        for invalid in ["", "-1", "+1", "1.5", "1x", "60", String(Int.max) + "0"] {
            draft.seconds = invalid
            #expect(draft.interval == nil, "Invalid seconds must stay an uncommitted draft: \(invalid)")
        }
        draft.seconds = "1"
        draft.hours = "100"
        #expect(draft.interval == nil)
        draft.hours = "99"
        draft.minutes = "60"
        #expect(draft.interval == nil)
        draft.minutes = "59"
        draft.seconds = "59"
        #expect(draft.interval == 359_999)
    }

    @Test
    func localizedAndFullWidthDigitsHaveTheSameSecondPrecision() {
        var draft = UserCareIntervalDraft(interval: 2_700)
        draft.hours = "١"
        draft.minutes = "０２"
        draft.seconds = "٣"
        #expect(draft.interval == 3_723)
    }

    @Test(arguments: [false, true])
    func editingThroughZeroCommitsOnlyOnSaveOrReturn(keyboard: Bool) async throws {
        let fixture = Fixture(language: .english)
        defer { fixture.close() }
        await fixture.layout()
        try await fixture.edit("0", field: 1)
        #expect(fixture.input.interval == 2_700)
        #expect(fixture.input.commits.isEmpty)
        #expect(try !fixture.saveEnabled())
        try await fixture.edit("5", field: 2)
        #expect(fixture.input.interval == 2_700)
        #expect(fixture.input.commits.isEmpty)
        #expect(try fixture.saveEnabled())
        if keyboard {
            try await fixture.submitFromKeyboard(field: 2)
        } else {
            try await fixture.pressSave()
        }
        #expect(fixture.input.interval == 5)
        #expect(fixture.input.commits == [5])
        #expect(try !fixture.saveEnabled())
        try await fixture.submitFromKeyboard(field: 2)
        #expect(fixture.input.commits == [5], "Submitting an unchanged interval must not restart the service")
    }

    @Test(arguments: ["0", "-1", "60", "1x", String(Int.max) + "0"])
    func invalidNativeFieldValuesCannotSaveByButtonOrReturn(value: String) async throws {
        let fixture = Fixture(language: .english)
        defer { fixture.close() }
        await fixture.layout()
        try await fixture.edit("0", field: 1)
        try await fixture.edit(value, field: 2)
        #expect(try !fixture.saveEnabled())
        try await fixture.submitFromKeyboard(field: 2)
        #expect(fixture.input.interval == 2_700)
        #expect(fixture.input.commits.isEmpty)
    }

    @Test
    func replacingTheStoredIntervalRefreshesAllFieldsWithoutSavingTheDraft() async throws {
        let fixture = Fixture(language: .english)
        defer { fixture.close() }
        await fixture.layout()
        try await fixture.edit("0", field: 1)
        try await fixture.edit("5", field: 2)
        fixture.input.interval = 3_723
        await fixture.layout()
        #expect(fixture.fields().map(\.stringValue) == ["1", "2", "3"])
        #expect(try !fixture.saveEnabled())
        #expect(fixture.input.commits.isEmpty)
    }

    @Test(arguments: AppLanguage.allCases)
    func allThreeFieldsAndSaveUseTheRequestedLanguage(language: AppLanguage) async throws {
        let fixture = Fixture(language: language)
        defer { fixture.close() }
        await fixture.layout()
        let objects = fixture.accessibilityObjects()
        for title in ["小时", "分钟", "秒", "保存"] {
            let expected = AppLocalization.string(title, language: language)
            #expect(objects.contains { object in
                object.responds(to: NSSelectorFromString("accessibilityLabel"))
                    && object.value(forKey: "accessibilityLabel") as? String == expected
            }, "Missing \(language.rawValue) control label: \(expected)")
        }
        #expect(fixture.fields().count == 3)
    }

    private final class Input: ObservableObject {
        @Published var interval: TimeInterval = 2_700
        var commits: [TimeInterval] = []
    }

    private struct Host: View {
        @ObservedObject var input: Input
        let language: AppLanguage

        var body: some View {
            UserCareIntervalControl(interval: Binding(
                get: { input.interval },
                set: {
                    input.interval = $0
                    input.commits.append($0)
                }
            ))
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
            .frame(width: 480, height: 56)
        }
    }

    @MainActor
    private final class Fixture {
        let input = Input()
        let window: NSPanel
        let host: NSView
        let releaseAccessibility: @MainActor () -> Void

        init(language: AppLanguage) {
            _ = NSApplication.shared
            releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
            window = NSPanel(
                contentRect: CGRect(x: -100_000, y: -100_000, width: 480, height: 56),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: Host(input: input, language: language))
            hosting.sizingOptions = []
            host = hosting
            window.contentView = host
        }

        func close() {
            window.close()
            releaseAccessibility()
        }

        func layout() async {
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }

        func fields() -> [NSTextField] {
            func descendants(_ view: NSView) -> [NSView] {
                [view] + view.subviews.flatMap(descendants)
            }
            let fields = descendants(host).compactMap { $0 as? NSTextField }.filter(\.isEditable)
            return fields.sorted { $0.convert($0.bounds, to: host).minX < $1.convert($1.bounds, to: host).minX }
        }

        func edit(_ text: String, field index: Int) async throws {
            let field = try #require(fields().dropFirst(index).first)
            _ = window.makeFirstResponder(field)
            field.stringValue = text
            field.currentEditor()?.string = text
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
            await layout()
        }

        func submitFromKeyboard(field index: Int) async throws {
            let field = try #require(fields().dropFirst(index).first)
            _ = window.makeFirstResponder(field)
            let editor = try #require(window.fieldEditor(true, for: field) as? NSTextView)
            editor.insertNewline(nil)
            await layout()
        }

        func saveEnabled() throws -> Bool {
            let button = try saveButton()
            return try #require(button.value(forKey: "accessibilityEnabled") as? Bool)
        }

        func pressSave() async throws {
            let button = try saveButton()
            let action = NSSelectorFromString("accessibilityPerformPress")
            try #require(button.responds(to: action))
            _ = button.perform(action)
            await layout()
        }

        func accessibilityObjects() -> [NSObject] {
            func descendants(_ object: NSObject) -> [NSObject] {
                let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
                    ? object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
                return [object] + children.flatMap(descendants)
            }
            return descendants(host)
        }

        private func saveButton() throws -> NSObject {
            try #require(accessibilityObjects().first { object in
                object.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                    && object.value(forKey: "accessibilityIdentifier") as? String == "user-care-save"
            })
        }
    }
}
