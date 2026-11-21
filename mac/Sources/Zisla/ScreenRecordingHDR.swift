import AVFoundation
import CoreImage

enum RecordingHDR {
    static let pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
    static let colorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)!
    static let colorProperties = [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_SMPTE_ST_2084_PQ,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
    ]

    static func isHDR(_ format: CMFormatDescription) -> Bool {
        let transfer = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
        return transfer == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String
            || transfer == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String
    }

    static func containsHDR(_ track: AVAssetTrack) async throws -> Bool {
        try await track.load(.formatDescriptions).contains(where: isHDR)
    }

    static func image(_ image: CIImage, in bounds: CGRect, context: CIContext, preservesHDR: Bool) throws -> CGImage {
        guard let result = context.createCGImage(image, from: bounds, format: preservesHDR ? .RGBAh : .RGBA8,
                                                 colorSpace: CGColorSpace(name: preservesHDR ? CGColorSpace.extendedLinearSRGB : CGColorSpace.sRGB)),
            let measured = ScreenshotImageRendering.preservingHeadroom(result, from: result) else {
            throw ScreenRecordingExportError.cannotRender
        }
        return measured
    }
}
