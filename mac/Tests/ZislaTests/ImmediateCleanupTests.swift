import Combine
import Foundation
import SQLite3
import Testing
import ZislaCore
@testable import ZislaKit

@testable import Zisla

@MainActor
struct ImmediateCleanupTests {
    @Test
    func progressAndResultsFollowLanguageChangesWithoutRepeatingCleanup() {
        for (status, english, chinese, arabic) in [
            (AppModel.CleanupStatus.cleaning, "Cleaning", "正在清理", "جارٍ التنظيف"),
            (.completed, "Cleanup complete", "清理完成", "اكتمل التنظيف"),
            (.failed("fixture error"), "Cleanup failed: fixture error", "清理失败：fixture error", "فشل التنظيف: \u{2068}fixture error\u{2069}"),
        ] {
            #expect(status.message(locale: AppLanguage.english.locale) == english)
            #expect(status.message(locale: AppLanguage.simplifiedChinese.locale) == chinese)
            #expect(status.message(locale: AppLanguage.arabic.locale) == arabic)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func availabilityFollowsEnabledCleanupItems(systemEnabled: Bool, clipboardEnabled: Bool) {
        var settings = FeatureSettings(systemMonitorEnabled: systemEnabled, clipboardHistoryEnabled: clipboardEnabled)
        #expect(!AppModel.canCleanNow(settings: settings))
        settings.systemCleanupPolicy = .sevenDays
        #expect(AppModel.canCleanNow(settings: settings) == systemEnabled)
        settings.systemCleanupPolicy = .never
        settings.clipboardHistoryCleanupPolicy = .sevenDays
        #expect(AppModel.canCleanNow(settings: settings) == clipboardEnabled)
        settings.clipboardHistoryCleanupPolicy = .never
        settings.trashCleanupPolicy = .sevenDays
        #expect(AppModel.canCleanNow(settings: settings))
        settings.trashCleanupPolicy = .never
        settings.voiceInputEnabled = false
        settings.voiceRecordingCleanupPolicy = .sevenDays
        #expect(AppModel.canCleanNow(settings: settings))
    }

    @Test(arguments: ["all", "disabled", "never", "clipboard-failure", "voice-failure", "system-failure", "trash-failure"])
    func cleanupUsesConfiguredItemsAndPreservesUnexpiredDataAndSchedule(mode: String) async throws {
        let fixture = try ImmediateCleanupFixture()
        defer { fixture.removeFiles() }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        let clipboardURL = fixture.directory.appendingPathComponent("clipboard.sqlite")
        let expired = ClipboardHistoryItem(content: .text("expired"), lastCopiedAt: cutoff.addingTimeInterval(-1))
        let pinned = ClipboardHistoryItem(content: .text("pinned"), lastCopiedAt: .distantPast, isPinned: true)
        let current = ClipboardHistoryItem(content: .text("at cutoff"), lastCopiedAt: cutoff)
        let database = ClipboardHistoryDatabase(storageURL: clipboardURL)
        try database.flush([expired, pinned, current].map { .upsert($0, capacity: nil) })
        let clipboard = ClipboardHistoryStore(storageURL: clipboardURL, persistenceDelay: .seconds(60))
        await clipboard.waitUntilLoaded()
        let metadata = fixture.directory.appendingPathComponent("voice.json")
        let recordings = fixture.directory.appendingPathComponent("recordings")
        let voice = VoiceHistoryStore(storageURL: metadata, recordingsDirectory: recordings)
        let expiredID = UUID()
        let currentID = UUID()
        for (id, date) in [(expiredID, cutoff.addingTimeInterval(-1)), (currentID, cutoff)] {
            let url = voice.recordingURL(for: id)
            try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
            try Data("fixture audio".utf8).write(to: url)
            #expect(voice.record(VoiceRecordingResult(id: id, audioFileURL: url, transcript: "retained text",
                duration: 1, createdAt: date)))
        }
        if mode == "clipboard-failure" {
            try fixture.executeSQL("""
                CREATE TRIGGER fail_delete BEFORE DELETE ON clipboard_history
                BEGIN SELECT RAISE(ABORT, 'clipboard fixture failure'); END;
                """, at: clipboardURL)
        }
        if mode == "voice-failure" {
            try fixture.executeSQL("""
                CREATE TRIGGER fail_save BEFORE UPDATE ON voice_history_state
                BEGIN SELECT RAISE(ABORT, 'voice fixture failure'); END;
                """, at: metadata.deletingPathExtension().appendingPathExtension("sqlite"))
        }
        let service = fixture.makeService(systemFails: mode == "system-failure", trashFails: mode == "trash-failure")
        defer { service.stop() }
        var settings = FeatureSettings(systemMonitorEnabled: mode != "disabled",
            systemCleanupPolicy: mode == "never" ? .never : .sevenDays,
            trashCleanupPolicy: mode == "never" ? .never : .sevenDays,
            clipboardHistoryEnabled: mode != "disabled",
            clipboardHistoryCleanupPolicy: mode == "never" ? .never : .sevenDays)
        settings.voiceRecordingCleanupPolicy = mode == "never" ? .never : .sevenDays
        service.apply(settings: settings)
        let deadlines = fixture.timers.map(\.fireDate)
        let storedSystemDate = fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date
        let storedTrashDate = fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date

        let message = await AppModel.cleanConfiguredItems(settings: settings, systemCleanup: service,
            clipboardHistory: clipboard, voiceHistory: voice, now: now)

        let expectsFailure = mode.hasSuffix("failure")
        if case .failed(let error) = message {
            #expect(expectsFailure && error.contains("fixture failure"))
        } else { #expect(!expectsFailure && message == .completed) }
        #expect(fixture.moved.count == (["never", "disabled"].contains(mode) ? 0 : 1))
        #expect(fixture.emptied == (mode == "never" ? 0 : 1))
        let keepClipboard = ["never", "disabled", "clipboard-failure"].contains(mode)
        let reopenedClipboard = ClipboardHistoryStore(storageURL: clipboardURL)
        await reopenedClipboard.waitUntilLoaded()
        #expect(Set(reopenedClipboard.items.map(\.id)) == Set(keepClipboard ? [expired.id, pinned.id, current.id] : [pinned.id, current.id]))
        let reopenedVoice = VoiceHistoryStore(storageURL: metadata, recordingsDirectory: recordings)
        #expect(reopenedVoice.entries.count == 2)
        #expect(reopenedVoice.entries.allSatisfy { $0.rawTranscript == "retained text" })
        #expect(FileManager.default.fileExists(atPath: voice.recordingURL(for: expiredID).path)
            == ["never", "voice-failure"].contains(mode))
        #expect(FileManager.default.fileExists(atPath: voice.recordingURL(for: currentID).path))
        #expect(fixture.timers.map(\.fireDate) == deadlines)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date == storedSystemDate)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == storedTrashDate)
        #expect(clipboard.cleanupTimer == nil)
        clipboard.stopCleanup()
    }

    @Test
    func cancellationBeforeStartingLeavesEveryItemUntouched() async throws {
        let fixture = try ImmediateCleanupFixture()
        defer { fixture.removeFiles() }
        let service = fixture.makeService()
        let clipboard = ClipboardHistoryStore(storageURL: fixture.directory.appendingPathComponent("clipboard.sqlite"))
        await clipboard.waitUntilLoaded()
        let voice = VoiceHistoryStore(storageURL: fixture.directory.appendingPathComponent("voice.json"),
            recordingsDirectory: fixture.directory.appendingPathComponent("recordings"))
        let task = Task { await AppModel.cleanConfiguredItems(settings: FeatureSettings(trashCleanupPolicy: .sevenDays),
            systemCleanup: service, clipboardHistory: clipboard, voiceHistory: voice) }
        task.cancel()
        #expect(await task.value == nil)
        #expect(fixture.timers.isEmpty && fixture.emptied == 0 && fixture.moved.isEmpty)
        service.stop()
    }

    @Test
    func cancellationWhileClipboardCleanupCompletesDoesNotDeleteRecordings() async throws {
        let fixture = try ImmediateCleanupFixture()
        defer { fixture.removeFiles() }
        let clipboardURL = fixture.directory.appendingPathComponent("clipboard.sqlite")
        let expired = ClipboardHistoryItem(content: .text("expired clipboard"), lastCopiedAt: .distantPast)
        let database = ClipboardHistoryDatabase(storageURL: clipboardURL)
        try database.flush([.upsert(expired, capacity: nil)])
        let clipboard = ClipboardHistoryStore(storageURL: clipboardURL)
        await clipboard.waitUntilLoaded()
        let recordings = fixture.directory.appendingPathComponent("recordings")
        let voice = VoiceHistoryStore(storageURL: fixture.directory.appendingPathComponent("voice.json"), recordingsDirectory: recordings)
        let id = UUID()
        let audioURL = voice.recordingURL(for: id)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        try Data("fixture audio".utf8).write(to: audioURL)
        #expect(voice.record(VoiceRecordingResult(id: id, audioFileURL: audioURL, transcript: "retained text",
            duration: 1, createdAt: .distantPast)))
        let service = fixture.makeService()
        defer { service.stop() }
        var settings = FeatureSettings(clipboardHistoryCleanupPolicy: .sevenDays)
        settings.voiceRecordingCleanupPolicy = .sevenDays
        let task = Task { await AppModel.cleanConfiguredItems(settings: settings, systemCleanup: service,
            clipboardHistory: clipboard, voiceHistory: voice) }
        let observation = clipboard.$isLoading.dropFirst().filter { $0 }.sink { _ in task.cancel() }
        defer { observation.cancel() }

        #expect(await task.value == nil)
        #expect(task.isCancelled)
        #expect(clipboard.items.isEmpty, "The clipboard transaction completed before cancellation")
        #expect(FileManager.default.fileExists(atPath: audioURL.path), "Cancellation must skip remaining cleanup items")
        #expect(voice.entries.first?.audioFileName == audioURL.lastPathComponent)
    }
}

@MainActor
private final class ImmediateCleanupFixture {
    let directory: URL
    let defaults: UserDefaults
    private let suite = "Zisla.ImmediateCleanup.\(UUID().uuidString)"
    var timers: [Timer] = []
    var moved: [DiskCleanupCandidate] = []
    var emptied = 0

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    func makeService(systemFails: Bool = false, trashFails: Bool = false) -> SystemAutoCleanupService {
        let candidate = DiskCleanupCandidate(url: directory.appendingPathComponent("cache"), kind: .appCache,
            byteSize: 100, displayName: "fixture cache")
        return SystemAutoCleanupService(defaults: defaults, scan: { _, _ in [candidate] },
            trash: { candidates in
                self.moved = candidates
                return DiskCleanupResult(successCount: systemFails ? 0 : candidates.count, freedBytes: 0,
                    failures: systemFails ? [DiskCleanupFailure(url: candidate.url, message: "system fixture failure")] : [])
            }, emptyTrash: {
                self.emptied += 1
                return trashFails ? .failure(.failed("trash fixture failure")) : .success(())
            }, timerFactory: { interval, callback in
                let timer = Timer(timeInterval: interval, repeats: true, block: callback)
                self.timers.append(timer)
                return timer
            })
    }

    func executeSQL(_ sql: String, at url: URL) throws {
        var connection: OpaquePointer?
        let status = sqlite3_open(url.path, &connection)
        defer { sqlite3_close(connection) }
        #expect(status == SQLITE_OK)
        let opened = try #require(connection)
        #expect(sqlite3_exec(opened, sql, nil, nil, nil) == SQLITE_OK)
    }

    func removeFiles() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
