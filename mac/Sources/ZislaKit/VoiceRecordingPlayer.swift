import AVFoundation
import Foundation

@MainActor
protocol VoiceAudioPlaying: AnyObject {
    func prepareToPlay() -> Bool
    func play() -> Bool
    func stop()
}

extension AVAudioPlayer: VoiceAudioPlaying {}

@MainActor
public final class VoiceRecordingPlayer {
    public private(set) var activeRecordingID: UUID?

    private let makePlayer: (URL) throws -> any VoiceAudioPlaying
    private var player: (any VoiceAudioPlaying)?

    public init() {
        makePlayer = { try AVAudioPlayer(contentsOf: $0) }
    }

    init(_ makePlayer: @escaping (URL) throws -> any VoiceAudioPlaying) {
        self.makePlayer = makePlayer
    }

    @discardableResult
    public func play(id: UUID, url: URL) -> Bool {
        stop()
        do {
            let player = try makePlayer(url)
            guard player.prepareToPlay(), player.play() else {
                player.stop()
                return false
            }
            self.player = player
            activeRecordingID = id
            return true
        } catch {
            return false
        }
    }

    public func stop() {
        player?.stop()
        player = nil
        activeRecordingID = nil
    }
}
