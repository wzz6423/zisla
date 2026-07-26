import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct QuickNotesServiceTests {
    @Test
    func displaysBuiltInWelcomeWithoutAddingItToNotes() throws {
        let suiteName = "Zisla.QuickNotesServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = QuickNotesService(welcomeDismissalDefaults: defaults)
        let regular = NotesAppBridge.NoteSummary(
            id: "regular",
            title: "普通备忘录",
            modifiedAt: .now
        )
        let legacyWelcome = NotesAppBridge.NoteSummary(
            id: "legacy-welcome",
            title: QuickNotesService.welcomeNoteTitle,
            modifiedAt: .distantPast
        )

        service.applyFetchedNotes([legacyWelcome, regular])

        let welcome = try #require(service.welcomeNote)
        #expect(service.notes == [regular])
        #expect(service.regularNotes == [regular])
        #expect(service.selectedNote == welcome)
        #expect(service.isBuiltInWelcomeNote(id: welcome.id))
    }

    @Test
    func loadsWelcomeNoteTextFromBundledResource() {
        #expect(QuickNotesService.welcomeNoteText.contains("从现在开始，你可以在记事本中写记事了。"))
        #expect(QuickNotesService.welcomeNoteText.contains("愿你能愉快而轻松地使用这个小工具~"))
    }

    @Test
    func loadsAndDismissesBuiltInWelcomeLocally() async throws {
        let suiteName = "Zisla.QuickNotesServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = QuickNotesService(welcomeDismissalDefaults: defaults)
        let regular = NotesAppBridge.NoteSummary(id: "regular", title: "普通备忘录", modifiedAt: .now)
        service.applyFetchedNotes([regular])
        let welcome = try #require(service.welcomeNote)

        service.select(id: welcome.id)
        let content = try #require(await service.loadNote())
        #expect(content.plainText == QuickNotesService.welcomeNoteText)

        await service.delete(id: welcome.id)

        #expect(service.welcomeNote == nil)
        #expect(service.notes == [regular])
        #expect(service.selectedID == regular.id)

        let reloaded = QuickNotesService(welcomeDismissalDefaults: defaults)
        #expect(reloaded.welcomeNote == nil)
    }

    @Test
    func dropsSelectionWhenSelectedNoteMissingFromRefresh() {
        let suiteName = "Zisla.QuickNotesServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = QuickNotesService(welcomeDismissalDefaults: defaults)
        let kept = NotesAppBridge.NoteSummary(id: "keep", title: "保留", modifiedAt: .now)
        let removed = NotesAppBridge.NoteSummary(id: "gone", title: "已删", modifiedAt: .distantPast)

        service.applyFetchedNotes([removed, kept])
        service.select(id: removed.id)
        #expect(service.selectedID == removed.id)

        service.applyFetchedNotes([kept])
        #expect(service.selectedID == kept.id)
        #expect(service.notes.map(\.id) == [kept.id])
    }

    @Test
    func clearsSelectionWhenAllNotesRemoved() {
        let suiteName = "Zisla.QuickNotesServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = QuickNotesService(welcomeDismissalDefaults: defaults)
        service.applyFetchedNotes([
            NotesAppBridge.NoteSummary(id: "only", title: "唯一", modifiedAt: .now)
        ])
        service.select(id: "only")

        service.applyFetchedNotes([])
        #expect(service.notes.isEmpty)
        #expect(service.selectedID == service.welcomeNote?.id)
    }
}
