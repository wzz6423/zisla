import AppKit
import QuartzCore
import SwiftUI
import Testing
import ZislaKit

@testable import Zisla

@MainActor
struct PetSpriteRenderingTests {
    @Test(arguments: [CGSize(width: 182, height: 136), CGSize(width: 137, height: 184), CGSize(width: 136, height: 136)])
    func animatedSpritesFillSquareAtCollapsedAndExpandedSizes(sourceSize: CGSize) throws {
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
                try expectSquare(NSBitmapImageRep(cgImage: #require(context.makeImage())), side: pixels)
            }
        }
    }

    @Test(arguments: [CGSize(width: 182, height: 136), CGSize(width: 137, height: 184), CGSize(width: 136, height: 136)])
    func reducedMotionSpritesFillTheSameSquare(sourceSize: CGSize) throws {
        let sprite = PetSprite(image: try image(size: sourceSize))
        for size: CGFloat in [24, 32, 40, 56] {
            let renderer = ImageRenderer(content: PetSpriteView(sprite: sprite, activity: .idle, size: size)
                .environment(\._accessibilityReduceMotion, true))
            for scale: CGFloat in [1, 2] {
                renderer.scale = scale
                try expectSquare(NSBitmapImageRep(cgImage: #require(renderer.cgImage)), side: Int(size * scale))
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

    private func expectSquare(_ bitmap: NSBitmapImageRep, side: Int) throws {
        #expect(bitmap.pixelsWide == side && bitmap.pixelsHigh == side)
        for (x, y) in [(0, 0), (side - 1, 0), (0, side - 1), (side - 1, side - 1)] {
            let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            #expect(color.alphaComponent > 0.99, "All source corners must reach the square viewport without letterboxing")
        }
        let center = try #require(bitmap.colorAt(x: side / 2, y: side / 2))
        #expect(center.alphaComponent == 0, "Transparent sprite pixels must remain transparent")
    }
}
