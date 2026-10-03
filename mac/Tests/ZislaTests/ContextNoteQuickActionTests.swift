import AppKit
import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct ContextNoteQuickActionTests {
    @Test(arguments: [false, true])
    func remindersOfferViewCopyDeleteWithViewAsTheDefault(lightweight: Bool) throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        var settings = FeatureSettings.default
        settings.contextNotesEnabled = true
        settings.clipboardAssistantDisplayDuration = .never
        settings.clipboardAssistantLightweightMode = lightweight
        settings.clipboardAssistantActionOrders[.text] = [.share, .translate, .search]
        let item = FileShelfItem(
            id: UUID(), url: URL(fileURLWithPath: "/synthetic-context-note/note"),
            addedAt: Date(timeIntervalSince1970: 0), bookmarkData: Data(), text: "Remember",
            noteLocation: .desktop(displayID: "fixture", displayName: "Screen")
        )

        #expect(ContextNoteReminderPresenter.present(item, at: .zero, on: controller, settings: settings))
        let detection = try #require(controller.presentation.detection)
        #expect(detection.actions.map(\.identifier) == ["showContextNote", "copyContextNote", "deleteContextNote"])
        #expect(detection.actions.map(ClipboardAssistantToastView.actionLabel) == ["查看便签", "复制", "删除"])
        #expect(detection.action == .showContextNote(item.id))
        #expect(detection.secondaryActions == [.copyContextNote(item.id), .deleteContextNote(item.id)])
        #expect(ClipboardAssistantActionOrder.ordered(detection.actions, for: .text, using: settings.clipboardAssistantActionOrders) == detection.actions)
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        controller.performCurrentAction()
        #expect(performed == [.showContextNote(item.id)])
        #expect(controller.presentation.detection == nil)
    }

    @Test
    func copyingResolvesTheLatestSavedTextWithoutChangingOtherNotesOrAnUnsavedDraft() throws {
        try withStore { shelf, directory in
            let other = try #require(shelf.addContextNote("other", location: Self.location))
            let note = try #require(shelf.addContextNote("old", location: Self.location))
            let editor = ContextNoteShelfEditor()
            editor.open(note)
            let draft = try #require(editor.draft)
            draft.text = "unsaved edit"
            let savedText = "  latest 文本\nsecond line  "
            let updated = try #require(shelf.updateContextNote(id: note.id, text: savedText))
            let copyAction = try #require(AppModel.contextNoteCopyAction(id: note.id, in: shelf))
            #expect(copyAction == .copyText(savedText))
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            if case .copyText(let text) = copyAction {
                #expect(ClipboardHistoryPasteboard.write(.text(text), to: pasteboard))
            }
            #expect(pasteboard.string(forType: .string) == savedText)
            #expect(shelf.items == [other, updated])
            #expect(FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json")).items == shelf.items)
            #expect(editor.draft === draft)
            #expect(draft.text == "unsaved edit")
            #expect(editor.isPresented)
        }
    }

    @Test
    func deletionRemovesOnlyTheTargetAndClosesItsEditorAfterPersistence() throws {
        try withStore { shelf, directory in
            let other = try #require(shelf.addContextNote("same", location: Self.location))
            let target = try #require(shelf.addContextNote("same", location: Self.location))
            #expect(shelf.add(payloads: [.text("ordinary")]) == 1)
            let ordinary = try #require(shelf.items.last)
            let editor = ContextNoteShelfEditor()
            editor.open(other)
            editor.draft?.text = "keep this edit"
            editor.open(target)
            editor.draft?.text = "deleted edit"

            #expect(AppModel.deleteContextNote(id: target.id, from: shelf, editor: editor))
            #expect(shelf.items == [other, ordinary])
            #expect(FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json")).items == shelf.items)
            #expect(!FileManager.default.fileExists(atPath: target.url.deletingLastPathComponent().path))
            #expect(try String(contentsOf: other.url, encoding: .utf8) == "same")
            #expect(try String(contentsOf: ordinary.url, encoding: .utf8) == "ordinary")
            #expect(editor.draft == nil)
            #expect(editor.itemID == nil)
            #expect(!editor.isPresented)
            editor.open(other)
            #expect(editor.draft?.text == "keep this edit")
        }
    }

    @Test(arguments: [false, true])
    func deletingAnotherNotePreservesTheActiveDraftAndReleasesOnlyTheDeletedDraft(newDraft: Bool) throws {
        try withStore { shelf, _ in
            let target = try #require(shelf.addContextNote("target", location: Self.location))
            let other = try #require(shelf.addContextNote("other", location: Self.location))
            let editor = ContextNoteShelfEditor()
            editor.open(target)
            editor.draft?.text = "remove this cached edit"
            weak let removedDraft = editor.draft
            if newDraft { editor.begin(ContextNoteDraft(location: Self.location)) }
            else { editor.open(other) }
            let activeDraft = try #require(editor.draft)
            activeDraft.text = "preserve current edit"

            #expect(AppModel.deleteContextNote(id: target.id, from: shelf, editor: editor))
            #expect(removedDraft == nil)
            #expect(editor.draft === activeDraft)
            #expect(editor.itemID == (newDraft ? nil : other.id))
            #expect(activeDraft.text == "preserve current edit")
            #expect(editor.isPresented)
            #expect(!AppModel.deleteContextNote(id: target.id, from: shelf, editor: editor))
            #expect(editor.draft === activeDraft)
            #expect(shelf.items == [other])
        }
    }

    @Test
    func failedDeletionPreservesSavedDataAndTheEditableDraftAndCanBeRetried() throws {
        try withStore { shelf, directory in
            let target = try #require(shelf.addContextNote("saved", location: Self.location))
            let other = try #require(shelf.addContextNote("other", location: Self.location))
            let editor = ContextNoteShelfEditor()
            editor.open(target)
            let draft = try #require(editor.draft)
            draft.text = "retry this edit"
            let index = directory.appendingPathComponent("shelf.json")
            let backup = directory.appendingPathComponent("saved-shelf.json")
            try FileManager.default.moveItem(at: index, to: backup)
            try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)

            #expect(!AppModel.deleteContextNote(id: target.id, from: shelf, editor: editor))
            #expect(shelf.errorDescription != nil)
            #expect(shelf.items == [target, other])
            #expect(try String(contentsOf: target.url, encoding: .utf8) == "saved")
            #expect(try String(contentsOf: other.url, encoding: .utf8) == "other")
            #expect(editor.draft === draft)
            #expect(draft.text == "retry this edit")
            #expect(editor.itemID == target.id)
            #expect(editor.isPresented)

            try FileManager.default.removeItem(at: index)
            try FileManager.default.moveItem(at: backup, to: index)
            #expect(FileShelfStore(storageURL: index).items == [target, other])
            #expect(AppModel.deleteContextNote(id: target.id, from: shelf, editor: editor))
            #expect(shelf.errorDescription == nil)
            #expect(FileShelfStore(storageURL: index).items == [other])
            #expect(editor.draft == nil)
        }
    }

    @Test
    func missingIDsAndOrdinaryShelfTextOrFilesCannotBeCopiedOrDeletedAsNotes() throws {
        try withStore { shelf, directory in
            let editor = ContextNoteShelfEditor()
            #expect(AppModel.contextNoteCopyAction(id: UUID(), in: shelf) == nil)
            #expect(!AppModel.deleteContextNote(id: UUID(), from: shelf, editor: editor))
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
            let file = directory.appendingPathComponent("keep.txt")
            try Data("original file".utf8).write(to: file)
            #expect(shelf.add(payloads: [.text("ordinary"), .file(file)]) == 2)
            let invalidIDs = shelf.items.map(\.id) + [UUID()]
            let note = try #require(shelf.addContextNote("saved", location: Self.location))
            let original = shelf.items
            let index = directory.appendingPathComponent("shelf.json")
            let originalIndex = try Data(contentsOf: index)
            editor.open(note)
            let draft = try #require(editor.draft)
            draft.text = "keep edit"

            for id in invalidIDs {
                #expect(AppModel.contextNoteCopyAction(id: id, in: shelf) == nil)
                #expect(!AppModel.deleteContextNote(id: id, from: shelf, editor: editor))
                #expect(shelf.items == original)
                #expect(try Data(contentsOf: index) == originalIndex)
                #expect(editor.draft === draft)
                #expect(editor.isPresented)
            }
            #expect(try String(contentsOf: file, encoding: .utf8) == "original file")
            #expect(draft.text == "keep edit")
        }
    }

    @Test
    func aStoredNoteWithoutTextCannotProduceACopyAction() throws {
        try withStore { shelf, directory in
            let note = try #require(shelf.addContextNote("saved", location: Self.location))
            let index = directory.appendingPathComponent("shelf.json")
            var records = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [[String: Any]])
            records[0].removeValue(forKey: "text")
            try JSONSerialization.data(withJSONObject: records).write(to: index)
            let restored = FileShelfStore(storageURL: index)
            #expect(restored.items.first?.noteLocation == Self.location)
            #expect(AppModel.contextNoteCopyAction(id: note.id, in: restored) == nil)
            #expect(try String(contentsOf: note.url, encoding: .utf8) == "saved")
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func noteActionLabelsUseTheExistingTranslationsInEveryLanguage(language: AppLanguage) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let table = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")), format: nil
        ) as? [String: String])
        let translations = [
            "zh-Hans": ["查看便签", "复制", "删除"], "zh-Hant": ["檢視便箋", "拷貝", "刪除"],
            "en": ["View note", "Copy", "Delete"], "ja": ["メモを表示", "コピー", "削除"],
            "ko": ["메모 보기", "복사", "삭제"], "fr": ["Voir la note", "Copier", "Supprimer"],
            "de": ["Notiz ansehen", "Kopieren", "Löschen"], "es": ["Ver nota", "Copiar", "Eliminar"],
            "pt-BR": ["Ver nota", "Copiar", "Excluir"], "it": ["Visualizza nota", "Copia", "Elimina"],
            "nl": ["Notitie bekijken", "Kopieer", "Verwijder"], "ru": ["Посмотреть заметку", "Копировать", "Удалить"],
            "ar": ["عرض الملاحظة", "نسخ", "حذف"], "th": ["ดูบันทึก", "คัดลอก", "ลบ"],
            "id": ["Lihat catatan", "Salin", "Hapus"], "vi": ["Xem ghi chú", "Sao chép", "Xóa"],
            "tr": ["Notu görüntüle", "Kopyala", "Sil"],
        ]
        #expect(Set(translations.keys) == Set(AppLanguage.allCases.map(\.rawValue)))
        let expected = try #require(translations[language.rawValue])
        let id = UUID()
        let actions: [ClipboardAssistantAction] = [.showContextNote(id), .copyContextNote(id), .deleteContextNote(id)]
        for (action, translation) in zip(actions, expected) {
            let key = ClipboardAssistantToastView.actionLabel(action)
            #expect(table[key] == translation)
            #expect(AppLocalization.string(key, language: language) == translation)
        }
    }

    private func withStore(_ body: (FileShelfStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("context-note-quick-actions-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json")), directory)
    }

    private static let location = ContextNoteLocation.window(bundleIdentifier: "test.editor", applicationName: "Editor", title: "Document")
}
