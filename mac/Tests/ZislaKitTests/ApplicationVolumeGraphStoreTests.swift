import CoreAudio
import Foundation
import Testing

@testable import ZislaKit

struct ApplicationVolumeGraphStoreTests {
    @Test
    func replacingHelpersRetriesTheFailedApplication() {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.failTapForProcesses = [[101]]
        let store = Self.store(hardware)
        defer { store.stop() }

        let original = ApplicationVolumeRequest(id: "music", processIdentifiers: [101], gain: 0.4)
        #expect(store.apply([original], retryingApplication: nil, rebuild: false)["music"] != nil)

        let replacement = ApplicationVolumeRequest(id: "music", processIdentifiers: [102, 103], gain: 0.4)
        let failures = store.apply([replacement], retryingApplication: nil, rebuild: false)

        #expect(failures.isEmpty, "A replacement helper must not inherit the exited process's failure")
        #expect(store.hasGraphs)
        #expect(hardware.tapDescriptions.last?.processes == [102, 103])
    }

    @Test
    func reusingAPIDWithANewProcessObjectRetriesItsFailure() {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.failTapForProcesses = [[101]]
        let store = Self.store(hardware)
        defer { store.stop() }
        let request = ApplicationVolumeRequest(id: "music", processIdentifiers: [101], gain: 0.4)
        #expect(store.apply([request], retryingApplication: nil, rebuild: false)["music"] != nil)

        hardware.objectsByPID[101] = 401
        let failures = store.apply([request], retryingApplication: nil, rebuild: false)

        #expect(failures.isEmpty, "PID reuse must not retain a failure for a different Core Audio process")
        #expect(store.hasGraphs)
        #expect(hardware.tapDescriptions.last?.processes == [401])
    }

    @Test
    func selectingAnotherOutputRetriesItsFailure() {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.failAt = .tap
        let store = Self.store(hardware)
        defer { store.stop() }
        let request = ApplicationVolumeRequest(id: "music", processIdentifiers: [101], gain: 0.4)
        #expect(store.apply([request], retryingApplication: nil, rebuild: false)["music"] != nil)

        hardware.failAt = nil
        hardware.output = ApplicationVolumeOutput(id: 500, uid: "fixture.replacement-output")
        let failures = store.apply([request], retryingApplication: nil, rebuild: false)

        #expect(failures.isEmpty, "A failure on the old output must not disable a newly selected output")
        #expect(store.hasGraphs)
    }

    @Test
    func separateApplicationsKeepIndependentGainsAndMuteWithoutRecreatingGraphs() {
        let hardware = ApplicationVolumeHardwareStub()
        let store = Self.store(hardware)
        defer { store.stop() }
        let music = Self.request("music", pids: [101, 102], gain: 0.25)
        let video = Self.request("video", pids: [201], gain: 0.75)
        #expect(store.apply([music, video], retryingApplication: nil, rebuild: false).isEmpty)
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])

        hardware.emit(input: input, output: output, at: 0)
        #expect(output.samples(at: 0) == [0.25, -0.25])
        hardware.emit(input: input, output: output, at: 1)
        #expect(output.samples(at: 0) == [0.75, -0.75])
        #expect(hardware.tapDescriptions.map(\.processes) == [[101, 102], [201]])

        #expect(store.apply([Self.request("music", pids: [101, 102], gain: 0), video],
                            retryingApplication: nil, rebuild: false).isEmpty)
        hardware.emit(input: input, output: output, at: 0)
        #expect(output.samples(at: 0) == [0, 0])
        hardware.emit(input: input, output: output, at: 1)
        #expect(output.samples(at: 0) == [0.75, -0.75])
        #expect(hardware.liveTaps.count == 2 && hardware.callbacks.count == 2)
    }

    @Test
    func removingAUnityRequestReleasesOnlyThatApplicationAndEmptyRequestsReleaseEverything() {
        let hardware = ApplicationVolumeHardwareStub()
        let store = Self.store(hardware)
        defer { store.stop() }
        let video = Self.request("video", pids: [201], gain: 0.75)
        #expect(store.apply([Self.request(), video], retryingApplication: nil, rebuild: false).isEmpty)
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])

        #expect(store.apply([video], retryingApplication: nil, rebuild: false).isEmpty)

        hardware.emit(input: input, output: output, at: 0)
        #expect(output.samples(at: 0) == [0, 0])
        hardware.emit(input: input, output: output, at: 1)
        #expect(output.samples(at: 0) == [0.75, -0.75])
        #expect(hardware.liveTaps.count == 1 && hardware.liveAggregates.count == 1 && hardware.liveIO.count == 1)

        #expect(store.apply([], retryingApplication: nil, rebuild: false).isEmpty)
        #expect(!store.hasGraphs)
        #expect(hardware.liveTaps.isEmpty && hardware.liveAggregates.isEmpty && hardware.liveIO.isEmpty)
        #expect(store.releaseStalledGraphs().isEmpty)
    }

    @Test
    func changingProcessObjectsAndOutputReplacesGraphsWithoutLeakingResources() {
        let hardware = ApplicationVolumeHardwareStub()
        let store = Self.store(hardware)
        defer { store.stop() }
        #expect(store.apply([Self.request()], retryingApplication: nil, rebuild: false).isEmpty)
        let originalTaps = hardware.liveTaps
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        hardware.objectsByPID[101] = 301

        #expect(store.apply([Self.request()], retryingApplication: nil, rebuild: false).isEmpty)

        #expect(hardware.liveTaps.isDisjoint(with: originalTaps))
        #expect(hardware.tapDescriptions.last?.processes == [301])
        hardware.emit(input: input, output: output, at: 0)
        #expect(output.samples(at: 0) == [0, 0])
        hardware.output = ApplicationVolumeOutput(id: 70, uid: "fixture.second-output")
        #expect(store.apply([Self.request()], retryingApplication: nil, rebuild: false).isEmpty)
        hardware.emit(input: input, output: output, at: 2)
        #expect(output.samples(at: 0) == [0.5, -0.5])
        #expect(hardware.liveTaps.count == 1 && hardware.liveAggregates.count == 1 && hardware.liveIO.count == 1)
    }

    @Test
    func permissionsForTheSameContextAreNotRepeatedUntilTheUserRetries() {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.failure = .permissionDenied
        hardware.failTapForProcesses = [[101]]
        let store = Self.store(hardware)
        defer { store.stop() }
        #expect(store.apply([Self.request()], retryingApplication: nil, rebuild: false) == ["music": .permissionDenied])
        hardware.failTapForProcesses = []

        #expect(store.apply([Self.request(gain: 0.25)], retryingApplication: nil,
                            rebuild: false) == ["music": .permissionDenied])
        #expect(hardware.tapDescriptions.count == 1)
        #expect(!store.hasGraphs)
        #expect(store.apply([Self.request(gain: 0.25)], retryingApplication: "music", rebuild: false).isEmpty)
        #expect(store.hasGraphs)
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        hardware.emit(input: input, output: output)
        #expect(output.samples(at: 0) == [0.25, -0.25])
    }

    @Test
    func processResolutionFailureCanRecoverWithoutInheritingAStaleContext() {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.failAt = .processObjects
        let store = Self.store(hardware)
        defer { store.stop() }
        #expect(store.apply([Self.request()], retryingApplication: nil, rebuild: false) == ["music": hardware.failure])

        hardware.failAt = nil

        #expect(store.apply([Self.request()], retryingApplication: nil, rebuild: false).isEmpty)
        #expect(store.hasGraphs)
    }

    @Test
    func helperIdentityChangeStillRetriesWhenItsAudioObjectIsUnchanged() {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.failure = .permissionDenied
        hardware.failTapForProcesses = [[101]]
        let store = Self.store(hardware)
        defer { store.stop() }
        #expect(store.apply([Self.request()], retryingApplication: nil, rebuild: false)["music"] == .permissionDenied)
        hardware.objectsByPID[102] = 101
        hardware.failTapForProcesses = []

        #expect(store.apply([Self.request(pids: [102])], retryingApplication: nil, rebuild: false).isEmpty)
        #expect(store.hasGraphs)
    }

    @Test
    func aCreationFailureRestoresThatApplicationWithoutInterruptingAnother() {
        let hardware = ApplicationVolumeHardwareStub()
        let store = Self.store(hardware)
        defer { store.stop() }
        let music = Self.request()
        let video = Self.request("video", pids: [201], gain: 0.75)
        #expect(store.apply([music], retryingApplication: nil, rebuild: false).isEmpty)
        let existingTaps = hardware.liveTaps
        let existingAggregates = hardware.liveAggregates
        let existingIO = hardware.liveIO
        hardware.failAt = .start

        #expect(store.apply([music, video], retryingApplication: nil, rebuild: false) == ["video": hardware.failure])

        #expect(hardware.liveTaps == existingTaps)
        #expect(hardware.liveAggregates == existingAggregates)
        #expect(hardware.liveIO == existingIO)
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        hardware.emit(input: input, output: output, at: 1)
        #expect(output.samples(at: 0) == [0, 0])
        hardware.emit(input: input, output: output, at: 0)
        #expect(output.samples(at: 0) == [0.5, -0.5])
        hardware.failAt = nil
        #expect(store.apply([music, video], retryingApplication: "video", rebuild: false).isEmpty)
        #expect(hardware.liveTaps.count == 2 && hardware.liveIO.count == 2)
    }

    @Test
    func outputUnavailableReleasesControlsAndReselectingAnOutputRecovers() {
        let hardware = ApplicationVolumeHardwareStub()
        let store = Self.store(hardware)
        defer { store.stop() }
        let requests = [Self.request(), Self.request("video", pids: [201], gain: 0.75)]
        #expect(store.apply(requests, retryingApplication: nil, rebuild: false).isEmpty)
        hardware.failAt = .defaultOutput
        hardware.failure = .outputUnavailable

        #expect(store.apply(requests, retryingApplication: nil, rebuild: false)
                == ["music": .outputUnavailable, "video": .outputUnavailable])

        #expect(!store.hasGraphs)
        #expect(hardware.liveTaps.isEmpty && hardware.liveAggregates.isEmpty && hardware.liveIO.isEmpty)
        hardware.failAt = nil
        hardware.output = ApplicationVolumeOutput(id: 500, uid: "fixture.available-output")
        #expect(store.apply(requests, retryingApplication: nil, rebuild: false).isEmpty)
        #expect(hardware.liveIO.count == 2)
    }

    @Test
    func aStalledApplicationRestoresPlaybackWhileAnotherProgressesAndUserRetryRecovers() {
        let hardware = ApplicationVolumeHardwareStub()
        let store = Self.store(hardware)
        defer { store.stop() }
        let requests = [Self.request(), Self.request("video", pids: [201], gain: 0.75)]
        #expect(store.apply(requests, retryingApplication: nil, rebuild: false).isEmpty)
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        hardware.emit(input: input, output: output, at: 0)

        #expect(store.releaseStalledGraphs() == ["video": .hardware(kAudioHardwareNotRunningError)])

        #expect(hardware.liveIO.count == 1)
        hardware.emit(input: input, output: output, at: 1)
        #expect(output.samples(at: 0) == [0, 0], "停滞链路释放后保留的回调必须静音")
        hardware.emit(input: input, output: output, at: 0)
        #expect(output.samples(at: 0) == [0.5, -0.5])
        #expect(store.releaseStalledGraphs().isEmpty)
        #expect(store.apply(requests, retryingApplication: nil, rebuild: false)
                == ["video": .hardware(kAudioHardwareNotRunningError)])
        #expect(store.apply(requests, retryingApplication: "video", rebuild: false).isEmpty)
        hardware.emit(input: input, output: output, at: 2)
        #expect(output.samples(at: 0) == [0.75, -0.75])
        #expect(hardware.liveIO.count == 2)
    }

    @Test
    func rebuildingOnTheSameOutputRefreshesCompensationAndClearsFailures() {
        let hardware = ApplicationVolumeHardwareStub()
        let store = Self.store(hardware)
        defer { store.stop() }
        let requests = [Self.request()]
        #expect(store.apply(requests, retryingApplication: nil, rebuild: false).isEmpty)
        hardware.compensation = 3

        #expect(store.apply(requests, retryingApplication: nil, rebuild: true).isEmpty)

        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        hardware.emit(input: input, output: output, at: 0)
        #expect(output.samples(at: 0) == [0, 0])
        hardware.emit(input: input, output: output, at: 1)
        #expect(output.samples(at: 0) == [1.5, -1.5])
        #expect(hardware.liveIO.count == 1)
        hardware.failAt = .compensation
        #expect(store.apply(requests, retryingApplication: nil, rebuild: true)["music"] == hardware.failure)
        hardware.failAt = nil
        #expect(store.apply(requests, retryingApplication: nil, rebuild: true).isEmpty)
        #expect(hardware.liveIO.count == 1)
    }

    @Test
    func stopIsIdempotentAndClearsFailuresBeforeReselection() {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.failTapForProcesses = [[201]]
        let store = Self.store(hardware)
        defer { store.stop() }
        let requests = [Self.request(), Self.request("video", pids: [201], gain: 0.75)]
        #expect(store.apply(requests, retryingApplication: nil, rebuild: false)["video"] != nil)

        store.stop()
        let firstStopEvents = hardware.events
        store.stop()

        #expect(hardware.events == firstStopEvents)
        #expect(!store.hasGraphs)
        #expect(hardware.liveTaps.isEmpty && hardware.liveAggregates.isEmpty && hardware.liveIO.isEmpty)
        #expect(store.releaseStalledGraphs().isEmpty)
        hardware.failTapForProcesses = []
        #expect(store.apply(requests, retryingApplication: nil, rebuild: false).isEmpty)
        #expect(hardware.liveIO.count == 2)
    }

    @Test
    func removingAFailedRequestAllowsTheSameApplicationToBeSelectedAgain() {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.failTapForProcesses = [[101]]
        let store = Self.store(hardware)
        defer { store.stop() }
        #expect(store.apply([Self.request()], retryingApplication: nil, rebuild: false)["music"] != nil)

        #expect(store.apply([], retryingApplication: nil, rebuild: false).isEmpty)
        hardware.failTapForProcesses = []

        #expect(store.apply([Self.request()], retryingApplication: nil, rebuild: false).isEmpty)
        #expect(hardware.liveIO.count == 1)
    }

    private static func store(_ hardware: ApplicationVolumeHardwareStub) -> ApplicationVolumeGraphStore {
        ApplicationVolumeGraphStore(hardware: hardware, dispose: { $0() })
    }

    private static func request(_ id: String = "music", pids: [pid_t] = [101], gain: Float = 0.5)
        -> ApplicationVolumeRequest {
        ApplicationVolumeRequest(id: id, processIdentifiers: pids, gain: gain)
    }
}
