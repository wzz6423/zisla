import Combine
import Darwin
import Foundation
import ZislaCore

public enum AIUsageHistoryState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

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

        var changedPersistedState: Bool {
            switch self {
            case .success:
                true
            case .unchanged, .corruptedState, .failure:
                false
            }
        }
    }

    private enum DetectorRefreshResult: Sendable {
        case tasks([AIProgressTask], usageChanged: Bool)
        case state(AIState)
        case corruptedState
        case failure(String)
    }

    private enum UsageHistoryLoadResult: Sendable {
        case samples([AIUsageSample])
        case corruptedState
        case failure(String)
    }

    public static let defaultActiveTaskTTL: TimeInterval = 30 * 60
    public static let defaultDetectorRefreshInterval: TimeInterval = 30
    public static let defaultUsageRefreshInterval: TimeInterval = 3 * 60
    private static let usageHistoryWeeks = 24

    @Published public private(set) var state: AIState = .empty
    @Published public private(set) var errorDescription: String?
    @Published public private(set) var usageHistoryState: AIUsageHistoryState = .idle

    private let repository: AIStateRepository
    private let activityDetectors: [any AIActivityDetecting]
    private let usageDetectors: [any AIUsageDetecting]
    private var source: DispatchSourceFileSystemObject?
    private var databaseSource: DispatchSourceFileSystemObject?
    private var walSource: DispatchSourceFileSystemObject?
    private var stateFileReloadTask: Task<Void, Never>?
    private var usageHistoryLoadInFlight = false
    private var usageHistoryLoadPending = false
    private var usageHistoryGeneration: UInt64 = 0
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
    private var detectorRefreshPendingAllowsUsageScan = false
    private var refreshGeneration: UInt64 = 0
    private var usageHistoryRequested = false
    private var usageHistoryIsLoaded = false
    private var lastUsageRefreshAt = Date.distantPast
    private var persistedStorageChangeToken: AIStateStorageChangeToken?
    private var persistedReloadPendingForce = false
    private var persistedReloadPendingRefreshDetectorsAfterLoad = false
    private var persistedReloadPendingRefreshDetectorsWhenUnchanged = false
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
            ClaudeSessionActivityDetector(maxTranscriptFiles: 12, initialTailBytes: 256 * 1_024),
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
            descriptor = open(repository.directoryURL.path, O_EVTONLY)
            guard descriptor >= 0 else {
                errorDescription = "无法监听 AI 状态目录"
                return
            }

            let watcherGeneration = refreshGeneration
            let watcher = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            watcher.setEventHandler { [weak self] in
                guard let self, self.refreshGeneration == watcherGeneration else { return }
                self.refreshStateFileWatchers(generation: watcherGeneration)
                self.scheduleStateFileReload()
            }
            let fileDescriptor = descriptor
            watcher.setCancelHandler {
                close(fileDescriptor)
            }
            source = watcher
            watcher.resume()
            refreshStateFileWatchers(generation: watcherGeneration)
            // Load persisted tasks first; the completion schedules one activity refresh with the
            // loaded task snapshot, while usage log scans remain on the throttled timer.
            schedulePersistedReload(refreshDetectorsAfterLoad: true)

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
                    Task { @MainActor [weak self] in
                        self?.scheduleDetectorRefresh(allowUsageScan: true)
                    }
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
        persistedReloadPendingRefreshDetectorsAfterLoad = false
        persistedReloadPendingRefreshDetectorsWhenUnchanged = false
        stateFileReloadTask?.cancel()
        stateFileReloadTask = nil
        detectorRefreshInFlight = false
        detectorRefreshPending = false
        detectorRefreshPendingAllowsUsageScan = false
        lastUsageRefreshAt = .distantPast
        usageHistoryGeneration &+= 1
        usageHistoryLoadInFlight = false
        usageHistoryLoadPending = false
        unloadUsageHistory()
        databaseSource?.cancel()
        databaseSource = nil
        walSource?.cancel()
        walSource = nil
        source?.cancel()
        source = nil
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        descriptor = -1
        activityTimer?.invalidate()
        activityTimer = nil
    }

    public func reload(includeUsageSamples: Bool = true) {
        usageHistoryGeneration &+= 1
        usageHistoryLoadInFlight = false
        usageHistoryLoadPending = false
        usageHistoryRequested = includeUsageSamples
        usageHistoryState = includeUsageSamples ? .loading : .idle
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

    /// Loads usage history in the background when the line chart or heatmap appears.
    public func loadUsageHistory() {
        usageHistoryRequested = true
        guard !usageHistoryIsLoaded, !usageHistoryLoadInFlight else { return }
        requestUsageHistoryLoad()
    }

    /// Immediately releases historical samples that are no longer needed for the normal state display after leaving the AI panel.
    public func unloadUsageHistory() {
        guard usageHistoryRequested || usageHistoryIsLoaded || usageHistoryLoadInFlight || !state.usageSamples.isEmpty else {
            return
        }
        usageHistoryRequested = false
        usageHistoryIsLoaded = false
        usageHistoryGeneration &+= 1
        usageHistoryLoadInFlight = false
        usageHistoryLoadPending = false
        usageHistoryState = .idle
        let shouldRelieveMemory = !state.usageSamples.isEmpty
        state.usageSamples.removeAll(keepingCapacity: false)
        if shouldRelieveMemory {
            Self.scheduleAllocatorRelief(on: refreshQueue)
        }
    }

    /// Schedules a background refresh for interactive paths, avoiding a full decode of large state files on the main thread.
    public func refresh() {
        schedulePersistedReload(
            refreshDetectorsAfterLoad: true,
            refreshDetectorsWhenUnchanged: true
        )
    }

    /// Refreshes only currently active sessions. Historical usage logs are deliberately excluded.
    public func refreshActiveTasks() {
        scheduleDetectorRefresh(allowUsageScan: false)
    }

    private func requestUsageHistoryLoad(force: Bool = false) {
        guard usageHistoryRequested else { return }
        if usageHistoryLoadInFlight {
            usageHistoryLoadPending = usageHistoryLoadPending || force
            return
        }

        usageHistoryLoadInFlight = true
        usageHistoryState = .loading
        usageHistoryGeneration &+= 1
        let historyGeneration = usageHistoryGeneration
        let monitorGeneration = refreshGeneration
        let repository = repository
        let usageHistoryStart = usageHistoryStartDate(endingAt: now())
        let monitor = self
        refreshQueue.async { [weak monitor] in
            let result: UsageHistoryLoadResult
            do {
                result = .samples(try repository.loadUsageSamples(startingAt: usageHistoryStart))
            } catch AIStateRepositoryError.corruptedState {
                result = .corruptedState
            } catch {
                result = .failure(error.localizedDescription)
            }
            Task { @MainActor [weak monitor] in
                monitor?.applyUsageHistory(
                    result,
                    historyGeneration: historyGeneration,
                    monitorGeneration: monitorGeneration
                )
            }
        }
    }

    private func applyUsageHistory(
        _ result: UsageHistoryLoadResult,
        historyGeneration: UInt64,
        monitorGeneration: UInt64
    ) {
        guard usageHistoryGeneration == historyGeneration else { return }
        usageHistoryLoadInFlight = false
        guard refreshGeneration == monitorGeneration, usageHistoryRequested else { return }

        switch result {
        case let .samples(samples):
            if state.usageSamples != samples {
                state.usageSamples = samples
            }
            usageHistoryIsLoaded = true
            usageHistoryState = .loaded
            errorDescription = nil
        case .corruptedState:
            usageHistoryState = .failed("AI 状态文件已损坏，已保留上一次有效数据")
            errorDescription = "AI 状态文件已损坏，已保留上一次有效数据"
        case let .failure(message):
            usageHistoryState = .failed(message)
            errorDescription = message
        }

        guard usageHistoryLoadPending else { return }
        usageHistoryLoadPending = false
        requestUsageHistoryLoad()
    }

    private func refreshStateFileWatchers(generation: UInt64) {
        guard refreshGeneration == generation else { return }
        if databaseSource != nil, !FileManager.default.fileExists(atPath: repository.databaseURL.path) {
            databaseSource?.cancel()
            databaseSource = nil
        }
        if walSource != nil, !FileManager.default.fileExists(atPath: repository.databaseWALURL.path) {
            walSource?.cancel()
            walSource = nil
        }
        startStateFileWatcher(
            at: repository.databaseURL,
            generation: generation,
            isWAL: false
        )
        startStateFileWatcher(
            at: repository.databaseWALURL,
            generation: generation,
            isWAL: true
        )
    }

    private func startStateFileWatcher(at url: URL, generation: UInt64, isWAL: Bool) {
        guard (isWAL ? walSource : databaseSource) == nil,
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        watcher.setEventHandler { [weak self] in
            guard let self, self.refreshGeneration == generation else { return }
            let event = watcher.data
            if event.contains(.rename) || event.contains(.delete) {
                self.rebindStateFileWatcher(generation: generation, isWAL: isWAL)
            }
            self.scheduleStateFileReload()
        }
        watcher.setCancelHandler {
            close(fileDescriptor)
        }
        if isWAL {
            walSource = watcher
        } else {
            databaseSource = watcher
        }
        watcher.resume()
    }

    private func rebindStateFileWatcher(generation: UInt64, isWAL: Bool) {
        guard refreshGeneration == generation else { return }
        if isWAL {
            walSource?.cancel()
            walSource = nil
        } else {
            databaseSource?.cancel()
            databaseSource = nil
        }
        startStateFileWatcher(
            at: isWAL ? repository.databaseWALURL : repository.databaseURL,
            generation: generation,
            isWAL: isWAL
        )
    }

    private func scheduleStateFileReload() {
        stateFileReloadTask?.cancel()
        let generation = refreshGeneration
        stateFileReloadTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            guard let self, self.refreshGeneration == generation else { return }
            self.stateFileReloadTask = nil
            // File changes only reconcile persisted tasks. Activity detectors are refreshed by
            // the page-entry path and the throttled timer, so a noisy SQLite/WAL writer cannot
            // turn every state update into a full session scan.
            self.schedulePersistedReload(refreshDetectorsAfterLoad: false)
        }
    }

    private func schedulePersistedReload(
        refreshDetectorsAfterLoad: Bool = true,
        force: Bool = false,
        refreshDetectorsWhenUnchanged: Bool = false
    ) {
        guard !persistedReloadInFlight else {
            persistedReloadPending = true
            persistedReloadPendingForce = persistedReloadPendingForce || force
            persistedReloadPendingRefreshDetectorsAfterLoad =
                persistedReloadPendingRefreshDetectorsAfterLoad || refreshDetectorsAfterLoad
            persistedReloadPendingRefreshDetectorsWhenUnchanged =
                persistedReloadPendingRefreshDetectorsWhenUnchanged || refreshDetectorsWhenUnchanged
            return
        }
        persistedReloadInFlight = true
        let generation = refreshGeneration
        let dependencies = refreshDependencies()
        // Historical samples have their own lazy read path; persisted reloads only reconcile
        // tasks and notices so a watcher event cannot pull the whole usage table into memory.
        let includesUsageSamples = false
        let storageChangeToken = force ? nil : persistedStorageChangeToken
        let completion: @MainActor @Sendable (PersistedRefreshResult) -> Void = { [weak self] result in
            guard let self, self.refreshGeneration == generation else { return }
            self.persistedReloadInFlight = false
            self.applyPersisted(result, includesUsageSamples: includesUsageSamples)
            if refreshDetectorsAfterLoad,
               result.changedPersistedState || refreshDetectorsWhenUnchanged {
                self.scheduleDetectorRefresh(allowUsageScan: false)
            }
            if self.persistedReloadPending {
                self.persistedReloadPending = false
                let pendingForce = self.persistedReloadPendingForce
                self.persistedReloadPendingForce = false
                let pendingRefreshDetectorsAfterLoad =
                    self.persistedReloadPendingRefreshDetectorsAfterLoad
                self.persistedReloadPendingRefreshDetectorsAfterLoad = false
                let pendingRefreshDetectorsWhenUnchanged =
                    self.persistedReloadPendingRefreshDetectorsWhenUnchanged
                self.persistedReloadPendingRefreshDetectorsWhenUnchanged = false
                self.schedulePersistedReload(
                    refreshDetectorsAfterLoad: pendingRefreshDetectorsAfterLoad,
                    force: pendingForce,
                    refreshDetectorsWhenUnchanged: pendingRefreshDetectorsWhenUnchanged
                )
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

    private func scheduleDetectorRefresh(allowUsageScan: Bool) {
        guard !detectorRefreshInFlight else {
            detectorRefreshPending = true
            detectorRefreshPendingAllowsUsageScan =
                detectorRefreshPendingAllowsUsageScan || allowUsageScan
            return
        }
        detectorRefreshInFlight = true
        let generation = refreshGeneration
        let dependencies = refreshDependencies()
        let storedTasks = persistedTasks
        let detectsUsage = allowUsageScan && !usageDetectors.isEmpty
            && now().timeIntervalSince(lastUsageRefreshAt) >= usageRefreshInterval
        if detectsUsage { lastUsageRefreshAt = now() }
        let completion: @MainActor @Sendable (DetectorRefreshResult) -> Void = { [weak self] result in
            guard let self, self.refreshGeneration == generation else { return }
            self.detectorRefreshInFlight = false
            self.applyDetector(result)
            if self.detectorRefreshPending {
                self.detectorRefreshPending = false
                let pendingAllowsUsageScan = self.detectorRefreshPendingAllowsUsageScan
                self.detectorRefreshPendingAllowsUsageScan = false
                self.scheduleDetectorRefresh(allowUsageScan: pendingAllowsUsageScan)
            }
        }

        refreshQueue.async {
            let result = Self.detectState(
                using: dependencies,
                persistedTasks: storedTasks,
                detectsUsage: detectsUsage,
                loadsUsageHistory: false
            )
            Self.scheduleAllocatorRelief(on: self.refreshQueue)
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

    private func usageHistoryStartDate(endingAt date: Date) -> Date {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: endDay)
        let daysFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        guard let lastWeekStart = calendar.date(byAdding: .day, value: -daysFromWeekStart, to: endDay),
              let gridStart = calendar.date(
                byAdding: .day,
                value: -(Self.usageHistoryWeeks - 1) * 7,
                to: lastWeekStart
              ) else {
            return endDay
        }
        return gridStart
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
            var usageChanged = false
            if detectsUsage, usageScanComplete {
                usageChanged = try dependencies.repository.recordDetectedUsage(automaticUsage) > 0
                if loadsUsageHistory {
                    if usageChanged {
                        var next = try dependencies.repository.load(includeUsageSamples: true)
                        next.tasks = tasks
                        return .state(next)
                    }
                }
            }
            return .tasks(tasks, usageChanged: usageChanged)
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
            let keepsExistingUsageSamples = !includesUsageSamples && usageHistoryRequested
            let keepsLoadedUsageSamples = keepsExistingUsageSamples || (includesUsageSamples && usageHistoryRequested)
            if keepsExistingUsageSamples {
                next.usageSamples = state.usageSamples
            } else if !keepsLoadedUsageSamples {
                next.usageSamples.removeAll(keepingCapacity: false)
            }
            if next != state { state = next }
            if includesUsageSamples && usageHistoryRequested {
                usageHistoryIsLoaded = true
                usageHistoryState = .loaded
            } else if !usageHistoryRequested {
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
        case let .tasks(tasks, usageChanged):
            if tasks != state.tasks { state.tasks = tasks }
            errorDescription = nil
            if usageChanged, usageHistoryRequested {
                requestUsageHistoryLoad(force: true)
            }
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
