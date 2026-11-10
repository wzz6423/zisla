import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

@MainActor
struct MeetingNoteStoreTests {
    private let location = ContextNoteLocation.window(bundleIdentifier: "test.editor", applicationName: "Editor", title: "Original")
    private let first = CalendarEventIdentity(calendarIdentifier: "work", eventIdentifier: "meeting")

    @Test
    func meetingMetadataPersistsWithoutReplacingOriginalTextLocationTimeOrReminder() throws {
        try withStore { store, index in
            let date = Date(timeIntervalSince1970: 42)
            let note = try #require(store.addContextNote("  original\ntext  ", location: location, addedAt: date))
            let enabled = try #require(store.updateContextNote(id: note.id, text: note.text!, reminderInterval: .sixHours,
                at: Date(timeIntervalSince1970: 10_000)))
            let content = try Data(contentsOf: enabled.url)
            #expect(store.setMeeting(first, associated: true, withNote: note.id))
            var expected = enabled; expected.noteMeetingIDs = [first]
            #expect(store.items == [expected])
            #expect(FileShelfStore(storageURL: index).items == [expected])
            #expect(try Data(contentsOf: enabled.url) == content)
            let edited = try #require(store.updateContextNote(id: note.id, text: "edited"))
            #expect(edited.noteMeetingIDs == [first])
            #expect(edited.noteLocation == location)
            #expect(edited.addedAt == date)
            #expect(edited.noteReminderInterval == .sixHours)
            #expect(edited.nextNoteReminderAt == enabled.nextNoteReminderAt)
            #expect(FileShelfStore(storageURL: index).items == [edited])
        }
    }

    @Test
    func oneNoteCanLinkToMultipleMeetingsWithoutDuplicatingOrCombiningOccurrences() throws {
        try withStore { store, index in
            let note = try #require(store.addContextNote("original", location: location, meetingID: first))
            let second = CalendarEventIdentity(calendarIdentifier: "work", eventIdentifier: "series",
                occurrenceDate: Date(timeIntervalSince1970: 100))
            let third = CalendarEventIdentity(calendarIdentifier: "work", eventIdentifier: "series",
                occurrenceDate: Date(timeIntervalSince1970: 86_500))
            #expect(store.setMeeting(first, associated: true, withNote: note.id))
            #expect(store.items.first?.noteMeetingIDs == [first])
            #expect(store.setMeeting(second, associated: true, withNote: note.id))
            #expect(store.setMeeting(third, associated: true, withNote: note.id))
            #expect(store.items.first?.noteMeetingIDs == [first, second, third])
            #expect(store.setMeeting(second, associated: false, withNote: note.id))
            #expect(FileShelfStore(storageURL: index).items.first?.noteMeetingIDs == [first, third])
            #expect(store.items.count == 1)
            #expect(store.items.first?.text == "original")
        }
    }

    @Test
    func legacyNotesAndUnlinkingKeepTheOptionalMetadataFieldAbsent() throws {
        try withStore { store, index in
            let note = try #require(store.addContextNote("legacy", location: location))
            let records = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [[String: Any]])
            #expect(records.first?["noteMeetingIDs"] == nil)
            #expect(FileShelfStore(storageURL: index).items == [note])
            #expect(store.setMeeting(first, associated: true, withNote: note.id))
            #expect(store.setMeeting(first, associated: false, withNote: note.id))
            let unlinked = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [[String: Any]])
            #expect(unlinked.first?["noteMeetingIDs"] == nil)
            #expect(FileShelfStore(storageURL: index).items == [note])
        }
    }

    @Test
    func failedMetadataPersistenceLeavesTheSavedNoteAndItsFileUnchanged() throws {
        try withStore { store, index in
            let note = try #require(store.addContextNote("original", location: location, meetingID: first))
            let second = CalendarEventIdentity(calendarIdentifier: "work", eventIdentifier: "other")
            let content = try Data(contentsOf: note.url)
            let backup = index.deletingLastPathComponent().appendingPathComponent("backup.json")
            try FileManager.default.moveItem(at: index, to: backup)
            try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
            #expect(!store.setMeeting(first, associated: false, withNote: note.id))
            #expect(!store.setMeeting(second, associated: true, withNote: note.id))
            #expect(store.items == [note])
            #expect(store.errorDescription != nil)
            #expect(try Data(contentsOf: note.url) == content)
            try FileManager.default.removeItem(at: index)
            try FileManager.default.moveItem(at: backup, to: index)
            #expect(FileShelfStore(storageURL: index).items == [note])
            #expect(store.setMeeting(second, associated: true, withNote: note.id))
            #expect(store.errorDescription == nil)
            #expect(FileShelfStore(storageURL: index).items.first?.noteMeetingIDs == [first, second])
        }
    }

    @Test
    func ordinaryAndMissingItemsCannotAcquireMeetingMetadata() throws {
        try withStore { store, index in
            #expect(store.add(payloads: [.text("ordinary")]) == 1)
            let ordinary = try #require(store.items.first)
            let before = try Data(contentsOf: index)
            #expect(!store.setMeeting(first, associated: true, withNote: ordinary.id))
            #expect(!store.setMeeting(first, associated: true, withNote: UUID()))
            #expect(store.items == [ordinary])
            #expect(try Data(contentsOf: index) == before)
        }
    }

    private func withStore(_ body: (FileShelfStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-note-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = directory.appendingPathComponent("shelf.json")
        try body(FileShelfStore(storageURL: index), index)
    }
}
