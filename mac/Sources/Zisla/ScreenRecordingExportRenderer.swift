import CoreImage
import CoreText
import Foundation
import ZislaCore

struct RecordingExportZoomState: Equatable, Sendable {
    let scale: Double
    let x: Double
    let y: Double
}

struct RecordingExportEffectTrack {
    private let pointers: [RecordingPointer]
    private let clicks: [RecordingPointer]
    private let manualZooms: [RecordingZoom]
    private let automaticZooms: [RecordingZoom]

    init(project: ScreenRecordingProject) {
        pointers = project.pointers.sorted { $0.time < $1.time }
        clicks = pointers.filter { $0.kind != .move }
        manualZooms = project.edits.zoomClips.sorted { $0.time < $1.time }
        var automatic: [RecordingZoom] = []
        if project.edits.autoZoom {
            for click in clicks where automatic.last.map({ click.time >= $0.time + $0.duration }) ?? true {
                let start = max(0, click.time - 0.4)
                automatic.append(RecordingZoom(time: start, duration: min(2.4, project.duration - start),
                                                scale: 1.8, x: click.x, y: click.y))
            }
        }
        automaticZooms = automatic
    }

    func pointer(at time: Double, slice: RecordingExportSlice?) -> CGPoint? {
        let upper = recordingUpperBound(pointers, value: time, key: \.time)
        guard upper > 0 else { return nil }
        let previous = pointers[upper - 1]
        guard upper < pointers.count else { return CGPoint(x: previous.x, y: previous.y) }
        let next = pointers[upper]
        let end = slice?.sourceEnd ?? .infinity
        guard next.time < end, next.time > previous.time else {
            return CGPoint(x: previous.x, y: previous.y)
        }
        let progress = (time - previous.time) / (next.time - previous.time)
        let smooth = progress * progress * (3 - 2 * progress)
        return CGPoint(x: previous.x + (next.x - previous.x) * smooth,
                       y: previous.y + (next.y - previous.y) * smooth)
    }

    func recentClicks(at time: Double, slice: RecordingExportSlice?) -> ArraySlice<RecordingPointer> {
        let lower = recordingUpperBound(clicks, value: max(time - 0.55, slice?.sourceStart ?? 0) - 0.000_001,
                                        key: \.time)
        let upper = recordingUpperBound(clicks, value: time, key: \.time)
        return clicks[lower..<upper]
    }

    func zoom(at time: Double) -> RecordingExportZoomState {
        if let manual = activeZoom(manualZooms, at: time) { return evaluate(manual, at: time) }
        if let automatic = activeZoom(automaticZooms, at: time) { return evaluate(automatic, at: time) }
        return RecordingExportZoomState(scale: 1, x: 0.5, y: 0.5)
    }

    private func activeZoom(_ zooms: [RecordingZoom], at time: Double) -> RecordingZoom? {
        let upper = recordingUpperBound(zooms, value: time, key: \.time)
        guard upper > 0 else { return nil }
        return zooms[..<upper].last { time < $0.time + $0.duration }
    }

    private func evaluate(_ zoom: RecordingZoom, at time: Double) -> RecordingExportZoomState {
        let ramp = min(0.35, zoom.duration / 3)
        let progress = min(1, min((time - zoom.time) / ramp, (zoom.time + zoom.duration - time) / ramp))
        let eased = progress * progress * (3 - 2 * progress)
        return RecordingExportZoomState(scale: pow(zoom.scale, eased), x: zoom.x, y: zoom.y)
    }
}

final class RecordingExportRenderer {
    let canvas: CGRect
    let screenRect: CGRect
    let sourceCrop: RecordingRect
    let context: CIContext
    private let project: ScreenRecordingProject
    private let effects: RecordingExportEffectTrack
    private let background: CIImage
    private let screenMask: CIImage
    private let cursor: CIImage
    private let shadow: CIImage?
    private let cameraRect: CGRect
    private let cameraMask: CIImage
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init(project: ScreenRecordingProject, size: CGSize) throws {
        self.project = project
        effects = RecordingExportEffectTrack(project: project)
        canvas = CGRect(origin: .zero, size: size)
        context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        sourceCrop = project.edits.crop ?? RecordingRect(x: 0, y: 0, width: 1, height: 1)
        let shortSide = min(size.width, size.height)
        let padding = project.edits.background == .none && project.edits.backgroundColor == nil ? 0 : shortSide * project.edits.padding
        let available = canvas.insetBy(dx: padding, dy: padding)
        if project.edits.canvasAspectRatio?.ratio != nil {
            let sourceWidth = Double(project.width) * sourceCrop.width
            let sourceHeight = Double(project.height) * sourceCrop.height
            let scale = min(available.width / sourceWidth, available.height / sourceHeight)
            let width = sourceWidth * scale
            let height = sourceHeight * scale
            screenRect = CGRect(x: available.midX - width / 2, y: available.midY - height / 2, width: width, height: height)
        } else { screenRect = available }
        screenMask = try Self.mask(rect: screenRect, radius: shortSide * project.edits.cornerRadius,
                                   canvas: canvas)
        if let color = project.edits.backgroundColor {
            background = CIImage(color: CIColor(red: color.red, green: color.green, blue: color.blue)).cropped(to: canvas)
        } else { background = try Self.background(project.edits.background, canvas: canvas) }
        cursor = try Self.cursorImage(size: max(8, shortSide * 0.028 * project.edits.cursorSize))
        if project.edits.shadow > 0 {
            let alphaMask = screenMask.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: project.edits.shadow),
            ])
            shadow = alphaMask.applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: shortSide * 0.025 * project.edits.shadow,
            ]).transformed(by: CGAffineTransform(translationX: 0, y: -shortSide * 0.012))
        } else { shadow = nil }
        let side = shortSide * project.edits.cameraSize
        let cameraHeight = side / CGFloat(project.edits.effectiveCameraAspectRatio.ratio)
        let margin = shortSide * 0.025
        let cameraX: CGFloat
        let cameraY: CGFloat
        switch project.edits.cameraPosition {
        case .topLeft: cameraX = margin; cameraY = size.height - margin - cameraHeight
        case .topRight: cameraX = size.width - margin - side; cameraY = size.height - margin - cameraHeight
        case .bottomLeft: cameraX = margin; cameraY = margin
        case .bottomRight: cameraX = size.width - margin - side; cameraY = margin
        }
        cameraRect = CGRect(x: cameraX, y: cameraY, width: side, height: cameraHeight)
        cameraMask = try Self.mask(rect: cameraRect,
                                   radius: min(side, cameraHeight) * project.edits.effectiveCameraCornerRadius,
                                   canvas: canvas)
    }

    static func outputSize(source: CGSize, edits: RecordingEdits,
                           resolution: RecordingExportResolution) throws -> CGSize {
        let crop = edits.crop ?? RecordingRect(x: 0, y: 0, width: 1, height: 1)
        let width = source.width * crop.width
        let height = source.height * crop.height
        guard width.isFinite, height.isFinite, width >= 1, height >= 1 else {
            throw ScreenRecordingExportError.invalidConfiguration
        }
        let longest: Double
        switch resolution {
        case .source: longest = max(width, height)
        case .fullHD: longest = 1_920
        case .quadHD: longest = 2_560
        case .ultraHD: longest = 3_840
        }
        let aspect = edits.canvasAspectRatio?.ratio ?? width / height
        let output = CGSize(width: max(2, (longest * min(1, aspect) / 2).rounded() * 2),
                            height: max(2, (longest / max(1, aspect) / 2).rounded() * 2))
        guard output.width <= 16_384, output.height <= 16_384,
              output.width * output.height <= 40_000_000 else {
            throw ScreenRecordingExportError.invalidConfiguration
        }
        return output
    }

    func render(screen: CIImage, camera: CIImage?, sourceTime: Double,
                slice: RecordingExportSlice? = nil) throws -> CIImage {
        let normalized = Self.normalized(screen)
        let crop = CGRect(x: sourceCrop.x * normalized.extent.width,
                          y: (1 - sourceCrop.y - sourceCrop.height) * normalized.extent.height,
                          width: sourceCrop.width * normalized.extent.width,
                          height: sourceCrop.height * normalized.extent.height)
        let zoom = effects.zoom(at: sourceTime)
        let viewport = Self.viewport(crop: crop, zoom: zoom, source: normalized.extent.size)
        var visible = normalized.cropped(to: viewport)
        if project.edits.clickEffects {
            for click in effects.recentClicks(at: sourceTime, slice: slice) {
                let location = CGPoint(x: click.x * normalized.extent.width,
                                       y: (1 - click.y) * normalized.extent.height)
                let phase = (sourceTime - click.time) / 0.55
                let radius = min(normalized.extent.width, normalized.extent.height) * (0.018 + 0.038 * phase)
                let ring = try Self.clickImage(center: location, radius: radius, opacity: 1 - phase,
                                               rightClick: click.kind == .rightClick)
                visible = ring.composited(over: visible).cropped(to: viewport)
            }
        }
        if project.edits.showCursor, let pointer = effects.pointer(at: sourceTime, slice: slice) {
            let scale = viewport.width / screenRect.width
            let image = cursor.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let origin = CGPoint(x: pointer.x * normalized.extent.width,
                                 y: (1 - pointer.y) * normalized.extent.height - image.extent.height)
            visible = image.transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
                .composited(over: visible).cropped(to: viewport)
        }
        let screenLayer = Self.fit(visible, to: screenRect, fill: false)
        var scene = background
        if let shadow { scene = shadow.composited(over: scene) }
        scene = Self.masked(screenLayer, mask: screenMask, canvas: canvas).composited(over: scene)
        if project.edits.effectiveShowCamera, let camera {
            var image = Self.normalized(camera)
            if project.edits.cameraMirrored {
                image = image.transformed(by: CGAffineTransform(translationX: image.extent.width, y: 0)
                    .scaledBy(x: -1, y: 1))
            }
            let cameraLayer = Self.fit(image, to: cameraRect, fill: true)
            scene = Self.masked(cameraLayer, mask: cameraMask, canvas: canvas).composited(over: scene)
        }
        for annotation in project.edits.annotations ?? [] where annotation.isVisible(at: sourceTime) {
            scene = try Self.annotationImage(annotation, canvas: canvas).composited(over: scene)
        }
        if project.edits.showCaptions,
           let caption = project.captions.first(where: { sourceTime >= $0.start && sourceTime < $0.end }),
           !caption.text.isEmpty {
            let image = try Self.captionImage(text: caption.text, canvas: canvas)
            scene = image.composited(over: scene)
        }
        return scene.cropped(to: canvas)
    }

    func image(screen: CIImage, camera: CIImage?, sourceTime: Double,
               slice: RecordingExportSlice? = nil) throws -> CGImage {
        let rendered = try render(screen: screen, camera: camera, sourceTime: sourceTime, slice: slice)
        guard let image = context.createCGImage(rendered, from: canvas, format: .RGBA8, colorSpace: colorSpace) else {
            throw ScreenRecordingExportError.cannotRender
        }
        return image
    }

    static func normalized(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    static func viewport(crop: CGRect, zoom: RecordingExportZoomState, source: CGSize) -> CGRect {
        let width = crop.width / zoom.scale
        let height = crop.height / zoom.scale
        return CGRect(x: min(max(zoom.x * source.width - width / 2, crop.minX), crop.maxX - width),
                      y: min(max((1 - zoom.y) * source.height - height / 2, crop.minY), crop.maxY - height),
                      width: width, height: height)
    }

    private static func fit(_ image: CIImage, to rect: CGRect, fill: Bool) -> CIImage {
        let scaleX = rect.width / image.extent.width
        let scaleY = rect.height / image.extent.height
        let scale = fill ? max(scaleX, scaleY) : min(scaleX, scaleY)
        let normalized = normalized(image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return normalized.transformed(by: CGAffineTransform(translationX: rect.midX - normalized.extent.width / 2,
                                                            y: rect.midY - normalized.extent.height / 2))
            .cropped(to: rect)
    }

    private static func masked(_ image: CIImage, mask: CIImage, canvas: CGRect) -> CIImage {
        image.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: canvas),
            kCIInputMaskImageKey: mask,
        ]).cropped(to: canvas)
    }

    private static func mask(rect: CGRect, radius: CGFloat, canvas: CGRect) throws -> CIImage {
        let context = try bitmap(size: rect.size)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: rect.size),
                               cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        return try bitmapImage(context).transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
            .cropped(to: canvas)
    }

    private static func background(_ style: RecordingBackground, canvas: CGRect) throws -> CIImage {
        switch style {
        case .none: return CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: canvas)
        case .midnight: return CIImage(color: CIColor(red: 0.055, green: 0.071, blue: 0.13)).cropped(to: canvas)
        case .white: return CIImage(color: .white).cropped(to: canvas)
        case .gradient:
            let context = try bitmap(size: canvas.size)
            let colors = [CGColor(red: 0.16, green: 0.19, blue: 0.53, alpha: 1),
                          CGColor(red: 0.38, green: 0.14, blue: 0.46, alpha: 1)]
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                            colors: colors as CFArray, locations: [0, 1]) else {
                throw ScreenRecordingExportError.cannotRender
            }
            context.drawLinearGradient(gradient, start: CGPoint(x: canvas.minX, y: canvas.maxY),
                                       end: CGPoint(x: canvas.maxX, y: canvas.minY), options: [])
            return try bitmapImage(context)
        }
    }

    private static func cursorImage(size: Double) throws -> CIImage {
        let context = try bitmap(size: CGSize(width: ceil(size * 0.7), height: ceil(size)))
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: size / 24, y: -size / 24)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1.5, y: 1))
        path.addLine(to: CGPoint(x: 1.5, y: 18))
        path.addLine(to: CGPoint(x: 6, y: 13.5))
        path.addLine(to: CGPoint(x: 10, y: 22))
        path.addLine(to: CGPoint(x: 13, y: 20.5))
        path.addLine(to: CGPoint(x: 9, y: 12))
        path.addLine(to: CGPoint(x: 15, y: 12))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.setStrokeColor(CGColor(gray: 0.05, alpha: 1))
        context.setLineWidth(1.2)
        context.drawPath(using: .fillStroke)
        return try bitmapImage(context)
    }

    private static func clickImage(center: CGPoint, radius: Double, opacity: Double,
                                    rightClick: Bool) throws -> CIImage {
        let side = ceil(radius * 2 + 4)
        let context = try bitmap(size: CGSize(width: side, height: side))
        context.setStrokeColor(CGColor(red: rightClick ? 1 : 0.2, green: rightClick ? 0.7 : 0.75,
                                      blue: rightClick ? 0.2 : 1, alpha: opacity))
        context.setLineWidth(max(1.5, radius * 0.08))
        context.strokeEllipse(in: CGRect(x: 2, y: 2, width: side - 4, height: side - 4))
        return try bitmapImage(context).transformed(by: CGAffineTransform(translationX: center.x - side / 2,
                                                                         y: center.y - side / 2))
    }

    private static func captionImage(text: String, canvas: CGRect) throws -> CIImage {
        let fontSize = max(12, min(canvas.width, canvas.height) * 0.035)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString,
                                                                                      fontSize, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let padding = fontSize * 0.6
        let width = canvas.width * 0.88 - padding * 2
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0),
                                                                     nil, CGSize(width: width, height: .infinity), nil)
        let height = min(suggested.height, canvas.height * 0.3)
        let box = CGRect(x: (canvas.width - width - padding * 2) / 2, y: canvas.height * 0.05,
                         width: width + padding * 2, height: height + padding * 2)
        let context = try bitmap(size: box.size)
        let localBox = CGRect(origin: .zero, size: box.size)
        context.setFillColor(CGColor(gray: 0, alpha: 0.78))
        context.addPath(CGPath(roundedRect: localBox, cornerWidth: padding, cornerHeight: padding, transform: nil))
        context.fillPath()
        let path = CGPath(rect: localBox.insetBy(dx: padding, dy: padding), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        return try bitmapImage(context).transformed(by: CGAffineTransform(translationX: box.minX, y: box.minY))
    }

    private static func annotationImage(_ annotation: RecordingAnnotation, canvas: CGRect) throws -> CIImage {
        let bounds = annotation.bounds
        let rect = CGRect(x: bounds.x * canvas.width, y: (1 - bounds.y - bounds.height) * canvas.height,
                          width: bounds.width * canvas.width, height: bounds.height * canvas.height)
        let shortSide = min(canvas.width, canvas.height)
        let lineWidth = shortSide * annotation.lineWidth
        let inset = annotation.kind == .arrow ? max(shortSide * 0.05, lineWidth * 2) : lineWidth
        let imageBounds = rect.insetBy(dx: -inset, dy: -inset).intersection(canvas).integral
        let context = try bitmap(size: imageBounds.size)
        context.translateBy(x: -imageBounds.minX, y: -imageBounds.minY)
        let color = CGColor(red: annotation.color.red, green: annotation.color.green, blue: annotation.color.blue, alpha: 1)
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch annotation.kind {
        case .rectangle:
            context.stroke(rect)
        case .arrow:
            let start = CGPoint(x: annotation.x * canvas.width, y: (1 - annotation.y) * canvas.height)
            let end = CGPoint(x: annotation.endX * canvas.width, y: (1 - annotation.endY) * canvas.height)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = min(max(shortSide * 0.025, lineWidth * 3), hypot(end.x - start.x, end.y - start.y) * 0.4)
            let first = CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6))
            let second = CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6))
            context.strokeLineSegments(between: [start, end, end, first, end, second])
        case .text:
            context.clip(to: rect)
            let text = NSAttributedString(string: annotation.text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString,
                                                                                          shortSide * annotation.fontSize, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ])
            let setter = CTFramesetterCreateWithAttributedString(text)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
            CTFrameDraw(frame, context)
        }
        return try bitmapImage(context).transformed(by: .init(translationX: imageBounds.minX, y: imageBounds.minY))
            .cropped(to: canvas)
    }

    private static func bitmap(size: CGSize) throws -> CGContext {
        guard let context = CGContext(data: nil, width: Int(ceil(size.width)), height: Int(ceil(size.height)),
                                      bitsPerComponent: 8, bytesPerRow: Int(ceil(size.width)) * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ScreenRecordingExportError.cannotRender
        }
        return context
    }

    private static func bitmapImage(_ context: CGContext) throws -> CIImage {
        guard let image = context.makeImage() else { throw ScreenRecordingExportError.cannotRender }
        return CIImage(cgImage: image)
    }
}
