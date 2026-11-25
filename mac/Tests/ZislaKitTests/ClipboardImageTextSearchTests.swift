import Combine
import Foundation
import SQLite3
import Testing
import ZislaCore
@testable import ZislaKit

@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClipboardImageTextSearchTests {
    @Test
    func indexesCapturedImageWithoutChangingOriginalOrSource() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        let source = ClipboardSourceApp(bundleIdentifier: "com.example.capture", name: "Screenshot Source")
        #expect(store.record(.image(Data([1, 2, 3])), sourceApp: source))
        let original = try #require(store.items.first)
        try await recognizer.waitForCalls(1)
        await recognizer.complete(.success("  Search 中文 invoice  \n"))
        await store.waitUntilImageRecognitionFinished()
        store.updateQuery(scope: .all, searchText: "中文", category: .image)
        await store.waitUntilLoaded()
        let indexed = try #require(store.items.first)
        #expect(indexed.id == original.id)
        #expect(indexed.content == original.content)
        #expect(indexed.lastCopiedAt == original.lastCopiedAt)
        #expect(indexed.sourceApp == source)
        #expect(indexed.recognizedImageText == "Search 中文 invoice")
        #expect(store.categoryCounts == [.image: 1])
        let reopened = ClipboardHistoryStore(storageURL: fixture.url)
        await reopened.waitUntilLoaded()
        #expect(reopened.items == [indexed])
    }

    @Test
    func repeatedImagesReuseCompletedRecognitionAcrossPagesAndPinChanges() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        let content = ClipboardHistoryContent.image(Data([7]))
        #expect(store.record(content))
        try await recognizer.waitForCalls(1)
        #expect(store.record(content))
        await recognizer.complete(.success("archived words"))
        await store.waitUntilImageRecognitionFinished()
        let id = try #require(store.items.first?.id)
        store.setPinned(id: id, isPinned: true)
        store.flushPendingChanges()
        store.updateQuery(scope: .all, searchText: "missing")
        await store.waitUntilLoaded()
        #expect(store.items.isEmpty)
        #expect(store.record(content))
        await store.waitUntilImageRecognitionFinished()
        store.updateQuery(scope: .all, searchText: "archived")
        await store.waitUntilLoaded()
        #expect(store.items.count == 1)
        #expect(store.items.first?.isPinned == true)
        #expect(store.items.first?.recognizedImageText == "archived words")
        #expect(await recognizer.callCount == 1)
    }

    @Test
    func olderUnindexedImagesOnlyRunOnAnExplicitRequest() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let old = ClipboardHistoryItem(content: .image(Data([1])))
        try fixture.database.flush([.upsert(old, capacity: nil)])
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        #expect(store.imageRecognitionStates.isEmpty)
        #expect(await recognizer.callCount == 0)
        let task = Task { try await store.recognizeImageText(id: old.id) }
        try await recognizer.waitForCalls(1)
        await recognizer.complete(.success("legacy text"))
        #expect(try await task.value == "legacy text")
        await store.waitUntilImageRecognitionFinished()
        #expect(store.items.first?.recognizedImageText == "legacy text")
    }

    @Test
    func anEmptyResultIsPersistedAndNotRetried() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        #expect(store.record(.image(Data([1]))))
        try await recognizer.waitForCalls(1)
        await recognizer.complete(.success(" \n\t"))
        await store.waitUntilImageRecognitionFinished()
        let id = try #require(store.items.first?.id)
        #expect(try await store.recognizeImageText(id: id) == "")
        #expect(store.items.first?.recognizedImageText == "")
        #expect(await recognizer.callCount == 1)
        #expect(store.imageRecognitionError == nil)
    }

    @Test(arguments: ["remove", "clear", "prune", "capacity"])
    func lateRecognitionCannotRecreateRemovedImages(action: String) async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer, capacity: action == "capacity" ? 1 : nil)
        await store.waitUntilLoaded()
        #expect(store.record(.image(Data([1]))))
        let id = try #require(store.items.first?.id)
        try await recognizer.waitForCalls(1)
        switch action {
        case "remove": store.remove(id: id)
        case "clear": store.removeAllHistory()
        case "prune":
            #expect(await store.cleanupOldHistoryNow(policy: .sevenDays, now: Date(timeIntervalSince1970: 2_000_000)) == nil)
        default: #expect(store.record(.text("newer")))
        }
        store.flushPendingChanges()
        await recognizer.complete(.success("late hidden secret"))
        await store.waitUntilImageRecognitionFinished()
        let page = try await fixture.load(search: "late hidden secret")
        #expect(page.items.isEmpty)
        #expect(try await fixture.load().items.allSatisfy { $0.id != id })
        #expect(store.imageRecognitionStates.isEmpty)
    }

    @Test
    func offPageInFlightDuplicateKeepsNewIdentityAndRejectsOlderResult() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        let content = ClipboardHistoryContent.image(Data([3]))
        #expect(store.record(content))
        let olderID = try #require(store.items.first?.id)
        try await recognizer.waitForCalls(1)
        store.updateQuery(scope: .all, searchText: "unmatched")
        await store.waitUntilLoaded()
        #expect(store.record(content))
        store.flushPendingChanges()
        await recognizer.complete(.success("old result"))
        try await recognizer.waitForCalls(2)
        #expect(try await fixture.load(search: "old result").items.isEmpty)
        await recognizer.complete(.success("new result"))
        await store.waitUntilImageRecognitionFinished()
        let page = try await fixture.load(search: "new result")
        #expect(page.items.count == 1)
        #expect(page.items.first?.id != olderID)
        #expect(page.items.first?.content == content)
    }

    @Test
    func cancellingOneSameImageWaiterKeepsTheOtherRequestAlive() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        #expect(store.record(.image(Data([1]))))
        let id = try #require(store.items.first?.id)
        try await recognizer.waitForCalls(1)
        let first = Task { try await store.recognizeImageText(id: id) }
        let second = Task { try await store.recognizeImageText(id: id) }
        try await waitUntil { store.imageRecognitionWaiterCounts[id] == 2 }
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(store.imageRecognitionStates[id] == .processing)
        await recognizer.complete(.success("second request"))
        #expect(try await second.value == "second request")
        await store.waitUntilImageRecognitionFinished()
        #expect(await recognizer.callCount == 1)
    }

    @Test
    func cancelThenImmediateRetryCannotConsumeNewWaiters() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        #expect(store.record(.image(Data([1]))))
        let id = try #require(store.items.first?.id)
        try await recognizer.waitForCalls(1)
        store.cancelImageRecognition(id: id)
        let retry = Task { try await store.recognizeImageText(id: id) }
        await Task.yield()
        await recognizer.complete(.success("cancelled text"))
        try await recognizer.waitForCalls(2)
        await recognizer.complete(.success("retried text"))
        #expect(try await retry.value == "retried text")
        await store.waitUntilImageRecognitionFinished()
        #expect(store.items.first?.recognizedImageText == "retried text")
        #expect(store.imageRecognitionStates.isEmpty)
    }

    @Test
    func cancellingQueuedImageDoesNotCancelOtherImages() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        #expect(store.record(.image(Data([1]))))
        try await recognizer.waitForCalls(1)
        #expect(store.record(.image(Data([2]))))
        let cancelledID = try #require(store.items.first?.id)
        #expect(store.record(.image(Data([3]))))
        store.cancelImageRecognition(id: cancelledID)
        await recognizer.complete(.success("first"))
        try await recognizer.waitForCalls(2)
        #expect(await recognizer.inputs == [Data([1]), Data([3])])
        await recognizer.complete(.success("third"))
        await store.waitUntilImageRecognitionFinished()
        #expect(try await fixture.load().items.first(where: { $0.id == cancelledID })?.recognizedImageText == nil)
    }

    @Test
    func clearingHistoryRetainsRecognitionOfOffPagePinnedImages() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        #expect(store.recordPinned(.image(Data([1]))))
        let pinnedID = try #require(store.items.first?.id)
        try await recognizer.waitForCalls(1)
        store.updateQuery(scope: .all, searchText: "missing")
        await store.waitUntilLoaded()
        #expect(store.items.isEmpty)
        store.removeAllHistory()
        #expect(store.imageRecognitionStates[pinnedID] == .processing)
        await recognizer.complete(.success("pinned archive"))
        await store.waitUntilImageRecognitionFinished()
        #expect(try await fixture.load(search: "pinned archive", scope: .pinned).items.first?.id == pinnedID)
    }

    @Test
    func cancellingAnAlreadyIndexedRequestCannotReturnItsCachedText() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let indexed = ClipboardHistoryItem(content: .image(Data([1])), recognizedImageText: "cached")
        try fixture.database.flush([.upsert(indexed, capacity: nil)])
        let store = fixture.store(recognizer: ImageRecognitionGate())
        await store.waitUntilLoaded()
        let task = Task { try await store.recognizeImageText(id: indexed.id) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(store.items == [indexed])
    }

    @Test
    func simultaneousRecognitionAndPendingCapturesPersistBeforeIndexing() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        for index in 0..<8 { #expect(store.record(.image(Data([UInt8(index)])))) }
        for call in 1...8 {
            try await recognizer.waitForCalls(call)
            await recognizer.complete(.success("capture-\(call)"))
        }
        await store.waitUntilImageRecognitionFinished()
        #expect(store.imageRecognitionError == nil)
        #expect(try await fixture.load().items.count == 8)
        #expect(try await fixture.load().items.allSatisfy { $0.recognizedImageText != nil })
    }

    @Test
    func disabledLifecycleCancelsInFlightAndQueueWithoutScanningOnResume() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        #expect(store.record(.image(Data([1]))))
        try await recognizer.waitForCalls(1)
        #expect(store.record(.image(Data([2]))))
        store.setImageRecognitionEnabled(false)
        await recognizer.complete(.success("discarded"))
        await store.waitUntilImageRecognitionFinished()
        #expect(store.imageRecognitionStates.isEmpty)
        #expect(try await fixture.load().items.allSatisfy { $0.recognizedImageText == nil })
        store.setImageRecognitionEnabled(true)
        #expect(await recognizer.callCount == 1)
        #expect(store.imageRecognitionStates.isEmpty)
    }

    @Test
    func burstsKeepOneRecognitionWorkerAndBoundedPendingIdentifiers() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        #expect(store.record(.image(Data([0]))))
        try await recognizer.waitForCalls(1)
        for index in 1...520 {
            #expect(store.record(.image(Data("image-\(index)".utf8))))
        }
        #expect(store.imageRecognitionStates.count == 513)
        #expect(store.imageRecognitionStates.values.filter { $0 == .processing }.count == 1)
        #expect(await recognizer.callCount == 1)
        store.cancelImageRecognition()
        await recognizer.complete(.success("discarded"))
        await store.waitUntilImageRecognitionFinished()
        #expect(store.imageRecognitionStates.isEmpty)
        #expect(try await fixture.load().items.allSatisfy { $0.recognizedImageText == nil })
    }

    @Test
    func recognitionFailureLeavesOriginalAndCanBeRetried() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        #expect(store.record(.image(Data([1]))))
        let original = try #require(store.items.first)
        try await recognizer.waitForCalls(1)
        await recognizer.complete(.failure(CocoaError(.fileReadCorruptFile)))
        await store.waitUntilImageRecognitionFinished()
        #expect(store.items == [original])
        #expect(store.imageRecognitionError?.id == original.id)
        let retry = Task { try await store.recognizeImageText(id: original.id) }
        try await recognizer.waitForCalls(2)
        await recognizer.complete(.success("recovered"))
        #expect(try await retry.value == "recovered")
        await store.waitUntilImageRecognitionFinished()
        #expect(store.imageRecognitionError == nil)
    }

    @Test
    func databaseWriteFailureDoesNotExposeUnpersistedSearchText() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        #expect(store.record(.image(Data([1]))))
        let original = try #require(store.items.first)
        try await recognizer.waitForCalls(1)
        try fixture.execute("CREATE TRIGGER reject_ocr BEFORE UPDATE OF image_text ON clipboard_history BEGIN SELECT RAISE(ABORT, 'injected OCR storage failure'); END")
        await recognizer.complete(.success("uncommitted secret"))
        await store.waitUntilImageRecognitionFinished()
        #expect(store.items == [original])
        #expect(store.imageRecognitionError?.message.contains("injected OCR storage failure") == true)
        #expect(try await fixture.load(search: "uncommitted secret").items.isEmpty)
        try fixture.execute("DROP TRIGGER reject_ocr")
        let retry = Task { try await store.recognizeImageText(id: original.id) }
        try await recognizer.waitForCalls(2)
        await recognizer.complete(.success("stored text"))
        #expect(try await retry.value == "stored text")
        await store.waitUntilImageRecognitionFinished()
        #expect(try await fixture.load(search: "stored text").items.count == 1)
    }

    @Test
    func queriesTreatSqlMetacharactersLiterallyAndKeepImageSourceFilters() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let source = ClipboardSourceApp(bundleIdentifier: "com.example.ocr", name: "图像编辑器")
        let original = ClipboardHistoryItem(content: .image(Data([1])), isPinned: true, sourceApp: source,
                                            recognizedImageText: "Invoice 中文 100% unit_name C:\\folder ' OR 1=1; -- 👩🏽‍💻 café")
        let other = ClipboardHistoryItem(content: .image(Data([2])), recognizedImageText: "unrelated")
        try fixture.database.flush([.upsert(original, capacity: nil), .upsert(other, capacity: nil),
                                    .upsert(ClipboardHistoryItem(content: .text("unrelated")), capacity: nil)])
        for term in ["invoice", "中文", "%", "_", "\\", "' OR 1=1; --", "👩🏽‍💻", "café", "图像编辑器", "com.example.ocr"] {
            #expect(try await fixture.load(search: term, category: .image).items == [original], "Literal query failed: \(term)")
        }
        #expect(try await fixture.load(search: "中文", category: .text).items.isEmpty)
        #expect(try await fixture.load(search: "中文", scope: .history).items.isEmpty)
        #expect(try await fixture.load(search: "中文", scope: .pinned).items == [original])
    }

    @Test
    func legacyMigrationAddsNullableIndexWithoutChangingImage() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let id = UUID()
        try fixture.execute("""
        CREATE TABLE clipboard_history (
            id TEXT PRIMARY KEY NOT NULL, content_type INTEGER NOT NULL, text_value TEXT,
            image_data BLOB, last_copied_at REAL NOT NULL, is_pinned INTEGER NOT NULL
        );
        INSERT INTO clipboard_history VALUES ('\(id.uuidString)', 1, NULL, X'0102', 0, 1);
        """)
        let page = try await fixture.load()
        #expect(page.items.first?.id == id)
        #expect(page.items.first?.content == .image(Data([1, 2])))
        #expect(page.items.first?.recognizedImageText == nil)
        #expect(try fixture.scalar("PRAGMA user_version") == 7)
        #expect(try fixture.scalar("SELECT COUNT(*) FROM clipboard_history WHERE image_text IS NULL") == 1)
    }

    @Test
    func replacingDifferentImageBytesWithIdenticalOCRRetainsInheritedIndex() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let first = ClipboardHistoryItem(content: .image(Data([1])), recognizedImageText: "TOTAL")
        let second = ClipboardHistoryItem(content: .image(Data([2])), recognizedImageText: "TOTAL")
        try fixture.database.flush([.upsert(first, capacity: nil), .upsert(second, capacity: nil)])
        let replacement = ClipboardHistoryItem(id: first.id, content: second.content)
        try fixture.database.flush([.upsert(replacement, capacity: nil)])
        let page = try await fixture.load(search: "TOTAL", category: .image)
        #expect(page.items.count == 1)
        #expect(page.items.first?.id == first.id)
        #expect(page.items.first?.content == second.content)
        #expect(page.items.first?.recognizedImageText == "TOTAL")
        try fixture.execute("UPDATE clipboard_history SET image_data = X'03'")
        #expect(try await fixture.load(search: "TOTAL").items.isEmpty)
    }

    @Test(arguments: [("CAFÉ", "café"), ("É", "e\u{301}"), ("Σ", "σ"), ("ÜBER 中文", "über 中文")])
    func unicodeOCRSearchMatchesPagesCountsAndOptimisticRecopies(text: String, query: String) async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let content = ClipboardHistoryContent.image(Data([1]))
        let original = ClipboardHistoryItem(content: content, sourceApp: .init(bundleIdentifier: "test.source", name: query), recognizedImageText: text)
        try fixture.database.flush([.upsert(original, capacity: nil)])
        let store = fixture.store(recognizer: ImageRecognitionGate())
        await store.waitUntilLoaded()
        store.updateQuery(scope: .all, searchText: query, category: .image)
        await store.waitUntilLoaded()
        #expect(store.items.first?.id == original.id)
        #expect(store.record(content, sourceApp: .init(bundleIdentifier: "test.new", name: "Different source")))
        #expect(store.items.first?.id == original.id)
        store.flushPendingChanges()
        store.updateQuery(scope: .all, searchText: query + " ", category: .image, grouping: .sourceApp)
        await store.waitUntilLoaded()
        #expect(store.items.count == 1)
        #expect(store.totalItemCount == 1)
        #expect(store.categoryCounts == [.image: 1])
        #expect(store.items.first?.recognizedImageText == text)
        let page = try await fixture.load(search: query, category: .image)
        #expect(page.items.map(\.id) == [original.id])
    }

    @Test
    func clearHistoryRejectsLateOffPageUnpinnedResultsBeforeDeletionIsFlushed() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let recognizer = ImageRecognitionGate()
        let store = fixture.store(recognizer: recognizer)
        await store.waitUntilLoaded()
        #expect(store.record(.image(Data([1]))))
        let id = try #require(store.items.first?.id)
        try await recognizer.waitForCalls(1)
        store.updateQuery(scope: .all, searchText: "missing")
        await store.waitUntilLoaded()
        let request = Task { try await store.recognizeImageText(id: id) }
        try await waitUntil { store.imageRecognitionWaiterCounts[id] == 1 }
        store.removeAllHistory()
        await recognizer.complete(.success("cleared OCR"))
        await #expect(throws: CancellationError.self) { try await request.value }
        await store.waitUntilImageRecognitionFinished()
        store.flushPendingChanges()
        #expect(try await fixture.load().items.isEmpty)
    }

    @Test
    func deduplicationAndPinUpdatesRetainThePersistedImageIndex() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let old = ClipboardHistoryItem(content: .image(Data([9])), isPinned: true, recognizedImageText: "retained OCR")
        var incoming = ClipboardHistoryItem(content: old.content)
        try fixture.database.flush([.upsert(old, capacity: nil), .upsert(incoming, capacity: nil)])
        let deduplicated = try #require(try await fixture.load().items.first)
        #expect(deduplicated.id == incoming.id)
        #expect(deduplicated.isPinned)
        #expect(deduplicated.recognizedImageText == "retained OCR")
        incoming.isPinned = true
        try fixture.database.flush([.upsert(incoming, capacity: nil)])
        #expect(try await fixture.load().items.first?.recognizedImageText == "retained OCR")
    }

    @Test
    func legacyWriterKeepsSameImageTextButInvalidatesChangedImage() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let item = ClipboardHistoryItem(content: .image(Data([1])), recognizedImageText: "old text")
        try fixture.database.flush([.upsert(item, capacity: nil)])
        try fixture.execute("UPDATE clipboard_history SET source_app_name = 'New source', image_data = X'01'")
        #expect(try await fixture.load(search: "old text").items.count == 1)
        try fixture.execute("UPDATE clipboard_history SET image_data = X'02'")
        #expect(try await fixture.load(search: "old text").items.isEmpty)
        #expect(try await fixture.load().items.first?.recognizedImageText == nil)
        #expect(try fixture.scalar("PRAGMA user_version") == 7)
    }

    @Test
    func cancelledDatabaseCommitCannotWriteRecognizedText() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let item = ClipboardHistoryItem(content: .image(Data([1])))
        try fixture.database.flush([.upsert(item, capacity: nil)])
        let cancellation = ClipboardImageRecognitionCancellation()
        cancellation.cancel()
        await #expect(throws: CancellationError.self) {
            try await fixture.database.saveRecognizedImageText("cancelled", id: item.id, imageData: Data([1]), cancellation: cancellation)
        }
        #expect(try await fixture.load().items == [item])
    }

    @Test
    func lateBytesTokenCannotIndexAReplacementUnderTheSameIdentifier() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let id = UUID()
        let old = ClipboardHistoryItem(id: id, content: .image(Data([1])))
        let replacement = ClipboardHistoryItem(id: id, content: .image(Data([2])))
        try fixture.database.flush([.upsert(old, capacity: nil), .upsert(replacement, capacity: nil)])
        #expect(try await !fixture.database.saveRecognizedImageText("old text", id: id, imageData: Data([1]), cancellation: ClipboardImageRecognitionCancellation()))
        #expect(try await fixture.load().items == [replacement])
        #expect(try await fixture.load(search: "old text").items.isEmpty)
    }

    @Test
    func seededUnicodeAndSqlShapedCorpusRoundTripsThroughImageSearch() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        var seed: UInt64 = 0x434C49504F4352
        let units = ["A", "é", "e\u{301}", "中文", "👩🏽‍💻", "%_\\", "' OR 1=1; --", "\n"]
        let corpus = (0..<24).map { index -> ClipboardHistoryItem in
            var text = "marker-\(index)-end "
            for _ in 0..<6 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                text += units[Int(seed % UInt64(units.count))]
            }
            return ClipboardHistoryItem(content: .image(Data("fixture-\(index)".utf8)), recognizedImageText: text)
        }
        try fixture.database.flush(corpus.map { .upsert($0, capacity: nil) })
        for (index, original) in corpus.enumerated() {
            let found = try await fixture.load(search: "marker-\(index)-end", category: .image)
            #expect(found.items == [original])
            #expect(found.items.first?.recognizedImageText?.utf8.elementsEqual(original.recognizedImageText!.utf8) == true)
        }
        #expect(try await fixture.load().totalCount == corpus.count)
    }

    @Test
    func migrationFailureRollsBackNewColumnAndPreservesLegacyRecords() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let id = UUID()
        try fixture.execute("""
        CREATE TABLE clipboard_history (
            id TEXT PRIMARY KEY NOT NULL, content_type INTEGER NOT NULL, text_value TEXT,
            image_data BLOB, last_copied_at REAL NOT NULL, is_pinned INTEGER NOT NULL
        );
        INSERT INTO clipboard_history VALUES ('\(id.uuidString)', 1, NULL, X'0102', 0, 1);
        PRAGMA user_version = 6;
        """)
        let database = ClipboardHistoryDatabase(storageURL: fixture.url, connectionObserver: { handle in
            sqlite3_set_authorizer(handle, { _, action, first, _, _, _ in
                if action == SQLITE_CREATE_TRIGGER, let first,
                   String(cString: first) == "clipboard_history_invalidate_image_text" { return SQLITE_DENY }
                return SQLITE_OK
            }, nil)
        })
        await #expect(throws: (any Error).self) {
            try await database.loadPage(scope: .all, searchText: "", category: .all, offset: 0, limit: 10)
        }
        #expect(try fixture.scalar("PRAGMA user_version") == 6)
        #expect(try fixture.scalar("SELECT COUNT(*) FROM clipboard_history") == 1)
        #expect(try fixture.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_history') WHERE name = 'image_text'") == 0)
        let recovered = try await fixture.load()
        #expect(recovered.items.first?.id == id)
        #expect(recovered.items.first?.content == .image(Data([1, 2])))
        #expect(try fixture.scalar("PRAGMA user_version") == 7)
    }

    @Test
    func oldJsonHistoryItemDecodesWithNoRecognitionIndex() throws {
        let original = ClipboardHistoryItem(content: .image(Data([1])))
        let encoded = try JSONEncoder().encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "recognizedImageText")
        let decoded = try JSONDecoder().decode(ClipboardHistoryItem.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == original)
        #expect(decoded.recognizedImageText == nil)
    }

    @Test(arguments: [false, true])
    func recopiedOffPageFavoriteKeepsInheritedPinWhileHistoryClears(clearBeforeLoad: Bool) async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let content = ClipboardHistoryContent.image(Data([1]))
        let original = ClipboardHistoryItem(content: content, isPinned: true)
        try fixture.database.flush([.upsert(original, capacity: nil)])
        let gate = ImageRecognitionGate()
        let store = fixture.store(recognizer: gate)
        await store.waitUntilLoaded()
        store.updateQuery(scope: .history, searchText: "")
        await store.waitUntilLoaded()
        #expect(store.items.isEmpty)
        store.record(content)
        if clearBeforeLoad { store.removeAllHistory() }
        try await gate.waitForCalls(1)
        if !clearBeforeLoad { store.removeAllHistory() }
        await gate.complete(.success("inherited favorite"))
        await store.waitUntilImageRecognitionFinished()
        store.flushPendingChanges()
        let retained = try await fixture.load(search: "inherited favorite", scope: .pinned)
        #expect(retained.items.count == 1)
        #expect(retained.items.first?.content == content)
        #expect(retained.items.first?.id != original.id)
    }

    @Test
    func disabledMetadataLookupRejectsPinnedImagesWithoutLeavingWaiters() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let item = ClipboardHistoryItem(content: .image(Data([1])), isPinned: true)
        try fixture.database.flush([.upsert(item, capacity: nil)])
        let recognition = ImageRecognitionGate()
        let metadata = ImagePinLookupGate()
        let store = fixture.store(recognizer: recognition)
        await store.waitUntilLoaded()
        store.updateQuery(scope: .history, searchText: "")
        await store.waitUntilLoaded()
        store.imagePinnedLookup = { _ in await metadata.load() }
        let request = Task { try await store.recognizeImageText(id: item.id) }
        try await waitUntil { await metadata.isLoading }
        store.setImageRecognitionEnabled(false)
        await metadata.complete(true)
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(store.imageRecognitionWaiterCounts.isEmpty)
        #expect(store.imageRecognitionStates.isEmpty)
        #expect(await recognition.callCount == 0)
    }

    @Test(arguments: ["disable", "clear"])
    func offPageMetadataLookupCannotRestartRecognitionAfterLifecycleChanges(action: String) async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let item = ClipboardHistoryItem(content: .image(Data([1])))
        try fixture.database.flush([.upsert(item, capacity: nil)])
        let recognition = ImageRecognitionGate()
        let metadata = ImagePinLookupGate()
        let store = fixture.store(recognizer: recognition)
        await store.waitUntilLoaded()
        store.updateQuery(scope: .all, searchText: "missing")
        await store.waitUntilLoaded()
        store.imagePinnedLookup = { _ in await metadata.load() }
        let request = Task { try await store.recognizeImageText(id: item.id) }
        try await waitUntil { await metadata.isLoading }
        if action == "disable" { store.setImageRecognitionEnabled(false) }
        else { store.removeAllHistory() }
        await metadata.complete(false)
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(store.imageRecognitionWaiterCounts.isEmpty)
        #expect(store.imageRecognitionStates.isEmpty)
        #expect(await recognition.callCount == 0)
    }

    @Test(arguments: [false, true])
    func clearHistoryRejectsOffPageRequestsBeforeTheyRegister(startBeforeClear: Bool) async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let item = ClipboardHistoryItem(content: .image(Data([1])))
        try fixture.database.flush([.upsert(item, capacity: nil)])
        let gate = ImageRecognitionGate()
        let store = fixture.store(recognizer: gate)
        await store.waitUntilLoaded()
        store.updateQuery(scope: .all, searchText: "missing")
        await store.waitUntilLoaded()
        let request: Task<String, any Error>
        if startBeforeClear {
            request = Task { try await store.recognizeImageText(id: item.id) }
            store.removeAllHistory()
        } else {
            store.removeAllHistory()
            request = Task { try await store.recognizeImageText(id: item.id) }
        }
        do {
            _ = try await request.value
            Issue.record("A cleared image must not return recognized text")
        } catch {
            #expect(error is CancellationError || (error as? CocoaError)?.code == .fileReadNoSuchFile)
        }
        await store.waitUntilImageRecognitionFinished()
        #expect(await gate.callCount == 0)
        #expect(store.imageRecognitionStates.isEmpty)
    }

    @Test
    func pinningAndUnpinningOffPageRecognitionUsesCurrentFavoriteStateOnClear() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let gate = ImageRecognitionGate()
        let store = fixture.store(recognizer: gate)
        await store.waitUntilLoaded()
        #expect(store.recordPinned(.image(Data([1]))))
        let id = try #require(store.items.first?.id)
        try await gate.waitForCalls(1)
        store.setPinned(id: id, isPinned: false)
        store.updateQuery(scope: .all, searchText: "missing")
        await store.waitUntilLoaded()
        let request = Task { try await store.recognizeImageText(id: id) }
        try await waitUntil { store.imageRecognitionWaiterCounts[id] == 1 }
        store.removeAllHistory()
        await #expect(throws: CancellationError.self) { try await request.value }
        await gate.complete(.success("discard unpinned"))
        await store.waitUntilImageRecognitionFinished()
        store.flushPendingChanges()
        #expect(try await fixture.load().items.isEmpty)
    }

    @Test(arguments: [false, true])
    func disabledOrUnavailableRecognitionKeepsNoPerImageMetadata(unavailable: Bool) async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let store = unavailable ? ClipboardHistoryStore(storageURL: fixture.url) : fixture.store(recognizer: ImageRecognitionGate())
        await store.waitUntilLoaded()
        if !unavailable { store.setImageRecognitionEnabled(false) }
        for index in 0..<32 {
            store.recordPinned(.image(Data("disabled-image-\(index)".utf8)))
        }
        #expect(store.imageRecognitionMetadataCount == 0)
        #expect(store.imageRecognitionStates.isEmpty)
        #expect(store.imageRecognitionWaiterCounts.isEmpty)
        store.flushPendingChanges()
    }

    @Test
    func rejectingAnOverCapacityManualRequestReleasesItsMetadata() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let gate = ImageRecognitionGate()
        let records = (0..<514).map { ClipboardHistoryItem(content: .image(Data("manual-capacity-\($0)".utf8)), isPinned: true) }
        try fixture.database.flush(records.map { .upsert($0, capacity: nil) })
        let store = fixture.store(recognizer: gate)
        await store.waitUntilLoaded()
        var requests: [Task<String, any Error>] = []
        for record in records.prefix(513) {
            requests.append(Task { try await store.recognizeImageText(id: record.id) })
            try await waitUntil { store.imageRecognitionWaiterCounts[record.id] == 1 }
        }
        try await gate.waitForCalls(1)
        #expect(store.imageRecognitionStates.count == 513)
        let rejected = Task { try await store.recognizeImageText(id: records[513].id) }
        await #expect(throws: CocoaError(.fileReadTooLarge)) { try await rejected.value }
        #expect(store.imageRecognitionMetadataCount == 513)
        #expect(store.imageRecognitionWaiterCounts.count == 513)
        store.cancelImageRecognition()
        await gate.complete(.success("discarded"))
        for request in requests { await #expect(throws: CancellationError.self) { try await request.value } }
        await store.waitUntilImageRecognitionFinished()
        #expect(store.imageRecognitionMetadataCount == 0)
        #expect(store.imageRecognitionWaiterCounts.isEmpty)
        #expect(store.imageRecognitionStates.isEmpty)
    }

    @Test
    func callThresholdWaitsCancelWithoutBlockingLaterRecognition() async throws {
        let gate = ImageRecognitionGate()
        let cancelled = Task { try await gate.waitForCalls(2) }
        try await waitUntil { await gate.pendingCallWaiterCount == 1 }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await gate.pendingCallWaiterCount == 0)
        let recognition = Task { try await gate.recognize(Data([1])) }
        try await gate.waitForCalls(1)
        await gate.complete(.success("still available"))
        #expect(try await recognition.value == "still available")
        try await gate.waitForCalls(1)
        #expect(await gate.pendingCallWaiterCount == 0)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<256 {
            try Task.checkCancellation()
            if await condition() { return }
            await Task.yield()
        }
        throw CocoaError(.coderReadCorrupt)
    }

    @Test
    func storedImageBytesAreRejectedBeforeLoadingOverTheConfiguredLimit() async throws {
        let fixture = try ImageHistoryFixture()
        defer { fixture.cleanup() }
        let item = ClipboardHistoryItem(content: .image(Data([1, 2, 3, 4])))
        try fixture.database.flush([.upsert(item, capacity: nil)])
        #expect(try await fixture.database.loadImageForRecognition(id: item.id, maximumBytes: 3) == nil)
        let loaded = try #require(try await fixture.database.loadImageForRecognition(id: item.id, maximumBytes: 4))
        #expect(loaded.data == Data([1, 2, 3, 4]))
        #expect(loaded.text == nil)
    }
}

private actor ImageRecognitionGate {
    private(set) var inputs: [Data] = []
    private var continuation: CheckedContinuation<String, any Error>?
    private var callWaiters: [UUID: (count: Int, continuation: CheckedContinuation<Void, any Error>)] = [:]
    var callCount: Int { inputs.count }
    var pendingCallWaiterCount: Int { callWaiters.count }

    func recognize(_ data: Data) async throws -> String {
        inputs.append(data)
        for id in Array(callWaiters.keys) where inputs.count >= callWaiters[id]!.count {
            callWaiters.removeValue(forKey: id)?.continuation.resume()
        }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitForCalls(_ count: Int) async throws {
        try Task.checkCancellation()
        if inputs.count >= count { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                callWaiters[id] = (count, continuation)
            }
        } onCancel: {
            Task { await self.cancelCallWaiter(id: id) }
        }
        try Task.checkCancellation()
    }

    private func cancelCallWaiter(id: UUID) {
        callWaiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }

    func complete(_ result: Result<String, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

private actor ImagePinLookupGate {
    private var continuation: CheckedContinuation<Bool?, Never>?
    private(set) var isLoading = false

    func load() async -> Bool? {
        isLoading = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func complete(_ isPinned: Bool) {
        continuation?.resume(returning: isPinned)
        continuation = nil
    }
}

@MainActor
private final class ImageHistoryFixture {
    let directory: URL
    let url: URL
    let database: ClipboardHistoryDatabase

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-image-history-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        url = directory.appendingPathComponent("history.sqlite")
        database = ClipboardHistoryDatabase(storageURL: url)
    }

    func store(recognizer: ImageRecognitionGate, capacity: Int? = nil) -> ClipboardHistoryStore {
        var timestamp: TimeInterval = 0
        return ClipboardHistoryStore(storageURL: url, capacity: capacity, persistenceDelay: .seconds(60),
                                     now: {
                                         timestamp += 1
                                         return Date(timeIntervalSince1970: timestamp)
                                     }, imageTextRecognizer: { try await recognizer.recognize($0) })
    }

    func load(search: String = "", category: FileShelfCategory = .all, scope: ClipboardHistoryScope = .all) async throws -> ClipboardHistoryPage {
        try await database.loadPage(scope: scope, searchText: search, category: category, offset: 0, limit: 1024)
    }

    func execute(_ sql: String) throws {
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        var message: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &message)
        defer { sqlite3_free(message) }
        guard result == SQLITE_OK else { throw NSError(domain: "ImageHistoryFixture", code: Int(result), userInfo: [NSLocalizedDescriptionKey: message.map { String(cString: $0) } ?? "SQL failed"]) }
    }

    func scalar(_ sql: String) throws -> Int? {
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_INTEGER else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
