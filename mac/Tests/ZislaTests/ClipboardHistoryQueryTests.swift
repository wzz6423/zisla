import AppKit
import Combine
import Foundation
import SQLite3
import SwiftUI
import Testing
import ZislaCore
@testable import Zisla
@testable import ZislaKit

@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClipboardHistoryQueryTests {
    @Test(arguments: ["filter", "search", "category", "grouping"])
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
            fixture.controls.grouping = dimension == "grouping" ? .sourceApp : .none
            await fixture.controls.apply(to: fixture.store)

            #expect(fixture.controls.filter == .all)
            #expect(fixture.controls.searchText.isEmpty)
            #expect(fixture.controls.category == .all)
            #expect(fixture.controls.grouping == .none)
            #expect(fixture.store.items == [fixture.kept])
            #expect(fixture.store.totalItemCount == 1)
            #expect(fixture.store.errorDescription?.contains("injected query control failure") == true)
            let completedLoads = startedLoads
            await fixture.controls.apply(to: fixture.store)
            #expect(startedLoads == completedLoads, "Restoring controls must not initiate another failed write")
        }
    }

    @Test(.serialized, arguments: [false, true])
    func failedQueriesShowTheirErrorInTheModuleUntilRetrySucceeds(emptyHistory: Bool) async throws {
        let fixture = try ClipboardQueryFixture()
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        try fixture.rejectRemovals()
        if emptyHistory {
            fixture.store.removeAllHistory()
        } else {
            fixture.store.remove(id: fixture.removed.id)
        }
        fixture.controls.filter = .history
        fixture.controls.searchText = "missing"
        fixture.controls.category = .text
        await fixture.controls.apply(to: fixture.store)
        let error = try #require(fixture.store.errorDescription)
        #expect(fixture.controls.filter == .all && fixture.controls.searchText.isEmpty && fixture.controls.category == .all)
        let expectedItems = emptyHistory ? [] : [fixture.kept]
        #expect(fixture.store.items == expectedItems)

        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: ClipboardHistoryModuleView(
            store: fixture.store,
            copyItem: { _ in },
            sendToQuickNote: { _ in }
        ).frame(width: 360, height: 440))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 440)
        await layout(host)

        #expect(accessibilityText(in: host).contains(error), "A failed query must explain why its controls were restored")
        #expect(fixture.store.items == expectedItems)
        #expect(fixture.store.errorDescription == error)
        try fixture.allowRemovals()
        fixture.store.updateQuery(scope: .all, searchText: "")
        await fixture.store.waitUntilLoaded()
        await layout(host)

        #expect(fixture.store.errorDescription == nil)
        #expect(!accessibilityText(in: host).contains(error), "The error must disappear once the pending write succeeds")
        #expect(fixture.store.items == expectedItems)
        #expect(host.window == nil)
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

    @Test(arguments: ["search", "grouping"])
    func changedInputIsNotSubmittedByAnOlderDebouncingTask(dimension: String) async throws {
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
        if dimension == "search" {
            fixture.controls.searchText = "kept "
        } else {
            fixture.controls.grouping = .sourceApp
        }
        await older.value

        #expect(fixture.store.items == [fixture.removed, fixture.kept], "An older debounce must not submit a newer input")
        #expect(fixture.store.currentQuery.grouping == .none)
        #expect(fixture.controls.searchText == (dimension == "search" ? "kept " : "removed"))
        await fixture.controls.apply(to: fixture.store)
        #expect(fixture.store.items == [dimension == "search" ? fixture.kept : fixture.removed])
        #expect(fixture.controls.searchText == (dimension == "search" ? "kept " : "removed"))
        #expect(fixture.store.currentQuery.grouping == (dimension == "grouping" ? .sourceApp : .none))
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["cancelled", "changed", "grouping"])
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
        fixture.controls.grouping = action == "grouping" ? .sourceApp : .none
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
        } else if action == "grouping" {
            fixture.controls.grouping = .none
        } else {
            fixture.controls.searchText = "kept "
        }
        let currentSearch = fixture.controls.searchText
        let currentGrouping = fixture.controls.grouping
        #expect(sqlite3_exec(blocker, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        await older.value

        #expect(fixture.controls.searchText == currentSearch)
        #expect(fixture.controls.filter == .history)
        #expect(fixture.controls.category == .text)
        #expect(fixture.controls.grouping == currentGrouping)
        #expect(fixture.store.items == [fixture.kept])
        await fixture.controls.apply(to: fixture.store)
        #expect(fixture.controls.searchText.isEmpty)
        #expect(fixture.controls.filter == .all)
        #expect(fixture.controls.category == .all)
        #expect(fixture.controls.grouping == .none)
    }

    @Test(.serialized, arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    func nativeGroupingButtonSharesTheCategoryRowAndPreservesDynamicNames(language: AppLanguage) async throws {
        let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previous
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        let firstApp = ClipboardSourceApp(bundleIdentifier: "test.a", name: "删除")
        let secondApp = ClipboardSourceApp(bundleIdentifier: "test.b", name: "删除")
        let records = [
            ClipboardHistoryItem(content: .text("first app favorite"), lastCopiedAt: Date(timeIntervalSince1970: 1),
                isPinned: true, sourceApp: firstApp),
            ClipboardHistoryItem(content: .text("first app history"), lastCopiedAt: Date(timeIntervalSince1970: 3),
                sourceApp: .init(bundleIdentifier: firstApp.bundleIdentifier, name: "Renamed Tool")),
            ClipboardHistoryItem(content: .text("second app history"), lastCopiedAt: Date(timeIntervalSince1970: 2), sourceApp: secondApp),
            ClipboardHistoryItem(content: .text("decomposed app history"), lastCopiedAt: Date(timeIntervalSince1970: 6),
                sourceApp: .init(bundleIdentifier: "test.e\u{301}", name: "Unicode Tool")),
            ClipboardHistoryItem(content: .text("composed app history"), lastCopiedAt: Date(timeIntervalSince1970: 5),
                sourceApp: .init(bundleIdentifier: "test.é", name: "Unicode Tool")),
            ClipboardHistoryItem(content: .text("unknown history"), lastCopiedAt: Date(timeIntervalSince1970: 4)),
            ClipboardHistoryItem(content: .text("older unknown history"), lastCopiedAt: Date(timeIntervalSince1970: 0)),
        ]
        let fixture = try ClipboardQueryFixture(items: records)
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: ClipboardHistoryModuleView(
            store: fixture.store, copyItem: { _ in }, sendToQuickNote: { _ in }
        ).frame(width: 620, height: 900)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        host.sizingOptions = []
        let window = NSPanel(contentRect: .init(x: -100_000, y: -100_000, width: 620, height: 900),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        await layout(host)
        #expect(groupHeadings(in: host).isEmpty)
        #expect(accessibilityText(in: host).contains { $0.contains("Renamed Tool · ") })
        for grouping in [ClipboardHistoryGrouping.sourceApp, .none] {
            let button = try #require(accessibilityObjects(in: host).first {
                $0.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                    && $0.value(forKey: "accessibilityIdentifier") as? String == "clipboardHistory.grouping"
            })
            let category = try #require(accessibilityObjects(in: host).first {
                $0.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                    && $0.value(forKey: "accessibilityIdentifier") as? String == "clipboardHistory.category." + FileShelfCategory.all.rawValue
            })
            #expect(button.value(forKey: "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue)
            #expect(button.value(forKey: "accessibilityLabel") as? String == AppLocalization.text("按应用"))
            let buttonFrame = try #require(button as? any NSAccessibilityElementProtocol).accessibilityFrame()
            let categoryFrame = try #require(category as? any NSAccessibilityElementProtocol).accessibilityFrame()
            #expect(buttonFrame.height > 0 && abs(buttonFrame.midY - categoryFrame.midY) < 1,
                "Application grouping must share the content category row")
            try #require(button.responds(to: NSSelectorFromString("accessibilityPerformPress")))
            _ = button.perform(NSSelectorFromString("accessibilityPerformPress"))
            try await waitUntil { fixture.store.currentQuery.grouping == grouping }
            await fixture.store.waitUntilLoaded()
            await layout(host)
            #expect(fixture.store.displayedQuery.grouping == grouping)
            #expect(button.value(forKey: "accessibilityValue") as? String == AppLocalization.text(grouping.title))
            if grouping == .sourceApp {
                #expect(groupHeadings(in: host) == ["删除", "删除", "Unicode Tool", "Unicode Tool", AppLocalization.text("未知应用")],
                    "App names are user data, and same-named bundles must have separate source headings")
                #expect(fixture.store.items == records)
            } else {
                #expect(groupHeadings(in: host).isEmpty && fixture.store.isShowingHistoryPreview)
            }
        }
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) } && !window.isKeyWindow)
    }

    @Test(arguments: [ClipboardHistoryGrouping.none, .sourceApp])
    func pendingGroupingKeepsDisplayedSectionsUntilTheQueryCommits(initial: ClipboardHistoryGrouping) async throws {
        let fixture = try ClipboardQueryFixture()
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        fixture.store.updateQuery(scope: .all, searchText: "", grouping: initial)
        await fixture.store.waitUntilLoaded()
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: ClipboardHistoryModuleView(
            store: fixture.store, copyItem: { _ in }, sendToQuickNote: { _ in }
        ).frame(width: 360, height: 440))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 440)
        await layout(host)
        try fixture.rejectRemovals()
        let blocker = try fixture.blockWrites()
        defer { sqlite3_close(blocker) }
        defer { sqlite3_exec(blocker, "ROLLBACK", nil, nil, nil) }
        fixture.store.remove(id: fixture.removed.id)
        let requested: ClipboardHistoryGrouping = initial == .none ? .sourceApp : .none
        fixture.store.updateQuery(scope: .all, searchText: "", grouping: requested)
        await layout(host)

        let expectedHeadings = initial == .sourceApp ? [AppLocalization.text("未知应用")] : []
        #expect(fixture.store.isLoading && fixture.store.currentQuery.grouping == requested)
        #expect(fixture.store.displayedQuery.grouping == initial && fixture.store.items == [fixture.kept])
        #expect(groupHeadings(in: host) == expectedHeadings)
        #expect(accessibilityObjects(in: host).contains {
            $0.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                && $0.value(forKey: "accessibilityIdentifier") as? String == "clipboardHistory.refreshing"
        })
        #expect(sqlite3_exec(blocker, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        await fixture.store.waitUntilLoaded()
        await layout(host)
        #expect(fixture.store.errorDescription != nil && fixture.store.displayedQuery.grouping == initial)
        #expect(groupHeadings(in: host) == expectedHeadings)
        try fixture.allowRemovals()
        fixture.store.updateQuery(scope: .all, searchText: "", grouping: requested)
        await fixture.store.waitUntilLoaded()
        await layout(host)
        #expect(fixture.store.errorDescription == nil && fixture.store.displayedQuery.grouping == requested)
        #expect(groupHeadings(in: host) == (requested == .sourceApp ? [AppLocalization.text("未知应用")] : []))
        #expect(host.window == nil)
    }

    @Test(.serialized, arguments: ["search", "category"])
    func filteredEmptyQueriesShowNoMatchingContent(dimension: String) async throws {
        let fixture = try ClipboardQueryFixture()
        defer { fixture.cleanup() }
        await fixture.store.waitUntilLoaded()
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: ClipboardHistoryModuleView(
            store: fixture.store, copyItem: { _ in }, sendToQuickNote: { _ in }
        ).frame(width: 360, height: 440))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 440)
        await layout(host)
        fixture.store.updateQuery(scope: .all, searchText: dimension == "search" ? "no match" : "",
            category: dimension == "category" ? .url : .all, grouping: .sourceApp)
        await fixture.store.waitUntilLoaded()
        await layout(host)

        #expect(fixture.store.items.isEmpty && fixture.store.errorDescription == nil)
        #expect(accessibilityText(in: host).contains(AppLocalization.text("无符合条件的内容")))
        #expect(!accessibilityText(in: host).contains(AppLocalization.text("复制内容后会自动记录")))
        #expect(host.window == nil)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ClipboardQueryFixtureError()
    }

    private func layout(_ host: NSView) async {
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }

    private func accessibilityText(in object: NSObject) -> [String] {
        accessibilityObjects(in: object).flatMap { object in
            ["accessibilityValue", "accessibilityLabel"].compactMap { key in
                object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) as? String : nil
            }
        }
    }

    private func accessibilityObjects(in object: NSObject) -> [NSObject] {
        let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
            ? object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
        return [object] + children.flatMap { accessibilityObjects(in: $0) }
    }

    private func groupHeadings(in object: NSObject) -> [String] {
        accessibilityObjects(in: object).compactMap { object in
            guard object.responds(to: NSSelectorFromString("accessibilityIdentifier")),
                  let id = object.value(forKey: "accessibilityIdentifier") as? String,
                  id.hasPrefix("clipboardHistory.sourceGroup.") else { return nil }
            return ["accessibilityValue", "accessibilityLabel"].compactMap { key in
                object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) as? String : nil
            }.first
        }
    }
}

@MainActor
private final class ClipboardQueryControls {
    var filter: ClipboardFilter = .all
    var searchText = ""
    var category: FileShelfCategory = .all
    var grouping: ClipboardHistoryGrouping = .none
    var onSearchRead: (() -> Void)?

    func apply(to store: ClipboardHistoryStore) async {
        await ClipboardHistoryModuleView.updateQuery(
            store: store,
            filter: Binding(get: { self.filter }, set: { self.filter = $0 }),
            categoryFilter: Binding(get: { self.category }, set: { self.category = $0 }),
            grouping: Binding(get: { self.grouping }, set: { self.grouping = $0 }),
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

    init(items: [ClipboardHistoryItem]? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-query-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storageURL = directory.appendingPathComponent("clipboard-history.sqlite")
        let database = ClipboardHistoryDatabase(storageURL: storageURL)
        try database.flush((items ?? [removed, kept]).map { .upsert($0, capacity: nil) })
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

    func allowRemovals() throws {
        var connection: OpaquePointer?
        guard sqlite3_open(storageURL.path, &connection) == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            throw ClipboardQueryFixtureError()
        }
        defer { sqlite3_close(connection) }
        guard sqlite3_exec(connection, "DROP TRIGGER reject_removal", nil, nil, nil) == SQLITE_OK else {
            throw ClipboardQueryFixtureError()
        }
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
