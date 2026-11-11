import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageWatermarkOverlay {
    let url: URL
    let x: Int
    let y: Int
}

struct ImageWatermarkRenderer {
    enum Content {
        case text(String)
        case image(CGImage)
    }

    let options: ImageWatermarkOptions
    let content: Content

    func render(width: Int, height: Int, to url: URL,
                createDestination: (URL) -> CGImageDestination? = { CGImageDestinationCreateWithURL($0 as CFURL, UTType.png.identifier as CFString, 1, nil) }) throws -> ImageWatermarkOverlay {
        let inset = min(16, Int((Double(min(width, height)) * 0.03).rounded(.down)))
        let available = CGSize(width: width - 2 * inset, height: height - 2 * inset)
        let desiredWidth = min(available.width, CGFloat(width) * options.scale)
        let layout: CGSize
        let framesetter: CTFramesetter?
        switch content {
        case let .text(text):
            let value = options.colorValue!
            let color = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [
                CGFloat((value >> 16) & 255) / 255, CGFloat((value >> 8) & 255) / 255, CGFloat(value & 255) / 255, 1,
            ])!
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 48, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]
            let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: text.utf16.count), nil,
                CGSize(width: 1_024, height: CGFloat.greatestFiniteMagnitude), nil)
            layout = CGSize(width: ceil(size.width) + 2, height: ceil(size.height) + 2)
            framesetter = setter
        case let .image(image):
            layout = CGSize(width: image.width, height: image.height)
            framesetter = nil
        }
        let factor = min(desiredWidth / layout.width, available.height / layout.height)
        let size = CGSize(width: max(1, ceil(layout.width * factor)), height: max(1, ceil(layout.height * factor)))
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw ImageProcessingError.resourceLimit
        }
        context.setAlpha(options.opacity)
        context.interpolationQuality = .high
        switch content {
        case let .text(text):
            context.scaleBy(x: factor, y: factor)
            let frame = CTFramesetterCreateFrame(framesetter!, CFRange(location: 0, length: text.utf16.count),
                CGPath(rect: CGRect(origin: .zero, size: layout), transform: nil), nil)
            CTFrameDraw(frame, context)
        case let .image(image): context.draw(image, in: CGRect(origin: .zero, size: size))
        }
        try Task.checkCancellation()
        guard let image = context.makeImage(),
              let destination = createDestination(url) else {
            throw ImageProcessingError.invalidOutput
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageProcessingError.invalidOutput }
        let x: Int
        let y: Int
        switch options.position {
        case .center: x = (width - image.width) / 2; y = (height - image.height) / 2
        case .topLeft: x = inset; y = inset
        case .topRight: x = width - inset - image.width; y = inset
        case .bottomLeft: x = inset; y = height - inset - image.height
        case .bottomRight: x = width - inset - image.width; y = height - inset - image.height
        }
        return ImageWatermarkOverlay(url: url, x: x, y: y)
    }
}
