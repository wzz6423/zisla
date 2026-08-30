import Foundation
import Testing

@testable import ZislaKit

struct AudioSpectrumServiceTests {
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

    @Test
    func processTapCreationAlwaysUsesAuthorizationHost() throws {
        let source = try String(
            contentsOf: Self.sourcesDirectoryURL.appendingPathComponent("ZislaKit/AudioSpectrumService.swift"),
            encoding: .utf8
        )
        let createGraph = try #require(source.range(of: "private func createGraph("))
        let graphBody = source[createGraph.lowerBound...]

        #expect(graphBody.contains("host = WindowPlacement.authorizationPromptHost()"))
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

    func fail(at index: Int) {
        failures[index]()
    }
}
