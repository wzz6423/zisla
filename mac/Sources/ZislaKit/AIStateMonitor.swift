import Combine
import Darwin
import Foundation
import ZislaCore

@MainActor
public final class AIStateMonitor: ObservableObject {
    private final class RefreshDependencies: @unchecked Sendable {
        let repository: AIStateRepository
        let activityDetectors: [any AIActivityDetecting]
        let usageDetectors: [any AIUsageDetecting]
        let activeTaskTTL: TimeInterval
        let now: () -> Date

        init(
            repository: AIStateRepository,
            activityDetectors: [any AIActivityDetecting],
            usageDetectors: [any AIUsageDetecting],
            activeTaskTTL: TimeInterval,
            now: @escaping () -> Date
        ) {
            self.repository = repository
            self.activityDetectors = activityDetectors
            self.usageDetectors = usageDetectors
            self.activeTaskTTL = activeTaskTTL
            self.now = now
        }
    }

    private enum PersistedRefreshResult: Sendable {
        case success(AIState, AIStateStorageChangeToken)
        case unchanged
        case corruptedState
        case failure(String)

        var allowsDetectorRefresh: Bool {
            switch self {
            case .success, .unchanged:
                true
            case .corruptedState, .failure:
                false
            }
        }
    }

    private enum DetectorRefreshResult: Sendable {
        case tasks([AIProgressTask])
        case state(AIState)
        case corruptedState
        case failure(String)
    }

    public static let defaultActiveTaskTTL: TimeInterval = 30 * 60
    public static let defaultDetectorRefreshInterval: TimeInterval = 30
    public static let defaultUsageRefreshInterval: TimeInterval = 3 * 60

    @Published public private(set) var state: AIState = .empty
    @Published public private(set) var errorDescription: String?

    private let repository: AIStateRepository
    private let activityDetectors: [any AIActivityDetecting]
    private let usageDetectors: [any AIUsageDetecting]
    private var source: DispatchSourceFileSystemObject?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var descriptor: Int32 = -1
    private var activityTimer: Timer?
    private let activeTaskTTL: TimeInterval
    private let detectorRefreshInterval: TimeInterval
    private let usageRefreshInterval: TimeInterval
    private let now: () -> Date
    private let refreshQueue = DispatchQueue(
        label: "dev.wzz.zisla.ai-state-refresh",
        qos: .utility
    )
    private var persistedReloadInFlight = false
    private var persistedReloadPending = false
    private var detectorRefreshInFlight = false
    private var detectorRefreshPending = false
    private var refreshGeneration: UInt64 = 0
    private var usageHistoryRequested = false
    private var usageHistoryIsLoaded = false
    private var lastUsageRefreshAt = Date.distantPast
    private var persistedStorageChangeToken: AIStateStorageChangeToken?
    private var persistedReloadPendingForce = false
    private var persistedTasks: [AIProgressTask] = []

    public convenience init(
        directoryURL: URL = AppPaths.applicationSupport,
        activeTaskTTL: TimeInterval = AIStateMonitor.defaultActiveTaskTTL,
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            directoryURL: directoryURL,
            activityDetectors: Self.defaultActivityDetectors(),
            usageDetectors: [AIUsageLogDetector()],
            activeTaskTTL: activeTaskTTL,
            now: now
        )
    }

    public convenience init(
        directoryURL: URL = AppPaths.applicationSupport,
        codexSessionsDirectory: URL?,
        activeTaskTTL: TimeInterval = AIStateMonitor.defaultActiveTaskTTL,
        now: @escaping () -> Date = Date.init
    ) {
        let detectors: [any AIActivityDetecting] = codexSessionsDirectory.map {
            [CodexSessionActivityDetector(sessionsDirectory: $0)]
        } ?? []
        self.init(
            directoryURL: directoryURL,
            activityDetectors: detectors,
            usageDetectors: [],
            activeTaskTTL: activeTaskTTL,
            now: now
        )
    }

    public init(
        directoryURL: URL = AppPaths.applicationSupport,
        activityDetectors: [any AIActivityDetecting],
        usageDetectors: [any AIUsageDetecting] = [],
        activeTaskTTL: TimeInterval = AIStateMonitor.defaultActiveTaskTTL,
        detectorRefreshInterval: TimeInterval = AIStateMonitor.defaultDetectorRefreshInterval,
        usageRefreshInterval: TimeInterval = AIStateMonitor.defaultUsageRefreshInterval,
        now: @escaping () -> Date = Date.init
    ) {
        repository = AIStateRepository(directoryURL: directoryURL)
        self.activityDetectors = activityDetectors
        self.usageDetectors = usageDetectors
        self.activeTaskTTL = max(0, activeTaskTTL)
        self.detectorRefreshInterval = max(1, detectorRefreshInterval)
        self.usageRefreshInterval = max(1, usageRefreshInterval)
        self.now = now
    }

    static func defaultActivityDetectors() -> [any AIActivityDetecting] {
        [
            CodexSessionActivityDetector(),
            ClaudeSessionActivityDetector(maxTranscriptFiles: 4, initialTailBytes: 256 * 1_024),
            CopilotSessionActivityDetector(maxTranscriptFiles: 4, maxCLISessions: 4),
            KimiSessionActivityDetector(maxSessionFiles: 4, initialTailBytes: 256 * 1_024),
            GeminiSessionActivityDetector(
                maxSessionFiles: 4,
                initialTailBytes: 256 * 1_024,
                maximumLegacyJSONBytes: 256 * 1_024
            ),
            GrokSessionActivityDetector(maxSessionFiles: 4, initialTailBytes: 256 * 1_024),
            QwenSessionActivityDetector(maxRuntimeFiles: 4, initialTailBytes: 256 * 1_024),
            QoderSessionActivityDetector(maxLogFiles: 4, initialTailBytes: 256 * 1_024),
            ZCodeSessionActivityDetector(),
            TraeSessionActivityDetector(maxLogFiles: 4, tailBytes: 256 * 1_024),
            OpenCodeSessionActivityDetector(maxSessions: 4),
            PiSessionActivityDetector(maxSessionFiles: 4),
            HarnessSessionActivityDetector(maxFiles: 4),
            HarnessSessionActivityDetector(
                dataRoot: HarnessSessionActivityDetector.deepSeekDataRoot(),
                sourceName: HarnessSessionActivityDetector.deepSeekSourceName,
                maxFiles: 4
            ),
            WorkBuddySessionActivityDetector(),
            DoubaoSessionActivityDetector(maxFiles: 4),
        ]
    }

    public func start() {
        stop()
        do {
            try FileManager.default.createDirectory(
                at: repository.directoryURL,
                withIntermediateDirectories: true
            )
            schedulePersistedReload(refreshDetectorsAfterLoad: true)
            descriptor = open(repository.directoryURL.path, O_EVTONLY)
            guard descriptor >= 0 else {
                errorDescription = "无法监听 AI 状态目录"
                return
            }

            let watcher = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            watcher.setEventHandler { [weak self] in
                self?.schedulePersistedReload()
            }
            let fileDescriptor = descriptor
            watcher.setCancelHandler {
                close(fileDescriptor)
            }
            source = watcher
            watcher.resume()

            let pressureQueue = refreshQueue
            let memoryPressure = DispatchSource.makeMemoryPressureSource(
                eventMask: [.warning, .critical],
                queue: pressureQueue
            )
            memoryPressure.setEventHandler {
                Self.scheduleAllocatorRelief(on: pressureQueue)
            }
            memoryPressureSource = memoryPressure
            memoryPressure.resume()

            if !activityDetectors.isEmpty || !usageDetectors.isEmpty {
                let timer = Timer(timeInterval: detectorRefreshInterval, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.scheduleDetectorRefresh() }
                }
                timer.tolerance = detectorRefreshInterval * 0.1
                activityTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    public func stop() {
        refreshGeneration &+= 1
        persistedReloadInFlight = false
        persistedReloadPending = false
        persistedReloadPendingForce = false
        detectorRefreshInFlight = false
        detectorRefreshPending = false
        lastUsageRefreshAt = .distantPast
        unloadUsageHistory()
        source?.cancel()
        source = nil
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        descriptor = -1
        activityTimer?.invalidate()
        activityTimer = nil
    }

    public func reload(includeUsageSamples: Bool = true) {
        usageHistoryRequested = includeUsageSamples
        let dependencies = refreshDependencies()
        applyPersisted(
            refreshQueue.sync {
                Self.loadPersistedState(
                    using: dependencies,
                    after: nil,
                    includeUsageSamples: includeUsageSamples
                )
            },
            includesUsageSamples: includeUsageSamples
        )
        let storedTasks = persistedTasks
        applyDetector(refreshQueue.sync {
            Self.detectState(
                using: dependencies,
                persistedTasks: storedTasks,
                detectsUsage: !usageDetectors.isEmpty,
                loadsUsageHistory: includeUsageSamples
            )
        })
    }

    /// Loads the full usage history only when the line chart or heatmap appears.
    public func loadUsageHistory() {
        guard !usageHistoryIsLoaded else { return }
        usageHistoryRequested = true
        lastUsageRefreshAt = .distantPast
        schedulePersistedReload(force: true)
    }

    /// Immediately releases historical samples that are no longer needed for the normal state display after leaving the AI panel.
    public func unloadUsageHistory() {
        guard usageHistoryRequested || usageHistoryIsLoaded || !state.usageSamples.isEmpty else { return }
        usageHistoryRequested = false
        usageHistoryIsLoaded = false
        let shouldRelieveMemory = !state.usageSamples.isEmpty
        state.usageSamples.removeAll(keepingCapacity: false)
        if shouldRelieveMemory {
            Self.scheduleAllocatorRelief(on: refreshQueue)
        }
    }

    /// Schedules a background refresh for interactive paths, avoiding a full decode of large state files on the main thread.
    public func refresh() {
        schedulePersistedReload()
    }

    private func schedulePersistedReload(
        refreshDetectorsAfterLoad: Bool = true,
        force: Bool = false
    ) {
        guard !persistedReloadInFlight else {
            persistedReloadPending = true
            persistedReloadPendingForce = persistedReloadPendingForce || force
            return
        }
        persistedReloadInFlight = true
        let generation = refreshGeneration
        let dependencies = refreshDependencies()
        let includesUsageSamples = usageHistoryRequested
        let storageChangeToken = force ? nil : persistedStorageChangeToken
        let completion: @MainActor @Sendable (PersistedRefreshResult) -> Void = { [weak self] result in
            guard let self, self.refreshGeneration == generation else { return }
            self.persistedReloadInFlight = false
            self.applyPersisted(result, includesUsageSamples: includesUsageSamples)
            if refreshDetectorsAfterLoad, result.allowsDetectorRefresh {
                self.scheduleDetectorRefresh()
            }
            if self.persistedReloadPending {
                self.persistedReloadPending = false
                let pendingForce = self.persistedReloadPendingForce
                self.persistedReloadPendingForce = false
                self.schedulePersistedReload(force: pendingForce)
            }
        }

        refreshQueue.async {
            let result = Self.loadPersistedState(
                using: dependencies,
                after: storageChangeToken,
                includeUsageSamples: includesUsageSamples
            )
            Task { @MainActor in completion(result) }
        }
    }

    private func scheduleDetectorRefresh() {
        guard !detectorRefreshInFlight else {
            detectorRefreshPending = true
            return
        }
        detectorRefreshInFlight = true
        let generation = refreshGeneration
        let dependencies = refreshDependencies()
        let storedTasks = persistedTasks
        let loadsUsageHistory = usageHistoryIsLoaded
        let detectsUsage = !usageDetectors.isEmpty
            && now().timeIntervalSince(lastUsageRefreshAt) >= usageRefreshInterval
        if detectsUsage { lastUsageRefreshAt = now() }
        let completion: @MainActor @Sendable (DetectorRefreshResult) -> Void = { [weak self] result in
            guard let self, self.refreshGeneration == generation else { return }
            self.detectorRefreshInFlight = false
            self.applyDetector(result)
            if self.detectorRefreshPending {
                self.detectorRefreshPending = false
                self.scheduleDetectorRefresh()
            }
        }

        refreshQueue.async {
            let result = Self.detectState(
                using: dependencies,
                persistedTasks: storedTasks,
                detectsUsage: detectsUsage,
                loadsUsageHistory: loadsUsageHistory
            )
            if detectsUsage { Self.scheduleAllocatorRelief(on: self.refreshQueue) }
            Task { @MainActor in completion(result) }
        }
    }

    private nonisolated static func scheduleAllocatorRelief(on queue: DispatchQueue) {
        queue.async {
            autoreleasepool { _ = malloc_zone_pressure_relief(nil, 0) }
            queue.asyncAfter(deadline: .now() + .milliseconds(100)) {
                autoreleasepool { _ = malloc_zone_pressure_relief(nil, 0) }
            }
        }
    }

    private func refreshDependencies() -> RefreshDependencies {
        RefreshDependencies(
            repository: repository,
            activityDetectors: activityDetectors,
            usageDetectors: usageDetectors,
            activeTaskTTL: activeTaskTTL,
            now: now
        )
    }

    private nonisolated static func loadPersistedState(
        using dependencies: RefreshDependencies,
        after storageChangeToken: AIStateStorageChangeToken?,
        includeUsageSamples: Bool
    ) -> PersistedRefreshResult {
        do {
            let previous = dependencies.repository.storageChangeToken()
            guard previous != storageChangeToken else { return .unchanged }
            let state = try dependencies.repository.load(
                includeUsageSamples: includeUsageSamples
            )
            return .success(state, dependencies.repository.storageChangeToken())
        } catch AIStateRepositoryError.corruptedState {
            return .corruptedState
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private nonisolated static func detectState(
        using dependencies: RefreshDependencies,
        persistedTasks: [AIProgressTask],
        detectsUsage: Bool,
        loadsUsageHistory: Bool
    ) -> DetectorRefreshResult {
        do {
            var automaticUsage: [AIUsageSample] = []
            var usageScanComplete = true
            if detectsUsage {
                for detector in dependencies.usageDetectors {
                    let samples = autoreleasepool { try? detector.usageSamples() }
                    guard let samples else {
                        usageScanComplete = false
                        continue
                    }
                    automaticUsage.append(contentsOf: samples)
                }
            }
            let tasks = mergedTasks(
                persistedTasks,
                using: dependencies
            )
            if detectsUsage, usageScanComplete {
                let usageChanged = try dependencies.repository.recordDetectedUsage(automaticUsage)
                if loadsUsageHistory {
                    if usageChanged > 0 {
                        var next = try dependencies.repository.load(includeUsageSamples: true)
                        next.tasks = tasks
                        return .state(next)
                    }
                }
            }
            return .tasks(tasks)
        } catch AIStateRepositoryError.corruptedState {
            return .corruptedState
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private nonisolated static func mergedTasks(
        _ persistedTasks: [AIProgressTask],
        using dependencies: RefreshDependencies
    ) -> [AIProgressTask] {
        var tasks = persistedTasks
        var detectedTaskIDs: Set<String> = []

        for detector in dependencies.activityDetectors {
            guard let automaticTasks = try? detector.activeTasks() else { continue }
            for task in automaticTasks {
                detectedTaskIDs.insert(task.id)
                if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[index] = task
                } else {
                    tasks.append(task)
                }
            }
        }

        // Remove active tasks no longer returned by detectors (completed or aborted).
        tasks.removeAll { task in
            guard task.status.isActive else { return false }
            // A task absent from both persistence and detector results has ended.
            let isPersistedTask = persistedTasks.contains(where: { $0.id == task.id })
            if !isPersistedTask && !detectedTaskIDs.contains(task.id) {
                return true
            }
            // Check TTL expiry.
            return dependencies.now().timeIntervalSince(task.updatedAt) > dependencies.activeTaskTTL
        }
        return tasks
    }

    private func applyPersisted(
        _ result: PersistedRefreshResult,
        includesUsageSamples: Bool,
        updatesPersistedTasks: Bool = true
    ) {
        switch result {
        case let .success(nextState, storageChangeToken):
            var next = nextState
            if updatesPersistedTasks { persistedTasks = nextState.tasks }
            let keepsUsageSamples = includesUsageSamples && usageHistoryRequested
            if !keepsUsageSamples {
                next.usageSamples.removeAll(keepingCapacity: false)
            }
            if next != state { state = next }
            if keepsUsageSamples {
                usageHistoryIsLoaded = true
            } else {
                usageHistoryIsLoaded = false
            }
            persistedStorageChangeToken = storageChangeToken
            errorDescription = nil
        case .unchanged:
            break
        case .corruptedState:
            errorDescription = "AI 状态文件已损坏，已保留上一次有效数据"
        case let .failure(message):
            errorDescription = message
        }
    }

    private func applyDetector(_ result: DetectorRefreshResult) {
        switch result {
        case let .tasks(tasks):
            if tasks != state.tasks { state.tasks = tasks }
            errorDescription = nil
        case let .state(next):
            applyPersisted(
                .success(next, repository.storageChangeToken()),
                includesUsageSamples: true,
                updatesPersistedTasks: false
            )
        case .corruptedState:
            errorDescription = "AI 状态文件已损坏，已保留上一次有效数据"
        case let .failure(message):
            errorDescription = message
        }
    }

}
