import Combine
import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct AIStateMonitorActivityDetectorTests {
    private static let testPeriodicRefreshInterval: TimeInterval = 24 * 60 * 60

    @Test @MainActor
    func defaultActivityRefreshAvoidsHighFrequencyDirectoryScans() {
        #expect(AIStateMonitor.defaultDetectorRefreshInterval == 60)
    }

    @Test @MainActor
    func defaultUsageRefreshChecksEveryFiveMinutes() {
        #expect(AIStateMonitor.defaultUsageRefreshInterval == 5 * 60)
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
            detectorRefreshInterval: Self.testPeriodicRefreshInterval,
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
            detectorRefreshInterval: Self.testPeriodicRefreshInterval
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

    @Test @MainActor
    func activityFileChangeRefreshesOnlyItsDetectorAndPreservesOtherTasks() async throws {
        let directory = monitorTempDirectory("targeted-log-watch")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = directory.appendingPathComponent("session.jsonl")
        try Data().write(to: log)
        let codex = AIProgressTask(id: "codex", provider: .codex, title: "Codex", progress: nil, updatedAt: .now)
        let claude = AIProgressTask(id: "claude", provider: .claude, title: "Claude", progress: nil, updatedAt: .now)
        let changed = MutableActivityDetector(tasks: [codex], activityFileURLs: [log])
        let unchanged = MutableActivityDetector(tasks: [claude])
        let usage = CountingUsageDetector()
        let monitor = AIStateMonitor(directoryURL: directory.appendingPathComponent("state"),
            activityDetectors: [changed, unchanged], usageDetectors: [usage],
            detectorRefreshInterval: Self.testPeriodicRefreshInterval)
        defer { monitor.stop() }
        monitor.start()
        #expect(await waitForMonitorState(timeout: 10) { monitor.state.tasks.count == 2 })
        let unchangedCalls = unchanged.callCount
        changed.replaceTasks(with: [])
        try Data("finished\n".utf8).write(to: log)
        #expect(await waitForMonitorState(timeout: 10) { monitor.state.tasks == [claude] })
        #expect(unchanged.callCount == unchangedCalls,
            "One log event must not launch filesystem scans or processes for unrelated providers")
        #expect(usage.callCount == 0)
    }

    @Test @MainActor
    func persistedTaskChangePreservesCachedAutomaticActivityWithoutRescanning() async throws {
        let directory = monitorTempDirectory("cached-automatic-with-persisted")
        defer { try? FileManager.default.removeItem(at: directory) }
        let automatic = AIProgressTask(id: "automatic", provider: .codex, title: "Codex", progress: nil, updatedAt: .now)
        let persisted = AIProgressTask(id: "persisted", provider: .claude, title: "Claude", progress: nil, updatedAt: .now)
        let detector = MutableActivityDetector(tasks: [automatic])
        let monitor = AIStateMonitor(directoryURL: directory, activityDetectors: [detector],
            detectorRefreshInterval: Self.testPeriodicRefreshInterval)
        defer { monitor.stop() }
        monitor.start()
        #expect(await waitForMonitorState(timeout: 10) { monitor.state.tasks == [automatic] })
        let initialCalls = detector.callCount
        let repository = AIStateRepository(directoryURL: directory)
        let database = try AIStateDatabase(url: repository.databaseURL, maximumUsageSamples: 10)
        try database.upsertTask(persisted)
        #expect(await waitForMonitorState(timeout: 2) {
            Set(monitor.state.tasks.map(\.id)) == [automatic.id, persisted.id]
        })
        #expect(detector.callCount == initialCalls)
        withExtendedLifetime(database) {}
    }

    @Test @MainActor
    func periodicRefreshRotatesProvidersWithoutRescanningUnchangedSources() async throws {
        let directory = monitorTempDirectory("round-robin")
        defer { try? FileManager.default.removeItem(at: directory) }
        let tasks = [AIProvider.codex, .claude, .gemini].map {
            AIProgressTask(id: $0.rawValue, provider: $0, title: "initial", progress: nil, updatedAt: .now)
        }
        let detectors = tasks.map { MutableActivityDetector(tasks: [$0]) }
        let usage = CountingUsageDetector()
        let monitor = AIStateMonitor(directoryURL: directory, activityDetectors: detectors,
            usageDetectors: [usage], detectorRefreshInterval: Self.testPeriodicRefreshInterval)
        defer { monitor.stop() }
        monitor.start()
        #expect(await waitForMonitorState { monitor.state.tasks == tasks })
        let timer = try #require(monitor.activityTimer)
        #expect(timer.timeInterval == Self.testPeriodicRefreshInterval / Double(detectors.count))
        var expected = tasks
        for index in detectors.indices {
            var next = tasks[index]
            next.title = "updated"
            detectors[index].replaceTasks(with: [next])
        }
        for index in detectors.indices {
            timer.fire()
            expected[index].title = "updated"
            #expect(await waitForMonitorState { monitor.state.tasks == expected })
            #expect(detectors.enumerated().allSatisfy { $0.element.callCount == ($0.offset <= index ? 2 : 1) },
                "Each timer slot may scan only its source while retaining the other snapshots")
        }
        #expect(usage.callCount == 0)
    }

    @Test @MainActor
    func usageTimerCollectsWithoutActivityDetectorsOrLoadingPanelHistory() async throws {
        let directory = monitorTempDirectory("usage-only-timer")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_910_000_000)
        let usage = CountingUsageDetector(samples: [
            AIUsageSample(sourceID: "usage-only", provider: .claude, timestamp: now,
                inputTokens: 10, outputTokens: 5),
        ])
        let monitor = AIStateMonitor(directoryURL: directory, activityDetectors: [],
            usageDetectors: [usage], detectorRefreshInterval: Self.testPeriodicRefreshInterval,
            now: { now })
        defer { monitor.stop() }
        monitor.start()
        #expect(monitor.activityTimer == nil)
        let timer = try #require(monitor.usageTimer)
        #expect(timer.timeInterval == 5 * 60)
        timer.fire()
        let repository = AIStateRepository(directoryURL: directory)
        #expect(await waitForMonitorState {
            (try? repository.load().usageSamples.reduce(0) { $0 + $1.totalTokens }) == 15
        })
        #expect(usage.callCount == 1)
        #expect(monitor.state.usageSamples.isEmpty && monitor.usageHistoryState == .idle)
    }

    @Test @MainActor
    func usageThrottleChecksAgainWithinOneMinuteAfterAnEarlyTick() async throws {
        let directory = monitorTempDirectory("usage-timer-drift")
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 1_910_000_000)
        let usage = CountingUsageDetector()
        let monitor = AIStateMonitor(directoryURL: directory, activityDetectors: [],
            usageDetectors: [usage], now: { now })
        defer { monitor.stop() }
        monitor.start()
        let timer = try #require(monitor.usageTimer)
        #expect(timer.timeInterval == 60,
            "A delayed scan must not make an early timer tick postpone the next scan by five more minutes")
        timer.fire()
        await Task { @MainActor in }.value
        _ = try await monitor.readUsageHistory()
        #expect(usage.callCount == 1)

        now = now.addingTimeInterval(299.9)
        timer.fire()
        await Task { @MainActor in }.value
        _ = try await monitor.readUsageHistory()
        #expect(usage.callCount == 1, "An early check must not trigger another full scan")

        now = now.addingTimeInterval(timer.timeInterval)
        timer.fire()
        await Task { @MainActor in }.value
        _ = try await monitor.readUsageHistory()
        #expect(usage.callCount == 2)
    }

    @Test @MainActor
    func failedActivityReadKeepsItsSnapshotUntilTTLAndRecovers() {
        let directory = monitorTempDirectory("cached-failure-ttl")
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 1_910_000_000)
        var task = AIProgressTask(id: "waiting", provider: .claude, title: "Waiting", progress: nil,
            status: .blocked, updatedAt: now)
        let detector = MutableActivityDetector(tasks: [task])
        let monitor = AIStateMonitor(directoryURL: directory, activityDetectors: [detector],
            activeTaskTTL: 30, now: { now })
        monitor.reload(includeUsageSamples: false)
        #expect(monitor.state.tasks == [task])

        detector.setFailure(true)
        now = now.addingTimeInterval(30)
        monitor.reload(includeUsageSamples: false)
        #expect(monitor.state.tasks == [task], "A failed read must not look like task completion")
        now = now.addingTimeInterval(1)
        monitor.reload(includeUsageSamples: false)
        #expect(monitor.state.tasks.isEmpty, "A cached failed read must still respect the active-task TTL")

        task.status = .running
        task.updatedAt = now
        detector.replaceTasks(with: [task])
        detector.setFailure(false)
        monitor.reload(includeUsageSamples: false)
        #expect(monitor.state.tasks == [task])
    }

    @Test @MainActor
    func restartRefreshesDetectorsEvenWhenPersistenceDidNotChange() async {
        let directory = monitorTempDirectory("restart-unchanged")
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = AIProgressTask(id: "before-stop", provider: .codex, title: "Codex", progress: nil, updatedAt: .now)
        let detector = MutableActivityDetector(tasks: [task])
        let monitor = AIStateMonitor(directoryURL: directory, activityDetectors: [detector],
            detectorRefreshInterval: Self.testPeriodicRefreshInterval)
        defer { monitor.stop() }
        monitor.start()
        #expect(await waitForMonitorState { monitor.state.tasks == [task] })
        let initialCalls = detector.callCount
        monitor.stop()
        detector.replaceTasks(with: [])
        monitor.start()
        #expect(await waitForMonitorState { monitor.state.tasks.isEmpty })
        #expect(detector.callCount == initialCalls + 1)
    }

    @Test @MainActor
    func queuedTimerCallbacksCannotRestartCollectionAfterStop() async throws {
        let directory = monitorTempDirectory("stop-queued-timers")
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = AIProgressTask(id: "before-stop", provider: .codex, title: "Codex", progress: nil, updatedAt: .now)
        let detector = MutableActivityDetector(tasks: [task])
        let usage = CountingUsageDetector()
        let monitor = AIStateMonitor(directoryURL: directory, activityDetectors: [detector],
            usageDetectors: [usage], detectorRefreshInterval: Self.testPeriodicRefreshInterval)
        defer { monitor.stop() }
        monitor.start()
        #expect(await waitForMonitorState { monitor.state.tasks == [task] })
        let calls = detector.callCount
        try #require(monitor.activityTimer).fire()
        try #require(monitor.usageTimer).fire()
        monitor.stop()
        // Drain the enqueued main-actor callbacks, then their serialized background work.
        await Task { @MainActor in }.value
        _ = try await monitor.readUsageHistory()
        #expect(detector.callCount == calls)
        #expect(usage.callCount == 0)
        #expect(monitor.state.tasks == [task])
    }

    @Test @MainActor
    func stoppedInFlightDetectionCannotPublishIntoRestart() async {
        let directory = monitorTempDirectory("restart-in-flight")
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = AIProgressTask(id: "old-generation", provider: .codex, title: "Old", progress: nil, updatedAt: .now)
        let new = AIProgressTask(id: "new-generation", provider: .codex, title: "New", progress: nil, updatedAt: .now)
        let detector = MutableActivityDetector(tasks: [old])
        let gate = detector.suspendNextCall()
        defer { gate.signal() }
        let monitor = AIStateMonitor(directoryURL: directory, activityDetectors: [detector],
            detectorRefreshInterval: Self.testPeriodicRefreshInterval)
        defer { monitor.stop() }
        var observedIDs: [String] = []
        let observation = monitor.$state.sink { observedIDs.append(contentsOf: $0.tasks.map(\.id)) }
        defer { withExtendedLifetime(observation) {} }
        monitor.start()
        #expect(await waitForMonitorState { detector.callCount == 1 })
        monitor.stop()
        detector.replaceTasks(with: [new])
        monitor.start()
        gate.signal()
        #expect(await waitForMonitorState { monitor.state.tasks == [new] })
        #expect(!observedIDs.contains(old.id), "An obsolete scan must never publish during the new lifecycle")
    }

    @Test @MainActor
    func coalescedLogEventsRefreshAllChangedSourcesAndKeepUnchangedTasks() async throws {
        let directory = monitorTempDirectory("coalesced-log-events")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logs = ["codex.jsonl", "claude.jsonl"].map { directory.appendingPathComponent($0) }
        for log in logs { try Data().write(to: log) }
        let tasks = [AIProvider.codex, .claude, .gemini].map {
            AIProgressTask(id: $0.rawValue, provider: $0, title: $0.rawValue, progress: nil, updatedAt: .now)
        }
        let detectors = tasks.enumerated().map {
            MutableActivityDetector(tasks: [$0.element], activityFileURLs: $0.offset < logs.count ? [logs[$0.offset]] : [])
        }
        let monitor = AIStateMonitor(directoryURL: directory.appendingPathComponent("state"),
            activityDetectors: detectors, detectorRefreshInterval: Self.testPeriodicRefreshInterval)
        defer { monitor.stop() }
        monitor.start()
        #expect(await waitForMonitorState { monitor.state.tasks == tasks })
        var blocked = tasks[0]
        blocked.status = .blocked
        detectors[0].replaceTasks(with: [blocked])
        detectors[1].replaceTasks(with: [])
        for log in logs { try Data("changed\n".utf8).write(to: log) }
        #expect(await waitForMonitorState { monitor.state.tasks == [blocked, tasks[2]] })
        #expect(detectors[2].callCount == 1)
    }

    @Test @MainActor
    func busyDetectorCoalescesPendingSourcesWithoutDroppingUsageCollection() async throws {
        let directory = monitorTempDirectory("busy-detector-pending")
        defer { try? FileManager.default.removeItem(at: directory) }
        let tasks = [AIProvider.codex, .claude, .gemini].map {
            AIProgressTask(id: $0.rawValue, provider: $0, title: "initial", progress: nil, updatedAt: .now)
        }
        let detectors = tasks.map { MutableActivityDetector(tasks: [$0]) }
        let usage = CountingUsageDetector()
        let monitor = AIStateMonitor(directoryURL: directory, activityDetectors: detectors,
            usageDetectors: [usage], detectorRefreshInterval: Self.testPeriodicRefreshInterval)
        defer { monitor.stop() }
        monitor.start()
        #expect(await waitForMonitorState { monitor.state.tasks == tasks })
        let expected = tasks.map { task in
            var next = task
            next.status = .blocked
            return next
        }
        for index in detectors.indices { detectors[index].replaceTasks(with: [expected[index]]) }
        let gate = detectors[0].suspendNextCall()
        defer { gate.signal() }
        let timer = try #require(monitor.activityTimer)
        timer.fire()
        #expect(await waitForMonitorState { detectors[0].callCount == 2 })
        timer.fire()
        timer.fire()
        try #require(monitor.usageTimer).fire()
        await Task { @MainActor in }.value
        gate.signal()
        #expect(await waitForMonitorState { monitor.state.tasks == expected && usage.callCount == 1 })
        #expect(detectors.allSatisfy { $0.callCount == 2 },
            "Pending slots must merge without re-scanning the source already in flight")
    }

    @Test @MainActor
    func continuousLogWritesDoNotPostponeActivityUntilTheWriterStops() async throws {
        let directory = monitorTempDirectory("continuous-log-events")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = directory.appendingPathComponent("session.jsonl")
        try Data().write(to: log)
        var task = AIProgressTask(id: "streaming", provider: .claude, title: "Claude", progress: nil, updatedAt: .now)
        let detector = MutableActivityDetector(tasks: [task], activityFileURLs: [log])
        let monitor = AIStateMonitor(directoryURL: directory.appendingPathComponent("state"),
            activityDetectors: [detector], detectorRefreshInterval: Self.testPeriodicRefreshInterval)
        defer { monitor.stop() }
        monitor.start()
        #expect(await waitForMonitorState { monitor.state.tasks == [task] })
        task.status = .blocked
        detector.replaceTasks(with: [task])
        let writer = Task { @MainActor in
            let handle = try FileHandle(forWritingTo: log)
            defer { try? handle.close() }
            while !Task.isCancelled {
                try handle.write(contentsOf: Data("event\n".utf8))
                // Model a steady producer that outpaces the 250 ms event-coalescing window.
                try await Task.sleep(for: .milliseconds(25))
            }
        }
        defer { writer.cancel() }
        #expect(await waitForMonitorState { monitor.state.tasks == [task] },
            "A growing log must publish updates while writes continue")
        writer.cancel()
        _ = await writer.result
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
    private struct DetectionError: Error {}
    private let lock = NSLock()
    private var tasks: [AIProgressTask]
    private var calls = 0
    private var fails = false
    private var nextCallGate: DispatchSemaphore?
    let activityFileURLs: [URL]

    init(tasks: [AIProgressTask], activityFileURLs: [URL] = []) {
        self.tasks = tasks
        self.activityFileURLs = activityFileURLs
    }

    func activeTasks() throws -> [AIProgressTask] {
        let snapshot = lock.withLock {
            calls += 1
            let gate = nextCallGate
            nextCallGate = nil
            return (tasks, fails, gate)
        }
        if let gate = snapshot.2, gate.wait(timeout: .now() + 10) == .timedOut { throw DetectionError() }
        if snapshot.1 { throw DetectionError() }
        return snapshot.0
    }

    func setFailure(_ value: Bool) {
        lock.withLock { fails = value }
    }

    func suspendNextCall() -> DispatchSemaphore {
        lock.withLock {
            let gate = DispatchSemaphore(value: 0)
            nextCallGate = gate
            return gate
        }
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
    private let samples: [AIUsageSample]

    init(samples: [AIUsageSample] = []) {
        self.samples = samples
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func reset() {
        lock.withLock { calls = 0 }
    }

    func usageSamples() throws -> [AIUsageSample] {
        lock.withLock { calls += 1 }
        return samples
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
