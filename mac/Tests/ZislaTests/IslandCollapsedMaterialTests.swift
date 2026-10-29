import AppKit
import SwiftUI
import Testing
import ZislaCore
@testable import Zisla

@MainActor
struct IslandCollapsedMaterialTests {
    @Test(arguments: IslandNotchBackground.allCases, [false, true])
    func collapsedMaterialUsesTheSelectedNativeSurfaceAndAccessibilityFallback(
        style: IslandNotchBackground, reduceTransparency: Bool
    ) async {
        let host = NSHostingView(rootView: IslandCollapsedMaterial.rendering(
            style: style, reduceTransparency: reduceTransparency
        ).frame(width: 160, height: 32))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -100_000, y: -100_000, width: 160, height: 32),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        for _ in 0..<3 { await Task.yield() }
        host.layoutSubtreeIfNeeded()
        let views = descendants(host)
        let effects = views.compactMap { $0 as? NSVisualEffectView }
        #expect(!window.isVisible, "The automated material fixture must remain offscreen")
        if reduceTransparency || style == .black {
            #expect(effects.isEmpty)
        } else if style == .frosted {
            #expect(effects.contains { $0.material == .popover && $0.blendingMode == .behindWindow && $0.alphaValue == 0.92 })
        }
        if #available(macOS 26.0, *) {
            let glass = views.compactMap { $0 as? NSGlassEffectView }
            #expect(glass.isEmpty == (reduceTransparency || style != .liquidGlass))
            if style == .liquidGlass && !reduceTransparency {
                #expect(glass.contains { $0.style == .clear && $0.cornerRadius == 16 && $0.tintColor == nil })
            }
        } else if style == .liquidGlass && !reduceTransparency {
            #expect(effects.contains { $0.material == .popover })
        }
    }

    @Test
    func liquidGlassCrownFadesBeforeTheBottomAndOpaqueModesStayBlack() throws {
        let renderer = ImageRenderer(content: IslandCollapsedMaterial.liquidGlassCrown.frame(width: 160, height: 32))
        renderer.scale = 1
        let transparent = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let top = try #require(transparent.colorAt(x: 80, y: 1))
        let middle = try #require(transparent.colorAt(x: 80, y: 17))
        let bottom = try #require(transparent.colorAt(x: 80, y: 30))
        #expect(top.alphaComponent > 0.95)
        #expect((0.65...0.8).contains(middle.alphaComponent))
        #expect(bottom.alphaComponent < 0.15)
        for style in IslandNotchBackground.allCases {
            let opaque = try bitmap(style: style, reduceTransparency: true)
            for y in [1, 16, 30] {
                let pixel = try #require(opaque.colorAt(x: 80, y: y)?.usingColorSpace(.deviceRGB))
                #expect(pixel.alphaComponent == 1)
                #expect(pixel.redComponent == 0 && pixel.greenComponent == 0 && pixel.blueComponent == 0)
            }
        }
        let black = try bitmap(style: .black, reduceTransparency: false)
        #expect(try #require(black.colorAt(x: 80, y: 30)).alphaComponent == 1)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func bitmap(style: IslandNotchBackground, reduceTransparency: Bool) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: IslandCollapsedMaterial.rendering(
            style: style, reduceTransparency: reduceTransparency
        ).frame(width: 160, height: 32))
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }
}
