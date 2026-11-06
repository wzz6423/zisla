import Foundation
import SwiftUI
import ZislaCore

extension FirstLaunchGreetingArtwork {
    private struct SystemDrawing: Decodable {
        struct Curve: Decodable {
            let p0: [CGFloat]
            let p1: [CGFloat]
            let p2: [CGFloat]
            let p3: [CGFloat]
        }
        let strokes: [[Curve]]
        let scale: [CGFloat]
    }

    static func systemArtwork(
        for language: AppLanguage,
        read: (URL) throws -> Data
    ) throws -> Self {
        let name: String
        switch language {
        case .simplifiedChinese, .traditionalChinese: name = "zh_CN"
        case .brazilianPortuguese: name = "pt_BR"
        default: name = language.rawValue
        }
        // macOS 14+ ships the lettering locally; Apple's artwork is not redistributed.
        let directory = URL(fileURLWithPath:
            "/System/Library/ExtensionKit/Extensions/Hello.appex/Contents/Resources/Languages")
        return try Self(systemData: read(directory.appendingPathComponent("\(name).json")))
    }

    init(systemData: Data) throws {
        let drawing = try JSONDecoder().decode(SystemDrawing.self, from: systemData)
        guard drawing.scale.count == 4, drawing.scale.allSatisfy({ $0 > 0 }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid greeting drawing"))
        }
        var paths: [Path] = []
        var widths: [CGFloat] = []
        for curves in drawing.strokes {
            var path = Path()
            var radius: CGFloat = 0
            for (index, curve) in curves.enumerated() {
                let values = [curve.p0, curve.p1, curve.p2, curve.p3]
                guard values.allSatisfy({ $0.count == 4 && $0[3] > 0 }) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid greeting point"))
                }
                let points = values.map { CGPoint(x: $0[0] * drawing.scale[0], y: -$0[1] * drawing.scale[1]) }
                guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid scaled greeting point"))
                }
                if index == 0 { path.move(to: points[0]) }
                path.addCurve(to: points[3], control1: points[1], control2: points[2])
                // The stored fourth coordinate is the pen radius.
                radius += curve.p0[3] / CGFloat(curves.count)
            }
            paths.append(path)
            widths.append(radius * drawing.scale[3] * 2)
        }
        let bounds = paths.reduce(CGRect.null) { $0.union($1.boundingRect) }
        guard bounds.width > 0, bounds.height > 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid greeting bounds"))
        }
        let scale = 132 / bounds.height
        let lineWidths = widths.map { $0 * scale }
        guard lineWidths.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid greeting scale"))
        }
        // Include the increased-contrast pen so dots and accent marks cannot clip.
        let padding = max(16, lineWidths.max()! * 0.6)
        let transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: padding - bounds.minX * scale, ty: padding - bounds.minY * scale
        )
        self.init(
            strokes: paths.map { $0.applying(transform) },
            size: CGSize(width: bounds.width * scale + padding * 2, height: 132 + padding * 2),
            lineWidths: lineWidths
        )
    }
}
