import AppKit
import CoreGraphics
import Foundation

private struct AssetSpec {
    let name: String
    let width: Int
    let height: Int
    let markScale: CGFloat
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}

private func drawMark(in context: CGContext, rect: CGRect) {
    let radius = rect.width * 0.22
    let card = CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )

    context.saveGState()
    if rect.width >= 32 {
        context.setShadow(
            offset: CGSize(width: 0, height: -rect.width * 0.025),
            blur: rect.width * 0.08,
            color: NSColor(calibratedWhite: 0.16, alpha: 0.2).cgColor
        )
    }
    context.addPath(card)
    context.clip()
    let surfaceGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedWhite: 1, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.95, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        surfaceGradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )
    context.restoreGState()

    context.addPath(card)
    context.setStrokeColor(
        NSColor(calibratedRed: 0.70, green: 0.76, blue: 0.80, alpha: 0.9).cgColor
    )
    context.setLineWidth(max(1, rect.width * 0.025))
    context.strokePath()

    let zPath = CGMutablePath()
    zPath.move(to: CGPoint(x: rect.minX + rect.width * 0.29, y: rect.minY + rect.height * 0.69))
    zPath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.minY + rect.height * 0.69))
    zPath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.31))
    zPath.addLine(to: CGPoint(x: rect.minX + rect.width * 0.71, y: rect.minY + rect.height * 0.31))

    context.saveGState()
    context.addPath(zPath)
    context.setLineWidth(max(2, rect.width * 0.105))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    let markGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.02, green: 0.55, blue: 0.69, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.04, green: 0.72, blue: 0.55, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        markGradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
    context.restoreGState()

    let statusSize = max(1.5, rect.width * 0.075)
    context.setFillColor(
        NSColor(calibratedRed: 0.97, green: 0.34, blue: 0.31, alpha: 1).cgColor
    )
    context.fillEllipse(in: CGRect(
        x: rect.maxX - rect.width * 0.20,
        y: rect.maxY - rect.height * 0.20,
        width: statusSize,
        height: statusSize
    ))
}

private func renderPNG(width: Int, height: Int, markScale: CGFloat) throws -> Data {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
        throw CocoaError(.fileWriteUnknown)
    }

    let context = graphicsContext.cgContext
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let markSize = min(CGFloat(width), CGFloat(height)) * markScale
    let markRect = CGRect(
        x: (CGFloat(width) - markSize) / 2,
        y: (CGFloat(height) - markSize) / 2,
        width: markSize,
        height: markSize
    )
    drawMark(in: context, rect: markRect)

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

private func makeIcon(frames: [(size: Int, data: Data)]) -> Data {
    var icon = Data()
    icon.appendLittleEndian(UInt16(0))
    icon.appendLittleEndian(UInt16(1))
    icon.appendLittleEndian(UInt16(frames.count))

    let headerSize = 6 + frames.count * 16
    var offset = headerSize
    for frame in frames {
        icon.append(frame.size == 256 ? 0 : UInt8(frame.size))
        icon.append(frame.size == 256 ? 0 : UInt8(frame.size))
        icon.append(0)
        icon.append(0)
        icon.appendLittleEndian(UInt16(1))
        icon.appendLittleEndian(UInt16(32))
        icon.appendLittleEndian(UInt32(frame.data.count))
        icon.appendLittleEndian(UInt32(offset))
        offset += frame.data.count
    }
    for frame in frames {
        icon.append(frame.data)
    }
    return icon
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("用法：generate-assets.swift <输出目录>\n".utf8))
    exit(64)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

private let assets = [
    AssetSpec(name: "Square44x44Logo.png", width: 44, height: 44, markScale: 0.82),
    AssetSpec(name: "StoreLogo.png", width: 50, height: 50, markScale: 0.82),
    AssetSpec(name: "Square150x150Logo.png", width: 150, height: 150, markScale: 0.82),
    AssetSpec(name: "Wide310x150Logo.png", width: 310, height: 150, markScale: 0.70),
    AssetSpec(name: "SplashScreen.png", width: 620, height: 300, markScale: 0.56),
]

for asset in assets {
    let png = try renderPNG(
        width: asset.width,
        height: asset.height,
        markScale: asset.markScale
    )
    try png.write(
        to: outputDirectory.appendingPathComponent(asset.name),
        options: .atomic
    )
}

let iconFrames = try [16, 20, 24, 32, 40, 48, 64, 256].map { size in
    (size: size, data: try renderPNG(width: size, height: size, markScale: 0.88))
}
try makeIcon(frames: iconFrames).write(
    to: outputDirectory.appendingPathComponent("Zisla.ico"),
    options: .atomic
)
