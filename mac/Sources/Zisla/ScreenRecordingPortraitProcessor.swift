import CoreImage
import Foundation
import Vision
import ZislaCore

final class RecordingPortraitProcessor {
    struct Regions {
        var faces: [CGRect] = []
        var bodies: [CGRect] = []
    }

    struct Kernels {
        let mask: CIColorKernel
        let warp: CIWarpKernel

        init(library: Data) throws {
            mask = try CIColorKernel(functionName: "portraitMask", fromMetalLibraryData: library)
            warp = try CIWarpKernel(functionName: "portraitSlim", fromMetalLibraryData: library)
        }
    }

    typealias Detector = (CIImage, Bool, Bool) throws -> Regions
    private let detector: Detector
    private let kernels: () -> Kernels?
    private var detection: (size: CGSize, time: Double?, faces: Bool, bodies: Bool, regions: Regions)?

    init(detector: @escaping Detector = RecordingPortraitProcessor.detect,
         kernels: @autoclosure @escaping () -> Kernels? = RecordingPortraitProcessor.kernels) {
        self.detector = detector
        self.kernels = kernels
    }

    func apply(_ image: CIImage, effects: RecordingPortraitEffects, sourceTime: Double? = nil) throws -> CIImage {
        guard effects.isValid, sourceTime.map(\.isFinite) != false else { throw ScreenRecordingExportError.invalidConfiguration }
        guard effects.isEnabled else { detection = nil; return image }
        let extent = image.extent
        guard [extent.minX, extent.minY, extent.width, extent.height].allSatisfy(\.isFinite),
              !extent.isEmpty, !extent.isInfinite else {
            throw ScreenRecordingExportError.invalidConfiguration
        }
        try Task.checkCancellation()
        let needsFaces = effects.smoothing > 0 || effects.brightening > 0 || effects.faceSlimming > 0
        let needsBodies = effects.bodySlimming > 0
        let reusable = detection.map { cached in
            cached.size == extent.size && cached.faces == needsFaces && cached.bodies == needsBodies
                && sourceTime.flatMap { time in cached.time.map { time >= $0 && time - $0 < 0.15 } } == true
        } ?? false
        if !reusable {
            detection = nil
            let scale = min(1, 512 / max(extent.width, extent.height))
            let reduced = image.transformed(by: CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                tx: -extent.minX * scale, ty: -extent.minY * scale))
            let found = try detector(reduced, needsFaces, needsBodies)
            detection = (extent.size, sourceTime, needsFaces, needsBodies,
                Regions(faces: Self.bounded(found.faces), bodies: Self.bounded(found.bodies)))
        }
        let regions = detection!.regions
        var output = image
        if effects.smoothing > 0 || effects.brightening > 0 {
            for face in regions.faces {
                let rectangle = Self.rectangle(face, in: extent)
                if effects.smoothing > 0 {
                    let softened = output.applyingFilter("CINoiseReduction", parameters: [
                        "inputNoiseLevel": 0.04 + 0.12 * effects.smoothing, "inputSharpness": 0.4,
                    ])
                    output = try blend(softened, over: output, region: rectangle, amount: effects.smoothing)
                }
                if effects.brightening > 0 {
                    let brighter = output.applyingFilter("CIExposureAdjust", parameters: ["inputEV": 0.35])
                    output = try blend(brighter, over: output, region: rectangle, amount: effects.brightening)
                }
            }
        }
        if effects.bodySlimming > 0 {
            for body in regions.bodies {
                output = try slim(output, region: Self.rectangle(body, in: extent), amount: effects.bodySlimming * 0.18)
            }
        }
        if effects.faceSlimming > 0 {
            for face in regions.faces {
                output = try slim(output, region: Self.rectangle(face, in: extent), amount: effects.faceSlimming * 0.22)
            }
        }
        return output.cropped(to: extent)
    }

    private static func bounded(_ rectangles: [CGRect]) -> [CGRect] {
        rectangles.compactMap { rectangle in
            guard [rectangle.minX, rectangle.minY, rectangle.width, rectangle.height].allSatisfy(\.isFinite),
                  rectangle.width > 0, rectangle.height > 0 else { return nil }
            let clipped = rectangle.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            return clipped.isEmpty || clipped.isNull ? nil : clipped
        }.sorted { $0.width * $0.height > $1.width * $1.height }.prefix(4).map { $0 }
    }

    private static func rectangle(_ normalized: CGRect, in extent: CGRect) -> CGRect {
        CGRect(x: extent.minX + normalized.minX * extent.width, y: extent.minY + normalized.minY * extent.height,
            width: normalized.width * extent.width, height: normalized.height * extent.height)
    }

    private static func detect(_ image: CIImage, faces: Bool, bodies: Bool) throws -> Regions {
        let faceRequest = VNDetectFaceRectanglesRequest()
        let bodyRequest = VNDetectHumanRectanglesRequest()
        bodyRequest.upperBodyOnly = false
        var requests: [VNRequest] = []
        if faces { requests.append(faceRequest) }
        if bodies { requests.append(bodyRequest) }
        try VNImageRequestHandler(ciImage: image).perform(requests)
        return Regions(faces: faceRequest.results?.map(\.boundingBox) ?? [],
            bodies: bodyRequest.results?.map(\.boundingBox) ?? [])
    }

    private static let kernels: Kernels? = {
        #if SWIFT_PACKAGE && !SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "RecordingPortraitKernels", withExtension: "metallib") else { return nil }
        return try? Kernels(library: Data(contentsOf: url))
    }()

    private static func vector(_ rectangle: CGRect) -> CIVector {
        CIVector(x: rectangle.midX, y: rectangle.midY, z: rectangle.width / 2, w: rectangle.height / 2)
    }

    private func blend(_ foreground: CIImage, over background: CIImage, region: CGRect, amount: Double) throws -> CIImage {
        guard let mask = kernels()?.mask.apply(extent: background.extent, arguments: [Self.vector(region), amount]) else {
            throw ScreenRecordingExportError.cannotRender
        }
        return foreground.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask,
        ])
    }

    private func slim(_ image: CIImage, region: CGRect, amount: Double) throws -> CIImage {
        guard let warped = kernels()?.warp.apply(extent: image.extent, roiCallback: { _, rectangle in
            rectangle.insetBy(dx: -region.width * amount, dy: 0)
        }, image: image, arguments: [Self.vector(region), amount]) else {
            throw ScreenRecordingExportError.cannotRender
        }
        return warped
    }
}
