import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct DailyBriefingActivityIntegrationTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("briefing-activity-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func controller(store: DailyBriefingStore, onObserve: @escaping (Date) -> Void = { _ in },
                            export: @escaping @MainActor (DailyBriefingReport) -> Void = { _ in }) -> DailyBriefingController {
        DailyBriefingController(store: store,
            observation: { date in
                onObserve(date)
                return .init(date: date, applicationID: "fixture", applicationName: "Fixture", category: .work, isActive: false, isListening: false)
            },
            typing: { _ in nil }, readScreenTime: { _ in .init() },
            export: { report, _, _, directory in export(report); return directory.appendingPathComponent("fixture.png") })
    }

    @Test
    func enabledEventsAndPhysicalKeysAreBatchedBeforeNormalExport() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        var reports: [DailyBriefingReport] = []
        let controller = controller(store: DailyBriefingStore(fileURL: file), export: { reports.append($0) })
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        controller.recordActivity(.clipboardCaptured)
        controller.recordKeyPress(at: date)
        controller.configure(settings: .init(enabled: true, readsSystemScreenTime: false), directory: directory, language: .english, startsTimer: false)
        controller.recordActivity(.clipboardCaptured, count: 2, at: date)
        controller.recordActivity(.shelfItemsAdded, count: 3, at: date)
        controller.recordActivity(.noteSaved, count: -1, at: date)
        for _ in 0..<1_000 { controller.recordKeyPress(at: date) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        await controller.exportToday(at: date)
        let day = try #require(reports.first?.day)
        #expect(reports.count == 1)
        #expect(day.activity?.count(for: .clipboardCaptured) == 2)
        #expect(day.activity?.count(for: .shelfItemsAdded) == 3)
        #expect(day.activity?.count(for: .noteSaved) == 0)
        #expect(day.hourlyKeyPresses?[DailyBriefingDay.calendar.component(.hour, from: date)] == 1_000)
        #expect(day.activeSeconds == 0)
        await controller.exportToday(at: date)
        #expect(reports.last?.day.activity == day.activity)
        #expect(reports.last?.day.hourlyKeyPresses == day.hourlyKeyPresses)
    }

    @Test
    func failedFlushRetainsAllPendingEventsAndRetriesWithoutDuplication() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("archive")
        let file = folder.appendingPathComponent("history.json")
        var reports: [DailyBriefingReport] = []
        let controller = controller(store: DailyBriefingStore(fileURL: file), export: { reports.append($0) })
        controller.configure(settings: .init(enabled: true, readsSystemScreenTime: false), directory: directory, language: .english, startsTimer: false)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        controller.recordActivity(.quickNoteCreated, at: date)
        await controller.exportToday(at: date)
        let backup = directory.appendingPathComponent("backup")
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked".utf8).write(to: folder)
        controller.recordActivity(.quickNoteCreated, count: 2, at: date)
        controller.recordKeyPress(at: date)
        await controller.exportToday(at: date)
        #expect(reports.count == 1)
        #expect(controller.errorMessage != nil)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        await controller.exportToday(at: date)
        #expect(controller.errorMessage == nil)
        #expect(reports.last?.day.activity?.count(for: .quickNoteCreated) == 3)
        #expect(reports.last?.day.hourlyKeyPresses?.compactMap { $0 }.reduce(0, +) == 1)
        #expect(await controller.prepareToTerminate())
        let restored = try await DailyBriefingStore(fileURL: file).day(at: date, calendar: DailyBriefingDay.calendar)
        #expect(restored.activity?.count(for: .quickNoteCreated) == 3)
        #expect(restored.hourlyKeyPresses?.compactMap { $0 }.reduce(0, +) == 1)
        #expect(restored.hourlyKeyPresses?[0] == nil || DailyBriefingDay.calendar.component(.hour, from: date) == 0)
    }

    @Test
    func unlocksRequireALockedToUnlockedTransitionAndShutdownFlushesPendingWork() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let controller = controller(store: DailyBriefingStore(fileURL: file))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        controller.setScreenLocked(true, at: date)
        controller.setScreenLocked(false, at: date)
        controller.configure(settings: .init(enabled: true), directory: directory, language: .english, startsTimer: false)
        controller.setScreenLocked(false, at: date)
        controller.setScreenLocked(true, at: date)
        controller.setScreenLocked(true, at: date)
        controller.setScreenLocked(false, at: date)
        controller.setScreenLocked(false, at: date)
        controller.recordActivity(.pomodoroCompleted, focusSeconds: 1500, at: date)
        #expect(await controller.prepareToTerminate())
        let day = try await DailyBriefingStore(fileURL: file).day(at: date, calendar: DailyBriefingDay.calendar)
        #expect(day.activity?.count(for: .unlocked) == 1)
        #expect(day.activity?.count(for: .pomodoroCompleted) == 1)
        #expect(day.activity?.completedFocusSeconds == 1500)
    }

    @Test
    func failedShutdownRejectsQuitAndPreservesEventsForAnExplicitRetry() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("blocked")
        let file = folder.appendingPathComponent("history.json")
        try Data("blocked".utf8).write(to: folder)
        let store = DailyBriefingStore(fileURL: file)
        let controller = controller(store: store)
        controller.configure(settings: .init(enabled: true, readsSystemScreenTime: false), directory: directory, language: .english, startsTimer: false)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        controller.recordActivity(.noteCreated, at: date)
        controller.recordKeyPress(at: date)
        #expect(await controller.prepareToTerminate() == false)
        controller.recordActivity(.noteCreated, at: date)
        controller.recordKeyPress(at: date)
        try FileManager.default.removeItem(at: folder)
        await controller.tick(at: date)
        #expect(await controller.prepareToTerminate())
        let day = try await DailyBriefingStore(fileURL: file).day(at: date, calendar: DailyBriefingDay.calendar)
        #expect(day.activity?.count(for: .noteCreated) == 2)
        #expect(day.hourlyKeyPresses?.compactMap { $0 }.reduce(0, +) == 2)
        #expect(day.hourlyKeyPresses?.filter { $0 != nil }.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func failedShutdownRestartsTheAutomaticLoopAndContinuesRecording() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("archive")
        let file = folder.appendingPathComponent("history.json")
        let store = DailyBriefingStore(fileURL: file)
        let (stream, continuation) = AsyncStream<Date>.makeStream()
        defer { continuation.finish() }
        var observations = stream.makeAsyncIterator()
        let controller = controller(store: store, onObserve: { continuation.yield($0) })
        defer { controller.stop() }
        controller.configure(settings: .init(enabled: true, readsSystemScreenTime: false), directory: directory, language: .english)
        try #require(await observations.next())
        try await store.flush()
        let backup = directory.appendingPathComponent("backup")
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked".utf8).write(to: folder)
        let date = Date()
        controller.recordActivity(.quickNoteCreated, at: date)
        #expect(await controller.prepareToTerminate() == false)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        controller.recordActivity(.quickNoteCreated, at: date)
        try #require(await observations.next())
        let recovered = try await store.day(at: date, calendar: DailyBriefingDay.calendar)
        #expect(recovered.activity?.count(for: .quickNoteCreated) == 2)
        #expect(await controller.prepareToTerminate())
        #expect(try await DailyBriefingStore(fileURL: file).day(at: date, calendar: DailyBriefingDay.calendar).activity?.count(for: .quickNoteCreated) == 2)
    }

    @Test
    func normalFeatureRoutesFeedTheCounterAndTerminationHooks() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/AppModel.swift"), encoding: .utf8)
        for source in ["self.dailyBriefing.recordActivity(.clipboardCaptured)",
                       "dailyBriefing.recordActivity(.clipboardReused)",
                       "dailyBriefing.recordActivity(.shelfItemsCopied, count: items.count)",
                       "shelf.onDailyBriefingActivity = recordActivity",
                       "pomodoro.onDailyBriefingActivity = recordActivity",
                       "quickNotes.onDailyBriefingActivity = recordActivity",
                       "self?.dailyBriefing.recordKeyPress(at: date)",
                       "await self?.dailyBriefing.prepareToTerminate()"] {
            #expect(model.contains(source))
        }
        let application = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/ZislaApp.swift"), encoding: .utf8)
        #expect(application.contains("model.dailyBriefing.setScreenLocked(locked)"))
        let keyboard = try String(contentsOf: root.appendingPathComponent("Sources/KeyboardKit/KeyboardAppModel.swift"), encoding: .utf8)
        #expect(keyboard.contains("application.reply(toApplicationShouldTerminate: persisted)"))
        let editor = try String(contentsOf: root.appendingPathComponent("Sources/KeyboardKit/SoundPackEditorWindowController.swift"), encoding: .utf8)
        #expect(editor.contains("cleaned = await self.appModel?.flushTypingStatsBeforeTermination() ?? true"))
        #expect(editor.contains("if !cleaned {\n                    self.allowsNextClose = true\n                    self.window?.performClose(nil)"))
    }
}
