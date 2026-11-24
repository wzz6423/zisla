import CoreAudio
import Foundation
import Testing
import ZislaCore

@testable import ZislaKit

@MainActor
struct ApplicationVolumeMixerServiceTests {
    private let preferenceDefaults = ApplicationVolumeDefaultsFixture()

    @Test
    func retryWithoutAnErrorDoesNotReapplyAudioControls() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()
        let requests = backend.appliedRequests
        let applications = service.applications

        service.retry()

        #expect(backend.appliedRequests == requests, "没有错误时重试不能重新协调所有候选来源")
        #expect(service.applications == applications)
    }

    @Test
    func retryAfterStopDoesNotRestartCaptureOrReapplyControls() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        backend.failures = ["music": .permissionDenied]
        let service = makeService(monitor, backend)
        service.start()
        #expect(service.errorMessage != nil)
        service.stop()
        let requests = backend.appliedRequests

        service.retry()

        #expect(backend.appliedRequests == requests)
        #expect(service.applications.isEmpty)
        #expect(service.errorMessage == nil)
        #expect(backend.stopCount == 1)
    }

    @Test
    func removedCandidatesCannotReportAQueuedControlFailure() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()
        service.setVolume(0.25, for: "music")
        monitor.publish([])

        backend.onControlFailure?("music", .hardware(kAudioHardwareNotRunningError))

        #expect(service.applications.isEmpty)
        #expect(service.errorMessage == nil, "已退场的候选不能用旧故障回调显示错误")
    }

    @Test
    func listingSourcesRequestsMonitoringWithoutControllingUnityPlayback() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101, 102])])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }

        service.start()
        service.start()

        #expect(service.applications.map(\.id) == ["music"])
        #expect(service.applications.first?.volume == 1)
        #expect(service.applications.first?.isControlled == false)
        let monitoring = [ApplicationVolumeRequest(id: "music", processIdentifiers: [101, 102], gain: 1)]
        #expect(backend.appliedRequests == [monitoring])
        #expect(monitor.startCount == 1)
        #expect(backend.startCount == 1)
    }

    @Test
    func gainsAreIndependentAndIncludeEveryHelperProcess() {
        let monitor = ApplicationVolumeMonitorStub(sources: [
            Self.source("music", pids: [101, 102]), Self.source("video", pids: [201]),
        ])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()

        service.setVolume(0.25, for: "music")
        service.setVolume(0.75, for: "video")

        #expect(backend.appliedRequests.last == [
            ApplicationVolumeRequest(id: "music", processIdentifiers: [101, 102], gain: 0.25),
            ApplicationVolumeRequest(id: "video", processIdentifiers: [201], gain: 0.75),
        ])
        #expect(service.applications.map(\.volume) == [0.25, 0.75])
        #expect(service.applications.allSatisfy { $0.isControlled })
    }

    @Test
    func mutingPreservesVolumeAndUnityReturnsToMonitoring() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()
        service.setVolume(0.4, for: "music")

        service.toggleMute(for: "music")
        #expect(service.applications.first?.volume == 0.4)
        #expect(service.applications.first?.isMuted == true)
        #expect(backend.appliedRequests.last?.first?.gain == 0)

        service.toggleMute(for: "music")
        #expect(service.applications.first?.isMuted == false)
        #expect(backend.appliedRequests.last?.first?.gain == 0.4)

        service.setVolume(1, for: "music")
        #expect(backend.appliedRequests.last == [
            ApplicationVolumeRequest(id: "music", processIdentifiers: [101], gain: 1),
        ])
        #expect(service.applications.first?.isControlled == false)
        #expect(service.applications.first?.volume == 1)
    }

    @Test(arguments: [-1.0, 0, 1, 2])
    func finiteVolumesStayWithinTheSupportedRange(value: Double) {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()

        service.setVolume(value, for: "music")

        #expect(service.applications.first?.volume == min(1, max(0, value)))
        #expect(service.applications.first?.isMuted == false)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonfiniteVolumesAndUnknownApplicationsHaveNoSideEffects(value: Double) {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()
        let original = service.applications
        let appliedCount = backend.appliedRequests.count

        service.setVolume(value, for: "music")
        service.setVolume(0.5, for: "unknown")
        service.toggleMute(for: "unknown")

        #expect(service.applications == original)
        #expect(backend.appliedRequests.count == appliedCount)
    }

    @Test
    func ownApplicationAndProcessAreExcludedFromCapture() {
        let monitor = ApplicationVolumeMonitorStub(sources: [
            Self.source("own", pids: [999, 998], bundle: "fixture.zisla"),
            Self.source("music", pids: [999, 101]),
            Self.source("ownProcess", pids: [999]),
            Self.source("empty", pids: []),
        ])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()

        #expect(service.applications.map(\.id) == ["music"])
        service.setVolume(0.5, for: "music")
        #expect(backend.appliedRequests.last?.first?.processIdentifiers == [101])
    }

    @Test
    func replacingHelpersAndChangingOutputReconcilesTheCurrentGain() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()
        service.setVolume(0.3, for: "music")

        monitor.publish([Self.source("music", pids: [102, 103])])
        backend.onOutputChanged?()

        #expect(service.applications.first?.volume == 0.3)
        #expect(service.applications.first?.isControlled == true)
        #expect(backend.appliedRequests.last == [
            ApplicationVolumeRequest(id: "music", processIdentifiers: [102, 103], gain: 0.3),
        ])

        monitor.publish([])
        #expect(service.applications.isEmpty)
        #expect(backend.appliedRequests.last == [])
    }

    @Test
    func controlFailureDoesNotMarkTheOtherApplicationAsFailed() {
        let monitor = ApplicationVolumeMonitorStub(sources: [
            Self.source("music", pids: [101]), Self.source("video", pids: [201]),
        ])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()
        service.setVolume(0.5, for: "music")
        backend.failures = ["video": .permissionDenied]

        service.setVolume(0.7, for: "video")

        #expect(service.applications[0].isControlled)
        #expect(!service.applications[1].isControlled)
        #expect(service.errorMessage == AppLocalization.text(ApplicationVolumeFailure.permissionDenied.messageKey))

        backend.failures = [:]
        service.setVolume(0.6, for: "video")
        #expect(service.applications.allSatisfy { $0.isControlled })
        #expect(service.errorMessage == nil)

        backend.onControlFailure?("video", .hardware(kAudioHardwareNotRunningError))
        #expect(service.applications[0].isControlled)
        #expect(!service.applications[1].isControlled)
        #expect(service.errorMessage != nil)
    }

    @Test
    func olderCompletionsCannotOverwriteTheLatestControlState() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        backend.completesImmediately = false
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()
        service.setVolume(0.2, for: "music")
        service.setVolume(0.8, for: "music")

        backend.complete(at: 2, failures: [:])
        backend.complete(at: 1, failures: ["music": .permissionDenied])

        #expect(service.applications.first?.volume == 0.8)
        #expect(service.applications.first?.isControlled == true)
        #expect(service.errorMessage == nil)
    }

    @Test
    func stopRestoresPlaybackButPreservesPreferencesAndRejectsPreviousSessionCallbacks() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        backend.completesImmediately = false
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()
        service.setVolume(0.2, for: "music")
        service.toggleMute(for: "music")

        service.stop()
        service.stop()
        backend.complete(at: 2, failures: ["music": .permissionDenied])
        monitor.publish([Self.source("music", pids: [102])])
        service.setVolume(0.5, for: "music")
        backend.onOutputChanged?()
        backend.onControlFailure?("music", .permissionDenied)
        #expect(service.applications.isEmpty)
        #expect(service.errorMessage == nil)
        #expect(monitor.stopCount == 1)
        #expect(backend.stopCount == 1)

        service.start()
        backend.complete(at: 1, failures: ["music": .permissionDenied])
        #expect(service.applications.first?.volume == 0.2)
        #expect(service.applications.first?.isMuted == true)
        #expect(service.applications.first?.isControlled == false)
        #expect(service.errorMessage == nil)
        #expect(backend.appliedRequests.last == [
            ApplicationVolumeRequest(id: "music", processIdentifiers: [102], gain: 0),
        ])
    }

    @Test
    func pausingAndRelaunchingAnApplicationRetainsItsVolumeAndMute() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()
        service.setVolume(0.35, for: "music")
        service.toggleMute(for: "music")

        monitor.publish([])
        #expect(service.applications.isEmpty)
        #expect(backend.appliedRequests.last == [])

        monitor.publish([Self.source("music", pids: [101])])
        #expect(service.applications.first?.volume == 0.35)
        #expect(service.applications.first?.isMuted == true)
        #expect(backend.appliedRequests.last?.first?.gain == 0)

        monitor.publish([])
        monitor.publish([Self.source("music", pids: [201, 202])])
        service.toggleMute(for: "music")
        #expect(service.applications.first?.volume == 0.35)
        #expect(backend.appliedRequests.last == [
            ApplicationVolumeRequest(id: "music", processIdentifiers: [201, 202], gain: 0.35),
        ])
    }

    @Test
    func aNewMixerRestoresSavedVolumesOnlyWhenTheApplicationsPlay() {
        let monitor = ApplicationVolumeMonitorStub(sources: [
            Self.source("music", pids: [101]), Self.source("video", pids: [201]),
        ])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        service.start()
        service.setVolume(0.35, for: "music")
        service.setVolume(0.6, for: "video")
        service.toggleMute(for: "video")
        service.stop()
        monitor.publish([])

        let restoredBackend = ApplicationVolumeBackendStub()
        let restored = makeService(monitor, restoredBackend)
        defer { restored.stop() }
        restored.start()
        #expect(restored.applications.isEmpty)
        #expect(restoredBackend.appliedRequests.last == [])

        monitor.publish([
            Self.source("music", pids: [102]), Self.source("video", pids: [202, 203]),
        ])
        #expect(restored.applications.map(\.volume) == [0.35, 0.6])
        #expect(restored.applications.map(\.isMuted) == [false, true])
        #expect(restoredBackend.appliedRequests.last == [
            ApplicationVolumeRequest(id: "music", processIdentifiers: [102], gain: 0.35),
            ApplicationVolumeRequest(id: "video", processIdentifiers: [202, 203], gain: 0),
        ])
    }

    @Test
    func changedVolumesAndMuteAreSavedBeforeTheMixerStops() throws {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()
        service.setVolume(0.4, for: "music")
        let volumeRecord = try #require(preferenceDefaults.store.dictionary(
            forKey: ApplicationVolumeMixerService.preferencesKey
        )?["music"] as? [String: Any])
        #expect(volumeRecord["volume"] as? Double == 0.4)
        #expect(volumeRecord["isMuted"] as? Bool == false)

        service.toggleMute(for: "music")
        let mutedRecord = try #require(preferenceDefaults.store.dictionary(
            forKey: ApplicationVolumeMixerService.preferencesKey
        )?["music"] as? [String: Any])
        #expect(mutedRecord["volume"] as? Double == 0.4)
        #expect(mutedRecord["isMuted"] as? Bool == true)

        service.setVolume(1, for: "music")
        let resetRecord = try #require(preferenceDefaults.store.dictionary(
            forKey: ApplicationVolumeMixerService.preferencesKey
        )?["music"] as? [String: Any])
        #expect(resetRecord["volume"] as? Double == 1)
        #expect(resetRecord["isMuted"] as? Bool == false)
        #expect(backend.appliedRequests.last == [
            ApplicationVolumeRequest(id: "music", processIdentifiers: [101], gain: 1),
        ])
    }

    @Test
    func malformedPreferencesDoNotDiscardValidApplications() {
        preferenceDefaults.store.set([
            "music": ["volume": 0.4, "isMuted": true],
            "negative": ["volume": -0.1, "isMuted": true],
            "large": ["volume": 1.1, "isMuted": true],
            "notFinite": ["volume": Double.nan, "isMuted": true],
            "infinite": ["volume": Double.infinity, "isMuted": true],
            "wrongType": ["volume": "0.3", "isMuted": true],
            "wrongMute": ["volume": 0.2, "isMuted": "true"],
            "missingMute": ["volume": 0.2],
            "notARecord": "invalid",
            "pid:301": ["volume": 0, "isMuted": true],
        ] as [String: Any], forKey: ApplicationVolumeMixerService.preferencesKey)
        let ids = ["music", "negative", "large", "notFinite", "infinite", "wrongType", "wrongMute", "missingMute", "notARecord", "pid:301"]
        let monitor = ApplicationVolumeMonitorStub(sources: ids.enumerated().map {
            Self.source($0.element, pids: [pid_t($0.offset + 101)])
        })
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()

        #expect(service.applications.first?.volume == 0.4)
        #expect(service.applications.first?.isMuted == true)
        #expect(service.applications.dropFirst().allSatisfy { $0.volume == 1 && !$0.isMuted })
        #expect(backend.appliedRequests.last == ids.enumerated().map {
            ApplicationVolumeRequest(id: $0.element, processIdentifiers: [pid_t($0.offset + 101)],
                                     gain: $0.element == "music" ? 0 : 1)
        })
    }

    @Test
    func aMalformedArchiveLoadsDefaultOutput() {
        preferenceDefaults.store.set("invalid", forKey: ApplicationVolumeMixerService.preferencesKey)
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()

        #expect(service.applications.first?.volume == 1)
        #expect(service.applications.first?.isMuted == false)
        #expect(backend.appliedRequests.last == [
            ApplicationVolumeRequest(id: "music", processIdentifiers: [101], gain: 1),
        ])
    }

    @Test
    func pidOnlyPreferencesCannotBeAppliedToAnUnrelatedRelaunchedProcess() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("pid:101", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        service.start()
        service.setVolume(0.2, for: "pid:101")
        service.toggleMute(for: "pid:101")
        #expect(preferenceDefaults.store.dictionary(forKey: ApplicationVolumeMixerService.preferencesKey)?["pid:101"] == nil)
        service.stop()

        let restoredBackend = ApplicationVolumeBackendStub()
        let restored = makeService(monitor, restoredBackend)
        defer { restored.stop() }
        restored.start()
        #expect(restored.applications.first?.volume == 1)
        #expect(restored.applications.first?.isMuted == false)
        #expect(restoredBackend.appliedRequests.last == [
            ApplicationVolumeRequest(id: "pid:101", processIdentifiers: [101], gain: 1),
        ])
    }

    @Test
    func restartingTheSameMixerDoesNotReusePidOnlyPreferences() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("pid:101", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        let service = makeService(monitor, backend)
        defer { service.stop() }
        service.start()
        service.setVolume(0.2, for: "pid:101")
        service.stop()
        service.start()

        #expect(service.applications.first?.volume == 1)
        #expect(service.applications.first?.isMuted == false)
        #expect(backend.appliedRequests.last == [
            ApplicationVolumeRequest(id: "pid:101", processIdentifiers: [101], gain: 1),
        ])
    }

    @Test
    func unsupportedSystemsNeverStartMonitoringOrCapture() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        backend.isSupported = false
        let service = makeService(monitor, backend)

        service.start()
        service.setVolume(0.5, for: "music")
        service.toggleMute(for: "music")
        service.stop()

        #expect(!service.isSupported)
        #expect(service.applications.isEmpty)
        #expect(backend.appliedRequests.isEmpty)
        #expect(monitor.startCount == 0)
        #expect(backend.startCount == 0)
        #expect(backend.stopCount == 0)
    }

    private func makeService(
        _ monitor: ApplicationVolumeMonitorStub, _ backend: ApplicationVolumeBackendStub
    ) -> ApplicationVolumeMixerService {
        backend.playingApplications = Set(monitor.sources.map(\.id))
        return ApplicationVolumeMixerService(
            monitor: monitor, backend: backend, ownProcessIdentifier: 999, ownBundleIdentifier: "fixture.zisla",
            defaults: preferenceDefaults.store
        )
    }

    private static func source(_ id: String, pids: [pid_t], bundle: String? = nil) -> AudioPlaybackSource {
        AudioPlaybackSource(
            id: id, processIdentifiers: pids, bundleIdentifier: bundle ?? "fixture.\(id)",
            applicationName: id, iconData: nil, isFrontmost: false
        )
    }
}

@MainActor
private final class ApplicationVolumeMonitorStub: ApplicationVolumeSourceMonitoring {
    var sources: [AudioPlaybackSource]
    var onSourcesChanged: (@MainActor ([AudioPlaybackSource]) -> Void)?
    var startCount = 0
    var stopCount = 0

    init(sources: [AudioPlaybackSource]) { self.sources = sources }
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func publish(_ sources: [AudioPlaybackSource]) {
        self.sources = sources
        onSourcesChanged?(sources)
    }
}

@MainActor
private final class ApplicationVolumeBackendStub: ApplicationVolumeMixing {
    var isSupported = true
    var playingApplications: Set<String> = []
    var onOutputChanged: (@MainActor () -> Void)?
    var onControlFailure: (@MainActor (String, ApplicationVolumeFailure) -> Void)?
    var onPlaybackChanged: (@MainActor (Set<String>) -> Void)?
    var startCount = 0
    var stopCount = 0
    var failures: [String: ApplicationVolumeFailure] = [:]
    var completesImmediately = true
    var appliedRequests: [[ApplicationVolumeRequest]] = []
    private var completions: [@MainActor ([String: ApplicationVolumeFailure]) -> Void] = []

    func start() { startCount += 1 }
    func stop() { stopCount += 1; playingApplications = [] }
    func apply(
        _ requests: [ApplicationVolumeRequest], retryingApplication: String?,
        completion: @escaping @MainActor ([String: ApplicationVolumeFailure]) -> Void
    ) {
        appliedRequests.append(requests)
        completions.append(completion)
        let next = Set(requests.map(\.id))
        let changed = next != playingApplications
        playingApplications = next
        if completesImmediately { completion(failures) }
        if changed { onPlaybackChanged?(next) }
    }
    func complete(at index: Int, failures: [String: ApplicationVolumeFailure]) { completions[index](failures) }
}

@MainActor
private final class ApplicationVolumeDefaultsFixture {
    private let suite = "Zisla.ApplicationVolume.\(UUID().uuidString)"
    let store: UserDefaults

    init() { store = UserDefaults(suiteName: suite)! }

    isolated deinit { store.removePersistentDomain(forName: suite) }
}
