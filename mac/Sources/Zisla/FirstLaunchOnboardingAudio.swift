import AVFoundation
import Foundation

@MainActor
protocol FirstLaunchOnboardingAudioPlaying: AnyObject {
    var volume: Float { get set }
    var isPlaying: Bool { get }
    var onFinish: (@MainActor () -> Void)? { get set }
    func prepareToPlay() -> Bool
    func play() -> Bool
    func stop()
}

@MainActor
final class FirstLaunchOnboardingAudio {
    var isMuted = false {
        didSet { player?.volume = isMuted ? 0 : 1 }
    }
    var isPlaying: Bool { player?.isPlaying ?? false }

    private let makePlayer: (Data) throws -> any FirstLaunchOnboardingAudioPlaying
    private var player: (any FirstLaunchOnboardingAudioPlaying)?
    private var playbackID: UUID?

    init() {
        makePlayer = { try FirstLaunchOnboardingAVPlayer(data: $0) }
    }

    init(makePlayer: @escaping (Data) throws -> any FirstLaunchOnboardingAudioPlaying) {
        self.makePlayer = makePlayer
    }

    @discardableResult
    func play() -> Bool {
        if isPlaying { return true }
        stop()
        do {
            let candidate = try makePlayer(FirstLaunchOnboardingScore.wavData())
            let id = UUID()
            candidate.volume = isMuted ? 0 : 1
            candidate.onFinish = { [weak self] in
                // A queued completion from an old player must not stop a new playback.
                guard self?.playbackID == id else { return }
                self?.stop()
            }
            player = candidate
            playbackID = id
            guard candidate.prepareToPlay(), candidate.play(), candidate.isPlaying else {
                stop()
                return false
            }
            return true
        } catch {
            stop()
            return false
        }
    }

    func stop() {
        playbackID = nil
        player?.onFinish = nil
        player?.stop()
        player = nil
    }
}

@MainActor
private final class FirstLaunchOnboardingAVPlayer: NSObject, FirstLaunchOnboardingAudioPlaying,
    AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var onFinish: (@MainActor () -> Void)?
    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }
    var isPlaying: Bool { player.isPlaying }

    init(data: Data) throws {
        player = try AVAudioPlayer(data: data)
        super.init()
        player.numberOfLoops = 0
        player.delegate = self
    }

    func prepareToPlay() -> Bool { player.prepareToPlay() }
    func play() -> Bool { player.play() }
    func stop() { player.stop() }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.onFinish?() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in self?.onFinish?() }
    }
}

enum FirstLaunchOnboardingScore {
    static let sampleRate = 24_000
    static let duration = 7.2
    static let frameCount = 172_800
    static let peakLimit = 0.18

    private struct Note {
        let start: Double
        let duration: Double
        let midi: Int
        let gain: Double
    }

    // Original D-major phrase: D5 A4 F#5 E5 A5 F#5 E5 B4 E5 D5,
    // over D(add9), Gmaj7 and D6. All timing and voicing live here.
    private static let notes: [Note] = [
        Note(start: 0.00, duration: 1.15, midi: 74, gain: 0.065),
        Note(start: 0.45, duration: 1.10, midi: 69, gain: 0.050),
        Note(start: 0.90, duration: 1.25, midi: 78, gain: 0.060),
        Note(start: 1.50, duration: 1.15, midi: 76, gain: 0.050),
        Note(start: 2.10, duration: 1.50, midi: 81, gain: 0.060),
        Note(start: 2.85, duration: 1.20, midi: 78, gain: 0.052),
        Note(start: 3.45, duration: 1.20, midi: 76, gain: 0.048),
        Note(start: 4.05, duration: 1.35, midi: 71, gain: 0.050),
        Note(start: 4.80, duration: 1.40, midi: 76, gain: 0.048),
        Note(start: 5.40, duration: 1.80, midi: 74, gain: 0.060),
        Note(start: 0.00, duration: 2.40, midi: 50, gain: 0.018),
        Note(start: 0.00, duration: 2.40, midi: 57, gain: 0.014),
        Note(start: 0.00, duration: 2.40, midi: 64, gain: 0.012),
        Note(start: 2.40, duration: 2.40, midi: 55, gain: 0.018),
        Note(start: 2.40, duration: 2.40, midi: 62, gain: 0.014),
        Note(start: 2.40, duration: 2.40, midi: 66, gain: 0.012),
        Note(start: 4.80, duration: 2.40, midi: 50, gain: 0.018),
        Note(start: 4.80, duration: 2.40, midi: 57, gain: 0.014),
        Note(start: 4.80, duration: 2.40, midi: 59, gain: 0.012),
    ]

    static func wavData() -> Data {
        // Fixed mono PCM16: 345,600 payload bytes; no cache or audio resource files.
        var mix = [Double](repeating: 0, count: frameCount)
        for note in notes {
            let frequency = 440 * pow(2, Double(note.midi - 69) / 12)
            let start = Int(note.start * Double(sampleRate))
            let end = min(frameCount, Int((note.start + note.duration) * Double(sampleRate)))
            for frame in start..<end {
                let t = Double(frame - start) / Double(sampleRate)
                let attack = min(1, t / 0.045)
                let release = min(1, (note.duration - t) / 0.35)
                let envelope = attack * attack * release * release * exp(-1.4 * t)
                let phase = 2 * Double.pi * frequency * t
                let wave = 0.88 * sin(phase) + 0.12 * sin(2 * phase)
                mix[frame] += note.gain * envelope * wave
            }
        }

        var data = Data(capacity: 44 + frameCount * 2)
        func appendLE<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        appendLE(UInt32(36 + frameCount * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendLE(UInt32(16))
        appendLE(UInt16(1))
        appendLE(UInt16(1))
        appendLE(UInt32(sampleRate))
        appendLE(UInt32(sampleRate * 2))
        appendLE(UInt16(2))
        appendLE(UInt16(16))
        data.append(contentsOf: "data".utf8)
        appendLE(UInt32(frameCount * 2))
        for frame in 0..<frameCount {
            let t = Double(frame) / Double(sampleRate)
            let remaining = Double(frameCount - 1 - frame) / Double(sampleRate)
            let fade = min(1, t / 0.08) * min(1, remaining / 0.5)
            let sample = peakLimit * tanh(mix[frame] / peakLimit) * fade * fade
            appendLE(Int16((sample * Double(Int16.max)).rounded()))
        }
        return data
    }
}
