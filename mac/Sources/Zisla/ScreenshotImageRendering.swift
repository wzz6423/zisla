import CoreGraphics
import CoreImage

enum ScreenshotImageRendering {
    static func isHDR(_ image: CGImage) -> Bool {
        image.bitmapInfo.contains(.floatComponents)
            || image.colorSpace.map(CGColorSpaceUsesITUR_2100TF) == true
    }

    static func bitmapContext(width: Int, height: Int, matching image: CGImage) -> CGContext? {
        let hdr = isHDR(image)
        return CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: hdr ? 16 : 8, bytesPerRow: 0,
            space: hdr ? CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
                : image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | (hdr ? CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue : 0)
        )
    }

    static func preservingHeadroom(_ image: CGImage, from source: CGImage) -> CGImage? {
        if #available(macOS 15.0, *), isHDR(image) {
            return CGImageCreateCopyWithContentHeadroom(source.contentHeadroom, image)
        }
        return image
    }

    static func render(_ image: CIImage, matching source: CGImage, context: CIContext) -> CGImage? {
        let hdr = isHDR(source)
        guard let rendered = context.createCGImage(
            image, from: image.extent, format: hdr ? .RGBAh : .RGBA8,
            colorSpace: hdr ? CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
                : CGColorSpaceCreateDeviceRGB()
        ) else { return nil }
        return preservingHeadroom(rendered, from: source)
    }

    static func sdrImage(from image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
