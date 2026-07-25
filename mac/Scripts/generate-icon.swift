import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: generate-icon <size> <output>\n".utf8))
    exit(64)
}

guard let pixels = Int(CommandLine.arguments[1]), pixels > 0 else { exit(64) }
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let size = NSSize(width: pixels, height: pixels)
let image = NSImage(size: size)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { exit(70) }
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let canvas = CGRect(origin: .zero, size: CGSize(width: pixels, height: pixels))
let outerRadius = CGFloat(pixels) * 0.22
let outer = CGPath(
    roundedRect: canvas.insetBy(dx: CGFloat(pixels) * 0.045, dy: CGFloat(pixels) * 0.045),
    cornerWidth: outerRadius,
    cornerHeight: outerRadius,
    transform: nil
)
context.addPath(outer)
context.setFillColor(NSColor(calibratedRed: 0.035, green: 0.039, blue: 0.047, alpha: 1).cgColor)
context.fillPath()

let glowRect = canvas.insetBy(dx: CGFloat(pixels) * 0.12, dy: CGFloat(pixels) * 0.12)
let colors = [
    NSColor(calibratedRed: 0.35, green: 0.80, blue: 0.98, alpha: 0.35).cgColor,
    NSColor(calibratedRed: 0.38, green: 0.90, blue: 0.69, alpha: 0).cgColor,
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
context.saveGState()
context.addPath(outer)
context.clip()
context.drawRadialGradient(
    gradient,
    startCenter: CGPoint(x: glowRect.minX, y: glowRect.maxY),
    startRadius: 0,
    endCenter: CGPoint(x: glowRect.midX, y: glowRect.midY),
    endRadius: CGFloat(pixels) * 0.68,
    options: []
)
context.restoreGState()

let islandRect = CGRect(
    x: CGFloat(pixels) * 0.17,
    y: CGFloat(pixels) * 0.37,
    width: CGFloat(pixels) * 0.66,
    height: CGFloat(pixels) * 0.27
)
let island = CGPath(
    roundedRect: islandRect,
    cornerWidth: islandRect.height / 2,
    cornerHeight: islandRect.height / 2,
    transform: nil
)
context.addPath(island)
context.setFillColor(NSColor.black.cgColor)
context.fillPath()
context.addPath(island)
context.setStrokeColor(NSColor.white.withAlphaComponent(0.26).cgColor)
context.setLineWidth(max(1, CGFloat(pixels) * 0.012))
context.strokePath()

let dotRadius = CGFloat(pixels) * 0.033
context.setFillColor(NSColor(calibratedRed: 0.35, green: 0.80, blue: 0.98, alpha: 1).cgColor)
context.fillEllipse(in: CGRect(
    x: CGFloat(pixels) * 0.5 - dotRadius,
    y: CGFloat(pixels) * 0.505 - dotRadius,
    width: dotRadius * 2,
    height: dotRadius * 2
))

image.unlockFocus()
guard
    let data = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: data),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    exit(70)
}
try png.write(to: outputURL, options: .atomic)
