import CoreText
import Foundation
import ZislaCore

struct RecordingAnnotationTextLayout {
    let bounds: CGRect
    let text: NSAttributedString

    init(_ annotation: RecordingAnnotation, canvas: CGSize) {
        let stored = annotation.bounds
        let fontSize = min(canvas.width, canvas.height) * annotation.fontSize
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(red: annotation.color.red, green: annotation.color.green, blue: annotation.color.blue, alpha: 1),
        ]
        text = NSAttributedString(string: annotation.text, attributes: attributes)
        let measurement = annotation.text.isEmpty || annotation.text.last?.isNewline == true
            ? NSAttributedString(string: annotation.text + " ", attributes: attributes) : text
        let setter = CTFramesetterCreateWithAttributedString(measurement)
        let width = stored.width * canvas.width
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0),
            nil, CGSize(width: width, height: CGFloat.infinity), nil)
        bounds = CGRect(x: stored.x * canvas.width, y: stored.y * canvas.height,
            width: min(width, max(fontSize / 2, ceil(suggested.width))),
            height: min((1 - stored.y) * canvas.height, ceil(suggested.height)))
    }
}
