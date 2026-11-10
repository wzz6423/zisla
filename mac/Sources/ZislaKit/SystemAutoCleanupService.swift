import Foundation
import ZislaCore

@MainActor
public final class SystemAutoCleanupService {
    private let systemCleanup: CleanupSchedule<DiskCleanupResult>
    let trashCleanup: CleanupSchedule<Result<Void, DesktopOrganizerError>>
    private let scan: (Set<DiskCleanupKind>, DiskCleanupScanOptions) async -> [DiskCleanupCandidate]
    private let trash: ([DiskCleanupCandidate]) async -> DiskCleanupResult
    private let emptyTrash: () async -> Result<Void, DesktopOrganizerError>
    private var scope: SystemCleanupScope = .trustedOnly
    var cleanupTask: Task<DiskCleanupResult?, Never>? { systemCleanup.task }

    public init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        scan: @escaping (Set<DiskCleanupKind>, DiskCleanupScanOptions) async -> [DiskCleanupCandidate],
        trash: @escaping ([DiskCleanupCandidate]) async -> DiskCleanupResult,
        emptyTrash: @escaping () async -> Result<Void, DesktopOrganizerError> = { await DesktopOrganizer.emptyTrash() },
        timerFactory: @escaping (TimeInterval, @escaping @Sendable (Timer) -> Void) -> Timer = {
            Timer(timeInterval: $0, repeats: true, block: $1)
        }
    ) {
        self.scan = scan
        self.trash = trash
        self.emptyTrash = emptyTrash
        systemCleanup = CleanupSchedule(defaults: defaults, now: now,
            lastRunKey: "system-cleanup-last-run-v1", timerFactory: timerFactory)
        trashCleanup = CleanupSchedule(defaults: defaults, now: now,
            lastRunKey: "trash-cleanup-last-run-v1", timerFactory: timerFactory)
    }

    isolated deinit {
        stop()
    }

    public func apply(settings: FeatureSettings) {
        let policy = settings.systemMonitorEnabled ? settings.systemCleanupPolicy : .never
        if scope != settings.systemCleanupScope { systemCleanup.stop() }
        scope = settings.systemCleanupScope
        let scope = scope
        let scan = scan
        let trash = trash
        systemCleanup.apply(policy: policy) { referenceDate in
            let kinds = Set(DiskCleanupKind.allCases.filter {
                scope == .all ? $0.safetyLevel != .analysisOnly : $0.safetyLevel == .safeToClean
            })
            let candidates = await scan(kinds, DiskCleanupScanOptions(referenceDate: referenceDate))
            guard !Task.isCancelled else { return nil }
            let selected = candidates.filter {
                $0.isActionable && (scope == .all || $0.safetyLevel == .safeToClean)
            }
            return await trash(selected)
        }
        let emptyTrash = emptyTrash
        trashCleanup.apply(policy: settings.trashCleanupPolicy) { _ in await emptyTrash() }
    }

    public func stop() {
        systemCleanup.stop()
        trashCleanup.stop()
    }

    @discardableResult
    func runIfDue() -> Task<DiskCleanupResult?, Never>? {
        systemCleanup.runIfDue()
    }
}

@MainActor
final class CleanupSchedule<Outcome: Sendable> {
    private let defaults: UserDefaults
    private let now: () -> Date
    private let timerFactory: (TimeInterval, @escaping @Sendable (Timer) -> Void) -> Timer
    private let lastRunKey: String
    private var policy: VoiceRecordingCleanupPolicy = .never
    private var timer: Timer?
    private var nextCleanupDate = Date.distantFuture
    private var generation: UInt = 0
    private var operation: ((Date) async -> Outcome?)?
    private(set) var task: Task<Outcome?, Never>?

    init(
        defaults: UserDefaults,
        now: @escaping () -> Date,
        lastRunKey: String,
        timerFactory: @escaping (TimeInterval, @escaping @Sendable (Timer) -> Void) -> Timer
    ) {
        self.defaults = defaults
        self.now = now
        self.lastRunKey = lastRunKey
        self.timerFactory = timerFactory
    }

    isolated deinit {
        stop()
    }

    func apply(policy: VoiceRecordingCleanupPolicy, operation: @escaping (Date) async -> Outcome?) {
        guard self.policy != policy else { return }
        stop()
        self.policy = policy
        guard let days = policy.daysThreshold else { return }
        self.operation = operation

        let interval = TimeInterval(days * 24 * 60 * 60)
        let lastRun: Date
        if let saved = defaults.object(forKey: lastRunKey) as? Date {
            lastRun = saved
        } else {
            lastRun = now()
            defaults.set(lastRun, forKey: lastRunKey)
        }
        nextCleanupDate = lastRun.addingTimeInterval(interval)
        let timer = timerFactory(interval) { [weak self] timer in
            let timerID = ObjectIdentifier(timer)
            MainActor.assumeIsolated {
                guard let self, let activeTimer = self.timer,
                      ObjectIdentifier(activeTimer) == timerID else { return }
                self.runIfDue()
            }
        }
        self.timer = timer
        timer.fireDate = nextCleanupDate
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        generation &+= 1
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
        operation = nil
        policy = .never
    }

    @discardableResult
    func runIfDue() -> Task<Outcome?, Never>? {
        guard let timer, let operation, task == nil, now() >= nextCleanupDate else { return nil }
        let generation = generation
        let interval = timer.timeInterval
        let referenceDate = now()
        let task = Task { [weak self] () -> Outcome? in
            guard let self, !Task.isCancelled else { return nil }
            defer {
                if self.generation == generation { self.task = nil }
            }
            guard let result = await operation(referenceDate), !Task.isCancelled else { return nil }
            let completedAt = now()
            // Failed attempts also wait for the next interval instead of repeatedly retrying protected files.
            defaults.set(completedAt, forKey: lastRunKey)
            nextCleanupDate = completedAt.addingTimeInterval(interval)
            timer.fireDate = nextCleanupDate
            return result
        }
        self.task = task
        return task
    }
}
