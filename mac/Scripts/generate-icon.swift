import AppKit
import Foundation

enum IconTheme: String {
    case day
    case night

    var background: (UInt8, UInt8, UInt8) {
        switch self {
        case .day: (255, 255, 255)
        case .night: (0, 0, 0)
        }
    }

    var foreground: (UInt8, UInt8, UInt8) {
        switch self {
        case .day: (24, 24, 24)
        case .night: (216, 216, 216)
        }
    }
}

guard CommandLine.arguments.count == 5 else {
    FileHandle.standardError.write(
        Data("usage: generate-icon <source> <day|night> <size> <output>\n".utf8)
    )
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let theme = IconTheme(rawValue: CommandLine.arguments[2]),
      let pixels = Int(CommandLine.arguments[3]), pixels > 0,
      let source = NSImage(contentsOf: sourceURL)
else { exit(64) }

let outputURL = URL(fileURLWithPath: CommandLine.arguments[4])
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap),
   let data = bitmap.bitmapData
else { exit(70) }

bitmap.size = NSSize(width: pixels, height: pixels)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
source.draw(
    in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
    from: .zero,
    operation: .copy,
    fraction: 1
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let background = theme.background
let foreground = theme.foreground
for y in 0..<pixels {
    let row = data.advanced(by: y * bitmap.bytesPerRow)
    for x in 0..<pixels {
        let pixel = row.advanced(by: x * 4)
        let luminance = (
            0.2126 * Double(pixel[0])
                + 0.7152 * Double(pixel[1])
                + 0.0722 * Double(pixel[2])
        ) / 255
        let normalized = min(1, max(0, (luminance - 0.35) / 0.30))
        let smoothBackground = normalized * normalized * (3 - 2 * normalized)
        let foregroundCoverage = 1 - smoothBackground
        pixel[0] = UInt8(
            Double(background.0) * smoothBackground
                + Double(foreground.0) * foregroundCoverage
        )
        pixel[1] = UInt8(
            Double(background.1) * smoothBackground
                + Double(foreground.1) * foregroundCoverage
        )
        pixel[2] = UInt8(
            Double(background.2) * smoothBackground
                + Double(foreground.2) * foregroundCoverage
        )
        pixel[3] = 255
    }
}

guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(70) }
try png.write(to: outputURL, options: .atomic)
