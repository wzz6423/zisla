import Foundation

public enum RecordingCanvasAspectRatio: String, Codable, CaseIterable, Sendable {
    case original, landscape, portrait, square, standard

    public var title: String {
        switch self {
        case .original: "原始比例"
        case .landscape: "16:9"
        case .portrait: "9:16"
        case .square: "1:1"
        case .standard: "4:3"
        }
    }

    public var ratio: Double? {
        switch self {
        case .original: nil
        case .landscape: 16.0 / 9
        case .portrait: 9.0 / 16
        case .square: 1
        case .standard: 4.0 / 3
        }
    }
}

public struct RecordingColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let annotation = Self(red: 1, green: 0.8, blue: 0.1)
    public static let background = Self(red: 0.16, green: 0.19, blue: 0.53)
    public var isValid: Bool { [red, green, blue].allSatisfy { (0...1).contains($0) } }
}

public enum RecordingAnnotationKind: String, Codable, CaseIterable, Sendable {
    case text, arrow, rectangle

    public var title: String {
        switch self {
        case .text: "文字标注"
        case .arrow: "箭头标注"
        case .rectangle: "矩形标注"
        }
    }

    public var symbol: String {
        switch self {
        case .text: "textformat"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        }
    }
}

public struct RecordingAnnotation: Codable, Equatable, Identifiable, Sendable {
    public static let maximumCount = 200
    public var id: UUID
    public var kind: RecordingAnnotationKind
    public var start: Double
    public var end: Double
    public var x: Double
    public var y: Double
    public var endX: Double
    public var endY: Double
    public var text: String
    public var color: RecordingColor
    public var fontSize: Double
    public var lineWidth: Double

    public init(id: UUID = UUID(), kind: RecordingAnnotationKind, start: Double, end: Double,
                x: Double = 0.2, y: Double = 0.2, endX: Double = 0.7, endY: Double = 0.4,
                text: String = "", color: RecordingColor = .annotation,
                fontSize: Double = 0.06, lineWidth: Double = 0.006) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.x = x
        self.y = y
        self.endX = endX
        self.endY = endY
        self.text = text
        self.color = color
        self.fontSize = fontSize
        self.lineWidth = lineWidth
    }

    public var bounds: RecordingRect {
        .init(x: min(x, endX), y: min(y, endY), width: abs(endX - x), height: abs(endY - y))
    }

    public func isVisible(at time: Double) -> Bool { time >= start && time < end }

    public func isValid(duration: Double) -> Bool {
        duration.isFinite && duration > 0 && start >= 0 && end > start && end <= duration + 0.001
            && [x, y, endX, endY].allSatisfy { (0...1).contains($0) }
            && (kind == .arrow ? x != endX || y != endY : x != endX && y != endY)
            && text.count <= 4_000 && color.isValid
            && (0.01...0.3).contains(fontSize) && (0.001...0.05).contains(lineWidth)
    }
}
