import AppKit
import QuartzCore
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct PetSpriteRenderingTests {
    @Test(arguments: [CGSize(width: 182, height: 136), CGSize(width: 137, height: 184), CGSize(width: 136, height: 136)], [false, true])
    func animatedSpritesPreserveAspectAtCollapsedAndExpandedSizes(sourceSize: CGSize, matchesPillHeight: Bool) throws {
        let sprite = PetSprite(image: try image(size: sourceSize))
        for size: CGFloat in [24, 32, 40, 56] {
            let viewport = CGSize(width: matchesPillHeight ? size * sourceSize.width / sourceSize.height : size, height: size)
            let host = NSHostingView(rootView: IslandPetView(sprite: sprite, behavior: PetBehaviorController(), side: .left, size: viewport)
                .environment(\._accessibilityReduceMotion, false))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: viewport),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            host.layoutSubtreeIfNeeded()
            let layer = try #require(spriteLayer(in: host), "The animated pet must mount its native sprite layer")
            for scale: CGFloat in [1, 2] {
                let pixels = CGSize(width: viewport.width * scale, height: viewport.height * scale)
                let width = Int(ceil(pixels.width)), height = Int(ceil(pixels.height))
                let context = try #require(CGContext(data: nil, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.scaleBy(x: scale, y: scale)
                layer.render(in: context)
                try expectAspect(NSBitmapImageRep(cgImage: #require(context.makeImage())), viewport: pixels, sourceSize: sourceSize)
            }
        }
    }

    @Test(arguments: [CGSize(width: 182, height: 136), CGSize(width: 137, height: 184), CGSize(width: 136, height: 136)], [false, true])
    func reducedMotionSpritesPreserveTheSameAspect(sourceSize: CGSize, matchesPillHeight: Bool) throws {
        let sprite = PetSprite(image: try image(size: sourceSize))
        for size: CGFloat in [24, 32, 40, 56] {
            let viewport = CGSize(width: matchesPillHeight ? size * sourceSize.width / sourceSize.height : size, height: size)
            let renderer = ImageRenderer(content: IslandPetView(sprite: sprite, behavior: PetBehaviorController(), side: .left, size: viewport)
                .environment(\._accessibilityReduceMotion, true))
            for scale: CGFloat in [1, 2] {
                renderer.scale = scale
                try expectAspect(NSBitmapImageRep(cgImage: #require(renderer.cgImage)),
                    viewport: CGSize(width: viewport.width * scale, height: viewport.height * scale), sourceSize: sourceSize)
            }
        }
    }

    @Test(arguments: IslandEdge.allCases, [false, true])
    func collapsedPetPixelsFollowTheIslandCenterInTheFullPanel(edge: IslandEdge, reduceMotion: Bool) throws {
        let sprite = PetSprite(image: try image(size: CGSize(width: 182, height: 136)))
        let screen = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1056))
        let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: edge),
            statusIconSize: edge.isVertical ? CGSize(width: 40, height: 120) : CGSize(width: 120, height: 32))).layout(for: screen)
        let bar = layout.collapsedFrame
        let height: CGFloat = 24
        let width = height * 182 / 136
        let container = CollapsedPetLayout.frame(for: layout, petAspectRatio: 182 / 136)
        let content = CollapsedPetView.pillPet(sprite: sprite, behavior: PetBehaviorController(),
            layout: layout, compactBarFrame: bar, side: .right)
            .frame(width: container.width, height: container.height)
            .environment(\._accessibilityReduceMotion, reduceMotion)
        let bitmap: NSBitmapImageRep
        if reduceMotion {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        } else {
            let host = NSHostingView(rootView: content)
            host.sizingOptions = []
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: container.size),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            host.layoutSubtreeIfNeeded()
            let view = try #require(spriteView(in: host))
            let layer = try #require(spriteLayer(in: view))
            let frame = host.convert(view.bounds, from: view)
            let pixelsWide = Int(ceil(container.width * 2)), pixelsHigh = Int(ceil(container.height * 2))
            let context = try #require(CGContext(data: nil, width: pixelsWide, height: pixelsHigh,
                bitsPerComponent: 8, bytesPerRow: pixelsWide * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: frame.minX * 2, y: (host.isFlipped ? container.height - frame.maxY : frame.minY) * 2)
            context.scaleBy(x: 2, y: 2)
            layer.render(in: context)
            bitmap = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
        }
        let bounds = try visibleBounds(bitmap)
        let expectedCenter = CGPoint(
            x: (edge.isVertical ? bar.midX : bar.maxX + 4 + width / 2) - container.minX,
            y: container.maxY - (edge.isVertical ? bar.minY - 4 - height / 2 : bar.midY))
        #expect(abs(bounds.midX / 2 - expectedCenter.x) <= 0.5)
        #expect(abs(bounds.midY / 2 - expectedCenter.y) <= 0.5,
                "The pet center must follow the island center instead of its previous top inset")
        #expect(abs(bounds.height / 2 - height) <= 1)
        #expect(abs(bounds.width / 2 - width) <= 1)
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

    private func spriteView(in view: NSView) -> NSView? {
        if view.layer?.sublayers?.contains(where: { $0.contents != nil }) == true { return view }
        return view.subviews.lazy.compactMap { spriteView(in: $0) }.first
    }

    private func visibleBounds(_ bitmap: NSBitmapImageRep) throws -> CGRect {
        var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if try #require(bitmap.colorAt(x: x, y: y)).alphaComponent > 0.5 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        try #require(maxX >= minX && maxY >= minY, "The pet must render visible pixels")
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func expectAspect(_ bitmap: NSBitmapImageRep, viewport: CGSize, sourceSize: CGSize) throws {
        #expect(abs(CGFloat(bitmap.pixelsWide) - viewport.width) < 1 && abs(CGFloat(bitmap.pixelsHigh) - viewport.height) < 1)
        let bounds = try visibleBounds(bitmap)
        let scale = min(viewport.width / sourceSize.width, viewport.height / sourceSize.height)
        let renderedSize = bounds.size
        let expectedSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let inset = CGPoint(x: (viewport.width - expectedSize.width) / 2,
                            y: (viewport.height - expectedSize.height) / 2)
        // Each edge rounds independently to physical pixels.
        #expect(abs(bounds.minX - inset.x) <= 1
                && abs(bounds.maxX - inset.x - expectedSize.width) <= 1,
                "Pet width must preserve source proportions: rendered \(renderedSize), expected \(expectedSize), viewport \(viewport)px")
        #expect(abs(bounds.minY - inset.y) <= 1
                && abs(bounds.maxY - inset.y - expectedSize.height) <= 1,
                "Pet height must preserve source proportions: rendered \(renderedSize), expected \(expectedSize), viewport \(viewport)px")
        #expect(abs(bounds.midX * 2 - viewport.width) <= 1 && abs(bounds.midY * 2 - viewport.height) <= 1,
                "The sprite must remain centered inside its viewport")
        let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        #expect(center.alphaComponent == 0, "Transparent sprite pixels must remain transparent")
    }
}
