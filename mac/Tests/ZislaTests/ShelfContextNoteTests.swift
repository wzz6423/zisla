import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ShelfContextNoteTests {
    @Test
    func collapsedNoteOccupiesTwoFileColumns() {
        let host = NSHostingView(rootView: ShelfItemView(
            item: Self.note, onOpen: {}, onCopy: {}, onSendToQuickNote: {}, onRemove: {}
        ))
        #expect(host.fittingSize == CGSize(width: 140, height: 84))
    }

    @Test
    func savedNotesReturnToTheShelfHome() throws {
        let source = try Self.source("ZislaApp.swift")
        let savedHandler = try #require(source.range(of: "onSaved: { [weak coordinator] _, point in"))
        let tail = source[savedHandler.upperBound...]
        let handler = try #require(tail.range(of: "\n            }"))
        #expect(tail[..<handler.lowerBound].contains("model.contextNoteEditor.hide()"))
    }

    @Test
    func detailHasAnExplicitLocationActionAndNoDeletion() throws {
        let source = try Self.source("ContextNoteViews.swift")
        let detailStart = try #require(source.range(of: "struct ContextNoteDetailView"))
        let detail = source[detailStart.lowerBound...]
        #expect(detail.contains("前往记录位置"))
        #expect(!detail.contains("onRemove"))
        #expect(!detail.contains("role: .destructive"))
    }

    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func mixedCardsWrapWithoutOverlappingOrCoveringFiles(direction: LayoutDirection) {
        let spans = [1, 2, 1, 2, 2, 1, 1]
        let frames = ShelfGridLayout.frames(columnSpans: spans, width: 288, layoutDirection: direction)
        #expect(frames.map(\.width) == spans.map { CGFloat($0 * 74 - 8) })
        #expect(frames.map(\.minY) == [0, 0, 0, 92, 92, 184, 184])
        for (index, frame) in frames.enumerated() {
            #expect(frame.minX >= 0 && frame.maxX <= 288)
            #expect(frame.height == 84)
            for other in frames.dropFirst(index + 1) { #expect(!frame.intersects(other)) }
        }
        #expect(ShelfGridLayout.frames(columnSpans: [], width: 140).isEmpty)
    }

    @Test
    func creatingAndClosingAnEmptyDraftDoesNotAddAShelfItem() throws {
        try withStore { store, _ in
            let editor = ContextNoteShelfEditor()
            let draft = ContextNoteDraft(location: try #require(Self.note.noteLocation), createdAt: Self.note.addedAt)
            editor.begin(draft)
            #expect(editor.isPresented)
            #expect(editor.draft?.text == "")
            #expect(editor.draft?.createdAt == Self.note.addedAt)
            #expect(editor.save(in: store) == nil)
            #expect(store.items.isEmpty)
            editor.close()
            #expect(!editor.isPresented)
            #expect(editor.draft == nil)
            #expect(!editor.resumeNew())
            #expect(store.items.isEmpty)
        }
    }

    @Test
    func hidingDraftsReturnsToHomeAndExplicitActionsResumeTheirUnsavedText() throws {
        try withStore { store, _ in
            let editor = ContextNoteShelfEditor()
            let draft = ContextNoteDraft(location: try #require(Self.note.noteLocation))
            editor.begin(draft)
            draft.text = "new unsaved"
            editor.hide()
            #expect(!editor.isPresented)
            #expect(editor.resumeNew())
            #expect(editor.draft === draft)
            let saved = try #require(editor.save(in: store))
            #expect(saved.text == "new unsaved")
            #expect(!editor.isPresented)
            #expect(!editor.resumeNew())
            editor.open(saved)
            editor.draft?.text = "edited unsaved"
            editor.hide()
            #expect(!editor.isPresented)
            editor.open(saved)
            #expect(editor.draft?.text == "edited unsaved")
            #expect(store.items.first?.text == "new unsaved")
            let edited = try #require(editor.save(in: store))
            #expect(edited.id == saved.id)
            #expect(edited.addedAt == saved.addedAt)
            #expect(edited.text == "edited unsaved")
            #expect(store.items.count == 1)
            #expect(!editor.isPresented)
            editor.open(edited)
            editor.draft?.text = "discard me"
            editor.close()
            editor.open(edited)
            #expect(editor.draft?.text == "edited unsaved")
            editor.removed(edited.id)
            #expect(editor.draft == nil)
        }
    }

    @Test
    func aFailedSaveKeepsTheEditableDraftAndDoesNotCreateADuplicate() throws {
        try withStore { store, directory in
            let location = try #require(Self.note.noteLocation)
            let saved = try #require(store.addContextNote("original", location: location))
            let editor = ContextNoteShelfEditor()
            editor.open(saved)
            let draft = try #require(editor.draft)
            draft.text = "retry this edit"
            let index = directory.appendingPathComponent("shelf.json")
            try FileManager.default.removeItem(at: index)
            try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
            #expect(editor.save(in: store) == nil)
            #expect(editor.draft === draft)
            #expect(editor.isPresented)
            #expect(editor.draft?.error != nil)
            #expect(store.items == [saved])
            try FileManager.default.removeItem(at: index)
            #expect(editor.save(in: store)?.text == "retry this edit")
            #expect(store.items.count == 1)
            #expect(!editor.isPresented)
        }
    }

    private func withStore(_ body: (FileShelfStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-editor-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json")), directory)
    }

    private static let note = FileShelfItem(
        id: UUID(), url: URL(fileURLWithPath: "/synthetic-context-note/note"),
        addedAt: Date(timeIntervalSince1970: 0), bookmarkData: Data(),
        text: "Remember the current review before changing this window",
        noteLocation: .window(bundleIdentifier: "test.app", applicationName: "Test", title: "Review")
    )

    private static func source(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/Zisla/\(name)"), encoding: .utf8)
    }
}
