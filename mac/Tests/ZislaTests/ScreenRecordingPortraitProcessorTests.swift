import CoreImage
import Foundation
import Testing
import ZislaCore
@testable import Zisla

struct ScreenRecordingPortraitProcessorTests {
    private let face = CGRect(x: 0.3, y: 0.55, width: 0.4, height: 0.3)
    private let body = CGRect(x: 0.2, y: 0.05, width: 0.6, height: 0.9)

    @Test func disabledEffectsSkipDetectionAndPreserveEveryPixel() throws {
        let image = try chart()
        let processor = RecordingPortraitProcessor { _, _, _ in
            Issue.record("Disabled effects must not start portrait detection")
            return .init()
        }
        let output = try processor.apply(image, effects: .init())
        #expect(output === image)
        #expect(try bytes(output) == bytes(image))
    }

    @Test func absentPeopleLeaveTheFrameUnchanged() throws {
        let image = try chart()
        let processor = RecordingPortraitProcessor { _, _, _ in .init() }
        let output = try processor.apply(image, effects: .init(smoothing: 1, brightening: 1, faceSlimming: 1, bodySlimming: 1))
        #expect(try bytes(output) == bytes(image))
        #expect(output.extent == image.extent)
    }

    @Test func productionVisionLeavesAnEmptySceneUnchanged() throws {
        let image = CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: 192, height: 192))
        let output = try RecordingPortraitProcessor().apply(image,
            effects: .init(smoothing: 1, brightening: 1, faceSlimming: 1, bodySlimming: 1))
        #expect(try bytes(output) == bytes(image), "A scene without a person must remain unchanged through real Vision detection")
    }

    @Test(arguments: ["smoothing", "brightening", "faceSlimming", "bodySlimming"])
    func eachEffectChangesLocalPixelsAndProtectsTheBackground(_ effect: String) throws {
        let image = try chart()
        let processor = RecordingPortraitProcessor { _, _, _ in .init(faces: [face], bodies: [body]) }
        let effects: RecordingPortraitEffects
        switch effect {
        case "smoothing": effects = .init(smoothing: 1)
        case "brightening": effects = .init(brightening: 1)
        case "faceSlimming": effects = .init(faceSlimming: 1)
        default: effects = .init(bodySlimming: 1)
        }
        let output = try processor.apply(image, effects: effects)
        let before = try bytes(image)
        let after = try bytes(output)
        #expect(output.extent == image.extent)
        #expect(before != after, "\(effect) must change actual portrait pixels")
        var changed = 0
        for y in 0..<192 {
            for x in 0..<192 {
                let offset = (y * 192 + x) * 4
                if before[offset..<offset + 3] != after[offset..<offset + 3] { changed += 1 }
                #expect(before[offset + 3] == after[offset + 3], "The portrait effects must preserve alpha")
                if x < 24 || x > 168 || y < 6 || y > 186 {
                    #expect(before[offset..<offset + 4] == after[offset..<offset + 4], "The distant background must remain unchanged")
                }
            }
        }
        #expect(changed > 25, "\(effect) must affect the portrait region")
    }

    @Test func brighteningRaisesFaceLuminanceAndSmoothingReducesNoise() throws {
        let image = try chart()
        let processor = RecordingPortraitProcessor { _, _, _ in .init(faces: [face]) }
        let original = try bytes(image)
        let brightened = try bytes(processor.apply(image, effects: .init(brightening: 1)))
        let smoothed = try bytes(processor.apply(image, effects: .init(smoothing: 1)))
        var beforeContrast = 0
        var afterContrast = 0
        var beforeLight = 0
        var afterLight = 0
        for y in 47..<66 {
            for x in 80..<110 {
                let offset = (y * 192 + x) * 4
                beforeContrast += abs(Int(original[offset]) - Int(original[offset + 4]))
                afterContrast += abs(Int(smoothed[offset]) - Int(smoothed[offset + 4]))
                beforeLight += Int(original[offset])
                afterLight += Int(brightened[offset])
            }
        }
        #expect(afterLight > beforeLight)
        #expect(afterContrast < beforeContrast, "Skin smoothing must reduce local high frequency noise")
    }

    @Test func shrinkingIsLocalAndDoesNotScaleTheWholeImage() throws {
        let image = try chart()
        let processor = RecordingPortraitProcessor { _, _, _ in .init(bodies: [body]) }
        let result = try bytes(processor.apply(image, effects: .init(bodySlimming: 1)))
        let baseline = try bytes(image)
        for x in 0..<192 {
            let offset = (191 * 192 + x) * 4
            #expect(result[offset..<offset + 4] == baseline[offset..<offset + 4])
        }
        #expect(result != baseline)
    }

    @Test(arguments: [false, true])
    func slimmingNarrowsThePortraitSilhouette(_ faceEffect: Bool) throws {
        let region = faceEffect ? face : body
        let extent = CGRect(x: 0, y: 0, width: 192, height: 192)
        let silhouette = CGRect(x: (region.midX - region.width * 0.25) * 192, y: region.minY * 192,
            width: region.width * 0.5 * 192, height: region.height * 192)
        let image = CIImage(color: .white).cropped(to: silhouette)
            .composited(over: CIImage(color: .black).cropped(to: extent))
        let processor = RecordingPortraitProcessor { _, _, _ in .init(faces: [face], bodies: [body]) }
        let output = try processor.apply(image, effects: faceEffect ? .init(faceSlimming: 1) : .init(bodySlimming: 1))
        let baseline = try bytes(image)
        let result = try bytes(output)
        let row = Int((1 - region.midY) * 192)
        let beforeWidth = (0..<192).filter { baseline[(row * 192 + $0) * 4] > 128 }.count
        let afterWidth = (0..<192).filter { result[(row * 192 + $0) * 4] > 128 }.count
        #expect(afterWidth < beforeWidth, "Slimming must narrow the portrait silhouette rather than shift its color")
    }

    @Test(arguments: [false, true])
    func skinEffectsPreserveTranslucentAlpha(_ smoothing: Bool) throws {
        let extent = CGRect(x: 0, y: 0, width: 192, height: 192)
        let image = CIImage(color: CIColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 0.45)).cropped(to: extent)
        let processor = RecordingPortraitProcessor { _, _, _ in .init(faces: [face]) }
        let result = try bytes(processor.apply(image, effects: smoothing ? .init(smoothing: 1) : .init(brightening: 1)))
        let baseline = try bytes(image)
        #expect(stride(from: 3, to: result.count, by: 4).allSatisfy { result[$0] == baseline[$0] })
    }

    @Test func brighteningRetainsTheEllipticalMaskAndItsFeather() throws {
        let extent = CGRect(x: 0, y: 0, width: 192, height: 192)
        let region = CGRect(x: 56.5 / 192, y: 76.5 / 192, width: 80.0 / 192, height: 40.0 / 192)
        let image = CIImage(color: CIColor(red: 0.25, green: 0.25, blue: 0.25)).cropped(to: extent)
        let processor = RecordingPortraitProcessor { _, _, _ in .init(faces: [region]) }
        let output = try processor.apply(image, effects: .init(brightening: 0.6))
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        for (x, y, feather) in [(96, 96, 1.0), (124, 96, 1.0), (130, 96, 0.5),
            (136, 96, 0.0), (96, 113, 0.5), (120, 112, 0.0), (40, 40, 0.0)] {
            let result = pixel(output, x: x, y: y, context: context)
            let expected = Float(0.25 * (1 + (pow(2, 0.35) - 1) * 0.6 * feather))
            #expect(result.prefix(3).allSatisfy { abs($0 - expected) < 0.000_01 },
                "Brightening must retain the original elliptical inner area, feather, and protected background at (\(x), \(y))")
            #expect(result[3] == 1)
        }
    }

    @Test(arguments: [false, true])
    func slimmingRetainsTheOriginalDisplacementCurve(_ faceEffect: Bool) throws {
        var pixels = [Float](repeating: 1, count: 192 * 192 * 4)
        for y in 0..<192 {
            for x in 0..<192 {
                let offset = (y * 192 + x) * 4
                pixels[offset] = Float(x) / 192
                pixels[offset + 1] = 0.2
                pixels[offset + 2] = 0.3
            }
        }
        let image = pixels.withUnsafeBytes { pointer in
            CIImage(bitmapData: Data(pointer), bytesPerRow: 192 * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: 192, height: 192), format: .RGBAf, colorSpace: nil)
        }
        let region = CGRect(x: 56.5 / 192, y: 76.5 / 192, width: 80.0 / 192, height: 40.0 / 192)
        let processor = RecordingPortraitProcessor { _, _, _ in .init(faces: [region], bodies: [region]) }
        let output = try processor.apply(image, effects: faceEffect ? .init(faceSlimming: 0.6) : .init(bodySlimming: 0.6))
        let amount = 0.6 * (faceEffect ? 0.22 : 0.18)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        for (x, y, displacement) in [(96, 96, 0.0), (116, 96, 11.25 * amount),
            (116, 106, 5 * amount), (136, 96, 0.0), (20, 20, 0.0)] {
            let result = pixel(output, x: x, y: y, context: context)
            #expect(abs(result[0] - Float((Double(x) + displacement) / 192)) < 0.000_01,
                "Slimming must retain its original horizontal sampling displacement at (\(x), \(y))")
            #expect(abs(result[1] - 0.2) < 0.000_01 && abs(result[2] - 0.3) < 0.000_01 && result[3] == 1)
        }
    }

    @Test func partialRenderUsesTheSameWarpedSourcePixels() throws {
        let image = try chart().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1])
            .cropped(to: CGRect(x: 0, y: 0, width: 192, height: 192))
        let processor = RecordingPortraitProcessor { _, _, _ in .init(bodies: [body]) }
        let output = try processor.apply(image, effects: .init(bodySlimming: 1))
        let whole = try bytes(output)
        let rectangle = CGRect(x: 111, y: 90, width: 4, height: 4)
        var cropped = [UInt8](repeating: 0, count: 4 * 4 * 4)
        cropped.withUnsafeMutableBytes { pointer in
            CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!]).render(output,
                toBitmap: pointer.baseAddress!, rowBytes: 4 * 4, bounds: rectangle, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
        for y in 0..<4 {
            for x in 0..<4 {
                let actual = (y * 4 + x) * 4
                let expected = ((192 - 94 + y) * 192 + 111 + x) * 4
                #expect(cropped[actual..<actual + 4] == whole[expected..<expected + 4])
            }
        }
    }

    @Test func cancellationPreventsDetection() async throws {
        let image = try chart()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let processor = RecordingPortraitProcessor { _, _, _ in
                Issue.record("Cancelled work must not reach Vision")
                return .init()
            }
            return try processor.apply(image, effects: .init(brightening: 1))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func detectionUsesBoundedImagesAndReusesOnlyAdjacentFrames() throws {
        var calls: [CGSize] = []
        let processor = RecordingPortraitProcessor { image, faces, bodies in
            calls.append(image.extent.size)
            #expect(faces && !bodies)
            return .init()
        }
        let image = CIImage(color: .black).cropped(to: CGRect(x: 17, y: 23, width: 3840, height: 2160))
        let effects = RecordingPortraitEffects(brightening: 1)
        _ = try processor.apply(image, effects: effects, sourceTime: 0)
        _ = try processor.apply(image, effects: effects, sourceTime: 0.03)
        _ = try processor.apply(image, effects: effects, sourceTime: 0.1)
        #expect(calls.count == 1)
        #expect(calls[0] == CGSize(width: 512, height: 288))
        _ = try processor.apply(image, effects: effects, sourceTime: 0.16)
        #expect(calls.count == 2)
        _ = try processor.apply(image, effects: effects, sourceTime: 0.02)
        #expect(calls.count == 3, "Seeking backwards must discard the previous portrait locations")
        let smaller = image.cropped(to: CGRect(x: 17, y: 23, width: 1920, height: 1080))
        _ = try processor.apply(smaller, effects: effects, sourceTime: 0.03)
        #expect(calls.count == 4, "A resized source must be detected again")
        _ = try processor.apply(smaller, effects: .init(), sourceTime: 0.04)
        _ = try processor.apply(smaller, effects: effects, sourceTime: 0.05)
        #expect(calls.count == 5, "Disabling and enabling effects must not retain old detections")
    }

    @Test func staticImagesAndNewDetectionKindsNeverUseStaleRegions() throws {
        var requests: [(Bool, Bool)] = []
        let processor = RecordingPortraitProcessor { _, faces, bodies in requests.append((faces, bodies)); return .init() }
        let image = try chart()
        _ = try processor.apply(image, effects: .init(smoothing: 1))
        _ = try processor.apply(image, effects: .init(smoothing: 1))
        _ = try processor.apply(image, effects: .init(bodySlimming: 1), sourceTime: 0)
        _ = try processor.apply(image, effects: .init(smoothing: 1, bodySlimming: 1), sourceTime: 0.01)
        #expect(requests.count == 4)
        #expect(requests[0].0 && !requests[0].1)
        #expect(!requests[2].0 && requests[2].1)
        #expect(requests[3].0 && requests[3].1)
    }

    @Test func malformedRegionsAreDiscardedAndWorkIsLimitedToFourPortraits() throws {
        let image = try chart()
        let invalid = [CGRect(x: Double.nan, y: 0, width: 1, height: 1), CGRect.zero,
            CGRect(x: 2, y: 2, width: 1, height: 1), CGRect(x: 0, y: 0, width: -1, height: 1)]
        let rejects = RecordingPortraitProcessor { _, _, _ in .init(faces: invalid, bodies: invalid) }
        #expect(try bytes(rejects.apply(image, effects: .init(brightening: 1, bodySlimming: 1))) == bytes(image))
        let crowded = RecordingPortraitProcessor { _, _, _ in .init(faces: Array(repeating: face, count: 40)) }
        let limited = RecordingPortraitProcessor { _, _, _ in .init(faces: Array(repeating: face, count: 4)) }
        #expect(try bytes(crowded.apply(image, effects: .init(brightening: 1)))
            == bytes(limited.apply(image, effects: .init(brightening: 1))))
    }

    @Test func nonzeroExtentOriginRetainsTheSamePortraitLocation() throws {
        let image = try chart()
        let moved = image.transformed(by: CGAffineTransform(translationX: 21, y: -12))
        let processor = RecordingPortraitProcessor { _, _, _ in .init(faces: [face], bodies: [body]) }
        let effects = RecordingPortraitEffects(brightening: 1, faceSlimming: 1, bodySlimming: 1)
        let reference = try processor.apply(image, effects: effects)
        let result = try processor.apply(moved, effects: effects)
        #expect(result.extent == moved.extent)
        #expect(try bytes(result) == bytes(reference))
    }

    @Test func detectionFailureIsSurfacedAndCannotReusePreviousRegions() throws {
        enum Failure: Error { case unavailable }
        var calls = 0
        let processor = RecordingPortraitProcessor { _, _, _ in
            calls += 1
            if calls == 2 { throw Failure.unavailable }
            return .init(faces: [face])
        }
        let image = try chart()
        _ = try processor.apply(image, effects: .init(brightening: 1), sourceTime: 0)
        #expect(throws: Failure.unavailable) { try processor.apply(image, effects: .init(brightening: 1), sourceTime: 1) }
        _ = try processor.apply(image, effects: .init(brightening: 1), sourceTime: 0.03)
        #expect(calls == 3)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -0.001, 1.000_001])
    func invalidEffectsAreRejectedBeforeDetection(_ strength: Double) throws {
        let image = try chart()
        let processor = RecordingPortraitProcessor { _, _, _ in
            Issue.record("Invalid effects must not reach Vision")
            return .init()
        }
        #expect(throws: ScreenRecordingExportError.invalidConfiguration) {
            try processor.apply(image, effects: .init(smoothing: strength))
        }
    }

    @Test func invalidFrameAndTimeAreRejectedBeforeDetection() throws {
        let processor = RecordingPortraitProcessor { _, _, _ in
            Issue.record("Invalid frames must not reach Vision")
            return .init()
        }
        #expect(throws: ScreenRecordingExportError.invalidConfiguration) {
            try processor.apply(CIImage(color: .black), effects: .init(brightening: 1))
        }
        #expect(throws: ScreenRecordingExportError.invalidConfiguration) {
            try processor.apply(CIImage.empty(), effects: .init(brightening: 1))
        }
        #expect(throws: ScreenRecordingExportError.invalidConfiguration) {
            try processor.apply(chart(), effects: .init(brightening: 1), sourceTime: .nan)
        }
    }

    private func chart() throws -> CIImage {
        var pixels = [UInt8](repeating: 0, count: 192 * 192 * 4)
        for y in 0..<192 {
            for x in 0..<192 {
                let offset = (y * 192 + x) * 4
                let inFace = (58..<135).contains(x) && (28..<86).contains(y)
                let base = inFace ? 140 : 60 + x / 2
                pixels[offset] = UInt8(base + (inFace && (x + y) % 2 == 0 ? 8 : 0))
                pixels[offset + 1] = UInt8(inFace ? 100 + (x + y) % 2 * 8 : y / 2)
                pixels[offset + 2] = UInt8(inFace ? 70 : 120)
                pixels[offset + 3] = 255
            }
        }
        return CIImage(bitmapData: Data(pixels), bytesPerRow: 192 * 4,
            size: CGSize(width: 192, height: 192), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    private func bytes(_ image: CIImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 192 * 192 * 4)
        bytes.withUnsafeMutableBytes { pointer in
            CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!]).render(image,
                toBitmap: pointer.baseAddress!, rowBytes: 192 * 4, bounds: image.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
        return bytes
    }

    private func pixel(_ image: CIImage, x: Int, y: Int, context: CIContext) -> [Float] {
        var pixel = [Float](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { pointer in
            context.render(image, toBitmap: pointer.baseAddress!, rowBytes: 4 * MemoryLayout<Float>.size,
                bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        }
        return pixel
    }
}
