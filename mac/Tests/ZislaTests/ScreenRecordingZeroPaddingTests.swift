import CoreImage
import CoreVideo
import Testing
import ZislaCore

@testable import Zisla

@Suite @MainActor
struct ScreenRecordingZeroPaddingTests {
    @Test(arguments: [CGSize(width: 161, height: 90), CGSize(width: 90, height: 161),
                      CGSize(width: 163, height: 91), CGSize(width: 91, height: 163)])
    func zeroPaddingCoversOriginalCanvasAfterEvenPixelRounding(_ sourceSize: CGSize) throws {
        for ratio in [nil, RecordingCanvasAspectRatio.original] {
            var project = project(size: sourceSize)
            project.edits.canvasAspectRatio = ratio
            let size = try RecordingExportRenderer.outputSize(source: sourceSize, edits: project.edits, resolution: .source)
            #expect(Int(size.width).isMultiple(of: 2) && Int(size.height).isMultiple(of: 2))
            let renderer = try RecordingExportRenderer(project: project, size: size)
            #expect(renderer.screenRect == renderer.canvas)
            let image = try renderer.image(screen: solid(in: CGRect(origin: .zero, size: sourceSize)),
                                           camera: nil, sourceTime: 0)
            try expectGreenCanvas(image)
        }
    }

    @Test(arguments: [CGSize(width: 1_919, height: 1_081), CGSize(width: 1_081, height: 1_919)])
    func zeroPaddingCoversDownscaledPreviewAndPlaybackFrames(_ sourceSize: CGSize) throws {
        let project = project(size: sourceSize)
        let original = try RecordingExportRenderer.outputSize(source: sourceSize, edits: project.edits, resolution: .source)
        for maximumSize in [CGSize(width: 631, height: 359), CGSize(width: 1_280, height: 1_280)] {
            let scale = min(1, min(maximumSize.width / original.width, maximumSize.height / original.height))
            let size = CGSize(width: max(2, (original.width * scale / 2).rounded(.down) * 2),
                              height: max(2, (original.height * scale / 2).rounded(.down) * 2))
            let renderer = try RecordingExportRenderer(project: project, size: size)
            let image = try renderer.image(screen: solid(in: CGRect(origin: .zero, size: sourceSize)),
                                           camera: nil, sourceTime: 0)
            try expectGreenCanvas(image)
        }
    }

    @Test
    func croppedFractionalAndTranslatedSourceExtentsCoverTheCanvas() throws {
        let sourceSize = CGSize(width: 163, height: 91)
        var project = project(size: sourceSize)
        project.edits.crop = .init(x: 0.13, y: 0.17, width: 0.71, height: 0.67)
        let size = try RecordingExportRenderer.outputSize(source: sourceSize, edits: project.edits, resolution: .source)
        let renderer = try RecordingExportRenderer(project: project, size: size)
        for origin in [CGPoint.zero, CGPoint(x: -37.25, y: 19.75)] {
            let screen = solid(in: CGRect(origin: origin, size: sourceSize))
            let before = screen.extent
            let image = try renderer.image(screen: screen, camera: nil, sourceTime: 0)
            try expectGreenCanvas(image)
            #expect(screen.extent == before, "Rendering must not change the source image extent")
        }
    }

    @Test
    func fractionalCropUsesOnlyTheChosenSourceRegion() throws {
        let sourceSize = CGSize(width: 163, height: 91)
        var project = project(size: sourceSize)
        let crop = RecordingRect(x: 0.13, y: 0.17, width: 0.71, height: 0.67)
        project.edits.crop = crop
        let size = try RecordingExportRenderer.outputSize(source: sourceSize, edits: project.edits, resolution: .source)
        let renderer = try RecordingExportRenderer(project: project, size: size)
        let image = try renderer.image(screen: contrastingSource(size: sourceSize, crop: crop),
                                       camera: nil, sourceTime: 0)
        try expectGreenCanvas(image)
    }

    @Test(arguments: [RecordingCanvasAspectRatio.original, .square])
    func croppedSourceNeverLeaksIntoLetterboxing(_ ratio: RecordingCanvasAspectRatio) throws {
        let sourceSize = CGSize(width: 163, height: 91)
        var project = project(size: sourceSize)
        let crop = RecordingRect(x: 0.13, y: 0.17, width: 0.71, height: 0.67)
        project.edits.crop = crop
        project.edits.canvasAspectRatio = ratio
        project.edits.padding = 0.2
        project.edits.backgroundColor = .init(red: 1, green: 0, blue: 0)
        let size = try RecordingExportRenderer.outputSize(source: sourceSize, edits: project.edits, resolution: .source)
        let renderer = try RecordingExportRenderer(project: project, size: size)
        let image = try renderer.image(screen: contrastingSource(size: sourceSize, crop: crop),
                                       camera: nil, sourceTime: 0)
        let pixels = try bytes(image)
        let leakedPixels = stride(from: 2, to: pixels.count, by: 4).filter { pixels[$0] > 2 }.count
        #expect(leakedPixels == 0, "Found \(leakedPixels) blue pixels from outside the chosen source crop in the letterbox")
        #expect(pixels[0] > 252 && pixels[1] < 3 && pixels[2] < 3,
                "Letterboxing must preserve the selected red background")
        let center = (image.height / 2 * image.width + image.width / 2) * 4
        #expect(pixels[center] < 3 && pixels[center + 1] > 252 && pixels[center + 2] < 3,
                "The chosen source crop must remain visible in the center")
    }

    @Test(arguments: [RecordingCanvasAspectRatio.square, .portrait, .standard, .landscape])
    func explicitCanvasRatiosPreserveLetterboxingAndWholeSource(_ ratio: RecordingCanvasAspectRatio) throws {
        let sourceSize = ratio == .landscape ? CGSize(width: 91, height: 163) : CGSize(width: 163, height: 91)
        var project = project(size: sourceSize)
        project.edits.canvasAspectRatio = ratio
        project.edits.backgroundColor = .init(red: 1, green: 0, blue: 1)
        let size = try RecordingExportRenderer.outputSize(source: sourceSize, edits: project.edits, resolution: .source)
        let renderer = try RecordingExportRenderer(project: project, size: size)
        let image = try renderer.image(screen: solid(in: CGRect(origin: .zero, size: sourceSize)),
                                       camera: nil, sourceTime: 0)
        let bytes = try bytes(image)
        let center = (image.height / 2 * image.width + image.width / 2) * 4
        #expect(bytes[center] < 3 && bytes[center + 1] > 252 && bytes[center + 2] < 3)
        #expect(abs(renderer.screenRect.width / renderer.screenRect.height - sourceSize.width / sourceSize.height) < 0.000_001)
        let outside = renderer.screenRect.minY > renderer.screenRect.minX
            ? (x: image.width / 2, y: 0) : (x: 0, y: image.height / 2)
        let offset = (outside.y * image.width + outside.x) * 4
        #expect(bytes[offset] > 100 && bytes[offset + 2] > 100,
                "An explicit canvas ratio must retain the chosen background outside the source frame")
    }

    @Test
    func nonzeroPaddingPreservesTheWholeSourceWithinItsBackground() throws {
        let sourceSize = CGSize(width: 163, height: 91)
        var project = project(size: sourceSize)
        project.edits.padding = 0.2
        project.edits.backgroundColor = .init(red: 1, green: 0, blue: 1)
        let size = try RecordingExportRenderer.outputSize(source: sourceSize, edits: project.edits, resolution: .source)
        let renderer = try RecordingExportRenderer(project: project, size: size)
        let lower = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: sourceSize.width, height: 8))
        let upper = CIImage(color: CIColor(red: 0, green: 0, blue: 1))
            .cropped(to: CGRect(x: 0, y: sourceSize.height - 8, width: sourceSize.width, height: 8))
        let screen = lower.composited(over: upper)
            .composited(over: solid(in: CGRect(origin: .zero, size: sourceSize)))
        let image = try renderer.image(screen: screen, camera: nil, sourceTime: 0)
        let pixels = try bytes(image)
        let rows = [Int(ceil(renderer.screenRect.minY)) + 2, Int(floor(renderer.screenRect.maxY)) - 3]
        let colors = rows.map { row in
            let offset = (row * image.width + image.width / 2) * 4
            return (red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2])
        }
        #expect(colors.contains { $0.red > 252 && $0.green < 3 && $0.blue < 3 }
                && colors.contains { $0.blue > 252 && $0.green < 3 && $0.red < 3 },
                "Nonzero padding must preserve both colored source edges rather than crop them to fill the inset")
        #expect(pixels[0] > 252 && pixels[2] > 252,
                "Nonzero padding must retain the selected background")
    }

    @Test
    func pixelBufferOutputMatchesStillPreviewAtZeroPadding() throws {
        let sourceSize = CGSize(width: 161, height: 90)
        let project = project(size: sourceSize)
        let size = try RecordingExportRenderer.outputSize(source: sourceSize, edits: project.edits, resolution: .source)
        let renderer = try RecordingExportRenderer(project: project, size: size)
        let screen = solid(in: CGRect(origin: CGPoint(x: -12, y: 7), size: sourceSize))
        let still = try renderer.image(screen: screen, camera: nil, sourceTime: 0)
        var output: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA,
                                   [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
                                   &output) == kCVReturnSuccess)
        let buffer = try #require(output)
        let rendered = try renderer.render(screen: screen, camera: nil, sourceTime: 0)
        renderer.context.render(rendered, to: buffer, bounds: renderer.canvas,
                                colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let video = try #require(renderer.context.createCGImage(CIImage(cvPixelBuffer: buffer), from: renderer.canvas,
                                                              format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
        #expect(try bytes(still) == bytes(video), "Still preview and video pixel-buffer output must use the same canvas geometry")
        try expectGreenCanvas(video)
    }

    private func project(size: CGSize) -> ScreenRecordingProject {
        var project = ScreenRecordingProject(name: "Zero Padding", videoFile: "screen.mp4", duration: 1,
                                              width: Int(size.width), height: Int(size.height))
        project.edits.padding = 0
        project.edits.cornerRadius = 0
        project.edits.shadow = 0
        project.edits.showCursor = false
        project.edits.clickEffects = false
        project.edits.showCaptions = false
        return project
    }

    private func solid(in rect: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: rect)
    }

    private func contrastingSource(size: CGSize, crop: RecordingRect) throws -> CIImage {
        let viewport = CGRect(x: crop.x * size.width, y: (1 - crop.y - crop.height) * size.height,
                              width: crop.width * size.width, height: crop.height * size.height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                            bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
                                            space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 0, 1, 1])!)
        context.fill(CGRect(origin: .zero, size: size))
        // Keep contrasting pixels outside the fractional boundary's sampling footprint.
        context.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 1, 0, 1])!)
        context.fill(viewport.insetBy(dx: -2, dy: -2).integral)
        return CIImage(cgImage: try #require(context.makeImage()))
    }

    private func expectGreenCanvas(_ image: CGImage) throws {
        let bytes = try bytes(image)
        let mixedPixels = stride(from: 0, to: bytes.count, by: 4).filter {
            bytes[$0] > 2 || bytes[$0 + 1] < 253 || bytes[$0 + 2] > 2 || bytes[$0 + 3] < 253
        }.count
        #expect(mixedPixels == 0,
                "Zero padding must cover every output pixel; found \(mixedPixels) background/transparent pixels in \(image.width)x\(image.height)")
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { pointer in
            let context = try #require(CGContext(data: pointer.baseAddress, width: image.width, height: image.height,
                                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }
}
