import Foundation
import Testing
@testable import KeyboardKit

@MainActor
struct DailyBriefingKeyPressTests {
    private func keyboardModel(directory: URL, defaults: UserDefaults) -> KeyboardAppModel {
        defaults.set(false, forKey: "enabled")
        defaults.set(false, forKey: "typingStatsEnabled")
        return KeyboardAppModel(settings: AppSettings(defaults: defaults),
            permission: InputMonitoringPermissionManager(defaults: defaults),
            soundPackLibrary: SoundPackLibrary(rootURL: directory.appendingPathComponent("packs"), bundledPackRootURL: nil),
            typingStats: TypingStatsModel(persistence: TypingStatsStore(databaseURL: directory.appendingPathComponent("stats.sqlite3"))),
            startsServices: false)
    }

    @Test
    func physicalKeyCallbackExcludesAutoRepeatWithoutConfusingCharactersAndShortcuts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("briefing-physical-key-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let store = TypingStatsStore(databaseURL: directory.appendingPathComponent("stats.sqlite3"), nowProvider: { date })
        let model = TypingStatsModel(persistence: store)
        let application = TypingApplicationIdentity(processKey: "fixture", displayName: "Fixture", processName: "Fixture", bundleIdentifier: nil)
        var presses: [Date] = []
        model.onPhysicalKeyDown = { presses.append($0) }
        model.recordKeyDown(keyCode: 0, isRepeat: false, isShortcutModified: false, application: application, at: date)
        model.recordKeyDown(keyCode: 0, isRepeat: true, isShortcutModified: false, application: application, at: date)
        model.recordKeyDown(keyCode: 0, isRepeat: false, isShortcutModified: true, application: application, at: date)
        model.recordKeyDown(keyCode: 123, isRepeat: false, isShortcutModified: false, application: application, at: date)
        #expect(presses == [date, date, date])
        #expect(await model.flushPending())
        let snapshot = try await store.loadSnapshot()
        #expect(snapshot.today.characterCount == 2)
        #expect(snapshot.allTimeKeyCounts.values.reduce(0, +) == 3)
    }

    @Test
    func keyboardTerminationWaitsForTheHostAggregateFlush() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("briefing-termination-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "BriefingTermination.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = keyboardModel(directory: directory, defaults: defaults)
        let entered = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); resume.continuation.finish() }
        var completed = false
        model.onBeforeTermination = {
            entered.continuation.yield()
            for await _ in resume.stream { break }
            completed = true
            return true
        }
        let flush = Task { await model.flushTypingStatsBeforeTermination() }
        for await _ in entered.stream { break }
        #expect(!completed)
        resume.continuation.yield()
        #expect(await flush.value)
        #expect(completed)
    }

    @Test
    func keyboardTerminationPropagatesHostFailureAndAllowsASuccessfulRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("briefing-termination-retry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "BriefingTerminationRetry.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = keyboardModel(directory: directory, defaults: defaults)
        var attempts = 0
        model.onBeforeTermination = { attempts += 1; return attempts > 1 }
        #expect(await model.flushTypingStatsBeforeTermination() == false)
        #expect(model.monitoringState == .stopped)
        #expect(await model.flushTypingStatsBeforeTermination())
        #expect(attempts == 2)
        model.onBeforeTermination = nil
        #expect(await model.flushTypingStatsBeforeTermination())
    }
}
