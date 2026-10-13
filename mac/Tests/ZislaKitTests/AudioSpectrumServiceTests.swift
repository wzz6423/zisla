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
    func idleStartupAndVisualizationChangesNeverOpenAudioCapture() {
        let capture = FakeAudioSpectrumCapture()
        let service = AudioSpectrumService(capture: capture)

        service.startMonitoring(hasActivePlayback: false)
        service.setVisualizationEnabled(false)
        service.setVisualizationEnabled(true)
        service.startMonitoring(hasActivePlayback: false)

        #expect(capture.startCount == 0)
        #expect(!capture.isCapturing)
        #expect(!service.isAudible)
        #expect(service.levels.allSatisfy { $0 == 0 })
    }

    @Test @MainActor
    func playbackStartsCaptureAndIdleReleasesItWithoutAcceptingLateFrames() async {
        let capture = FakeAudioSpectrumCapture()
        let service = AudioSpectrumService(capture: capture)

        service.startMonitoring(hasActivePlayback: true)
        capture.emitAudibleFrame(at: 0)
        await drainMainActor()
        #expect(capture.isCapturing)
        #expect(service.isAudible)
        #expect(service.levels.contains { $0 > 0 })

        service.startMonitoring(hasActivePlayback: false)
        #expect(!capture.isCapturing)
        #expect(!service.isAudible)
        #expect(service.levels.allSatisfy { $0 == 0 })

        capture.emitAudibleFrame(at: 0)
        await drainMainActor()
        #expect(!service.isAudible)
        #expect(service.levels.allSatisfy { $0 == 0 })

        service.startMonitoring(hasActivePlayback: true)
        capture.emitAudibleFrame(at: 1)
        await drainMainActor()
        #expect(capture.isCapturing)
        #expect(service.isAudible)
        service.stop()
        #expect(!capture.isCapturing)
    }

    @Test @MainActor
    func currentCaptureFailureAllowsRetryWhileStaleFailureCannotStopNewGeneration() async {
        let capture = FakeAudioSpectrumCapture()
        let service = AudioSpectrumService(capture: capture)

        service.startMonitoring(hasActivePlayback: true)
        #expect(capture.startCount == 1)

        capture.fail(at: 0)
        await drainMainActor()
        service.startMonitoring(hasActivePlayback: true)
        #expect(capture.startCount == 2)

        capture.fail(at: 0)
        await drainMainActor()
        service.startMonitoring(hasActivePlayback: true)
        #expect(capture.startCount == 2)

        capture.fail(at: 1)
        await drainMainActor()
        service.startMonitoring(hasActivePlayback: true)
        #expect(capture.startCount == 3)
        service.stop()
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
    private var frames: [@Sendable (AudioSpectrumFrame) -> Void] = []
    private(set) var startCount = 0
    private(set) var isCapturing = false

    func setAnalysisMode(_ mode: AudioSpectrumAnalysisMode) {}

    func start(
        onFrame: @escaping @Sendable (AudioSpectrumFrame) -> Void,
        onFailure: @escaping @Sendable () -> Void
    ) {
        startCount += 1
        isCapturing = true
        failures.append(onFailure)
        frames.append(onFrame)
    }

    func stop() { isCapturing = false }

    func emitAudibleFrame(at index: Int) {
        frames[index](AudioSpectrumFrame(levels: Array(repeating: 0.5, count: 7), rootMeanSquare: 0.1))
    }

    func fail(at index: Int) {
        if index == failures.count - 1 { isCapturing = false }
        failures[index]()
    }
}
