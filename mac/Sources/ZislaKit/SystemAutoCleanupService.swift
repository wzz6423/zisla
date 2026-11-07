import Foundation
import ZislaCore

@MainActor
public final class SystemAutoCleanupService {
    private let defaults: UserDefaults
    private let now: () -> Date
    private let scan: (Set<DiskCleanupKind>, DiskCleanupScanOptions) async -> [DiskCleanupCandidate]
    private let trash: ([DiskCleanupCandidate]) async -> DiskCleanupResult
    private let timerFactory: (TimeInterval, @escaping @Sendable (Timer) -> Void) -> Timer
    private let lastRunKey = "system-cleanup-last-run-v1"
    private var policy: VoiceRecordingCleanupPolicy = .never
    private var scope: SystemCleanupScope = .trustedOnly
    private var timer: Timer?
    private var nextCleanupDate = Date.distantFuture
    private var generation: UInt = 0
    private(set) var cleanupTask: Task<DiskCleanupResult?, Never>?

    public init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        scan: @escaping (Set<DiskCleanupKind>, DiskCleanupScanOptions) async -> [DiskCleanupCandidate],
        trash: @escaping ([DiskCleanupCandidate]) async -> DiskCleanupResult,
        timerFactory: @escaping (TimeInterval, @escaping @Sendable (Timer) -> Void) -> Timer = {
            Timer(timeInterval: $0, repeats: true, block: $1)
        }
    ) {
        self.defaults = defaults
        self.now = now
        self.scan = scan
        self.trash = trash
        self.timerFactory = timerFactory
    }

    isolated deinit {
        stop()
    }

    public func apply(settings: FeatureSettings) {
        let policy = settings.systemMonitorEnabled ? settings.systemCleanupPolicy : .never
        guard self.policy != policy || scope != settings.systemCleanupScope else { return }
        stop()
        self.policy = policy
        scope = settings.systemCleanupScope
        guard let days = policy.daysThreshold else { return }

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

    public func stop() {
        generation &+= 1
        timer?.invalidate()
        timer = nil
        cleanupTask?.cancel()
        cleanupTask = nil
        policy = .never
    }

    @discardableResult
    func runIfDue() -> Task<DiskCleanupResult?, Never>? {
        guard let timer, cleanupTask == nil, now() >= nextCleanupDate else { return nil }
        let generation = generation
        let scope = scope
        let interval = timer.timeInterval
        let referenceDate = now()
        let kinds = Set(DiskCleanupKind.allCases.filter {
            scope == .all ? $0.safetyLevel != .analysisOnly : $0.safetyLevel == .safeToClean
        })
        let task = Task { [weak self] () -> DiskCleanupResult? in
            guard let self, !Task.isCancelled else { return nil }
            defer {
                if self.generation == generation { self.cleanupTask = nil }
            }
            let candidates = await scan(kinds, DiskCleanupScanOptions(referenceDate: referenceDate))
            guard !Task.isCancelled else { return nil }
            let selected = candidates.filter {
                $0.isActionable && (scope == .all || $0.safetyLevel == .safeToClean)
            }
            let result = await trash(selected)
            guard !Task.isCancelled else { return nil }
            let completedAt = now()
            // Failed attempts also wait for the next interval instead of repeatedly retrying protected files.
            defaults.set(completedAt, forKey: lastRunKey)
            nextCleanupDate = completedAt.addingTimeInterval(interval)
            timer.fireDate = nextCleanupDate
            return result
        }
        cleanupTask = task
        return task
    }
}
