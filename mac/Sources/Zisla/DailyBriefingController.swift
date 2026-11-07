import AppKit
import Combine
import ZislaCore
import ZislaKit

@MainActor
final class DailyBriefingController: ObservableObject {
    @Published private(set) var isExporting = false
    @Published private(set) var lastExportURL: URL?
    @Published private(set) var errorMessage: String?

    private let store: DailyBriefingStore
    private let observation: (Date) -> DailyBriefingObservation
    private let typing: @MainActor (Date) async throws -> DailyBriefingTyping?
    private let readScreenTime: @Sendable (DateInterval) async -> DailyBriefingScreenTimeResult
    private let export: @MainActor (DailyBriefingReport, DailyBriefingTemplate, AppLanguage, URL) async throws -> URL
    private var settings = DailyBriefingSettings(enabled: false)
    private var language = AppLanguage.simplifiedChinese
    private var directory = AppPaths.downloads
    private var loopTask: Task<Void, Never>?
    private var isTicking = false
    private var isSuspended = false
    private var isScreenLocked = false
    private var pendingActivities: [String: DailyBriefingActivityBatch] = [:]
    private var activityFlushTask: Task<Void, Error>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        store: DailyBriefingStore = DailyBriefingStore(),
        saveLocations: SaveLocationStore? = nil,
        observation: @escaping (Date) -> DailyBriefingObservation,
        typing: @escaping @MainActor (Date) async throws -> DailyBriefingTyping?,
        readScreenTime: @escaping @Sendable (DateInterval) async -> DailyBriefingScreenTimeResult = { range in
            await Task.detached(priority: .utility) { DailyBriefingScreenTimeReader().read(within: range) }.value
        },
        export: @escaping @MainActor (DailyBriefingReport, DailyBriefingTemplate, AppLanguage, URL) async throws -> URL = { report, template, language, directory in
            let accessing = directory.startAccessingSecurityScopedResource()
            defer { if accessing { directory.stopAccessingSecurityScopedResource() } }
            let png = try DailyBriefingRenderer.png(report: report, template: template, language: language)
            try Task.checkCancellation()
            return try await Task.detached(priority: .utility) {
                try DailyBriefingPNGExport.write(png, for: report.day.date, language: language, calendar: report.calendar, directory: directory)
            }.value
        }
    ) {
        self.store = store
        self.observation = observation
        self.typing = typing
        self.readScreenTime = readScreenTime
        self.export = export
        saveLocations?.$directories.sink { [weak self] directories in
            self?.directory = directories[.dailyBriefing]!
        }.store(in: &cancellables)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            center.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor in await self?.suspend() }
            }.store(in: &cancellables)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor in self?.isSuspended = false }
            }.store(in: &cancellables)
        }
    }

    deinit {
        loopTask?.cancel()
    }

    func configure(settings: DailyBriefingSettings, directory: URL, language: AppLanguage, startsTimer: Bool = true) {
        let changed = self.settings.enabled != settings.enabled
        self.settings = settings
        self.directory = directory
        self.language = language
        guard changed || settings.enabled && loopTask?.isCancelled == true else { return }
        let previous = loopTask
        previous?.cancel()
        guard startsTimer else { return }
        loopTask = Task { [weak self, store] in
            await previous?.value
            do {
                try await self?.flushActivities()
                try await store.suspend()
            } catch { self?.record(error) }
            guard !Task.isCancelled, self?.settings.enabled == true else { return }
            while !Task.isCancelled {
                await self?.tick(at: Date())
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    func stop() {
        var disabled = settings
        disabled.enabled = false
        configure(settings: disabled, directory: directory, language: language)
    }

    func prepareToTerminate() async -> Bool {
        loopTask?.cancel()
        await loopTask?.value
        do {
            try await store.suspend()
            try await flushActivities()
            settings.enabled = false
            return true
        } catch {
            record(error)
            configure(settings: settings, directory: directory, language: language)
            return false
        }
    }

    func suspend() async {
        isSuspended = true
        do {
            try await flushActivities()
            try await store.suspend()
        } catch { record(error) }
    }

    func recordActivity(_ activity: DailyBriefingActivity, count: Int = 1, focusSeconds: TimeInterval = 0, at date: Date = Date()) {
        guard settings.enabled else { return }
        var batch = DailyBriefingActivityBatch(date: date, calendar: DailyBriefingDay.calendar)
        guard batch.activity.record(activity, count: count, focusSeconds: focusSeconds) else { return }
        enqueue(batch)
    }

    func recordKeyPress(at date: Date) {
        guard settings.enabled else { return }
        let calendar = DailyBriefingDay.calendar
        var batch = DailyBriefingActivityBatch(date: date, calendar: calendar)
        batch.recordKeyPress(hour: calendar.component(.hour, from: date))
        enqueue(batch)
    }

    func setScreenLocked(_ locked: Bool, at date: Date = Date()) {
        if isScreenLocked, !locked { recordActivity(.unlocked, at: date) }
        isScreenLocked = locked
    }

    private func enqueue(_ batch: DailyBriefingActivityBatch) {
        do {
            if var combined = pendingActivities[batch.key] {
                try combined.merge(batch)
                pendingActivities[batch.key] = combined
            } else {
                pendingActivities[batch.key] = batch
            }
        } catch { record(error) }
    }

    private func flushActivities() async throws {
        while !pendingActivities.isEmpty || activityFlushTask != nil {
            if let task = activityFlushTask {
                try await task.value
                continue
            }
            let batches = Array(pendingActivities.values)
            pendingActivities.removeAll(keepingCapacity: true)
            let task = Task { @MainActor [weak self, store] in
                do {
                    try await store.recordActivities(batches, calendar: DailyBriefingDay.calendar)
                    self?.activityFlushTask = nil
                } catch {
                    for batch in batches { self?.enqueue(batch) }
                    self?.activityFlushTask = nil
                    throw error
                }
            }
            activityFlushTask = task
            try await task.value
        }
    }

    func recordExpansion(at date: Date = Date()) {
        guard settings.enabled else { return }
        Task {
            do { try await store.recordExpansion(at: date, calendar: DailyBriefingDay.calendar) }
            catch { record(error) }
        }
    }

    func tick(at now: Date) async {
        guard settings.enabled, !isSuspended, !isTicking else { return }
        isTicking = true
        defer { isTicking = false }
        do {
            try await flushActivities()
            try await store.observe(observation(now), calendar: DailyBriefingDay.calendar)
            let pending = try await store.pendingExports(at: now, settings: settings, calendar: DailyBriefingDay.calendar)
            for day in pending {
                try Task.checkCancellation()
                guard settings.enabled else { return }
                try await exportDay(day, now: now, scheduled: true)
            }
        } catch is CancellationError {
        } catch { record(error) }
    }

    func exportToday(at now: Date = Date()) async {
        guard settings.enabled, !isExporting else { return }
        do {
            try await flushActivities()
            let day = try await store.day(at: now, calendar: DailyBriefingDay.calendar)
            try await exportDay(day, now: now, scheduled: false)
        } catch is CancellationError {
        } catch { record(error) }
    }

    private func exportDay(_ day: DailyBriefingDay, now: Date, scheduled: Bool) async throws {
        guard !isExporting else { return }
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }
        let calendar = DailyBriefingDay.calendar
        let end = min(now, calendar.dateInterval(of: .day, for: day.date)!.end)
        let screenTime = settings.readsSystemScreenTime
            ? await readScreenTime(DateInterval(start: day.date, end: end)) : DailyBriefingScreenTimeResult()
        let typing = try? await typing(day.date)
        try Task.checkCancellation()
        guard settings.enabled else { throw CancellationError() }
        var report = DailyBriefingReport(
            day: day,
            generatedAt: end,
            typing: typing,
            allDeviceSeconds: screenTime.allDeviceSeconds,
            notificationCount: screenTime.notificationCount,
            selectedContent: settings.selectedContent
        )
        if let intervals = screenTime.local, !intervals.isEmpty {
            Self.applySystemUsage(intervals, to: &report)
        }
        let url = try await export(report, settings.template, language, directory)
        if scheduled { try await store.markExported(day) }
        else { try await store.flush() }
        lastExportURL = url
    }

    static func applySystemUsage(_ intervals: [ScreenTimeUsageInterval], to report: inout DailyBriefingReport) {
        report.day.hourlySeconds = Array(repeating: 0, count: 24)
        report.day.applications = [:]
        report.day.firstActivity = intervals.map(\.start).min()
        report.day.lastActivity = intervals.map(\.end).max()
        for interval in intervals {
            var cursor = interval.start
            while cursor < interval.end {
                let end = min(report.calendar.dateInterval(of: .hour, for: cursor)!.end, interval.end)
                report.day.hourlySeconds[report.calendar.component(.hour, from: cursor)] += end.timeIntervalSince(cursor)
                cursor = end
            }
            var application = report.day.applications[interval.bundleID]
            if application == nil {
                let bundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: interval.bundleID).flatMap(Bundle.init(url:))
                let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? interval.bundleID
                application = DailyBriefingApplication(name: name,
                    category: DailyBriefingCategory(applicationCategory: bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String))
            }
            application!.seconds += interval.end.timeIntervalSince(interval.start)
            report.day.applications[interval.bundleID] = application
        }
    }

    private func record(_ error: Error) {
        errorMessage = AppLocalization.string("简报导出或记录失败", language: language) + "\n" + error.localizedDescription
    }
}
