import Foundation

public struct RecordingPortraitEffects: Codable, Equatable, Sendable {
    public var smoothing: Double
    public var brightening: Double
    public var faceSlimming: Double
    public var bodySlimming: Double

    public init(smoothing: Double = 0, brightening: Double = 0, faceSlimming: Double = 0, bodySlimming: Double = 0) {
        self.smoothing = smoothing
        self.brightening = brightening
        self.faceSlimming = faceSlimming
        self.bodySlimming = bodySlimming
    }

    public var isEnabled: Bool { smoothing > 0 || brightening > 0 || faceSlimming > 0 || bodySlimming > 0 }
    public var isValid: Bool {
        [smoothing, brightening, faceSlimming, bodySlimming].allSatisfy { (0...1).contains($0) }
    }
}
