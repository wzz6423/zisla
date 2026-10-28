import CoreText
import Foundation

extension RecordingExportRenderer {
    static func drawText(_ text: NSAttributedString, frame: CTFrame, in context: CGContext, visibleCharacters: Int?) {
        guard let visibleCharacters else { CTFrameDraw(frame, context); return }
        guard visibleCharacters >= 0 else { return }
        CTFrameDraw(typewriterFrame(text, frame: frame, visibleCharacters: visibleCharacters), context)
    }

    static func typewriterFrame(_ text: NSAttributedString, frame: CTFrame, visibleCharacters: Int) -> CTFrame {
        let visibleLength = text.string.prefix(visibleCharacters).utf16.count
        let partial = NSMutableAttributedString(attributedString: text)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        for line in lines {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                let range = CTRunGetStringRange(run)
                let boundaries = Array(Set(indices + [range.location + range.length])).sorted()
                for (start, end) in zip(boundaries, boundaries.dropFirst()) where end > visibleLength {
                    partial.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String),
                        value: CGColor(gray: 0, alpha: 0), range: NSRange(location: start, length: end - start))
                }
            }
        }
        // Keep complete glyph clusters and the full layout; direct run drawing changes color-emoji rasterization.
        let setter = CTFramesetterCreateWithAttributedString(partial)
        return CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CTFrameGetPath(frame), nil)
    }
}
