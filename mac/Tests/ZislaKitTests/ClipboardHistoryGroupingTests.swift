import Combine
import Foundation
import SQLite3
import Testing
import ZislaCore
@testable import ZislaKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ClipboardHistoryGroupingTests {
    private static let firstApp = ClipboardSourceApp(bundleIdentifier: "test.a", name: "Shared Tool")
    private static let secondApp = ClipboardSourceApp(bundleIdentifier: "test.b", name: "Shared Tool")

    @Test
    func sourceGroupsAreOrderedAcrossPagesBeforeApplyingThePageLimit() async throws {
        let firstPinned = item("first pinned", at: 1, pinned: true, source: Self.firstApp)
        let firstRecent = item("first recent", at: 9, source: Self.firstApp)
        let firstOld = item("first old", at: 2, source: .init(bundleIdentifier: Self.firstApp.bundleIdentifier, name: "Old Name"))
        let secondPinned = item("second pinned", at: 3, pinned: true, source: Self.secondApp)
        let secondHistory = item("second history", at: 10, source: Self.secondApp)
        let unknownPinned = item("unknown pinned", at: 4, pinned: true)
        let unknownRecent = item("unknown recent", at: 12)
        let unknownOld = item("unknown old", at: 11)
        let expected = [firstPinned, firstRecent, firstOld, secondPinned, secondHistory, unknownPinned, unknownRecent, unknownOld]
        let fixture = try ClipboardGroupingFixture(items: expected.reversed(), pageSize: 2)
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        fixture.store.updateQuery(scope: .all, searchText: "", grouping: .sourceApp)
        await fixture.store.waitUntilLoaded()

        var allPages: [ClipboardHistoryItem] = []
        for page in 0..<4 {
            #expect(fixture.store.currentPage == page)
            #expect(fixture.store.totalItemCount == expected.count)
            #expect(fixture.store.categoryCounts == [.text: expected.count])
            #expect(fixture.store.items == Array(expected[(page * 2)..<(page * 2 + 2)]))
            allPages += fixture.store.items
            fixture.store.loadNextPage()
            await fixture.store.waitUntilLoaded()
        }
        #expect(allPages == expected, "Same-named apps must remain separate, and renamed records of one bundle must stay together")
        #expect(!fixture.store.canLoadNextPage)
    }

    @Test(arguments: [ClipboardHistoryScope.all, .pinned, .history])
    func sourceGroupingCombinesScopeCategorySearchAndFullResultCounts(scope: ClipboardHistoryScope) async throws {
        let firstPinned = item("favorite text", at: 1, pinned: true, source: Self.firstApp)
        let firstHistory = item("history text", at: 2, source: Self.firstApp)
        let secondHistory = item("another text", at: 3, source: Self.secondApp)
        let unknown = item("shared content", at: 4)
        let firstImage = ClipboardHistoryItem(content: .image(Data([1])), sourceApp: Self.firstApp)
        let secondImage = ClipboardHistoryItem(content: .image(Data([2])), isPinned: true, sourceApp: Self.secondApp)
        let excluded = item("excluded content", at: 5, source: .init(bundleIdentifier: "test.other", name: "Other"))
        let fixture = try ClipboardGroupingFixture(
            items: [firstPinned, firstHistory, secondHistory, unknown, firstImage, secondImage, excluded], pageSize: 1
        )
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        fixture.store.updateQuery(scope: scope, searchText: " SHARED ", category: .text, grouping: .sourceApp)
        await fixture.store.waitUntilLoaded()
        let expected: [ClipboardHistoryItem]
        let expectedImageCount: Int
        switch scope {
        case .all: expected = [firstPinned, firstHistory, secondHistory, unknown]; expectedImageCount = 2
        case .pinned: expected = [firstPinned]; expectedImageCount = 1
        case .history: expected = [firstHistory, secondHistory, unknown]; expectedImageCount = 1
        }

        for item in expected {
            #expect(fixture.store.items == [item])
            #expect(fixture.store.totalItemCount == expected.count)
            #expect(fixture.store.categoryCounts == [.text: expected.count, .image: expectedImageCount])
            fixture.store.loadNextPage()
            await fixture.store.waitUntilLoaded()
        }
        fixture.store.updateQuery(scope: scope, searchText: "missing app", category: .text, grouping: .sourceApp)
        await fixture.store.waitUntilLoaded()
        #expect(fixture.store.items.isEmpty && fixture.store.totalItemCount == 0)
        #expect(fixture.store.categoryCounts.isEmpty && fixture.store.errorDescription == nil)
    }

    @Test
    func changingGroupingResetsPaginationAndRestoresTheDefaultPreview() async throws {
        let history = (1...12).map { item("history \($0)", at: Double($0), source: Self.firstApp) }
        let pinned = item("favorite", at: 0, pinned: true, source: Self.secondApp)
        let fixture = try ClipboardGroupingFixture(items: history + [pinned], pageSize: 10)
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        #expect(fixture.store.isShowingHistoryPreview)
        #expect(fixture.store.historyItems.count == ClipboardHistoryStore.recentHistoryPreviewLimit)

        fixture.store.loadFullHistory()
        await fixture.store.waitUntilLoaded()
        fixture.store.loadNextPage()
        await fixture.store.waitUntilLoaded()
        #expect(fixture.store.currentPage == 1)
        fixture.store.updateQuery(scope: .all, searchText: "", grouping: .sourceApp)
        await fixture.store.waitUntilLoaded()
        #expect(fixture.store.currentPage == 0 && fixture.store.items.count == 10)
        #expect(!fixture.store.isShowingHistoryPreview && fixture.store.isHistoryExpanded)
        #expect(fixture.store.currentQuery.grouping == .sourceApp && fixture.store.displayedQuery.grouping == .sourceApp)

        fixture.store.loadNextPage()
        await fixture.store.waitUntilLoaded()
        fixture.store.updateQuery(scope: .all, searchText: "", grouping: .none)
        await fixture.store.waitUntilLoaded()
        #expect(fixture.store.currentPage == 0 && fixture.store.isShowingHistoryPreview)
        #expect(!fixture.store.isHistoryExpanded)
        #expect(fixture.store.pinnedItems == [pinned])
        #expect(fixture.store.historyItems == Array(history.suffix(8).reversed()))
    }

    @Test
    func optimisticCopiesRespectTheGlobalFirstPageBoundaryAfterRowsMoveToAnotherApp() async throws {
        let first = item("first", at: 3, source: Self.firstApp)
        let second = item("second", at: 2, source: Self.firstApp)
        let hidden = item("hidden", at: 4, source: Self.secondApp)
        let fixture = try ClipboardGroupingFixture(items: [first, second, hidden], pageSize: 2)
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        fixture.store.updateQuery(scope: .all, searchText: "", grouping: .sourceApp)
        await fixture.store.waitUntilLoaded()
        let laterApp = ClipboardSourceApp(bundleIdentifier: "test.z", name: "Later")

        #expect(fixture.store.record(.text("later copy"), sourceApp: laterApp))
        #expect(fixture.store.items == [first, second], "A later app must not replace a row on a full first page")
        #expect(fixture.store.record(first.content, sourceApp: Self.secondApp))
        #expect(fixture.store.items == [second])
        #expect(fixture.store.record(.text("later copy"), sourceApp: laterApp))
        #expect(fixture.store.items == [second], "A temporary gap must not be mistaken for the end of the full result set")
        #expect(fixture.store.record(.text("earlier copy"), sourceApp: Self.firstApp))
        #expect(fixture.store.items.map(\.content) == [.text("earlier copy"), second.content])
        fixture.store.flushPendingChanges()
        let page = try await fixture.database.loadPage(scope: .all, searchText: "", category: .all,
            grouping: .sourceApp, offset: 0, limit: 2)
        #expect(page.items == fixture.store.items, "Optimistic group ordering must agree with SQLite")
        #expect(page.totalCount == 5)
    }

    @Test
    func groupedCapacityKeepsTheMostRecentHistoryAcrossAppsAndRetainsPinnedItems() async throws {
        let fixture = try ClipboardGroupingFixture(items: [], capacity: 2)
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        fixture.store.updateQuery(scope: .all, searchText: "", grouping: .sourceApp)
        await fixture.store.waitUntilLoaded()
        let laterApp = ClipboardSourceApp(bundleIdentifier: "test.z", name: "Later")
        let middleApp = ClipboardSourceApp(bundleIdentifier: "test.m", name: "Middle")
        fixture.clock.date = Date(timeIntervalSince1970: 1)
        #expect(fixture.store.recordPinned(.text("favorite"), sourceApp: Self.firstApp))
        #expect(fixture.store.record(.text("old history"), sourceApp: Self.firstApp))
        fixture.clock.date = Date(timeIntervalSince1970: 2)
        #expect(fixture.store.record(.text("middle history"), sourceApp: laterApp))
        fixture.clock.date = Date(timeIntervalSince1970: 3)
        #expect(fixture.store.record(.text("new history"), sourceApp: middleApp))
        #expect(fixture.store.items.map(\.content) == [.text("favorite"), .text("new history"), .text("middle history")])
        fixture.store.flushPendingChanges()
        let page = try await fixture.database.loadPage(scope: .all, searchText: "", category: .all,
            grouping: .sourceApp, offset: 0, limit: 20)
        #expect(page.items == fixture.store.items)

        let favorite = try #require(fixture.store.pinnedItems.first)
        fixture.clock.date = Date(timeIntervalSince1970: 4)
        fixture.store.setPinned(id: favorite.id, isPinned: false)
        #expect(fixture.store.items.map(\.content) == [.text("favorite"), .text("new history")])
        fixture.store.flushPendingChanges()
        let history = try await fixture.database.loadPage(scope: .history, searchText: "", category: .all,
            grouping: .sourceApp, offset: 0, limit: 20)
        #expect(history.items == fixture.store.items)
    }

    @Test
    func clearingTheWholeHistoryQueryAllowsTheNextCopyToAppearImmediately() async throws {
        let history = (1...3).map { item("history \($0)", at: Double($0), source: Self.firstApp) }
        let favorite = item("favorite", at: 0, pinned: true, source: Self.secondApp)
        let fixture = try ClipboardGroupingFixture(items: history + [favorite], pageSize: 1)
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        fixture.store.updateQuery(scope: .history, searchText: "", grouping: .sourceApp)
        await fixture.store.waitUntilLoaded()
        fixture.store.removeAllHistory()
        #expect(fixture.store.record(.text("new copy"), sourceApp: Self.secondApp))
        #expect(fixture.store.items.map(\.content) == [.text("new copy")])
        fixture.store.flushPendingChanges()
        let page = try await fixture.database.loadPage(scope: .all, searchText: "", category: .all,
            grouping: .sourceApp, offset: 0, limit: 20)
        #expect(page.items.map(\.content) == [favorite.content, .text("new copy")])
    }

    @Test(arguments: [false, true])
    func anEmptyFirstPageReloadsHiddenGroupsWithoutInsertingALaterApp(clearHistory: Bool) async throws {
        let hidden = item("hidden", at: 1, pinned: clearHistory, source: Self.secondApp)
        let initial = item("initial", at: 2, source: Self.firstApp)
        let fixture = try ClipboardGroupingFixture(items: clearHistory ? [initial, hidden] : [], pageSize: 1)
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        fixture.store.updateQuery(scope: .all, searchText: "", grouping: .sourceApp)
        await fixture.store.waitUntilLoaded()
        if clearHistory {
            fixture.store.removeAllHistory()
        } else {
            #expect(fixture.store.record(initial.content, sourceApp: initial.sourceApp))
            #expect(fixture.store.record(hidden.content, sourceApp: hidden.sourceApp))
            let id = try #require(fixture.store.items.first?.id)
            fixture.store.remove(id: id)
        }
        #expect(fixture.store.items.isEmpty)
        let (loads, continuation) = AsyncStream<Void>.makeStream()
        let observation = fixture.store.$items.dropFirst().sink { items in
            if items.first?.content == hidden.content { continuation.yield(()) }
        }
        defer { observation.cancel(); continuation.finish() }
        #expect(fixture.store.record(.text("later copy"), sourceApp: .init(bundleIdentifier: "test.z", name: "Later")))
        #expect(fixture.store.items.isEmpty, "A hidden earlier app must be loaded before a later app can appear")
        var iterator = loads.makeAsyncIterator()
        await iterator.next()
        await fixture.store.waitUntilLoaded()
        #expect(fixture.store.items.map(\.content) == [hidden.content])
        #expect(fixture.store.totalItemCount == 2 && fixture.store.errorDescription == nil)
        let all = try await fixture.database.loadPage(scope: .all, searchText: "", category: .all,
            grouping: .sourceApp, offset: 0, limit: 20)
        #expect(all.items.map(\.content) == [hidden.content, .text("later copy")])
    }

    @Test
    func incompleteSourceMetadataSortsInTheUnknownGroup() async throws {
        let known = item("known", at: 1, source: Self.secondApp)
        let identifierOnly = item("identifier only", at: 4, source: Self.firstApp)
        let nameOnly = item("name only", at: 5, source: Self.firstApp)
        let unknown = item("unknown favorite", at: 0, pinned: true)
        let fixture = try ClipboardGroupingFixture(items: [known, identifierOnly, nameOnly, unknown])
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        try fixture.execute("UPDATE clipboard_history SET source_app_name = NULL WHERE id = '\(identifierOnly.id.uuidString)'")
        try fixture.execute("UPDATE clipboard_history SET source_app_bundle_identifier = NULL WHERE id = '\(nameOnly.id.uuidString)'")
        fixture.store.updateQuery(scope: .all, searchText: "", grouping: .sourceApp)
        await fixture.store.waitUntilLoaded()

        #expect(fixture.store.items.map(\.content) == [known.content, unknown.content, nameOnly.content, identifierOnly.content])
        #expect(fixture.store.items.dropFirst().allSatisfy { $0.sourceApp == nil })
    }

    @Test
    func failedGroupReadPreservesTheDisplayedSnapshotAndCanRecover() async throws {
        let original = item("original", at: 1, source: Self.secondApp)
        let fixture = try ClipboardGroupingFixture(items: [original])
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        try fixture.execute("""
            INSERT INTO clipboard_history (id, content_type, text_value, last_copied_at, is_pinned,
                content_category, source_app_bundle_identifier, source_app_name)
            VALUES ('invalid-id', 0, 'invalid row', 20, 0, 'text', 'test.a', 'Invalid');
            """)
        fixture.store.updateQuery(scope: .all, searchText: "", grouping: .sourceApp)
        #expect(fixture.store.displayedQuery.grouping == .none && fixture.store.isShowingHistoryPreview)
        await fixture.store.waitUntilLoaded()
        #expect(fixture.store.items == [original] && fixture.store.totalItemCount == 1)
        #expect(fixture.store.currentQuery.grouping == .none && fixture.store.displayedQuery.grouping == .none)
        #expect(fixture.store.isShowingHistoryPreview && !fixture.store.isHistoryExpanded)
        #expect(fixture.store.errorDescription != nil && !fixture.store.isLoading)

        try fixture.execute("DELETE FROM clipboard_history WHERE id = 'invalid-id'")
        fixture.store.updateQuery(scope: .all, searchText: "", grouping: .sourceApp)
        await fixture.store.waitUntilLoaded()
        #expect(fixture.store.items == [original] && fixture.store.errorDescription == nil)
        #expect(fixture.store.displayedQuery.grouping == .sourceApp && !fixture.store.isShowingHistoryPreview)
    }

    @Test
    func optimisticAndPersistedOrderingUseTheSameBinaryBundleAndEqualTimestampOrder() async throws {
        let sources = ["test.z", "test.é", "test.e\u{301}", "test.A"].map {
            ClipboardSourceApp(bundleIdentifier: $0, name: "Shared Tool")
        }
        let fixture = try ClipboardGroupingFixture(items: [])
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        fixture.store.updateQuery(scope: .all, searchText: "", grouping: .sourceApp)
        await fixture.store.waitUntilLoaded()
        #expect(fixture.store.record(.text("unknown")))
        for (index, source) in sources.enumerated() {
            #expect(fixture.store.record(.text("copy \(index)"), sourceApp: source))
        }
        #expect(fixture.store.record(.text("same time"), sourceApp: sources[0]))
        fixture.store.flushPendingChanges()
        let page = try await fixture.database.loadPage(scope: .all, searchText: "", category: .all,
            grouping: .sourceApp, offset: 0, limit: 20)
        #expect(page.items == fixture.store.items)
        #expect(page.items.map { $0.sourceApp?.bundleIdentifier } == ["test.A", "test.e\u{301}", "test.z", "test.z", "test.é", nil])
    }

    private func item(_ text: String, at timestamp: Double, pinned: Bool = false, source: ClipboardSourceApp? = nil) -> ClipboardHistoryItem {
        ClipboardHistoryItem(content: .text(text), lastCopiedAt: Date(timeIntervalSince1970: timestamp),
            isPinned: pinned, sourceApp: source)
    }
}

@MainActor
private struct ClipboardGroupingFixture {
    let directory: URL
    let storageURL: URL
    let database: ClipboardHistoryDatabase
    let store: ClipboardHistoryStore
    let clock: ClipboardGroupingClock

    init(items: some Sequence<ClipboardHistoryItem>, pageSize: Int = 20, capacity: Int? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-grouping-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        database = ClipboardHistoryDatabase(storageURL: storageURL)
        try database.flush(items.map { .upsert($0, capacity: nil) })
        clock = ClipboardGroupingClock()
        let clock = clock
        store = ClipboardHistoryStore(storageURL: storageURL, capacity: capacity, pageSize: pageSize,
            persistenceDelay: .seconds(60), now: { clock.date })
    }

    func execute(_ sql: String) throws {
        var connection: OpaquePointer?
        guard sqlite3_open(storageURL.path, &connection) == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            throw ClipboardGroupingFixtureError()
        }
        defer { sqlite3_close(connection) }
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw ClipboardGroupingFixtureError() }
    }

    func cleanup() {
        store.flushPendingChanges()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class ClipboardGroupingClock {
    var date = Date(timeIntervalSince1970: 1_000)
}

private struct ClipboardGroupingFixtureError: Error {}
