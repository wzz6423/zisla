import AppKit
import QuartzCore
import SwiftUI
import Testing
import ZislaKit

@testable import Zisla

@MainActor
struct PetSpriteRenderingTests {
    @Test(arguments: [CGSize(width: 182, height: 136), CGSize(width: 137, height: 184), CGSize(width: 136, height: 136)])
    func animatedSpritesPreserveAspectAtCollapsedAndExpandedSizes(sourceSize: CGSize) throws {
        let sprite = PetSprite(image: try image(size: sourceSize))
        for size: CGFloat in [24, 32, 40, 56] {
            let host = NSHostingView(rootView: PetSpriteView(sprite: sprite, activity: .idle, size: size)
                .environment(\._accessibilityReduceMotion, false))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: size, height: size),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            host.layoutSubtreeIfNeeded()
            let layer = try #require(spriteLayer(in: host), "The animated pet must mount its native sprite layer")
            for scale: CGFloat in [1, 2] {
                let pixels = Int(size * scale)
                let context = try #require(CGContext(data: nil, width: pixels, height: pixels,
                    bitsPerComponent: 8, bytesPerRow: pixels * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.scaleBy(x: scale, y: scale)
                layer.render(in: context)
                try expectAspect(NSBitmapImageRep(cgImage: #require(context.makeImage())), side: pixels, sourceSize: sourceSize)
            }
        }
    }

    @Test(arguments: [CGSize(width: 182, height: 136), CGSize(width: 137, height: 184), CGSize(width: 136, height: 136)])
    func reducedMotionSpritesPreserveTheSameAspect(sourceSize: CGSize) throws {
        let sprite = PetSprite(image: try image(size: sourceSize))
        for size: CGFloat in [24, 32, 40, 56] {
            let renderer = ImageRenderer(content: PetSpriteView(sprite: sprite, activity: .idle, size: size)
                .environment(\._accessibilityReduceMotion, true))
            for scale: CGFloat in [1, 2] {
                renderer.scale = scale
                try expectAspect(NSBitmapImageRep(cgImage: #require(renderer.cgImage)), side: Int(size * scale), sourceSize: sourceSize)
            }
        }
    }

    private func image(size: CGSize) throws -> NSImage {
        let context = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.clear(CGRect(x: size.width * 0.375, y: size.height * 0.375,
                             width: size.width * 0.25, height: size.height * 0.25))
        return NSImage(cgImage: try #require(context.makeImage()), size: size)
    }

    private func spriteLayer(in view: NSView) -> CALayer? {
        if let layer = view.layer?.sublayers?.first(where: { $0.contents != nil }) { return layer }
        return view.subviews.lazy.compactMap { spriteLayer(in: $0) }.first
    }

    private func expectAspect(_ bitmap: NSBitmapImageRep, side: Int, sourceSize: CGSize) throws {
        #expect(bitmap.pixelsWide == side && bitmap.pixelsHigh == side)
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side {
                let color = try #require(bitmap.colorAt(x: x, y: y))
                if color.alphaComponent > 0.5 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        try #require(maxX >= minX && maxY >= minY, "The pet must render visible pixels")
        let scale = CGFloat(side) / max(sourceSize.width, sourceSize.height)
        let renderedSize = CGSize(width: maxX - minX + 1, height: maxY - minY + 1)
        let expectedSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let inset = CGPoint(x: (CGFloat(side) - expectedSize.width) / 2,
                            y: (CGFloat(side) - expectedSize.height) / 2)
        // Each edge rounds independently to physical pixels.
        #expect(abs(CGFloat(minX) - inset.x) <= 1
                && abs(CGFloat(maxX + 1) - inset.x - expectedSize.width) <= 1,
                "Pet width must preserve source proportions: rendered \(renderedSize), expected \(expectedSize), viewport \(side)px")
        #expect(abs(CGFloat(minY) - inset.y) <= 1
                && abs(CGFloat(maxY + 1) - inset.y - expectedSize.height) <= 1,
                "Pet height must preserve source proportions: rendered \(renderedSize), expected \(expectedSize), viewport \(side)px")
        #expect(abs(minX + maxX + 1 - side) <= 1 && abs(minY + maxY + 1 - side) <= 1,
                "The sprite must remain centered inside its square viewport")
        let center = try #require(bitmap.colorAt(x: side / 2, y: side / 2))
        #expect(center.alphaComponent == 0, "Transparent sprite pixels must remain transparent")
    }
}
