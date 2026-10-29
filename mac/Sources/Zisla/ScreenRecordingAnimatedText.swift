import CoreText
import Foundation

extension RecordingExportRenderer {
    static func drawText(_ text: NSAttributedString, frame: CTFrame, in context: CGContext, visibleCharacters: Int?) throws {
        guard let visibleCharacters else { CTFrameDraw(frame, context); return }
        guard visibleCharacters >= 0 else { return }
        CTFrameDraw(try typewriterFrame(text, frame: frame, visibleCharacters: visibleCharacters), context)
    }

    static func typewriterFrame(_ text: NSAttributedString, frame: CTFrame, visibleCharacters: Int) throws -> CTFrame {
        let visibleLength = text.string.prefix(visibleCharacters).utf16.count
        let partial = NSMutableAttributedString(attributedString: text)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let pathOrigin = CTFrameGetPath(frame).boundingBoxOfPath.origin
        var clusters: [(range: NSRange, bounds: CGRect)] = []
        for (lineIndex, line) in lines.enumerated() {
            let origin = CGPoint(x: origins[lineIndex].x + pathOrigin.x, y: origins[lineIndex].y + pathOrigin.y)
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                let range = CTRunGetStringRange(run)
                let boundaries = Array(Set(indices + [range.location + range.length])).sorted()
                for (start, end) in zip(boundaries, boundaries.dropFirst()) {
                    var bounds = CGRect.null
                    for index in indices.indices where indices[index] == start {
                        bounds = bounds.union(try glyphPixelBounds(run, index: index, origin: origin))
                    }
                    clusters.append((NSRange(location: start, length: end - start), bounds))
                }
            }
        }
        var hidden = Set(clusters.indices.filter { NSMaxRange(clusters[$0].range) > visibleLength })
        var pending = Array(hidden)
        // Adjacent emoji and letters can share antialiased pixels; reveal their complete clusters together.
        while let index = pending.popLast() {
            for candidate in clusters.indices where !hidden.contains(candidate)
                && clusters[index].bounds.intersects(clusters[candidate].bounds) {
                hidden.insert(candidate)
                pending.append(candidate)
            }
        }
        for index in hidden {
            partial.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String),
                value: CGColor(gray: 0, alpha: 0), range: clusters[index].range)
        }
        // Keep complete glyph clusters and the full layout; direct run drawing changes color-emoji rasterization.
        let setter = CTFramesetterCreateWithAttributedString(partial)
        return CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CTFrameGetPath(frame), nil)
    }

    private static func glyphPixelBounds(_ run: CTRun, index: Int, origin: CGPoint) throws -> CGRect {
        let range = CFRange(location: index, length: 1)
        let ink = CTRunGetImageBounds(run, nil, range)
        let box = ink.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -1, dy: -1).integral
        let context = try bitmap(size: box.size)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.textPosition = origin
        CTRunDraw(run, context, range)
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        var bounds = CGRect.null
        for y in 0..<context.height {
            for x in 0..<context.width where pixels[y * context.bytesPerRow + x * 4 + 3] != 0 {
                bounds = bounds.union(CGRect(x: box.minX + CGFloat(x), y: box.minY + CGFloat(context.height - 1 - y),
                    width: 1, height: 1))
            }
        }
        return bounds
    }
}
