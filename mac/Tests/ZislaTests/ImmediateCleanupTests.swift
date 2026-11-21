import AppKit
import Combine
import Foundation
import SQLite3
import Testing
import ZislaCore
@testable import ZislaKit

@testable import Zisla

@MainActor
struct ImmediateCleanupTests {
    @Test(arguments: [false, true], [false, true])
    func outcomesSeparateSuccessPartialFailureAndTotalFailure(succeeded: Bool, failed: Bool) {
        let outcome = ImmediateCleanupController.Outcome(didSucceed: succeeded, errors: failed ? ["fixture failure"] : [])
        #expect(outcome.noticeKey == (failed
                ? (succeeded ? "清理部分失败，如需查看详细信息请去设置-系统状态与清理页面查看"
                    : "清理失败，如需查看详细信息请去设置-系统状态与清理页面查看")
                : "清理完成"))
    }

    @Test
    func mountingSettingsDoesNotRunCleanupAndClosingItKeepsTheBackgroundTask() async throws {
        let gate = ImmediateCleanupGate()
        var settings = FeatureSettings(systemCleanupPolicy: .sevenDays)
        var notices: [String?] = []
        var choices: [FeatureSettings] = []
        let controller = ImmediateCleanupController(operation: { settings in
            choices.append(settings)
            await gate.wait()
            return .init(didSucceed: true, errors: [])
        }, onMessage: { notices.append($0) }, requestPermission: { _ in Issue.record("No permission request on success"); return false })
        let publisher = controller.objectWillChange.sink { _ in }
        #expect(controller.task == nil && !controller.isRunning && controller.errors.isEmpty && notices.isEmpty)
        let original = settings
        controller.start(settings: settings)
        let task = try #require(controller.task)
        await gate.waitUntilStarted()
        #expect(controller.isRunning && notices == [AppLocalization.text("正在清理")])
        controller.start(settings: settings)
        settings.systemCleanupPolicy = .never
        controller.start(settings: settings)
        publisher.cancel()
        await gate.release()
        await task.value
        #expect(choices == [original])
        #expect(!controller.isRunning && controller.task == nil && controller.errors.isEmpty)
        #expect(notices == [AppLocalization.text("正在清理"), AppLocalization.text("清理完成")])
    }

    @Test
    func cleanupWithoutEnabledItemsDoesNotEmitANotice() {
        let controller = ImmediateCleanupController(operation: { _ in
            Issue.record("Disabled cleanup cannot start")
            return nil
        }, onMessage: { _ in Issue.record("Disabled cleanup cannot emit progress or completion") }, requestPermission: { _ in false })
        controller.start(settings: FeatureSettings.default)
        #expect(controller.task == nil && !controller.isRunning && controller.errors.isEmpty)
    }

    @Test(arguments: [true, false])
    func failureDetailsStayInSettingsAndPermissionRequestsOccurOnce(opened: Bool) async throws {
        var notices: [String?] = []
        var requests: [OnboardingPermissionID] = []
        let controller = ImmediateCleanupController(operation: { _ in
            .init(didSucceed: true, errors: ["fixture file: permission denied"], permissions: [.fullDiskAccess])
        }, onMessage: { notices.append($0) }, requestPermission: { permission in requests.append(permission); return opened })
        controller.start(settings: FeatureSettings(systemCleanupPolicy: .sevenDays))
        await (try #require(controller.task)).value
        #expect(requests == [.fullDiskAccess])
        #expect(controller.errors.first == "fixture file: permission denied")
        #expect(controller.errors.count == (opened ? 1 : 2))
        #expect(notices.last == AppLocalization.text("清理部分失败，如需查看详细信息请去设置-系统状态与清理页面查看"))
        #expect(notices.allSatisfy { $0?.contains("fixture file") != true })
    }

    @Test
    func cleanupPermissionUsesTheSameDraggableApplicationHelperAsPermissionSettings() async throws {
        let fixture = try ImmediateCleanupFixture()
        defer { fixture.removeFiles() }
        let applicationURL = fixture.directory.appendingPathComponent("zisla.app")
        try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)
        let center = NotificationCenter()
        var opened: [URL] = []
        var timers: [(Timer, @Sendable (Timer) -> Void)] = []
        var uptime: TimeInterval = 0
        let assistant = PermissionSettingsAssistant(applicationURL: applicationURL, openURL: { opened.append($0); return true },
                                                    icon: { _ in NSImage(size: CGSize(width: 32, height: 32)) },
                                                    placement: { (CGRect(x: 100, y: 100, width: 600, height: 600), CGRect(x: 0, y: 0, width: 1600, height: 1000)) },
                                                    orderFront: { _ in }, timerFactory: { interval, callback in
                                                        let timer = Timer(timeInterval: interval, repeats: true, block: callback)
                                                        timers.append((timer, callback))
                                                        return timer
                                                    }, uptime: { uptime }, workspaceNotificationCenter: center)
        defer { assistant.dismiss() }
        let permissions = OnboardingPermissionCoordinator(dependencies: .init(read: { _, reply in reply(.unknown) },
                                                                              request: { _, _ in Issue.record("Full Disk Access uses System Settings") }, cancel: {}, openSettings: { assistant.openSettings($0) }))
        let controller = ImmediateCleanupController(operation: { _ in
            .init(didSucceed: false, errors: ["fixture permission failure"], permissions: [.fullDiskAccess])
        }, onMessage: { _ in }, requestPermission: { permissions.openSettings(for: $0) })
        controller.start(settings: FeatureSettings(systemCleanupPolicy: .sevenDays))
        await (try #require(controller.task)).value
        #expect(opened == [OnboardingPermissionID.fullDiskAccess.settingsURL])
        let (timer, callback) = try #require(timers.first)
        callback(timer)
        uptime = 0.5
        callback(timer)
        let panel = try #require(assistant.panel)
        let stack = try #require(panel.contentView?.subviews.compactMap { $0 as? NSStackView }.first)
        let image = try #require(stack.arrangedSubviews.compactMap { $0 as? FileShelfDraggingView }.first)
        #expect(image.payload == .file(applicationURL))
        #expect(image.sourceOperationMask(for: .outsideApplication) == .copy)
        #expect(!panel.canBecomeKey && !panel.isVisible)
    }

    @Test
    func cancellingCleanupClearsProgressAndDoesNotReportSuccess() async throws {
        let gate = ImmediateCleanupGate()
        var notices: [String?] = []
        let controller = ImmediateCleanupController(operation: { _ in
            await gate.wait()
            return .init(didSucceed: true, errors: [])
        }, onMessage: { notices.append($0) }, requestPermission: { _ in false })
        controller.start(settings: FeatureSettings(systemCleanupPolicy: .sevenDays))
        let task = try #require(controller.task)
        await gate.waitUntilStarted()
        controller.cancel()
        await gate.release()
        await task.value
        #expect(notices == [AppLocalization.text("正在清理"), nil])
        #expect(!controller.isRunning && controller.task == nil)
    }

    @Test(arguments: [0, 1])
    func voiceCleanupReportsPartialDeletionAsPartialFailure(failedIndex: Int) async throws {
        let fixture = try ImmediateCleanupFixture()
        defer { fixture.removeFiles() }
        let recordings = fixture.directory.appendingPathComponent("recordings")
        let fileManager = ImmediateCleanupVoiceFileManager()
        let voice = VoiceHistoryStore(storageURL: fixture.directory.appendingPathComponent("voice.json"),
                                      recordingsDirectory: recordings, fileManager: fileManager)
        for id in [UUID(), UUID()] {
            let url = voice.recordingURL(for: id)
            try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
            try Data("fixture audio".utf8).write(to: url)
            #expect(voice.record(VoiceRecordingResult(id: id, audioFileURL: url, transcript: "retained text",
                                                      duration: 1, createdAt: .distantPast)))
        }
        fileManager.deniedAudioName = voice.entries[failedIndex].audioFileName
        let service = fixture.makeService()
        defer { service.stop() }
        let clipboard = ClipboardHistoryStore(storageURL: fixture.directory.appendingPathComponent("clipboard.sqlite"))
        await clipboard.waitUntilLoaded()
        var settings = FeatureSettings.default
        settings.voiceRecordingCleanupPolicy = .sevenDays
        let outcome = try #require(await ImmediateCleanupController.cleanConfiguredItems(settings: settings,
                                                                                         systemCleanup: service, clipboardHistory: clipboard, voiceHistory: voice))
        #expect(outcome.didSucceed == (failedIndex > 0))
        #expect(outcome.errors.count == 1 && outcome.errors[0].contains("voice deletion fixture failure"))
        #expect(outcome.noticeKey == (failedIndex > 0
                ? "清理部分失败，如需查看详细信息请去设置-系统状态与清理页面查看"
                : "清理失败，如需查看详细信息请去设置-系统状态与清理页面查看"))
        #expect(voice.entries.filter { $0.audioFileName != nil }.count == 2 - failedIndex)
        #expect(voice.entries.allSatisfy { $0.rawTranscript == "retained text" })
    }

    @Test(arguments: [0, 1])
    func systemOnlyCleanupReportsAllFailedOrPartialFailed(successes: Int) async throws {
        let fixture = try ImmediateCleanupFixture()
        defer { fixture.removeFiles() }
        let failedURL = fixture.directory.appendingPathComponent("protected.log")
        let service = SystemAutoCleanupService(defaults: fixture.defaults, scan: { _, _ in [] }, trash: { _ in
            DiskCleanupResult(successCount: successes, freedBytes: 0,
                              failures: [DiskCleanupFailure(url: failedURL, message: "permission fixture", isPermissionDenied: true)])
        }, emptyTrash: { Issue.record("Disabled Trash cannot run"); return .success(()) })
        defer { service.stop() }
        let clipboard = ClipboardHistoryStore(storageURL: fixture.directory.appendingPathComponent("clipboard.sqlite"))
        await clipboard.waitUntilLoaded()
        let voice = VoiceHistoryStore(storageURL: fixture.directory.appendingPathComponent("voice.json"),
                                      recordingsDirectory: fixture.directory.appendingPathComponent("recordings"))
        let outcome = try #require(await ImmediateCleanupController.cleanConfiguredItems(
            settings: FeatureSettings(systemCleanupPolicy: .sevenDays), systemCleanup: service, clipboardHistory: clipboard, voiceHistory: voice
        ))
        #expect(outcome.didSucceed == (successes > 0))
        #expect(outcome.permissions == [.fullDiskAccess])
        #expect(outcome.errors == [failedURL.path + ": permission fixture"])
        #expect(outcome.noticeKey == (successes > 0
                ? "清理部分失败，如需查看详细信息请去设置-系统状态与清理页面查看"
                : "清理失败，如需查看详细信息请去设置-系统状态与清理页面查看"))
    }

    @Test(arguments: [false, true], [false, true])
    func availabilityFollowsEnabledCleanupItems(systemEnabled: Bool, clipboardEnabled: Bool) {
        var settings = FeatureSettings(systemMonitorEnabled: systemEnabled, clipboardHistoryEnabled: clipboardEnabled)
        #expect(!ImmediateCleanupController.canCleanNow(settings: settings))
        settings.systemCleanupPolicy = .sevenDays
        #expect(ImmediateCleanupController.canCleanNow(settings: settings) == systemEnabled)
        settings.systemCleanupPolicy = .never
        settings.clipboardHistoryCleanupPolicy = .sevenDays
        #expect(ImmediateCleanupController.canCleanNow(settings: settings) == clipboardEnabled)
        settings.clipboardHistoryCleanupPolicy = .never
        settings.trashCleanupPolicy = .sevenDays
        #expect(ImmediateCleanupController.canCleanNow(settings: settings))
        settings.trashCleanupPolicy = .never
        settings.voiceInputEnabled = false
        settings.voiceRecordingCleanupPolicy = .sevenDays
        #expect(ImmediateCleanupController.canCleanNow(settings: settings))
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

        let message = await ImmediateCleanupController.cleanConfiguredItems(settings: settings, systemCleanup: service,
                                                                            clipboardHistory: clipboard, voiceHistory: voice, now: now)

        let outcome = try #require(message)
        let expectsFailure = mode.hasSuffix("failure")
        #expect(!outcome.errors.isEmpty == expectsFailure)
        #expect(outcome.didSucceed == (mode != "never"))
        if expectsFailure {
            #expect(outcome.noticeKey == "清理部分失败，如需查看详细信息请去设置-系统状态与清理页面查看")
            #expect(outcome.errors.contains { $0.contains("fixture failure") })
        } else { #expect(outcome.noticeKey == "清理完成") }
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
        let task = Task { await ImmediateCleanupController.cleanConfiguredItems(settings: FeatureSettings(trashCleanupPolicy: .sevenDays),
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
        let task = Task { await ImmediateCleanupController.cleanConfiguredItems(settings: settings, systemCleanup: service,
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

private final class ImmediateCleanupVoiceFileManager: FileManager {
    var deniedAudioName: String?

    override func removeItem(at url: URL) throws {
        if url.lastPathComponent.hasPrefix(".zisla-deleting-"), let deniedAudioName,
           url.lastPathComponent.hasSuffix(deniedAudioName) {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                          userInfo: [NSLocalizedDescriptionKey: "voice deletion fixture failure"])
        }
        try super.removeItem(at: url)
    }
}

private actor ImmediateCleanupGate {
    private var pending: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        pending?.resume()
        pending = nil
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
