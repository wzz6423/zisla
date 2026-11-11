import CoreImage
import Foundation
import Vision
import ZislaCore

final class RecordingPortraitProcessor {
    struct Regions {
        var faces: [CGRect] = []
        var bodies: [CGRect] = []
    }

    typealias Detector = (CIImage, Bool, Bool) throws -> Regions
    private let detector: Detector
    private var detection: (size: CGSize, time: Double?, faces: Bool, bodies: Bool, regions: Regions)?

    init(detector: @escaping Detector = RecordingPortraitProcessor.detect) { self.detector = detector }

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
                    output = try Self.blend(softened, over: output, region: rectangle, amount: effects.smoothing)
                }
                if effects.brightening > 0 {
                    let brighter = output.applyingFilter("CIExposureAdjust", parameters: ["inputEV": 0.35])
                    output = try Self.blend(brighter, over: output, region: rectangle, amount: effects.brightening)
                }
            }
        }
        if effects.bodySlimming > 0 {
            for body in regions.bodies {
                output = try Self.slim(output, region: Self.rectangle(body, in: extent), amount: effects.bodySlimming * 0.18)
            }
        }
        if effects.faceSlimming > 0 {
            for face in regions.faces {
                output = try Self.slim(output, region: Self.rectangle(face, in: extent), amount: effects.faceSlimming * 0.22)
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

    private static let mask = CIColorKernel(source: """
        kernel vec4 portraitMask(vec4 region, float amount) {
            vec2 relative = (destCoord() - region.xy) / region.zw;
            float weight = amount * (1.0 - smoothstep(0.7, 1.0, length(relative)));
            return vec4(vec3(weight), 1.0);
        }
        """)
    private static let warp = CIWarpKernel(source: """
        kernel vec2 portraitSlim(vec4 region, float amount) {
            vec2 point = destCoord();
            vec2 relative = (point - region.xy) / region.zw;
            float weight = max(0.0, 1.0 - dot(relative, relative));
            return point + vec2((point.x - region.x) * amount * weight * weight, 0.0);
        }
        """)

    private static func vector(_ rectangle: CGRect) -> CIVector {
        CIVector(x: rectangle.midX, y: rectangle.midY, z: rectangle.width / 2, w: rectangle.height / 2)
    }

    private static func blend(_ foreground: CIImage, over background: CIImage, region: CGRect, amount: Double) throws -> CIImage {
        guard let mask = mask?.apply(extent: background.extent, arguments: [vector(region), amount]) else {
            throw ScreenRecordingExportError.cannotRender
        }
        return foreground.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask,
        ])
    }

    private static func slim(_ image: CIImage, region: CGRect, amount: Double) throws -> CIImage {
        guard let warped = warp?.apply(extent: image.extent, roiCallback: { _, rectangle in
            rectangle.insetBy(dx: -region.width * amount, dy: 0)
        }, image: image, arguments: [vector(region), amount]) else {
            throw ScreenRecordingExportError.cannotRender
        }
        return warped
    }
}
