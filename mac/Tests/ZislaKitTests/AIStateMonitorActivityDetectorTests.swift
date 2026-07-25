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

private func monitorTempDirectory(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-monitor-\(label)-\(UUID().uuidString)", isDirectory: true)
}
