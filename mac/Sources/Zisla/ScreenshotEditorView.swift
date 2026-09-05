import AppKit
import Carbon.HIToolbox
import CoreImage
import SwiftUI
import UniformTypeIdentifiers
import Vision
import ZislaKit

enum ScreenshotTool: String, CaseIterable, Identifiable {
    case rectangle
    case ellipse
    case brush
    case arrow
    case number
    case text
    case emoji
    case mosaic

    var id: Self { self }

    var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .brush: "pencil.tip"
        case .arrow: "arrow.up.right"
        case .number: "1.circle"
        case .text: "textformat"
        case .emoji: "face.smiling"
        case .mosaic: "square.grid.3x3"
        }
    }

    var title: String {
        switch self {
        case .rectangle: "矩形"
        case .ellipse: "椭圆"
        case .brush: "画笔"
        case .arrow: "箭头"
        case .number: "标号"
        case .text: "文字"
        case .emoji: "Emoji"
        case .mosaic: "马赛克"
        }
    }
}

enum ScreenshotArrowStyle: String, CaseIterable, Identifiable, Equatable {
    case straight
    case tapered

    var id: Self { self }

    var symbol: String {
        switch self {
        case .straight: "arrow.up.right"
        case .tapered: "arrowshape.up.right.fill"
        }
    }

    var title: String {
        switch self {
        case .straight: "直线"
        case .tapered: "渐粗"
        }
    }
}

enum ScreenshotArrowGeometry {
    static func headPoints(
        from start: CGPoint,
        to end: CGPoint,
        lineWidth: CGFloat,
        minimumLength: CGFloat
    ) -> (tip: CGPoint, left: CGPoint, right: CGPoint) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(minimumLength, lineWidth * 3)
        return (
            tip: end,
            left: CGPoint(
                x: end.x - cos(angle - .pi / 6) * headLength,
                y: end.y - sin(angle - .pi / 6) * headLength
            ),
            right: CGPoint(
                x: end.x - cos(angle + .pi / 6) * headLength,
                y: end.y - sin(angle + .pi / 6) * headLength
            )
        )
    }

    static func taperedShaftPoints(
        from start: CGPoint,
        to end: CGPoint,
        lineWidth: CGFloat
    ) -> [CGPoint]? {
        let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let length = hypot(delta.x, delta.y)
        guard length > 0 else { return nil }

        let unit = CGPoint(x: delta.x / length, y: delta.y / length)
        let normal = CGPoint(x: -unit.y, y: unit.x)
        let startWidth = max(0.8, lineWidth * 0.3)
        let endWidth = max(1, lineWidth)
        let startOffset = CGPoint(x: normal.x * startWidth / 2, y: normal.y * startWidth / 2)
        let endOffset = CGPoint(x: normal.x * endWidth / 2, y: normal.y * endWidth / 2)

        return [
            CGPoint(x: start.x + startOffset.x, y: start.y + startOffset.y),
            CGPoint(x: end.x + endOffset.x, y: end.y + endOffset.y),
            CGPoint(x: end.x - endOffset.x, y: end.y - endOffset.y),
            CGPoint(x: start.x - startOffset.x, y: start.y - startOffset.y),
        ]
    }
}

enum ScreenshotLongCaptureDirection: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: Self { self }

    var symbol: String {
        switch self {
        case .vertical: "arrow.up.and.down"
        case .horizontal: "arrow.left.and.right"
        }
    }

    var title: String {
        switch self {
        case .vertical: "上下"
        case .horizontal: "左右"
        }
    }
}

enum ScreenshotLongCapturePlacement: Equatable {
    case append
    case prepend
}

struct ScreenshotLongCaptureMatch: Equatable {
    let placement: ScreenshotLongCapturePlacement
    let overlapFraction: CGFloat
}

enum ScreenshotLongCaptureMatcher {
    private static let maximumSampleLength = 360
    private static let maximumCrossLength = 160

    static func isVisuallyUnchanged(previous: CGImage, next: CGImage) -> Bool {
        guard previous.width == next.width, previous.height == next.height else { return false }
        let sampleSize = CGSize(
            width: CGFloat(min(240, previous.width)),
            height: CGFloat(min(240, previous.height))
        )
        guard let previousPixels = grayscalePixels(in: previous, size: sampleSize),
              let nextPixels = grayscalePixels(in: next, size: sampleSize),
              previousPixels.count == nextPixels.count,
              !previousPixels.isEmpty
        else { return false }

        var totalDifference = 0
        var significantDifferenceCount = 0
        for index in previousPixels.indices {
            let difference = abs(Int(previousPixels[index]) - Int(nextPixels[index]))
            totalDifference += difference
            if difference > 4 { significantDifferenceCount += 1 }
        }
        return Double(totalDifference) / Double(previousPixels.count) <= 0.75
            && significantDifferenceCount <= max(8, previousPixels.count / 200)
    }

    static func match(
        previous: CGImage,
        next: CGImage,
        direction: ScreenshotLongCaptureDirection
    ) -> ScreenshotLongCaptureMatch? {
        let sampleSize = switch direction {
        case .vertical:
            CGSize(
                width: CGFloat(min(maximumCrossLength, min(previous.width, next.width))),
                height: CGFloat(min(maximumSampleLength, min(previous.height, next.height)))
            )
        case .horizontal:
            CGSize(
                width: CGFloat(min(maximumSampleLength, min(previous.width, next.width))),
                height: CGFloat(min(maximumCrossLength, min(previous.height, next.height)))
            )
        }
        guard sampleSize.width >= 16, sampleSize.height >= 16,
              let previousPixels = grayscalePixels(in: previous, size: sampleSize),
              let nextPixels = grayscalePixels(in: next, size: sampleSize)
        else { return nil }

        let width = Int(sampleSize.width)
        let height = Int(sampleSize.height)
        let axisLength = direction == .vertical ? height : width
        let minimumOverlap = max(12, Int(CGFloat(axisLength) * 0.12))
        let maximumOverlap = axisLength - 4
        guard minimumOverlap <= maximumOverlap else { return nil }

        var best: (match: ScreenshotLongCaptureMatch, score: Double)?
        for placement in [ScreenshotLongCapturePlacement.append, .prepend] {
            for overlap in minimumOverlap...maximumOverlap {
                guard let score = score(
                    previous: previousPixels,
                    next: nextPixels,
                    width: width,
                    height: height,
                    direction: direction,
                    placement: placement,
                    overlap: overlap
                ) else { continue }
                let match = ScreenshotLongCaptureMatch(
                    placement: placement,
                    overlapFraction: CGFloat(overlap) / CGFloat(axisLength)
                )
                if best == nil
                    || score < best!.score - 0.5
                    || (abs(score - best!.score) <= 0.5
                        && match.overlapFraction > best!.match.overlapFraction) {
                    best = (match, score)
                }
            }
        }
        guard let best, best.score <= 18 else { return nil }
        return best.match
    }

    private static func grayscalePixels(in image: CGImage, size: CGSize) -> [UInt8]? {
        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private static func score(
        previous: [UInt8],
        next: [UInt8],
        width: Int,
        height: Int,
        direction: ScreenshotLongCaptureDirection,
        placement: ScreenshotLongCapturePlacement,
        overlap: Int
    ) -> Double? {
        let crossLength = direction == .vertical ? width : height
        let crossInset = max(1, crossLength / 10)
        var difference = 0
        var detailCount = 0
        var count = 0

        for axis in 0..<overlap {
            for cross in crossInset..<(crossLength - crossInset) {
                let previousAxis: Int
                let nextAxis: Int
                switch placement {
                case .append:
                    previousAxis = (direction == .vertical ? height : width) - overlap + axis
                    nextAxis = axis
                case .prepend:
                    previousAxis = axis
                    nextAxis = (direction == .vertical ? height : width) - overlap + axis
                }
                let previousIndex = direction == .vertical
                    ? previousAxis * width + cross
                    : cross * width + previousAxis
                let nextIndex = direction == .vertical
                    ? nextAxis * width + cross
                    : cross * width + nextAxis
                let previousValue = Int(previous[previousIndex])
                let nextValue = Int(next[nextIndex])
                difference += abs(previousValue - nextValue)
                if axis > 0 {
                    let previousNeighbor = direction == .vertical
                        ? previousIndex - width
                        : previousIndex - 1
                    let nextNeighbor = direction == .vertical
                        ? nextIndex - width
                        : nextIndex - 1
                    if abs(previousValue - Int(previous[previousNeighbor])) > 0
                        || abs(nextValue - Int(next[nextNeighbor])) > 0 {
                        detailCount += 1
                    }
                }
                count += 1
            }
        }
        guard count > 0, detailCount >= max(6, count / 200) else { return nil }
        return Double(difference) / Double(count)
    }
}

enum ScreenshotObscureShape: String, CaseIterable, Identifiable {
    case rectangle
    case brush

    var id: Self { self }

    var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .brush: "scribble"
        }
    }

    var title: String {
        switch self {
        case .rectangle: "矩形"
        case .brush: "画笔"
        }
    }
}

enum ScreenshotObscureEffect: String, CaseIterable, Identifiable {
    case blur
    case pixelate

    var id: Self { self }

    var title: String {
        switch self {
        case .blur: "模糊"
        case .pixelate: "马赛克"
        }
    }

    var strengthTitle: String {
        switch self {
        case .blur: "模糊度"
        case .pixelate: "格子"
        }
    }
}

struct ScreenshotRGBA: Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat = 1

    static let accent = ScreenshotRGBA(red: 1, green: 0.25, blue: 0.2)
    static let black = ScreenshotRGBA(red: 0, green: 0, blue: 0)
    static let white = ScreenshotRGBA(red: 1, green: 1, blue: 1)

    static func contrastingTextColor(for background: ScreenshotRGBA) -> ScreenshotRGBA {
        let linearized = [background.red, background.green, background.blue].map { component in
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = linearized[0] * 0.2126 + linearized[1] * 0.7152 + linearized[2] * 0.0722
        return luminance > 0.179 ? .black : .white
    }

    var nsColor: NSColor {
        NSColor(
            calibratedRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    init(_ color: NSColor) {
        let resolved = color.usingColorSpace(.deviceRGB) ?? color
        red = resolved.redComponent
        green = resolved.greenComponent
        blue = resolved.blueComponent
        alpha = resolved.alphaComponent
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

enum ScreenshotTextRendering {
    static let defaultFontSize: CGFloat = 14
    static let minimumFontSize: CGFloat = 3
    private static let backgroundStrokeWidth: CGFloat = -60

    static func font(for fontSize: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: max(minimumFontSize, fontSize), weight: .semibold)
    }

    static func backgroundAttributedString(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: font(for: fontSize),
                .foregroundColor: NSColor.white,
                .strokeColor: NSColor.white,
                .strokeWidth: backgroundStrokeWidth,
            ]
        )
    }

    static func foregroundAttributedString(
        _ text: String,
        color: ScreenshotRGBA,
        fontSize: CGFloat
    ) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: font(for: fontSize),
                .foregroundColor: color.nsColor,
            ]
        )
    }

    static func draw(
        _ text: String,
        color: ScreenshotRGBA,
        fontSize: CGFloat,
        in rect: NSRect
    ) {
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.setLineJoin(.round)
        backgroundAttributedString(text, fontSize: fontSize).draw(in: rect)
        context?.restoreGState()
        foregroundAttributedString(text, color: color, fontSize: fontSize).draw(in: rect)
    }

    static func size(
        of text: String,
        color: ScreenshotRGBA,
        fontSize: CGFloat
    ) -> CGSize {
        foregroundAttributedString(text, color: color, fontSize: fontSize).size()
    }

    static func inset(for fontSize: CGFloat) -> CGFloat {
        max(1, abs(backgroundStrokeWidth) * max(minimumFontSize, fontSize) / 100)
    }
}

enum ScreenshotInlineTextLayout {
    static let initialWidth: CGFloat = 80
    static let placeholderOpacity: CGFloat = 0.6

    static func lineHeight(for fontSize: CGFloat) -> CGFloat {
        let font = ScreenshotTextRendering.font(for: fontSize)
        return ceil(font.ascender - font.descender + font.leading)
    }

    static func width(from startX: CGFloat, to rightEdge: CGFloat) -> CGFloat {
        max(rightEdge - min(max(startX, 0), rightEdge), 1)
    }

    static func width(
        for text: String,
        fontSize: CGFloat,
        from startX: CGFloat,
        to rightEdge: CGFloat
    ) -> CGFloat {
        let availableWidth = width(from: startX, to: rightEdge)
        let contentWidth = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { ScreenshotTextRendering.size(of: String($0), color: .black, fontSize: fontSize).width }
            .max() ?? 0
        return min(max(initialWidth, ceil(contentWidth)), availableWidth)
    }

    static func contentHeight(for text: String, fontSize: CGFloat, width: CGFloat) -> CGFloat {
        let font = ScreenshotTextRendering.font(for: fontSize)
        let storage = NSTextStorage(
            string: text.isEmpty ? " " : text,
            attributes: [.font: font]
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(
            width: max(width, 1),
            height: .greatestFiniteMagnitude
        ))
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        return max(lineHeight(for: fontSize), ceil(layoutManager.usedRect(for: textContainer).height))
    }

}

struct ScreenshotAnnotation: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case rectangle
        case ellipse
        case brush
        case arrow
        case number
        case text
        case emoji
        case mosaic
    }

    let id: UUID
    var kind: Kind
    var points: [CGPoint] = []
    var rect: CGRect = .zero
    var text = ""
    var color = ScreenshotRGBA.accent
    var lineWidth: CGFloat = 3
    var arrowStyle: ScreenshotArrowStyle = .straight
    var fontSize: CGFloat = ScreenshotTextRendering.defaultFontSize
    var number = 1
    var obscureShape: ScreenshotObscureShape = .rectangle
    var obscureEffect: ScreenshotObscureEffect = .blur
    var obscurePixelateStrength: CGFloat = 3
    /// 0 leaves a mosaic as plain blocks; a blur region always gets a real value written through
    /// `obscureStrength`, so the default only ever applies to pixelate.
    var obscureBlurStrength: CGFloat = 0
    var rotation: CGFloat = 0

    /// The strength each effect drives itself with: block size for pixelate, radius for blur. A
    /// mosaic keeps its extra blur in `obscureBlurStrength`, so the two knobs move independently.
    var obscureStrength: CGFloat {
        get {
            switch obscureEffect {
            case .pixelate: obscurePixelateStrength
            case .blur: obscureBlurStrength
            }
        }
        set {
            switch obscureEffect {
            case .pixelate: obscurePixelateStrength = newValue
            case .blur: obscureBlurStrength = newValue
            }
        }
    }

    init(
        id: UUID = UUID(),
        kind: Kind,
        points: [CGPoint] = [],
        rect: CGRect = .zero,
        text: String = "",
        color: ScreenshotRGBA = .accent,
        lineWidth: CGFloat = 3,
        arrowStyle: ScreenshotArrowStyle = .straight,
        fontSize: CGFloat = ScreenshotTextRendering.defaultFontSize,
        number: Int = 1,
        obscureShape: ScreenshotObscureShape = .rectangle,
        obscureEffect: ScreenshotObscureEffect = .blur,
        obscureStrength: CGFloat = 3,
        obscureBlurStrength: CGFloat? = nil,
        rotation: CGFloat = 0
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.rect = rect
        self.text = text
        self.color = color
        self.lineWidth = lineWidth
        self.arrowStyle = arrowStyle
        self.fontSize = fontSize
        self.number = number
        self.obscureShape = obscureShape
        self.obscureEffect = obscureEffect
        self.rotation = rotation
        self.obscureStrength = obscureStrength
        if let obscureBlurStrength { self.obscureBlurStrength = obscureBlurStrength }
    }
}

enum ScreenshotAnnotationTransform {
    static func translated(
        _ annotation: ScreenshotAnnotation,
        by translation: CGSize,
        textRightEdge: CGFloat? = nil
    ) -> ScreenshotAnnotation {
        var result = annotation
        result.points = annotation.points.map { point in
            CGPoint(x: point.x + translation.width, y: point.y + translation.height)
        }
        if annotation.rect != .zero {
            result.rect = annotation.rect.offsetBy(dx: translation.width, dy: translation.height)
        }
        if annotation.kind == .text,
           let textRightEdge,
           !result.text.isEmpty,
           ScreenshotAnnotationGeometry.bounds(for: result) != .zero {
            let rect = ScreenshotAnnotationGeometry.bounds(for: result).standardized
            let availableWidth = ScreenshotInlineTextLayout.width(
                from: rect.minX,
                to: textRightEdge
            )
            let contentWidth = ScreenshotInlineTextLayout.width(
                for: result.text,
                fontSize: result.fontSize,
                from: rect.minX,
                to: textRightEdge
            )
            let width = min(availableWidth, max(rect.width, contentWidth))
            result.rect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: width,
                height: ScreenshotInlineTextLayout.contentHeight(
                    for: result.text,
                    fontSize: result.fontSize,
                    width: width
                )
            )
            result.points = [result.rect.center]
        }
        return result
    }

    static func scaled(_ annotation: ScreenshotAnnotation, by scale: CGFloat) -> ScreenshotAnnotation {
        let factor = max(0.1, scale)
        var result = annotation
        if annotation.rect != .zero {
            let rect = annotation.rect.standardized
            let size = CGSize(width: rect.width * factor, height: rect.height * factor)
            result.rect = CGRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            if annotation.kind == .text || annotation.kind == .emoji {
                result.fontSize = max(3, annotation.fontSize * factor)
            } else if annotation.kind == .number {
                result.lineWidth = max(1, annotation.lineWidth * factor)
            }
        } else if annotation.kind == .text || annotation.kind == .emoji {
            result.fontSize = max(3, annotation.fontSize * factor)
        } else if annotation.kind == .number {
            result.lineWidth = max(1, annotation.lineWidth * factor)
        } else {
            let center = annotation.points.reduce(CGPoint.zero) { partial, point in
                CGPoint(x: partial.x + point.x, y: partial.y + point.y)
            }
            let count = CGFloat(max(annotation.points.count, 1))
            let midpoint = CGPoint(x: center.x / count, y: center.y / count)
            result.points = annotation.points.map { point in
                CGPoint(
                    x: midpoint.x + (point.x - midpoint.x) * factor,
                    y: midpoint.y + (point.y - midpoint.y) * factor
                )
            }
        }
        return result
    }

    static func rotated(_ annotation: ScreenshotAnnotation, by angle: CGFloat) -> ScreenshotAnnotation {
        var result = annotation
        result.rotation += angle
        return result
    }
}

enum ScreenshotAnnotationEditHandle: Equatable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
    case rotation
}

enum ScreenshotAnnotationGeometry {
    static let minimumSize: CGFloat = 12
    static let defaultEmojiDiameter: CGFloat = 28
    static let handleRadius: CGFloat = 14
    static let rotationOffset: CGFloat = 24

    static func numberDiameter(for lineWidth: CGFloat) -> CGFloat {
        max(18, lineWidth * 7)
    }

    static func emojiDiameter(for fontSize: CGFloat) -> CGFloat {
        max(defaultEmojiDiameter, fontSize)
    }

    static func bounds(for annotation: ScreenshotAnnotation) -> CGRect {
        if annotation.rect != .zero { return annotation.rect.standardized }
        guard let point = annotation.points.first else { return .zero }
        if usesPathGeometry(annotation) {
            return pathBounds(
                for: pathGeometryPoints(for: annotation),
                inset: max(1, annotation.lineWidth / 2),
                minimumSize: minimumSize
            )
        }
        if annotation.kind == .emoji {
            let diameter = emojiDiameter(for: annotation.fontSize)
            return CGRect(
                x: point.x - diameter / 2,
                y: point.y - diameter / 2,
                width: diameter,
                height: diameter
            )
        }
        if annotation.kind == .text {
            let size = ScreenshotTextRendering.size(
                of: annotation.text,
                color: annotation.color,
                fontSize: annotation.fontSize
            )
            let inset = ScreenshotTextRendering.inset(for: annotation.fontSize)
            return CGRect(
                x: point.x - max(size.width + inset * 2, minimumSize) / 2,
                y: point.y - max(size.height + inset * 2, minimumSize) / 2,
                width: max(size.width + inset * 2, minimumSize),
                height: max(size.height + inset * 2, minimumSize)
            )
        }
        if annotation.kind == .number {
            let diameter = numberDiameter(for: annotation.lineWidth)
            return CGRect(
                x: point.x - diameter / 2,
                y: point.y - diameter / 2,
                width: diameter,
                height: diameter
            )
        }
        return CGRect(x: point.x - minimumSize / 2, y: point.y - minimumSize / 2, width: minimumSize, height: minimumSize)
    }

    private static func usesPathGeometry(_ annotation: ScreenshotAnnotation) -> Bool {
        annotation.kind == .brush
            || annotation.kind == .arrow
            || (annotation.kind == .mosaic && annotation.obscureShape == .brush)
    }

    private static func pathGeometryPoints(for annotation: ScreenshotAnnotation) -> [CGPoint] {
        guard annotation.kind == .arrow,
              let start = annotation.points.first,
              let end = annotation.points.last
        else { return annotation.points }

        let headPoints = ScreenshotArrowGeometry.headPoints(
            from: start,
            to: end,
            lineWidth: annotation.lineWidth,
            minimumLength: 10
        )
        return [start, end, headPoints.left, headPoints.right]
    }

    private static func pathHitTestPoints(for annotation: ScreenshotAnnotation) -> [CGPoint] {
        guard annotation.kind == .arrow,
              let start = annotation.points.first,
              let end = annotation.points.last
        else { return annotation.points }

        let headPoints = ScreenshotArrowGeometry.headPoints(
            from: start,
            to: end,
            lineWidth: annotation.lineWidth,
            minimumLength: 10
        )
        return [start, end, headPoints.left, end, headPoints.right]
    }

    private static func pathBounds(
        for points: [CGPoint],
        inset: CGFloat,
        minimumSize: CGFloat
    ) -> CGRect {
        guard let first = points.first else { return .zero }
        let minX = (points.map(\.x).min() ?? first.x) - inset
        let maxX = (points.map(\.x).max() ?? first.x) + inset
        let minY = (points.map(\.y).min() ?? first.y) - inset
        let maxY = (points.map(\.y).max() ?? first.y) + inset
        let width = max(maxX - minX, minimumSize)
        let height = max(maxY - minY, minimumSize)
        return CGRect(
            x: (minX + maxX - width) / 2,
            y: (minY + maxY - height) / 2,
            width: width,
            height: height
        )
    }

    static func localPoint(_ point: CGPoint, in rect: CGRect, rotation: CGFloat) -> CGPoint {
        let center = rect.center
        let translated = CGPoint(x: point.x - center.x, y: point.y - center.y)
        let cosine = cos(-rotation)
        let sine = sin(-rotation)
        return CGPoint(
            x: center.x + translated.x * cosine - translated.y * sine,
            y: center.y + translated.x * sine + translated.y * cosine
        )
    }

    static func rotatedPoint(_ point: CGPoint, around center: CGPoint, by rotation: CGFloat) -> CGPoint {
        let translated = CGPoint(x: point.x - center.x, y: point.y - center.y)
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return CGPoint(
            x: center.x + translated.x * cosine - translated.y * sine,
            y: center.y + translated.x * sine + translated.y * cosine
        )
    }

    static func contains(_ point: CGPoint, in annotation: ScreenshotAnnotation) -> Bool {
        if usesPathGeometry(annotation) {
            let hitPoint = annotation.rotation == 0
                ? point
                : localPoint(point, in: bounds(for: annotation), rotation: annotation.rotation)
            return pathContains(
                hitPoint,
                points: pathHitTestPoints(for: annotation),
                hitRadius: max(handleRadius, annotation.lineWidth / 2 + 4)
            )
        }
        let rect = bounds(for: annotation).insetBy(dx: -handleRadius, dy: -handleRadius)
        return rect.contains(localPoint(point, in: bounds(for: annotation), rotation: annotation.rotation))
    }

    private static func pathContains(
        _ point: CGPoint,
        points: [CGPoint],
        hitRadius: CGFloat
    ) -> Bool {
        guard let first = points.first else { return false }
        guard points.count > 1 else { return point.distance(to: first) <= hitRadius }
        return zip(points, points.dropFirst()).contains { start, end in
            distance(from: point, toSegmentFrom: start, to: end) <= hitRadius
        }
    }

    private static func distance(
        from point: CGPoint,
        toSegmentFrom start: CGPoint,
        to end: CGPoint
    ) -> CGFloat {
        let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let lengthSquared = delta.x * delta.x + delta.y * delta.y
        guard lengthSquared > 0 else { return point.distance(to: start) }
        let projection = min(
            max(
                ((point.x - start.x) * delta.x + (point.y - start.y) * delta.y) / lengthSquared,
                0
            ),
            1
        )
        let nearest = CGPoint(
            x: start.x + delta.x * projection,
            y: start.y + delta.y * projection
        )
        return point.distance(to: nearest)
    }

    static func handle(at point: CGPoint, in annotation: ScreenshotAnnotation) -> ScreenshotAnnotationEditHandle? {
        let rect = bounds(for: annotation)
        let local = localPoint(point, in: rect, rotation: annotation.rotation)
        let hitRadius = handleHitRadius(for: annotation)
        var candidates: [(ScreenshotAnnotationEditHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
        ]
        if annotation.kind == .rectangle {
            candidates += [
                (.top, CGPoint(x: rect.midX, y: rect.minY)),
                (.right, CGPoint(x: rect.maxX, y: rect.midY)),
                (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
                (.left, CGPoint(x: rect.minX, y: rect.midY)),
            ]
        }
        if annotation.kind == .rectangle || annotation.kind == .text || annotation.kind == .arrow {
            candidates.append((.rotation, CGPoint(x: rect.midX, y: rect.minY - rotationOffset)))
        }
        return candidates.first { local.distance(to: $0.1) <= hitRadius }?.0
    }

    static func handleHitRadius(for annotation: ScreenshotAnnotation) -> CGFloat {
        let rect = bounds(for: annotation)
        let radius = min(handleRadius, max(5, min(rect.width, rect.height) * 0.25))
        return annotation.kind == .number ? radius * 0.9 : radius
    }

    static func shortestAngleDelta(from start: CGFloat, to current: CGFloat) -> CGFloat {
        let fullRotation = 2 * CGFloat.pi
        var delta = (current - start).truncatingRemainder(dividingBy: fullRotation)
        if delta > CGFloat.pi {
            delta -= fullRotation
        } else if delta < -CGFloat.pi {
            delta += fullRotation
        }
        return delta
    }

    static func transform(
        _ annotation: ScreenshotAnnotation,
        handle: ScreenshotAnnotationEditHandle?,
        from start: CGPoint,
        to current: CGPoint,
        textRightEdge: CGFloat? = nil
    ) -> ScreenshotAnnotation {
        let rect = bounds(for: annotation)
        guard let handle else {
            return ScreenshotAnnotationTransform.translated(
                annotation,
                by: CGSize(width: current.x - start.x, height: current.y - start.y),
                textRightEdge: annotation.kind == .text ? textRightEdge : nil
            )
        }
        if handle == .rotation && annotation.kind != .number {
            let center = rect.center
            let startAngle = atan2(start.y - center.y, start.x - center.x)
            let currentAngle = atan2(current.y - center.y, current.x - center.x)
            return ScreenshotAnnotationTransform.rotated(
                annotation,
                by: shortestAngleDelta(from: startAngle, to: currentAngle)
            )
        }

        let localCurrent = localPoint(current, in: rect, rotation: annotation.rotation)
        if annotation.kind == .number {
            let oppositeCorner: CGPoint
            switch handle {
            case .topLeft:
                oppositeCorner = CGPoint(x: rect.maxX, y: rect.maxY)
            case .topRight:
                oppositeCorner = CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomRight:
                oppositeCorner = CGPoint(x: rect.minX, y: rect.minY)
            case .bottomLeft:
                oppositeCorner = CGPoint(x: rect.maxX, y: rect.minY)
            case .top, .right, .bottom, .left, .rotation:
                return annotation
            }
            let diameter = max(
                numberDiameter(for: 1),
                abs(localCurrent.x - oppositeCorner.x),
                abs(localCurrent.y - oppositeCorner.y)
            )
            let resizedRect: CGRect
            switch handle {
            case .topLeft:
                resizedRect = CGRect(
                    x: oppositeCorner.x - diameter,
                    y: oppositeCorner.y - diameter,
                    width: diameter,
                    height: diameter
                )
            case .topRight:
                resizedRect = CGRect(
                    x: oppositeCorner.x,
                    y: oppositeCorner.y - diameter,
                    width: diameter,
                    height: diameter
                )
            case .bottomRight:
                resizedRect = CGRect(origin: oppositeCorner, size: CGSize(width: diameter, height: diameter))
            case .bottomLeft:
                resizedRect = CGRect(
                    x: oppositeCorner.x - diameter,
                    y: oppositeCorner.y,
                    width: diameter,
                    height: diameter
                )
            case .top, .right, .bottom, .left, .rotation:
                return annotation
            }
            var result = annotation
            result.lineWidth = diameter / 7
            result.points = [resizedRect.center]
            return result
        }

        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY
        switch handle {
        case .topLeft:
            minX = min(localCurrent.x, maxX - minimumSize)
            minY = min(localCurrent.y, maxY - minimumSize)
        case .top:
            minY = min(localCurrent.y, maxY - minimumSize)
        case .topRight:
            maxX = max(localCurrent.x, minX + minimumSize)
            minY = min(localCurrent.y, maxY - minimumSize)
        case .right:
            maxX = max(localCurrent.x, minX + minimumSize)
        case .bottomRight:
            maxX = max(localCurrent.x, minX + minimumSize)
            maxY = max(localCurrent.y, minY + minimumSize)
        case .bottom:
            maxY = max(localCurrent.y, minY + minimumSize)
        case .bottomLeft:
            minX = min(localCurrent.x, maxX - minimumSize)
            maxY = max(localCurrent.y, minY + minimumSize)
        case .left:
            minX = min(localCurrent.x, maxX - minimumSize)
        case .rotation:
            break
        }
        let oppositeCorner: CGPoint
        switch handle {
        case .topLeft:
            oppositeCorner = CGPoint(x: rect.maxX, y: rect.maxY)
        case .top:
            oppositeCorner = CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight:
            oppositeCorner = CGPoint(x: rect.minX, y: rect.maxY)
        case .right:
            oppositeCorner = CGPoint(x: rect.minX, y: rect.midY)
        case .bottomRight:
            oppositeCorner = CGPoint(x: rect.minX, y: rect.minY)
        case .bottom:
            oppositeCorner = CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft:
            oppositeCorner = CGPoint(x: rect.maxX, y: rect.minY)
        case .left:
            oppositeCorner = CGPoint(x: rect.maxX, y: rect.midY)
        case .rotation:
            return annotation
        }
        var resizedRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if annotation.rotation != 0 {
            let fixedCorner = rotatedPoint(oppositeCorner, around: rect.center, by: annotation.rotation)
            let resizedCorner = rotatedPoint(oppositeCorner, around: resizedRect.center, by: annotation.rotation)
            resizedRect = resizedRect.offsetBy(
                dx: fixedCorner.x - resizedCorner.x,
                dy: fixedCorner.y - resizedCorner.y
            )
        }
        if usesPathGeometry(annotation) {
            guard annotation.rotation == 0 else {
                let widthScale = rect.width > 0 ? resizedRect.width / rect.width : 1
                let heightScale = rect.height > 0 ? resizedRect.height / rect.height : 1
                var result = annotation
                result.points = annotation.points.map { point in
                    let local = localPoint(point, in: rect, rotation: annotation.rotation)
                    let resizedLocal = CGPoint(
                        x: resizedRect.minX + (local.x - rect.minX) * widthScale,
                        y: resizedRect.minY + (local.y - rect.minY) * heightScale
                    )
                    return rotatedPoint(resizedLocal, around: resizedRect.center, by: annotation.rotation)
                }
                result.rect = .zero
                return result
            }
            let sourceBounds = pathBounds(
                for: pathGeometryPoints(for: annotation),
                inset: 0,
                minimumSize: 0
            )
            let leftInset = sourceBounds.minX - rect.minX
            let rightInset = rect.maxX - sourceBounds.maxX
            let topInset = sourceBounds.minY - rect.minY
            let bottomInset = rect.maxY - sourceBounds.maxY
            let targetMinX = resizedRect.minX + leftInset
            let targetMinY = resizedRect.minY + topInset
            let targetWidth = max(0, resizedRect.width - leftInset - rightInset)
            let targetHeight = max(0, resizedRect.height - topInset - bottomInset)
            let widthScale = sourceBounds.width > 0 ? targetWidth / sourceBounds.width : 1
            let heightScale = sourceBounds.height > 0 ? targetHeight / sourceBounds.height : 1
            var result = annotation
            result.points = annotation.points.map { point in
                CGPoint(
                    x: targetMinX + (point.x - sourceBounds.minX) * widthScale,
                    y: targetMinY + (point.y - sourceBounds.minY) * heightScale
                )
            }
            result.rect = .zero
            return result
        }
        var result = annotation
        result.rect = resizedRect
        if annotation.kind == .text || annotation.kind == .emoji {
            result.points = [result.rect.origin]
        }
        return result
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

@MainActor
final class ScreenshotEditorModel: ObservableObject {
    private struct Snapshot {
        let image: NSImage
        let annotations: [ScreenshotAnnotation]
        let nextNumber: Int
    }

    @Published var image: NSImage
    @Published private(set) var mosaicPreviewImage: NSImage
    @Published private(set) var annotations: [ScreenshotAnnotation] = []
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var tool: ScreenshotTool = .rectangle
    @Published var color = ScreenshotRGBA.accent
    @Published var lineWidth: CGFloat = 3
    @Published var arrowStyle: ScreenshotArrowStyle = .straight
    @Published var fontSize: CGFloat = ScreenshotTextRendering.defaultFontSize
    @Published var selectedEmoji = "⭐️"
    @Published var obscureShape: ScreenshotObscureShape = .rectangle
    @Published var obscureEffect: ScreenshotObscureEffect = .blur
    @Published var pixelateStrength: CGFloat = 3
    @Published var blurStrength: CGFloat = 3
    /// Blur stacked on top of the mosaic blocks; 0 by default so a new mosaic stays plain blocks.
    @Published var mosaicBlurStrength: CGFloat = 0
    @Published var statusMessage: String?
    @Published var isPinned = false
    @Published private(set) var isLongCapturePreviewing = false
    @Published private(set) var hasLongCaptureResult = false
    @Published var longCaptureDirection = ScreenshotLongCaptureDirection.vertical

    /// Blur amount: the blur effect's own strength, or the extra blur a mosaic stacks on its blocks.
    var obscureBlurStrength: CGFloat {
        switch obscureEffect {
        case .pixelate: mosaicBlurStrength
        case .blur: blurStrength
        }
    }

    /// Strength of the effect that is currently selected; each effect keeps its own slider value.
    var obscureStrength: CGFloat {
        get {
            switch obscureEffect {
            case .pixelate: pixelateStrength
            case .blur: blurStrength
            }
        }
        set {
            switch obscureEffect {
            case .pixelate: pixelateStrength = newValue
            case .blur: blurStrength = newValue
            }
        }
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var nextNumber = 1
    private var lastLongCaptureFrame: NSImage?

    struct PendingTextDraft: Equatable {
        let id: UUID
        var text: String
        let isNew: Bool
    }

    private(set) var pendingTextDraft: PendingTextDraft?

    /// Geometry the canvas has drawn but not yet handed over, so an interrupted mouse-up cannot
    /// silently drop a shape, number, stroke, or emoji when the image is exported.
    private(set) var pendingAnnotationDraft: ScreenshotAnnotation?

    init(image: NSImage) {
        self.image = image
        mosaicPreviewImage = image
    }

    func add(_ annotation: ScreenshotAnnotation, saveUndo: Bool = true) {
        if saveUndo { saveUndoPoint() }
        let existingIndex = annotations.firstIndex(where: { $0.id == annotation.id })
        let changesMosaic = annotation.kind == .mosaic
            || existingIndex.map { annotations[$0].kind == .mosaic } == true
        if let existingIndex {
            annotations[existingIndex] = annotation
        } else {
            annotations.append(annotation)
        }
        if annotation.kind == .number { nextNumber = max(nextNumber, annotation.number + 1) }
        if changesMosaic { refreshMosaicPreview() }
    }

    func update(_ annotation: ScreenshotAnnotation, saveUndo: Bool = true) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else {
            if saveUndo { add(annotation) }
            return
        }
        let changesMosaic = annotation.kind == .mosaic || annotations[index].kind == .mosaic
        if saveUndo { saveUndoPoint() }
        annotations[index] = annotation
        if changesMosaic { refreshMosaicPreview() }
    }

    func applySelectedStyle(
        to annotationID: UUID,
        color: ScreenshotRGBA? = nil,
        lineWidth: CGFloat? = nil,
        arrowStyle: ScreenshotArrowStyle? = nil,
        fontSize: CGFloat? = nil,
        obscureStrength: CGFloat? = nil,
        obscureBlurStrength: CGFloat? = nil
    ) {
        guard let annotation = annotations.first(where: { $0.id == annotationID }) else { return }
        var updated = annotation
        var changed = false
        if let color, annotation.color != color {
            updated.color = color
            changed = true
        }
        switch annotation.kind {
        case .rectangle, .ellipse:
            if let lineWidth, annotation.lineWidth != lineWidth {
                updated.lineWidth = lineWidth
                changed = true
            }
        case .arrow:
            if let arrowStyle, annotation.arrowStyle != arrowStyle {
                updated.arrowStyle = arrowStyle
                changed = true
            }
        case .text, .emoji:
            if let fontSize, annotation.fontSize != fontSize {
                updated.fontSize = fontSize
                changed = true
            }
        case .mosaic:
            if let lineWidth, annotation.lineWidth != lineWidth {
                updated.lineWidth = lineWidth
                changed = true
            }
            if let obscureStrength, annotation.obscureStrength != obscureStrength {
                updated.obscureStrength = obscureStrength
                changed = true
            }
            if let obscureBlurStrength, annotation.obscureBlurStrength != obscureBlurStrength {
                updated.obscureBlurStrength = obscureBlurStrength
                changed = true
            }
        default:
            break
        }
        guard changed else { return }
        update(updated)
    }

    func remove(id: UUID, saveUndo: Bool = true) {
        guard let removed = annotations.first(where: { $0.id == id }) else { return }
        if pendingAnnotationDraft?.id == id { pendingAnnotationDraft = nil }
        if saveUndo { saveUndoPoint() }
        annotations.removeAll { $0.id == id }
        if removed.kind == .mosaic { refreshMosaicPreview() }
    }

    func numberAnnotation(at point: CGPoint) -> ScreenshotAnnotation {
        ScreenshotAnnotation(
            kind: .number,
            points: [point],
            color: color,
            lineWidth: lineWidth,
            number: nextNumber
        )
    }

    func addNumber(at point: CGPoint) {
        add(numberAnnotation(at: point))
    }

    func replaceCapture(
        with newImage: NSImage,
        translatingAnnotationsBy translation: CGSize
    ) {
        pendingAnnotationDraft = nil
        image = newImage
        annotations = Self.translated(annotations, by: translation)
        undoStack = undoStack.map { snapshot in
            Snapshot(
                image: newImage,
                annotations: Self.translated(snapshot.annotations, by: translation),
                nextNumber: snapshot.nextNumber
            )
        }
        redoStack = redoStack.map { snapshot in
            Snapshot(
                image: newImage,
                annotations: Self.translated(snapshot.annotations, by: translation),
                nextNumber: snapshot.nextNumber
            )
        }
        refreshMosaicPreview()
    }

    func undo() {
        pendingAnnotationDraft = nil
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(previous)
        syncHistoryState()
    }

    func redo() {
        pendingAnnotationDraft = nil
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
        syncHistoryState()
    }

    @discardableResult
    func append(
        image nextImage: NSImage,
        direction: ScreenshotLongCaptureDirection = .vertical
    ) -> Bool {
        let previous = lastLongCaptureFrame?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let next = nextImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if let previous, let next,
           ScreenshotLongCaptureMatcher.isVisuallyUnchanged(previous: previous, next: next) {
            lastLongCaptureFrame = nextImage
            statusMessage = "等待页面滚动"
            return false
        }
        let match: ScreenshotLongCaptureMatch? = {
            guard let previous, let next else { return nil }
            return ScreenshotLongCaptureMatcher.match(
                previous: previous,
                next: next,
                direction: direction
            )
        }()
        if isLongCapturePreviewing, match == nil {
            statusMessage = "未检测到可拼接区域，请放慢滚动"
            return false
        }
        guard let combined = Self.stackedImage(
            first: image,
            second: nextImage,
            direction: direction,
            match: match
        ) else {
            statusMessage = "长截图拼接失败"
            return false
        }
        saveUndoPoint()
        image = combined
        if match?.placement == .prepend {
            let addedLength: CGFloat = switch direction {
            case .vertical:
                nextImage.size.height * (1 - (match?.overlapFraction ?? 0))
            case .horizontal:
                nextImage.size.width * (1 - (match?.overlapFraction ?? 0))
            }
            annotations = Self.translated(
                annotations,
                by: direction == .vertical
                    ? CGSize(width: 0, height: addedLength)
                    : CGSize(width: addedLength, height: 0)
            )
        }
        lastLongCaptureFrame = nextImage
        refreshMosaicPreview()
        statusMessage = "已追加一屏，继续点击长截图可继续拼接"
        return true
    }

    func beginLongCapturePreview() {
        isLongCapturePreviewing = true
        hasLongCaptureResult = false
        lastLongCaptureFrame = image
    }

    func completeLongCapturePreview() {
        isLongCapturePreviewing = false
        hasLongCaptureResult = true
        lastLongCaptureFrame = nil
    }

    func endLongCapturePreview() {
        isLongCapturePreviewing = false
        hasLongCaptureResult = false
        lastLongCaptureFrame = nil
    }

    func beginTextDraft(id: UUID, text: String, isNew: Bool) {
        pendingTextDraft = PendingTextDraft(id: id, text: text, isNew: isNew)
    }

    func updateTextDraft(id: UUID, text: String, isNew: Bool) {
        guard let pendingTextDraft, pendingTextDraft.id == id else {
            self.pendingTextDraft = PendingTextDraft(id: id, text: text, isNew: isNew)
            return
        }
        self.pendingTextDraft = PendingTextDraft(
            id: pendingTextDraft.id,
            text: text,
            isNew: pendingTextDraft.isNew
        )
    }

    @discardableResult
    func commitPendingTextDraft() -> Bool {
        guard let draft = pendingTextDraft else { return false }
        pendingTextDraft = nil
        guard var annotation = annotations.first(where: { $0.id == draft.id }) else { return false }

        let value = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            if draft.isNew { remove(id: draft.id, saveUndo: false) }
            return false
        }

        annotation.text = value
        if !annotation.points.isEmpty {
            let rect = ScreenshotAnnotationGeometry.bounds(for: annotation)
            let width = ScreenshotInlineTextLayout.width(
                for: annotation.text,
                fontSize: annotation.fontSize,
                from: rect.minX,
                to: image.size.width
            )
            let height = ScreenshotInlineTextLayout.contentHeight(
                for: annotation.text,
                fontSize: annotation.fontSize,
                width: width
            )
            annotation.rect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: width,
                height: height
            )
            annotation.points = [annotation.rect.center]
        }

        if draft.isNew {
            remove(id: draft.id, saveUndo: false)
        }
        add(annotation)
        return true
    }

    func discardPendingTextDraft() {
        guard let draft = pendingTextDraft else { return }
        pendingTextDraft = nil
        if draft.isNew { remove(id: draft.id, saveUndo: false) }
    }

    func updatePendingAnnotationDraft(_ annotation: ScreenshotAnnotation?) {
        pendingAnnotationDraft = annotation
    }

    @discardableResult
    func commitPendingAnnotationDraft() -> Bool {
        guard let draft = pendingAnnotationDraft else { return false }
        pendingAnnotationDraft = nil
        add(draft)
        return true
    }

    func discardPendingAnnotationDraft() {
        pendingAnnotationDraft = nil
    }

    func renderedImage() -> NSImage {
        commitPendingTextDraft()
        commitPendingAnnotationDraft()
        let renderedBase = imageApplyingMosaics()
        guard let base = renderedBase.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let pixelWidth = base.width
        let pixelHeight = base.height
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image
        }
        bitmap.size = image.size
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else { return image }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        renderedBase.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        for annotation in annotations where annotation.kind != .mosaic {
            draw(annotation, in: image.size)
        }
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let output = NSImage(size: image.size)
        output.addRepresentation(bitmap)
        return output
    }

    func pngData() -> Data? {
        let rendered = renderedImage()
        guard let representation = rendered.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .first ?? NSBitmapImageRep(data: rendered.tiffRepresentation ?? Data())
        else { return nil }
        return representation.representation(using: .png, properties: [:])
    }

    func imageApplyingMosaics() -> NSImage {
        imageApplyingMosaics(adding: nil)
    }

    func imageApplyingMosaics(adding draft: ScreenshotAnnotation?) -> NSImage {
        var obscures = annotations.filter { $0.kind == .mosaic }
        if let draft, draft.kind == .mosaic {
            // A draft carrying an existing id is an in-flight edit of that region, so it replaces the
            // stored copy instead of stacking a second obscure pass over the same pixels.
            if let index = obscures.firstIndex(where: { $0.id == draft.id }) {
                obscures[index] = draft
            } else {
                obscures.append(draft)
            }
        }
        guard !obscures.isEmpty,
              image.size.width > 0,
              image.size.height > 0,
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return image
        }

        var output = CIImage(cgImage: source)
        let extent = output.extent
        let scaleX = extent.width / image.size.width
        let scaleY = extent.height / image.size.height

        for annotation in obscures {
            guard let mask = Self.obscureMask(
                for: annotation,
                imageSize: image.size,
                extent: extent,
                scaleX: scaleX,
                scaleY: scaleY
            ), let blend = CIFilter(name: "CIBlendWithMask") else {
                continue
            }

            let filtered: CIImage?
            switch annotation.obscureEffect {
            case .pixelate:
                let pixelate = CIFilter(name: "CIPixellate")
                pixelate?.setValue(output, forKey: kCIInputImageKey)
                pixelate?.setValue(
                    max(8, annotation.obscureStrength * 3) * max(scaleX, scaleY),
                    forKey: kCIInputScaleKey
                )
                let pixelated = pixelate?.outputImage?.clamped(to: extent).cropped(to: extent)
                // Blur can ride on top of the blocks; 0 keeps the plain mosaic it used to be.
                if let pixelated,
                   annotation.obscureBlurStrength > 0,
                   let blur = CIFilter(name: "CIGaussianBlur") {
                    blur.setValue(pixelated, forKey: kCIInputImageKey)
                    blur.setValue(
                        annotation.obscureBlurStrength * 1.5 * max(scaleX, scaleY),
                        forKey: kCIInputRadiusKey
                    )
                    filtered = blur.outputImage?.clamped(to: extent).cropped(to: extent) ?? pixelated
                } else {
                    filtered = pixelated
                }
            case .blur:
                let blur = CIFilter(name: "CIGaussianBlur")
                blur?.setValue(output, forKey: kCIInputImageKey)
                blur?.setValue(
                    max(4, annotation.obscureBlurStrength * 1.5) * max(scaleX, scaleY),
                    forKey: kCIInputRadiusKey
                )
                let blurred = blur?.outputImage
                filtered = blurred?.clamped(to: extent).cropped(to: extent)
            }
            guard let filtered else { continue }

            blend.setValue(filtered, forKey: kCIInputImageKey)
            blend.setValue(output, forKey: kCIInputBackgroundImageKey)
            blend.setValue(mask, forKey: kCIInputMaskImageKey)
            if let blended = blend.outputImage?.cropped(to: extent) {
                output = blended
            }
        }

        guard let result = Self.ciContext.createCGImage(output, from: extent) else { return image }
        return NSImage(cgImage: result, size: image.size)
    }

    private static func obscureMask(
        for annotation: ScreenshotAnnotation,
        imageSize: CGSize,
        extent: CGRect,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) -> CIImage? {
        let width = Int(extent.width.rounded(.up))
        let height = Int(extent.height.rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.setShouldAntialias(true)

        switch annotation.obscureShape {
        case .rectangle:
            let bounds = CGRect(origin: .zero, size: imageSize)
            let rect = annotation.rect.standardized.intersection(bounds)
            guard rect.width > 0, rect.height > 0 else { return nil }
            context.fill(CGRect(
                x: rect.minX * scaleX,
                y: (imageSize.height - rect.maxY) * scaleY,
                width: rect.width * scaleX,
                height: rect.height * scaleY
            ))
        case .brush:
            guard let first = annotation.points.first else { return nil }
            context.setLineWidth(max(12, annotation.lineWidth * 5) * max(scaleX, scaleY))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(
                x: first.x * scaleX,
                y: (imageSize.height - first.y) * scaleY
            ))
            for point in annotation.points.dropFirst() {
                context.addLine(to: CGPoint(
                    x: point.x * scaleX,
                    y: (imageSize.height - point.y) * scaleY
                ))
            }
            context.strokePath()
        }

        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image).cropped(to: extent)
    }

    private func saveUndoPoint() {
        undoStack.append(snapshot)
        if undoStack.count > 80 { undoStack.removeFirst() }
        redoStack.removeAll(keepingCapacity: true)
        syncHistoryState()
    }

    private func syncHistoryState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private var snapshot: Snapshot {
        Snapshot(image: image, annotations: annotations, nextNumber: nextNumber)
    }

    private func restore(_ snapshot: Snapshot) {
        image = snapshot.image
        annotations = snapshot.annotations
        nextNumber = snapshot.nextNumber
        refreshMosaicPreview()
    }

    private func refreshMosaicPreview() {
        mosaicPreviewImage = imageApplyingMosaics()
    }

    private static func translated(
        _ annotations: [ScreenshotAnnotation],
        by translation: CGSize
    ) -> [ScreenshotAnnotation] {
        annotations.map { annotation in
            var translated = annotation
            translated.points = annotation.points.map { point in
                CGPoint(x: point.x + translation.width, y: point.y + translation.height)
            }
            if annotation.rect != .zero {
                translated.rect = annotation.rect.offsetBy(
                    dx: translation.width,
                    dy: translation.height
                )
            }
            return translated
        }
    }

    private func draw(_ annotation: ScreenshotAnnotation, in imageSize: CGSize) {
        let color = annotation.color.nsColor
        color.setStroke()
        color.setFill()

        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        defer { context?.restoreGState() }
        let center = appKitPoint(
            ScreenshotAnnotationGeometry.bounds(for: annotation).center,
            imageHeight: imageSize.height
        )
        context?.translateBy(x: center.x, y: center.y)
        context?.rotate(by: annotation.rotation)
        context?.translateBy(x: -center.x, y: -center.y)

        switch annotation.kind {
        case .rectangle:
            let rect = appKitRect(annotation.rect, imageHeight: imageSize.height)
            let path = NSBezierPath(rect: rect)
            path.lineWidth = annotation.lineWidth
            path.stroke()
        case .ellipse:
            let rect = appKitRect(annotation.rect, imageHeight: imageSize.height)
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = annotation.lineWidth
            path.stroke()
        case .brush:
            drawLine(annotation.points, imageHeight: imageSize.height, lineWidth: annotation.lineWidth)
        case .arrow:
            guard let start = annotation.points.first, let end = annotation.points.last else { return }
            if annotation.arrowStyle == .tapered,
               let shaftPoints = ScreenshotArrowGeometry.taperedShaftPoints(
                   from: start,
                   to: end,
                   lineWidth: annotation.lineWidth
               ) {
                let shaft = NSBezierPath()
                shaft.move(to: appKitPoint(shaftPoints[0], imageHeight: imageSize.height))
                for point in shaftPoints.dropFirst() {
                    shaft.line(to: appKitPoint(point, imageHeight: imageSize.height))
                }
                shaft.close()
                shaft.fill()
            } else {
                let line = NSBezierPath()
                line.move(to: appKitPoint(start, imageHeight: imageSize.height))
                line.line(to: appKitPoint(end, imageHeight: imageSize.height))
                line.lineWidth = annotation.lineWidth
                line.stroke()
            }
            let headPoints = ScreenshotArrowGeometry.headPoints(
                from: start,
                to: end,
                lineWidth: annotation.lineWidth,
                minimumLength: 10
            )
            let head = NSBezierPath()
            head.move(to: appKitPoint(headPoints.tip, imageHeight: imageSize.height))
            head.line(to: appKitPoint(headPoints.left, imageHeight: imageSize.height))
            head.move(to: appKitPoint(headPoints.tip, imageHeight: imageSize.height))
            head.line(to: appKitPoint(headPoints.right, imageHeight: imageSize.height))
            head.lineWidth = annotation.lineWidth
            head.stroke()
        case .number:
            guard let point = annotation.points.first else { return }
            let center = appKitPoint(point, imageHeight: imageSize.height)
            let radius = ScreenshotAnnotationGeometry.numberDiameter(for: annotation.lineWidth) / 2
            let circle = NSBezierPath(ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            color.setFill()
            NSColor.white.setStroke()
            circle.lineWidth = 1.5
            circle.fill()
            circle.stroke()
            let text = "\(annotation.number)" as NSString
            let font = NSFont.systemFont(ofSize: radius * 0.9, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(
                    x: center.x - textSize.width / 2,
                    y: center.y - textSize.height / 2
                ),
                withAttributes: attributes
            )
        case .text:
            guard !annotation.points.isEmpty else { return }
            let bounds = ScreenshotAnnotationGeometry.bounds(for: annotation)
            ScreenshotTextRendering.draw(
                annotation.text,
                color: annotation.color,
                fontSize: annotation.fontSize,
                in: NSRect(
                    x: bounds.minX,
                    y: imageSize.height - bounds.maxY,
                    width: bounds.width,
                    height: bounds.height
                )
            )
        case .emoji:
            guard !annotation.points.isEmpty else { return }
            let font = NSFont.systemFont(
                ofSize: ScreenshotAnnotationGeometry.emojiDiameter(for: annotation.fontSize),
                weight: .semibold
            )
            let value = annotation.text as NSString
            let textSize = value.size(withAttributes: [.font: font])
            let bounds = ScreenshotAnnotationGeometry.bounds(for: annotation)
            value.draw(
                at: NSPoint(
                    x: bounds.midX - textSize.width / 2,
                    y: imageSize.height - bounds.midY - textSize.height / 2
                ),
                withAttributes: [.font: font]
            )
        case .mosaic:
            break
        }
    }

    private func drawLine(_ points: [CGPoint], imageHeight: CGFloat, lineWidth: CGFloat) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.move(to: appKitPoint(first, imageHeight: imageHeight))
        for point in points.dropFirst() {
            path.line(to: appKitPoint(point, imageHeight: imageHeight))
        }
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func appKitPoint(_ point: CGPoint, imageHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: imageHeight - point.y)
    }

    private func appKitRect(_ rect: CGRect, imageHeight: CGFloat) -> CGRect {
        let normalized = rect.standardized
        return CGRect(
            x: normalized.minX,
            y: imageHeight - normalized.maxY,
            width: normalized.width,
            height: normalized.height
        )
    }

    private static func stackedImage(
        first: NSImage,
        second: NSImage,
        direction: ScreenshotLongCaptureDirection,
        match: ScreenshotLongCaptureMatch?
    ) -> NSImage? {
        let placement = match?.placement ?? .append
        let overlapFraction = match?.overlapFraction ?? 0
        let size: CGSize = switch direction {
        case .vertical:
            CGSize(
                width: max(first.size.width, second.size.width),
                height: first.size.height + second.size.height * (1 - overlapFraction)
            )
        case .horizontal:
            CGSize(
                width: first.size.width + second.size.width * (1 - overlapFraction),
                height: max(first.size.height, second.size.height)
            )
        }
        guard size.width > 0, size.height > 0 else { return nil }

        if let firstCGImage = first.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let secondCGImage = second.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let overlap = Optional(min(
               direction == .vertical
                   ? min(firstCGImage.height, secondCGImage.height)
                   : min(firstCGImage.width, secondCGImage.width),
               Int((CGFloat(
                   direction == .vertical ? secondCGImage.height : secondCGImage.width
               ) * overlapFraction).rounded())
           )),
           let output = CGContext(
               data: nil,
               width: direction == .vertical
                   ? max(firstCGImage.width, secondCGImage.width)
                   : firstCGImage.width + secondCGImage.width - overlap,
               height: direction == .vertical
                   ? firstCGImage.height + secondCGImage.height - overlap
                   : max(firstCGImage.height, secondCGImage.height),
               bitsPerComponent: 8,
               bytesPerRow: 0,
               space: CGColorSpaceCreateDeviceRGB(),
               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
           ) {
            output.interpolationQuality = .none
            output.setFillColor(NSColor.white.cgColor)
            output.fill(CGRect(x: 0, y: 0, width: output.width, height: output.height))
            switch direction {
            case .vertical:
                if placement == .append {
                    output.draw(
                        firstCGImage,
                        in: CGRect(
                            x: CGFloat(output.width - firstCGImage.width) / 2,
                            y: CGFloat(secondCGImage.height - overlap),
                            width: CGFloat(firstCGImage.width),
                            height: CGFloat(firstCGImage.height)
                        )
                    )
                    output.draw(
                        secondCGImage,
                        in: CGRect(
                            x: CGFloat(output.width - secondCGImage.width) / 2,
                            y: 0,
                            width: CGFloat(secondCGImage.width),
                            height: CGFloat(secondCGImage.height)
                        )
                    )
                } else {
                    output.draw(
                        firstCGImage,
                        in: CGRect(
                            x: CGFloat(output.width - firstCGImage.width) / 2,
                            y: 0,
                            width: CGFloat(firstCGImage.width),
                            height: CGFloat(firstCGImage.height)
                        )
                    )
                    output.draw(
                        secondCGImage,
                        in: CGRect(
                            x: CGFloat(output.width - secondCGImage.width) / 2,
                            y: CGFloat(firstCGImage.height - overlap),
                            width: CGFloat(secondCGImage.width),
                            height: CGFloat(secondCGImage.height)
                        )
                    )
                }
            case .horizontal:
                if placement == .append {
                    output.draw(
                        firstCGImage,
                        in: CGRect(
                            x: 0,
                            y: CGFloat(output.height - firstCGImage.height) / 2,
                            width: CGFloat(firstCGImage.width),
                            height: CGFloat(firstCGImage.height)
                        )
                    )
                    output.draw(
                        secondCGImage,
                        in: CGRect(
                            x: CGFloat(firstCGImage.width - overlap),
                            y: CGFloat(output.height - secondCGImage.height) / 2,
                            width: CGFloat(secondCGImage.width),
                            height: CGFloat(secondCGImage.height)
                        )
                    )
                } else {
                    output.draw(
                        firstCGImage,
                        in: CGRect(
                            x: CGFloat(secondCGImage.width - overlap),
                            y: CGFloat(output.height - firstCGImage.height) / 2,
                            width: CGFloat(firstCGImage.width),
                            height: CGFloat(firstCGImage.height)
                        )
                    )
                    output.draw(
                        secondCGImage,
                        in: CGRect(
                            x: 0,
                            y: CGFloat(output.height - secondCGImage.height) / 2,
                            width: CGFloat(secondCGImage.width),
                            height: CGFloat(secondCGImage.height)
                        )
                    )
                }
            }
            if let combined = output.makeImage() {
                return NSImage(cgImage: combined, size: size)
            }
        }

        let output = NSImage(size: size)
        output.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        switch direction {
        case .vertical:
            let addedHeight = second.size.height * (1 - overlapFraction)
            let firstY = placement == .append ? addedHeight : 0
            let secondY = placement == .append ? 0 : first.size.height - second.size.height * overlapFraction
            first.draw(
                in: NSRect(x: (size.width - first.size.width) / 2, y: firstY, width: first.size.width, height: first.size.height),
                from: .zero, operation: .sourceOver, fraction: 1
            )
            second.draw(
                in: NSRect(x: (size.width - second.size.width) / 2, y: secondY, width: second.size.width, height: second.size.height),
                from: .zero, operation: .sourceOver, fraction: 1
            )
        case .horizontal:
            let addedWidth = second.size.width * (1 - overlapFraction)
            let firstX = placement == .append ? 0 : addedWidth
            let secondX = placement == .append ? first.size.width - second.size.width * overlapFraction : 0
            first.draw(
                in: NSRect(x: firstX, y: (size.height - first.size.height) / 2, width: first.size.width, height: first.size.height),
                from: .zero, operation: .sourceOver, fraction: 1
            )
            second.draw(
                in: NSRect(x: secondX, y: (size.height - second.size.height) / 2, width: second.size.width, height: second.size.height),
                from: .zero, operation: .sourceOver, fraction: 1
            )
        }
        output.unlockFocus()
        return output
    }

    private static let ciContext = CIContext()
}

@MainActor
final class ScreenshotAnnotationSelectionState: ObservableObject {
    @Published var selectedAnnotationID: UUID?
    @Published var isInlineTextEditing = false

    func deselect() {
        selectedAnnotationID = nil
    }

    func deleteSelectedAnnotation(from model: ScreenshotEditorModel) -> Bool {
        guard !isInlineTextEditing, let selectedAnnotationID else { return false }
        guard model.annotations.contains(where: { $0.id == selectedAnnotationID }) else {
            deselect()
            return false
        }
        model.remove(id: selectedAnnotationID)
        deselect()
        return true
    }
}

struct ScreenshotCanvasGeometry {
    let canvasSize: CGSize
    let imageSize: CGSize
    let scale: CGFloat
    let origin: CGPoint
    let offset: CGSize

    init(canvasSize: CGSize, imageSize: CGSize, zoom: CGFloat = 1, offset: CGSize = .zero) {
        self.canvasSize = canvasSize
        self.imageSize = imageSize
        let widthScale = canvasSize.width / max(imageSize.width, 1)
        let heightScale = canvasSize.height / max(imageSize.height, 1)
        scale = min(widthScale, heightScale) * max(0.01, zoom)
        let renderedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        self.offset = Self.clampedOffset(offset, canvasSize: canvasSize, renderedSize: renderedSize)
        origin = CGPoint(
            x: (canvasSize.width - renderedSize.width) / 2 + self.offset.width,
            y: (canvasSize.height - renderedSize.height) / 2 + self.offset.height
        )
    }

    var renderedSize: CGSize {
        CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    func clampedOffset(_ offset: CGSize) -> CGSize {
        Self.clampedOffset(offset, canvasSize: canvasSize, renderedSize: renderedSize)
    }

    private static func clampedOffset(
        _ offset: CGSize,
        canvasSize: CGSize,
        renderedSize: CGSize
    ) -> CGSize {
        let horizontalLimit = max(0, (renderedSize.width - canvasSize.width) / 2)
        let verticalLimit = max(0, (renderedSize.height - canvasSize.height) / 2)
        return CGSize(
            width: min(max(offset.width, -horizontalLimit), horizontalLimit),
            height: min(max(offset.height, -verticalLimit), verticalLimit)
        )
    }

    func imagePoint(from canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max((canvasPoint.x - origin.x) / max(scale, 0.0001), 0), imageSize.width),
            y: min(max((canvasPoint.y - origin.y) / max(scale, 0.0001), 0), imageSize.height)
        )
    }

    func canvasPoint(from imagePoint: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + imagePoint.x * scale, y: origin.y + imagePoint.y * scale)
    }

    func canvasRect(from imageRect: CGRect) -> CGRect {
        let rect = imageRect.standardized
        return CGRect(
            x: origin.x + rect.minX * scale,
            y: origin.y + rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}

enum ScreenshotCanvasStyle {
    static let draftDashPattern: [CGFloat] = []
    static let rotationAnimationResponse = 0.10
    static let rotationAnimationDampingFraction = 1.0
    static var rotationAnimation: Animation {
        .interactiveSpring(
            response: rotationAnimationResponse,
            dampingFraction: rotationAnimationDampingFraction,
            blendDuration: 0
        )
    }
}

@MainActor
struct ScreenshotToolbarDragWrapper<Content: View>: View {
    private let content: Content
    let restingCenter: CGPoint
    let toolbarSize: CGSize
    let bounds: CGRect
    let onDragEnd: (CGPoint) -> Void

    init(
        restingCenter: CGPoint,
        toolbarSize: CGSize,
        bounds: CGRect,
        onDragEnd: @escaping (CGPoint) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.restingCenter = restingCenter
        self.toolbarSize = toolbarSize
        self.bounds = bounds
        self.onDragEnd = onDragEnd
        self.content = content()
    }

    var body: some View {
        ScreenshotToolbarDragRepresentable(
            rootView: content,
            restingCenter: restingCenter,
            toolbarSize: toolbarSize,
            bounds: bounds,
            onDragEnd: onDragEnd
        )
        .frame(width: max(0, bounds.width), height: max(0, bounds.height))
    }
}

private struct ScreenshotToolbarDragRepresentable<Content: View>: NSViewRepresentable {
    typealias NSViewType = ScreenshotToolbarDragContainer<Content>

    let rootView: Content
    let restingCenter: CGPoint
    let toolbarSize: CGSize
    let bounds: CGRect
    let onDragEnd: (CGPoint) -> Void

    func makeNSView(context: Context) -> ScreenshotToolbarDragContainer<Content> {
        ScreenshotToolbarDragContainer(
            rootView: rootView,
            restingCenter: restingCenter,
            toolbarSize: toolbarSize,
            bounds: bounds,
            onDragEnd: onDragEnd
        )
    }

    func updateNSView(
        _ nsView: ScreenshotToolbarDragContainer<Content>,
        context: Context
    ) {
        nsView.update(
            rootView: rootView,
            restingCenter: restingCenter,
            toolbarSize: toolbarSize,
            bounds: bounds,
            onDragEnd: onDragEnd
        )
    }
}

@MainActor
final class ScreenshotToolbarDragContainer<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private let toolbarView = ScreenshotToolbarContentView()
    private let dragHandleView = ScreenshotToolbarDragHandleView()
    private var restingCenter: CGPoint
    private var toolbarSize: CGSize
    private var layoutBounds: CGRect
    private var onDragEnd: (CGPoint) -> Void
    private var dragStartPoint: CGPoint?
    private var dragStartCenter: CGPoint?
    private var isDragging = false

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(
        rootView: Content,
        restingCenter: CGPoint,
        toolbarSize: CGSize,
        bounds: CGRect,
        onDragEnd: @escaping (CGPoint) -> Void
    ) {
        hostingView = NSHostingView(rootView: rootView)
        self.restingCenter = restingCenter
        self.toolbarSize = toolbarSize
        layoutBounds = bounds
        self.onDragEnd = onDragEnd
        super.init(frame: .zero)

        toolbarView.addSubview(hostingView)
        toolbarView.addSubview(dragHandleView)
        addSubview(toolbarView)
        dragHandleView.toolTip = "拖动工具栏"

        dragHandleView.onMouseDown = { [weak self] event in
            self?.beginDrag(with: event)
        }
        dragHandleView.onMouseDragged = { [weak self] event in
            self?.continueDrag(with: event)
        }
        dragHandleView.onMouseUp = { [weak self] event in
            self?.endDrag(with: event)
        }
        updateToolbarFrame(center: restingCenter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        rootView: Content,
        restingCenter: CGPoint,
        toolbarSize: CGSize,
        bounds: CGRect,
        onDragEnd: @escaping (CGPoint) -> Void
    ) {
        hostingView.rootView = rootView
        self.restingCenter = restingCenter
        self.toolbarSize = toolbarSize
        layoutBounds = bounds
        self.onDragEnd = onDragEnd
        guard !isDragging else { return }
        updateToolbarFrame(center: restingCenter)
    }

    override func layout() {
        super.layout()
        guard !isDragging else { return }
        updateToolbarFrame(center: restingCenter)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    private func updateToolbarFrame(center: CGPoint) {
        let clampedCenter = ScreenshotToolbarLayout.clampedCenter(
            center,
            toolbarSize: toolbarSize,
            in: layoutBounds
        )
        toolbarView.frame = CGRect(
            x: clampedCenter.x - toolbarSize.width / 2,
            y: clampedCenter.y - toolbarSize.height / 2,
            width: toolbarSize.width,
            height: toolbarSize.height
        )
        updateToolbarSubviews()
    }

    private func moveToolbar(to center: CGPoint) {
        let clampedCenter = ScreenshotToolbarLayout.clampedCenter(
            center,
            toolbarSize: toolbarSize,
            in: layoutBounds
        )
        toolbarView.setFrameOrigin(CGPoint(
            x: clampedCenter.x - toolbarSize.width / 2,
            y: clampedCenter.y - toolbarSize.height / 2
        ))
    }

    private func updateToolbarSubviews() {
        hostingView.frame = toolbarView.bounds
        dragHandleView.frame = CGRect(
            x: 0,
            y: 0,
            width: ScreenshotToolbarLayout.horizontalPadding
                + ScreenshotToolbarLayout.dragHandleWidth,
            height: toolbarSize.height
        )
    }

    private func beginDrag(with event: NSEvent) {
        dragStartPoint = event.locationInWindow
        dragStartCenter = toolbarView.frame.center
        isDragging = false
    }

    private func continueDrag(with event: NSEvent) {
        guard let dragStartPoint, let dragStartCenter else { return }
        let currentPoint = event.locationInWindow
        let translation = CGSize(
            width: currentPoint.x - dragStartPoint.x,
            height: dragStartPoint.y - currentPoint.y
        )
        isDragging = true
        moveToolbar(to: CGPoint(
            x: dragStartCenter.x + translation.width,
            y: dragStartCenter.y + translation.height
        ))
    }

    private func endDrag(with event: NSEvent) {
        guard let dragStartPoint, let dragStartCenter else { return }
        defer {
            self.dragStartPoint = nil
            self.dragStartCenter = nil
            isDragging = false
        }
        guard isDragging else { return }

        let currentPoint = event.locationInWindow
        let finalCenter = ScreenshotToolbarLayout.clampedCenter(
            CGPoint(
                x: dragStartCenter.x + currentPoint.x - dragStartPoint.x,
                y: dragStartCenter.y + dragStartPoint.y - currentPoint.y
            ),
            toolbarSize: toolbarSize,
            in: layoutBounds
        )
        moveToolbar(to: finalCenter)
        onDragEnd(finalCenter)
    }
}

@MainActor
private final class ScreenshotToolbarContentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class ScreenshotToolbarDragHandleView: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(event)
    }
}

enum ScreenshotToolbarLayout {
    static let controlCount = 15
    static let controlWidth: CGFloat = 60
    static let controlHeight: CGFloat = 28
    static let dragHandleWidth: CGFloat = 28
    static let dragHandleColumns = 2
    static let dragHandleRows = 3
    static let dragHandleDotRadius: CGFloat = 2
    static let dragHandleHorizontalSpacing: CGFloat = 6
    static let dragHandleVerticalSpacing: CGFloat = 5
    static let spacing: CGFloat = 2
    static let horizontalPadding: CGFloat = 5
    static let height: CGFloat = 38
    static let cornerRadius: CGFloat = 10
    static let borderOpacity: Double = 0.08

    static var contentWidth: CGFloat {
        contentWidth(forControlCount: controlCount)
    }

    static func contentWidth(forControlCount count: Int) -> CGFloat {
        horizontalPadding * 2
            + dragHandleWidth
            + CGFloat(count) * controlWidth
            + CGFloat(count) * spacing
    }

    static func viewportWidth(
        availableWidth: CGFloat,
        controlCount: Int = controlCount
    ) -> CGFloat {
        min(contentWidth(forControlCount: controlCount), max(0, availableWidth - 24))
    }

    static func clampedCenter(_ center: CGPoint, toolbarSize: CGSize, in bounds: CGRect) -> CGPoint {
        let halfWidth = toolbarSize.width / 2
        let halfHeight = toolbarSize.height / 2
        let minimumX = bounds.minX + halfWidth
        let maximumX = bounds.maxX - halfWidth
        let minimumY = bounds.minY + halfHeight
        let maximumY = bounds.maxY - halfHeight
        return CGPoint(
            x: minimumX <= maximumX ? min(max(center.x, minimumX), maximumX) : bounds.midX,
            y: minimumY <= maximumY ? min(max(center.y, minimumY), maximumY) : bounds.midY
        )
    }
}

enum ScreenshotToolPopoverPlacement {
    static func preferredEdge(
        toolbarFrame: CGRect,
        selectionRect: CGRect?,
        bounds: CGRect
    ) -> Edge {
        guard let selectionRect, !selectionRect.isEmpty else { return .bottom }

        let toolbar = toolbarFrame.standardized
        let selection = selectionRect.standardized
        let overlapAbove = max(0, toolbar.minY - selection.minY)
        let overlapBelow = max(0, selection.maxY - toolbar.maxY)

        if overlapAbove == 0, overlapBelow > 0 { return .top }
        if overlapBelow == 0, overlapAbove > 0 { return .bottom }
        if overlapAbove != overlapBelow {
            return overlapAbove < overlapBelow ? .top : .bottom
        }

        let aboveSpace = max(0, toolbar.minY - bounds.minY)
        let belowSpace = max(0, bounds.maxY - toolbar.maxY)
        return aboveSpace > belowSpace ? .top : .bottom
    }
}

struct ScreenshotToolbarDragDots: View {
    var body: some View {
        Canvas { context, size in
            let totalWidth = ScreenshotToolbarLayout.dragHandleHorizontalSpacing
                * CGFloat(ScreenshotToolbarLayout.dragHandleColumns - 1)
            let totalHeight = ScreenshotToolbarLayout.dragHandleVerticalSpacing
                * CGFloat(ScreenshotToolbarLayout.dragHandleRows - 1)
            let startX = (size.width - totalWidth) / 2
            let startY = (size.height - totalHeight) / 2

            for row in 0..<ScreenshotToolbarLayout.dragHandleRows {
                for column in 0..<ScreenshotToolbarLayout.dragHandleColumns {
                    let center = CGPoint(
                        x: startX + CGFloat(column) * ScreenshotToolbarLayout.dragHandleHorizontalSpacing,
                        y: startY + CGFloat(row) * ScreenshotToolbarLayout.dragHandleVerticalSpacing
                    )
                    let radius = ScreenshotToolbarLayout.dragHandleDotRadius
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )),
                        with: .color(.secondary.opacity(0.7))
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct ScreenshotRecognizedFragment: Equatable {
    let text: String
    let boundingBox: CGRect
}

struct ScreenshotRecognizedTable: Equatable {
    struct Cell: Equatable, Hashable {
        let row: Int
        let column: Int
    }

    struct Merge: Equatable, Hashable {
        let row: Int
        let column: Int
        let rowSpan: Int
        let columnSpan: Int
    }

    var rows: [[String]]
    var merges: [Merge]
    var columnWidths: [Double] = []
    var rowHeights: [Double] = []
    var gridRowRange: Range<Int>?
    var titleRows: Set<Int> = []
    var verticalCells: Set<Cell> = []

    var isEmpty: Bool {
        rows.allSatisfy { $0.allSatisfy(\.isEmpty) }
    }
}

enum ScreenshotRecognitionFormatter {
    private struct ImageGrid {
        let width: Int
        let height: Int
        let pixels: [UInt8]
        let rows: [Int]
        let columns: [Int]

        func hasVerticalLine(at x: Int, from startY: Int, to endY: Int) -> Bool {
            let range = (startY + 2)..<max(startY + 2, endY - 1)
            guard !range.isEmpty else { return true }
            let darkCount = range.reduce(into: 0) { count, y in
                if ((x - 1)...(x + 1)).contains(where: { isDark(x: $0, y: y) }) {
                    count += 1
                }
            }
            return Double(darkCount) / Double(range.count) >= 0.65
        }

        func hasHorizontalLine(at y: Int, from startX: Int, to endX: Int) -> Bool {
            let range = (startX + 2)..<max(startX + 2, endX - 1)
            guard !range.isEmpty else { return true }
            let darkCount = range.reduce(into: 0) { count, x in
                if ((y - 1)...(y + 1)).contains(where: { isDark(x: x, y: $0) }) {
                    count += 1
                }
            }
            return Double(darkCount) / Double(range.count) >= 0.65
        }

        private func isDark(x: Int, y: Int) -> Bool {
            guard x >= 0, y >= 0, x < width, y < height else { return false }
            return pixels[y * width + x] < 190
        }
    }

    private struct TableRow {
        var fragments: [ScreenshotRecognizedFragment]

        var centerY: CGFloat {
            fragments.map(\.boundingBox.midY).reduce(0, +) / CGFloat(fragments.count)
        }

        var averageHeight: CGFloat {
            fragments.map(\.boundingBox.height).reduce(0, +) / CGFloat(fragments.count)
        }
    }

    static func plainText(from fragments: [ScreenshotRecognizedFragment]) -> String {
        fragments
            .sorted(by: readingOrder)
            .map(\.text)
            .joined(separator: "\n")
    }

    static func tableText(from fragments: [ScreenshotRecognizedFragment]) -> String {
        table(from: fragments).rows
            .map { $0.joined(separator: "\t") }
            .joined(separator: "\n")
    }

    static func table(from fragments: [ScreenshotRecognizedFragment]) -> ScreenshotRecognizedTable {
        let rows = tableRows(from: fragments).sorted { $0.centerY > $1.centerY }
        let anchors = columnAnchors(in: rows)
        guard !anchors.isEmpty else { return ScreenshotRecognizedTable(rows: [], merges: []) }

        var merges: [ScreenshotRecognizedTable.Merge] = []
        var cells = rows.enumerated().map { rowIndex, row in
            var values = Array(repeating: "", count: anchors.count)
            var occupiedColumns = Set<Int>()
            for fragment in row.fragments.sorted(by: { $0.boundingBox.minX < $1.boundingBox.minX }) {
                let column = anchors.indices.min { left, right in
                    abs(anchors[left] - fragment.boundingBox.minX)
                        < abs(anchors[right] - fragment.boundingBox.minX)
                } ?? 0
                values[column] += values[column].isEmpty ? fragment.text : " \(fragment.text)"
                let endColumn = anchors.indices.last { anchors[$0] <= fragment.boundingBox.maxX } ?? column
                if endColumn > column,
                   occupiedColumns.isDisjoint(with: column...endColumn) {
                    merges.append(ScreenshotRecognizedTable.Merge(
                        row: rowIndex,
                        column: column,
                        rowSpan: 1,
                        columnSpan: endColumn - column + 1
                    ))
                    occupiedColumns.formUnion(column...endColumn)
                } else {
                    occupiedColumns.insert(column)
                }
            }
            return values
        }
        merges.append(contentsOf: mergeVerticalLabels(in: &cells, rows: rows))
        return ScreenshotRecognizedTable(rows: cells, merges: merges)
    }

    static func table(
        from fragments: [ScreenshotRecognizedFragment],
        image: CGImage
    ) -> ScreenshotRecognizedTable {
        guard let grid = imageGrid(in: image) else { return table(from: fragments) }
        return table(from: fragments, grid: grid)
    }

    private static func table(
        from fragments: [ScreenshotRecognizedFragment],
        grid: ImageGrid
    ) -> ScreenshotRecognizedTable {
        let rowCount = grid.rows.count - 1
        let columnCount = grid.columns.count - 1
        let gridBounds = CGRect(
            x: grid.columns[0],
            y: grid.rows[0],
            width: grid.columns[columnCount] - grid.columns[0],
            height: grid.rows[rowCount] - grid.rows[0]
        )
        let positioned = fragments.map { fragment in
            (
                fragment: fragment,
                point: CGPoint(
                    x: fragment.boundingBox.midX * CGFloat(grid.width),
                    y: (1 - fragment.boundingBox.midY) * CGFloat(grid.height)
                )
            )
        }
        let topRows = tableRows(from: positioned.filter { $0.point.y < gridBounds.minY }.map(\.fragment))
            .sorted { $0.centerY > $1.centerY }
        let bottomRows = tableRows(from: positioned.filter { $0.point.y > gridBounds.maxY }.map(\.fragment))
            .sorted { $0.centerY > $1.centerY }
        let fragmentHeights = fragments.map(\.boundingBox.height).sorted()
        let typicalTextHeight = fragmentHeights.isEmpty ? 0 : fragmentHeights[fragmentHeights.count / 2]
        let titleIndex = topRows.indices.filter { index in
            let row = topRows[index]
            let centerX = row.fragments.map(\.boundingBox.midX).reduce(0, +) / CGFloat(row.fragments.count)
            return row.averageHeight >= typicalTextHeight * 1.35 && abs(centerX - 0.5) <= 0.2
        }.max { topRows[$0].averageHeight < topRows[$1].averageHeight }
        var outputRows = topRows.map { outsideRow(from: $0, grid: grid) }
        var rowHeights = topRows.map { outsideRowHeight(for: $0, imageHeight: grid.height) }
        var titleRows = Set<Int>()
        var merges: [ScreenshotRecognizedTable.Merge] = []
        if let titleIndex {
            let title = topRows[titleIndex].fragments.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .map(\.text).joined(separator: " ")
            outputRows[titleIndex] = Array(repeating: "", count: columnCount)
            outputRows[titleIndex][0] = title
            rowHeights[titleIndex] = max(rowHeights[titleIndex], 36)
            titleRows.insert(titleIndex)
            merges.append(.init(row: titleIndex, column: 0, rowSpan: 1, columnSpan: columnCount))
        }

        let gridOffset = outputRows.count
        var gridRows = Array(
            repeating: Array(repeating: "", count: columnCount),
            count: rowCount
        )
        var regions: [ScreenshotRecognizedTable.Cell: [ScreenshotRecognizedTable.Cell]] = [:]
        var cellRegion: [ScreenshotRecognizedTable.Cell: ScreenshotRecognizedTable.Cell] = [:]
        var visited = Set<ScreenshotRecognizedTable.Cell>()
        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let start = ScreenshotRecognizedTable.Cell(row: row, column: column)
                guard visited.insert(start).inserted else { continue }
                var queue = [start]
                var component: [ScreenshotRecognizedTable.Cell] = []
                while let cell = queue.popLast() {
                    component.append(cell)
                    for neighbor in connectedNeighbors(of: cell, grid: grid) where visited.insert(neighbor).inserted {
                        queue.append(neighbor)
                    }
                }
                let minRow = component.map(\.row).min() ?? row
                let maxRow = component.map(\.row).max() ?? row
                let minColumn = component.map(\.column).min() ?? column
                let maxColumn = component.map(\.column).max() ?? column
                let isRectangle = component.count == (maxRow - minRow + 1) * (maxColumn - minColumn + 1)
                if isRectangle {
                    let anchor = ScreenshotRecognizedTable.Cell(row: minRow, column: minColumn)
                    regions[anchor] = component
                    component.forEach { cellRegion[$0] = anchor }
                    if component.count > 1 {
                        merges.append(.init(
                            row: gridOffset + minRow,
                            column: minColumn,
                            rowSpan: maxRow - minRow + 1,
                            columnSpan: maxColumn - minColumn + 1
                        ))
                    }
                } else {
                    for cell in component {
                        regions[cell] = [cell]
                        cellRegion[cell] = cell
                    }
                }
            }
        }

        var regionFragments: [ScreenshotRecognizedTable.Cell: [ScreenshotRecognizedFragment]] = [:]
        for item in positioned where gridBounds.contains(item.point) {
            guard let row = interval(containing: Int(item.point.y), in: grid.rows),
                  let column = interval(containing: Int(item.point.x), in: grid.columns),
                  let anchor = cellRegion[.init(row: row, column: column)]
            else { continue }
            regionFragments[anchor, default: []].append(item.fragment)
        }

        var verticalCells = Set<ScreenshotRecognizedTable.Cell>()
        for (anchor, component) in regions {
            guard let fragments = regionFragments[anchor], !fragments.isEmpty else { continue }
            let maxRow = component.map(\.row).max() ?? anchor.row
            let maxColumn = component.map(\.column).max() ?? anchor.column
            let pixelWidth = grid.columns[maxColumn + 1] - grid.columns[anchor.column]
            let pixelHeight = grid.rows[maxRow + 1] - grid.rows[anchor.row]
            let vertical = pixelHeight > Int(Double(pixelWidth) * 1.35)
                && fragments.map(\.text).joined().filter { !$0.isWhitespace }.count <= 12
            let value: String
            if vertical {
                value = fragments.sorted(by: readingOrder).map(\.text).joined()
                    .filter { !$0.isWhitespace }
                verticalCells.insert(.init(row: gridOffset + anchor.row, column: anchor.column))
            } else {
                value = text(from: fragments)
            }
            gridRows[anchor.row][anchor.column] = value
        }
        outputRows.append(contentsOf: gridRows)
        rowHeights.append(contentsOf: zip(grid.rows, grid.rows.dropFirst()).map { start, end in
            min(max(Double(end - start) * 0.75, 18), 60)
        })

        outputRows.append(contentsOf: bottomRows.map { outsideRow(from: $0, grid: grid) })
        rowHeights.append(contentsOf: bottomRows.map { outsideRowHeight(for: $0, imageHeight: grid.height) })
        return ScreenshotRecognizedTable(
            rows: outputRows,
            merges: merges,
            columnWidths: zip(grid.columns, grid.columns.dropFirst()).map { start, end in
                min(max(Double(end - start) / 9, 2), 48)
            },
            rowHeights: rowHeights,
            gridRowRange: gridOffset..<(gridOffset + rowCount),
            titleRows: titleRows,
            verticalCells: verticalCells
        )
    }

    private static func imageGrid(in image: CGImage) -> ImageGrid? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        guard width >= 40, height >= 40,
              let context = CGContext(
                  data: &pixels,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let minimumLength = Int(Double(width) * 0.15)
        let candidates = (0..<height).compactMap { y -> (position: Int, start: Int, end: Int)? in
            guard let span = longestDarkRun(in: pixels, width: width, y: y),
                  span.end - span.start >= minimumLength
            else { return nil }
            return (y, span.start, span.end)
        }
        let horizontalLines = clusteredLines(candidates.map(\.position)) { positions in
            positions.max { left, right in
                let leftSpan = candidates.first { $0.position == left }!
                let rightSpan = candidates.first { $0.position == right }!
                return leftSpan.end - leftSpan.start < rightSpan.end - rightSpan.start
            } ?? positions[0]
        }
        guard horizontalLines.count >= 3,
              let widest = candidates.max(by: { $0.end - $0.start < $1.end - $1.start })
        else { return nil }
        let left = widest.start
        let right = widest.end
        let tableWidth = right - left
        guard tableWidth >= minimumLength else { return nil }
        let rows = horizontalLines.filter { y in
            guard let span = candidates.first(where: { $0.position == y }) else { return false }
            return min(span.end, right) - max(span.start, left) >= Int(Double(tableWidth) * 0.15)
        }
        guard rows.count >= 3 else { return nil }

        var verticalCandidates = [left, right]
        for (startY, endY) in zip(rows, rows.dropFirst()) where endY - startY >= 5 {
            for x in left...right {
                let range = (startY + 2)..<(endY - 1)
                let darkCount = range.reduce(into: 0) { count, y in
                    if pixels[y * width + x] < 190 { count += 1 }
                }
                if Double(darkCount) / Double(range.count) >= 0.72 {
                    verticalCandidates.append(x)
                }
            }
        }
        let columns = clusteredLines(verticalCandidates) { positions in
            Int((Double(positions.reduce(0, +)) / Double(positions.count)).rounded())
        }.filter { $0 >= left - 2 && $0 <= right + 2 }
        guard columns.count >= 2 else { return nil }
        return ImageGrid(width: width, height: height, pixels: pixels, rows: rows, columns: columns)
    }

    private static func longestDarkRun(
        in pixels: [UInt8],
        width: Int,
        y: Int
    ) -> (start: Int, end: Int)? {
        var best: (start: Int, end: Int)?
        var start: Int?
        var lastDark = 0
        var gap = 0
        for x in 0..<width {
            if pixels[y * width + x] < 190 {
                start = start ?? x
                lastDark = x
                gap = 0
            } else if start != nil {
                gap += 1
                if gap > 2 {
                    if best == nil || lastDark - start! > best!.end - best!.start {
                        best = (start!, lastDark)
                    }
                    start = nil
                }
            }
        }
        if let start, best == nil || lastDark - start > best!.end - best!.start {
            best = (start, lastDark)
        }
        return best
    }

    private static func clusteredLines(
        _ positions: [Int],
        representative: ([Int]) -> Int
    ) -> [Int] {
        var groups: [[Int]] = []
        for position in positions.sorted() {
            if let index = groups.indices.last, position - groups[index].last! <= 3 {
                groups[index].append(position)
            } else {
                groups.append([position])
            }
        }
        return groups.map(representative).sorted()
    }

    private static func connectedNeighbors(
        of cell: ScreenshotRecognizedTable.Cell,
        grid: ImageGrid
    ) -> [ScreenshotRecognizedTable.Cell] {
        let rowCount = grid.rows.count - 1
        let columnCount = grid.columns.count - 1
        var neighbors: [ScreenshotRecognizedTable.Cell] = []
        if cell.column > 0,
           !grid.hasVerticalLine(
               at: grid.columns[cell.column],
               from: grid.rows[cell.row],
               to: grid.rows[cell.row + 1]
           ) {
            neighbors.append(.init(row: cell.row, column: cell.column - 1))
        }
        if cell.column + 1 < columnCount,
           !grid.hasVerticalLine(
               at: grid.columns[cell.column + 1],
               from: grid.rows[cell.row],
               to: grid.rows[cell.row + 1]
           ) {
            neighbors.append(.init(row: cell.row, column: cell.column + 1))
        }
        if cell.row > 0,
           !grid.hasHorizontalLine(
               at: grid.rows[cell.row],
               from: grid.columns[cell.column],
               to: grid.columns[cell.column + 1]
           ) {
            neighbors.append(.init(row: cell.row - 1, column: cell.column))
        }
        if cell.row + 1 < rowCount,
           !grid.hasHorizontalLine(
               at: grid.rows[cell.row + 1],
               from: grid.columns[cell.column],
               to: grid.columns[cell.column + 1]
           ) {
            neighbors.append(.init(row: cell.row + 1, column: cell.column))
        }
        return neighbors
    }

    private static func interval(containing value: Int, in boundaries: [Int]) -> Int? {
        boundaries.indices.dropLast().first { value >= boundaries[$0] && value <= boundaries[$0 + 1] }
    }

    private static func outsideRow(from row: TableRow, grid: ImageGrid) -> [String] {
        var values = Array(repeating: "", count: grid.columns.count - 1)
        for fragment in row.fragments.sorted(by: { $0.boundingBox.minX < $1.boundingBox.minX }) {
            let x = Int(fragment.boundingBox.midX * CGFloat(grid.width))
            let column = interval(containing: x, in: grid.columns)
                ?? (x < grid.columns[0] ? 0 : values.count - 1)
            values[column] += values[column].isEmpty ? fragment.text : " \(fragment.text)"
        }
        return values
    }

    private static func outsideRowHeight(for row: TableRow, imageHeight: Int) -> Double {
        min(max(Double(row.averageHeight * CGFloat(imageHeight)) * 0.75 + 8, 18), 42)
    }

    private static func text(from fragments: [ScreenshotRecognizedFragment]) -> String {
        tableRows(from: fragments)
            .sorted { $0.centerY > $1.centerY }
            .map { row in
                row.fragments.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                    .map(\.text).joined(separator: " ")
            }
            .joined(separator: "\n")
    }

    private static func tableRows(from fragments: [ScreenshotRecognizedFragment]) -> [TableRow] {
        var rows: [TableRow] = []
        for fragment in fragments.sorted(by: readingOrder) {
            let bestIndex = rows.indices.min { left, right in
                abs(rows[left].centerY - fragment.boundingBox.midY)
                    < abs(rows[right].centerY - fragment.boundingBox.midY)
            }
            if let bestIndex {
                let row = rows[bestIndex]
                let tolerance = max(row.averageHeight, fragment.boundingBox.height) * 0.65
                if abs(row.centerY - fragment.boundingBox.midY) <= tolerance {
                    rows[bestIndex].fragments.append(fragment)
                    continue
                }
            }
            rows.append(TableRow(fragments: [fragment]))
        }
        return rows
    }

    private static func columnAnchors(in rows: [TableRow]) -> [CGFloat] {
        let fragments = rows.filter { $0.fragments.count > 1 }.flatMap(\.fragments)
        let source = fragments.isEmpty ? rows.flatMap(\.fragments) : fragments
        let widths = source.map(\.boundingBox.width).filter { $0 > 0 }.sorted()
        guard !widths.isEmpty else { return [] }
        let tolerance = max(widths[widths.count / 2] * 0.6, 0.01)
        var anchors: [[CGFloat]] = []
        for position in source.map(\.boundingBox.minX).sorted() {
            if let index = anchors.indices.last,
               position - (anchors[index].reduce(0, +) / CGFloat(anchors[index].count)) <= tolerance {
                anchors[index].append(position)
            } else {
                anchors.append([position])
            }
        }
        return anchors.map { $0.reduce(0, +) / CGFloat($0.count) }
    }

    private static func mergeVerticalLabels(
        in cells: inout [[String]],
        rows: [TableRow]
    ) -> [ScreenshotRecognizedTable.Merge] {
        guard let columnCount = cells.first?.count else { return [] }
        var merges: [ScreenshotRecognizedTable.Merge] = []
        for column in 0..<columnCount {
            var run: [Int] = []
            for row in cells.indices {
                let value = cells[row][column]
                if value.count == 1,
                   !value.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains),
                   let previous = run.last,
                   rows[previous].centerY - rows[row].centerY
                        <= max(rows[previous].averageHeight, rows[row].averageHeight) * 2.2 {
                    run.append(row)
                } else {
                    mergeVerticalLabelRun(&cells, column: column, rows: run, merges: &merges)
                    run = value.count == 1 && !value.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
                        ? [row]
                        : []
                }
            }
            mergeVerticalLabelRun(&cells, column: column, rows: run, merges: &merges)
        }
        return merges
    }

    private static func mergeVerticalLabelRun(
        _ cells: inout [[String]],
        column: Int,
        rows: [Int],
        merges: inout [ScreenshotRecognizedTable.Merge]
    ) {
        guard rows.count >= 3 else { return }
        cells[rows[0]][column] = rows.map { cells[$0][column] }.joined()
        for row in rows.dropFirst() {
            cells[row][column] = ""
        }
        merges.append(ScreenshotRecognizedTable.Merge(
            row: rows[0],
            column: column,
            rowSpan: rows.count,
            columnSpan: 1
        ))
    }

    private static func readingOrder(
        _ left: ScreenshotRecognizedFragment,
        _ right: ScreenshotRecognizedFragment
    ) -> Bool {
        let tolerance = max(left.boundingBox.height, right.boundingBox.height) * 0.45
        if abs(left.boundingBox.midY - right.boundingBox.midY) <= tolerance {
            return left.boundingBox.minX < right.boundingBox.minX
        }
        return left.boundingBox.midY > right.boundingBox.midY
    }

}

enum ScreenshotXLSXExporter {
    enum ExportError: LocalizedError {
        case archiveFailed(String)

        var errorDescription: String? {
            switch self {
            case let .archiveFailed(message):
                "无法生成 XLSX：\(message)"
            }
        }
    }

    static func write(_ table: ScreenshotRecognizedTable, to destination: URL) throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("zisla-xlsx-\(UUID().uuidString)", isDirectory: true)
        let package = temporaryRoot.appendingPathComponent("package", isDirectory: true)
        let relationships = package.appendingPathComponent("_rels", isDirectory: true)
        let workbook = package.appendingPathComponent("xl", isDirectory: true)
        let workbookRelationships = workbook.appendingPathComponent("_rels", isDirectory: true)
        let worksheets = workbook.appendingPathComponent("worksheets", isDirectory: true)
        let archive = temporaryRoot.appendingPathComponent("output.xlsx")
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        try fileManager.createDirectory(at: relationships, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workbookRelationships, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worksheets, withIntermediateDirectories: true)
        try write(contentTypesXML, to: package.appendingPathComponent("[Content_Types].xml"))
        try write(rootRelationshipsXML, to: relationships.appendingPathComponent(".rels"))
        try write(workbookXML, to: workbook.appendingPathComponent("workbook.xml"))
        try write(workbookRelationshipsXML, to: workbookRelationships.appendingPathComponent("workbook.xml.rels"))
        try write(stylesXML, to: workbook.appendingPathComponent("styles.xml"))
        try write(worksheetXML(for: table), to: worksheets.appendingPathComponent("sheet1.xml"))

        let output = try AIAgentProcessRunner.runSynchronously(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-q", "-r", archive.path, "[Content_Types].xml", "_rels", "xl"],
            workingDirectoryURL: package,
            timeout: 5 * 60,
            maximumOutputBytes: 1,
            maximumErrorBytes: 256 * 1_024
        )
        if output.didTimeout {
            throw ExportError.archiveFailed("压缩操作超时")
        }
        guard output.status == 0 else {
            throw ExportError.archiveFailed(output.standardError)
        }
        try Data(contentsOf: archive).write(to: destination, options: .atomic)
    }

    static func worksheetXML(for table: ScreenshotRecognizedTable) -> String {
        let columnCount = max(table.rows.map(\.count).max() ?? 0, 1)
        let rowCount = max(table.rows.count, 1)
        let columns = (0..<columnCount).map { column in
            let width = table.columnWidths.indices.contains(column)
                ? table.columnWidths[column]
                : min(max(Double(table.rows.compactMap {
                    $0.indices.contains(column) ? $0[column].count : nil
                }.max() ?? 0) + 2, 10), 48)
            return "<col min=\"\(column + 1)\" max=\"\(column + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
        }.joined()
        let sheetRows = table.rows.enumerated().map { rowIndex, row in
            let cells = (0..<columnCount).map { column in
                cellXML(
                    row: rowIndex,
                    column: column,
                    value: row.indices.contains(column) ? row[column] : "",
                    table: table
                )
            }.joined()
            let height = table.rowHeights.indices.contains(rowIndex) ? table.rowHeights[rowIndex] : 24
            return "<row r=\"\(rowIndex + 1)\" ht=\"\(height)\" customHeight=\"1\">\(cells)</row>"
        }.joined()
        let mergeReferences = Array(Set(table.merges.compactMap { mergeReference($0, table: table) })).sorted()
        let mergeXML = mergeReferences.isEmpty
            ? ""
            : "<mergeCells count=\"\(mergeReferences.count)\">"
                + mergeReferences.map { "<mergeCell ref=\"\($0)\"/>" }.joined()
                + "</mergeCells>"
        let dimension = "A1:\(cellReference(row: rowCount - 1, column: columnCount - 1))"
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <dimension ref="\(dimension)"/>
          <sheetViews><sheetView showGridLines="0" workbookViewId="0"/></sheetViews>
          <sheetFormatPr defaultRowHeight="24"/>
          <cols>\(columns)</cols>
          <sheetData>\(sheetRows)</sheetData>
          \(mergeXML)
        </worksheet>
        """
    }

    private static func cellXML(
        row: Int,
        column: Int,
        value: String,
        table: ScreenshotRecognizedTable
    ) -> String {
        let reference = cellReference(row: row, column: column)
        let style: Int
        if table.titleRows.contains(row) {
            style = 4
        } else if table.verticalCells.contains(.init(row: row, column: column)) {
            style = 3
        } else if table.gridRowRange?.contains(row) ?? true {
            style = shouldCenter(value) ? 2 : 1
        } else {
            style = 0
        }
        guard !value.isEmpty else { return "<c r=\"\(reference)\" s=\"\(style)\"/>" }
        if isNumber(value) {
            return "<c r=\"\(reference)\" s=\"\(style)\"><v>\(value)</v></c>"
        }
        return "<c r=\"\(reference)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escapedXML(value))</t></is></c>"
    }

    private static func shouldCenter(_ value: String) -> Bool {
        value.isEmpty
            || isNumber(value)
            || (value.count <= 10 && value.rangeOfCharacter(from: CharacterSet(charactersIn: "，、,。；;")) == nil)
    }

    private static func isNumber(_ value: String) -> Bool {
        guard value.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains),
              value.unicodeScalars.allSatisfy(CharacterSet(charactersIn: "+-.0123456789").contains),
              Double(value) != nil
        else { return false }
        return !(value.count > 1 && value.first == "0" && !value.hasPrefix("0."))
    }

    private static func mergeReference(
        _ merge: ScreenshotRecognizedTable.Merge,
        table: ScreenshotRecognizedTable
    ) -> String? {
        guard merge.row >= 0,
              merge.column >= 0,
              merge.rowSpan > 0,
              merge.columnSpan > 0,
              merge.row + merge.rowSpan <= table.rows.count,
              merge.column + merge.columnSpan <= (table.rows.map(\.count).max() ?? 0),
              merge.rowSpan > 1 || merge.columnSpan > 1
        else { return nil }
        return "\(cellReference(row: merge.row, column: merge.column)):"
            + cellReference(
                row: merge.row + merge.rowSpan - 1,
                column: merge.column + merge.columnSpan - 1
            )
    }

    private static func cellReference(row: Int, column: Int) -> String {
        var value = column + 1
        var name = ""
        while value > 0 {
            value -= 1
            name = String(UnicodeScalar(65 + value % 26)!) + name
            value /= 26
        }
        return "\(name)\(row + 1)"
    }

    private static func escapedXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func write(_ value: String, to url: URL) throws {
        try Data(value.utf8).write(to: url, options: .atomic)
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets><sheet name="识别表格" sheetId="1" r:id="rId1"/></sheets>
    </workbook>
    """

    private static let workbookRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <fonts count="2"><font><sz val="11"/><name val="PingFang SC"/></font><font><b/><sz val="18"/><name val="PingFang SC"/></font></fonts>
      <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
      <borders count="2"><border/><border><left style="thin"/><right style="thin"/><top style="thin"/><bottom style="thin"/><diagonal/></border></borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" textRotation="255" wrapText="1"/></xf><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf></cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """
}

struct ScreenshotEditorOverlayConfiguration {
    let backgroundImage: NSImage
    let initialSelection: CGRect
    let cropImage: (CGRect) -> NSImage?
}

private struct ScreenshotOutlinedText: NSViewRepresentable {
    let text: String
    let color: ScreenshotRGBA
    let fontSize: CGFloat

    func makeNSView(context: Context) -> ScreenshotOutlinedTextView {
        ScreenshotOutlinedTextView(
            text: text,
            color: color,
            fontSize: fontSize
        )
    }

    func updateNSView(_ nsView: ScreenshotOutlinedTextView, context: Context) {
        nsView.update(text: text, color: color, fontSize: fontSize)
    }
}

private final class ScreenshotOutlinedTextView: NSView {
    private var text = ""
    private var color = ScreenshotRGBA.accent
    private var fontSize = ScreenshotTextRendering.defaultFontSize

    override var isOpaque: Bool { false }

    init(text: String, color: ScreenshotRGBA, fontSize: CGFloat) {
        super.init(frame: .zero)
        update(text: text, color: color, fontSize: fontSize)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func update(text: String, color: ScreenshotRGBA, fontSize: CGFloat) {
        self.text = text
        self.color = color
        self.fontSize = fontSize
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        ScreenshotTextRendering.draw(
            text,
            color: color,
            fontSize: fontSize,
            in: bounds
        )
    }
}

private final class ScreenshotInlineTextView: NSTextView {
    var placeholder = ""
    var placeholderColor = NSColor.labelColor
    var onCancel: () -> Void = {}

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        (placeholder as NSString).draw(
            at: .zero,
            withAttributes: [
                .font: font ?? NSFont.systemFont(ofSize: ScreenshotTextRendering.defaultFontSize),
                .foregroundColor: placeholderColor,
            ]
        )
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}

private struct ScreenshotInlineTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let color: ScreenshotRGBA
    let placeholderColor: ScreenshotRGBA
    let fontSize: CGFloat
    let width: CGFloat
    let onCancel: () -> Void
    let onTextChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ScreenshotInlineTextView {
        let textView = ScreenshotInlineTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.onCancel = onCancel
        return textView
    }

    func updateNSView(_ textView: ScreenshotInlineTextView, context: Context) {
        context.coordinator.parent = self
        textView.placeholder = "输入文字"
        textView.placeholderColor = placeholderColor.nsColor.withAlphaComponent(
            placeholderColor.alpha * ScreenshotInlineTextLayout.placeholderOpacity
        )
        textView.textContainer?.containerSize = NSSize(
            width: max(width, 1),
            height: .greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        if textView.string != text {
            textView.string = text
        }

        let font = ScreenshotTextRendering.font(for: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color.nsColor,
        ]
        textView.font = font
        textView.textColor = color.nsColor
        textView.insertionPointColor = color.nsColor
        textView.typingAttributes = attributes
        textView.textStorage?.setAttributes(
            attributes,
            range: NSRange(location: 0, length: (textView.string as NSString).length)
        )
        textView.needsDisplay = true

        if isFocused {
            DispatchQueue.main.async {
                guard textView.window?.firstResponder !== textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScreenshotInlineTextEditor

        init(_ parent: ScreenshotInlineTextEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onTextChange(textView.string)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }
    }
}

/// Presents the PNG save panel shared by the editor toolbar and the ⌘S shortcut.
@MainActor
enum ScreenshotImageExport {
    /// - Parameter status: Receives the result message, or `nil` when the panel closes without writing a file.
    static func presentSavePanel(
        for data: Data,
        status: @escaping @MainActor (String?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "截图.png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let response: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                Task { @MainActor in status(nil) }
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                Task { @MainActor in status("已保存：\(url.lastPathComponent)") }
            } catch {
                Task { @MainActor in status("保存失败：\(error.localizedDescription)") }
            }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.isVisible {
            panel.beginSheetModal(for: window, completionHandler: response)
        } else {
            WindowPlacement.prepareModal(panel)
            panel.begin(completionHandler: response)
        }
    }
}

struct ScreenshotEditorView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @ObservedObject var model: ScreenshotEditorModel
    @ObservedObject var selectionState: ScreenshotAnnotationSelectionState
    let overlayConfiguration: ScreenshotEditorOverlayConfiguration?
    let toolbarOnly: Bool
    let onClose: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onPinToggle: (Bool) -> Void
    let onLongCapture: () -> Void
    let onLongCaptureFinish: () -> Void

    @State private var draftPoints: [CGPoint] = []
    @State private var draftRect = CGRect.zero
    @State private var textDraft = ""
    @State private var inlineTextPlaceholderColor = ScreenshotRGBA.black
    @State private var inlineTextID: UUID?
    @State private var inlineTextIsNew = false
    @State private var inlineTextFocused = false
    @State private var activeAnnotationEdit: ActiveAnnotationEdit?
    @State private var editPreview: ScreenshotAnnotation?
    @State private var activeToolMenuID: ScreenshotTool?
    @State private var statusMessage: String?
    @State private var selectionRect: CGRect
    @State private var resizeStartRect: CGRect?
    @State private var toolbarCenter: CGPoint?
    @State private var canvasZoom: CGFloat = 1
    @State private var canvasOffset = CGSize.zero

    private static let canvasZoomRange: ClosedRange<CGFloat> = 0.5...4

    private struct ActiveAnnotationEdit {
        let id: UUID
        let original: ScreenshotAnnotation
        let handle: ScreenshotAnnotationEditHandle?
        let startPoint: CGPoint
    }

    private var toolbarControlCount: Int {
        13
            + (model.canUndo ? 1 : 0)
            + (model.canRedo ? 1 : 0)
            + (model.isLongCapturePreviewing ? 2 : 0)
            + (model.hasLongCaptureResult && !model.isLongCapturePreviewing ? 2 : 0)
    }

    init(
        model: ScreenshotEditorModel,
        selectionState: ScreenshotAnnotationSelectionState,
        overlayConfiguration: ScreenshotEditorOverlayConfiguration? = nil,
        toolbarOnly: Bool = false,
        onClose: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void = {},
        onPinToggle: @escaping (Bool) -> Void,
        onLongCapture: @escaping () -> Void,
        onLongCaptureFinish: @escaping () -> Void = {}
    ) {
        self.model = model
        self.selectionState = selectionState
        self.overlayConfiguration = overlayConfiguration
        self.toolbarOnly = toolbarOnly
        self.onClose = onClose
        self.onCopy = onCopy
        self.onSave = onSave
        self.onPinToggle = onPinToggle
        self.onLongCapture = onLongCapture
        self.onLongCaptureFinish = onLongCaptureFinish
        _selectionRect = State(initialValue: overlayConfiguration?.initialSelection.standardized ?? .zero)
    }

    var body: some View {
        Group {
            if toolbarOnly {
                toolbarOnlyContent
            } else {
                editorContent
            }
        }
        .onChange(of: model.statusMessage) { _, newValue in
            statusMessage = newValue
        }
        .onChange(of: model.hasLongCaptureResult) { _, _ in
            canvasZoom = 1
            canvasOffset = .zero
        }
        .onChange(of: selectionState.selectedAnnotationID) { _, newValue in
            guard let newValue else {
                editPreview = nil
                activeAnnotationEdit = nil
                return
            }
            guard let annotation = model.annotations.first(where: { $0.id == newValue }) else { return }
            model.color = annotation.color
            switch annotation.kind {
            case .rectangle, .ellipse:
                model.lineWidth = annotation.lineWidth
            case .arrow:
                model.arrowStyle = annotation.arrowStyle
            case .text, .emoji:
                model.fontSize = annotation.fontSize
            case .mosaic:
                model.lineWidth = annotation.lineWidth
                switch annotation.obscureEffect {
                case .pixelate:
                    model.pixelateStrength = annotation.obscurePixelateStrength
                    model.mosaicBlurStrength = annotation.obscureBlurStrength
                case .blur:
                    model.blurStrength = annotation.obscureBlurStrength
                }
            default:
                break
            }
        }
        .onChange(of: model.color) { _, newValue in
            guard let annotationID = selectionState.selectedAnnotationID else { return }
            model.applySelectedStyle(to: annotationID, color: newValue)
        }
        .onChange(of: model.lineWidth) { _, newValue in
            guard let annotationID = selectionState.selectedAnnotationID else { return }
            model.applySelectedStyle(to: annotationID, lineWidth: newValue)
        }
        .onChange(of: model.arrowStyle) { _, newValue in
            guard let annotationID = selectionState.selectedAnnotationID else { return }
            model.applySelectedStyle(to: annotationID, arrowStyle: newValue)
        }
        .onChange(of: model.fontSize) { _, newValue in
            guard let annotationID = selectionState.selectedAnnotationID else { return }
            model.applySelectedStyle(to: annotationID, fontSize: newValue)
        }
        .onChange(of: model.pixelateStrength) { _, newValue in
            applyObscureStrength(newValue, ifSelectedRegionUses: .pixelate)
        }
        .onChange(of: model.blurStrength) { _, newValue in
            applyObscureStrength(newValue, ifSelectedRegionUses: .blur)
        }
        .onChange(of: model.mosaicBlurStrength) { _, newValue in
            applyObscureBlurStrength(newValue, ifSelectedRegionUses: .pixelate)
        }
    }

    private var toolbarOnlyContent: some View {
        GeometryReader { proxy in
            toolbar(viewportWidth: proxy.size.width)
        }
        .frame(height: ScreenshotToolbarLayout.height)
    }

    @ViewBuilder
    private var editorContent: some View {
        if let overlayConfiguration {
            overlayEditor(configuration: overlayConfiguration)
        } else {
            windowEditor
        }
    }

    private var windowEditor: some View {
        VStack(spacing: 0) {
            header
            Divider()
            canvas(showsImage: true)
            Divider()
            standaloneToolbar
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(.regularMaterial)
    }

    private var standaloneToolbar: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let toolbarSize = CGSize(
                width: ScreenshotToolbarLayout.viewportWidth(
                    availableWidth: proxy.size.width,
                    controlCount: toolbarControlCount
                ),
                height: ScreenshotToolbarLayout.height
            )
            let restingCenter = ScreenshotToolbarLayout.clampedCenter(
                toolbarCenter ?? CGPoint(x: bounds.midX, y: bounds.midY),
                toolbarSize: toolbarSize,
                in: bounds
            )

            ScreenshotToolbarDragWrapper(
                restingCenter: restingCenter,
                toolbarSize: toolbarSize,
                bounds: bounds,
                onDragEnd: { newCenter in
                    toolbarCenter = newCenter
                }
            ) {
                toolbar(viewportWidth: toolbarSize.width)
            }
        }
        .frame(height: ScreenshotToolbarLayout.height)
    }

    private func overlayEditor(
        configuration: ScreenshotEditorOverlayConfiguration
    ) -> some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let toolbarSize = CGSize(
                width: ScreenshotToolbarLayout.viewportWidth(
                    availableWidth: proxy.size.width,
                    controlCount: toolbarControlCount
                ),
                height: ScreenshotToolbarLayout.height
            )
            let defaultToolbarCenter = overlayToolbarCenter(
                toolbarSize: toolbarSize,
                bounds: bounds
            )
            let restingToolbarCenter = ScreenshotToolbarLayout.clampedCenter(
                toolbarCenter ?? defaultToolbarCenter,
                toolbarSize: toolbarSize,
                in: bounds
            )
            let toolbarFrame = CGRect(
                x: restingToolbarCenter.x - toolbarSize.width / 2,
                y: restingToolbarCenter.y - toolbarSize.height / 2,
                width: toolbarSize.width,
                height: toolbarSize.height
            )
            let popoverEdge = ScreenshotToolPopoverPlacement.preferredEdge(
                toolbarFrame: toolbarFrame,
                selectionRect: selectionRect,
                bounds: bounds
            )

            ZStack(alignment: .topLeading) {
                ScreenshotBackingImage(image: configuration.backgroundImage)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .allowsHitTesting(false)

                Color.black.opacity(0.44)
                    .allowsHitTesting(false)

                ScreenshotBackingImage(image: configuration.backgroundImage)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .mask {
                        Rectangle()
                            .frame(width: selectionRect.width, height: selectionRect.height)
                            .position(selectionRect.center)
                    }
                    .allowsHitTesting(false)

                canvas(showsImage: model.hasLongCaptureResult)
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(selectionRect.center)
                    .clipped()

                selectionBorder

                ForEach(ScreenshotSelectionHandle.allCases, id: \.self) { handle in
                    selectionHandle(handle, bounds: bounds)
                }

                ScreenshotToolbarDragWrapper(
                    restingCenter: restingToolbarCenter,
                    toolbarSize: toolbarSize,
                    bounds: bounds,
                    onDragEnd: { newCenter in
                        toolbarCenter = newCenter
                    }
                ) {
                    toolbar(viewportWidth: toolbarSize.width, popoverEdge: popoverEdge)
                }

                ScreenshotSelectionSizeBadge(
                    selection: selectionRect,
                    bounds: proxy.size
                )

            }
            .background(Color.black)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera.viewfinder")
                .foregroundStyle(Color.accentColor)
            Text("截图编辑")
                .font(.system(size: 14, weight: .semibold))
            Text("\(Int(model.image.size.width.rounded())) × \(Int(model.image.size.height.rounded()))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            if let message = statusMessage ?? model.statusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button(action: onClose) {
                Label("关闭", systemImage: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .frame(height: 26)
            }
            .buttonStyle(.plain)
            .help("关闭截图编辑器")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func canvas(showsImage: Bool) -> some View {
        GeometryReader { proxy in
            let geometry = ScreenshotCanvasGeometry(
                canvasSize: proxy.size,
                imageSize: model.image.size,
                zoom: model.hasLongCaptureResult ? canvasZoom : 1,
                offset: model.hasLongCaptureResult ? canvasOffset : .zero
            )
            let mosaicDraft = mosaicDraftAnnotation
            let previewImage = mosaicDraft.map { model.imageApplyingMosaics(adding: $0) }
                ?? model.mosaicPreviewImage

            ZStack(alignment: .topLeading) {
                if showsImage {
                    Color.black.opacity(0.12)
                }
                if showsImage || model.annotations.contains(where: { $0.kind == .mosaic }) || mosaicDraft != nil {
                    Image(nsImage: previewImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: geometry.renderedSize.width, height: geometry.renderedSize.height)
                        .position(
                            x: geometry.origin.x + geometry.renderedSize.width / 2,
                            y: geometry.origin.y + geometry.renderedSize.height / 2
                        )
                }

                ForEach(model.annotations) { storedAnnotation in
                    let annotation = editPreview?.id == storedAnnotation.id
                        ? editPreview!
                        : storedAnnotation
                    annotationView(annotation, geometry: geometry)
                }

                if let selectedAnnotationID = selectionState.selectedAnnotationID,
                   let selected = (editPreview?.id == selectedAnnotationID
                       ? editPreview
                       : model.annotations.first(where: { $0.id == selectedAnnotationID })) {
                    annotationSelectionOverlay(inlineTextPreview(selected), geometry: geometry)
                }

                draftAnnotation(geometry: geometry)

                ScreenshotPointerInteractionView(
                    onDrag: { start, current, isComplete in
                        handleCanvasDrag(
                            from: start,
                            to: current,
                            isComplete: isComplete,
                            geometry: geometry
                        )
                    },
                    onDragBegan: {
                        // A lost mouse-up leaves the previous stroke pending; pressing again keeps
                        // it instead of folding its geometry into the next one.
                        model.commitPendingAnnotationDraft()
                        draftPoints.removeAll(keepingCapacity: true)
                        draftRect = .zero
                    },
                    onDoubleClick: { location in
                        let point = geometry.imagePoint(from: location)
                        guard let annotation = editableAnnotation(at: point), annotation.kind == .text else {
                            return
                        }
                        beginInlineTextEditing(annotation)
                    },
                    onMagnify: { magnification in
                        guard model.hasLongCaptureResult else { return }
                        adjustCanvasZoom(by: magnification)
                    },
                    onScrollPan: { delta in
                        guard model.hasLongCaptureResult else { return }
                        canvasOffset = geometry.clampedOffset(CGSize(
                            width: canvasOffset.width + delta.width,
                            height: canvasOffset.height + delta.height
                        ))
                    }
                )

                if let inlineTextID,
                   let annotation = model.annotations.first(where: { $0.id == inlineTextID }) {
                    inlineTextField(annotation, geometry: geometry)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var selectionBorder: some View {
        Rectangle()
            .stroke(Color.accentColor, lineWidth: 2)
            .frame(width: selectionRect.width, height: selectionRect.height)
            .position(selectionRect.center)
            .allowsHitTesting(false)
    }

    private func selectionHandle(_ handle: ScreenshotSelectionHandle, bounds: CGRect) -> some View {
        Circle()
            .fill(Color.accentColor)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .frame(width: 12, height: 12)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .position(ScreenshotSelectionGeometry.position(of: handle, in: selectionRect))
            .highPriorityGesture(selectionResizeGesture(handle: handle, bounds: bounds))
    }

    private func selectionResizeGesture(
        handle: ScreenshotSelectionHandle,
        bounds: CGRect
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let source = resizeStartRect ?? selectionRect
                if resizeStartRect == nil { resizeStartRect = source }
                selectionRect = ScreenshotSelectionGeometry.resized(
                    source,
                    using: handle,
                    translation: value.translation,
                    within: bounds
                )
            }
            .onEnded { _ in
                let previous = resizeStartRect ?? selectionRect
                resizeStartRect = nil
                commitSelectionChange(from: previous, to: selectionRect)
            }
    }

    private func commitSelectionChange(from previous: CGRect, to next: CGRect) {
        guard previous != next, let overlayConfiguration else { return }
        guard let image = overlayConfiguration.cropImage(next) else {
            selectionRect = previous
            model.statusMessage = "选区无效"
            return
        }
        model.replaceCapture(
            with: image,
            translatingAnnotationsBy: CGSize(
                width: previous.minX - next.minX,
                height: previous.minY - next.minY
            )
        )
    }

    private func overlayToolbarCenter(toolbarSize: CGSize, bounds: CGRect) -> CGPoint {
        let margin: CGFloat = 8
        let minimumX = bounds.minX + toolbarSize.width / 2 + margin
        let maximumX = bounds.maxX - toolbarSize.width / 2 - margin
        let x = min(max(selectionRect.midX, minimumX), maximumX)
        let below = selectionRect.maxY + margin + toolbarSize.height / 2
        let above = selectionRect.minY - margin - toolbarSize.height / 2
        let y: CGFloat
        if below + toolbarSize.height / 2 + margin <= bounds.maxY {
            y = below
        } else if above - toolbarSize.height / 2 - margin >= bounds.minY {
            y = above
        } else {
            y = min(
                bounds.maxY - toolbarSize.height / 2 - margin,
                max(bounds.minY + toolbarSize.height / 2 + margin, selectionRect.maxY - toolbarSize.height / 2 - margin)
            )
        }
        return CGPoint(x: x, y: y)
    }

    @ViewBuilder
    private func annotationView(
        _ annotation: ScreenshotAnnotation,
        geometry: ScreenshotCanvasGeometry
    ) -> some View {
        let color = annotation.color.swiftUIColor
        switch annotation.kind {
        case .rectangle:
            Rectangle()
                .stroke(color, lineWidth: max(1, annotation.lineWidth * geometry.scale))
                .frame(
                    width: geometry.canvasRect(from: annotation.rect).width,
                    height: geometry.canvasRect(from: annotation.rect).height
                )
                .rotationEffect(.radians(Double(annotation.rotation)))
                .position(geometry.canvasPoint(from: annotation.rect.standardized.center))
        case .ellipse:
            Ellipse()
                .stroke(color, lineWidth: max(1, annotation.lineWidth * geometry.scale))
                .frame(
                    width: geometry.canvasRect(from: annotation.rect).width,
                    height: geometry.canvasRect(from: annotation.rect).height
                )
                .position(geometry.canvasPoint(from: annotation.rect.standardized.center))
                .rotationEffect(.radians(Double(annotation.rotation)))
        case .brush:
            strokePath(
                annotation.points,
                geometry: geometry,
                color: color,
                lineWidth: annotation.lineWidth
            )
        case .arrow:
            let bounds = ScreenshotAnnotationGeometry.bounds(for: annotation)
            arrowView(
                annotation.points,
                geometry: geometry,
                color: color,
                lineWidth: annotation.lineWidth,
                style: annotation.arrowStyle,
                rotation: annotation.rotation,
                rotationCenter: bounds.center
            )
        case .number:
            if let point = annotation.points.first {
                let diameter = ScreenshotAnnotationGeometry.numberDiameter(for: annotation.lineWidth)
                    * geometry.scale
                ZStack {
                    Circle().fill(color)
                    Circle().stroke(.white, lineWidth: max(1, 1.5 * geometry.scale))
                    Text("\(annotation.number)")
                        .font(.system(
                            size: max(10, annotation.lineWidth * 3.2) * geometry.scale,
                            weight: .bold
                        ))
                        .foregroundStyle(.white)
                }
                .frame(width: diameter, height: diameter)
                .position(geometry.canvasPoint(from: point))
            }
        case .text:
            if annotation.points.first != nil {
                let bounds = ScreenshotAnnotationGeometry.bounds(for: annotation)
                let canvasBounds = geometry.canvasRect(from: bounds)
                ScreenshotOutlinedText(
                    text: annotation.text,
                    color: annotation.color,
                    fontSize: annotation.fontSize * geometry.scale
                )
                    .frame(
                        width: canvasBounds.width,
                        height: canvasBounds.height
                    )
                    .position(geometry.canvasPoint(from: bounds.center))
                    .rotationEffect(.radians(Double(annotation.rotation)))
            }
        case .emoji:
            if annotation.points.first != nil {
                let bounds = ScreenshotAnnotationGeometry.bounds(for: annotation)
                let canvasBounds = geometry.canvasRect(from: bounds)
                Text(annotation.text)
                    .font(.system(
                        size: ScreenshotAnnotationGeometry.emojiDiameter(for: annotation.fontSize) * geometry.scale,
                        weight: .semibold
                    ))
                    .frame(width: canvasBounds.width, height: canvasBounds.height)
                    .position(geometry.canvasPoint(from: bounds.center))
                    .rotationEffect(.radians(Double(annotation.rotation)))
            }
        case .mosaic:
            EmptyView()
        }
    }

    private func annotationSelectionOverlay(
        _ annotation: ScreenshotAnnotation,
        geometry: ScreenshotCanvasGeometry
    ) -> some View {
        let rect = ScreenshotAnnotationGeometry.bounds(for: annotation)
        let canvasRect = geometry.canvasRect(from: rect)
        let handleSize = max(8, 10 * geometry.scale)
        let showRotationHandle = annotation.kind == .rectangle
            || annotation.kind == .text
            || annotation.kind == .arrow
        let rotationDistance = ScreenshotAnnotationGeometry.rotationOffset * geometry.scale
        let handlePoints = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: canvasRect.width, y: 0),
            CGPoint(x: canvasRect.width, y: canvasRect.height),
            CGPoint(x: 0, y: canvasRect.height),
        ] + (annotation.kind == .rectangle ? [
            CGPoint(x: canvasRect.width / 2, y: 0),
            CGPoint(x: canvasRect.width, y: canvasRect.height / 2),
            CGPoint(x: canvasRect.width / 2, y: canvasRect.height),
            CGPoint(x: 0, y: canvasRect.height / 2),
        ] : [])
        return ZStack {
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 1)
            ForEach(Array(handlePoints.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(Color.accentColor)
                    .overlay(Circle().stroke(.white, lineWidth: 1))
                    .frame(width: handleSize, height: handleSize)
                    .position(point)
            }
            if showRotationHandle {
                Path { path in
                    path.move(to: CGPoint(x: canvasRect.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: canvasRect.width / 2, y: -rotationDistance))
                }
                .stroke(Color.accentColor, lineWidth: 1)

                Circle()
                    .fill(Color.accentColor)
                    .overlay(Circle().stroke(.white, lineWidth: 1))
                    .frame(width: handleSize, height: handleSize)
                    .position(x: canvasRect.width / 2, y: -rotationDistance)
            }
        }
        .frame(width: canvasRect.width, height: canvasRect.height)
        .rotationEffect(.radians(Double(annotation.rotation)))
        .position(geometry.canvasPoint(from: rect.center))
        .allowsHitTesting(false)
    }

    private func inlineTextField(
        _ annotation: ScreenshotAnnotation,
        geometry: ScreenshotCanvasGeometry
    ) -> some View {
        let rect = inlineTextRect(for: annotation)
        let canvasRect = geometry.canvasRect(from: rect)
        let height = ScreenshotInlineTextLayout.contentHeight(
            for: textDraft,
            fontSize: annotation.fontSize * geometry.scale,
            width: canvasRect.width
        )
        return ScreenshotInlineTextEditor(
            text: $textDraft,
            isFocused: $inlineTextFocused,
            color: annotation.color,
            placeholderColor: inlineTextPlaceholderColor,
            fontSize: annotation.fontSize * geometry.scale,
            width: canvasRect.width,
            onCancel: cancelInlineText,
            onTextChange: updateInlineTextDraft
        )
            .frame(width: canvasRect.width, height: height)
            .position(x: canvasRect.midX, y: canvasRect.minY + height / 2)
            .onChange(of: inlineTextFocused) { _, isFocused in
                selectionState.isInlineTextEditing = isFocused && inlineTextID != nil
                if !isFocused { commitInlineText() }
            }
            .onAppear {
                DispatchQueue.main.async { inlineTextFocused = true }
            }
    }

    private func inlineTextPreview(_ annotation: ScreenshotAnnotation) -> ScreenshotAnnotation {
        guard inlineTextID == annotation.id, annotation.kind == .text else { return annotation }
        let rect = inlineTextRect(for: annotation)
        let height = ScreenshotInlineTextLayout.contentHeight(
            for: textDraft,
            fontSize: annotation.fontSize,
            width: rect.width
        )
        var preview = annotation
        preview.rect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: height
        )
        return preview
    }

    private func inlineTextRect(for annotation: ScreenshotAnnotation) -> CGRect {
        let rect = ScreenshotAnnotationGeometry.bounds(for: annotation)
        return CGRect(
            x: rect.minX,
            y: rect.minY,
            width: ScreenshotInlineTextLayout.width(
                for: textDraft,
                fontSize: annotation.fontSize,
                from: rect.minX,
                to: model.image.size.width
            ),
            height: rect.height
        )
    }

    private func beginInlineTextEditing(
        _ annotation: ScreenshotAnnotation,
        isNew: Bool = false,
        placeholderColor: ScreenshotRGBA? = nil
    ) {
        selectionState.selectedAnnotationID = annotation.id
        selectionState.isInlineTextEditing = true
        inlineTextID = annotation.id
        inlineTextIsNew = isNew
        inlineTextPlaceholderColor = placeholderColor ?? textPlaceholderColor(for: annotation)
        textDraft = annotation.text
        model.beginTextDraft(id: annotation.id, text: annotation.text, isNew: isNew)
        DispatchQueue.main.async { inlineTextFocused = true }
    }

    private func updateInlineTextDraft(_ text: String) {
        guard let inlineTextID else { return }
        model.updateTextDraft(id: inlineTextID, text: text, isNew: inlineTextIsNew)
    }

    private func textPlaceholderColor(for annotation: ScreenshotAnnotation) -> ScreenshotRGBA {
        guard let point = annotation.points.first,
              let cgImage = model.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let background = ScreenshotCaptureService.pixelColor(
                  at: point,
                  in: cgImage,
                  screenSize: model.image.size
              )
        else { return .black }
        return ScreenshotRGBA.contrastingTextColor(for: background)
    }

    private func commitInlineText() {
        guard let inlineTextID else {
            selectionState.isInlineTextEditing = false
            return
        }
        if model.pendingTextDraft?.id != inlineTextID {
            model.beginTextDraft(id: inlineTextID, text: textDraft, isNew: inlineTextIsNew)
        }
        model.commitPendingTextDraft()
        self.inlineTextID = nil
        inlineTextIsNew = false
        inlineTextFocused = false
        selectionState.isInlineTextEditing = false
    }

    private func cancelInlineText() {
        model.discardPendingTextDraft()
        if inlineTextIsNew, let inlineTextID {
            model.remove(id: inlineTextID, saveUndo: false)
        }
        inlineTextID = nil
        inlineTextIsNew = false
        inlineTextFocused = false
        selectionState.isInlineTextEditing = false
    }

    @ViewBuilder
    private func draftAnnotation(geometry: ScreenshotCanvasGeometry) -> some View {
        if model.tool == .rectangle || model.tool == .ellipse,
           draftRect.width > 1, draftRect.height > 1 {
            let rect = geometry.canvasRect(from: draftRect)
            if model.tool == .rectangle {
                Rectangle()
                    .stroke(
                        model.color.swiftUIColor,
                        style: StrokeStyle(
                            lineWidth: max(1, model.lineWidth * geometry.scale),
                            dash: ScreenshotCanvasStyle.draftDashPattern
                        )
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(geometry.canvasPoint(from: draftRect.standardized.center))
            } else {
                Ellipse()
                    .stroke(
                        model.color.swiftUIColor,
                        style: StrokeStyle(
                            lineWidth: max(1, model.lineWidth * geometry.scale),
                            dash: ScreenshotCanvasStyle.draftDashPattern
                        )
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(geometry.canvasPoint(from: draftRect.standardized.center))
            }
        } else if (model.tool == .brush || model.tool == .arrow), !draftPoints.isEmpty {
            if model.tool == .brush {
                strokePath(
                    draftPoints,
                    geometry: geometry,
                    color: model.color.swiftUIColor,
                    lineWidth: model.lineWidth
                )
            } else if model.tool == .arrow {
                arrowView(
                    draftPoints,
                    geometry: geometry,
                    color: model.color.swiftUIColor,
                    lineWidth: model.lineWidth,
                    style: model.arrowStyle
                )
            }
        }
    }

    private var mosaicDraftAnnotation: ScreenshotAnnotation? {
        // Dragging or resizing a committed region only updates `editPreview`, so feed it through the
        // obscure pass to keep the pixels following the frame instead of snapping on mouse-up.
        if let editPreview, editPreview.kind == .mosaic { return editPreview }
        guard model.tool == .mosaic else { return nil }
        switch model.obscureShape {
        case .rectangle:
            guard draftRect.width > 1, draftRect.height > 1 else { return nil }
            return ScreenshotAnnotation(
                kind: .mosaic,
                rect: draftRect,
                lineWidth: model.lineWidth,
                obscureShape: .rectangle,
                obscureEffect: model.obscureEffect,
                obscureStrength: model.obscureStrength,
                obscureBlurStrength: model.obscureBlurStrength
            )
        case .brush:
            guard draftPoints.count > 1 else { return nil }
            return ScreenshotAnnotation(
                kind: .mosaic,
                points: draftPoints,
                lineWidth: model.lineWidth,
                obscureShape: .brush,
                obscureEffect: model.obscureEffect,
                obscureStrength: model.obscureStrength,
                obscureBlurStrength: model.obscureBlurStrength
            )
        }
    }

    private func strokePath(
        _ points: [CGPoint],
        geometry: ScreenshotCanvasGeometry,
        color: Color,
        lineWidth: CGFloat
    ) -> some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: geometry.canvasPoint(from: first))
            for point in points.dropFirst() {
                path.addLine(to: geometry.canvasPoint(from: point))
            }
        }
        .stroke(
            color,
            style: StrokeStyle(
                lineWidth: max(1, lineWidth * geometry.scale),
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    @ViewBuilder
    private func arrowView(
        _ points: [CGPoint],
        geometry: ScreenshotCanvasGeometry,
        color: Color,
        lineWidth: CGFloat,
        style: ScreenshotArrowStyle,
        rotation: CGFloat = 0,
        rotationCenter: CGPoint? = nil
    ) -> some View {
        if let start = points.first, let end = points.last {
            let rotatedStart = rotationCenter.map {
                ScreenshotAnnotationGeometry.rotatedPoint(start, around: $0, by: rotation)
            } ?? start
            let rotatedEnd = rotationCenter.map {
                ScreenshotAnnotationGeometry.rotatedPoint(end, around: $0, by: rotation)
            } ?? end
            let startPoint = geometry.canvasPoint(from: rotatedStart)
            let endPoint = geometry.canvasPoint(from: rotatedEnd)
            let scaledLineWidth = max(1, lineWidth * geometry.scale)
            let headPoints = ScreenshotArrowGeometry.headPoints(
                from: startPoint,
                to: endPoint,
                lineWidth: scaledLineWidth,
                minimumLength: 8
            )
            if style == .tapered,
               let shaftPoints = ScreenshotArrowGeometry.taperedShaftPoints(
                   from: startPoint,
                   to: endPoint,
                   lineWidth: scaledLineWidth
               ) {
                Path { path in
                    path.move(to: shaftPoints[0])
                    for point in shaftPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                    path.closeSubpath()
                }
                .fill(color)
            } else {
                Path { path in
                    path.move(to: startPoint)
                    path.addLine(to: endPoint)
                }
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: scaledLineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
            Path { path in
                path.move(to: headPoints.tip)
                path.addLine(to: headPoints.left)
                path.move(to: headPoints.tip)
                path.addLine(to: headPoints.right)
            }
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: scaledLineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    private func handleCanvasDrag(
        from startLocation: CGPoint,
        to currentLocation: CGPoint,
        isComplete: Bool,
        geometry: ScreenshotCanvasGeometry
    ) {
        let start = geometry.imagePoint(from: startLocation)
        let point = geometry.imagePoint(from: currentLocation)

        if activeAnnotationEdit == nil,
           editPreview == nil,
           !isComplete,
           let hit = editableAnnotation(at: start) {
            selectionState.selectedAnnotationID = hit.id
            activeAnnotationEdit = ActiveAnnotationEdit(
                id: hit.id,
                original: hit,
                handle: ScreenshotAnnotationGeometry.handle(at: start, in: hit),
                startPoint: start
            )
            editPreview = hit
            return
        }

        if let activeAnnotationEdit {
            let current = ScreenshotAnnotationGeometry.transform(
                activeAnnotationEdit.original,
                handle: activeAnnotationEdit.handle,
                from: activeAnnotationEdit.startPoint,
                to: point,
                textRightEdge: model.image.size.width
            )
            if activeAnnotationEdit.handle == .rotation, !accessibilityReduceMotion {
                withAnimation(ScreenshotCanvasStyle.rotationAnimation) {
                    editPreview = current
                }
            } else {
                editPreview = current
            }
            guard isComplete else {
                model.updatePendingAnnotationDraft(
                    current == activeAnnotationEdit.original ? nil : current
                )
                return
            }
            model.discardPendingAnnotationDraft()
            if current != activeAnnotationEdit.original {
                model.add(current)
            }
            self.activeAnnotationEdit = nil
            self.editPreview = nil
            return
        }

        if !isComplete {
            selectionState.deselect()
        }

        switch model.tool {
        case .rectangle, .ellipse:
            draftRect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
        case .mosaic:
            switch model.obscureShape {
            case .rectangle:
                draftRect = CGRect(
                    x: min(start.x, point.x),
                    y: min(start.y, point.y),
                    width: abs(point.x - start.x),
                    height: abs(point.y - start.y)
                )
            case .brush:
                appendDraftPoint(point)
            }
        case .brush:
            appendDraftPoint(point)
        case .arrow:
            draftPoints = [start, point]
        case .number, .text, .emoji:
            break
        }

        guard isComplete else {
            model.updatePendingAnnotationDraft(committableDraftAnnotation(at: point))
            return
        }
        model.discardPendingAnnotationDraft()
        defer {
            draftPoints.removeAll(keepingCapacity: true)
            draftRect = .zero
        }

        switch model.tool {
        case .rectangle, .ellipse, .mosaic, .brush, .arrow, .number, .emoji:
            guard let annotation = committableDraftAnnotation(at: point) else { return }
            model.add(annotation)
        case .text:
            let placeholderColor: ScreenshotRGBA
            if let cgImage = model.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let background = ScreenshotCaptureService.pixelColor(
                   at: point,
                   in: cgImage,
                   screenSize: model.image.size
               ) {
                placeholderColor = ScreenshotRGBA.contrastingTextColor(for: background)
            } else {
                placeholderColor = .black
            }
            let width = ScreenshotInlineTextLayout.width(
                for: "",
                fontSize: model.fontSize,
                from: point.x,
                to: model.image.size.width
            )
            let height = ScreenshotInlineTextLayout.lineHeight(for: model.fontSize)
            let annotation = ScreenshotAnnotation(
                kind: .text,
                points: [point],
                rect: CGRect(
                    x: point.x,
                    y: point.y - height / 2,
                    width: width,
                    height: height
                ),
                text: "",
                color: model.color,
                lineWidth: model.lineWidth,
                fontSize: model.fontSize
            )
            model.add(annotation, saveUndo: false)
            beginInlineTextEditing(annotation, isNew: true, placeholderColor: placeholderColor)
        }
    }

    /// The annotation the current draft would produce, or `nil` while it stays below the commit
    /// thresholds. Shared by the drag handler and the export fallback so both agree on what counts
    /// as a finished annotation.
    private func committableDraftAnnotation(at point: CGPoint) -> ScreenshotAnnotation? {
        switch model.tool {
        case .rectangle:
            guard draftRect.width > 2, draftRect.height > 2 else { return nil }
            return ScreenshotAnnotation(
                kind: .rectangle,
                rect: draftRect,
                color: model.color,
                lineWidth: model.lineWidth
            )
        case .ellipse:
            guard draftRect.width > 2, draftRect.height > 2 else { return nil }
            return ScreenshotAnnotation(
                kind: .ellipse,
                rect: draftRect,
                color: model.color,
                lineWidth: model.lineWidth
            )
        case .mosaic:
            switch model.obscureShape {
            case .rectangle:
                guard draftRect.width > 2, draftRect.height > 2 else { return nil }
            case .brush:
                guard draftPoints.count > 1 else { return nil }
            }
            return ScreenshotAnnotation(
                kind: .mosaic,
                points: draftPoints,
                rect: draftRect,
                color: model.color,
                lineWidth: model.lineWidth,
                obscureShape: model.obscureShape,
                obscureEffect: model.obscureEffect,
                obscureStrength: model.obscureStrength,
                obscureBlurStrength: model.obscureBlurStrength
            )
        case .brush:
            guard draftPoints.count > 1 else { return nil }
            return ScreenshotAnnotation(
                kind: .brush,
                points: draftPoints,
                color: model.color,
                lineWidth: model.lineWidth
            )
        case .arrow:
            guard draftPoints.count == 2 else { return nil }
            return ScreenshotAnnotation(
                kind: .arrow,
                points: draftPoints,
                color: model.color,
                lineWidth: model.lineWidth,
                arrowStyle: model.arrowStyle
            )
        case .number:
            return model.numberAnnotation(at: point)
        case .emoji:
            return ScreenshotAnnotation(
                kind: .emoji,
                points: [point],
                text: model.selectedEmoji,
                color: model.color,
                lineWidth: model.lineWidth,
                fontSize: ScreenshotAnnotationGeometry.defaultEmojiDiameter
            )
        case .text:
            return nil
        }
    }

    private func editableAnnotation(at point: CGPoint) -> ScreenshotAnnotation? {
        let expectedKinds: Set<ScreenshotAnnotation.Kind> = switch model.tool {
        case .rectangle: [.rectangle]
        case .ellipse: [.ellipse]
        case .brush: [.brush]
        case .arrow: [.arrow]
        case .number: [.number]
        case .text: [.text]
        case .emoji: [.emoji]
        case .mosaic: [.mosaic]
        }
        return model.annotations.reversed().first {
            guard expectedKinds.contains($0.kind) else { return false }
            return ScreenshotAnnotationGeometry.contains(point, in: $0)
                || ScreenshotAnnotationGeometry.handle(at: point, in: $0) != nil
        }
    }

    private func appendDraftPoint(_ point: CGPoint) {
        if draftPoints.last != point {
            draftPoints.append(point)
        }
    }

    private func toolbar(viewportWidth: CGFloat, popoverEdge: Edge = .bottom) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ScreenshotToolbarLayout.spacing) {
                toolbarDragHandle
                ForEach(ScreenshotTool.allCases.filter { $0 != .emoji && $0 != .mosaic }) { tool in
                    toolButtonWithMenu(tool, popoverEdge: popoverEdge)
                }
                obscureButton(popoverEdge: popoverEdge)
                if model.canUndo {
                    iconButton("arrow.uturn.backward", title: "撤销") { model.undo() }
                }
                if model.canRedo {
                    iconButton("arrow.uturn.forward", title: "重做") { model.redo() }
                }
                recognitionMenu
                iconButton(
                    model.isLongCapturePreviewing ? "arrow.clockwise" : "rectangle.on.rectangle",
                    title: model.isLongCapturePreviewing ? "继续" : "长截图"
                ) { onLongCapture() }
                if model.isLongCapturePreviewing {
                    longCaptureDirectionMenu
                    iconButton("checkmark", title: "完成") { onLongCaptureFinish() }
                }
                if model.hasLongCaptureResult {
                    iconButton("minus.magnifyingglass", title: "缩小") {
                        updateCanvasZoom(to: canvasZoom - 0.1)
                    }
                    iconButton("plus.magnifyingglass", title: "放大") {
                        updateCanvasZoom(to: canvasZoom + 0.1)
                    }
                }
                iconButton(model.isPinned ? "pin.fill" : "pin", title: model.isPinned ? "取消置顶" : "钉图") {
                    commitInlineText()
                    model.isPinned.toggle()
                    onPinToggle(model.isPinned)
                }
                iconButton("doc.on.doc", title: "复制") {
                    commitInlineText()
                    onCopy()
                }
                iconButton("square.and.arrow.down", title: "保存") {
                    commitInlineText()
                    onSave()
                }
                iconButton("xmark", title: "关闭") { onClose() }
            }
            .frame(
                width: ScreenshotToolbarLayout.contentWidth(forControlCount: toolbarControlCount)
                    - ScreenshotToolbarLayout.horizontalPadding * 2,
                height: ScreenshotToolbarLayout.height
            )
            .padding(.horizontal, ScreenshotToolbarLayout.horizontalPadding)
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: viewportWidth, height: ScreenshotToolbarLayout.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(
            cornerRadius: ScreenshotToolbarLayout.cornerRadius,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(
                cornerRadius: ScreenshotToolbarLayout.cornerRadius,
                style: .continuous
            )
                .stroke(.white.opacity(ScreenshotToolbarLayout.borderOpacity), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
    }

    private func updateCanvasZoom(to proposedZoom: CGFloat) {
        canvasZoom = min(
            max(proposedZoom, Self.canvasZoomRange.lowerBound),
            Self.canvasZoomRange.upperBound
        )
    }

    private func adjustCanvasZoom(by magnification: CGFloat) {
        updateCanvasZoom(to: ScreenshotPinnedInteraction.scale(
            current: canvasZoom,
            magnification: magnification,
            range: Self.canvasZoomRange
        ))
    }

    private var longCaptureDirectionMenu: some View {
        Menu {
            ForEach(ScreenshotLongCaptureDirection.allCases) { direction in
                Button {
                    model.longCaptureDirection = direction
                } label: {
                    if model.longCaptureDirection == direction {
                        Label(direction.title, systemImage: "checkmark")
                    } else {
                        Label(direction.title, systemImage: direction.symbol)
                    }
                }
            }
        } label: {
            toolbarControlLabel(
                symbol: model.longCaptureDirection.symbol,
                title: model.longCaptureDirection.title,
                selected: true
            )
        }
        .menuStyle(.borderlessButton)
        .help("长截图方向")
    }

    private var toolbarDragHandle: some View {
        ScreenshotToolbarDragDots()
        .frame(
            width: ScreenshotToolbarLayout.dragHandleWidth,
            height: ScreenshotToolbarLayout.controlHeight
        )
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func toolbarSelectionBackground(
        isSelected: Bool,
        cornerRadius: CGFloat
    ) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.fillCard)
                .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
        }
    }

    private func toolButtonWithMenu(_ tool: ScreenshotTool, popoverEdge: Edge) -> some View {
        Button {
            selectTool(tool)
            activeToolMenuID = tool
        } label: {
            HStack(spacing: 3) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(tool.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .bold))
            }
            .frame(
                width: ScreenshotToolbarLayout.controlWidth,
                height: ScreenshotToolbarLayout.controlHeight
            )
            .background {
                toolbarSelectionBackground(isSelected: model.tool == tool, cornerRadius: 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(tool.title)
        .popover(isPresented: Binding(
            get: { activeToolMenuID == tool },
            set: { if !$0 { activeToolMenuID = nil } }
        ), arrowEdge: popoverEdge) {
            toolAttributesMenu(for: tool)
        }
    }

    @ViewBuilder
    private func toolAttributesMenu(for tool: ScreenshotTool) -> some View {
        HStack(spacing: 10) {
            if tool == .rectangle || tool == .ellipse || tool == .brush {
                colorPicker
                Divider().frame(height: 24)
                lineWidthSlider
            } else if tool == .arrow {
                colorPicker
                Divider().frame(height: 24)
                Picker("样式", selection: $model.arrowStyle) {
                    ForEach(ScreenshotArrowStyle.allCases) { style in
                        Label(style.title, systemImage: style.symbol).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .help("箭头样式：\(model.arrowStyle.title)")
                Divider().frame(height: 24)
                lineWidthSlider
            } else if tool == .number {
                colorPicker
                Divider().frame(height: 24)
                HStack(spacing: 8) {
                    Text("大小").font(.system(size: 12, weight: .semibold))
                    Slider(value: $model.lineWidth, in: 1...12, step: 1)
                        .frame(width: 130)
                    Text("\(Int(model.lineWidth.rounded()))")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 18, alignment: .trailing)
                }
            } else if tool == .text {
                colorPicker
                Divider().frame(height: 24)
                fontSizeSlider
            }
        }
        .padding(.horizontal, 12)
        .frame(height: ScreenshotToolbarLayout.height)
    }

    private var colorPicker: some View {
        HStack(spacing: 8) {
            Text("颜色").font(.system(size: 12, weight: .semibold))
            ForEach(Array(Self.colorPresets.enumerated()), id: \.offset) { _, preset in
                Button {
                    model.color = preset
                } label: {
                    Circle()
                        .fill(preset.swiftUIColor)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(
                            model.color == preset ? Color.accentColor : .white.opacity(0.65),
                            lineWidth: model.color == preset ? 2 : 1
                        ))
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 22)
            Button {
                activeToolMenuID = nil
                NSColorSampler().show { color in
                    guard let color else { return }
                    Task { @MainActor in model.color = ScreenshotRGBA(color) }
                }
            } label: {
                Label(model.color.hex, systemImage: "eyedropper")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取色")
            .accessibilityValue(model.color.hex)
        }
    }

    private var lineWidthSlider: some View {
        HStack(spacing: 8) {
            Text("粗细").font(.system(size: 12, weight: .semibold))
            Slider(value: $model.lineWidth, in: 1...12, step: 1)
                .frame(width: 130)
            Text("\(Int(model.lineWidth.rounded()))")
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 18, alignment: .trailing)
        }
    }

    private var fontSizeSlider: some View {
        HStack(spacing: 8) {
            Text("字号").font(.system(size: 12, weight: .semibold))
            Slider(value: $model.fontSize, in: 3...72, step: 1)
                .frame(width: 130)
            Text("\(Int(model.fontSize.rounded()))")
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 24, alignment: .trailing)
        }
    }

    private func selectTool(_ tool: ScreenshotTool) {
        if model.tool != tool {
            selectionState.deselect()
        }
        model.tool = tool
    }

    private func obscureButton(popoverEdge: Edge) -> some View {
        Button {
            selectTool(.mosaic)
            activeToolMenuID = .mosaic
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.obscureEffect == .pixelate ? "square.grid.3x3" : "aqi.medium")
                    .font(.system(size: 12, weight: .semibold))
                Text(model.obscureEffect.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .frame(
                width: ScreenshotToolbarLayout.controlWidth,
                height: ScreenshotToolbarLayout.controlHeight
            )
            .background {
                toolbarSelectionBackground(isSelected: model.tool == .mosaic, cornerRadius: 6)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help("马赛克 / 模糊")
        .popover(isPresented: Binding(
            get: { activeToolMenuID == .mosaic },
            set: { if !$0 { activeToolMenuID = nil } }
        ), arrowEdge: popoverEdge) {
            HStack(spacing: 10) {
                Picker("作用方式", selection: $model.obscureShape) {
                    ForEach(ScreenshotObscureShape.allCases) { shape in
                        Label(shape.title, systemImage: shape.symbol)
                            .tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .help(model.obscureShape.title)

                Divider().frame(height: 24)

                Picker("处理效果", selection: $model.obscureEffect) {
                    ForEach(ScreenshotObscureEffect.allCases) { effect in
                        Text(effect.title).tag(effect)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 92)

                Divider().frame(height: 24)

                if model.obscureShape == .brush {
                    Text("粗细")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 36, alignment: .leading)
                    Slider(value: $model.lineWidth, in: 1...12, step: 1)
                        .frame(width: 90)
                        .help("画笔粗细")
                    Text("\(Int(model.lineWidth.rounded()))")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 18, alignment: .trailing)

                    Divider().frame(height: 24)
                }

                if model.obscureEffect == .pixelate {
                    obscureStrengthControl(
                        title: ScreenshotObscureEffect.pixelate.strengthTitle,
                        value: $model.pixelateStrength,
                        range: 1...12
                    )

                    Divider().frame(height: 24)
                }

                obscureStrengthControl(
                    title: ScreenshotObscureEffect.blur.strengthTitle,
                    value: model.obscureEffect == .pixelate
                        ? $model.mosaicBlurStrength
                        : $model.blurStrength,
                    // A mosaic may skip the blur entirely; the blur effect has to blur something.
                    range: model.obscureEffect == .pixelate ? 0...12 : 1...12
                )
            }
            .padding(.horizontal, 10)
            .frame(height: ScreenshotToolbarLayout.height)
            .onChange(of: model.obscureShape) { _, _ in selectTool(.mosaic) }
            .onChange(of: model.obscureEffect) { _, _ in selectTool(.mosaic) }
        }
    }

    private func obscureStrengthControl(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 36, alignment: .leading)
            Slider(value: value, in: range, step: 1)
                .frame(width: 90)
                .help(title)
            Text("\(Int(value.wrappedValue.rounded()))")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 18, alignment: .trailing)
        }
    }

    private func applyObscureStrength(
        _ strength: CGFloat,
        ifSelectedRegionUses effect: ScreenshotObscureEffect
    ) {
        guard let annotationID = selectedObscureAnnotationID(usingEffect: effect) else { return }
        model.applySelectedStyle(to: annotationID, obscureStrength: strength)
    }

    private func applyObscureBlurStrength(
        _ strength: CGFloat,
        ifSelectedRegionUses effect: ScreenshotObscureEffect
    ) {
        guard let annotationID = selectedObscureAnnotationID(usingEffect: effect) else { return }
        model.applySelectedStyle(to: annotationID, obscureBlurStrength: strength)
    }

    private func selectedObscureAnnotationID(
        usingEffect effect: ScreenshotObscureEffect
    ) -> UUID? {
        guard let annotationID = selectionState.selectedAnnotationID,
              model.annotations.first(where: { $0.id == annotationID })?.obscureEffect == effect
        else { return nil }
        return annotationID
    }

    private var recognitionMenu: some View {
        Menu {
            Button { recognize(.text) } label: {
                Label("识图 / OCR", systemImage: "text.viewfinder")
            }
            Button { recognize(.table) } label: {
                Label("表格识别", systemImage: "tablecells")
            }
        } label: {
            toolbarControlLabel(symbol: "text.viewfinder", title: "识图")
        }
        .menuStyle(.borderlessButton)
        .help("识别图片中的文字或表格")
    }

    private static let colorPresets: [ScreenshotRGBA] = [
        ScreenshotRGBA(red: 1, green: 0.25, blue: 0.2),
        ScreenshotRGBA(red: 1, green: 0.55, blue: 0.1),
        ScreenshotRGBA(red: 0.95, green: 0.8, blue: 0.1),
        ScreenshotRGBA(red: 0.2, green: 0.75, blue: 0.35),
        ScreenshotRGBA(red: 0.2, green: 0.5, blue: 1),
        ScreenshotRGBA(red: 0.55, green: 0.3, blue: 0.9),
        ScreenshotRGBA(red: 1, green: 1, blue: 1),
    ]

    private func iconButton(
        _ symbol: String,
        title: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolbarControlLabel(symbol: symbol, title: title)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? .secondary : .primary)
        .disabled(disabled)
        .help(title)
    }

    private func toolbarControlLabel(
        symbol: String,
        title: String,
        selected: Bool = false
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .frame(
            width: ScreenshotToolbarLayout.controlWidth,
            height: ScreenshotToolbarLayout.controlHeight
        )
        .background {
            toolbarSelectionBackground(isSelected: selected, cornerRadius: 6)
        }
        .contentShape(Rectangle())
    }

    private func chooseTableDestination(_ completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "识别表格.xlsx"
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .spreadsheet]
        panel.canCreateDirectories = true
        let response: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .OK ? panel.url : nil)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.isVisible {
            panel.beginSheetModal(for: window, completionHandler: response)
        } else {
            WindowPlacement.prepareModal(panel)
            panel.begin(completionHandler: response)
        }
    }

    private enum RecognitionMode {
        case text
        case table

        var title: String {
            switch self {
            case .text: "识图完成"
            case .table: "表格识别完成"
            }
        }
    }

    private func recognize(_ mode: RecognitionMode, tableURL: URL? = nil) {
        if case .table = mode, tableURL == nil {
            chooseTableDestination { url in
                guard let url else {
                    model.statusMessage = "已取消保存表格"
                    return
                }
                recognize(.table, tableURL: url)
            }
            return
        }
        guard let cgImage = model.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            model.statusMessage = "无法读取图片"
            return
        }
        model.statusMessage = "正在识别..."
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if let supportedLanguages = try? request.supportedRecognitionLanguages() {
                let preferredLanguages = ["zh-Hans", "zh-Hant", "en-US", "en"]
                let validLanguages = preferredLanguages.filter { supportedLanguages.contains($0) }
                if !validLanguages.isEmpty {
                    request.recognitionLanguages = validLanguages
                }
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            var text = ""
            var failureMessage: String?
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                let fragments = observations.compactMap { observation -> ScreenshotRecognizedFragment? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return ScreenshotRecognizedFragment(
                        text: candidate.string,
                        boundingBox: observation.boundingBox
                    )
                }
                switch mode {
                case .text:
                    text = ScreenshotRecognitionFormatter.plainText(from: fragments)
                case .table:
                    let table = ScreenshotRecognitionFormatter.table(from: fragments, image: cgImage)
                    text = table.rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
                    if !table.isEmpty, let tableURL {
                        try ScreenshotXLSXExporter.write(table, to: tableURL)
                    }
                }
            } catch {
                failureMessage = "识别失败：\(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                if let failureMessage {
                    model.statusMessage = failureMessage
                    return
                }
                guard !text.isEmpty else {
                    model.statusMessage = "未识别到文字"
                    return
                }
                if case .table = mode, let tableURL {
                    model.statusMessage = "表格已保存：\(tableURL.lastPathComponent)"
                    return
                }
                let result = text
                let alert = NSAlert()
                alert.messageText = mode.title
                let contentWidth: CGFloat = 480
                let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 0))
                textView.string = result
                textView.isEditable = false
                textView.isSelectable = true
                textView.drawsBackground = false
                textView.isHorizontallyResizable = false
                textView.textContainer?.containerSize = NSSize(
                    width: contentWidth,
                    height: .greatestFiniteMagnitude
                )
                textView.textContainer?.widthTracksTextView = true

                let textContainer = textView.textContainer
                textView.layoutManager?.ensureLayout(for: textContainer!)
                let textHeight = (textView.layoutManager?.usedRect(for: textContainer!).height ?? 0)
                    + textView.textContainerInset.height * 2
                textView.frame.size.height = textHeight

                let visibleHeight = NSApp.keyWindow?.screen?.visibleFrame.height
                    ?? NSScreen.main?.visibleFrame.height
                    ?? 800
                let scrollView = NSScrollView(frame: NSRect(
                    x: 0,
                    y: 0,
                    width: contentWidth,
                    height: min(max(textHeight, 120), max(120, visibleHeight - 220))
                ))
                scrollView.documentView = textView
                scrollView.drawsBackground = false
                scrollView.hasVerticalScroller = true
                scrollView.hasHorizontalScroller = false
                scrollView.autohidesScrollers = true
                scrollView.borderType = .noBorder
                scrollView.scrollerStyle = .overlay
                ThinScrollChrome.apply(to: scrollView)

                let resultContainer = NSVisualEffectView(frame: scrollView.frame)
                resultContainer.material = .sidebar
                resultContainer.blendingMode = .withinWindow
                resultContainer.state = .active
                resultContainer.appearance = NSAppearance(named: .aqua)
                resultContainer.wantsLayer = true
                resultContainer.layer?.cornerRadius = 8
                resultContainer.layer?.masksToBounds = true
                scrollView.frame = resultContainer.bounds.insetBy(dx: 1, dy: 1)
                scrollView.autoresizingMask = [.width, .height]
                resultContainer.addSubview(scrollView)
                alert.accessoryView = resultContainer
                alert.addButton(withTitle: "复制")
                alert.addButton(withTitle: "关闭")
                let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
                    guard response == .alertFirstButtonReturn else { return }
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(result, forType: .string)
                    model.statusMessage = "\(mode.title)，结果已复制"
                }
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.keyWindow, window.isVisible {
                    alert.beginSheetModal(for: window, completionHandler: handleResponse)
                } else {
                    handleResponse(alert.runModal())
                }
            }
        }
    }
}

extension CGRect {
    fileprivate var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

final class ScreenshotPinnedFocusState: ObservableObject {
    @Published var isSelected = false
    @Published var isPointerInside = false
    @Published var windowIsKey = true

    var isActive: Bool {
        isSelected && isPointerInside && windowIsKey
    }
}

struct ScreenshotPointerInteractionView: NSViewRepresentable {
    let onDrag: (CGPoint, CGPoint, Bool) -> Void
    var onDragBegan: (() -> Void)? = nil
    var usesScreenCoordinatesForDrag = false
    var onDoubleClick: ((CGPoint) -> Void)? = nil
    var onMagnify: ((CGFloat) -> Void)? = nil
    var onScroll: ((CGFloat) -> Void)? = nil
    var onScrollPan: ((CGSize) -> Void)? = nil
    var onResize: ((ScreenshotPinnedResizeCorner, CGPoint, CGPoint, Bool) -> Void)? = nil
    var onPointerFocusChange: ((Bool) -> Void)? = nil
    var onPointerClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> ScreenshotPointerInteractionNSView {
        ScreenshotPointerInteractionNSView()
    }

    func updateNSView(_ nsView: ScreenshotPointerInteractionNSView, context: Context) {
        nsView.onDrag = onDrag
        nsView.onDragBegan = onDragBegan
        nsView.usesScreenCoordinatesForDrag = usesScreenCoordinatesForDrag
        nsView.onDoubleClick = onDoubleClick
        nsView.onMagnify = onMagnify
        nsView.onScroll = onScroll
        nsView.onScrollPan = onScrollPan
        nsView.onResize = onResize
        nsView.onPointerFocusChange = onPointerFocusChange
        nsView.onPointerClick = onPointerClick
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

@MainActor
final class ScreenshotPointerInteractionNSView: NSView {
    var onDrag: ((CGPoint, CGPoint, Bool) -> Void)?
    var onDragBegan: (() -> Void)?
    var usesScreenCoordinatesForDrag = false
    var onDoubleClick: ((CGPoint) -> Void)?
    var onMagnify: ((CGFloat) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    var onScrollPan: ((CGSize) -> Void)?
    var onResize: ((ScreenshotPinnedResizeCorner, CGPoint, CGPoint, Bool) -> Void)?
    var onPointerFocusChange: ((Bool) -> Void)?
    var onPointerClick: (() -> Void)?

    private var dragStart: CGPoint?
    private var resizeCorner: ScreenshotPinnedResizeCorner?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard onResize != nil else { return }

        let radius = ScreenshotPinnedInteraction.cornerHitRadius
        for corner in ScreenshotPinnedResizeCorner.allCases {
            let rect = CGRect(
                x: corner.isLeft ? bounds.minX : bounds.maxX - radius,
                y: corner.isTop ? bounds.minY : bounds.maxY - radius,
                width: radius,
                height: radius
            )
            addCursorRect(rect, cursor: resizeCursor(for: corner))
        }
    }

    private func resizeCursor(for corner: ScreenshotPinnedResizeCorner) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition = switch corner {
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomRight: .bottomRight
            case .bottomLeft: .bottomLeft
            }
            return .frameResize(position: position, directions: .all)
        }

        let symbol = corner.isLeft == corner.isTop
            ? "arrow.up.left.and.arrow.down.right"
            : "arrow.up.right.and.arrow.down.left"
        let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return .crosshair }
        return NSCursor(
            image: image,
            hotSpot: CGPoint(x: image.size.width / 2, y: image.size.height / 2)
        )
    }

    override func mouseDown(with event: NSEvent) {
        activateWindowForInteraction()
        let localPoint = convert(event.locationInWindow, from: nil)
        onPointerClick?()
        if event.clickCount >= 2 {
            onDoubleClick?(localPoint)
            dragStart = nil
            resizeCorner = nil
            return
        }
        resizeCorner = onResize == nil
            ? nil
            : ScreenshotPinnedInteraction.resizeCorner(at: localPoint, in: bounds)
        let point = resizeCorner == nil ? dragPoint(for: event) : localPoint
        dragStart = point
        if let resizeCorner {
            onResize?(resizeCorner, point, point, false)
        } else {
            onDragBegan?()
            onDrag?(point, point, false)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let current = resizeCorner == nil
            ? dragPoint(for: event)
            : convert(event.locationInWindow, from: nil)
        if let resizeCorner {
            onResize?(resizeCorner, dragStart, current, false)
        } else {
            onDrag?(dragStart, current, false)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else { return }
        let current = resizeCorner == nil
            ? dragPoint(for: event)
            : convert(event.locationInWindow, from: nil)
        if let resizeCorner {
            onResize?(resizeCorner, dragStart, current, true)
        } else {
            onDrag?(dragStart, current, true)
        }
        self.dragStart = nil
        resizeCorner = nil
    }

    private func dragPoint(for event: NSEvent) -> CGPoint {
        if usesScreenCoordinatesForDrag, let screenPoint = event.cgEvent?.location {
            return screenPoint
        }
        return convert(event.locationInWindow, from: nil)
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerFocusChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onPointerFocusChange?(false)
    }

    override func magnify(with event: NSEvent) {
        activateWindowForInteraction()
        handleMagnification(event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        activateWindowForInteraction()
        handleScroll(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            directionInverted: event.isDirectionInvertedFromDevice,
            precise: event.hasPreciseScrollingDeltas
        )
    }

    func handleMagnification(_ magnification: CGFloat) {
        onMagnify?(magnification)
    }

    func handleScroll(
        deltaX: CGFloat = 0,
        deltaY: CGFloat,
        directionInverted: Bool,
        precise: Bool
    ) {
        let scale: CGFloat = precise ? 1 : 12
        let deviceDelta = CGSize(
            width: (directionInverted ? -deltaX : deltaX) * scale,
            height: (directionInverted ? -deltaY : deltaY) * scale
        )
        onScrollPan?(deviceDelta)
        onScroll?(deviceDelta.height)
    }

    private func activateWindowForInteraction() {
        guard let window, window.isVisible, !window.isKeyWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

enum ScreenshotPinnedLayout {
    static let toolbarHeight: CGFloat = 30
    static let verticalSpacing: CGFloat = 4
    static let controlHeight: CGFloat = 22
    static let dragHandleWidth = ScreenshotToolbarLayout.dragHandleWidth
    static let buttonWidth: CGFloat = 46
    static let scaleLabelWidth: CGFloat = 32
    static let opacityControlWidth: CGFloat = 98
    static let spacing: CGFloat = 2
    static let horizontalPadding: CGFloat = 4
    static let toolbarCornerRadius: CGFloat = 10
    static let toolbarBorderOpacity: Double = 0.08

    static var footerHeight: CGFloat { footerHeight(toolbarVisible: true) }

    static func footerHeight(toolbarVisible: Bool) -> CGFloat {
        toolbarVisible ? verticalSpacing + toolbarHeight : 0
    }
    static var contentWidth: CGFloat {
        horizontalPadding * 2
            + dragHandleWidth
            + buttonWidth * 3
            + scaleLabelWidth
            + opacityControlWidth
            + spacing * 5
    }

    static func windowWidth(forImageWidth imageWidth: CGFloat, toolbarVisible: Bool) -> CGFloat {
        toolbarVisible ? max(imageWidth, contentWidth) : imageWidth
    }
}

enum ScreenshotPinnedInteraction {
    static let opacityRange: ClosedRange<CGFloat> = 0.2...1
    static let cornerHitRadius: CGFloat = 14

    static func scale(
        current: CGFloat,
        magnification: CGFloat,
        range: ClosedRange<CGFloat>
    ) -> CGFloat {
        let proposed = current * max(0.01, 1 + magnification)
        return min(max(proposed, range.lowerBound), range.upperBound)
    }

    static func opacity(current: CGFloat, deviceScrollDelta: CGFloat) -> CGFloat {
        let proposed = current + deviceScrollDelta * 0.006
        return min(max(proposed, opacityRange.lowerBound), opacityRange.upperBound)
    }

    static func resizeCorner(at point: CGPoint, in bounds: CGRect) -> ScreenshotPinnedResizeCorner? {
        let candidates: [(ScreenshotPinnedResizeCorner, CGPoint)] = [
            (.topLeft, CGPoint(x: bounds.minX, y: bounds.minY)),
            (.topRight, CGPoint(x: bounds.maxX, y: bounds.minY)),
            (.bottomRight, CGPoint(x: bounds.maxX, y: bounds.maxY)),
            (.bottomLeft, CGPoint(x: bounds.minX, y: bounds.maxY)),
        ]
        return candidates.first {
            abs(point.x - $0.1.x) <= cornerHitRadius
                && abs(point.y - $0.1.y) <= cornerHitRadius
        }?.0
    }

    static func resizeScale(
        baseScale: CGFloat,
        corner: ScreenshotPinnedResizeCorner,
        translation: CGSize,
        imageSize: CGSize,
        range: ClosedRange<CGFloat>
    ) -> CGFloat {
        let horizontalDirection: CGFloat = corner.isLeft ? -1 : 1
        let verticalDirection: CGFloat = corner.isTop ? -1 : 1
        let widthChange = translation.width * horizontalDirection / max(imageSize.width, 1)
        let heightChange = translation.height * verticalDirection / max(imageSize.height, 1)
        let proposed = baseScale * (1 + max(widthChange, heightChange))
        return min(max(proposed, range.lowerBound), range.upperBound)
    }
}

enum ScreenshotPinnedResizeCorner: CaseIterable, Hashable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

struct ScreenshotPinnedImageView: View {
    let image: NSImage
    let scaleRange: ClosedRange<CGFloat>
    let onScaleChange: (CGFloat) -> Void
    let onOpacityChange: (CGFloat) -> Void
    let onMove: (CGSize, Bool) -> Void
    let onResize: (ScreenshotPinnedResizeCorner, CGFloat, Bool) -> Void
    let onClose: () -> Void
    let toolbarVisible: Bool

    @ObservedObject private var focusState: ScreenshotPinnedFocusState
    @State private var scale: CGFloat
    @State private var imageOpacity: CGFloat
    @State private var resizeStartScale: CGFloat?

    init(
        image: NSImage,
        initialScale: CGFloat,
        scaleRange: ClosedRange<CGFloat>,
        initialOpacity: CGFloat,
        onScaleChange: @escaping (CGFloat) -> Void,
        onOpacityChange: @escaping (CGFloat) -> Void,
        onMove: @escaping (CGSize, Bool) -> Void,
        onClose: @escaping () -> Void,
        toolbarVisible: Bool = true,
        focusState: ScreenshotPinnedFocusState = ScreenshotPinnedFocusState(),
        onResize: @escaping (ScreenshotPinnedResizeCorner, CGFloat, Bool) -> Void = { _, _, _ in }
    ) {
        self.image = image
        self.scaleRange = scaleRange
        self.onScaleChange = onScaleChange
        self.onOpacityChange = onOpacityChange
        self.onMove = onMove
        self.onResize = onResize
        self.onClose = onClose
        self.toolbarVisible = toolbarVisible
        _focusState = ObservedObject(wrappedValue: focusState)
        _scale = State(initialValue: initialScale)
        _imageOpacity = State(initialValue: initialOpacity)
    }

    private var borderColor: Color {
        focusState.isActive ? Color.blue.opacity(0.72) : Color.gray.opacity(0.55)
    }

    private var borderWidth: CGFloat {
        focusState.isActive ? 1.2 : 1
    }

    private var glowRadius: CGFloat {
        focusState.isActive ? 2 : 0
    }

    private var glowColor: Color {
        focusState.isActive ? Color.blue.opacity(0.16) : .clear
    }

    var body: some View {
        let imageSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let windowWidth = ScreenshotPinnedLayout.windowWidth(
            forImageWidth: imageSize.width,
            toolbarVisible: toolbarVisible
        )
        VStack(spacing: toolbarVisible ? ScreenshotPinnedLayout.verticalSpacing : 0) {
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: imageSize.width, height: imageSize.height)
                    .opacity(Double(imageOpacity))
                    .allowsHitTesting(false)

                ScreenshotPointerInteractionView(
                    onDrag: { start, current, isComplete in
                        onMove(
                            CGSize(
                                width: current.x - start.x,
                                height: current.y - start.y
                            ),
                            isComplete
                        )
                    },
                    usesScreenCoordinatesForDrag: true,
                    onMagnify: { magnification in
                        updateScale(ScreenshotPinnedInteraction.scale(
                            current: scale,
                            magnification: magnification,
                            range: scaleRange
                        ))
                    },
                    onScroll: { deviceDelta in
                        updateOpacity(ScreenshotPinnedInteraction.opacity(
                            current: imageOpacity,
                            deviceScrollDelta: deviceDelta
                        ))
                    },
                    onResize: { corner, start, current, isComplete in
                        if resizeStartScale == nil { resizeStartScale = scale }
                        let translation = CGSize(
                            width: current.x - start.x,
                            height: current.y - start.y
                        )
                        let nextScale = ScreenshotPinnedInteraction.resizeScale(
                            baseScale: resizeStartScale ?? scale,
                            corner: corner,
                            translation: translation,
                            imageSize: image.size,
                            range: scaleRange
                        )
                        scale = nextScale
                        onResize(corner, nextScale, isComplete)
                        if isComplete { resizeStartScale = nil }
                    },
                    onPointerFocusChange: { isInside in
                        focusState.isPointerInside = isInside
                    },
                    onPointerClick: {
                        focusState.isSelected = true
                        focusState.isPointerInside = true
                    }
                )
            }
            .frame(width: imageSize.width, height: imageSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
                    .shadow(color: glowColor, radius: glowRadius)
                    .allowsHitTesting(false)
            }

            if toolbarVisible {
                pinnedToolbar
                    .frame(
                        width: ScreenshotPinnedLayout.contentWidth,
                        height: ScreenshotPinnedLayout.toolbarHeight
                    )
            }
        }
        .frame(
            width: windowWidth,
            height: imageSize.height + ScreenshotPinnedLayout.footerHeight(toolbarVisible: toolbarVisible)
        )
    }

    private var pinnedToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ScreenshotPinnedLayout.spacing) {
                pinnedDragHandle

                pinnedButton("minus.magnifyingglass", title: "缩小") {
                    updateScale(scale - 0.1)
                }

                Text("\(Int((scale * 100).rounded()))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .frame(width: ScreenshotPinnedLayout.scaleLabelWidth)

                pinnedButton("plus.magnifyingglass", title: "放大") {
                    updateScale(scale + 0.1)
                }

                HStack(spacing: 3) {
                    Image(systemName: "circle.lefthalf.filled")
                    Text("透明度")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Slider(
                        value: Binding(
                            get: { imageOpacity },
                            set: { updateOpacity($0) }
                        ),
                        in: ScreenshotPinnedInteraction.opacityRange
                    )
                    .frame(width: 54)
                }
                .font(.system(size: 9, weight: .medium))
                .frame(width: ScreenshotPinnedLayout.opacityControlWidth)

                pinnedButton("xmark", title: "关闭", action: onClose)
            }
            .padding(.horizontal, ScreenshotPinnedLayout.horizontalPadding)
            .frame(height: ScreenshotPinnedLayout.toolbarHeight)
            .fixedSize(horizontal: true, vertical: false)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(
            cornerRadius: ScreenshotPinnedLayout.toolbarCornerRadius,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(
                cornerRadius: ScreenshotPinnedLayout.toolbarCornerRadius,
                style: .continuous
            )
                .stroke(.white.opacity(ScreenshotPinnedLayout.toolbarBorderOpacity), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    private var pinnedDragHandle: some View {
        ZStack {
            ScreenshotToolbarDragDots()
                .allowsHitTesting(false)

            ScreenshotPointerInteractionView(
                onDrag: { start, current, isComplete in
                    onMove(
                        CGSize(
                            width: current.x - start.x,
                            height: current.y - start.y
                        ),
                        isComplete
                    )
                },
                usesScreenCoordinatesForDrag: true
            )
        }
        .frame(
            width: ScreenshotPinnedLayout.dragHandleWidth,
            height: ScreenshotPinnedLayout.controlHeight
        )
        .help("拖动钉图位置")
    }

    private func pinnedButton(
        _ symbol: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 9, weight: .medium))
                .frame(
                    width: ScreenshotPinnedLayout.buttonWidth,
                    height: ScreenshotPinnedLayout.controlHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func updateScale(_ proposedScale: CGFloat) {
        let nextScale = min(max(proposedScale, scaleRange.lowerBound), scaleRange.upperBound)
        guard nextScale != scale else { return }
        scale = nextScale
        onScaleChange(nextScale)
    }

    private func updateOpacity(_ proposedOpacity: CGFloat) {
        let nextOpacity = min(
            max(proposedOpacity, ScreenshotPinnedInteraction.opacityRange.lowerBound),
            ScreenshotPinnedInteraction.opacityRange.upperBound
        )
        guard nextOpacity != imageOpacity else { return }
        imageOpacity = nextOpacity
        onOpacityChange(nextOpacity)
    }
}

@MainActor
private final class ScreenshotInteractiveHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum ScreenshotLongCaptureRangeGeometry {
    static func windowFrame(selection: CGRect, screenFrame: CGRect) -> CGRect {
        let normalized = selection.standardized
        return CGRect(
            x: screenFrame.minX + normalized.minX,
            y: screenFrame.maxY - normalized.maxY,
            width: normalized.width,
            height: normalized.height
        )
    }

    static func outsideRects(selection: CGRect, screenSize: CGSize) -> [CGRect] {
        let bounds = CGRect(origin: .zero, size: screenSize)
        let selected = selection.standardized.intersection(bounds)
        return [
            CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: selected.minY),
            CGRect(x: bounds.minX, y: selected.maxY, width: bounds.width, height: bounds.maxY - selected.maxY),
            CGRect(x: bounds.minX, y: selected.minY, width: selected.minX, height: selected.height),
            CGRect(x: selected.maxX, y: selected.minY, width: bounds.maxX - selected.maxX, height: selected.height),
        ]
    }
}

enum ScreenshotWindowGeometry {
    static func localContentRect(for frame: CGRect, on screenFrame: CGRect) -> CGRect {
        frame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }
}

enum ScreenshotLongCapturePreviewGeometry {
    private static let gap: CGFloat = 12
    private static let minimumWidth: CGFloat = 120
    private static let maximumWidth: CGFloat = 220
    private static let minimumHeight: CGFloat = 96

    static func frame(
        selectionFrame: CGRect,
        availableFrame: CGRect,
        imageSize: CGSize
    ) -> CGRect {
        let available = availableFrame.standardized
        guard available.width > 0, available.height > 0,
              imageSize.width > 0, imageSize.height > 0
        else { return .zero }

        let selection = selectionFrame.standardized
        let leftSpace = max(0, selection.minX - available.minX - gap)
        let rightSpace = max(0, available.maxX - selection.maxX - gap)
        let placeOnRight = rightSpace >= leftSpace
        let sideSpace = max(leftSpace, rightSpace)
        let desiredWidth = min(maximumWidth, max(minimumWidth, available.width * 0.18))
        let fitsOutside = sideSpace >= minimumWidth
        let width = min(desiredWidth, fitsOutside ? sideSpace : available.width)
        let height = min(
            available.height,
            max(minimumHeight, width * imageSize.height / imageSize.width)
        )
        let x: CGFloat
        if fitsOutside {
            x = placeOnRight ? selection.maxX + gap : selection.minX - gap - width
        } else {
            x = placeOnRight ? available.maxX - width : available.minX
        }
        let y = min(
            max(selection.midY - height / 2, available.minY),
            available.maxY - height
        )
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private struct ScreenshotLongCaptureRangeView: View {
    let selection: CGRect

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(
                    Array(ScreenshotLongCaptureRangeGeometry.outsideRects(
                        selection: selection,
                        screenSize: proxy.size
                    ).enumerated()),
                    id: \.offset
                ) { _, rect in
                    Color.black.opacity(0.42)
                        .frame(width: rect.width, height: rect.height)
                        .position(rect.center)
                }

                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .frame(width: selection.width, height: selection.height)
                    .position(selection.center)
                    .shadow(color: .black.opacity(0.7), radius: 2)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct ScreenshotLongCapturePreviewView: View {
    @ObservedObject var model: ScreenshotEditorModel

    var body: some View {
        Image(nsImage: model.image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

@MainActor
private final class ScreenshotLongCaptureRangeWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ScreenshotEditorWindow: NSWindow {
    var onConfirm: (() -> Void)?
    var onCancelEditing: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onDelete: (() -> Bool)?
    var onSave: (() -> Void)?
    /// Returns false while editing so ⌘C stays with the inline text editor; only the pinned image copies here.
    var onCopyImage: (() -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) {
        close()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleImageShortcut(event) { return true }
        // sendAction(_:to:from:) raises NSInvalidArgumentException when the explicit target lacks the selector,
        // which happens whenever no text editor holds focus.
        if let action = Self.editingAction(for: event),
           let firstResponder,
           firstResponder.responds(to: action),
           NSApp.sendAction(action, to: firstResponder, from: self) {
            return true
        }
        return handleEditingKey(event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleImageShortcut(event) { return }
        if handleEditingKey(event) { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancelEditing?()
    }

    private static func editingAction(for event: NSEvent) -> Selector? {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased()

        return switch (key, modifiers) {
        case ("a", .command): #selector(NSResponder.selectAll(_:))
        case ("c", .command): #selector(NSText.copy(_:))
        case ("v", .command): #selector(NSText.paste(_:))
        case ("x", .command): #selector(NSText.cut(_:))
        default: nil
        }
    }

    private func handleImageShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard modifiers == [.command] else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "s":
            guard let onSave else { return false }
            onSave()
            return true
        case "c":
            return onCopyImage?() ?? false
        default:
            return false
        }
    }

    private func handleEditingKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        if event.keyCode == UInt16(kVK_ANSI_Z) {
            if modifiers == [.command] {
                onUndo?()
                return true
            }
            if modifiers == [.command, .shift] {
                onRedo?()
                return true
            }
        }
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            onConfirm?()
            return true
        case UInt16(kVK_Escape):
            onCancelEditing?()
            return true
        case UInt16(kVK_Delete), UInt16(kVK_ForwardDelete):
            return onDelete?() ?? false
        default:
            return false
        }
    }
}

@MainActor
final class ScreenshotEditorWindowController: NSWindowController, NSWindowDelegate {
    /// Presents the PNG save panel; `nil` in the status callback means the panel closed without writing a file.
    typealias PresentSavePanel = @MainActor (Data, @escaping @MainActor (String?) -> Void) -> Void

    private let model: ScreenshotEditorModel
    private let annotationSelectionState: ScreenshotAnnotationSelectionState
    private var onCloseHandler: (() -> Void)?
    private var currentScreen: NSScreen?
    private var currentDisplayID: CGDirectDisplayID?
    private let screenImage: NSImage
    private let screenCGImage: CGImage
    private var captureRect: CGRect
    private weak var capturedApplication: NSRunningApplication?
    private let writeImageToPasteboard: (Data) -> Bool
    private let presentSavePanel: PresentSavePanel
    private var isLongCaptureInProgress = false
    private var longCaptureSessionID = 0
    private var longCaptureCaptureWorkItem: DispatchWorkItem?
    private var longCaptureRangeWindow: ScreenshotLongCaptureRangeWindow?
    private var longCapturePreviewWindow: ScreenshotLongCaptureRangeWindow?
    private var isLongCaptureCaptureInFlight = false
    private var shouldFinishLongCaptureAfterCurrentFrame = false
    private var isClosed = false
    private var isPinnedImagePresentation = false
    private var pinnedImage: NSImage?
    private var pinnedDragStartFrame: CGRect?
    private var pinnedResizeStartFrame: CGRect?
    private let pinnedEscapeHotkeyManager = GlobalHotkeyManager()
    private let pinnedFocusState = ScreenshotPinnedFocusState()
    private(set) var pinnedScale: CGFloat = 1
    private(set) var pinnedOpacity: CGFloat = 1
    let pinnedScaleRange: ClosedRange<CGFloat> = 0.2...3
    let pinnedToolbarVisible: Bool

    var isPinnedPresentation: Bool {
        isPinnedImagePresentation && model.isPinned
    }

    /// After display reconfiguration (wake from sleep, external display changes, or resolution changes), a retained NSScreen becomes stale,
    /// its frame reads as .zero, and every window position derived from it collapses to the lower-left screen origin.
    /// Re-resolve it by displayID before using its geometry and never fall back to .zero.
    private var activeScreen: NSScreen? {
        let liveScreens = NSScreen.screens
        if let currentScreen, liveScreens.contains(where: { $0 === currentScreen }) {
            return currentScreen
        }
        if let currentDisplayID,
           let refreshed = liveScreens.first(where: {
               ScreenshotCaptureService.displayID(for: $0) == currentDisplayID
           }) {
            currentScreen = refreshed
            return refreshed
        }
        let fallback = WindowPlacement.screenUnderMouse() ?? NSScreen.main ?? liveScreens.first
        if let fallback {
            currentScreen = fallback
            currentDisplayID = ScreenshotCaptureService.displayID(for: fallback)
        }
        return fallback
    }

    init(
        image: NSImage,
        screenImage: NSImage,
        screenCGImage: CGImage,
        screen: NSScreen?,
        captureRect: CGRect,
        capturedApplication: NSRunningApplication?,
        writeImageToPasteboard: @escaping (Data) -> Bool = {
            ClipboardHistoryPasteboard.write(.image($0))
        },
        presentSavePanel: @escaping PresentSavePanel = { data, status in
            ScreenshotImageExport.presentSavePanel(for: data, status: status)
        },
        onClose: @escaping () -> Void,
        pinnedToolbarVisible: Bool = true
    ) {
        model = ScreenshotEditorModel(image: image)
        annotationSelectionState = ScreenshotAnnotationSelectionState()
        self.screenImage = screenImage
        self.screenCGImage = screenCGImage
        currentScreen = screen
        currentDisplayID = screen.flatMap(ScreenshotCaptureService.displayID(for:))
        self.captureRect = captureRect
        self.capturedApplication = capturedApplication
        self.writeImageToPasteboard = writeImageToPasteboard
        self.presentSavePanel = presentSavePanel
        self.pinnedToolbarVisible = pinnedToolbarVisible
        onCloseHandler = onClose
        let overlayFrame = screen?.frame ?? CGRect(origin: .zero, size: screenImage.size)
        let window = ScreenshotEditorWindow(
            // The initializer with screen: treats contentRect as local to that screen. The other three call sites use
            // localContentRect, so keep this consistent or external displays with negative origins will be offset.
            contentRect: ScreenshotWindowGeometry.localContentRect(
                for: overlayFrame,
                on: screen?.frame ?? overlayFrame
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        super.init(window: window)
        window.onConfirm = { [weak self] in self?.quickPasteAndClose() }
        window.onCancelEditing = { [weak self] in self?.close() }
        window.onUndo = { [weak self] in self?.model.undo() }
        window.onRedo = { [weak self] in self?.model.redo() }
        window.onDelete = { [weak self] in self?.deleteSelectedAnnotation() ?? false }
        window.onSave = { [weak self] in self?.saveImage() }
        window.onCopyImage = { [weak self] in self?.copyPinnedImage() ?? false }
        configureOverlayView(in: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        isClosed = false
        if let screen = activeScreen {
            window?.setFrame(screen.frame, display: true)
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        isClosed = true
        invalidateLongCaptureSession()
        window?.ignoresMouseEvents = false
        pinnedEscapeHotkeyManager.unregister()
        pinnedFocusState.isSelected = false
        pinnedFocusState.isPointerInside = false
        pinnedFocusState.windowIsKey = false
        window?.contentView = nil
        onCloseHandler?()
        onCloseHandler = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let notificationWindow = notification.object as? NSWindow,
              notificationWindow === window else { return }
        pinnedFocusState.windowIsKey = true
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let notificationWindow = notification.object as? NSWindow,
              notificationWindow === window else { return }
        pinnedFocusState.windowIsKey = false
    }

    func setPinned(_ pinned: Bool) {
        model.isPinned = pinned
        if pinned {
            switchToPinnedImagePresentation()
        } else if isPinnedImagePresentation {
            close()
        } else {
            window?.level = pinned ? .floating : WindowPlacement.modalWindowLevel
        }
    }

    func togglePinned() {
        setPinned(!model.isPinned)
    }

    private func configureOverlayView(in window: NSWindow) {
        window.contentView = ScreenshotInteractiveHostingView(
            rootView: ScreenshotEditorView(
                model: model,
                selectionState: annotationSelectionState,
                overlayConfiguration: ScreenshotEditorOverlayConfiguration(
                    backgroundImage: screenImage,
                    initialSelection: captureRect,
                    cropImage: { [weak self] rect in self?.updateCaptureRect(rect) }
                ),
                onClose: { [weak self] in self?.close() },
                onCopy: { [weak self] in self?.quickPasteAndClose() },
                onSave: { [weak self] in self?.saveImage() },
                onPinToggle: { [weak self] pinned in self?.setPinned(pinned) },
                onLongCapture: { [weak self] in self?.captureNextScreen() },
                onLongCaptureFinish: { [weak self] in self?.finishLongCapture() }
            )
        )
    }

    private func configureLongCaptureToolbar(in window: NSWindow) {
        window.contentView = ScreenshotInteractiveHostingView(
            rootView: ScreenshotEditorView(
                model: model,
                selectionState: annotationSelectionState,
                toolbarOnly: true,
                onClose: { [weak self] in self?.close() },
                onCopy: { [weak self] in self?.quickPasteAndClose() },
                onSave: { [weak self] in self?.saveImage() },
                onPinToggle: { [weak self] pinned in self?.setPinned(pinned) },
                onLongCapture: { [weak self] in self?.captureNextScreen() },
                onLongCaptureFinish: { [weak self] in self?.finishLongCapture() }
            )
        )
    }

    private func switchToPinnedImagePresentation() {
        guard let window, !isPinnedImagePresentation else { return }
        isPinnedImagePresentation = true
        pinnedFocusState.isSelected = false
        pinnedFocusState.isPointerInside = false
        pinnedFocusState.windowIsKey = window.isKeyWindow
        let pinnedImage = model.renderedImage()
        self.pinnedImage = pinnedImage
        pinnedScale = initialPinnedScale(for: pinnedImage.size)
        pinnedOpacity = 1
        let pinnedSize = pinnedWindowSize(for: pinnedImage.size, scale: pinnedScale)
        let pinnedFrame = pinnedWindowFrame(size: pinnedSize)

        window.styleMask = [.borderless]
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        window.contentView = ScreenshotInteractiveHostingView(
            rootView: ScreenshotPinnedImageView(
                image: pinnedImage,
                initialScale: pinnedScale,
                scaleRange: pinnedScaleRange,
                initialOpacity: pinnedOpacity,
                onScaleChange: { [weak self] in self?.setPinnedScale($0) },
                onOpacityChange: { [weak self] in self?.setPinnedOpacity($0) },
                onMove: { [weak self] translation, isComplete in
                    self?.movePinnedWindow(by: translation, isComplete: isComplete)
                },
                onClose: { [weak self] in self?.close() },
                toolbarVisible: pinnedToolbarVisible,
                focusState: pinnedFocusState,
                onResize: { [weak self] corner, scale, isComplete in
                    self?.resizePinnedWindow(corner: corner, scale: scale, isComplete: isComplete)
                }
            )
        )
        window.setFrame(pinnedFrame, display: true)
        registerPinnedEscapeHotkey()
        capturedApplication?.activate()
    }

    private func registerPinnedEscapeHotkey() {
        guard let window, window.isVisible else { return }
        pinnedEscapeHotkeyManager.register(
            keyCode: UInt32(kVK_Escape),
            modifiers: 0,
            action: { [weak self] in
                Task { @MainActor [weak self] in self?.close() }
            }
        )
    }

    private func initialPinnedScale(for imageSize: CGSize) -> CGFloat {
        guard let screen = activeScreen else { return 1 }
        let visibleSize = screen.visibleFrame.size
        return min(max(min(
            1,
            visibleSize.width / max(imageSize.width, 1),
                max(0, visibleSize.height - ScreenshotPinnedLayout.footerHeight(toolbarVisible: pinnedToolbarVisible))
                / max(imageSize.height, 1)
        ), pinnedScaleRange.lowerBound), pinnedScaleRange.upperBound)
    }

    private func pinnedWindowSize(for imageSize: CGSize, scale: CGFloat) -> CGSize {
        CGSize(
            width: ScreenshotPinnedLayout.windowWidth(
                forImageWidth: imageSize.width * scale,
                toolbarVisible: pinnedToolbarVisible
            ),
            height: imageSize.height * scale + ScreenshotPinnedLayout.footerHeight(toolbarVisible: pinnedToolbarVisible)
        )
    }

    private func pinnedWindowFrame(size: CGSize) -> CGRect {
        guard let screen = activeScreen else {
            // Keep the current window position when no screen is available; falling back to .zero would place it at the main screen's lower-left corner.
            return CGRect(origin: window?.frame.origin ?? .zero, size: size)
        }
        let selectionFrame = CGRect(
            x: screen.frame.minX + captureRect.minX,
            y: screen.frame.maxY - captureRect.maxY,
            width: captureRect.width,
            height: captureRect.height
        )
        let proposed = CGRect(
            x: selectionFrame.midX - size.width / 2,
            y: selectionFrame.midY
                - ScreenshotPinnedLayout.footerHeight(toolbarVisible: pinnedToolbarVisible)
                - (size.height - ScreenshotPinnedLayout.footerHeight(toolbarVisible: pinnedToolbarVisible)) / 2,
            width: size.width,
            height: size.height
        )
        return proposed
    }

    func setPinnedScale(_ scale: CGFloat) {
        guard let window, let pinnedImage else { return }
        let nextScale = min(max(scale, pinnedScaleRange.lowerBound), pinnedScaleRange.upperBound)
        guard nextScale != pinnedScale else { return }
        pinnedScale = nextScale
        let size = pinnedWindowSize(for: pinnedImage.size, scale: nextScale)
        let currentFrame = window.frame
        let currentImageCenterY = currentFrame.minY
            + ScreenshotPinnedLayout.footerHeight(toolbarVisible: pinnedToolbarVisible)
            + (currentFrame.height - ScreenshotPinnedLayout.footerHeight(toolbarVisible: pinnedToolbarVisible)) / 2
        let proposed = CGRect(
            x: currentFrame.midX - size.width / 2,
            y: currentImageCenterY
                - ScreenshotPinnedLayout.footerHeight(toolbarVisible: pinnedToolbarVisible)
                - (size.height - ScreenshotPinnedLayout.footerHeight(toolbarVisible: pinnedToolbarVisible)) / 2,
            width: size.width,
            height: size.height
        )
        window.setFrame(proposed, display: false, animate: false)
    }

    private func resizePinnedWindow(
        corner: ScreenshotPinnedResizeCorner,
        scale: CGFloat,
        isComplete: Bool
    ) {
        guard let window, let pinnedImage else { return }
        let startFrame = pinnedResizeStartFrame ?? window.frame
        if pinnedResizeStartFrame == nil { pinnedResizeStartFrame = startFrame }
        pinnedScale = min(max(scale, pinnedScaleRange.lowerBound), pinnedScaleRange.upperBound)
        let footer = ScreenshotPinnedLayout.footerHeight(toolbarVisible: pinnedToolbarVisible)
        let size = pinnedWindowSize(for: pinnedImage.size, scale: pinnedScale)
        let anchor: CGPoint
        let proposed: CGRect
        switch corner {
        case .topLeft:
            anchor = CGPoint(x: startFrame.maxX, y: startFrame.minY + footer)
            proposed = CGRect(x: anchor.x - size.width, y: anchor.y - footer, width: size.width, height: size.height)
        case .topRight:
            anchor = CGPoint(x: startFrame.minX, y: startFrame.minY + footer)
            proposed = CGRect(x: anchor.x, y: anchor.y - footer, width: size.width, height: size.height)
        case .bottomRight:
            anchor = CGPoint(x: startFrame.minX, y: startFrame.maxY)
            proposed = CGRect(x: anchor.x, y: anchor.y - size.height, width: size.width, height: size.height)
        case .bottomLeft:
            anchor = CGPoint(x: startFrame.maxX, y: startFrame.maxY)
            proposed = CGRect(x: anchor.x - size.width, y: anchor.y - size.height, width: size.width, height: size.height)
        }
        window.setFrame(proposed, display: false, animate: false)
        if isComplete { pinnedResizeStartFrame = nil }
    }

    func setPinnedOpacity(_ opacity: CGFloat) {
        pinnedOpacity = min(
            max(opacity, ScreenshotPinnedInteraction.opacityRange.lowerBound),
            ScreenshotPinnedInteraction.opacityRange.upperBound
        )
    }

    func movePinnedWindow(by translation: CGSize, isComplete: Bool) {
        guard let window else { return }
        let startFrame = pinnedDragStartFrame ?? window.frame
        if pinnedDragStartFrame == nil { pinnedDragStartFrame = startFrame }
        let proposedOrigin = CGPoint(
            x: startFrame.minX + translation.width,
            y: startFrame.minY - translation.height
        )
        window.setFrameOrigin(proposedOrigin)
        if isComplete { pinnedDragStartFrame = nil }
    }

    private func updateCaptureRect(_ rect: CGRect) -> NSImage? {
        let screenSize = activeScreen?.frame.size ?? screenImage.size
        let bounds = CGRect(origin: .zero, size: screenSize)
        let normalized = rect.standardized.intersection(bounds)
        guard let image = ScreenshotCaptureService.image(
            from: screenCGImage,
            cropInScreenPoints: normalized,
            screenSize: screenSize
        ) else { return nil }
        captureRect = normalized
        return image
    }

    /// Shared by the toolbar's save button and ⌘S in both the editor and the pinned image.
    private func saveImage() {
        model.commitPendingTextDraft()
        guard let data = model.pngData() else {
            model.statusMessage = "图片生成失败"
            return
        }
        // The pinned image keeps a global Escape hotkey, which would close it instead of dismissing the panel.
        let suspendsPinnedEscapeHotkey = isPinnedImagePresentation
        if suspendsPinnedEscapeHotkey {
            pinnedEscapeHotkeyManager.unregister()
        }
        presentSavePanel(data) { [weak self] message in
            guard let self else { return }
            if suspendsPinnedEscapeHotkey {
                registerPinnedEscapeHotkey()
            }
            if let message {
                model.statusMessage = message
            }
        }
    }

    /// ⌘C copies the pinned image and keeps it on screen, unlike the editor's Enter shortcut.
    private func copyPinnedImage() -> Bool {
        guard isPinnedPresentation else { return false }
        guard let data = model.pngData() else {
            model.statusMessage = "图片生成失败"
            return true
        }
        if !writeImageToPasteboard(data) {
            model.statusMessage = "粘贴板写入失败"
        }
        return true
    }

    private func quickPasteAndClose() {
        invalidateLongCaptureSession()
        model.commitPendingTextDraft()
        guard let data = model.pngData() else {
            model.statusMessage = "图片生成失败"
            return
        }
        guard writeImageToPasteboard(data) else {
            model.statusMessage = "粘贴板写入失败"
            return
        }
        close()
    }

    private func deleteSelectedAnnotation() -> Bool {
        annotationSelectionState.deleteSelectedAnnotation(from: model)
    }

    private func invalidateLongCaptureSession(preservingLongCaptureResult: Bool = false) {
        longCaptureSessionID += 1
        isLongCaptureInProgress = false
        longCaptureCaptureWorkItem?.cancel()
        longCaptureCaptureWorkItem = nil
        isLongCaptureCaptureInFlight = false
        shouldFinishLongCaptureAfterCurrentFrame = false
        dismissLongCaptureOverlays()
        if preservingLongCaptureResult {
            model.completeLongCapturePreview()
        } else {
            model.endLongCapturePreview()
        }
        window?.ignoresMouseEvents = false
    }

    private func finishLongCapture() {
        guard !isClosed else { return }
        guard model.isLongCapturePreviewing || isLongCaptureInProgress else { return }
        guard let screen = activeScreen else {
            completeLongCapture()
            return
        }
        longCaptureCaptureWorkItem?.cancel()
        longCaptureCaptureWorkItem = nil
        shouldFinishLongCaptureAfterCurrentFrame = true
        if !isLongCaptureCaptureInFlight {
            captureLongCaptureScreen(on: screen, sessionID: longCaptureSessionID)
        }
    }

    private func completeLongCapture() {
        invalidateLongCaptureSession(preservingLongCaptureResult: true)
        model.statusMessage = "长截图已完成"
        restoreEditorPresentation()
    }

    private func captureNextScreen() {
        guard !isClosed else { return }
        guard let screen = activeScreen else {
            model.statusMessage = "找不到显示器"
            return
        }
        if isLongCaptureInProgress {
            scheduleLongCapture(screen: screen, sessionID: longCaptureSessionID, after: 0.25)
            return
        }
        let isContinuing = model.isLongCapturePreviewing
        if !isContinuing {
            model.beginLongCapturePreview()
        }
        isLongCaptureInProgress = true
        longCaptureSessionID += 1
        let sessionID = longCaptureSessionID
        model.statusMessage = "请滚动页面，停止后自动拼接"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self,
                  !self.isClosed,
                  self.longCaptureSessionID == sessionID
            else { return }
            self.capturedApplication?.activate()
            self.showLongCaptureRangeOverlay(on: screen)
            self.scheduleLongCapture(screen: screen, sessionID: sessionID, after: 0.35)
        }
    }

    private func showLongCaptureRangeOverlay(on screen: NSScreen) {
        guard let window else { return }
        let rangeWindow = ScreenshotLongCaptureRangeWindow(
            contentRect: ScreenshotWindowGeometry.localContentRect(
                for: screen.frame,
                on: screen.frame
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        rangeWindow.level = .screenSaver
        rangeWindow.isReleasedWhenClosed = false
        rangeWindow.isOpaque = false
        rangeWindow.backgroundColor = .clear
        rangeWindow.hasShadow = false
        rangeWindow.sharingType = .none
        rangeWindow.ignoresMouseEvents = true
        rangeWindow.hidesOnDeactivate = false
        rangeWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        rangeWindow.contentView = ScreenshotInteractiveHostingView(
            rootView: ScreenshotLongCaptureRangeView(selection: captureRect)
        )
        longCaptureRangeWindow = rangeWindow

        let previewFrame = longCapturePreviewFrame(on: screen)
        let previewWindow = ScreenshotLongCaptureRangeWindow(
            contentRect: ScreenshotWindowGeometry.localContentRect(
                for: previewFrame,
                on: screen.frame
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        previewWindow.level = .screenSaver
        previewWindow.isReleasedWhenClosed = false
        previewWindow.isOpaque = false
        previewWindow.backgroundColor = .clear
        previewWindow.hasShadow = true
        previewWindow.sharingType = .none
        previewWindow.ignoresMouseEvents = true
        previewWindow.hidesOnDeactivate = false
        previewWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        previewWindow.contentView = ScreenshotInteractiveHostingView(
            rootView: ScreenshotLongCapturePreviewView(model: model)
        )
        longCapturePreviewWindow = previewWindow

        window.isOpaque = false
        window.backgroundColor = .clear
        window.sharingType = .none
        window.ignoresMouseEvents = false
        configureLongCaptureToolbar(in: window)
        window.setFrame(longCaptureToolbarFrame(on: screen), display: true)
        rangeWindow.orderFrontRegardless()
        previewWindow.orderFrontRegardless()
        window.orderFrontRegardless()
    }

    private func longCapturePreviewFrame(on screen: NSScreen) -> CGRect {
        let visibleFrame = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let toolbarFrame = longCaptureToolbarFrame(on: screen)
        let availableFrame = CGRect(
            x: visibleFrame.minX,
            y: max(visibleFrame.minY, toolbarFrame.maxY + 12),
            width: visibleFrame.width,
            height: max(0, visibleFrame.maxY - max(visibleFrame.minY, toolbarFrame.maxY + 12))
        )
        return ScreenshotLongCapturePreviewGeometry.frame(
            selectionFrame: ScreenshotLongCaptureRangeGeometry.windowFrame(
                selection: captureRect,
                screenFrame: screen.frame
            ),
            availableFrame: availableFrame,
            imageSize: model.image.size
        )
    }

    private func updateLongCapturePreviewFrame(on screen: NSScreen) {
        longCapturePreviewWindow?.setFrame(
            longCapturePreviewFrame(on: screen),
            display: true,
            animate: false
        )
    }

    private func longCaptureToolbarFrame(on screen: NSScreen) -> CGRect {
        let controlCount = ScreenshotToolbarLayout.controlCount
            + (model.canUndo ? 1 : 0)
            + (model.canRedo ? 1 : 0)
        let visibleFrame = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let width = ScreenshotToolbarLayout.viewportWidth(
            availableWidth: screen.visibleFrame.width,
            controlCount: controlCount
        )
        let selectionFrame = ScreenshotLongCaptureRangeGeometry.windowFrame(
            selection: captureRect,
            screenFrame: screen.frame
        )
        let gap: CGFloat = 10
        let belowY = selectionFrame.minY - gap - ScreenshotToolbarLayout.height
        let aboveY = selectionFrame.maxY + gap
        let y: CGFloat
        if belowY >= visibleFrame.minY {
            y = min(belowY, visibleFrame.maxY - ScreenshotToolbarLayout.height)
        } else if aboveY <= visibleFrame.maxY - ScreenshotToolbarLayout.height {
            y = aboveY
        } else {
            y = min(
                max(selectionFrame.midY - ScreenshotToolbarLayout.height / 2, visibleFrame.minY),
                visibleFrame.maxY - ScreenshotToolbarLayout.height
            )
        }
        return CGRect(
            x: min(
                max(selectionFrame.midX - width / 2, visibleFrame.minX),
                visibleFrame.maxX - width
            ),
            y: y,
            width: width,
            height: ScreenshotToolbarLayout.height
        )
    }

    private func restoreEditorPresentation() {
        guard let window, !isClosed else { return }
        dismissLongCaptureOverlays()
        window.isOpaque = true
        window.backgroundColor = .black
        window.sharingType = .readWrite
        if let screen = activeScreen {
            window.setFrame(screen.frame, display: true)
        }
        configureOverlayView(in: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissLongCaptureOverlays() {
        longCaptureRangeWindow?.orderOut(nil)
        longCaptureRangeWindow?.contentView = nil
        longCaptureRangeWindow = nil
        longCapturePreviewWindow?.orderOut(nil)
        longCapturePreviewWindow?.contentView = nil
        longCapturePreviewWindow = nil
    }

    private func scheduleLongCapture(screen: NSScreen, sessionID: Int, after delay: TimeInterval) {
        longCaptureCaptureWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      !self.isClosed,
                      self.longCaptureSessionID == sessionID,
                      self.model.isLongCapturePreviewing
                else { return }
                self.captureLongCaptureScreen(on: screen, sessionID: sessionID)
            }
        }
        longCaptureCaptureWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func captureLongCaptureScreen(on screen: NSScreen, sessionID: Int) {
        guard !isClosed,
              longCaptureSessionID == sessionID,
              model.isLongCapturePreviewing,
              !isLongCaptureCaptureInFlight
        else { return }
        longCaptureCaptureWorkItem = nil
        isLongCaptureCaptureInFlight = true
        Task { @MainActor [weak self] in
            guard let self,
                  !self.isClosed,
                  self.longCaptureSessionID == sessionID,
                  self.model.isLongCapturePreviewing
            else { return }
            do {
                let capture = try await ScreenshotCaptureService.capture(
                    screen: screen,
                    excludingApplicationWithProcessIdentifier: ProcessInfo.processInfo.processIdentifier
                )
                guard !self.isClosed,
                      self.longCaptureSessionID == sessionID,
                      self.model.isLongCapturePreviewing
                else { return }
                guard let nextImage = ScreenshotCaptureService.image(
                    from: capture.cgImage,
                    cropInScreenPoints: self.captureRect,
                    screenSize: screen.frame.size
                ) else {
                    self.isLongCaptureCaptureInFlight = false
                    self.model.statusMessage = "长截图选区无效"
                    self.invalidateLongCaptureSession()
                    self.restoreEditorPresentation()
                    return
                }
                let didAppend = self.model.append(
                    image: nextImage,
                    direction: self.model.longCaptureDirection
                )
                if didAppend {
                    self.updateLongCapturePreviewFrame(on: screen)
                }
                self.isLongCaptureCaptureInFlight = false
                if self.shouldFinishLongCaptureAfterCurrentFrame {
                    self.completeLongCapture()
                } else {
                    self.model.statusMessage = didAppend
                        ? "已自动拼接，继续滚动或点击“完成”"
                        : "长截图采集中，请滚动页面"
                    self.scheduleLongCapture(screen: screen, sessionID: sessionID, after: 0.35)
                }
            } catch {
                self.isLongCaptureCaptureInFlight = false
                self.model.statusMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                self.invalidateLongCaptureSession()
                self.restoreEditorPresentation()
            }
        }
    }
}
