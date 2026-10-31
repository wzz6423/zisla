import Foundation

public enum MediaVisualizationStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case waveform
    case glow

    public var title: String {
        switch self {
        case .waveform: "音浪模式"
        case .glow: "光晕模式"
        }
    }
}
