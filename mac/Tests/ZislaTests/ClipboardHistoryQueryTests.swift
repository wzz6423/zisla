import Combine
import Foundation
import SQLite3
import SwiftUI
import Testing
@testable import Zisla
@testable import ZislaKit

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ClipboardHistoryQueryTests {
    @Test(arguments: ["filter", "search", "category"])
    func failedQueriesRestoreControlsWithoutRetryingTheirRollback(dimension: String) async throws {
        let fixture = try ClipboardQueryFixture()
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        try fixture.rejectRemovals()
        fixture.store.remove(id: fixture.removed.id)
        var startedLoads = 0
        let observation = fixture.store.$isLoading.dropFirst().sink { loading in
            if loading { startedLoads += 1 }
        }
        defer { observation.cancel() }

        for _ in 0..<2 {
            fixture.controls.filter = dimension == "filter" ? .pinned : .all
            fixture.controls.searchText = dimension == "search" ? "missing" : ""
            fixture.controls.category = dimension == "category" ? .url : .all
            await fixture.controls.apply(to: fixture.store)

            #expect(fixture.controls.filter == .all)
            #expect(fixture.controls.searchText.isEmpty)
            #expect(fixture.controls.category == .all)
            #expect(fixture.store.items == [fixture.kept])
            #expect(fixture.store.totalItemCount == 1)
            #expect(fixture.store.errorDescription?.contains("injected query control failure") == true)
            let completedLoads = startedLoads
            await fixture.controls.apply(to: fixture.store)
            #expect(startedLoads == completedLoads, "Restoring controls must not initiate another failed write")
        }
    }

    @Test
    func successfulSearchPreservesTrailingSpaceForTheNextWord() async throws {
        let fixture = try ClipboardQueryFixture()
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        fixture.controls.filter = .history
        fixture.controls.searchText = "kept "
        fixture.controls.category = .text

        await fixture.controls.apply(to: fixture.store)

        #expect(fixture.controls.searchText == "kept ")
        #expect(fixture.controls.filter == .history)
        #expect(fixture.controls.category == .text)
        #expect(fixture.store.items == [fixture.kept])
        #expect(fixture.store.errorDescription == nil)
    }

    @Test(arguments: [false, true])
    func cancelledQueryCannotRestoreOverANewerInput(sameQuery: Bool) async throws {
        let fixture = try ClipboardQueryFixture()
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        try fixture.rejectRemovals()
        let blocker = try fixture.blockWrites()
        defer { sqlite3_close(blocker) }
        defer { sqlite3_exec(blocker, "ROLLBACK", nil, nil, nil) }
        fixture.store.remove(id: fixture.removed.id)
        fixture.controls.filter = .history
        fixture.controls.searchText = "target "
        fixture.controls.category = .text
        let older = Task { await fixture.controls.apply(to: fixture.store) }
        let newerSearch = sameQuery ? "target " : "kept "
        var newer: Task<Void, Never>?
        defer {
            older.cancel()
            newer?.cancel()
        }
        do {
            try await waitUntil { fixture.store.isLoading }
        } catch {
            older.cancel()
            sqlite3_exec(blocker, "ROLLBACK", nil, nil, nil)
            await older.value
            throw error
        }

        older.cancel()
        fixture.controls.searchText = newerSearch
        let (reads, continuation) = AsyncStream<Void>.makeStream()
        var searchReads = 0
        fixture.controls.onSearchRead = {
            searchReads += 1
            if searchReads == 3 { continuation.yield(()) }
        }
        defer { continuation.finish() }
        newer = Task { await fixture.controls.apply(to: fixture.store) }
        var iterator = reads.makeAsyncIterator()
        await iterator.next()
        fixture.controls.onSearchRead = nil
        #expect(fixture.store.isLoading, "The next task must finish its debounce while the shared query remains blocked")
        #expect(fixture.controls.searchText == newerSearch)
        #expect(fixture.controls.filter == .history)
        #expect(fixture.controls.category == .text)
        #expect(sqlite3_exec(blocker, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        await older.value

        await newer?.value
        #expect(fixture.controls.searchText.isEmpty)
        #expect(fixture.controls.filter == .all)
        #expect(fixture.controls.category == .all)
        #expect(fixture.store.items == [fixture.kept])
    }

    @Test
    func changedInputIsNotSubmittedByAnOlderDebouncingTask() async throws {
        let fixture = try ClipboardQueryFixture()
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        fixture.controls.searchText = "removed"
        let (reads, continuation) = AsyncStream<Void>.makeStream()
        var searchReads = 0
        fixture.controls.onSearchRead = {
            searchReads += 1
            if searchReads == 2 { continuation.yield(()) }
        }
        defer { continuation.finish() }
        let older = Task { await fixture.controls.apply(to: fixture.store) }
        defer { older.cancel() }
        var iterator = reads.makeAsyncIterator()
        await iterator.next()
        fixture.controls.onSearchRead = nil
        fixture.controls.searchText = "kept "
        await older.value

        #expect(fixture.store.items == [fixture.removed, fixture.kept], "An older debounce must not submit a newer input")
        #expect(fixture.controls.searchText == "kept ")
        await fixture.controls.apply(to: fixture.store)
        #expect(fixture.store.items == [fixture.kept])
        #expect(fixture.controls.searchText == "kept ")
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["cancelled", "changed"])
    func anOlderLoadedQueryCannotOverwriteTheCurrentControls(action: String) async throws {
        let fixture = try ClipboardQueryFixture()
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        try fixture.rejectRemovals()
        let blocker = try fixture.blockWrites()
        defer { sqlite3_close(blocker) }
        defer { sqlite3_exec(blocker, "ROLLBACK", nil, nil, nil) }
        fixture.store.remove(id: fixture.removed.id)
        fixture.controls.filter = .history
        fixture.controls.searchText = "target "
        fixture.controls.category = .text
        let older = Task { await fixture.controls.apply(to: fixture.store) }
        defer { older.cancel() }
        do {
            try await waitUntil { fixture.store.isLoading }
        } catch {
            older.cancel()
            sqlite3_exec(blocker, "ROLLBACK", nil, nil, nil)
            await older.value
            throw error
        }
        if action == "cancelled" {
            older.cancel()
        } else {
            fixture.controls.searchText = "kept "
        }
        let currentSearch = fixture.controls.searchText
        #expect(sqlite3_exec(blocker, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        await older.value

        #expect(fixture.controls.searchText == currentSearch)
        #expect(fixture.controls.filter == .history)
        #expect(fixture.controls.category == .text)
        #expect(fixture.store.items == [fixture.kept])
        await fixture.controls.apply(to: fixture.store)
        #expect(fixture.controls.searchText.isEmpty)
        #expect(fixture.controls.filter == .all)
        #expect(fixture.controls.category == .all)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ClipboardQueryFixtureError()
    }
}

@MainActor
private final class ClipboardQueryControls {
    var filter: ClipboardFilter = .all
    var searchText = ""
    var category: FileShelfCategory = .all
    var onSearchRead: (() -> Void)?

    func apply(to store: ClipboardHistoryStore) async {
        await ClipboardHistoryModuleView.updateQuery(
            store: store,
            filter: Binding(get: { self.filter }, set: { self.filter = $0 }),
            categoryFilter: Binding(get: { self.category }, set: { self.category = $0 }),
            searchText: Binding(get: {
                self.onSearchRead?()
                return self.searchText
            }, set: { self.searchText = $0 })
        )
        await store.waitUntilLoaded()
    }
}

@MainActor
private struct ClipboardQueryFixture {
    let directory: URL
    let storageURL: URL
    let store: ClipboardHistoryStore
    let controls = ClipboardQueryControls()
    let removed = ClipboardHistoryItem(content: .text("removed target"), lastCopiedAt: Date(timeIntervalSince1970: 2))
    let kept = ClipboardHistoryItem(content: .text("kept target"), lastCopiedAt: Date(timeIntervalSince1970: 1))

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-query-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let database = ClipboardHistoryDatabase(storageURL: storageURL)
        try database.flush([.upsert(removed, capacity: nil), .upsert(kept, capacity: nil)])
        store = ClipboardHistoryStore(storageURL: storageURL, persistenceDelay: .seconds(60))
    }

    func rejectRemovals() throws {
        var connection: OpaquePointer?
        guard sqlite3_open(storageURL.path, &connection) == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            throw ClipboardQueryFixtureError()
        }
        defer { sqlite3_close(connection) }
        guard sqlite3_exec(connection, """
            CREATE TRIGGER reject_removal BEFORE DELETE ON clipboard_history
            BEGIN SELECT RAISE(ABORT, 'injected query control failure'); END;
            """, nil, nil, nil) == SQLITE_OK else { throw ClipboardQueryFixtureError() }
    }

    func blockWrites() throws -> OpaquePointer {
        var connection: OpaquePointer?
        guard sqlite3_open(storageURL.path, &connection) == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            throw ClipboardQueryFixtureError()
        }
        guard sqlite3_exec(connection, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(connection)
            throw ClipboardQueryFixtureError()
        }
        return connection
    }

    func cleanup() {
        store.flushPendingChanges()
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct ClipboardQueryFixtureError: Error {}
