import AppKit
import SwiftUI
import Testing

@testable import Zisla

@MainActor
struct ScreenshotSelectionSizeBadgeTests {
    @Test(arguments: [
        (CGSize.zero, nil, "0 × 0"),
        (CGSize(width: 300, height: 200), nil, "300 × 200"),
        (CGSize(width: 300.4, height: 200.6), nil, "300 × 201"),
        (CGSize(width: 3_840, height: 2_160), CGFloat(0), "3840 × 2160 · r: 0"),
        (CGSize(width: 452, height: 300), CGFloat(205), "452 × 300 · r: 205"),
        (CGSize(width: 140, height: 20), CGFloat(10.6), "140 × 20 · r: 11"),
        (CGSize(width: 16_384, height: 8_192), CGFloat(4_096), "16384 × 8192 · r: 4096"),
    ])
    func measurementMatchesTheRenderedReadout(scenario: (size: CGSize, radius: CGFloat?, label: String)) throws {
        let badge = ScreenshotSelectionSizeBadge(
            selection: CGRect(origin: .zero, size: scenario.size),
            bounds: CGSize(width: 800, height: 600),
            cornerRadius: scenario.radius
        )
        let reference = ImageRenderer(content: Text(scenario.label)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .fixedSize())
        var referenceSize: CGSize?
        reference.render { size, _ in referenceSize = size }
        let size = try #require(referenceSize, "The reference readout must produce a layout size")
        #expect(badge.badgeSize == size, "Positioning must use the full padded readout size")
    }

    @Test(arguments: [
        CGRect(x: 200, y: 100, width: 300, height: 200),
        CGRect(x: 660, y: 0, width: 140, height: 20),
        CGRect(x: 0, y: 0, width: 800, height: 600),
    ], [CGFloat(1), 2])
    func renderedReadoutStaysInsideTheScreen(selection: CGRect, scale: CGFloat) throws {
        let bounds = CGSize(width: 800, height: 600)
        let badge = ScreenshotSelectionSizeBadge(selection: selection, bounds: bounds, cornerRadius: 10)
        let position = ScreenshotSelectionGeometry.badgePosition(
            for: selection, in: bounds, badgeSize: badge.badgeSize
        )
        let frame = CGRect(
            x: position.x - badge.badgeSize.width / 2,
            y: position.y - badge.badgeSize.height / 2,
            width: badge.badgeSize.width,
            height: badge.badgeSize.height
        )
        #expect(CGRect(origin: .zero, size: bounds).contains(frame))

        let renderer = ImageRenderer(content: badge.frame(width: bounds.width, height: bounds.height))
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let center = try #require(bitmap.colorAt(x: Int(position.x * scale), y: Int(position.y * scale)))
        #expect(center.alphaComponent > 0.6, "The readout must still render at its computed position")
    }
}
