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
    func refreshDetectsNewActivityWhenPersistedStateIsUnchanged() async {
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

        monitor.start()
        #expect(await waitForDetectorCall(detector))

        detector.replaceTasks(with: [task])
        monitor.refresh()

        #expect(await waitForMonitorState(timeout: 10) { monitor.state.tasks == [task] })
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
    private var callCount = 0

    init(tasks: [AIProgressTask]) {
        self.tasks = tasks
    }

    func activeTasks() throws -> [AIProgressTask] {
        lock.lock()
        defer { lock.unlock() }
        callCount += 1
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
        return callCount > 0
    }
}

@MainActor
private func waitForDetectorCall(
    _ detector: MutableActivityDetector,
    timeout: TimeInterval = 2
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if detector.hasBeenCalled { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return detector.hasBeenCalled
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
