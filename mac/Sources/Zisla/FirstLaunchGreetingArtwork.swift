import SwiftUI
import ZislaCore

struct FirstLaunchGreetingArtwork {
    let strokes: [Path]
    let size: CGSize
    let strokeLengths: [CGFloat]
    private let strokeStarts: [CGFloat]
    private let totalLength: CGFloat

    init(strokes: [Path], size: CGSize) {
        self.strokes = strokes
        self.size = size
        let lengths = strokes.map(Self.length)
        strokeLengths = lengths
        var start: CGFloat = 0
        strokeStarts = lengths.map { length in
            defer { start += length }
            return start
        }
        totalLength = lengths.reduce(0, +)
    }

    static func artwork(for language: AppLanguage) -> Self {
        catalog[language]!
    }

    private static let catalog: [AppLanguage: Self] = Dictionary(
        uniqueKeysWithValues: AppLanguage.allCases.map { ($0, makeArtwork(for: $0)) }
    )

    private static func makeArtwork(for language: AppLanguage) -> Self {
        switch language {
        case .english: word("Hello")
        case .german: word("hallo")
        case .spanish: word("Hola")
        case .french: word("Bonjour")
        case .brazilianPortuguese: word("Olá")
        case .indonesian: word("Halo")
        case .italian: word("Ciao")
        case .dutch: word("Hallo")
        case .turkish: word("Merhaba")
        case .vietnamese: word("Xin chào")
        case .russian: word("Здравствуйте")
        case .simplifiedChinese, .traditionalChinese: chinese
        case .japanese: japanese
        case .korean: korean
        case .thai: thai
        case .arabic: arabic
        }
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

    func fittedLineWidth(in available: CGSize, baseWidth: CGFloat) -> CGFloat {
        baseWidth * min(1, scale(in: available))
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

    private typealias Ink = [[CGPoint]]

    // These are original pen centerlines, not font outlines. Shared tangents soften each turn.
    private static func ink(_ coordinates: [[CGFloat]]) -> Ink {
        coordinates.map { values in
            stride(from: 0, to: values.count, by: 2).map {
                CGPoint(x: values[$0], y: values[$0 + 1])
            }
        }
    }

    private static func path(_ points: [CGPoint]) -> Path {
        let last = points.count - 1
        let isClosed = points[0] == points[last]
        return Path { path in
            path.move(to: points[0])
            for index in 0..<last {
                let a = points[index]
                let b = points[index + 1]
                let previous = points[index > 0 ? index - 1 : (isClosed ? last - 1 : 0)]
                let next = points[index + 2 <= last ? index + 2 : (isClosed ? 1 : last)]
                path.addCurve(
                    to: b,
                    control1: CGPoint(x: a.x + (b.x - previous.x) / 6, y: a.y + (b.y - previous.y) / 6),
                    control2: CGPoint(x: b.x - (next.x - a.x) / 6, y: b.y - (next.y - a.y) / 6)
                )
            }
        }
    }

    private static func drawing(_ coordinates: [[CGFloat]], width: CGFloat, height: CGFloat = 160) -> Self {
        Self(strokes: ink(coordinates).map(path), size: CGSize(width: width, height: height))
    }

    private static func word(_ text: String) -> Self {
        var x: CGFloat = 16
        var strokes: [Path] = []
        for letter in text {
            if letter == " " {
                x += 28
                continue
            }
            let glyph = letterInk(letter)
            for points in glyph.0 {
                let translated = points.map { point in
                    CGPoint(x: x + point.x + (112 - point.y) * 0.055, y: point.y + 12)
                }
                strokes.append(path(translated))
            }
            x += glyph.1
        }
        return Self(strokes: strokes, size: CGSize(width: x + 16, height: 164))
    }

    private static func letterInk(_ letter: Character) -> (Ink, CGFloat) {
        let coordinates: [[CGFloat]]
        let width: CGFloat
        switch letter {
        case "H":
            coordinates = [[8, 28, 6, 68, 3, 110], [57, 26, 52, 67, 49, 110], [6, 72, 29, 69, 53, 67]]
            width = 70
        case "h":
            coordinates = [[8, 110, 12, 64, 15, 27], [10, 83, 26, 64, 42, 70, 42, 100, 49, 110]]
            width = 61
        case "e", "е":
            coordinates = [[6, 88, 29, 83, 40, 72, 27, 64, 9, 75, 6, 98, 23, 111, 44, 102]]
            width = 56
        case "l":
            coordinates = [[15, 28, 11, 58, 7, 91, 9, 108, 21, 109]]
            width = 33
        case "o":
            coordinates = [[35, 68, 19, 64, 6, 80, 7, 102, 23, 111, 39, 98, 42, 79, 35, 68]]
            width = 55
        case "a", "а", "á", "à":
            var lines: [[CGFloat]] = [[39, 70, 23, 64, 8, 76, 6, 99, 19, 110, 34, 99, 40, 72], [40, 68, 37, 91, 40, 109, 49, 107]]
            if letter == "á" { lines.append([24, 49, 38, 34]) }
            if letter == "à" { lines.append([23, 34, 35, 49]) }
            coordinates = lines
            width = 61
        case "B":
            coordinates = [[9, 109, 12, 68, 16, 29], [16, 30, 43, 29, 53, 43, 42, 62, 14, 68, 43, 68, 57, 85, 45, 105, 9, 109]]
            width = 72
        case "n":
            coordinates = [[9, 66, 6, 110], [8, 84, 24, 65, 39, 70, 40, 98, 45, 109]]
            width = 58
        case "j":
            coordinates = [[23, 67, 19, 112, 12, 131, 1, 127], [25, 44, 26, 46]]
            width = 37
        case "u":
            coordinates = [[11, 66, 7, 94, 12, 109, 28, 106, 40, 83, 43, 67], [43, 67, 40, 98, 44, 110, 51, 106]]
            width = 62
        case "r":
            coordinates = [[9, 67, 6, 110], [8, 82, 23, 65, 37, 70]]
            width = 49
        case "O":
            coordinates = [[43, 30, 20, 30, 6, 59, 8, 94, 27, 111, 51, 99, 61, 65, 57, 39, 43, 30]]
            width = 77
        case "C":
            coordinates = [[60, 39, 44, 28, 22, 36, 8, 64, 10, 94, 29, 110, 55, 102]]
            width = 73
        case "i":
            coordinates = [[15, 67, 11, 97, 14, 109, 23, 106], [18, 44, 19, 46]]
            width = 35
        case "M":
            coordinates = [[5, 110, 13, 32, 19, 30, 37, 88, 44, 87, 69, 29, 74, 31, 68, 109]]
            width = 86
        case "b":
            coordinates = [[13, 29, 9, 74, 6, 109], [9, 82, 27, 65, 43, 75, 43, 96, 27, 110, 8, 106]]
            width = 58
        case "X":
            coordinates = [[9, 31, 30, 69, 52, 110], [56, 30, 30, 70, 4, 110]]
            width = 69
        case "c", "с":
            coordinates = [[42, 71, 25, 65, 10, 76, 7, 98, 22, 111, 42, 103]]
            width = 55
        case "З":
            coordinates = [[8, 36, 28, 28, 49, 38, 46, 56, 27, 68, 47, 74, 52, 94, 34, 111, 7, 105]]
            width = 66
        case "д":
            coordinates = [[12, 108, 23, 91, 29, 66, 48, 66, 48, 109], [5, 122, 7, 111, 57, 111, 58, 123]]
            width = 72
        case "р":
            coordinates = [[12, 67, 6, 132], [11, 78, 28, 65, 44, 74, 44, 97, 27, 110, 10, 102]]
            width = 59
        case "в":
            coordinates = [[10, 67, 7, 108], [10, 68, 31, 64, 42, 74, 32, 84, 10, 87, 34, 87, 43, 98, 31, 110, 7, 108]]
            width = 57
        case "т":
            coordinates = [[6, 68, 28, 66, 50, 67], [29, 67, 25, 110]]
            width = 61
        case "у":
            coordinates = [[8, 66, 15, 91, 29, 106], [47, 66, 32, 101, 17, 128, 5, 130]]
            width = 60
        case "й":
            coordinates = [[10, 67, 8, 102, 12, 110, 37, 85, 45, 67, 42, 108], [17, 44, 27, 51, 40, 43]]
            width = 59
        default:
            preconditionFailure("Missing original greeting letter: \(letter)")
        }
        return (ink(coordinates), width)
    }

    private static let chinese = drawing([
        [57, 28, 47, 45, 33, 63, 18, 78],
        [38, 59, 37, 101, 36, 140],
        [98, 28, 87, 49, 75, 67],
        [89, 48, 127, 46, 151, 47, 150, 57, 141, 71],
        [114, 66, 114, 105, 111, 134, 103, 140, 93, 132],
        [81, 90, 72, 106, 62, 120],
        [139, 89, 151, 104, 163, 121],
        [232, 37, 224, 68, 221, 94, 238, 109, 265, 130],
        [269, 52, 260, 83, 244, 110, 215, 139],
        [210, 86, 246, 84, 282, 82],
        [295, 45, 326, 44, 350, 46, 346, 55, 326, 69],
        [324, 66, 328, 83, 328, 111, 326, 135, 310, 143],
        [288, 94, 326, 91, 365, 87],
    ], width: 386, height: 174)

    private static let japanese = drawing([
        // こ
        [24, 49, 47, 46, 68, 49, 62, 57],
        [25, 86, 22, 103, 40, 113, 69, 111],
        // ん
        [127, 34, 114, 64, 98, 103, 100, 111, 119, 85, 133, 86, 134, 108, 146, 113, 161, 98],
        // に
        [188, 37, 181, 74, 181, 111, 188, 103],
        [207, 54, 229, 51, 245, 53],
        [208, 88, 205, 104, 219, 112, 245, 109],
        // ち
        [276, 60, 303, 57, 328, 51],
        [307, 31, 299, 65, 288, 90, 312, 83, 332, 91, 330, 111, 309, 123, 289, 122],
        // は
        [367, 36, 361, 73, 362, 115, 369, 106],
        [387, 64, 411, 62, 435, 58],
        [416, 36, 414, 77, 416, 107, 408, 119, 389, 116, 387, 104, 404, 100, 425, 108, 439, 119],
    ], width: 460)

    private static let korean = drawing([
        // 안: ㅇ, ㅏ, ㄴ
        [37, 34, 20, 37, 15, 52, 24, 66, 42, 65, 49, 49, 43, 36, 37, 34],
        [72, 29, 70, 57, 69, 83], [71, 55, 91, 54],
        [26, 93, 25, 119, 36, 123, 82, 121],
        // 녕: ㄴ, ㅕ, ㅇ
        [119, 33, 118, 70, 127, 75, 150, 73],
        [180, 29, 177, 81], [158, 45, 179, 44], [157, 63, 178, 62],
        [153, 95, 133, 98, 127, 115, 138, 130, 159, 130, 170, 114, 166, 101, 153, 95],
        // 하: ㅎ, ㅏ
        [225, 30, 246, 29], [213, 47, 256, 45],
        [236, 62, 220, 67, 216, 84, 227, 97, 244, 93, 251, 77, 246, 66, 236, 62],
        [279, 32, 275, 78, 274, 123], [277, 74, 299, 73],
        // 세: ㅅ, ㅔ
        [336, 43, 328, 75, 313, 107], [332, 67, 346, 85, 354, 105],
        [375, 34, 371, 122], [352, 75, 373, 74], [393, 32, 390, 123],
        // 요: ㅇ, ㅛ
        [453, 32, 435, 37, 429, 56, 439, 72, 461, 72, 473, 54, 466, 37, 453, 32],
        [440, 94, 439, 119], [465, 93, 464, 119], [418, 121, 451, 120, 486, 119],
    ], width: 510)

    private static let thai = drawing([
        // ส
        [23, 104, 15, 99, 19, 90, 28, 92, 29, 103, 19, 112, 15, 82, 26, 65, 48, 64, 60, 78, 59, 115],
        [46, 66, 59, 56, 68, 43],
        // ว and its following mai han-akat
        [95, 90, 87, 88, 85, 98, 93, 103, 102, 94, 99, 74, 109, 65, 127, 70, 133, 88, 128, 108, 116, 116],
        [90, 45, 99, 49, 117, 47, 130, 37],
        // ส
        [167, 104, 159, 99, 163, 90, 172, 92, 173, 103, 163, 112, 159, 82, 170, 65, 192, 64, 204, 78, 203, 115],
        [190, 66, 203, 56, 212, 43],
        // ด and sara ii
        [246, 104, 238, 99, 242, 90, 251, 92, 252, 102, 242, 111, 235, 91, 240, 72, 257, 64, 278, 69, 286, 88, 284, 115],
        [240, 48, 251, 39, 269, 38, 284, 45, 283, 51, 241, 51],
        [283, 45, 285, 25],
    ], width: 310)

    private static let arabic = drawing([
        // مـر: the ra ends below the baseline and does not join the following ha.
        [355, 88, 345, 76, 334, 77, 329, 88, 339, 96, 350, 89, 331, 100, 314, 100],
        [314, 100, 303, 103, 293, 123, 277, 132, 264, 130],
        // حـبـا: one continuous joining baseline, written from right to left.
        [255, 72, 238, 63, 215, 66, 230, 76, 245, 82, 225, 94, 206, 101,
         188, 102, 169, 101, 148, 101, 130, 99, 120, 89, 119, 62, 118, 35],
        // Ba's dot and fathatan are separate pen lifts, not missing shaping marks.
        [170, 121, 172, 123],
        [165, 66, 178, 61], [164, 75, 177, 70],
    ], width: 385)
}
