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
    func notesGroupByApplicationWithoutMixingDesktopOrChangingTheirOrder() {
        let items = Self.groupingItems
        let groups = ShelfNoteApplicationGroup.groups(in: items)
        #expect(groups.map(\.id) == [.application("Safari"), .application("Editor"), .desktop, .application("桌面")])
        #expect(groups.map { $0.items.map(\.id) } == [
            [items[0].id, items[3].id, items[5].id], [items[1].id],
            [items[2].id, items[6].id], [items[7].id],
        ])
        #expect(groups.map(\.title) == ["Safari", "Editor", AppLocalization.text("桌面"), "桌面"])
        #expect(ShelfNoteApplicationGroup.groups(in: []).isEmpty)
        #expect(ShelfNoteApplicationGroup.groups(in: [items[4]]).isEmpty)
    }

    @Test
    func noteCategoryAndSearchComposeBeforeGroupingAndKeepOtherCategoriesUnchanged() {
        let items = Self.groupingItems
        let notes = ShelfModuleView.filteredItems(in: items, category: .note, searchText: "")
        #expect(notes == items.filter { $0.noteLocation != nil })
        #expect(ShelfModuleView.filteredItems(in: items, category: .all, searchText: "") == items)
        #expect(ShelfModuleView.filteredItems(in: items, category: .text, searchText: "") == [items[4]])
        #expect(ShelfModuleView.filteredItems(in: items, category: .note, searchText: "missing").isEmpty)
        #expect(ShelfModuleView.filteredItems(in: [], category: .note, searchText: "").isEmpty)
        let matches = ShelfModuleView.filteredItems(in: items, category: .note, searchText: "SECOND")
        #expect(matches == [items[3], items[6]])
        #expect(ShelfNoteApplicationGroup.groups(in: matches).map(\.id) == [.application("Safari"), .desktop])
    }

    @Test(arguments: [CGFloat(140), 288, 436], [LayoutDirection.leftToRight, .rightToLeft])
    func applicationGroupsStartTheirOwnRowsAndWrapWithinTheAvailableWidth(width: CGFloat, direction: LayoutDirection) throws {
        let notes = Self.groupingItems.filter { $0.noteLocation != nil }
        let frames = try Self.renderedFrames(items: notes, category: .note, width: width, direction: direction)
        let groups = ShelfNoteApplicationGroup.groups(in: notes)
        let columns = Int((width + 8) / 148)
        var previousBottom: CGFloat = -.infinity
        for group in groups {
            let first = try #require(frames[group.items[0].id])
            #expect(first.minY > previousBottom)
            for (index, item) in group.items.enumerated() {
                let frame = try #require(frames[item.id])
                let leading = CGFloat(index % columns) * 148
                #expect(abs(frame.minX - (direction == .leftToRight ? leading : width - leading - 140)) < 0.01)
                #expect(abs(frame.minY - first.minY - CGFloat(index / columns) * 92) < 0.01)
                #expect(frame.width == 140 && frame.height == 84)
                #expect(frame.minX >= 0 && frame.maxX <= width)
                previousBottom = max(previousBottom, frame.maxY)
            }
        }
    }

    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func allCategoryKeepsTheExistingMixedGridInsteadOfGroupingNotes(direction: LayoutDirection) throws {
        let items = Self.groupingItems
        let frames = try Self.renderedFrames(items: items, category: .all, width: 436, direction: direction)
        let expected = ShelfGridLayout.frames(columnSpans: items.map { $0.noteLocation == nil ? 1 : 2 }, width: 436,
                                              layoutDirection: direction)
        #expect(items.compactMap { frames[$0.id] } == expected)
    }

    @Test(arguments: AppLanguage.allCases)
    func noteCategoryAndDesktopGroupLabelsRenderInEveryLanguage(language: AppLanguage) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let resource = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: resource), format: nil) as? [String: String])
        for key in ["便签", "桌面"] {
            let value = try #require(table[key], "Missing \(language.rawValue) translation for \(key)")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
            if language != .simplifiedChinese && language != .traditionalChinese {
                #expect(value != key)
            }
        }
    }

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

    private static var groupingItems: [FileShelfItem] {
        let locations: [ContextNoteLocation?] = [
            .webPage(url: URL(string: "https://example.invalid/first")!, title: "First", applicationName: "Safari"),
            .window(bundleIdentifier: "test.editor", applicationName: "Editor", title: "Document"),
            .desktop(displayID: "one", displayName: "Built-in"),
            .window(bundleIdentifier: "com.apple.Safari", applicationName: "Safari", title: "Downloads"),
            nil,
            .webPage(url: URL(string: "https://example.invalid/third")!, title: "Third", applicationName: "Safari"),
            .desktop(displayID: "two", displayName: "External"),
            .window(bundleIdentifier: "test.desktop-name", applicationName: "桌面", title: "Document"),
        ]
        return locations.enumerated().map { index, location in
            FileShelfItem(id: UUID(), url: URL(fileURLWithPath: "/synthetic-shelf-note/\(index)"),
                          addedAt: Date(timeIntervalSince1970: Double(index)), bookmarkData: Data(),
                          text: [3, 6].contains(index) ? "second note" : "note \(index)", noteLocation: location)
        }
    }

    private static func renderedFrames(items: [FileShelfItem], category: FileShelfCategory, width: CGFloat,
                                       direction: LayoutDirection) throws -> [UUID: CGRect] {
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: CGRect(x: -100_000, y: -100_000, width: width, height: 1_000),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let host = NSHostingView(rootView: ShelfItemCollection(items: items, category: category) { item in
            ShelfItemView(item: item, onOpen: {}, onCopy: {}, onSendToQuickNote: {}, onRemove: {})
                .background(ShelfFrameProbe(id: item.id))
        }.environment(\.layoutDirection, direction)
            .frame(width: width, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading))
        host.sizingOptions = []
        panel.contentView = host
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(panel.frame) })
        panel.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        #expect(host.bounds.size == CGSize(width: width, height: 1_000))
        var frames: [UUID: CGRect] = [:]
        func visit(_ view: NSView) {
            if let probe = view as? ShelfFrameProbe.ProbeView {
                frames[probe.id] = probe.convert(probe.bounds, to: host)
            }
            view.subviews.forEach(visit)
        }
        visit(host)
        #expect(frames.count == items.count)
        return frames
    }

    private static func source(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/Zisla/\(name)"), encoding: .utf8)
    }
}

private struct ShelfFrameProbe: NSViewRepresentable {
    let id: UUID

    final class ProbeView: NSView {
        let id: UUID
        init(id: UUID) {
            self.id = id
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
    }

    func makeNSView(context: Context) -> ProbeView { ProbeView(id: id) }
    func updateNSView(_ nsView: ProbeView, context: Context) {}
}
