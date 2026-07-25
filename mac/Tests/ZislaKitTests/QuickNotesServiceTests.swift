import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct QuickNotesServiceTests {
    @Test
    func separatesWelcomeNoteFromRegularNotes() {
        let welcome = NotesAppBridge.NoteSummary(
            id: "welcome",
            title: QuickNotesService.welcomeNoteTitle,
            modifiedAt: .distantPast
        )
        let regular = NotesAppBridge.NoteSummary(
            id: "regular",
            title: "普通备忘录",
            modifiedAt: .now
        )
        let sameTitleRegular = NotesAppBridge.NoteSummary(
            id: "same-title-regular",
            title: QuickNotesService.welcomeNoteTitle,
            modifiedAt: .now
        )

        #expect(QuickNotesService.welcomeNote(in: [regular, welcome, sameTitleRegular]) == welcome)
        #expect(
            QuickNotesService.regularNotes(in: [regular, welcome, sameTitleRegular])
                == [regular, sameTitleRegular]
        )
        #expect(QuickNotesService.welcomeNote(in: [regular]) == nil)
    }

    @Test
    func normalizesWelcomeTextWhitespace() {
        let source = "科学证明人脑的记忆力是有限 的。\n \n\n\n记事本，记录点滴生活。\n\n"

        #expect(
            QuickNotesService.normalizedWelcomeText(source)
                == "科学证明人脑的记忆力是有限的。\n\n记事本，记录点滴生活。"
        )
    }

    @Test
    func dropsSelectionWhenSelectedNoteMissingFromRefresh() {
        let service = QuickNotesService()
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
        let service = QuickNotesService()
        service.applyFetchedNotes([
            NotesAppBridge.NoteSummary(id: "only", title: "唯一", modifiedAt: .now)
        ])
        service.select(id: "only")

        service.applyFetchedNotes([])
        #expect(service.notes.isEmpty)
        #expect(service.selectedID == nil)
    }
}
