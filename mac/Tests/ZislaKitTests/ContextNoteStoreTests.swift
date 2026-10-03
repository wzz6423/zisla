import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

@MainActor
struct ContextNoteStoreTests {
    private let location = ContextNoteLocation.window(bundleIdentifier: "test.editor", applicationName: "Editor", title: "Document")

    private func withStore(_ body: (FileShelfStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("context-note-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json")), directory)
    }

    @Test
    func savesOriginalContentTimeAndLocationAcrossReload() throws {
        try withStore { store, directory in
            let date = Date(timeIntervalSince1970: 123456)
            let text = "  Remember this 文本\nnext line "
            let item = try #require(store.addContextNote(text, location: location, addedAt: date))
            #expect(try String(contentsOf: item.url, encoding: .utf8) == text)
            #expect(item.isManaged)
            let restored = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
            #expect(restored.items == store.items)
            #expect(restored.items.first?.noteLocation == location)
            #expect(restored.items.first?.addedAt == date)
        }
    }

    @Test
    func identicalNotesAndNormalShelfTextRemainIndependent() throws {
        try withStore { store, _ in
            #expect(store.addContextNote("same", location: location) != nil)
            #expect(store.addContextNote("same", location: location) != nil)
            #expect(store.addContextNote("same", location: .desktop(displayID: "screen", displayName: "Display")) != nil)
            #expect(store.add(payloads: [.text("same")]) == 1)
            #expect(store.add(payloads: [.text("same")]) == 0)
            #expect(store.items.count == 4)
            #expect(Set(store.items.map(\.id)).count == 4)
            #expect(store.items.filter { $0.noteLocation != nil }.count == 3)
        }
    }

    @Test(arguments: ["", " \t\r\n"])
    func emptyNotesDoNotCreateFiles(_ text: String) throws {
        try withStore { store, directory in
            #expect(store.addContextNote(text, location: location) == nil)
            #expect(store.items.isEmpty)
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(contents.isEmpty)
        }
    }

    @Test
    func failedIndexWriteRollsBackOnlyTheNewManagedFile() throws {
        try withStore { store, directory in
            #expect(store.add(payloads: [.text("existing")]) == 1)
            let before = store.items
            let index = directory.appendingPathComponent("shelf.json")
            try FileManager.default.removeItem(at: index)
            try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
            #expect(store.addContextNote("unsaved", location: location) == nil)
            #expect(store.items == before)
            #expect(store.errorDescription != nil)
            let managedFiles = try FileManager.default.contentsOfDirectory(atPath: store.managedDirectory.path)
            #expect(managedFiles.count == 1)
            #expect(try String(contentsOf: before[0].url, encoding: .utf8) == "existing")
        }
    }

    @Test
    func managedDirectoryFailureLeavesTheIndexUnchanged() throws {
        try withStore { store, directory in
            try Data("obstruction".utf8).write(to: store.managedDirectory)
            #expect(store.addContextNote("unsaved", location: location) == nil)
            #expect(store.items.isEmpty)
            #expect(store.errorDescription != nil)
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("shelf.json").path))
        }
    }

    @Test
    func removalAndClearDeleteOwnedFilesAndPersist() throws {
        try withStore { store, directory in
            let first = try #require(store.addContextNote("first", location: location))
            let second = try #require(store.addContextNote("second", location: location))
            store.remove(id: first.id)
            #expect(!FileManager.default.fileExists(atPath: first.url.path))
            #expect(store.items.map(\.id) == [second.id])
            store.removeAll()
            #expect(!FileManager.default.fileExists(atPath: second.url.path))
            #expect(FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json")).items.isEmpty)
        }
    }

    @Test
    func legacyShelfJSONWithoutNoteMetadataStillLoads() throws {
        try withStore { store, directory in
            #expect(store.add(payloads: [.text("legacy")]) == 1)
            let index = directory.appendingPathComponent("shelf.json")
            var records = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [[String: Any]])
            records[0].removeValue(forKey: "noteLocation")
            try JSONSerialization.data(withJSONObject: records).write(to: index)
            let restored = FileShelfStore(storageURL: index)
            #expect(restored.items == store.items)
            #expect(restored.items.first?.noteLocation == nil)
        }
    }

    @Test
    func editingUpdatesOnlyTheTextAndCommitsTheNewFileWithItsIndex() throws {
        try withStore { store, directory in
            let original = try #require(store.addContextNote("original", location: location, addedAt: Date(timeIntervalSince1970: 42)))
            let edited = try #require(store.updateContextNote(id: original.id, text: "edited\n正文"))
            #expect(edited.id == original.id)
            #expect(edited.noteLocation == original.noteLocation)
            #expect(edited.addedAt == original.addedAt)
            #expect(edited.text == "edited\n正文")
            #expect(try String(contentsOf: edited.url, encoding: .utf8) == edited.text)
            #expect(!FileManager.default.fileExists(atPath: original.url.path))
            #expect(FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json")).items == [edited])
            #expect(try FileManager.default.contentsOfDirectory(atPath: edited.url.deletingLastPathComponent().path).count == 1)
        }
    }

    @Test
    func failedEditPreservesSavedContentAndRemovesItsReplacementFile() throws {
        try withStore { store, directory in
            let original = try #require(store.addContextNote("original", location: location))
            let index = directory.appendingPathComponent("shelf.json")
            try FileManager.default.removeItem(at: index)
            try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
            #expect(store.updateContextNote(id: original.id, text: "edited") == nil)
            #expect(store.errorDescription != nil)
            #expect(store.items == [original])
            #expect(try String(contentsOf: original.url, encoding: .utf8) == "original")
            #expect(try FileManager.default.contentsOfDirectory(atPath: original.url.deletingLastPathComponent().path).count == 1)
            try FileManager.default.removeItem(at: index)
            #expect(store.updateContextNote(id: original.id, text: "retry")?.text == "retry")
        }
    }

    @Test
    func blankMissingOrOrdinaryItemsCannotBeEditedAsNotes() throws {
        try withStore { store, _ in
            #expect(store.add(payloads: [.text("ordinary")]) == 1)
            let note = try #require(store.addContextNote("original", location: location))
            let before = store.items
            #expect(store.updateContextNote(id: note.id, text: " \n ") == nil)
            #expect(store.updateContextNote(id: before[0].id, text: "edited") == nil)
            #expect(store.updateContextNote(id: UUID(), text: "edited") == nil)
            #expect(store.items == before)
        }
    }

    @Test
    func editingCannotFollowAManagedDirectorySymlinkOutsideTheShelf() throws {
        try withStore { store, directory in
            let note = try #require(store.addContextNote("original", location: location))
            let owned = note.url.deletingLastPathComponent()
            let outside = directory.appendingPathComponent("outside")
            try FileManager.default.moveItem(at: owned, to: outside)
            try FileManager.default.createSymbolicLink(at: owned, withDestinationURL: outside)
            #expect(store.updateContextNote(id: note.id, text: "edited") == nil)
            #expect(store.items == [note])
            #expect(try String(contentsOf: outside.appendingPathComponent(note.url.lastPathComponent), encoding: .utf8) == "original")
            #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).count == 1)
        }
    }
}

@MainActor
struct ContextNoteLocationReaderTests {
    @Test
    func pageAddressUsesWindowDocumentOrWebAreaWithoutReadingPageContent() {
        let address = "https://example.test/article?query=1#part"
        let direct = ContextNoteLocationReader.findPageAddress(in: 0, document: { _ in address }, role: { _ in nil }, url: { _ in nil }, children: { _ in Issue.record("A window document must not traverse the page"); return [] })
        #expect(direct == address)
        let nested = ContextNoteLocationReader.findPageAddress(in: 0, document: { _ in nil }, role: { $0 == 1 ? "AXWebArea" : "AXWindow" }, url: { $0 == 1 ? address : nil }, children: { node in
            #expect(node == 0)
            return [1]
        })
        #expect(nested == address)
        let unavailable = ContextNoteLocationReader.findPageAddress(in: 0, document: { _ in nil }, role: { _ in "AXWebArea" }, url: { _ in nil }, children: { _ in Issue.record("The page DOM must remain unread"); return [] })
        #expect(unavailable == nil)
    }

    @Test
    func cyclicAndHugeAccessibilityTreesHaveATimeAndNodeBudget() {
        var visited = 0
        let result = ContextNoteLocationReader.findPageAddress(in: 0, document: { _ in nil }, role: { _ in visited += 1; return "AXGroup" }, url: { _ in nil }, children: { _ in Array(repeating: 0, count: 200) }, now: { 0 })
        #expect(result == nil)
        #expect(visited == 80)
        var time = 0.0
        visited = 0
        let timed = ContextNoteLocationReader.findPageAddress(in: 0, document: { _ in nil }, role: { _ in visited += 1; return "AXGroup" }, url: { _ in nil }, children: { _ in [0] }, now: { defer { time += 0.05 }; return time })
        #expect(timed == nil)
        #expect(visited == 3)
    }

    @Test
    func browserWithoutAValidAddressCannotFallBackToAnotherPagesWindowTitle() {
        for value in [nil, "", "javascript:alert(1)", "file:///private/document", "https://"] as [String?] {
            #expect(ContextNoteLocationReader.resolve(bundleIdentifier: "browser", applicationName: "Browser", windowTitle: "Shared title", isBrowser: true, pageAddress: value) == .unavailable)
        }
    }

    @Test
    func recognizedPagePreservesRouteButRemovesEmbeddedCredentials() throws {
        let result = ContextNoteLocationReader.resolve(bundleIdentifier: "browser", applicationName: "Browser", windowTitle: "Page", isBrowser: true, pageAddress: "https://name:secret@example.test/path?q=one#two")
        #expect(result == .location(.webPage(url: try #require(URL(string: "https://example.test/path?q=one#two")), title: "Page", applicationName: "Browser")))
    }

    @Test
    func applicationWindowRequiresAnIdentifiableTitle() {
        #expect(ContextNoteLocationReader.resolve(bundleIdentifier: "editor", applicationName: "Editor", windowTitle: " ", isBrowser: false, pageAddress: nil) == .unavailable)
        #expect(ContextNoteLocationReader.resolve(bundleIdentifier: "editor", applicationName: "Editor", windowTitle: "Doc", isBrowser: false, pageAddress: nil) == .location(.window(bundleIdentifier: "editor", applicationName: "Editor", title: "Doc")))
    }
}
