import Foundation
import Testing
import XCTest
import ZislaCore

@testable import ZislaKit

@MainActor
struct SystemAutoCleanupServiceTests {
    @Test
    func cancellingBeforeManualScanningStartsDoesNotBlockTheNextCleanup() async throws {
        let fixture = try SystemAutoCleanupFixture()
        let service = fixture.makeService()
        let selected = FeatureSettings(systemCleanupPolicy: .sevenDays, trashCleanupPolicy: .sevenDays)
        service.apply(settings: selected)
        defer { service.stop() }
        let manual = Task { await service.runNow(settings: selected) }
        manual.cancel()
        let cancelled = await manual.value
        #expect(cancelled.system == nil && cancelled.trash == nil)
        #expect(fixture.options == nil && fixture.emptiedCount == 0)
        let retried = await service.runNow(settings: selected)
        #expect(retried.system != nil && retried.trash != nil)
        #expect(fixture.emptiedCount == 1)
    }

    @Test
    func anImmediateOperationDoesNotRequireOrCreateAnAutomaticSchedule() async throws {
        let fixture = try SystemAutoCleanupFixture()
        fixture.candidates = [fixture.candidate("cache", kind: .appCache)]
        let service = fixture.makeService()
        defer { service.stop() }
        let selected = FeatureSettings(systemCleanupPolicy: .sevenDays, trashCleanupPolicy: .sevenDays)
        let result = await service.runNow(settings: selected)
        #expect(result.system?.successCount == 1)
        #expect(result.trash != nil && fixture.emptiedCount == 1)
        #expect(fixture.timers.isEmpty)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") == nil)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") == nil)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
    }

    @Test
    func multipleManualRequestsRunSequentiallyAndDoNotDelayAnAutomaticDeadline() async throws {
        let fixture = try SystemAutoCleanupFixture()
        let gate = CleanupScanGate()
        let service = fixture.makeService(scan: { kinds, options in
            await gate.wait()
            return fixture.scan(kinds, options: options)
        })
        defer { service.stop() }
        let selected = FeatureSettings(systemCleanupPolicy: .sevenDays)
        service.apply(settings: selected)
        let timer = try #require(fixture.timers.first)
        let deadline = timer.fireDate
        let first = Task { await service.runNow(settings: selected) }
        await gate.waitUntilScanning(1)
        let second = Task { await service.runNow(settings: selected) }
        await Task.yield()
        #expect(await gate.startedCount() == 1, "A second manual request must wait for the first one")
        fixture.date = deadline
        #expect(service.runIfDue() == nil, "Automatic cleanup must not overlap manual work")
        await gate.releaseOne()
        #expect(await first.value.system != nil)
        await gate.waitUntilScanning(2)
        await gate.releaseOne()
        #expect(await second.value.system != nil)
        #expect(timer.fireDate == deadline)
    }

    @Test(arguments: ["scope", "interval", "never", "disable"])
    func changingSettingsDoesNotCancelImmediateCleanupOrChangeItsSelectedItems(change: String) async throws {
        let fixture = try SystemAutoCleanupFixture()
        let gate = CleanupScanGate()
        let safe = fixture.candidate("cache", kind: .appCache)
        let review = fixture.candidate("log", kind: .log)
        fixture.candidates = [safe, review]
        let service = fixture.makeService(scan: { kinds, options in
            await gate.wait()
            return fixture.scan(kinds, options: options)
        })
        defer { service.stop() }
        let selected = FeatureSettings(systemCleanupPolicy: .sevenDays, systemCleanupScope: .all, trashCleanupPolicy: .sevenDays)
        service.apply(settings: selected)
        let manual = Task { await service.runNow(settings: selected) }
        await gate.waitUntilScanning(1)
        #expect(fixture.emptiedCount == 0, "System cleanup must finish before emptying the Trash")
        var changed = selected
        switch change {
        case "scope": changed.systemCleanupScope = .trustedOnly
        case "interval": changed.systemCleanupPolicy = .fifteenDays; changed.trashCleanupPolicy = .thirtyDays
        case "never": changed.systemCleanupPolicy = .never; changed.trashCleanupPolicy = .never
        default: changed.systemMonitorEnabled = false
        }
        service.apply(settings: changed)
        let deadlines = fixture.timers.filter(\.isValid).map(\.fireDate)
        let lastSystemRun = fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date
        let lastTrashRun = fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date
        await gate.releaseOne()

        let result = await manual.value
        #expect(result.system?.successCount == 2)
        #expect(fixture.moved == [safe, review], "Manual cleanup must use the scope selected when it started")
        #expect(fixture.emptiedCount == 1)
        #expect(result.trash != nil)
        #expect(fixture.timers.filter(\.isValid).map(\.fireDate) == deadlines)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date == lastSystemRun)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == lastTrashRun)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
    }

    @Test(arguments: [VoiceRecordingCleanupPolicy.never, .fifteenDays])
    func changingTheTrashScheduleDoesNotCancelAnImmediateEmptying(policy: VoiceRecordingCleanupPolicy) async throws {
        let fixture = try SystemAutoCleanupFixture()
        let gate = CleanupScanGate()
        let service = fixture.makeService(emptyTrash: {
            await gate.wait()
            #expect(!Task.isCancelled)
            fixture.emptiedCount += 1
            return .success(())
        })
        defer { service.stop() }
        let selected = FeatureSettings(trashCleanupPolicy: .sevenDays)
        service.apply(settings: selected)
        let manual = Task { await service.runNow(settings: selected) }
        await gate.waitUntilScanning(1)
        service.apply(settings: FeatureSettings(trashCleanupPolicy: policy))
        let deadline = fixture.timers.last?.fireDate
        let lastRun = fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date
        await gate.releaseOne()
        let result = await manual.value
        #expect(result.trash != nil)
        #expect(fixture.emptiedCount == 1)
        #expect(fixture.timers.last?.fireDate == deadline)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == lastRun)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
    }

    @Test
    func cancellingTheImmediateCallerStopsScanningAndDoesNotStartTrashEmptying() async throws {
        let fixture = try SystemAutoCleanupFixture()
        let gate = CleanupScanGate()
        fixture.candidates = [fixture.candidate("cache", kind: .appCache)]
        let service = fixture.makeService(scan: { kinds, options in
            await gate.wait()
            return fixture.scan(kinds, options: options)
        })
        defer { service.stop() }
        let selected = FeatureSettings(systemCleanupPolicy: .sevenDays, trashCleanupPolicy: .sevenDays)
        service.apply(settings: selected)
        let deadlines = fixture.timers.map(\.fireDate)
        let manual = Task { await service.runNow(settings: selected) }
        await gate.waitUntilScanning(1)
        manual.cancel()
        await gate.releaseOne()
        let result = await manual.value
        #expect(result.system == nil && result.trash == nil)
        #expect(fixture.moved.isEmpty && fixture.emptiedCount == 0)
        #expect(fixture.timers.map(\.fireDate) == deadlines)
    }

    @Test(arguments: SystemCleanupScope.allCases)
    func immediateCleanupUsesTheSelectedScopeAndPreservesBothDeadlines(scope: SystemCleanupScope) async throws {
        let fixture = try SystemAutoCleanupFixture()
        let safe = fixture.candidate("cache", kind: .appCache)
        let review = fixture.candidate("log", kind: .log)
        let analysis = fixture.candidate("simulator", kind: .simulatorData, safetyLevel: .safeToClean)
        fixture.candidates = [safe, review, analysis]
        let service = fixture.makeService()
        defer { service.stop() }
        let selected = FeatureSettings(systemCleanupPolicy: .sevenDays,
                                       systemCleanupScope: scope, trashCleanupPolicy: .fifteenDays)
        service.apply(settings: selected)
        let deadlines = fixture.timers.map(\.fireDate)
        let originalDate = fixture.date
        fixture.date.addTimeInterval(86_400)

        let result = await service.runNow(settings: selected)

        #expect(result.system?.successCount == (scope == .all ? 2 : 1))
        #expect(fixture.moved == (scope == .all ? [safe, review] : [safe]))
        #expect(fixture.options?.referenceDate == fixture.date)
        #expect(fixture.emptiedCount == 1)
        #expect(fixture.timers.map(\.fireDate) == deadlines)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date == originalDate)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == originalDate)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
        #expect(service.runIfDue() == nil)
        #expect(service.trashCleanup.runIfDue() == nil)
    }

    @Test(arguments: [false, true], [false, true])
    func immediateCleanupSkipsDisabledItemsAndAcceptsEmptyCandidates(systemEnabled: Bool, trashEnabled: Bool) async throws {
        let fixture = try SystemAutoCleanupFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        let selected = FeatureSettings(systemMonitorEnabled: systemEnabled,
                                       systemCleanupPolicy: .sevenDays, trashCleanupPolicy: trashEnabled ? .sevenDays : .never)
        service.apply(settings: selected)
        let result = await service.runNow(settings: selected)
        #expect((result.system != nil) == systemEnabled)
        #expect(result.system?.successCount == (systemEnabled ? 0 : nil))
        #expect((result.trash != nil) == trashEnabled)
        #expect(fixture.emptiedCount == (trashEnabled ? 1 : 0))
        #expect(fixture.moved.isEmpty)
        #expect((fixture.options != nil) == systemEnabled)
    }

    @Test
    func immediateFailuresAreReturnedWithoutChangingTheScheduleAndAllowRetry() async throws {
        let fixture = try SystemAutoCleanupFixture()
        let candidate = fixture.candidate("protected", kind: .appCache)
        fixture.candidates = [candidate]
        fixture.result = DiskCleanupResult(successCount: 0, freedBytes: 0,
                                           failures: [DiskCleanupFailure(url: candidate.url, message: "Permission denied")])
        fixture.emptyResult = .failure(.failed("Automation permission denied"))
        let service = fixture.makeService()
        defer { service.stop() }
        let selected = FeatureSettings(systemCleanupPolicy: .sevenDays, trashCleanupPolicy: .sevenDays)
        service.apply(settings: selected)
        let deadlines = fixture.timers.map(\.fireDate)
        let failed = await service.runNow(settings: selected)
        #expect(failed.system == fixture.result)
        if case .failure(let error) = failed.trash {
            #expect(error == .failed("Automation permission denied"))
        } else { Issue.record("Immediate Trash failure must be returned") }
        #expect(fixture.timers.map(\.fireDate) == deadlines)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
        fixture.result = nil
        fixture.emptyResult = .success(())
        let retried = await service.runNow(settings: selected)
        #expect(retried.system?.successCount == 1)
        #expect(fixture.emptiedCount == 2)
        #expect(fixture.timers.map(\.fireDate) == deadlines)
    }

    @Test
    func aDeadlineReachedDuringImmediateCleanupStillRunsItsScheduledOperation() async throws {
        let fixture = try SystemAutoCleanupFixture()
        let gate = CleanupScanGate()
        let service = fixture.makeService(scan: { kinds, options in
            await gate.wait()
            return fixture.scan(kinds, options: options)
        })
        defer { service.stop() }
        let selected = FeatureSettings(systemCleanupPolicy: .sevenDays)
        service.apply(settings: selected)
        let timer = try #require(fixture.timers.first)
        let deadline = timer.fireDate
        let manual = Task { await service.runNow(settings: selected) }
        await gate.waitUntilScanning(1)
        fixture.date = deadline
        timer.fireDate = deadline.addingTimeInterval(timer.timeInterval)
        fixture.callbacks[0](timer)
        await gate.releaseOne()
        #expect(await manual.value.system != nil)
        #expect(timer.fireDate == deadline, "An extra cleanup cannot defer the original deadline")
        let scheduled = try #require(service.runIfDue())
        await gate.waitUntilScanning(2)
        await gate.releaseOne()
        #expect(await scheduled.value != nil)
        #expect(timer.fireDate == deadline.addingTimeInterval(timer.timeInterval))
    }

    @Test
    func immediateCleanupWaitsForScheduledWorkInsteadOfOverlappingIt() async throws {
        let fixture = try SystemAutoCleanupFixture()
        let gate = CleanupScanGate()
        let service = fixture.makeService(scan: { kinds, options in
            await gate.wait()
            return fixture.scan(kinds, options: options)
        })
        defer { service.stop() }
        let selected = FeatureSettings(systemCleanupPolicy: .sevenDays)
        service.apply(settings: selected)
        fixture.date.addTimeInterval(7 * 86_400)
        let scheduled = try #require(service.runIfDue())
        await gate.waitUntilScanning(1)
        let manual = Task { await service.runNow(settings: selected) }
        await Task.yield()
        await gate.releaseOne()
        #expect(await scheduled.value != nil)
        let deadline = try #require(fixture.timers.first).fireDate
        await gate.waitUntilScanning(2)
        await gate.releaseOne()
        #expect(await manual.value.system != nil)
        #expect(fixture.timers.first?.fireDate == deadline)
    }

    @Test
    func stoppingImmediateCleanupDuringScanningKeepsFilesAndScheduleRecords() async throws {
        let fixture = try SystemAutoCleanupFixture()
        let gate = CleanupScanGate()
        fixture.candidates = [fixture.candidate("cache", kind: .appCache)]
        let service = fixture.makeService(scan: { kinds, options in
            await gate.wait()
            return fixture.scan(kinds, options: options)
        })
        let selected = FeatureSettings(systemCleanupPolicy: .sevenDays, trashCleanupPolicy: .sevenDays)
        service.apply(settings: selected)
        let originalDate = fixture.date
        let manual = Task { await service.runNow(settings: selected) }
        await gate.waitUntilScanning(1)
        service.stop()
        await gate.releaseOne()
        #expect(await manual.value.system == nil)
        #expect(fixture.moved.isEmpty)
        #expect(fixture.emptiedCount == 0)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date == originalDate)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == originalDate)
    }

    @Test(arguments: [VoiceRecordingCleanupPolicy.sevenDays, .fifteenDays, .thirtyDays])
    func firstCleanupWaitsForTheSelectedIntervalAndReschedulesFromCompletion(policy: VoiceRecordingCleanupPolicy) async throws {
        let fixture = try SystemAutoCleanupFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        let interval = TimeInterval(try #require(policy.daysThreshold) * 86_400)
        service.apply(settings: FeatureSettings(systemCleanupPolicy: policy))
        let timer = try #require(fixture.timers.first)
        #expect(timer.isValid)
        #expect(timer.timeInterval == interval)
        #expect(timer.fireDate == fixture.date.addingTimeInterval(interval))
        #expect(fixture.moved.isEmpty)
        fixture.date.addTimeInterval(interval - 0.001)
        #expect(service.runIfDue() == nil)
        fixture.date.addTimeInterval(0.001)
        let result = await (try #require(service.runIfDue())).value
        #expect(result?.successCount == 0)
        #expect(service.cleanupTask == nil)
        #expect(timer.fireDate == fixture.date.addingTimeInterval(interval))
        #expect(fixture.options?.referenceDate == fixture.date)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date == fixture.date)
        #expect(service.runIfDue() == nil)
        fixture.date.addTimeInterval(interval)
        fixture.callbacks[0](timer)
        #expect(await (try #require(service.cleanupTask)).value != nil)
    }

    @Test(arguments: [false, true])
    func neverAndDisabledMonitorDoNotScheduleCleanup(monitorEnabled: Bool) throws {
        let fixture = try SystemAutoCleanupFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(systemMonitorEnabled: monitorEnabled,
                                                systemCleanupPolicy: monitorEnabled ? .never : .sevenDays))
        #expect(fixture.timers.isEmpty)
        #expect(service.runIfDue() == nil)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") == nil)
        #expect(fixture.moved.isEmpty)
    }

    @Test(arguments: [false, true])
    func savedScheduleSurvivesRelaunchAndOverdueTimerRunsOnce(overdue: Bool) async throws {
        let fixture = try SystemAutoCleanupFixture()
        var service = fixture.makeService()
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays))
        let deadline = try #require(fixture.timers.first).fireDate
        service.stop()
        fixture.date.addTimeInterval(overdue ? 12 * 86_400 : 3 * 86_400)
        service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays))
        let timer = try #require(fixture.timers.last)
        #expect(timer.fireDate == deadline)
        if overdue {
            fixture.callbacks.last?(timer)
            #expect(await (try #require(service.cleanupTask)).value != nil)
            #expect(timer.fireDate == fixture.date.addingTimeInterval(7 * 86_400))
            #expect(service.runIfDue() == nil)
        } else {
            #expect(service.runIfDue() == nil)
        }
    }

    @Test
    func unrelatedSettingsKeepTheTimerAndVoiceCleanupIndependent() throws {
        let fixture = try SystemAutoCleanupFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        var settings = FeatureSettings(systemCleanupPolicy: .fifteenDays)
        service.apply(settings: settings)
        let timer = try #require(fixture.timers.first)
        fixture.date.addTimeInterval(86_400)
        settings.voiceRecordingCleanupPolicy = .sevenDays
        settings.notificationsMuted = true
        settings.systemMetricsHistoryEnabled = false
        service.apply(settings: settings)
        #expect(fixture.timers.count == 1)
        #expect(timer.isValid)
        #expect(timer.fireDate == Date(timeIntervalSince1970: 1_800_000_000 + 15 * 86_400))
    }

    @Test
    func intervalAndScopeChangesReplaceTheTimerAndIgnoreStaleCallbacks() async throws {
        let fixture = try SystemAutoCleanupFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .thirtyDays))
        let original = try #require(fixture.timers.first)
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays, systemCleanupScope: .all))
        let replacement = try #require(fixture.timers.last)
        #expect(fixture.timers.count == 2)
        #expect(!original.isValid)
        #expect(replacement.timeInterval == 7 * 86_400)
        fixture.date = replacement.fireDate
        fixture.callbacks[0](original)
        #expect(service.cleanupTask == nil)
        fixture.callbacks[1](replacement)
        #expect(await (try #require(service.cleanupTask)).value != nil)
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays, systemCleanupScope: .trustedOnly))
        #expect(!replacement.isValid)
        #expect(fixture.timers.count == 3)
        #expect(fixture.timers.last?.fireDate == fixture.date.addingTimeInterval(7 * 86_400))
    }

    @Test
    func stopInvalidatesTheTimerAndAllowsTheSameConfigurationToRestart() throws {
        let fixture = try SystemAutoCleanupFixture()
        let service = fixture.makeService()
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays))
        let timer = try #require(fixture.timers.first)
        let deadline = timer.fireDate
        service.stop()
        #expect(!timer.isValid)
        fixture.date = deadline
        fixture.callbacks[0](timer)
        #expect(service.cleanupTask == nil)
        #expect(service.runIfDue() == nil)
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays))
        #expect(fixture.timers.count == 2)
        service.stop()
    }

    @Test
    func deinitializationReleasesBothTimersAndPreservesTheirSchedules() throws {
        let fixture = try SystemAutoCleanupFixture()
        var service: SystemAutoCleanupService? = fixture.makeService()
        weak let reference = service
        weak let trashReference = service?.trashCleanup
        service?.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays, trashCleanupPolicy: .fifteenDays))
        #expect(fixture.timers.count == 2)
        service = nil
        #expect(reference == nil)
        #expect(trashReference == nil)
        #expect(fixture.timers.allSatisfy { !$0.isValid })
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date == fixture.date)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == fixture.date)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
        for (timer, callback) in zip(fixture.timers, fixture.callbacks) {
            fixture.date = timer.fireDate
            callback(timer)
        }
        #expect(fixture.options == nil)
        #expect(fixture.moved.isEmpty)
        #expect(fixture.emptiedCount == 0)
    }

    @Test
    func overdueCleanupRunsThroughTheRegisteredTimer() async throws {
        let fixture = try SystemAutoCleanupFixture()
        fixture.defaults.set(Date().addingTimeInterval(-8 * 86_400), forKey: "system-cleanup-last-run-v1")
        let completed = XCTestExpectation(description: "Overdue cleanup runs from the main run loop")
        let service = SystemAutoCleanupService(defaults: fixture.defaults,
                                               scan: { _, _ in [] },
                                               trash: { _ in
                                                   completed.fulfill()
                                                   return DiskCleanupResult(successCount: 0, freedBytes: 0, failures: [])
                                               })
        defer { service.stop() }
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays))
        #expect(await XCTWaiter.fulfillment(of: [completed], timeout: 2) == .completed)
    }

    @Test(arguments: [false, true])
    func stoppingBeforeAQueuedTaskStartsSkipsScanning(releaseService: Bool) async throws {
        let fixture = try SystemAutoCleanupFixture()
        var service: SystemAutoCleanupService? = fixture.makeService()
        weak let reference = service
        service?.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays))
        fixture.date.addTimeInterval(7 * 86_400)
        let task = try #require(service?.runIfDue())
        if releaseService {
            service = nil
            #expect(reference == nil)
        } else {
            service?.stop()
        }
        #expect(task.isCancelled)
        #expect(fixture.timers.allSatisfy { !$0.isValid })
        #expect(await task.value == nil)
        #expect(fixture.options == nil)
        #expect(fixture.moved.isEmpty)
    }

    @Test(arguments: SystemCleanupScope.allCases)
    func cleanupUsesCandidateSafetyOverridesAndAlwaysExcludesAnalysisOnly(scope: SystemCleanupScope) async throws {
        let fixture = try SystemAutoCleanupFixture()
        let safe = fixture.candidate("cache", kind: .appCache)
        let review = fixture.candidate("apple-cache", kind: .cache, safetyLevel: .requiresManualReview)
        let log = fixture.candidate("log", kind: .log)
        let analysis = fixture.candidate("simulator", kind: .simulatorData, safetyLevel: .safeToClean)
        let downgraded = fixture.candidate("unknown-cache", kind: .appCache, safetyLevel: .analysisOnly)
        fixture.candidates = [safe, review, log, analysis, downgraded]
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays, systemCleanupScope: scope))
        fixture.date.addTimeInterval(7 * 86_400)
        #expect(await (try #require(service.runIfDue())).value?.successCount == (scope == .all ? 3 : 1))
        #expect(fixture.moved == (scope == .all ? [safe, review, log] : [safe]))
        #expect(fixture.kinds.contains(.log) == (scope == .all))
        #expect(fixture.kinds.contains(.cache))
        #expect(fixture.kinds.allSatisfy { $0.safetyLevel != .analysisOnly })
        if scope == .trustedOnly {
            #expect(fixture.kinds.allSatisfy { $0.safetyLevel == .safeToClean })
        }
    }

    @Test(arguments: ["stop", "never", "disable", "scope", "interval"])
    func cancellationDuringScanningDoesNotMoveFilesOrOverwriteANewTask(change: String) async throws {
        let fixture = try SystemAutoCleanupFixture()
        fixture.candidates = [fixture.candidate("cache", kind: .appCache)]
        let gate = CleanupScanGate()
        let service = fixture.makeService(scan: { kinds, options in
            await gate.wait()
            return fixture.scan(kinds, options: options)
        })
        defer { service.stop() }
        var settings = FeatureSettings(systemCleanupPolicy: .sevenDays)
        service.apply(settings: settings)
        fixture.date.addTimeInterval(7 * 86_400)
        let original = try #require(service.runIfDue())
        await gate.waitUntilScanning(1)
        #expect(service.runIfDue() == nil)
        switch change {
        case "stop": service.stop()
        case "never": settings.systemCleanupPolicy = .never
        case "disable": settings.systemMonitorEnabled = false
        case "scope": settings.systemCleanupScope = .all
        default: settings.systemCleanupPolicy = .fifteenDays
        }
        if change != "stop" { service.apply(settings: settings) }
        var replacement: Task<DiskCleanupResult?, Never>?
        if change == "scope" { replacement = service.runIfDue() }
        #expect((replacement != nil) == (change == "scope"))
        #expect((service.cleanupTask == nil) == (change != "scope"))
        if replacement != nil { await gate.waitUntilScanning(2) }
        await gate.releaseOne()
        #expect(await original.value == nil)
        #expect(fixture.moved.isEmpty)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date
            == Date(timeIntervalSince1970: 1_800_000_000))
        if let replacement {
            #expect(service.cleanupTask != nil)
            await gate.releaseOne()
            #expect(await replacement.value?.successCount == 1)
        }
    }

    @Test
    func cancellationDuringTrashDoesNotPersistCompletion() async throws {
        let fixture = try SystemAutoCleanupFixture()
        let gate = CleanupScanGate()
        let service = fixture.makeService(trash: { candidates in
            await gate.wait()
            #expect(Task.isCancelled)
            return DiskCleanupResult(successCount: 0, freedBytes: 0, failures: [])
        })
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays))
        fixture.date.addTimeInterval(7 * 86_400)
        let task = try #require(service.runIfDue())
        await gate.waitUntilScanning(1)
        service.stop()
        await gate.releaseOne()
        #expect(await task.value == nil)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date
            == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test
    func permissionFailuresAreReturnedAndWaitUntilTheNextInterval() async throws {
        let fixture = try SystemAutoCleanupFixture()
        let candidate = fixture.candidate("protected", kind: .appCache)
        fixture.candidates = [candidate]
        fixture.result = DiskCleanupResult(successCount: 0, freedBytes: 0,
                                           failures: [DiskCleanupFailure(url: candidate.url, message: "Permission denied")])
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays))
        fixture.date.addTimeInterval(7 * 86_400)
        let result = await (try #require(service.runIfDue())).value
        #expect(result == fixture.result)
        #expect(service.runIfDue() == nil)
        #expect(fixture.timers.last?.fireDate == fixture.date.addingTimeInterval(7 * 86_400))
    }

    @Test(arguments: SystemCleanupScope.allCases)
    func realScannerAndTrashAdapterKeepTheUnselectedMockFiles(scope: SystemCleanupScope) async throws {
        let fixture = try SystemAutoCleanupFixture()
        let mock = MockFileManager()
        let caches = mock.homeDirectory.appendingPathComponent("Library/Caches")
        let cache = caches.appendingPathComponent("com.example.cache")
        let logs = mock.homeDirectory.appendingPathComponent("Library/Logs")
        let log = logs.appendingPathComponent("app.log")
        mock.existingPaths = [caches.path, cache.path, logs.path, log.path]
        mock.directoryContents[caches.path] = [cache]
        mock.directoryContents[logs.path] = [log]
        mock.fileAttributes[cache.path] = [.size: NSNumber(value: 4_096)]
        mock.fileAttributes[log.path] = [.size: NSNumber(value: 8_192)]
        mock.trashResults[cache] = .success(mock.homeDirectory.appendingPathComponent(".Trash/cache"))
        mock.trashResults[log] = .failure(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError))
        let service = fixture.makeService(
            scan: { SystemDiskCleanup.scanCandidates(fileManager: mock, kinds: $0, options: $1) },
            trash: { SystemDiskCleanup.trashSelected(candidates: $0, fileManager: mock) }
        )
        defer { service.stop() }
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays, systemCleanupScope: scope))
        fixture.date.addTimeInterval(7 * 86_400)
        let task = try #require(service.runIfDue())
        let result = try #require(await task.value)
        #expect(result.successCount == 1)
        #expect(result.freedBytes == 4_096)
        #expect(result.failures.map(\.url) == (scope == .all ? [log] : []))
        #expect(mock.existingPaths.contains(log.path))
    }

    @Test(arguments: [VoiceRecordingCleanupPolicy.sevenDays, .fifteenDays, .thirtyDays])
    func trashEmptyingWaitsForItsOwnIntervalAndRunsWithOtherFeaturesDisabled(policy: VoiceRecordingCleanupPolicy) async throws {
        let fixture = try SystemAutoCleanupFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        let interval = TimeInterval(try #require(policy.daysThreshold) * 86_400)
        var settings = FeatureSettings(systemMonitorEnabled: false,
                                       systemCleanupPolicy: .sevenDays, trashCleanupPolicy: policy)
        settings.clipboardHistoryEnabled = false
        service.apply(settings: settings)
        let timer = try #require(fixture.timers.first)
        #expect(fixture.timers.count == 1)
        #expect(timer.timeInterval == interval)
        #expect(timer.fireDate == fixture.date.addingTimeInterval(interval))
        #expect(fixture.emptiedCount == 0)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") == nil)
        fixture.date.addTimeInterval(interval - 0.001)
        #expect(service.trashCleanup.runIfDue() == nil)
        fixture.date.addTimeInterval(0.001)
        let task = try #require(service.trashCleanup.runIfDue())
        #expect(service.trashCleanup.runIfDue() == nil)
        let result = try #require(await task.value)
        if case .failure(let error) = result { Issue.record("Unexpected emptying failure: \(error)") }
        #expect(fixture.emptiedCount == 1)
        #expect(fixture.options == nil)
        #expect(fixture.moved.isEmpty)
        #expect(service.trashCleanup.task == nil)
        #expect(timer.fireDate == fixture.date.addingTimeInterval(interval))
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == fixture.date)
        #expect(service.trashCleanup.runIfDue() == nil)
        fixture.date.addTimeInterval(interval)
        fixture.callbacks[0](timer)
        fixture.callbacks[0](timer)
        #expect(await (try #require(service.trashCleanup.task)).value != nil)
        #expect(fixture.emptiedCount == 2)
    }

    @Test
    func trashEmptyingIsOffByDefaultAndDoesNotCreateAPersistedSchedule() throws {
        let fixture = try SystemAutoCleanupFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: .default)
        #expect(fixture.timers.isEmpty)
        #expect(service.trashCleanup.runIfDue() == nil)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") == nil)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
        #expect(fixture.emptiedCount == 0)
    }

    @Test(arguments: [false, true], [false, true])
    func savedTrashScheduleSurvivesRelaunchAndOverdueWorkRunsOnlyOnce(overdue: Bool, stopBeforeRelaunch: Bool) async throws {
        let fixture = try SystemAutoCleanupFixture()
        var original: SystemAutoCleanupService? = fixture.makeService()
        original?.apply(settings: FeatureSettings(trashCleanupPolicy: .sevenDays))
        let deadline = try #require(fixture.timers.first).fireDate
        if stopBeforeRelaunch { original?.stop() }
        original = nil
        #expect(fixture.timers.allSatisfy { !$0.isValid })
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == fixture.date)
        fixture.date.addTimeInterval(overdue ? 90 * 86_400 : 3 * 86_400)
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(trashCleanupPolicy: .sevenDays))
        let timer = try #require(fixture.timers.last)
        #expect(timer.fireDate == deadline)
        if overdue {
            fixture.callbacks.last?(timer)
            #expect(await (try #require(service.trashCleanup.task)).value != nil)
            #expect(fixture.emptiedCount == 1)
            #expect(timer.fireDate == fixture.date.addingTimeInterval(7 * 86_400))
            fixture.callbacks.last?(timer)
            #expect(service.trashCleanup.task == nil)
        } else {
            #expect(service.trashCleanup.runIfDue() == nil)
            #expect(fixture.emptiedCount == 0)
        }
    }

    @Test
    func otherCleanupSettingsDoNotReplaceTheTrashTimer() throws {
        let fixture = try SystemAutoCleanupFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        var settings = FeatureSettings(systemCleanupPolicy: .sevenDays, trashCleanupPolicy: .fifteenDays)
        service.apply(settings: settings)
        let trashTimer = try #require(fixture.timers.last)
        let deadline = trashTimer.fireDate
        fixture.date.addTimeInterval(86_400)
        settings.systemCleanupScope = .all
        settings.systemCleanupPolicy = .thirtyDays
        settings.clipboardHistoryCleanupPolicy = .sevenDays
        settings.voiceRecordingCleanupPolicy = .fifteenDays
        service.apply(settings: settings)
        #expect(fixture.timers.count == 3)
        #expect(trashTimer.isValid)
        #expect(trashTimer.fireDate == deadline)
        settings.systemMonitorEnabled = false
        service.apply(settings: settings)
        #expect(fixture.timers.count == 3)
        #expect(trashTimer.isValid)
        #expect(trashTimer.fireDate == deadline)
        #expect(fixture.emptiedCount == 0)
    }

    @Test
    func trashPolicyChangesReplaceOnlyTheirTimerAndRejectStaleCallbacks() async throws {
        let fixture = try SystemAutoCleanupFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        var settings = FeatureSettings(systemCleanupPolicy: .fifteenDays, trashCleanupPolicy: .thirtyDays)
        service.apply(settings: settings)
        let systemTimer = try #require(fixture.timers.first)
        let original = try #require(fixture.timers.last)
        let originalCallback = try #require(fixture.callbacks.last)
        settings.trashCleanupPolicy = .sevenDays
        service.apply(settings: settings)
        let replacement = try #require(fixture.timers.last)
        #expect(fixture.timers.count == 3)
        #expect(!original.isValid)
        #expect(systemTimer.isValid)
        #expect(replacement.timeInterval == 7 * 86_400)
        fixture.date = replacement.fireDate
        originalCallback(original)
        #expect(service.trashCleanup.task == nil)
        fixture.callbacks.last?(replacement)
        #expect(await (try #require(service.trashCleanup.task)).value != nil)
        #expect(fixture.emptiedCount == 1)
        settings.trashCleanupPolicy = .never
        service.apply(settings: settings)
        #expect(!replacement.isValid)
        #expect(systemTimer.isValid)
        #expect(service.trashCleanup.runIfDue() == nil)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") == nil)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date
            == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test(arguments: [false, true], [false, true])
    func disablingAndReenablingTrashCleanupStartsACompleteNewInterval(overdue: Bool, relaunch: Bool) async throws {
        let fixture = try SystemAutoCleanupFixture()
        var service = fixture.makeService()
        defer { service.stop() }
        let interval = TimeInterval(7 * 86_400)
        var settings = FeatureSettings(trashCleanupPolicy: .sevenDays)
        service.apply(settings: settings)
        let original = try #require(fixture.timers.first)
        fixture.date.addTimeInterval(86_400)
        settings.trashCleanupPolicy = .never
        service.apply(settings: settings)
        #expect(!original.isValid)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") == nil)
        #expect(service.trashCleanup.runIfDue() == nil)
        fixture.date.addTimeInterval(overdue ? 8 * 86_400 : 3 * 86_400)
        if relaunch {
            service.stop()
            service = fixture.makeService()
        }
        service.apply(settings: settings)
        #expect(fixture.timers.count == 1)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") == nil)
        settings.trashCleanupPolicy = .sevenDays
        service.apply(settings: settings)
        let timer = try #require(fixture.timers.last)
        #expect(timer.fireDate == fixture.date.addingTimeInterval(interval))
        #expect(timer.fireDate != original.fireDate)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == fixture.date)
        #expect(service.trashCleanup.runIfDue() == nil)
        #expect(fixture.emptiedCount == 0)
        fixture.date.addTimeInterval(interval - 0.001)
        #expect(service.trashCleanup.runIfDue() == nil)
        fixture.date.addTimeInterval(0.001)
        #expect(await (try #require(service.trashCleanup.runIfDue())).value != nil)
        #expect(fixture.emptiedCount == 1)
        #expect(timer.fireDate == fixture.date.addingTimeInterval(interval))
    }

    @Test
    func launchingWithTrashCleanupDisabledDiscardsItsSavedScheduleAndKeepsSystemCleanup() throws {
        let fixture = try SystemAutoCleanupFixture()
        let saved = fixture.date.addingTimeInterval(-15 * 86_400)
        fixture.defaults.set(saved, forKey: "system-cleanup-last-run-v1")
        fixture.defaults.set(saved, forKey: "trash-cleanup-last-run-v1")
        let service = fixture.makeService()
        defer { service.stop() }
        var settings = FeatureSettings(systemCleanupPolicy: .thirtyDays)
        service.apply(settings: settings)
        let systemTimer = try #require(fixture.timers.first)
        #expect(fixture.timers.count == 1)
        #expect(systemTimer.fireDate == saved.addingTimeInterval(30 * 86_400))
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date == saved)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") == nil)
        #expect(service.trashCleanup.runIfDue() == nil)
        fixture.date.addTimeInterval(2 * 86_400)
        settings.trashCleanupPolicy = .sevenDays
        service.apply(settings: settings)
        #expect(fixture.timers.count == 2)
        #expect(systemTimer.isValid)
        #expect(systemTimer.fireDate == saved.addingTimeInterval(30 * 86_400))
        #expect(fixture.timers.last?.fireDate == fixture.date.addingTimeInterval(7 * 86_400))
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date == saved)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == fixture.date)
        #expect(service.trashCleanup.runIfDue() == nil)
        #expect(fixture.emptiedCount == 0)
    }

    @Test(arguments: [false, true])
    func stoppingQueuedTrashWorkCancelsItAndReleasesTimers(releaseService: Bool) async throws {
        let fixture = try SystemAutoCleanupFixture()
        var service: SystemAutoCleanupService? = fixture.makeService()
        weak let reference = service
        service?.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays, trashCleanupPolicy: .sevenDays))
        fixture.date.addTimeInterval(7 * 86_400)
        let task = try #require(service?.trashCleanup.runIfDue())
        if releaseService { service = nil } else { service?.stop() }
        #expect(fixture.timers.allSatisfy { !$0.isValid })
        #expect(task.isCancelled)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date
            == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date
            == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil,
                "Canceling before execution must not reserve an irreversible operation")
        #expect(await task.value == nil)
        #expect(fixture.emptiedCount == 0)
        if releaseService { #expect(reference == nil) }
        fixture.callbacks.last?(try #require(fixture.timers.last))
        #expect(fixture.emptiedCount == 0)
    }

    @Test(arguments: ["stop", "never", "interval"])
    func cancellationDuringTrashEmptyingDoesNotCommitOrClearAReplacementTask(change: String) async throws {
        let fixture = try SystemAutoCleanupFixture()
        let gate = CleanupScanGate()
        let service = fixture.makeService(emptyTrash: {
            await gate.wait()
            return .success(())
        })
        defer { service.stop() }
        var settings = FeatureSettings(systemCleanupPolicy: .thirtyDays, trashCleanupPolicy: .sevenDays)
        service.apply(settings: settings)
        fixture.date.addTimeInterval(15 * 86_400)
        let attemptedAt = fixture.date
        let original = try #require(service.trashCleanup.runIfDue())
        await gate.waitUntilScanning(1)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") as? Date == attemptedAt)
        #expect(service.trashCleanup.runIfDue() == nil)
        switch change {
        case "stop": service.stop()
        case "never": settings.trashCleanupPolicy = .never
        default: settings.trashCleanupPolicy = .fifteenDays
        }
        if change != "stop" { service.apply(settings: settings) }
        #expect(service.trashCleanup.runIfDue() == nil)
        if change == "interval" {
            #expect(fixture.timers.last?.fireDate == attemptedAt.addingTimeInterval(15 * 86_400))
            #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
            fixture.date.addTimeInterval(15 * 86_400)
        }
        let replacement = change == "interval" ? service.trashCleanup.runIfDue() : nil
        #expect((replacement != nil) == (change == "interval"))
        if replacement != nil { await gate.waitUntilScanning(2) }
        await gate.releaseOne()
        #expect(await original.value == nil)
        if change == "never" {
            #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") == nil)
            #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
        } else if change == "interval" {
            #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == attemptedAt)
            #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") as? Date == fixture.date,
                    "An obsolete completion cannot erase a replacement's reservation")
        } else {
            #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date
                == Date(timeIntervalSince1970: 1_800_000_000))
            #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") as? Date == attemptedAt)
        }
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date
            == Date(timeIntervalSince1970: 1_800_000_000))
        if let replacement {
            #expect(service.trashCleanup.task != nil)
            await gate.releaseOne()
            #expect(await replacement.value != nil)
            #expect(service.trashCleanup.task == nil)
            #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == fixture.date)
            #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
        }
    }

    @Test(arguments: [false, true])
    func interruptedTrashEmptyingWaitsForAFullIntervalAfterRelaunch(releaseOriginalBeforeRelaunch: Bool) async throws {
        let fixture = try SystemAutoCleanupFixture()
        let gate = CleanupScanGate()
        let originalService = fixture.makeService(emptyTrash: {
            await gate.wait()
            return .success(())
        })
        let settings = FeatureSettings(systemCleanupPolicy: .thirtyDays, trashCleanupPolicy: .sevenDays)
        originalService.apply(settings: settings)
        fixture.date.addTimeInterval(15 * 86_400)
        let attemptedAt = fixture.date
        let original = try #require(originalService.trashCleanup.runIfDue())
        await gate.waitUntilScanning(1)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") as? Date == attemptedAt,
                "Reserve the attempt before the irreversible executor starts")
        originalService.stop()
        if releaseOriginalBeforeRelaunch {
            await gate.releaseOne()
            #expect(await original.value == nil)
        }
        fixture.date.addTimeInterval(30 * 86_400)
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: settings)
        let recoveredAt = fixture.date
        let timer = try #require(fixture.timers.last)
        #expect(timer.fireDate == recoveredAt.addingTimeInterval(7 * 86_400))
        #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == recoveredAt)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date
            == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(service.trashCleanup.runIfDue() == nil)
        if !releaseOriginalBeforeRelaunch {
            await gate.releaseOne()
            #expect(await original.value == nil)
            #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == recoveredAt)
        }
        let recoveredDeadline = timer.fireDate
        service.stop()
        let relaunched = fixture.makeService()
        defer { relaunched.stop() }
        relaunched.apply(settings: settings)
        #expect(fixture.timers.last?.fireDate == recoveredDeadline,
                "A recovered reservation must not defer every later relaunch")
        fixture.date.addTimeInterval(7 * 86_400 - 0.001)
        #expect(relaunched.trashCleanup.runIfDue() == nil)
        #expect(fixture.emptiedCount == 0)
        fixture.date.addTimeInterval(0.001)
        #expect(await (try #require(relaunched.trashCleanup.runIfDue())).value != nil)
        #expect(fixture.emptiedCount == 1)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
    }

    @Test(arguments: ["date", "invalid"], [false, true])
    func persistedUncertainTrashAttemptsRecoverConservativelyOrDiscardWhenDisabled(marker: String, disabled: Bool) throws {
        let fixture = try SystemAutoCleanupFixture()
        let old = fixture.date.addingTimeInterval(-90 * 86_400)
        fixture.defaults.set(old, forKey: "system-cleanup-last-run-v1")
        fixture.defaults.set(old, forKey: "trash-cleanup-last-run-v1")
        if marker == "date" {
            fixture.defaults.set(old, forKey: "trash-cleanup-attempt-v1")
        } else {
            fixture.defaults.set("uncertain", forKey: "trash-cleanup-attempt-v1")
        }
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .thirtyDays,
                                                trashCleanupPolicy: disabled ? .never : .sevenDays))
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
        #expect(fixture.defaults.object(forKey: "system-cleanup-last-run-v1") as? Date == old)
        if disabled {
            #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") == nil)
            #expect(fixture.timers.count == 1)
        } else {
            #expect(fixture.defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == fixture.date)
            #expect(fixture.timers.last?.fireDate == fixture.date.addingTimeInterval(7 * 86_400))
            #expect(service.trashCleanup.runIfDue() == nil)
            let timer = fixture.timers.last
            service.apply(settings: FeatureSettings(systemCleanupPolicy: .thirtyDays, trashCleanupPolicy: .sevenDays))
            #expect(fixture.timers.last === timer)
        }
        #expect(fixture.emptiedCount == 0)
    }

    @Test
    func failedReservationPersistenceNeverSubmitsTrashEmptyingAndCanRecover() async throws {
        let suite = "Zisla.TrashReservation.\(UUID().uuidString)"
        let defaults = try #require(TrashReservationDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        var emptiedCount = 0
        var failures: [DesktopOrganizerError] = []
        let service = SystemAutoCleanupService(defaults: defaults, now: { date },
                                               scan: { _, _ in [] },
                                               trash: { _ in DiskCleanupResult(successCount: 0, freedBytes: 0, failures: []) },
                                               emptyTrash: { emptiedCount += 1; return .success(()) },
                                               onTrashReservationFailure: { failures.append($0) })
        defer { service.stop() }
        let settings = FeatureSettings(trashCleanupPolicy: .sevenDays)
        service.apply(settings: settings)
        date.addTimeInterval(7 * 86_400)
        defaults.synchronizationAllowed = false
        let failedTask = try #require(service.trashCleanup.runIfDue())
        let result = try #require(await failedTask.value)
        if case .failure(let error) = result {
            #expect(error == .failed(AppLocalization.text("无法保存定时倾倒废纸篓的记录，本次已跳过。")))
            #expect(failures == [error])
        } else { Issue.record("A failed durable reservation must be reported") }
        #expect(emptiedCount == 0, "No irreversible operation is allowed before the reservation reaches storage")
        #expect(service.trashCleanup.task == nil)
        #expect(service.trashCleanup.runIfDue() == nil)
        #expect(defaults.object(forKey: "trash-cleanup-attempt-v1") as? Date == date)
        defaults.synchronizationAllowed = true
        date.addTimeInterval(7 * 86_400)
        #expect(await (try #require(service.trashCleanup.runIfDue())).value != nil)
        #expect(emptiedCount == 1)
        #expect(failures.count == 1)
        #expect(defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
    }

    @Test(arguments: [false, true])
    func uncertainReservationSurvivesAFailedRecoveryOrCompletionWrite(completed: Bool) async throws {
        let suite = "Zisla.TrashReservationRecovery.\(UUID().uuidString)"
        let defaults = try #require(TrashReservationDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        let service = SystemAutoCleanupService(defaults: defaults, now: { date },
                                               scan: { _, _ in [] },
                                               trash: { _ in DiskCleanupResult(successCount: 0, freedBytes: 0, failures: []) },
                                               emptyTrash: {
                                                   defaults.synchronizationAllowed = false
                                                   return .success(())
                                               })
        defer { service.stop() }
        let settings = FeatureSettings(trashCleanupPolicy: .sevenDays)
        if completed {
            service.apply(settings: settings)
            date.addTimeInterval(7 * 86_400)
            #expect(await (try #require(service.trashCleanup.runIfDue())).value != nil)
        } else {
            defaults.set(date.addingTimeInterval(-90 * 86_400), forKey: "trash-cleanup-attempt-v1")
            defaults.synchronizationAllowed = false
            service.apply(settings: settings)
        }
        #expect(defaults.object(forKey: "trash-cleanup-attempt-v1") != nil,
                "Keep uncertainty until the next deadline is persisted")
        service.stop()
        defaults.synchronizationAllowed = true
        date.addTimeInterval(86_400)
        service.apply(settings: settings)
        #expect(defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
        #expect(defaults.object(forKey: "trash-cleanup-last-run-v1") as? Date == date)
        #expect(service.trashCleanup.runIfDue() == nil)
    }

    @Test
    func trashPermissionFailureWaitsUntilTheNextIntervalAndCanRecover() async throws {
        let fixture = try SystemAutoCleanupFixture()
        fixture.emptyResult = .failure(.failed("Automation permission denied"))
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(trashCleanupPolicy: .sevenDays))
        fixture.date.addTimeInterval(7 * 86_400)
        let task = try #require(service.trashCleanup.runIfDue())
        let result = try #require(await task.value)
        if case .failure(let error) = result {
            #expect(error == .failed("Automation permission denied"))
        } else { Issue.record("Permission denial must be returned") }
        #expect(fixture.emptiedCount == 1)
        #expect(service.trashCleanup.runIfDue() == nil)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
        #expect(fixture.timers.last?.fireDate == fixture.date.addingTimeInterval(7 * 86_400))
        fixture.emptyResult = .success(())
        fixture.date.addTimeInterval(7 * 86_400)
        #expect(await (try #require(service.trashCleanup.runIfDue())).value != nil)
        #expect(fixture.emptiedCount == 2)
    }

    @Test
    func trashEmptyingReschedulesFromCompletionRatherThanItsStart() async throws {
        let fixture = try SystemAutoCleanupFixture()
        let gate = CleanupScanGate()
        let service = fixture.makeService(emptyTrash: {
            await gate.wait()
            return .success(())
        })
        defer { service.stop() }
        service.apply(settings: FeatureSettings(trashCleanupPolicy: .sevenDays))
        fixture.date.addTimeInterval(7 * 86_400)
        let task = try #require(service.trashCleanup.runIfDue())
        await gate.waitUntilScanning(1)
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") as? Date == fixture.date)
        fixture.date.addTimeInterval(30)
        await gate.releaseOne()
        #expect(await task.value != nil)
        #expect(fixture.timers.last?.fireDate == fixture.date.addingTimeInterval(7 * 86_400))
        #expect(fixture.defaults.object(forKey: "trash-cleanup-attempt-v1") == nil)
    }

    @Test
    func anOverdueTrashScheduleRunsThroughTheMainRunLoopWithoutFinder() async throws {
        let fixture = try SystemAutoCleanupFixture()
        fixture.defaults.set(Date().addingTimeInterval(-8 * 86_400), forKey: "trash-cleanup-last-run-v1")
        let completed = XCTestExpectation(description: "Overdue trash emptying runs on the main run loop")
        let service = SystemAutoCleanupService(defaults: fixture.defaults,
                                               scan: { _, _ in [] },
                                               trash: { _ in DiskCleanupResult(successCount: 0, freedBytes: 0, failures: []) },
                                               emptyTrash: { completed.fulfill(); return .success(()) })
        defer { service.stop() }
        service.apply(settings: FeatureSettings(systemMonitorEnabled: false, trashCleanupPolicy: .sevenDays))
        #expect(await XCTWaiter.fulfillment(of: [completed], timeout: 2) == .completed)
    }
}

@MainActor
private final class SystemAutoCleanupFixture {
    let suite = "Zisla.SystemAutoCleanup.\(UUID().uuidString)"
    let defaults: UserDefaults
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    var timers: [Timer] = []
    var callbacks: [@Sendable (Timer) -> Void] = []
    var candidates: [DiskCleanupCandidate] = []
    var moved: [DiskCleanupCandidate] = []
    var kinds: Set<DiskCleanupKind> = []
    var options: DiskCleanupScanOptions?
    var result: DiskCleanupResult?
    var emptiedCount = 0
    var emptyResult: Result<Void, DesktopOrganizerError> = .success(())

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    isolated deinit {
        defaults.removePersistentDomain(forName: suite)
    }

    func makeService(
        scan: ((Set<DiskCleanupKind>, DiskCleanupScanOptions) async -> [DiskCleanupCandidate])? = nil,
        trash: (([DiskCleanupCandidate]) async -> DiskCleanupResult)? = nil,
        emptyTrash: (() async -> Result<Void, DesktopOrganizerError>)? = nil
    ) -> SystemAutoCleanupService {
        SystemAutoCleanupService(defaults: defaults, now: { self.date },
                                 scan: scan ?? { self.scan($0, options: $1) },
                                 trash: trash ?? {
                                     self.moved = $0
                                     return self.result ?? DiskCleanupResult(successCount: $0.count, freedBytes: 0, failures: [])
                                 },
                                 emptyTrash: emptyTrash ?? {
                                     self.emptiedCount += 1
                                     return self.emptyResult
                                 },
                                 timerFactory: { interval, callback in
                                     let timer = Timer(timeInterval: interval, repeats: true, block: callback)
                                     self.timers.append(timer)
                                     self.callbacks.append(callback)
                                     return timer
                                 })
    }

    func scan(_ kinds: Set<DiskCleanupKind>, options: DiskCleanupScanOptions) -> [DiskCleanupCandidate] {
        self.kinds = kinds
        self.options = options
        return candidates
    }

    func candidate(_ name: String, kind: DiskCleanupKind, safetyLevel: DiskCleanupSafetyLevel? = nil) -> DiskCleanupCandidate {
        DiskCleanupCandidate(url: URL(fileURLWithPath: "/Users/test/\(name)"), kind: kind,
                             byteSize: 1_024, displayName: name, safetyLevel: safetyLevel)
    }
}

private actor CleanupScanGate {
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var waiter: CheckedContinuation<Void, Never>?
    private var started = 0

    func wait() async {
        await withCheckedContinuation { continuation in
            started += 1
            pending.append(continuation)
            waiter?.resume()
            waiter = nil
        }
    }

    func waitUntilScanning(_ count: Int) async {
        if started >= count { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func startedCount() -> Int { started }

    func releaseOne() {
        pending.removeFirst().resume()
    }
}

private final class TrashReservationDefaults: UserDefaults {
    var synchronizationAllowed = true

    override func synchronize() -> Bool {
        synchronizationAllowed && super.synchronize()
    }
}
