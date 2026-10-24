import CoreAudio
import Foundation
import Testing
import ZislaCore

@testable import ZislaKit

@MainActor
struct ApplicationVolumeMixerServiceTests {
    @Test
    func listingSourcesDoesNotRequestAudioCapture() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101, 102])])
        let backend = ApplicationVolumeBackendStub()
        let service = Self.service(monitor, backend)
        defer { service.stop() }

        service.start()
        service.start()

        #expect(service.applications.map(\.id) == ["music"])
        #expect(service.applications.first?.volume == 1)
        #expect(service.applications.first?.isControlled == false)
        #expect(backend.appliedRequests == [[]])
        #expect(monitor.startCount == 1)
        #expect(backend.startCount == 1)
    }

    @Test
    func gainsAreIndependentAndIncludeEveryHelperProcess() {
        let monitor = ApplicationVolumeMonitorStub(sources: [
            Self.source("music", pids: [101, 102]), Self.source("video", pids: [201]),
        ])
        let backend = ApplicationVolumeBackendStub()
        let service = Self.service(monitor, backend)
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
    func mutingPreservesVolumeAndUnityReleasesTheApplication() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        let service = Self.service(monitor, backend)
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
        #expect(backend.appliedRequests.last == [])
        #expect(service.applications.first?.isControlled == false)
        #expect(service.applications.first?.volume == 1)
    }

    @Test(arguments: [-1.0, 0, 1, 2])
    func finiteVolumesStayWithinTheSupportedRange(value: Double) {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        let service = Self.service(monitor, backend)
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
        let service = Self.service(monitor, backend)
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
        let service = Self.service(monitor, backend)
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
        let service = Self.service(monitor, backend)
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
        let service = Self.service(monitor, backend)
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
        let service = Self.service(monitor, backend)
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
    func stopResetsControlsAndRejectsPreviousSessionCallbacks() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        backend.completesImmediately = false
        let service = Self.service(monitor, backend)
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
        #expect(service.applications.first?.volume == 1)
        #expect(service.applications.first?.isMuted == false)
        #expect(service.applications.first?.isControlled == false)
        #expect(service.errorMessage == nil)
        #expect(backend.appliedRequests.last == [])
    }

    @Test
    func unsupportedSystemsNeverStartMonitoringOrCapture() {
        let monitor = ApplicationVolumeMonitorStub(sources: [Self.source("music", pids: [101])])
        let backend = ApplicationVolumeBackendStub()
        backend.isSupported = false
        let service = Self.service(monitor, backend)

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

    private static func service(
        _ monitor: ApplicationVolumeMonitorStub, _ backend: ApplicationVolumeBackendStub
    ) -> ApplicationVolumeMixerService {
        ApplicationVolumeMixerService(
            monitor: monitor, backend: backend, ownProcessIdentifier: 999, ownBundleIdentifier: "fixture.zisla"
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
    var onOutputChanged: (@MainActor () -> Void)?
    var onControlFailure: (@MainActor (String, ApplicationVolumeFailure) -> Void)?
    var startCount = 0
    var stopCount = 0
    var failures: [String: ApplicationVolumeFailure] = [:]
    var completesImmediately = true
    var appliedRequests: [[ApplicationVolumeRequest]] = []
    private var completions: [@MainActor ([String: ApplicationVolumeFailure]) -> Void] = []

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func apply(
        _ requests: [ApplicationVolumeRequest], retryingApplication: String?,
        completion: @escaping @MainActor ([String: ApplicationVolumeFailure]) -> Void
    ) {
        appliedRequests.append(requests)
        completions.append(completion)
        if completesImmediately { completion(failures) }
    }
    func complete(at index: Int, failures: [String: ApplicationVolumeFailure]) { completions[index](failures) }
}
