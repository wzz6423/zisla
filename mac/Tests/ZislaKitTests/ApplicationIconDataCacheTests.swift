import AppKit
import Testing

@testable import ZislaKit

@MainActor
struct ApplicationIconDataCacheTests {
    @Test
    func rendersOneBoundedPNGAndReusesIt() throws {
        let image = try #require(makeImage(pixelSize: 512))
        let cacheKey = "test.\(UUID().uuidString)"

        let first = try #require(ApplicationIconDataCache.data(for: image, cacheKey: cacheKey))
        let second = try #require(ApplicationIconDataCache.data(for: image, cacheKey: cacheKey))
        let representation = try #require(NSBitmapImageRep(data: first))

        #expect(representation.pixelsWide == 128)
        #expect(representation.pixelsHigh == 128)
        #expect(representation.size == NSSize(width: 64, height: 64))
        #expect(first == second)
        #expect(first.count < 128 * 128 * 4)
    }

    @Test(arguments: [64, 128, 512])
    func renderedIconFillsTheEntireRetinaCanvas(sourcePixelSize: Int) throws {
        let image = try #require(makeImage(pixelSize: sourcePixelSize))
        let data = try #require(
            ApplicationIconDataCache.data(for: image, cacheKey: "coverage.\(UUID().uuidString)")
        )
        let representation = try #require(NSBitmapImageRep(data: data))
        var opaquePixels = 0
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                if let color = representation.colorAt(x: x, y: y), color.alphaComponent > 0.99 {
                    opaquePixels += 1
                }
            }
        }

        #expect(representation.pixelsWide == 128)
        #expect(representation.pixelsHigh == 128)
        #expect(opaquePixels == 128 * 128)
    }

    @Test
    func preservesTransparentInsetsAtRetinaScale() throws {
        let image = try #require(makeInsetImage())
        let data = try #require(
            ApplicationIconDataCache.data(for: image, cacheKey: "inset.\(UUID().uuidString)")
        )
        let representation = try #require(NSBitmapImageRep(data: data))
        let bounds = try #require(opaqueBounds(in: representation))

        #expect((31...33).contains(Int(bounds.minX)))
        #expect((31...33).contains(Int(bounds.minY)))
        #expect((62...66).contains(Int(bounds.width)))
        #expect((62...66).contains(Int(bounds.height)))
    }

    private func makeImage(pixelSize: Int) -> NSImage? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: pixelSize, height: pixelSize)
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()
        context.flushGraphics()

        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func makeInsetImage() -> NSImage? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 64,
            pixelsHigh: 64,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: 64, height: 64)
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.systemPink.setFill()
        NSRect(x: 16, y: 16, width: 32, height: 32).fill()
        context.flushGraphics()

        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func opaqueBounds(in representation: NSBitmapImageRep) -> NSRect? {
        var minX = representation.pixelsWide
        var minY = representation.pixelsHigh
        var maxX = -1
        var maxY = -1
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                guard let color = representation.colorAt(x: x, y: y), color.alphaComponent > 0.99 else {
                    continue
                }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return NSRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }
}
