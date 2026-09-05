import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct AIStateMonitorActivityDetectorTests {
    @Test @MainActor
    func defaultActivityRefreshAvoidsHighFrequencyDirectoryScans() {
        #expect(AIStateMonitor.defaultDetectorRefreshInterval == 30)
    }

    @Test @MainActor
    func defaultUsageRefreshChecksEveryThreeMinutes() {
        #expect(AIStateMonitor.defaultUsageRefreshInterval == 3 * 60)
    }

    @Test @MainActor
    func defaultCodexDetectorScansAllRollouts() throws {
        let detector = try #require(AIStateMonitor.defaultActivityDetectors()
            .compactMap { $0 as? CodexSessionActivityDetector }
            .first)

        #expect(detector.maxRolloutFiles == .max)
    }

    @Test @MainActor
    func defaultActivityDetectorsIncludeZCodeDesktopAndCLI() {
        #expect(AIStateMonitor.defaultActivityDetectors().contains {
            $0 is ZCodeSessionActivityDetector
        })
    }

    @Test @MainActor
    func defaultActivityDetectorsIncludeZedAgentThreads() {
        #expect(AIStateMonitor.defaultActivityDetectors().contains {
            $0 is ZedSessionActivityDetector
        })
    }

    @Test @MainActor
    func defaultActivityDetectorsIncludePiSessions() {
        #expect(AIStateMonitor.defaultActivityDetectors().contains {
            $0 is PiSessionActivityDetector
        })
    }

    @Test @MainActor
    func defaultActivityDetectorsIncludeGeminiDesktopChats() {
        #expect(AIStateMonitor.defaultActivityDetectors().contains {
            $0 is GeminiDesktopSessionActivityDetector
        })
    }

    @Test @MainActor
    func reloadMergesEveryInjectedProvider() {
        let directory = monitorTempDirectory("providers")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_910_000_000)
        let providers = AIProvider.allCases
        let tasks = providers.enumerated().map { index, provider in
            AIProgressTask(
                id: "automatic-\(provider.rawValue)",
                provider: provider,
                title: provider.rawValue,
                progress: nil,
                status: .running,
                updatedAt: now.addingTimeInterval(TimeInterval(index))
            )
        }
        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [StaticActivityDetector(tasks: tasks)],
            now: { now.addingTimeInterval(10) }
        )

        monitor.reload()

        #expect(Set(monitor.state.tasks.map(\.provider)) == Set(providers))
        #expect(monitor.errorDescription == nil)
    }

    @Test @MainActor
    func failingDetectorDoesNotSuppressHealthyDetector() {
        let directory = monitorTempDirectory("failure-isolation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_910_000_000)
        let task = AIProgressTask(
            id: "healthy",
            provider: .grok,
            title: "Grok",
            progress: nil,
            status: .blocked,
            updatedAt: now
        )
        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [
                FailingActivityDetector(),
                StaticActivityDetector(tasks: [task]),
            ],
            now: { now }
        )

        monitor.reload()

        #expect(monitor.state.tasks == [task])
        #expect(monitor.errorDescription == nil)
    }

    @Test @MainActor
    func scheduledRefreshRemovesFinishedAutomaticTask() async {
        let directory = monitorTempDirectory("scheduled-finish")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_910_000_000)
        let task = AIProgressTask(
            id: "automatic-finished",
            provider: .codex,
            title: "Codex",
            progress: nil,
            status: .running,
            updatedAt: now
        )
        let detector = MutableActivityDetector(tasks: [task])
        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [detector],
            activeTaskTTL: .greatestFiniteMagnitude,
            detectorRefreshInterval: 1,
            now: { now }
        )
        defer { monitor.stop() }

        monitor.start()
        let detected = await waitForMonitorState(timeout: 10) { monitor.state.tasks == [task] }
        #expect(detected)

        detector.replaceTasks(with: [])
        let removed = await waitForMonitorState(timeout: 10) { monitor.state.tasks.isEmpty }
        #expect(removed)
    }

    @Test @MainActor
    func stateFileWatchersReloadWALAppendsAndRemainStoppedUntilRestart() async throws {
        let directory = monitorTempDirectory("wal-watch")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let database = try AIStateDatabase(url: repository.databaseURL, maximumUsageSamples: 10)
        let first = AIProgressTask(
            id: "first", provider: .codex, title: "First", progress: nil,
            status: .running, updatedAt: .now
        )
        try database.upsertTask(first)

        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [],
            activeTaskTTL: .greatestFiniteMagnitude
        )
        defer { monitor.stop() }
        monitor.start()
        #expect(await waitForMonitorState(timeout: 10) { monitor.state.tasks == [first] })

        let second = AIProgressTask(
            id: "second", provider: .claude, title: "Second", progress: 0.5,
            status: .running, updatedAt: .now
        )
        try database.upsertTask(second)
        #expect(await waitForMonitorState(timeout: 10) {
            Set(monitor.state.tasks.map(\.id)) == Set([first.id, second.id])
        })

        monitor.stop()
        let stoppedState = monitor.state
        let third = AIProgressTask(
            id: "third", provider: .gemini, title: "Third", progress: 0.75,
            status: .running, updatedAt: .now
        )
        try database.upsertTask(third)
        try await Task.sleep(for: .milliseconds(250))
        #expect(monitor.state == stoppedState)

        monitor.start()
        #expect(await waitForMonitorState(timeout: 10) {
            Set(monitor.state.tasks.map(\.id)) == Set([first.id, second.id, third.id])
        })
        withExtendedLifetime(database) {}
    }

    @Test @MainActor
    func refreshDetectsNewActivityWhenPersistedStateIsUnchanged() async throws {
        let directory = monitorTempDirectory("unchanged-state-refresh")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_910_000_000)
        let task = AIProgressTask(
            id: "automatic-newly-active",
            provider: .codex,
            title: "Codex",
            progress: nil,
            status: .running,
            updatedAt: now
        )
        let detector = MutableActivityDetector(tasks: [])
        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [detector],
            detectorRefreshInterval: 60,
            now: { now }
        )
        defer { monitor.stop() }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        monitor.reload()
        #expect(detector.hasBeenCalled)

        detector.replaceTasks(with: [task])
        monitor.refresh()

        #expect(await waitForMonitorState(timeout: 10) { monitor.state.tasks == [task] })
    }

    @Test @MainActor
    func interactiveRefreshDoesNotScanUsageLogs() async throws {
        let directory = monitorTempDirectory("interactive-refresh-no-usage")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_910_000_000)
        let activityDetector = MutableActivityDetector(tasks: [])
        let usageDetector = CountingUsageDetector()
        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [activityDetector],
            usageDetectors: [usageDetector],
            detectorRefreshInterval: 60,
            now: { now }
        )
        defer { monitor.stop() }

        monitor.start()

        #expect(await waitForMonitorState(timeout: 10) { activityDetector.hasBeenCalled })
        let initialActivityCallCount = activityDetector.callCount
        monitor.refreshActiveTasks()

        #expect(await waitForMonitorState(timeout: 10) {
            activityDetector.callCount > initialActivityCallCount
        })
        #expect(usageDetector.callCount == 0)
    }

    @Test @MainActor
    func stateFileWatcherDoesNotRescanActivityDetectors() async throws {
        let directory = monitorTempDirectory("watcher-no-activity-rescan")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let detector = MutableActivityDetector(tasks: [])
        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [detector],
            detectorRefreshInterval: 60
        )
        defer { monitor.stop() }

        monitor.start()
        #expect(await waitForMonitorState(timeout: 10) { detector.callCount >= 1 })
        let initialCallCount = detector.callCount

        let task = AIProgressTask(
            id: "persisted-after-start",
            provider: .codex,
            title: "Codex",
            progress: nil,
            status: .running,
            updatedAt: .now
        )
        let database = try AIStateDatabase(url: repository.databaseURL, maximumUsageSamples: 10)
        try database.upsertTask(task)
        #expect(await waitForMonitorState(timeout: 10) { monitor.state.tasks == [task] })

        // Give the debounced watcher completion a chance to run; it must only reconcile
        // persisted state and leave the active-session scan to the timer/page entry path.
        try await Task.sleep(for: .milliseconds(250))
        #expect(detector.callCount == initialCallCount)
        withExtendedLifetime(database) {}
    }

    @Test @MainActor
    func reloadImmediatelyRemovesTaskNoLongerReturnedByDetector() {
        let directory = monitorTempDirectory("immediate-removal")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_910_000_000)
        let task = AIProgressTask(
            id: "automatic-removed",
            provider: .codex,
            title: "Codex",
            progress: nil,
            status: .running,
            updatedAt: now
        )
        let detector = MutableActivityDetector(tasks: [task])
        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [detector],
            activeTaskTTL: .greatestFiniteMagnitude,
            now: { now }
        )

        monitor.reload()
        #expect(monitor.state.tasks == [task])

        detector.replaceTasks(with: [])
        monitor.reload()
        #expect(monitor.state.tasks.isEmpty)
    }
}

private struct StaticActivityDetector: AIActivityDetecting {
    var tasks: [AIProgressTask]

    func activeTasks() throws -> [AIProgressTask] {
        tasks
    }
}

private struct FailingActivityDetector: AIActivityDetecting {
    struct DetectionError: Error {}

    func activeTasks() throws -> [AIProgressTask] {
        throw DetectionError()
    }
}

private final class MutableActivityDetector: AIActivityDetecting, @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [AIProgressTask]
    private var calls = 0

    init(tasks: [AIProgressTask]) {
        self.tasks = tasks
    }

    func activeTasks() throws -> [AIProgressTask] {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        return tasks
    }

    func replaceTasks(with tasks: [AIProgressTask]) {
        lock.lock()
        defer { lock.unlock() }
        self.tasks = tasks
    }

    var hasBeenCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return calls > 0
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

final class CountingUsageDetector: AIUsageDetecting {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    func reset() {
        lock.withLock { calls = 0 }
    }

    func usageSamples() throws -> [AIUsageSample] {
        lock.withLock { calls += 1 }
        return []
    }
}

@MainActor
private func waitForMonitorState(
    timeout: TimeInterval = 2,
    matching condition: @escaping () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return condition()
}

private func monitorTempDirectory(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-monitor-\(label)-\(UUID().uuidString)", isDirectory: true)
}
