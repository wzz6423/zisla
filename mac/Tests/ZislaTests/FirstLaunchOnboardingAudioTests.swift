import Foundation
import Testing

@testable import Zisla

struct FirstLaunchOnboardingScoreTests {
    @Test
    func emitsBoundedMonoPCMWithASevenSecondPhrase() throws {
        let data = FirstLaunchOnboardingScore.wavData()
        #expect(data.count == 345_644)
        #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
        #expect(readLE(data, at: 4, bytes: 4) == data.count - 8)
        #expect(String(decoding: data[8..<16], as: UTF8.self) == "WAVEfmt ")
        #expect(readLE(data, at: 16, bytes: 4) == 16)
        #expect(readLE(data, at: 20, bytes: 2) == 1)
        #expect(readLE(data, at: 22, bytes: 2) == 1)
        #expect(readLE(data, at: 24, bytes: 4) == 24_000)
        #expect(readLE(data, at: 28, bytes: 4) == 48_000)
        #expect(readLE(data, at: 32, bytes: 2) == 2)
        #expect(readLE(data, at: 34, bytes: 2) == 16)
        #expect(String(decoding: data[36..<40], as: UTF8.self) == "data")
        #expect(readLE(data, at: 40, bytes: 4) == data.count - 44)

        let samples = decode(data)
        #expect(samples.count == 172_800)
        #expect(Double(samples.count) / 24_000 == 7.2)
        #expect(samples.allSatisfy { $0.isFinite })
        let peak = try #require(samples.map { abs($0) }.max())
        #expect(peak > 0.03)
        #expect(peak <= 0.18)
    }

    @Test
    func hasQuietEndpointsAndSmoothSampleTransitions() throws {
        let samples = decode(FirstLaunchOnboardingScore.wavData())
        #expect(samples.first == 0)
        #expect(samples.last == 0)
        #expect(samples.prefix(240).allSatisfy { abs($0) < 0.001 })
        #expect(samples.suffix(240).allSatisfy { abs($0) < 0.001 })
        let largestStep = try #require(zip(samples, samples.dropFirst()).map { abs($0 - $1) }.max())
        #expect(largestStep < 0.05)
        let middle = samples[24_000..<120_000]
        let rms = sqrt(middle.reduce(0) { $0 + $1 * $1 } / Double(middle.count))
        #expect(rms > 0.005)
        #expect(rms < 0.08)
    }

    @Test
    func compositionIsByteForByteDeterministic() {
        #expect(FirstLaunchOnboardingScore.wavData() == FirstLaunchOnboardingScore.wavData())
    }

    private func readLE(_ data: Data, at offset: Int, bytes: Int) -> Int {
        (0..<bytes).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
    }

    private func decode(_ data: Data) -> [Double] {
        stride(from: 44, to: data.count, by: 2).map {
            let value = UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8
            return Double(Int16(bitPattern: value)) / Double(Int16.max)
        }
    }
}

@Suite @MainActor
struct FirstLaunchOnboardingAudioTests {
    @Test
    func initializationIsSilentAndRepeatedPlayKeepsTheSamePlayback() throws {
        let output = OnboardingAudioOutput()
        let audio = FirstLaunchOnboardingAudio(makePlayer: output.makePlayer)
        #expect(!audio.isPlaying)
        #expect(output.current == nil)

        #expect(audio.play())
        let first = try #require(output.current)
        #expect(audio.isPlaying)
        #expect(first.isAudible)
        #expect(first.position == 0)
        first.position = 1.5

        #expect(audio.play())
        #expect(output.current === first)
        #expect(first.position == 1.5)
        #expect(first.isAudible)
        audio.stop()
        #expect(!first.isAudible)
    }

    @Test(arguments: OnboardingAudioOutput.Failure.allCases)
    fileprivate func startupFailureIsSilentReleasesResourcesAndAllowsRetry(failure: OnboardingAudioOutput.Failure) {
        let output = OnboardingAudioOutput()
        output.failure = failure
        let audio = FirstLaunchOnboardingAudio(makePlayer: output.makePlayer)

        #expect(!audio.play())
        #expect(!audio.isPlaying)
        #expect(output.current == nil)

        output.failure = nil
        #expect(audio.play())
        #expect(audio.isPlaying)
        #expect(output.current?.isAudible == true)
        audio.stop()
        #expect(output.current == nil)
    }

    @Test
    func mutingAffectsCurrentPlaybackWithoutRestartingAndPersistsAcrossStops() throws {
        let output = OnboardingAudioOutput()
        let audio = FirstLaunchOnboardingAudio(makePlayer: output.makePlayer)
        audio.isMuted = true
        #expect(audio.play())
        let player = try #require(output.current)
        player.position = 2
        #expect(audio.isPlaying)
        #expect(!player.isAudible)
        #expect(player.volume == 0)

        audio.isMuted = false
        #expect(player.isAudible)
        #expect(player.volume == 1)
        #expect(player.position == 2)
        audio.isMuted = true
        #expect(!player.isAudible)
        audio.stop()
        #expect(audio.isMuted)
        #expect(audio.play())
        #expect(output.current?.volume == 0)
        audio.stop()
    }

    @Test
    func naturalCompletionReleasesThePlayerAndCanPlayAgain() {
        let output = OnboardingAudioOutput()
        let audio = FirstLaunchOnboardingAudio(makePlayer: output.makePlayer)
        #expect(audio.play())
        output.current?.finish()
        #expect(!audio.isPlaying)
        #expect(output.current == nil)
        #expect(audio.play())
        #expect(output.current?.isAudible == true)
        audio.stop()
    }

    @Test
    func stopIsIdempotentAndDetachesCompletionBeforeReleasingResources() throws {
        let output = OnboardingAudioOutput()
        let audio = FirstLaunchOnboardingAudio(makePlayer: output.makePlayer)
        audio.stop()
        #expect(!audio.isPlaying)
        #expect(audio.play())
        var old: OnboardingAudioPlayer? = try #require(output.current)
        let staleCompletion = try #require(old?.onFinish)

        audio.stop()
        audio.stop()
        #expect(!audio.isPlaying)
        #expect(old?.isAudible == false)
        #expect(old?.onFinish == nil)
        old = nil
        #expect(output.current == nil)

        #expect(audio.play())
        staleCompletion()
        #expect(audio.isPlaying)
        #expect(output.current?.isAudible == true)
        audio.stop()
        #expect(output.current == nil)
    }

    @Test
    func droppingTheOwnerDoesNotLeaveARetainCycle() {
        let output = OnboardingAudioOutput()
        var audio: FirstLaunchOnboardingAudio? = FirstLaunchOnboardingAudio(makePlayer: output.makePlayer)
        #expect(audio?.play() == true)
        weak var weakAudio = audio
        audio = nil
        #expect(weakAudio == nil)
        #expect(output.current == nil)
    }
}

@MainActor
private final class OnboardingAudioOutput {
    enum Failure: Error, CaseIterable {
        case initialization, preparation, playback, inactiveDevice
    }

    var failure: Failure?
    weak var current: OnboardingAudioPlayer?

    func makePlayer(data: Data) throws -> any FirstLaunchOnboardingAudioPlaying {
        if failure == .initialization { throw Failure.initialization }
        let player = OnboardingAudioPlayer(failure: failure)
        current = player
        return player
    }
}

@MainActor
private final class OnboardingAudioPlayer: FirstLaunchOnboardingAudioPlaying {
    var volume: Float = 1
    private(set) var isPlaying = false
    var onFinish: (@MainActor () -> Void)?
    var position = 0.0
    var isAudible: Bool { isPlaying && volume > 0 }
    private let failure: OnboardingAudioOutput.Failure?

    init(failure: OnboardingAudioOutput.Failure?) {
        self.failure = failure
    }

    func prepareToPlay() -> Bool { failure != .preparation }

    func play() -> Bool {
        guard failure != .playback else { return false }
        isPlaying = failure != .inactiveDevice
        position = 0
        return true
    }

    func stop() {
        isPlaying = false
        position = 0
    }

    func finish() {
        isPlaying = false
        onFinish?()
    }
}
