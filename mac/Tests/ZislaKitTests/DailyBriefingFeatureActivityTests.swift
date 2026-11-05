import AppKit
import Combine
import Foundation
import Testing
import XCTest
import ZislaCore
@testable import ZislaKit

@MainActor
struct DailyBriefingFeatureActivityTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("briefing-feature-activity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func shelfCountsAcceptedItemsAndContextNoteWritesAfterSuccessfulPersistence() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        var totals = DailyBriefingActivityTotals()
        store.onDailyBriefingActivity = { activity, count, seconds, _ in
            totals.record(activity, count: count, focusSeconds: seconds)
        }
        #expect(store.add(payloads: [.text("one"), .text("two")]) == 2)
        #expect(store.add(payloads: [.text("one"), .text("")]) == 0)
        let note = try #require(store.addContextNote("note", location: .desktop(displayID: "fixture", displayName: "Display")))
        #expect(store.updateContextNote(id: note.id, text: "updated") != nil)
        #expect(store.updateContextNote(id: note.id, text: "") == nil)
        store.remove(id: note.id)
        store.remove(id: note.id)
        #expect(totals.count(for: .shelfItemsAdded) == 3)
        #expect(totals.count(for: .noteCreated) == 1)
        #expect(totals.count(for: .noteSaved) == 1)
        #expect(totals.count(for: .noteDeleted) == 1)
        #expect(totals.count(for: .quickNoteCreated) == 0)
        _ = store.addContextNote("second", location: .desktop(displayID: "fixture", displayName: "Display"))
        _ = store.addContextNote("third", location: .desktop(displayID: "fixture", displayName: "Display"))
        store.removeAll()
        store.removeAll()
        #expect(totals.count(for: .noteDeleted) == 3)
    }

    @Test
    func failedShelfWritesDoNotProduceActivity() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("shelf.json")
        let store = FileShelfStore(storageURL: storage)
        let note = try #require(store.addContextNote("note", location: .desktop(displayID: "fixture", displayName: "Display")))
        try FileManager.default.removeItem(at: storage)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: false)
        var events: [DailyBriefingActivity] = []
        store.onDailyBriefingActivity = { activity, _, _, _ in events.append(activity) }
        #expect(store.add(payloads: [.text("another")]) == 0)
        #expect(store.updateContextNote(id: note.id, text: "changed") == nil)
        store.remove(id: note.id)
        store.removeAll()
        #expect(events.isEmpty)
        #expect(store.items.contains { $0.id == note.id })
    }

    @Test
    func imagePromiseAndScreenshotImportsCountEachCommittedItemOnce() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        var added = 0
        store.onDailyBriefingActivity = { activity, count, _, _ in
            if activity == .shelfItemsAdded { added += count }
        }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(store.importImage(png) == 1)
        #expect(store.importImage(Data()) == 0)
        let staged = directory.appendingPathComponent("promised.txt")
        try Data("fixture".utf8).write(to: staged)
        #expect(store.importPromisedFile(at: staged, from: directory) == 1)
        #expect(store.importPromisedFile(at: directory.deletingLastPathComponent(), from: directory) == 0)
        let metadata = ShelfScreenshotMetadata(source: .init(applicationName: "Fixture", bundleIdentifier: nil, processIdentifier: nil),
            isLongScreenshot: false, initialCaptureRect: .zero, captureRect: .zero, screenFrame: nil,
            displayIdentifier: nil, pixelWidth: 2, pixelHeight: 2)
        _ = try store.stashScreenshot(png: png, metadata: metadata)
        #expect(throws: (any Error).self) { try store.stashScreenshot(png: Data(), metadata: metadata) }
        #expect(added == 3)
    }

    @Test
    func pomodoroCountsNewFocusAndCompletionButExcludesResumeAndRest() throws {
        let suite = "BriefingPomodoroActivity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        let service = PomodoroService(notificationRequestHandler: { _ in }, defaults: defaults,
            completionSoundHandler: {}, now: { date })
        defer { service.stop() }
        service.notificationsMuted = true
        service.setFocusDuration(2)
        service.setRestDuration(1)
        var totals = DailyBriefingActivityTotals()
        service.onDailyBriefingActivity = { activity, count, seconds, _ in
            totals.record(activity, count: count, focusSeconds: seconds)
        }
        service.start()
        service.start()
        date = date.addingTimeInterval(0.5)
        service.pause()
        date = date.addingTimeInterval(20)
        service.start()
        date = date.addingTimeInterval(2)
        service.tick()
        service.tick()
        service.start()
        date = date.addingTimeInterval(2)
        service.tick()
        #expect(totals.count(for: .pomodoroStarted) == 1)
        #expect(totals.count(for: .pomodoroCompleted) == 1)
        #expect(totals.completedFocusSeconds == 2)
    }

    @Test(arguments: [false, true])
    func quickNotesCountSuccessfulBackendWritesAndExcludeWelcome(fails: Bool) async throws {
        let suite = "BriefingQuickNoteActivity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let note = NotesAppBridge.NoteSummary(id: "fixture", title: "Fixture", modifiedAt: .now)
        let service = QuickNotesService(welcomeDismissalDefaults: defaults,
            operations: .init(
                listNotes: { .success([note]) },
                readNote: { _ in .success(.init(plainText: "fixture", bodyHTML: "fixture", isPasswordProtected: false)) },
                writeNote: { _, _ in fails ? .failure(.failed("fixture failure")) : .success(()) },
                createNote: { _, _ in fails ? .failure(.failed("fixture failure")) : .success("created") },
                deleteNote: { _ in fails ? .failure(.failed("fixture failure")) : .success(()) }), saveDelay: .zero)
        var totals = DailyBriefingActivityTotals()
        service.onDailyBriefingActivity = { activity, count, seconds, _ in
            totals.record(activity, count: count, focusSeconds: seconds)
        }
        await service.refresh()
        if let welcome = service.welcomeNote { await service.delete(id: welcome.id) }
        #expect(totals.counts.isEmpty)
        #expect(await service.create(html: "created") == !fails)
        let saved = XCTestExpectation(description: "Fixture save finishes")
        let subscription = service.$isSaving.dropFirst().filter { !$0 }.prefix(1).sink { _ in saved.fulfill() }
        service.scheduleSave(id: note.id, html: "changed")
        #expect(await XCTWaiter.fulfillment(of: [saved], timeout: 5) == .completed)
        subscription.cancel()
        await service.delete(id: note.id)
        #expect(totals.count(for: .quickNoteCreated) == (fails ? 0 : 1))
        #expect(totals.count(for: .quickNoteSaved) == (fails ? 0 : 1))
        #expect(totals.count(for: .quickNoteDeleted) == (fails ? 0 : 1))
        #expect(totals.count(for: .noteCreated) == 0)
    }
}
