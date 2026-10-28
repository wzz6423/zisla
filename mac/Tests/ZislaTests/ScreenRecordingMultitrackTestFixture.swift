import AppKit
import AVFoundation
import CoreImage
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
final class RecordingMultitrackTestFixture {
    let root: URL
    let directory: URL
    var store: ScreenRecordingProjectStore { .init(root: root) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-multitrack-tests-\(UUID())", isDirectory: true)
        directory = root.appendingPathComponent("fixture.zisla-recording", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
    func files() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() }

    func project() -> ScreenRecordingProject {
        var project = ScreenRecordingProject(name: "Multitrack fixture", videoFile: "screen.mp4", duration: 2, width: 64, height: 48)
        project.edits.background = .none
        project.edits.showCursor = false
        project.edits.clickEffects = false
        return project
    }

    func model() throws -> ScreenRecordingStudioModel {
        let image = try #require(CIContext().createCGImage(CIImage(color: .black), from: CGRect(x: 0, y: 0, width: 64, height: 48)))
        return ScreenRecordingStudioModel(projectStore: store, renderPreview: { _, _, _ in image })
    }

    func createImage(_ name: String = "picture.png", size: CGSize = .init(width: 64, height: 48),
                     color: CIColor = .init(red: 0, green: 1, blue: 0)) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let image = try #require(CIContext().createCGImage(CIImage(color: color), from: CGRect(origin: .zero, size: size)))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return url
    }

    func createTone(_ name: String = "tone.wav") throws -> URL {
        let url = directory.appendingPathComponent(name)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000))
        buffer.frameLength = 96_000
        let channel = try #require(buffer.floatChannelData?[0])
        for index in 0..<96_000 { channel[index] = Float(0.15 * sin(2 * .pi * 440 * Double(index) / 48_000)) }
        try file.write(from: buffer)
        return url
    }

    func createVideo(_ name: String = "screen.mp4", size: CGSize = .init(width: 64, height: 48), duration: Double = 2,
                     colors: [CIColor] = [.init(red: 1, green: 0, blue: 0), .init(red: 0, green: 0, blue: 1)]) async throws -> URL {
        let url = directory.appendingPathComponent(name)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        try #require(writer.startWriting())
        defer { if writer.status == .writing { writer.cancelWriting() } }
        writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        let count = Int((duration * 8).rounded())
        for index in 0..<count {
            while !input.isReadyForMoreMediaData { try Task.checkCancellation(); await Task.yield() }
            var buffer: CVPixelBuffer?
            try #require(CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer) == kCVReturnSuccess)
            let color = colors[min(colors.count - 1, index * colors.count / count)]
            context.render(CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size)), to: try #require(buffer),
                bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            try #require(adaptor.append(try #require(buffer), withPresentationTime: .init(value: Int64(index), timescale: 8)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: .init(seconds: duration, preferredTimescale: 600))
        await writer.finishWriting()
        try #require(writer.status == .completed)
        return url
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { pointer in
            let context = try #require(CGContext(data: pointer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = (y * image.width + x) * 4
        return Array(bytes[offset..<offset + 3])
    }

    static func decode(_ asset: AVAsset, composition: AVVideoComposition? = nil) async throws -> [(Double, CGImage)] {
        let reader = try AVAssetReader(asset: asset)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let output: AVAssetReaderOutput
        let settings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if let composition {
            let composed = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: settings)
            composed.videoComposition = composition
            output = composed
        } else { output = AVAssetReaderTrackOutput(track: try #require(tracks.first), outputSettings: settings) }
        reader.add(output)
        try #require(reader.startReading())
        defer { reader.cancelReading() }
        let context = CIContext()
        var frames: [(Double, CGImage)] = []
        while let sample = output.copyNextSampleBuffer() {
            let source = CIImage(cvPixelBuffer: try #require(sample.imageBuffer))
            frames.append((sample.presentationTimeStamp.seconds, try #require(context.createCGImage(source, from: source.extent))))
        }
        #expect(reader.status == .completed && reader.error == nil, "The entire timeline must decode without dropped media")
        return frames
    }
}
