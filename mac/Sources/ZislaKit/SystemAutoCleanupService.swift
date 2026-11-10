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
        onTrashReservationFailure: @escaping (DesktopOrganizerError) -> Void = { _ in },
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
            lastRunKey: "trash-cleanup-last-run-v1", attemptKey: "trash-cleanup-attempt-v1",
            reservationFailure: {
                let error = DesktopOrganizerError.failed(CocoaError(.fileWriteUnknown).localizedDescription)
                onTrashReservationFailure(error)
                return .failure(error)
            }, timerFactory: timerFactory)
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
        if settings.trashCleanupPolicy == .never {
            trashCleanup.discardSchedule()
        } else {
            trashCleanup.apply(policy: settings.trashCleanupPolicy) { _ in await emptyTrash() }
        }
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
    private let attemptKey: String?
    private let reservationFailure: (() -> Outcome)?
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
        attemptKey: String? = nil,
        reservationFailure: (() -> Outcome)? = nil,
        timerFactory: @escaping (TimeInterval, @escaping @Sendable (Timer) -> Void) -> Timer
    ) {
        self.defaults = defaults
        self.now = now
        self.lastRunKey = lastRunKey
        self.attemptKey = attemptKey
        self.reservationFailure = reservationFailure
        self.timerFactory = timerFactory
    }

    func apply(policy: VoiceRecordingCleanupPolicy, operation: @escaping (Date) async -> Outcome?) {
        guard self.policy != policy else { return }
        stop()
        self.policy = policy
        guard let days = policy.daysThreshold else { return }
        self.operation = operation

        let interval = TimeInterval(days * 24 * 60 * 60)
        let lastRun: Date
        if let attemptKey, defaults.object(forKey: attemptKey) != nil {
            // An interrupted irreversible operation may have finished; wait a full interval from recovery.
            lastRun = now()
            defaults.set(lastRun, forKey: lastRunKey)
            if defaults.synchronize() { defaults.removeObject(forKey: attemptKey) }
        } else if let saved = defaults.object(forKey: lastRunKey) as? Date {
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

    func discardSchedule() {
        stop()
        defaults.removeObject(forKey: lastRunKey)
        if let attemptKey { defaults.removeObject(forKey: attemptKey) }
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
            if let attemptKey {
                defaults.set(referenceDate, forKey: attemptKey)
                // This once-per-cycle barrier must finish before irreversible work can start.
                guard defaults.synchronize() else {
                    nextCleanupDate = now().addingTimeInterval(interval)
                    timer.fireDate = nextCleanupDate
                    return reservationFailure?()
                }
            }
            guard let result = await operation(referenceDate), !Task.isCancelled else { return nil }
            let completedAt = now()
            // Failed attempts also wait for the next interval instead of repeatedly retrying protected files.
            defaults.set(completedAt, forKey: lastRunKey)
            if let attemptKey, defaults.synchronize() { defaults.removeObject(forKey: attemptKey) }
            nextCleanupDate = completedAt.addingTimeInterval(interval)
            timer.fireDate = nextCleanupDate
            return result
        }
        self.task = task
        return task
    }
}
