import Foundation
import SwiftUI
import ZislaCore

struct FirstLaunchGreetingArtwork {
    let strokes: [Path]
    let size: CGSize
    let lineWidths: [CGFloat]
    let strokeLengths: [CGFloat]
    private let strokeStarts: [CGFloat]
    private let totalLength: CGFloat

    init(strokes: [Path], size: CGSize, lineWidths: [CGFloat]) {
        self.strokes = strokes
        self.size = size
        self.lineWidths = lineWidths
        // A dot needs pen time even though its centerline has no travel.
        let lengths = zip(strokes, lineWidths).map { max(Self.length($0), $1) }
        strokeLengths = lengths
        var start: CGFloat = 0
        strokeStarts = lengths.map { length in
            defer { start += length }
            return start
        }
        totalLength = lengths.reduce(0, +)
    }

    static func artwork(for language: AppLanguage) -> Self? {
        catalog[language]
    }

    private static let catalog = makeCatalog()

    static func makeCatalog(read: (URL) throws -> Data = { try Data(contentsOf: $0) }) -> [AppLanguage: Self] {
        Dictionary(uniqueKeysWithValues: AppLanguage.allCases.compactMap { language in
            guard let artwork = try? systemArtwork(for: language, read: read) else { return nil }
            return (language, artwork)
        })
    }

    func strokeProgress(at progress: CGFloat, index: Int) -> CGFloat {
        let distance = progress * totalLength
        return FirstLaunchGreetingTimeline.smoothProgress(
            (distance - strokeStarts[index]) / strokeLengths[index]
        )
    }

    private func scale(in available: CGSize) -> CGFloat {
        max(0, min((available.width - 16) / size.width, (available.height - 16) / size.height))
    }

    func fittedLineWidth(in available: CGSize, index: Int, baseWidth: CGFloat) -> CGFloat {
        lineWidths[index] * (baseWidth / 5) * min(1, scale(in: available))
    }

    func fittedStrokes(in available: CGSize) -> [Path] {
        let scale = scale(in: available)
        guard scale > 0 else { return [] }
        let transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: (available.width - size.width * scale) / 2,
            ty: (available.height - size.height * scale) / 2
        )
        return strokes.map { $0.applying(transform) }
    }

    // Fixed subdivision keeps timing deterministic and avoids measuring paths on each frame.
    private static func length(_ path: Path) -> CGFloat {
        var current = CGPoint.zero
        var start = CGPoint.zero
        var result: CGFloat = 0
        path.cgPath.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                current = points[0]
                start = current
            case .addLineToPoint:
                result += hypot(points[0].x - current.x, points[0].y - current.y)
                current = points[0]
            case .addCurveToPoint, .addQuadCurveToPoint:
                let origin = current
                let isCubic = element.type == .addCurveToPoint
                let end = points[isCubic ? 2 : 1]
                for step in 1...24 {
                    let t = CGFloat(step) / 24
                    let u = 1 - t
                    let next: CGPoint
                    if isCubic {
                        next = CGPoint(
                            x: u * u * u * origin.x + 3 * u * u * t * points[0].x + 3 * u * t * t * points[1].x + t * t * t * end.x,
                            y: u * u * u * origin.y + 3 * u * u * t * points[0].y + 3 * u * t * t * points[1].y + t * t * t * end.y
                        )
                    } else {
                        next = CGPoint(
                            x: u * u * origin.x + 2 * u * t * points[0].x + t * t * end.x,
                            y: u * u * origin.y + 2 * u * t * points[0].y + t * t * end.y
                        )
                    }
                    result += hypot(next.x - current.x, next.y - current.y)
                    current = next
                }
            case .closeSubpath:
                result += hypot(start.x - current.x, start.y - current.y)
                current = start
            @unknown default: break
            }
        }
        return result
    }
}
