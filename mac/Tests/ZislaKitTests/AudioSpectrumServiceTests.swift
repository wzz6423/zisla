import Foundation
import CoreAudio
import Testing

@testable import ZislaKit

struct AudioSpectrumServiceTests {
    @Test
    func spectrumTapExcludesOnlyZislasAudioProcess() {
        let ownProcessObject = AudioObjectID(11)
        let otherProcessObject = AudioObjectID(22)

        let excluded = AudioPlaybackMonitor.processObjectIDs(
            from: [ownProcessObject, otherProcessObject],
            matching: 1_001,
            processIdentifier: { object in
                object == ownProcessObject ? 1_001 : 2_002
            }
        )

        #expect(excluded == [ownProcessObject])
    }

    @Test
    func audibilityOnlyModeSkipsFFTAndUsesLowerSamplingFrequency() {
        #expect(AudioSpectrumAnalysisMode.visualization.minimumInterval == 1.0 / 20.0)
        #expect(AudioSpectrumAnalysisMode.visualization.includesFrequencyLevels)
        #expect(AudioSpectrumAnalysisMode.audibilityOnly.minimumInterval == 1.0 / 5.0)
        #expect(!AudioSpectrumAnalysisMode.audibilityOnly.includesFrequencyLevels)
    }

    @Test
    func silenceProducesNoFrequencyEnergy() {
        let analyzer = AudioFrequencyAnalyzer()

        let levels = analyzer.process(
            samples: Array(repeating: 0, count: analyzer.fftSize),
            sampleRate: 48_000
        )

        #expect(levels.count == AudioFrequencyAnalyzer.bandCount)
        #expect(levels.allSatisfy { $0 == 0 })
    }

    @Test
    func bassTonePrimarilyDrivesLowFrequencyBands() throws {
        let analyzer = AudioFrequencyAnalyzer()
        let sampleRate = 48_000.0
        let samples = (0..<analyzer.fftSize).map { index in
            Float(sin(2 * Double.pi * 100 * Double(index) / sampleRate) * 0.7)
        }

        let levels = analyzer.process(samples: samples, sampleRate: sampleRate)
        let lowPeak = try #require(levels.prefix(3).max())
        let highPeak = try #require(levels.suffix(2).max())

        #expect(lowPeak > 0.5)
        #expect(lowPeak > highPeak + 0.25)
    }

    @Test @MainActor
    func currentCaptureFailureAllowsRetryWhileStaleFailureCannotStopNewGeneration() async {
        let capture = FakeAudioSpectrumCapture()
        let service = AudioSpectrumService(capture: capture)

        service.startMonitoring()
        #expect(capture.startCount == 1)

        capture.fail(at: 0)
        await drainMainActor()
        service.startMonitoring()
        #expect(capture.startCount == 2)

        capture.fail(at: 0)
        await drainMainActor()
        service.startMonitoring()
        #expect(capture.startCount == 2)

        capture.fail(at: 1)
        await drainMainActor()
        service.startMonitoring()
        #expect(capture.startCount == 3)
        service.stop()
    }

    /// The dictation engine must only open the microphone after the tap's teardown finished, so the
    /// wait has to resume strictly after the pending capture work drained, in enqueue order.
    @Test @MainActor
    func captureTeardownWaitResumesAfterPendingCaptureWorkDrains() async {
        let capture = OrderedAudioSpectrumCapture()
        let service = AudioSpectrumService(capture: capture)

        service.startMonitoring()
        service.stop()
        await service.waitForCaptureTeardown()

        #expect(capture.events == ["start", "stop", "barrier"])
    }

    /// Dictation must not hang when monitoring was never running: the wait still has to resume.
    @Test @MainActor
    func captureTeardownWaitResumesWithoutPendingCaptureWork() async {
        let capture = OrderedAudioSpectrumCapture()
        let service = AudioSpectrumService(capture: capture)

        await service.waitForCaptureTeardown()

        #expect(capture.events == ["barrier"])
    }

    /// The focus thief: every automatic graph rebuild anchored a permission prompt, and anchoring
    /// activates the app. A granted tap never fails, so it must never anchor.
    @Test
    func grantedTapCreationNeverRequestsAuthorizationPrompt() {
        #expect(!SystemAudioSpectrumCapture.shouldRequestAuthorizationPrompt(
            creationFailed: false,
            hasRequestedInCurrentLaunch: false
        ))
        #expect(!SystemAudioSpectrumCapture.shouldRequestAuthorizationPrompt(
            creationFailed: false,
            hasRequestedInCurrentLaunch: true
        ))
    }

    /// A denied tap keeps failing on every reveal, so the prompt is anchored at most once per launch.
    @Test
    func failedTapCreationRequestsAuthorizationPromptOncePerLaunch() {
        #expect(SystemAudioSpectrumCapture.shouldRequestAuthorizationPrompt(
            creationFailed: true,
            hasRequestedInCurrentLaunch: false
        ))
        #expect(!SystemAudioSpectrumCapture.shouldRequestAuthorizationPrompt(
            creationFailed: true,
            hasRequestedInCurrentLaunch: true
        ))
    }

    /// `AudioHardwareCreateProcessTap` cannot be injected, so guard the call site itself: the host may
    /// only be built after the prompt decision, never unconditionally as it once was.
    @Test
    func authorizationHostStaysBehindThePromptDecision() throws {
        let source = try String(
            contentsOf: Self.sourcesDirectoryURL.appendingPathComponent("ZislaKit/AudioSpectrumService.swift"),
            encoding: .utf8
        )
        let createGraph = try #require(source.range(of: "private func createGraph("))
        let graphBody = source[createGraph.lowerBound...]
        let hostCreation = try #require(
            graphBody.range(of: "WindowPlacement.authorizationPromptHost()")
        )

        #expect(graphBody[..<hostCreation.lowerBound]
            .contains("Self.shouldRequestAuthorizationPrompt("))
        #expect(!graphBody.contains("CGPreflightScreenCaptureAccess()"))
    }

    /// `AudioHardwareCreateProcessTap` cannot be injected, so the production barrier must be read
    /// from source: it only preserves create/teardown ordering while it runs on the control queue.
    @Test
    func captureTeardownBarrierRunsOnTheControlQueue() throws {
        let source = try String(
            contentsOf: Self.sourcesDirectoryURL.appendingPathComponent("ZislaKit/AudioSpectrumService.swift"),
            encoding: .utf8
        )
        let capture = try #require(source.range(of: "final class SystemAudioSpectrumCapture"))
        let captureBody = source[capture.lowerBound...]
        let barrier = try #require(
            captureBody.range(of: "func performAfterPendingWork(_ block: @escaping @Sendable () -> Void) {")
        )
        let barrierEnd = try #require(captureBody[barrier.upperBound...].range(of: "\n    }"))
        let barrierBody = captureBody[barrier.lowerBound..<barrierEnd.upperBound]

        #expect(barrierBody.contains("controlQueue.async"))
    }

    @MainActor
    private func drainMainActor() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    private static var sourcesDirectoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }
}

private final class FakeAudioSpectrumCapture: AudioSpectrumCapturing, @unchecked Sendable {
    private var failures: [@Sendable () -> Void] = []
    private(set) var startCount = 0

    func setAnalysisMode(_ mode: AudioSpectrumAnalysisMode) {}

    func start(
        onFrame: @escaping @Sendable (AudioSpectrumFrame) -> Void,
        onFailure: @escaping @Sendable () -> Void
    ) {
        startCount += 1
        failures.append(onFailure)
    }

    func stop() {}

    func performAfterPendingWork(_ block: @escaping @Sendable () -> Void) {
        block()
    }

    func fail(at index: Int) {
        failures[index]()
    }
}

/// Mirrors the production capture's serial control queue so ordering between capture work and a
/// teardown barrier is observable.
private final class OrderedAudioSpectrumCapture: AudioSpectrumCapturing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "test.ordered-audio-spectrum-capture")
    private let lock = NSLock()
    private var recordedEvents: [String] = []

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }

    private func record(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        recordedEvents.append(event)
    }

    func setAnalysisMode(_ mode: AudioSpectrumAnalysisMode) {}

    func start(
        onFrame: @escaping @Sendable (AudioSpectrumFrame) -> Void,
        onFailure: @escaping @Sendable () -> Void
    ) {
        queue.async { self.record("start") }
    }

    func stop() {
        queue.async { self.record("stop") }
    }

    func performAfterPendingWork(_ block: @escaping @Sendable () -> Void) {
        queue.async {
            self.record("barrier")
            block()
        }
    }
}
