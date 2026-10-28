import CoreImage
import CoreText
import Foundation
import ZislaCore

struct RecordingCaptionLayout {
    let box: CGRect
    let fontSize: CGFloat
    let padding: CGFloat
    var textRect: CGRect { box.insetBy(dx: padding, dy: padding) }
}

extension RecordingExportRenderer {
    static func captionLayout(_ caption: RecordingCaption, canvas: CGRect) -> RecordingCaptionLayout {
        let fontSize = caption.fontSize.map { min(canvas.width, canvas.height) * $0 }
            ?? max(12, min(canvas.width, canvas.height) * 0.035)
        let padding = fontSize * 0.6
        let box: CGRect
        if let layout = caption.layout {
            box = CGRect(x: layout.x * canvas.width, y: (1 - layout.y - layout.height) * canvas.height,
                         width: layout.width * canvas.width, height: layout.height * canvas.height)
        } else {
            let setter = CTFramesetterCreateWithAttributedString(captionText(caption.text, fontSize: fontSize))
            let width = canvas.width * 0.88 - padding * 2
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0),
                nil, CGSize(width: width, height: .infinity), nil)
            box = CGRect(x: (canvas.width - width - padding * 2) / 2, y: canvas.height * 0.05,
                         width: width + padding * 2, height: min(suggested.height, canvas.height * 0.3) + padding * 2)
        }
        return RecordingCaptionLayout(box: box, fontSize: fontSize,
            padding: max(0, min(padding, min(box.width, box.height) / 2 - 0.01)))
    }

    static func captionImage(_ caption: RecordingCaption, canvas: CGRect, drawsText: Bool = true,
                             visibleCharacters: Int? = nil) throws -> CIImage {
        let layout = captionLayout(caption, canvas: canvas)
        let context = try bitmap(size: layout.box.size)
        let localBox = CGRect(origin: .zero, size: layout.box.size)
        context.setFillColor(CGColor(gray: 0, alpha: 0.78))
        context.addPath(CGPath(roundedRect: localBox, cornerWidth: layout.padding,
                               cornerHeight: layout.padding, transform: nil))
        context.fillPath()
        if drawsText {
            let text = captionText(caption.text, fontSize: layout.fontSize)
            let setter = CTFramesetterCreateWithAttributedString(text)
            let path = CGPath(rect: localBox.insetBy(dx: layout.padding, dy: layout.padding), transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
            drawText(text, frame: frame, in: context, visibleCharacters: visibleCharacters)
        }
        return try bitmapImage(context).transformed(by: .init(translationX: layout.box.minX, y: layout.box.minY))
    }

    static func overlays(project: ScreenRecordingProject, sourceTime: Double, canvas: CGRect,
                         editingText: RecordingCanvasSelection? = nil) throws -> CIImage {
        var image = CIImage(color: .clear).cropped(to: canvas)
        for annotation in project.edits.annotations ?? [] where annotation.isVisible(at: sourceTime) {
            if annotation.kind == .text, editingText == .annotation(annotation.id) { continue }
            image = try annotationImage(annotation, canvas: canvas).composited(over: image)
        }
        if project.edits.showCaptions,
           let caption = project.captions.first(where: { sourceTime >= $0.start && sourceTime < $0.end }),
           !caption.text.isEmpty || editingText == .caption(caption.id) {
            image = try captionImage(caption, canvas: canvas, drawsText: editingText != .caption(caption.id))
                .composited(over: image)
        }
        return image.cropped(to: canvas)
    }

    static func composedPreview(base: CGImage, project: ScreenRecordingProject, sourceTime: Double,
                                context: CIContext, editingText: RecordingCanvasSelection? = nil) throws -> CGImage {
        let canvas = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let image = try overlays(project: project, sourceTime: sourceTime, canvas: canvas, editingText: editingText)
            .composited(over: CIImage(cgImage: base))
        guard let result = context.createCGImage(image, from: canvas, format: .RGBA8,
                                               colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else {
            throw ScreenRecordingExportError.cannotRender
        }
        return result
    }

    private static func captionText(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ])
    }
}
