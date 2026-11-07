import Foundation

public enum RecordingVoicePreset: String, Codable, CaseIterable, Sendable {
    case original, natural, warm, bright, broadcast

    public var title: String {
        switch self {
        case .original: "原声"
        case .natural: "自然"
        case .warm: "温暖"
        case .bright: "清亮"
        case .broadcast: "播音"
        }
    }
}

public struct RecordingVoiceEffects: Codable, Equatable, Sendable {
    public var preset: RecordingVoicePreset
    public var amount: Double

    public var isEnabled: Bool { preset != .original && amount > 0 }
    public var isValid: Bool { amount.isFinite && (0...1).contains(amount) }

    public init(preset: RecordingVoicePreset = .original, amount: Double = 0.5) {
        self.preset = preset
        self.amount = amount
    }
}
