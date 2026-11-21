import AppKit
import SwiftUI
import Testing
import WebKit

@testable import Zisla
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct QuickNoteNavigationShortcutTests {
    @Test
    func commandArrowsNavigateWithoutWrappingWhileAnEditorHasFocus() async throws {
        let suiteName = "Zisla.QuickNoteNavigationShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = QuickNotesService(welcomeDismissalDefaults: defaults)
        let welcomeID = try #require(service.welcomeNote).id
        let firstID = "first"
        let lastID = "last"
        service.applyFetchedNotes([
            .init(id: lastID, title: "Last", modifiedAt: Date(timeIntervalSince1970: 1)),
            .init(id: firstID, title: "First", modifiedAt: Date(timeIntervalSince1970: 2))
        ])
        service.select(id: firstID)
        let host = NSHostingView(rootView: QuickNoteListView(service: service) { note, _ in
            Button(note.title) { service.select(id: note.id) }
        })
        let panel = IslandPanel(contentView: host, frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        defer { panel.contentView = nil; panel.close() }
        let editor = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        editor.string = "Fixture note body"
        host.addSubview(editor)
        #expect(panel.makeFirstResponder(editor))
        await layout(host)

        for (key, keyCode, expectedID) in [
            ("\u{F700}", UInt16(126), welcomeID),
            ("\u{F700}", UInt16(126), welcomeID),
            ("\u{F701}", UInt16(125), firstID),
            ("\u{F701}", UInt16(125), lastID),
            ("\u{F701}", UInt16(125), lastID),
            ("\u{F700}", UInt16(126), firstID)
        ] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [.command, .numericPad, .function], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, characters: key,
                charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode))
            #expect(panel.performKeyEquivalent(with: event))
            #expect(service.selectedID == expectedID)
            #expect(editor.string == "Fixture note body")
        }
        let repeated = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0x8).union([.command, .numericPad, .function, .capsLock]), timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "\u{F701}",
            charactersIgnoringModifiers: "\u{F701}", isARepeat: true, keyCode: 125))
        #expect(panel.performKeyEquivalent(with: repeated))
        #expect(service.selectedID == lastID)
        #expect(panel.performKeyEquivalent(with: repeated))
        #expect(service.selectedID == lastID)

        for modifiers: NSEvent.ModifierFlags in [[], .shift, .option, .control,
                                                [.command, .shift], [.command, .option], [.command, .control]] {
            service.select(id: lastID)
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: modifiers.union([.numericPad, .function]), timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, characters: "\u{F700}",
                charactersIgnoringModifiers: "\u{F700}", isARepeat: false, keyCode: 126))
            _ = panel.performKeyEquivalent(with: event)
            #expect(service.selectedID == lastID, "Modifiers \(modifiers.rawValue) must not change the selection")
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webEditor = WKWebView(frame: editor.frame, configuration: configuration)
        host.addSubview(webEditor)
        #expect(panel.makeFirstResponder(webEditor))
        service.select(id: firstID)
        #expect(panel.performKeyEquivalent(with: repeated))
        #expect(service.selectedID == lastID, "WebKit editor focus must not intercept note navigation")
        #expect(panel.makeFirstResponder(editor))
        let otherPanel = IslandPanel(contentView: NSView(), frame: panel.frame)
        defer { otherPanel.close() }
        let otherEvent = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: otherPanel.windowNumber,
            context: nil, characters: "\u{F700}", charactersIgnoringModifiers: "\u{F700}",
            isARepeat: false, keyCode: 126))
        _ = panel.performKeyEquivalent(with: otherEvent)
        #expect(service.selectedID == lastID, "Events from another window must not navigate this list")
        let unknownKey = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12))
        #expect(!panel.performKeyEquivalent(with: unknownKey))
        #expect(service.selectedID == lastID)
        service.selectedID = nil
        await layout(host)
        _ = panel.performKeyEquivalent(with: repeated)
        #expect(service.selectedID == nil)
        #expect(editor.string == "Fixture note body")
        let otherService = QuickNotesService(welcomeDismissalDefaults: defaults)
        otherService.applyFetchedNotes(service.notes)
        otherService.select(id: firstID)
        host.rootView = QuickNoteListView(service: otherService) { note, _ in
            Button(note.title) { otherService.select(id: note.id) }
        }
        await layout(host)
        _ = panel.performKeyEquivalent(with: repeated)
        #expect(otherService.selectedID == lastID, "Replacing the list's service must update its shortcut target")
        #expect(service.selectedID == nil)
        panel.contentView = NSView()
        service.select(id: firstID)
        _ = panel.performKeyEquivalent(with: repeated)
        #expect(service.selectedID == firstID, "Removing the list must also remove its shortcut handlers")
        #expect(!panel.isVisible, "Shortcut routing must not show the fixture window")
    }

    @Test
    func navigationScrollsOffscreenSelectionsIntoViewAndKeepsNumberShortcuts() async throws {
        let suiteName = "Zisla.QuickNoteNavigationShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notes = (0..<16).map { index in
            NotesAppBridge.NoteSummary(id: "note-\(index)", title: "Note \(index)", modifiedAt: Date(timeIntervalSince1970: Double(16 - index)))
        }
        let service = QuickNotesService(welcomeDismissalDefaults: defaults)
        service.applyFetchedNotes(notes)
        let welcomeID = try #require(service.welcomeNote).id
        let host = NSHostingView(rootView: QuickNoteListView(service: service) { note, _ in
            Button(note.title) { service.select(id: note.id) }
                .frame(height: 48)
        })
        let panel = IslandPanel(contentView: host, frame: CGRect(x: 0, y: 0, width: 152, height: 160))
        defer { panel.contentView = nil; panel.close() }
        await layout(host)
        let scrollView = try #require(scrollView(in: host))
        let initialOrigin = scrollView.contentView.bounds.origin.y
        let down = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .numericPad, .function], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "\u{F701}",
            charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125))
        for note in notes {
            #expect(panel.performKeyEquivalent(with: down))
            #expect(service.selectedID == note.id)
            await layout(host)
        }
        let bottomOrigin = scrollView.contentView.bounds.origin.y
        #expect(bottomOrigin > initialOrigin, "Navigating past the viewport must reveal the selected row")
        #expect(panel.performKeyEquivalent(with: down))
        #expect(service.selectedID == notes.last?.id)

        service.select(id: welcomeID)
        await layout(host)
        #expect(scrollView.contentView.bounds.origin.y < bottomOrigin, "Returning to the welcome row must scroll toward the top")
        let number = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19))
        #expect(panel.performKeyEquivalent(with: number))
        #expect(service.selectedID == notes[1].id, "Command-number selection must retain its regular-note numbering")
        #expect(!panel.isVisible)
    }

    private func scrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    private func layout(_ host: NSView) async {
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }
}
