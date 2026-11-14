import AppKit
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

        init(
            repository: AIStateRepository,
            activityDetectors: [any AIActivityDetecting],
            usageDetectors: [any AIUsageDetecting]
        ) {
            self.repository = repository
            self.activityDetectors = activityDetectors
            self.usageDetectors = usageDetectors
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

    private struct ActivityDetection: Sendable {
        let tasks: [AIProgressTask]?
        let fileURLs: [URL]
    }

    private enum DetectorRefreshResult: Sendable {
        case tasks([Int: ActivityDetection], usageChanged: Bool)
        case state(AIState, activities: [Int: ActivityDetection])
        case corruptedState
        case failure(String)
    }

    private enum UsageHistoryLoadResult: Sendable {
        case samples(AIUsageHistory)
        case corruptedState
        case failure(String)
    }

    public static let defaultActiveTaskTTL: TimeInterval = 30 * 60
    public static let defaultDetectorRefreshInterval: TimeInterval = 60
    public static let defaultUsageRefreshInterval: TimeInterval = 5 * 60
    private static let usageHistoryWeeks = 24

    @Published public private(set) var state: AIState = .empty
    @Published public private(set) var errorDescription: String?
    @Published public private(set) var usageHistoryState: AIUsageHistoryState = .idle
    @Published public private(set) var failedUsageProviders: Set<AIProvider> = []
    @Published public private(set) var accountBalances: [AIAccountBalance] = []
    @Published public private(set) var isRefreshingAccountBalances = false
    @Published public private(set) var usageHistoryRevision: UInt64 = 0
    @Published public private(set) var isClearingUsageHistory = false

    private let repository: AIStateRepository
    private let activityDetectors: [any AIActivityDetecting]
    private let usageDetectors: [any AIUsageDetecting]
    private let subscriptionUsageDetector: (any AISubscriptionUsageDetecting)?
    private let accountBalanceDetector: (any AIAccountBalanceDetecting)?
    private let accountBalanceNotificationCenter: NotificationCenter
    private var accountBalanceObservers: [NSObjectProtocol] = []
    private var accountBalanceProviders = Set(AIProvider.allCases)
    private var accountBalanceQoderRegion = AIAccountBalanceQoderRegion.global
    private var accountBalanceTask: Task<Void, Never>?
    private var accountBalanceGeneration: UInt64 = 0
    private var lastAccountBalanceRefreshAt = Date.distantPast
    private var accountBalanceSuspended = false
    private var subscriptionUsageTask: Task<Void, Never>?
    private var lastSubscriptionRefreshAt = Date.distantPast
    private var source: DispatchSourceFileSystemObject?
    private var databaseSource: DispatchSourceFileSystemObject?
    private var walSource: DispatchSourceFileSystemObject?
    private var stateFileReloadTask: Task<Void, Never>?
    private var activityFileSources: [URL: DispatchSourceFileSystemObject] = [:]
    private var activityFileReloadTask: Task<Void, Never>?
    private var activityFileDetectorIndices: [URL: Set<Int>] = [:]
    private var activityFilePendingDetectorIndices: Set<Int> = []
    private var activityFilePendingURLs: Set<URL> = []
    private var detectedTasks: [Int: [AIProgressTask]] = [:]
    private var detectedActivityFileURLs: [Int: [URL]] = [:]
    private var usageHistoryLoadInFlight = false
    private var usageHistoryLoadPending = false
    private var usageHistoryGeneration: UInt64 = 0
    private var usageHistoryClearGeneration: UInt64 = 0
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var descriptor: Int32 = -1
    private(set) var activityTimer: Timer?
    private(set) var usageTimer: Timer?
    private var nextActivityDetectorIndex = 0
    private let activeTaskTTL: TimeInterval
    private let detectorRefreshInterval: TimeInterval
    private let usageRefreshInterval: TimeInterval
    private let now: () -> Date
    #if DEBUG
    private let debugEnvironment: [String: String]
    private var debugUsageHistoryCleared = false
    #endif
    private let refreshQueue = DispatchQueue(
        label: "dev.wzz.zisla.ai-state-refresh",
        qos: .utility
    )
    private var persistedReloadInFlight = false
    private var persistedReloadPending = false
    private var detectorRefreshInFlight = false
    private var detectorRefreshPendingIndices: Set<Int> = []
    private var detectorRefreshPendingFileURLs: Set<URL>?
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
            usageDetectors: Self.defaultUsageDetectors(),
            subscriptionUsageDetector: AISubscriptionUsageService(),
            accountBalanceDetector: AIAccountBalanceService(),
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
        subscriptionUsageDetector: (any AISubscriptionUsageDetecting)? = nil,
        accountBalanceDetector: (any AIAccountBalanceDetecting)? = nil,
        accountBalanceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        activeTaskTTL: TimeInterval = AIStateMonitor.defaultActiveTaskTTL,
        detectorRefreshInterval: TimeInterval = AIStateMonitor.defaultDetectorRefreshInterval,
        usageRefreshInterval: TimeInterval = AIStateMonitor.defaultUsageRefreshInterval,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: @escaping () -> Date = Date.init
    ) {
        repository = AIStateRepository(directoryURL: directoryURL)
        self.activityDetectors = activityDetectors
        self.usageDetectors = usageDetectors
        self.subscriptionUsageDetector = subscriptionUsageDetector
        self.accountBalanceDetector = accountBalanceDetector
        self.accountBalanceNotificationCenter = accountBalanceNotificationCenter
        self.activeTaskTTL = max(0, activeTaskTTL)
        self.detectorRefreshInterval = max(1, detectorRefreshInterval)
        self.usageRefreshInterval = max(1, usageRefreshInterval)
        self.now = now
        #if DEBUG
        debugEnvironment = environment
        #endif
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
            GeminiDesktopSessionActivityDetector(maxChats: 4),
            GrokSessionActivityDetector(maxSessionFiles: 4, initialTailBytes: 256 * 1_024),
            CursorSessionActivityDetector(),
            QwenSessionActivityDetector(maxRuntimeFiles: 4, initialTailBytes: 256 * 1_024),
            QoderSessionActivityDetector(maxLogFiles: 4, initialTailBytes: 256 * 1_024),
            ZCodeSessionActivityDetector(),
            ZedSessionActivityDetector(),
            DeltaSessionActivityDetector(),
            OrcaSessionActivityDetector(),
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
            WorkBuddyAISessionActivityDetector(),
        ]
    }

    static func defaultUsageDetectors() -> [any AIUsageDetecting] {
        [
            AIUsageLogDetector(),
            ZedUsageLogDetector(),
            DeltaSessionActivityDetector(),
            OrcaSessionActivityDetector(),
            ZCodeUsageDetector(),
        ]
    }

    /// Establishes one watcher lifecycle; persisted tasks load before their first activity-detector refresh.
    public func start() {
        guard source == nil else { return }
        stop()
        do {
            try FileManager.default.createDirectory(
                at: repository.directoryURL,
                withIntermediateDirectories: true
            )
            descriptor = open(repository.directoryURL.path, O_EVTONLY)
            guard descriptor >= 0 else {
                errorDescription = AppLocalization.text("无法监听 AI 状态目录")
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
            schedulePersistedReload(refreshDetectorsAfterLoad: true, refreshDetectorsWhenUnchanged: true)
            scheduleSubscriptionUsageRefresh()
            observeAccountBalanceLifecycle()
            scheduleAccountBalanceRefresh()

            let pressureQueue = refreshQueue
            let memoryPressure = DispatchSource.makeMemoryPressureSource(
                eventMask: [.warning, .critical],
                queue: pressureQueue
            )
            memoryPressure.setEventHandler { @Sendable in
                Self.scheduleAllocatorRelief(on: pressureQueue)
            }
            memoryPressureSource = memoryPressure
            memoryPressure.resume()

            if !activityDetectors.isEmpty {
                let slotInterval = detectorRefreshInterval / Double(activityDetectors.count)
                let timer = Timer(timeInterval: slotInterval, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.refreshGeneration == watcherGeneration else { return }
                        let index = self.nextActivityDetectorIndex
                        self.nextActivityDetectorIndex = (index + 1) % self.activityDetectors.count
                        self.scheduleDetectorRefresh(detectorIndices: [index], allowUsageScan: false)
                    }
                }
                timer.tolerance = slotInterval * 0.1
                activityTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
            if !usageDetectors.isEmpty || subscriptionUsageDetector != nil || accountBalanceDetector != nil {
                let checkInterval = min(detectorRefreshInterval, usageRefreshInterval)
                let timer = Timer(fire: Date(timeIntervalSinceNow: checkInterval),
                    interval: checkInterval, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.refreshGeneration == watcherGeneration else { return }
                        self.scheduleDetectorRefresh(detectorIndices: [], allowUsageScan: true)
                        self.scheduleSubscriptionUsageRefresh()
                        self.scheduleAccountBalanceRefresh()
                    }
                }
                timer.tolerance = checkInterval * 0.1
                usageTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    isolated deinit {
        accountBalanceTask?.cancel()
        accountBalanceObservers.forEach { accountBalanceNotificationCenter.removeObserver($0) }
    }

    /// Invalidates pending refresh generations before releasing observers, watchers, and timers.
    public func stop() {
        cancelAccountBalanceRefresh()
        accountBalanceObservers.forEach { accountBalanceNotificationCenter.removeObserver($0) }
        accountBalanceObservers.removeAll()
        accountBalanceSuspended = false
        lastAccountBalanceRefreshAt = .distantPast
        accountBalances = []
        refreshGeneration &+= 1
        subscriptionUsageTask?.cancel()
        subscriptionUsageTask = nil
        lastSubscriptionRefreshAt = .distantPast
        failedUsageProviders = []
        persistedReloadInFlight = false
        persistedReloadPending = false
        persistedReloadPendingForce = false
        persistedReloadPendingRefreshDetectorsAfterLoad = false
        persistedReloadPendingRefreshDetectorsWhenUnchanged = false
        stateFileReloadTask?.cancel()
        stateFileReloadTask = nil
        activityFileReloadTask?.cancel()
        activityFileReloadTask = nil
        activityFileSources.values.forEach { $0.cancel() }
        activityFileSources.removeAll()
        activityFileDetectorIndices.removeAll()
        activityFilePendingDetectorIndices.removeAll()
        activityFilePendingURLs.removeAll()
        detectedTasks.removeAll()
        detectedActivityFileURLs.removeAll()
        detectorRefreshInFlight = false
        detectorRefreshPendingIndices.removeAll()
        detectorRefreshPendingFileURLs = nil
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
        usageTimer?.invalidate()
        usageTimer = nil
        nextActivityDetectorIndex = 0
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
        applyDetector(refreshQueue.sync {
            Self.detectState(
                using: dependencies,
                detectorIndices: Set(activityDetectors.indices),
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
        guard usageHistoryRequested || usageHistoryIsLoaded || usageHistoryLoadInFlight || !state.usageSamples.isEmpty
            || !state.modelUsageSamples.isEmpty else {
            return
        }
        usageHistoryRequested = false
        usageHistoryIsLoaded = false
        usageHistoryGeneration &+= 1
        usageHistoryLoadInFlight = false
        usageHistoryLoadPending = false
        usageHistoryState = .idle
        let shouldRelieveMemory = !state.usageSamples.isEmpty || !state.modelUsageSamples.isEmpty
        state.usageSamples.removeAll(keepingCapacity: false)
        state.modelUsageSamples.removeAll(keepingCapacity: false)
        if shouldRelieveMemory {
            Self.scheduleAllocatorRelief(on: refreshQueue)
        }
    }

    /// A separate window owns its snapshot, so reading it cannot request or unload the island's history.
    public func readUsageHistory() async throws -> AIUsageHistory {
        try Task.checkCancellation()
        guard !isClearingUsageHistory else { throw CancellationError() }
        let generation = usageHistoryClearGeneration
        #if DEBUG
        if let history = debugUsageHistory() { return history }
        #endif
        let repository = repository
        let history: AIUsageHistory = try await withCheckedThrowingContinuation { continuation in
            refreshQueue.async {
                do { continuation.resume(returning: try repository.loadUsageHistory()) }
                catch { continuation.resume(throwing: error) }
            }
        }
        try Task.checkCancellation()
        guard generation == usageHistoryClearGeneration else { throw CancellationError() }
        return history
    }

    /// Serializes clearing with local scans and invalidates older panel reads before they can publish.
    public func clearUsageHistory() async throws {
        guard !isClearingUsageHistory else { throw CancellationError() }
        isClearingUsageHistory = true
        usageHistoryClearGeneration &+= 1
        usageHistoryGeneration &+= 1
        usageHistoryLoadInFlight = false
        usageHistoryLoadPending = false
        do {
            #if DEBUG
            if debugUsageHistory() != nil { debugUsageHistoryCleared = true }
            else { try await clearPersistedUsageHistory() }
            #else
            try await clearPersistedUsageHistory()
            #endif
            state.usageSamples.removeAll(keepingCapacity: false)
            state.modelUsageSamples.removeAll(keepingCapacity: false)
            usageHistoryIsLoaded = usageHistoryRequested
            usageHistoryState = usageHistoryRequested ? .loaded : .idle
            usageHistoryRevision &+= 1
            errorDescription = nil
            isClearingUsageHistory = false
        } catch {
            isClearingUsageHistory = false
            if usageHistoryRequested { requestUsageHistoryLoad(force: true) }
            throw error
        }
    }

    private func clearPersistedUsageHistory() async throws {
        let repository = repository
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            refreshQueue.async {
                do {
                    try repository.clearUsageHistory()
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    #if DEBUG
    /// A cleared preview stays empty for this process; restarting restores the environment fixture.
    private func debugUsageHistory() -> AIUsageHistory? {
        guard let history = AIModelUsageDebug.history(environment: debugEnvironment, now: now()) else { return nil }
        return debugUsageHistoryCleared ? AIUsageHistory() : history
    }
    #endif

    /// Schedules a background refresh for interactive paths, avoiding a full decode of large state files on the main thread.
    public func refresh() {
        scheduleAccountBalanceRefresh()
        scheduleSubscriptionUsageRefresh()
        schedulePersistedReload(
            refreshDetectorsAfterLoad: true,
            refreshDetectorsWhenUnchanged: true
        )
    }

    /// Invalidates old provider/region work and removes stale selection immediately, before the next query completes.
    public func configureAccountBalanceProviders(_ providers: Set<AIProvider>, qoderRegion: AIAccountBalanceQoderRegion = .global) {
        #if DEBUG
        let providers = AIAccountBalanceDebug.balances(environment: debugEnvironment, now: now())
            .map { Set($0.flatMap(\.providers)) } ?? providers
        #endif
        guard accountBalanceProviders != providers || accountBalanceQoderRegion != qoderRegion else { return }
        let regionChanged = accountBalanceQoderRegion != qoderRegion
        accountBalanceProviders = providers
        accountBalanceQoderRegion = qoderRegion
        cancelAccountBalanceRefresh()
        accountBalances = accountBalances.compactMap { balance in
            if regionChanged && balance.providers.contains(.coder) { return nil }
            var row = balance
            row.providers = row.providers.filter { providers.contains($0) }
            return row.providers.isEmpty ? nil : row
        }
        lastAccountBalanceRefreshAt = .distantPast
        scheduleAccountBalanceRefresh()
    }

    /// Bypasses quota throttling after a saved credential change while preserving the running/awake boundary.
    public func refreshAccountBalancesAfterCredentialChange() {
        cancelAccountBalanceRefresh()
        lastAccountBalanceRefreshAt = .distantPast
        scheduleAccountBalanceRefresh()
    }

    /// Advances the publication generation as cancellation alone cannot prevent a late detector completion.
    private func cancelAccountBalanceRefresh() {
        accountBalanceGeneration &+= 1
        accountBalanceTask?.cancel()
        accountBalanceTask = nil
        isRefreshingAccountBalances = false
    }

    /// Suspends quota reads during sleep and forces a fresh generation on wake without retaining the monitor.
    private func observeAccountBalanceLifecycle() {
        guard accountBalanceDetector != nil else { return }
        for (name, suspended) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)] {
            let token = accountBalanceNotificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.accountBalanceSuspended = suspended
                    self.cancelAccountBalanceRefresh()
                    if !suspended {
                        self.lastAccountBalanceRefreshAt = .distantPast
                        self.scheduleAccountBalanceRefresh()
                    }
                }
            }
            accountBalanceObservers.append(token)
        }
    }

    /// Queries only while running, awake, selected, and past the throttle, with one quota task in flight.
    /// Cancellation reaches detached work; only the captured configuration generation may publish ephemeral balances.
    private func scheduleAccountBalanceRefresh() {
        guard source != nil, !accountBalanceSuspended, !accountBalanceProviders.isEmpty,
              let detector = accountBalanceDetector, accountBalanceTask == nil,
              now().timeIntervalSince(lastAccountBalanceRefreshAt) >= usageRefreshInterval else { return }
        lastAccountBalanceRefreshAt = now()
        let generation = accountBalanceGeneration
        let providers = accountBalanceProviders
        let qoderRegion = accountBalanceQoderRegion
        isRefreshingAccountBalances = true
        accountBalanceTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let work = Task.detached(priority: .utility) { try await detector.accountBalances(for: providers, qoderRegion: qoderRegion) }
            let result = await withTaskCancellationHandler { await work.result } onCancel: { work.cancel() }
            guard !Task.isCancelled, let self, self.accountBalanceGeneration == generation else { return }
            self.accountBalanceTask = nil
            self.isRefreshingAccountBalances = false
            switch result {
            case let .success(balances): self.accountBalances = balances
            case .failure:
                self.accountBalances = AIAccountBalanceCatalog.groups.compactMap { group in
                    let selected = group.filter { providers.contains($0) }
                    guard !selected.isEmpty else { return nil }
                    var balance = AIAccountBalanceCatalog.placeholder(for: selected)
                    if balance.status == .notSignedIn || balance.status == .additionalCredentialsRequired { balance.status = .unavailable }
                    return balance
                }
            }
        }
    }

    /// Refreshes loaded history for metadata-only writes while rejecting results from an obsolete generation.
    private func scheduleSubscriptionUsageRefresh() {
        guard let detector = subscriptionUsageDetector, subscriptionUsageTask == nil,
              now().timeIntervalSince(lastSubscriptionRefreshAt) >= usageRefreshInterval else { return }
        lastSubscriptionRefreshAt = now()
        let generation = refreshGeneration
        let repository = repository
        subscriptionUsageTask = Task { [weak self] in
            let work = Task.detached(priority: .utility) { await detector.subscriptionUsage() }
            let result = await withTaskCancellationHandler {
                await work.value
            } onCancel: { work.cancel() }
            guard !Task.isCancelled, let self, self.refreshGeneration == generation else { return }
            defer { if self.refreshGeneration == generation { self.subscriptionUsageTask = nil } }
            self.failedUsageProviders = result.failedUsageProviders
            if !result.usageSamples.isEmpty {
                do {
                    let changed = try await Task.detached(priority: .utility) {
                        let previous = repository.storageChangeToken()
                        let count = try repository.recordDetectedUsage(result.usageSamples)
                        return count > 0 || previous != repository.storageChangeToken()
                    }.value
                    guard self.refreshGeneration == generation else { return }
                    if changed, self.usageHistoryRequested { self.requestUsageHistoryLoad(force: true) }
                } catch {
                    guard self.refreshGeneration == generation else { return }
                    self.errorDescription = error.localizedDescription
                }
            }
        }
    }

    /// Refreshes only currently active sessions. Historical usage logs are deliberately excluded.
    public func refreshActiveTasks() {
        scheduleDetectorRefresh(allowUsageScan: false)
    }

    /// Coalesces forced reads and loads both ledgers off the main thread without reviving an unloaded panel.
    private func requestUsageHistoryLoad(force: Bool = false) {
        guard usageHistoryRequested, !isClearingUsageHistory else { return }
        if usageHistoryLoadInFlight {
            usageHistoryLoadPending = usageHistoryLoadPending || force
            return
        }

        usageHistoryLoadInFlight = true
        usageHistoryState = .loading
        usageHistoryGeneration &+= 1
        let historyGeneration = usageHistoryGeneration
        let monitorGeneration = refreshGeneration
        #if DEBUG
        if let history = debugUsageHistory() {
            applyUsageHistory(.samples(history), historyGeneration: historyGeneration,
                monitorGeneration: monitorGeneration)
            return
        }
        #endif
        let repository = repository
        let usageHistoryStart = usageHistoryStartDate(endingAt: now())
        let monitor = self
        refreshQueue.async { [weak monitor] in
            let result: UsageHistoryLoadResult
            do {
                result = .samples(try repository.loadUsageHistory(startingAt: usageHistoryStart))
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

    /// Accepts only the current panel generation and retains the last valid snapshot when a read fails.
    private func applyUsageHistory(
        _ result: UsageHistoryLoadResult,
        historyGeneration: UInt64,
        monitorGeneration: UInt64
    ) {
        guard usageHistoryGeneration == historyGeneration else { return }
        usageHistoryLoadInFlight = false
        guard refreshGeneration == monitorGeneration, usageHistoryRequested else { return }

        switch result {
        case let .samples(history):
            if state.usageSamples != history.usageSamples {
                state.usageSamples = history.usageSamples
            }
            if state.modelUsageSamples != history.modelUsageSamples {
                state.modelUsageSamples = history.modelUsageSamples
            }
            usageHistoryIsLoaded = true
            usageHistoryState = .loaded
            errorDescription = nil
        case .corruptedState:
            usageHistoryState = .failed(AppLocalization.text("AI 状态文件已损坏，已保留上一次有效数据"))
            errorDescription = AppLocalization.text("AI 状态文件已损坏，已保留上一次有效数据")
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

    private func refreshActivityFileWatchers() {
        guard source != nil else { return }
        activityFileDetectorIndices.removeAll(keepingCapacity: true)
        for (index, urls) in detectedActivityFileURLs {
            for url in urls {
                activityFileDetectorIndices[url.standardizedFileURL, default: []].insert(index)
            }
        }
        let paths = Set(activityFileDetectorIndices.keys)
        for url in Array(activityFileSources.keys) where !paths.contains(url) {
            activityFileSources.removeValue(forKey: url)?.cancel()
        }
        let generation = refreshGeneration
        for url in paths where activityFileSources[url] == nil {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let watcher = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main
            )
            watcher.setEventHandler { [weak self] in
                guard let self, self.refreshGeneration == generation else { return }
                if let events = self.activityFileSources[url]?.data, !events.intersection([.rename, .delete]).isEmpty {
                    self.activityFileSources.removeValue(forKey: url)?.cancel()
                }
                self.activityFilePendingDetectorIndices.formUnion(self.activityFileDetectorIndices[url] ?? [])
                self.activityFilePendingURLs.insert(url)
                // Flush a burst at a fixed deadline so a continuously growing log cannot starve activity updates.
                guard self.activityFileReloadTask == nil else { return }
                self.activityFileReloadTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .milliseconds(250))
                    } catch {
                        return
                    }
                    guard let self, self.refreshGeneration == generation else { return }
                    self.activityFileReloadTask = nil
                    let indices = self.activityFilePendingDetectorIndices
                    let changedURLs = self.activityFilePendingURLs
                    self.activityFilePendingDetectorIndices.removeAll()
                    self.activityFilePendingURLs.removeAll()
                    self.scheduleDetectorRefresh(detectorIndices: indices, allowUsageScan: false,
                                                 changedFileURLs: changedURLs)
                }
            }
            watcher.setCancelHandler { close(descriptor) }
            activityFileSources[url] = watcher
            watcher.resume()
        }
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

    /// Reconciles tasks lazily; watcher changes refresh model history only while the AI panel requests it.
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
            if result.changedPersistedState, self.usageHistoryRequested {
                self.requestUsageHistoryLoad(force: true)
            }
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

    private func scheduleDetectorRefresh(
        detectorIndices: Set<Int>? = nil, allowUsageScan: Bool, changedFileURLs: Set<URL>? = nil
    ) {
        let indices = detectorIndices ?? Set(activityDetectors.indices)
        guard !detectorRefreshInFlight else {
            if detectorRefreshPendingIndices.isEmpty {
                detectorRefreshPendingFileURLs = changedFileURLs
            } else if let pending = detectorRefreshPendingFileURLs, let changedFileURLs {
                detectorRefreshPendingFileURLs = pending.union(changedFileURLs)
            } else {
                detectorRefreshPendingFileURLs = nil
            }
            detectorRefreshPendingIndices.formUnion(indices)
            detectorRefreshPendingAllowsUsageScan =
                detectorRefreshPendingAllowsUsageScan || allowUsageScan
            return
        }
        let detectsUsage = allowUsageScan && !usageDetectors.isEmpty
            && now().timeIntervalSince(lastUsageRefreshAt) >= usageRefreshInterval
        guard !indices.isEmpty || detectsUsage else { return }
        detectorRefreshInFlight = true
        let generation = refreshGeneration
        let dependencies = refreshDependencies()
        if detectsUsage { lastUsageRefreshAt = now() }
        let completion: @MainActor @Sendable (DetectorRefreshResult) -> Void = { [weak self] result in
            guard let self, self.refreshGeneration == generation else { return }
            self.detectorRefreshInFlight = false
            self.applyDetector(result)
            if !self.detectorRefreshPendingIndices.isEmpty || self.detectorRefreshPendingAllowsUsageScan {
                let pendingIndices = self.detectorRefreshPendingIndices
                let pendingFileURLs = self.detectorRefreshPendingFileURLs
                self.detectorRefreshPendingIndices.removeAll()
                self.detectorRefreshPendingFileURLs = nil
                let pendingAllowsUsageScan = self.detectorRefreshPendingAllowsUsageScan
                self.detectorRefreshPendingAllowsUsageScan = false
                self.scheduleDetectorRefresh(detectorIndices: pendingIndices, allowUsageScan: pendingAllowsUsageScan,
                                             changedFileURLs: pendingFileURLs)
            }
        }

        refreshQueue.async {
            let result = Self.detectState(
                using: dependencies,
                detectorIndices: indices,
                detectsUsage: detectsUsage,
                loadsUsageHistory: false,
                changedFileURLs: changedFileURLs
            )
            // Page-entry refreshes inspect active tasks only; forcing allocator pressure relief
            // there can invalidate the just-composited Liquid Glass surface. Reclaim memory only
            // when this pass actually scanned usage history.
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
            usageDetectors: usageDetectors
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

    /// Persists a complete usage scan and detects metadata writes before deciding whether loaded history is stale.
    private nonisolated static func detectState(
        using dependencies: RefreshDependencies,
        detectorIndices: Set<Int>,
        detectsUsage: Bool,
        loadsUsageHistory: Bool,
        changedFileURLs: Set<URL>? = nil
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
            var activities: [Int: ActivityDetection] = [:]
            for index in detectorIndices.sorted() {
                let detector = dependencies.activityDetectors[index]
                activities[index] = ActivityDetection(tasks: try? detector.taskUpdates(changedFileURLs: changedFileURLs),
                                                      fileURLs: detector.activityFileURLs)
            }
            var usageChanged = false
            if detectsUsage, usageScanComplete {
                let previous = dependencies.repository.storageChangeToken()
                let count = try dependencies.repository.recordDetectedUsage(automaticUsage)
                usageChanged = count > 0 || previous != dependencies.repository.storageChangeToken()
                if loadsUsageHistory {
                    if usageChanged {
                        let next = try dependencies.repository.load(includeUsageSamples: true)
                        return .state(next, activities: activities)
                    }
                }
            }
            return .tasks(activities, usageChanged: usageChanged)
        } catch AIStateRepositoryError.corruptedState {
            return .corruptedState
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func mergedTasks() -> [AIProgressTask] {
        var tasks = persistedTasks

        for index in activityDetectors.indices {
            for task in detectedTasks[index] ?? [] {
                if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[index] = task
                } else {
                    tasks.append(task)
                }
            }
        }

        let currentTime = now()
        tasks.removeAll { task in
            guard task.status.isActive else { return false }
            return currentTime.timeIntervalSince(task.updatedAt) > activeTaskTTL
        }
        return tasks
    }

    /// Preserves requested histories during task-only reloads and releases both arrays after panel exit.
    private func applyPersisted(
        _ result: PersistedRefreshResult,
        includesUsageSamples: Bool,
        updatesPersistedTasks: Bool = true
    ) {
        switch result {
        case let .success(nextState, storageChangeToken):
            var next = nextState
            if updatesPersistedTasks { persistedTasks = nextState.tasks }
            next.tasks = mergedTasks()
            let keepsExistingUsageSamples = !includesUsageSamples && usageHistoryRequested
            let keepsLoadedUsageSamples = keepsExistingUsageSamples || (includesUsageSamples && usageHistoryRequested)
            if keepsExistingUsageSamples {
                next.usageSamples = state.usageSamples
                next.modelUsageSamples = state.modelUsageSamples
            } else if !keepsLoadedUsageSamples {
                next.usageSamples.removeAll(keepingCapacity: false)
                next.modelUsageSamples.removeAll(keepingCapacity: false)
            }
            #if DEBUG
            if includesUsageSamples, usageHistoryRequested,
               let history = debugUsageHistory() {
                next.usageSamples = history.usageSamples
                next.modelUsageSamples = history.modelUsageSamples
            }
            #endif
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
            errorDescription = AppLocalization.text("AI 状态文件已损坏，已保留上一次有效数据")
        case let .failure(message):
            errorDescription = message
        }
    }

    private func applyDetector(_ result: DetectorRefreshResult) {
        switch result {
        case let .tasks(activities, usageChanged):
            applyActivityDetections(activities)
            let tasks = mergedTasks()
            if tasks != state.tasks { state.tasks = tasks }
            errorDescription = nil
            if usageChanged, usageHistoryRequested {
                requestUsageHistoryLoad(force: true)
            }
        case let .state(next, activities):
            applyActivityDetections(activities)
            applyPersisted(
                .success(next, repository.storageChangeToken()),
                includesUsageSamples: true,
                updatesPersistedTasks: false
            )
        case .corruptedState:
            errorDescription = AppLocalization.text("AI 状态文件已损坏，已保留上一次有效数据")
        case let .failure(message):
            errorDescription = message
        }
    }

    private func applyActivityDetections(_ activities: [Int: ActivityDetection]) {
        for (index, activity) in activities {
            // A failed read is not a completion signal; keep the last snapshot subject to the normal task TTL.
            if let tasks = activity.tasks { detectedTasks[index] = tasks }
            detectedActivityFileURLs[index] = activity.fileURLs
        }
        refreshActivityFileWatchers()
    }

}
