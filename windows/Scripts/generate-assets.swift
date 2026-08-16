import AppKit
import CoreGraphics
import Foundation

private struct AssetSpec {
    let name: String
    let width: Int
    let height: Int
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

private func renderPNG(
    source: NSImage,
    background: NSColor,
    width: Int,
    height: Int
) throws -> Data {
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

    bitmap.size = NSSize(width: width, height: height)
    let imageSize = min(CGFloat(width), CGFloat(height))
    let imageRect = NSRect(
        x: (CGFloat(width) - imageSize) / 2,
        y: (CGFloat(height) - imageSize) / 2,
        width: imageSize,
        height: imageSize
    )
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    background.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    graphicsContext.imageInterpolation = .high
    source.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1)
    graphicsContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

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

guard CommandLine.arguments.count == 4 else {
    FileHandle.standardError.write(
        Data("用法：generate-assets.swift <日间源图> <夜间源图> <输出目录>\n".utf8)
    )
    exit(64)
}

guard let daySource = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let nightSource = NSImage(contentsOfFile: CommandLine.arguments[2])
else {
    FileHandle.standardError.write(Data("无法读取图标源图\n".utf8))
    exit(66)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

private let assets = [
    AssetSpec(name: "Square44x44Logo.png", width: 44, height: 44),
    AssetSpec(name: "StoreLogo.png", width: 50, height: 50),
    AssetSpec(name: "Square150x150Logo.png", width: 150, height: 150),
    AssetSpec(name: "Wide310x150Logo.png", width: 310, height: 150),
    AssetSpec(name: "SplashScreen.png", width: 620, height: 300),
]

for asset in assets {
    let png = try renderPNG(
        source: daySource,
        background: .white,
        width: asset.width,
        height: asset.height
    )
    try png.write(
        to: outputDirectory.appendingPathComponent(asset.name),
        options: .atomic
    )
}

let iconSizes = [16, 20, 24, 32, 40, 48, 64, 256]
let dayIconFrames = try iconSizes.map { size in
    (size: size, data: try renderPNG(
        source: daySource,
        background: .white,
        width: size,
        height: size
    ))
}
let nightIconFrames = try iconSizes.map { size in
    (size: size, data: try renderPNG(
        source: nightSource,
        background: .black,
        width: size,
        height: size
    ))
}
try makeIcon(frames: dayIconFrames).write(
    to: outputDirectory.appendingPathComponent("Zisla.ico"),
    options: .atomic
)
try makeIcon(frames: dayIconFrames).write(
    to: outputDirectory.appendingPathComponent("TrayIconDay.ico"),
    options: .atomic
)
try makeIcon(frames: nightIconFrames).write(
    to: outputDirectory.appendingPathComponent("TrayIconNight.ico"),
    options: .atomic
)
