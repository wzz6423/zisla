import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct ContextNoteQuickActionTests {
    @Test(.serialized, arguments: [false, true], [AppLanguage.simplifiedChinese, .english, .arabic])
    func compactRemindersKeepContentAndTimeOnOppositeSidesOfTheNotch(hasNotch: Bool, language: AppLanguage) async throws {
        _ = NSApplication.shared
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        var settings = FeatureSettings.default
        settings.contextNotesEnabled = true
        settings.clipboardAssistantDisplayDuration = .never
        settings.collapsedProgressGlowEnabled = false
        settings.clipboardAssistantLightweightMode = false
        let item = FileShelfItem(id: UUID(), url: URL(fileURLWithPath: "/synthetic-context-note/note"),
                                 addedAt: Date(timeIntervalSince1970: 123_456), bookmarkData: Data(),
                                 text: String(repeating: "Synthetic long note ", count: 25), noteLocation: Self.location)
        #expect(ContextNoteReminderPresenter.present(item, at: .zero, on: controller, settings: settings))
        controller.presentation.physicalNotchWidth = hasNotch ? 185 : 0
        controller.presentation.islandTopHeight = 37
        let host = NSHostingView(rootView: ClipboardAssistantToastView(presentation: controller.presentation, controller: controller)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
            .transaction { $0.disablesAnimations = true })
        host.sizingOptions = []
        let panel = NSPanel(contentRect: CGRect(x: -100_000, y: -100_000, width: 533, height: 37),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        panel.contentView = host
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(panel.frame) })
        panel.orderFrontRegardless()
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        var frames: [String: CGRect] = [:]
        var labels: [String] = []
        func visit(_ object: NSObject) {
            func value(_ key: String) -> Any? {
                object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
            }
            let label = ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"]
                .compactMap { value($0) as? String }.first { !$0.isEmpty }
            if let element = object as? any NSAccessibilityElementProtocol, let label {
                labels.append(label)
                frames[label] = host.convert(panel.convertFromScreen(element.accessibilityFrame()), from: nil)
            }
            for child in value("accessibilityChildren") as? [NSObject] ?? [] { visit(child) }
        }
        visit(host)
        let content = try #require(frames[item.text!])
        let timeLabel = AppLocalization.string("添加时间", locale: language.locale) + " "
            + item.addedAt.formatted(.dateTime.year().month().day().hour().minute().locale(language.locale))
        let time = try #require(frames[timeLabel])
        #expect(content.width > 0 && time.width > 0)
        #expect(host.bounds.contains(time))
        #expect(abs(content.midY - time.midY) <= 1)
        if language.isRightToLeft { #expect(time.maxX < host.bounds.midX) }
        else { #expect(time.minX > host.bounds.midX) }
        if hasNotch {
            let notch = CGRect(x: (host.bounds.width - 185) / 2, y: 0, width: 185, height: 37)
            #expect(!time.intersects(notch))
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            var brightPixels = 0
            for x in Int(notch.minX * scale + 2)..<Int(notch.maxX * scale - 2) {
                for y in Int(6 * scale)..<Int(30 * scale) {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    if max(color.redComponent, color.greenComponent, color.blueComponent) * color.alphaComponent > 0.25 {
                        brightPixels += 1
                    }
                }
            }
            #expect(brightPixels == 0, "Long note text must remain clipped away from the physical notch")
        }
        #expect(labels.filter { $0 == item.text }.count == 1)
        #expect(!labels.contains(AppLocalization.string("查看便签", locale: language.locale)))
        #expect(controller.presentation.detection?.title == item.text)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let reference = NSHostingView(rootView: Image(systemName: "note.text")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: 26, height: 26)
            .frame(width: 26, height: 37)
            .background(.black)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        reference.sizingOptions = []
        let referencePanel = NSPanel(contentRect: CGRect(x: -100_000, y: -100_000, width: 26, height: 37),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        referencePanel.isReleasedWhenClosed = false
        defer { referencePanel.close() }
        referencePanel.contentView = reference
        referencePanel.orderFrontRegardless()
        for _ in 0..<3 {
            reference.layoutSubtreeIfNeeded()
            reference.displayIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let glyph = try #require(reference.bitmapImageRepForCachingDisplay(in: reference.bounds))
        reference.cacheDisplay(in: reference.bounds, to: glyph)
        let iconX = Int((language.isRightToLeft ? host.bounds.width - 40 : 14) * scale)
        var differingPixels = 0
        var referencePixels = 0
        for x in 0..<glyph.pixelsWide {
            for y in 0..<glyph.pixelsHigh {
                let expected = try #require(glyph.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let actual = try #require(bitmap.colorAt(x: iconX + x, y: y)?.usingColorSpace(.deviceRGB))
                let expectedBright = expected.redComponent * expected.alphaComponent > 0.25
                let actualBright = actual.redComponent * actual.alphaComponent > 0.25
                if expectedBright { referencePixels += 1 }
                if expectedBright != actualBright { differingPixels += 1 }
            }
        }
        #expect(referencePixels > 0)
        #expect(Double(differingPixels) / Double(max(1, referencePixels)) < 0.1,
                "Reminder must show the note glyph instead of the generic clipboard text glyph")
        var actions: [ClipboardAssistantAction] = []
        controller.onPerformAction = { actions.append($0) }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type,
                location: CGPoint(x: language.isRightToLeft ? 440 : 100, y: 18.5), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            panel.sendEvent(event)
        }
        #expect(actions == [.showContextNote(item.id)])
        #expect(controller.presentation.detection == nil)
        #expect(!panel.isKeyWindow)
    }

    @Test
    func reminderWidthReservesTheTimestampInsteadOfHiddenActionButtons() {
        let id = UUID()
        let ordinary = ClipboardAssistantDetection(kind: .text, title: "remember",
            actions: [.showContextNote(id), .copyContextNote(id), .deleteContextNote(id)])
        var reminder = ordinary
        reminder.contextNoteAddedAt = Date(timeIntervalSince1970: 123_456)
        let ordinaryWidth = ClipboardAssistantController.trailingControlsWidth(
            for: ordinary, isLightweightMode: false, shortcutHint: nil)
        let reminderWidth = ClipboardAssistantController.trailingControlsWidth(
            for: reminder, isLightweightMode: false, shortcutHint: nil)
        #expect(reminderWidth > 22)
        #expect(reminderWidth < ordinaryWidth)
        #expect(ClipboardAssistantController.trailingControlsWidth(
            for: reminder, isLightweightMode: true, shortcutHint: nil) == reminderWidth)
    }

    @Test
    func remindersPreviewAllLinesWithoutChangingSavedContent() throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        var settings = FeatureSettings.default
        settings.contextNotesEnabled = true
        let text = "first\r\nsecond\nthird"
        let item = FileShelfItem(id: UUID(), url: URL(fileURLWithPath: "/synthetic-context-note/note"),
                                 addedAt: Date(timeIntervalSince1970: 42), bookmarkData: Data(), text: text,
                                 noteLocation: Self.location)
        #expect(ContextNoteReminderPresenter.present(item, at: .zero, on: controller, settings: settings))
        let detection = try #require(controller.presentation.detection)
        #expect(detection.title == "first second third")
        #expect(detection.fullContent == text)
        #expect(detection.contextNoteAddedAt == item.addedAt)
    }

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
        #expect(detection.contextNoteAddedAt == item.addedAt)
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
