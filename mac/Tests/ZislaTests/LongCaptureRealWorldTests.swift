import AppKit
import CoreGraphics
import Testing

@testable import Zisla

/// Realistic long-capture reproduction tests.
///
/// The original regression tests only ever stitch *two* frames of high-entropy noise, which is the
/// easiest possible input for an overlap matcher. Real long screenshots are pages: mostly flat white
/// with thin dark text bands, and a session appends five to fifteen frames in a row. These tests model
/// that, and assert that the stitched result still equals the page it was cut from.
@MainActor
@Suite(.serialized)
struct LongCaptureRealWorldTests {
    // MARK: - Page fixtures

    /// A synthetic "page": white background, grey text bands, separator rules and a couple of solid
    /// blocks. Mostly flat, which is exactly where a whole-frame diff score gets ambiguous.
    private func makePageImage(width: Int, height: Int, seed: UInt64 = 0x1234_5678) -> CGImage? {
        var state = seed
        func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)
        for index in stride(from: 3, to: pixels.count, by: 4) {
            pixels[index] = 255
        }

        func fill(_ rect: CGRect, _ value: UInt8) {
            let x0 = max(0, Int(rect.minX))
            let x1 = min(width, Int(rect.maxX))
            let y0 = max(0, Int(rect.minY))
            let y1 = min(height, Int(rect.maxY))
            guard x0 < x1, y0 < y1 else { return }
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let offset = y * bytesPerRow + x * 4
                    pixels[offset] = value
                    pixels[offset + 1] = value
                    pixels[offset + 2] = value
                }
            }
        }

        var y = 24
        while y < height - 40 {
            let kind = Int(next() % 5)
            switch kind {
            case 0:
                // Paragraph: several text rows.
                let rows = Int(next() % 4) + 2
                for row in 0..<rows {
                    let rowY = y + row * 22
                    var x = 32
                    var lastX = 0
                    while x < width - 40 {
                        let wordWidth = Int(next() % 90) + 20
                        let wordEnd = min(x + wordWidth, width - 40)
                        let value: UInt8 = 40 + UInt8(next() % 60)
                        fill(CGRect(x: x, y: rowY, width: wordEnd - x, height: 9), value)
                        lastX = wordEnd
                        x = wordEnd + Int(next() % 14) + 8
                    }
                    _ = lastX
                }
                y += rows * 22 + 26
            case 1:
                // Separator rule.
                fill(CGRect(x: 32, y: y, width: width - 64, height: 2), 210)
                y += 34
            case 2:
                // Solid block (an image placeholder).
                let blockHeight = Int(next() % 120) + 60
                let value = UInt8(next() % 180) + 40
                fill(CGRect(x: 32, y: y, width: width - 64, height: blockHeight), value)
                y += blockHeight + 28
            case 3:
                // Bulleted list: short rows.
                let rows = Int(next() % 3) + 2
                for row in 0..<rows {
                    let rowY = y + row * 24
                    fill(CGRect(x: 46, y: rowY, width: 8, height: 8), 90)
                    let wordWidth = Int(next() % 200) + 80
                    fill(
                        CGRect(x: 66, y: rowY, width: min(wordWidth, width - 100), height: 9),
                        55 + UInt8(next() % 50)
                    )
                }
                y += rows * 24 + 30
            default:
                // Heading: one wide, dark row.
                fill(CGRect(x: 32, y: y, width: Int(next() % 240) + 160, height: 13), 25)
                y += 44
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func frame(from page: CGImage, offset: Int, height: Int) -> CGImage? {
        let clamped = min(max(offset, 0), page.height - height)
        return page.cropping(to: CGRect(x: 0, y: clamped, width: page.width, height: height))
    }

    /// A page built from a list of near-identical rows — a settings list, a table, or a feed. Every row
    /// has the same layout and the differences between rows are a few pixels wide, exactly like real
    /// text. This is the shape of the long screenshots users actually take, and the hardest input for an
    /// overlap matcher: a whole-row shift looks almost as good as the truth until you compare rows at
    /// native resolution.
    private func makeListPageImage(
        width: Int,
        height: Int,
        pitch: Int = 130,
        seed: UInt64 = 0x9E37_79B9
    ) -> CGImage? {
        var state = seed
        func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)

        func fill(_ rect: CGRect, _ value: UInt8) {
            let x0 = max(0, Int(rect.minX))
            let x1 = min(width, Int(rect.maxX))
            let y0 = max(0, Int(rect.minY))
            let y1 = min(height, Int(rect.maxY))
            guard x0 < x1, y0 < y1 else { return }
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let offset = y * bytesPerRow + x * 4
                    pixels[offset] = value
                    pixels[offset + 1] = value
                    pixels[offset + 2] = value
                }
            }
        }

        var row = 0
        while row * pitch < height {
            let base = row * pitch
            // Title: same bar everywhere, a couple of pixels longer on some rows.
            fill(CGRect(x: 24, y: base + 18, width: 220 + Int(next() % 5), height: 16), 28)
            // Body text: the run of words differs a little on every row.
            var x = 24
            while x < width - 48 {
                let word = 30 + Int(next() % 70)
                let end = min(x + word, width - 48)
                fill(CGRect(x: x, y: base + 48, width: end - x, height: 12), 90)
                x = end + 10 + Int(next() % 12)
            }
            // Trailing meta column, identical on every row.
            fill(CGRect(x: width - 120, y: base + 18, width: 60, height: 12), 150)
            // Row divider.
            fill(CGRect(x: 24, y: base + pitch - 6, width: width - 48, height: 2), 205)
            row += 1
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// A page whose rows really are identical — a table of duplicate entries, the adversarial case for
    /// any overlap matcher because a whole-row shift scores exactly as well as the truth.
    private func makePeriodicListPageImage(width: Int, height: Int, pitch: Int = 130) -> CGImage? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)

        func fill(_ rect: CGRect, _ value: UInt8) {
            let x0 = max(0, Int(rect.minX))
            let x1 = min(width, Int(rect.maxX))
            let y0 = max(0, Int(rect.minY))
            let y1 = min(height, Int(rect.maxY))
            guard x0 < x1, y0 < y1 else { return }
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let offset = y * bytesPerRow + x * 4
                    pixels[offset] = value
                    pixels[offset + 1] = value
                    pixels[offset + 2] = value
                }
            }
        }

        var row = 0
        while row * pitch < height {
            let base = row * pitch
            fill(CGRect(x: 24, y: base + 18, width: 220, height: 16), 28)
            fill(CGRect(x: 24, y: base + 48, width: width - 80, height: 12), 90)
            fill(CGRect(x: width - 120, y: base + 18, width: 60, height: 12), 150)
            fill(CGRect(x: 24, y: base + pitch - 6, width: width - 48, height: 2), 205)
            row += 1
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Redraws a frame with several small patches altered, scattered over the frame: a live list whose
    /// durations, clocks and spinners keep repainting even while the page is standing still.
    private func ticking(_ image: CGImage, amount: Int) -> CGImage {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Eight small repaints spread from top to bottom: several rows' counters changing at once.
        for patch in 0..<8 {
            let y = 30 + patch * 80
            let x = 40 + (patch * 97) % max(1, width - 140)
            for dy in 0..<8 {
                for dx in 0..<64 {
                    guard y + dy < height, x + dx < width else { continue }
                    let offset = ((height - 1 - (y + dy)) * bytesPerRow) + (x + dx) * 4
                    let value = UInt8((37 * (amount + patch + 1)) % 200 + 20)
                    pixels[offset] = value
                    pixels[offset + 1] = value
                    pixels[offset + 2] = value
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return image }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) ?? image
    }

    /// A chat-like page: mostly blank, with sparse bubbles and a few faint labels. Blank pages are the
    /// other extreme for an overlap matcher — a blank row matches a blank row at *every* offset, so a
    /// score that averages across the whole width is diluted into meaninglessness and the seam can land
    /// tens of pixels off without the score noticing.
    private func makeChatPageImage(width: Int, height: Int, seed: UInt64 = 0x5DEE_CE66) -> CGImage? {
        var state = seed
        func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 250, count: height * bytesPerRow)
        for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }

        func fill(_ rect: CGRect, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
            let x0 = max(0, Int(rect.minX))
            let x1 = min(width, Int(rect.maxX))
            let y0 = max(0, Int(rect.minY))
            let y1 = min(height, Int(rect.maxY))
            guard x0 < x1, y0 < y1 else { return }
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let offset = y * bytesPerRow + x * 4
                    pixels[offset] = r
                    pixels[offset + 1] = g
                    pixels[offset + 2] = b
                }
            }
        }

        var y = 40
        var left = true
        while y < height - 200 {
            let labelWidth = 90 + Int(next() % 60)
            fill(
                CGRect(x: CGFloat((width - labelWidth) / 2), y: CGFloat(y), width: CGFloat(labelWidth), height: 10),
                170, 170, 170
            )
            y += 46
            let bubbleHeight = 70 + Int(next() % 110)
            let bubbleWidth = min(width - 60, 200 + Int(next() % 280))
            let x: CGFloat = left ? 24 : CGFloat(width - 24 - bubbleWidth)
            fill(
                CGRect(x: x, y: CGFloat(y), width: CGFloat(bubbleWidth), height: CGFloat(bubbleHeight)),
                170, 235, 175
            )
            var textY = y + 16
            while textY < y + bubbleHeight - 14 {
                let runWidth = 80 + Int(next() % 160)
                fill(
                    CGRect(x: x + 14, y: CGFloat(textY), width: CGFloat(min(runWidth, bubbleWidth - 28)), height: 9),
                    45, 95, 60
                )
                textY += 22
            }
            y += bubbleHeight + 24 + Int(next() % 90)
            left.toggle()
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Pixels of a `CGImage` laid out as RGBA rows, top row first in the returned array.
    private func rgbaPixels(_ image: CGImage) -> [UInt8] {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    /// Compares stitched output against the expected page crop and reports where they diverge.
    private func describeMismatch(actual: [UInt8], expected: [UInt8], width: Int) -> String {
        guard actual.count == expected.count else {
            return "size \(actual.count / (width * 4)) rows vs expected \(expected.count / (width * 4)) rows"
        }
        var firstBad = -1
        var badRows = Set<Int>()
        for row in 0..<(actual.count / (width * 4)) {
            let start = row * width * 4
            let end = start + width * 4
            if actual[start..<end] != expected[start..<end] {
                if firstBad < 0 { firstBad = row }
                badRows.insert(row)
            }
        }
        guard firstBad >= 0 else { return "identical" }
        let rows = badRows.sorted()
        var runs: [ClosedRange<Int>] = []
        var runStart = rows[0]
        var previous = rows[0]
        for row in rows.dropFirst() {
            if row == previous + 1 {
                previous = row
            } else {
                runs.append(runStart...previous)
                runStart = row
                previous = row
            }
        }
        runs.append(runStart...previous)
        let summary = runs.prefix(12).map { "\($0.lowerBound)…\($0.upperBound)" }.joined(separator: ", ")
        return "\(badRows.count) bad rows, first at \(firstBad); runs: \(summary)\(runs.count > 12 ? " …" : "")"
    }

    // MARK: - Scenarios

    @Test
    func realWorldMultiFrameSessionReproducesThePage() throws {
        let pageWidth = 360
        let frameHeight = 700
        let page = try #require(makePageImage(width: pageWidth, height: 4_600))
        let offsets = [0, 340, 650, 1_010, 1_300, 1_660, 1_980, 2_300]
        let first = try #require(frame(from: page, offset: offsets[0], height: frameHeight))
        let model = ScreenshotEditorModel(
            image: NSImage(cgImage: first, size: CGSize(width: pageWidth, height: frameHeight))
        )
        model.beginLongCapturePreview()

        for offset in offsets.dropFirst() {
            let frameImage = try #require(frame(from: page, offset: offset, height: frameHeight))
            _ = model.append(
                image: NSImage(
                    cgImage: frameImage,
                    size: CGSize(width: pageWidth, height: frameHeight)
                ),
                direction: .vertical
            )
        }

        let lastOffset = try #require(offsets.last)
        let expectedRows = lastOffset + frameHeight
        let expected = try #require(page.cropping(
            to: CGRect(x: 0, y: 0, width: pageWidth, height: min(expectedRows, page.height))
        ))
        let combined = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let report = describeMismatch(
            actual: rgbaPixels(combined),
            expected: rgbaPixels(expected),
            width: pageWidth
        )
        #expect(combined.height == expected.height, "height \(combined.height) vs \(expected.height)")
        #expect(report == "identical", "stitched page differs: \(report)")
    }

    @Test
    func realWorldSmallScrollStepsStillStitchExactly() throws {
        let pageWidth = 300
        let frameHeight = 600
        let page = try #require(makePageImage(width: pageWidth, height: 3_200, seed: 0xABCD_1234))
        // Slow trackpad scrolling: many small, irregular steps.
        let offsets = [0, 40, 96, 140, 205, 250, 312, 366, 410, 470, 528, 590]
        let first = try #require(frame(from: page, offset: offsets[0], height: frameHeight))
        let model = ScreenshotEditorModel(
            image: NSImage(cgImage: first, size: CGSize(width: pageWidth, height: frameHeight))
        )
        model.beginLongCapturePreview()

        for offset in offsets.dropFirst() {
            let frameImage = try #require(frame(from: page, offset: offset, height: frameHeight))
            _ = model.append(
                image: NSImage(
                    cgImage: frameImage,
                    size: CGSize(width: pageWidth, height: frameHeight)
                ),
                direction: .vertical
            )
        }

        let lastOffset = try #require(offsets.last)
        let expected = try #require(page.cropping(
            to: CGRect(x: 0, y: 0, width: pageWidth, height: min(lastOffset + frameHeight, page.height))
        ))
        let combined = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let report = describeMismatch(
            actual: rgbaPixels(combined),
            expected: rgbaPixels(expected),
            width: pageWidth
        )
        #expect(combined.height == expected.height, "height \(combined.height) vs \(expected.height)")
        #expect(report == "identical", "stitched page differs: \(report)")
    }

    @Test
    func realWorldRepeatingListRowsDoNotShiftTheSeam() throws {
        let pageWidth = 360
        let frameHeight = 700
        let pitch = 130
        let page = try #require(makeListPageImage(width: pageWidth, height: 4_800, pitch: pitch))
        // Steps are deliberately not multiples of the row pitch, and the last one is the largest.
        let offsets = [0, 260, 545, 830, 1_190, 1_480]
        let first = try #require(frame(from: page, offset: offsets[0], height: frameHeight))
        let model = ScreenshotEditorModel(
            image: NSImage(cgImage: first, size: CGSize(width: pageWidth, height: frameHeight))
        )
        model.beginLongCapturePreview()

        for offset in offsets.dropFirst() {
            let frameImage = try #require(frame(from: page, offset: offset, height: frameHeight))
            _ = model.append(
                image: NSImage(
                    cgImage: frameImage,
                    size: CGSize(width: pageWidth, height: frameHeight)
                ),
                direction: .vertical
            )
        }

        let lastOffset = try #require(offsets.last)
        let expected = try #require(page.cropping(
            to: CGRect(x: 0, y: 0, width: pageWidth, height: min(lastOffset + frameHeight, page.height))
        ))
        let combined = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let report = describeMismatch(
            actual: rgbaPixels(combined),
            expected: rgbaPixels(expected),
            width: pageWidth
        )
        #expect(combined.height == expected.height, "height \(combined.height) vs \(expected.height)")
        #expect(report == "identical", "repeating list rows shifted the seam: \(report)")
    }

    @Test
    func realWorldStationaryRepeatingListIsNeverAppended() throws {
        let pageWidth = 360
        let frameHeight = 700
        let page = try #require(makeListPageImage(width: pageWidth, height: 4_000))
        let frameImage = try #require(frame(from: page, offset: 1_040, height: frameHeight))
        let frameNS = NSImage(cgImage: frameImage, size: CGSize(width: pageWidth, height: frameHeight))
        let model = ScreenshotEditorModel(image: frameNS)
        model.beginLongCapturePreview()

        let baseline = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        for _ in 0..<8 {
            let didAppend = model.append(image: frameNS, direction: .vertical)
            #expect(!didAppend, "a stationary repeating list was stitched in")
        }
        let after = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(after.height == baseline.height)
        #expect(rgbaPixels(after) == rgbaPixels(baseline))
    }

    @Test
    func realWorldStationaryPageIsNeverAppended() throws {
        let pageWidth = 300
        let frameHeight = 600
        let page = try #require(makePageImage(width: pageWidth, height: 2_400, seed: 0x55AA_00FF))
        let frameImage = try #require(frame(from: page, offset: 600, height: frameHeight))
        let frameNS = NSImage(cgImage: frameImage, size: CGSize(width: pageWidth, height: frameHeight))
        let model = ScreenshotEditorModel(image: frameNS)
        model.beginLongCapturePreview()

        let baseline = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        for _ in 0..<6 {
            let didAppend = model.append(image: frameNS, direction: .vertical)
            #expect(!didAppend, "a stationary frame was stitched in")
        }
        let after = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(after.height == baseline.height)
        #expect(rgbaPixels(after) == rgbaPixels(baseline))
    }

    /// A page can stand still while the screen is anything but still: durations tick, clocks advance,
    /// spinners spin, and every one of those repaints pixels. Those changes are scattered over the whole
    /// frame, not confined to one corner, so a check that only looks for a single changed patch lets the
    /// frame through to the matcher. On a page whose rows are alike — and rows usually are: they differ
    /// only in a timestamp and a couple of counters — the matcher can then read the stillness as another
    /// scroll and append the same rows a second time. That is the "kept recording while I was not
    /// scrolling" report.
    @Test
    func realWorldStationaryPageWithTickingContentIsNeverAppended() throws {
        let pageWidth = 360
        let frameHeight = 700
        let page = try #require(makePeriodicListPageImage(width: pageWidth, height: 4_000))
        let first = try #require(frame(from: page, offset: 0, height: frameHeight))
        let model = ScreenshotEditorModel(
            image: NSImage(cgImage: first, size: CGSize(width: pageWidth, height: frameHeight))
        )
        model.beginLongCapturePreview()

        // One real scroll first, so the matcher has a scroll step to compare against.
        let scrolled = try #require(frame(from: page, offset: 260, height: frameHeight))
        _ = model.append(
            image: NSImage(cgImage: scrolled, size: CGSize(width: pageWidth, height: frameHeight)),
            direction: .vertical
        )
        let settled = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        for tick in 1...8 {
            let frameImage = ticking(scrolled, amount: tick)
            let didAppend = model.append(
                image: NSImage(cgImage: frameImage, size: CGSize(width: pageWidth, height: frameHeight)),
                direction: .vertical
            )
            #expect(!didAppend, "a still page that was only repainting tick \(tick) was stitched in")
        }
        let after = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(after.height == settled.height)
        #expect(rgbaPixels(after) == rgbaPixels(settled))
    }

    /// Mostly-blank pages are where an overlap score is weakest, so they get their own session test.
    @Test
    func realWorldSparseChatPageStitchesExactly() throws {
        let pageWidth = 620
        let frameHeight = 900
        let page = try #require(makeChatPageImage(width: pageWidth, height: 5_200))
        let offsets = [0, 320, 700, 1_010, 1_430, 1_760, 2_140]
        let first = try #require(frame(from: page, offset: offsets[0], height: frameHeight))
        let model = ScreenshotEditorModel(
            image: NSImage(cgImage: first, size: CGSize(width: pageWidth, height: frameHeight))
        )
        model.beginLongCapturePreview()

        for offset in offsets.dropFirst() {
            let frameImage = try #require(frame(from: page, offset: offset, height: frameHeight))
            _ = model.append(
                image: NSImage(
                    cgImage: frameImage,
                    size: CGSize(width: pageWidth, height: frameHeight)
                ),
                direction: .vertical
            )
        }

        let lastOffset = try #require(offsets.last)
        let expected = try #require(page.cropping(
            to: CGRect(x: 0, y: 0, width: pageWidth, height: min(lastOffset + frameHeight, page.height))
        ))
        let combined = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let report = describeMismatch(
            actual: rgbaPixels(combined),
            expected: rgbaPixels(expected),
            width: pageWidth
        )
        #expect(combined.height == expected.height, "height \(combined.height) vs \(expected.height)")
        #expect(report == "identical", "sparse chat page differs: \(report)")
    }
}
