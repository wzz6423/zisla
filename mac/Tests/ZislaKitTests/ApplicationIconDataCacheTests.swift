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

        #expect(representation.pixelsWide == 64)
        #expect(representation.pixelsHigh == 64)
        #expect(first == second)
        #expect(first.count < 64 * 64 * 4)
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
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        bitmap.size = NSSize(width: pixelSize, height: pixelSize)
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
}
