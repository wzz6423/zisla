import AppKit
import CoreImage
import ImageIO
import ScreenCaptureKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenshotHDRTests {
    @Test
    func nativePreviewPreservesTheDisplayReferredFrameWithoutAnotherToneCurve() throws {
        let source = try Self.hdrGradient(headroom: 8)
        let image = NSImage(cgImage: source, size: CGSize(width: 8, height: 8))
        let view = ScreenshotBackingImageView(frame: CGRect(x: 0, y: 0, width: 32, height: 24))
        view.update(image: image, preservesHDR: true, opacity: 1)
        view.layoutSubtreeIfNeeded()
        let layerContents = try #require(view.hdrLayer.contents)
        let contents = layerContents as! CGImage
        #expect(view.image == nil && !view.hdrLayer.isHidden)
        #expect(view.hdrLayer.frame == view.bounds && view.intrinsicContentSize == image.size)
        #expect(try Self.pixelValues(contents) == Self.pixelValues(source),
            "A local-display capture's gray levels must reach the native layer unchanged")
        if #available(macOS 15.0, *) {
            #expect(view.hdrLayer.toneMapMode == .never,
                "Local-display HDR captures must not receive a second content-dependent tone curve")
        }
        if #available(macOS 26.0, *) {
            #expect(view.hdrLayer.preferredDynamicRange == .high)
        } else {
            #expect(view.hdrLayer.wantsExtendedDynamicRangeContent)
        }
        view.frame.size = CGSize(width: 80, height: 40)
        view.layoutSubtreeIfNeeded()
        #expect(view.hdrLayer.frame == view.bounds)
        #expect(try Self.pixelValues(contents) == Self.pixelValues(source))
    }

    @Test
    func nativePreviewHDRToggleReleasesThePreviousLayerAndKeepsOpacityOnTheImage() throws {
        let source = try Self.hdrImage()
        let image = NSImage(cgImage: source, size: CGSize(width: 32, height: 24))
        let standard = NSImage(cgImage: try #require(ScreenshotImageRendering.sdrImage(from: source)), size: image.size)
        let view = ScreenshotBackingImageView(frame: CGRect(origin: .zero, size: image.size))
        view.update(image: image, preservesHDR: true, opacity: 0.6)
        #expect(view.alphaValue == 1 && abs(view.hdrLayer.opacity - 0.6) < 0.001)
        for (next, enabled) in [(image, false), (standard, true)] {
            view.update(image: next, preservesHDR: enabled, opacity: 0.8)
            #expect(view.image === next && view.hdrLayer.contents == nil && view.hdrLayer.isHidden)
            #expect(view.alphaValue == 0.8)
            if #available(macOS 26.0, *) { #expect(view.hdrLayer.preferredDynamicRange == .standard) }
        }
        view.update(image: image, preservesHDR: true, opacity: 1)
        #expect(!view.hdrLayer.isHidden && view.hdrLayer.contents != nil && view.alphaValue == 1)
        view.update(image: NSImage(size: .zero), preservesHDR: true, opacity: 1)
        #expect(view.hdrLayer.contents == nil && view.hdrLayer.isHidden)
    }

    @Test
    func detachedFramesRetainHDRHighlightsAndContentHeadroom() throws {
        let source = try Self.hdrImage()
        let detached = try #require(ScreenshotCaptureService.detachedImage(from: source))

        #expect(detached !== source)
        #expect(detached.bitsPerComponent == 16, "Detaching a capture must not reduce HDR pixels to eight bits")
        #expect(detached.bitmapInfo.contains(.floatComponents))
        #expect(try Self.pixel(detached, x: 8, y: 8)[0] == 4, "HDR highlights must remain above SDR reference white")
        if #available(macOS 15.0, *) {
            #expect(detached.contentHeadroom == source.contentHeadroom)
        }
    }

    @Test
    func unknownHeadroomGetsMeasuredWithoutChangingReferenceWhiteOrHighlights() throws {
        guard #available(macOS 26.0, *) else { return }
        let source = try Self.hdrGradient(headroom: 0)
        let detached = try #require(ScreenshotCaptureService.detachedImage(from: source))
        let reference = try Self.pixelValues(source)
        let copied = try Self.pixelValues(detached)

        #expect(detached.contentHeadroom > 3.99 && detached.contentHeadroom <= 4.01)
        #expect(detached.contentAverageLightLevel > 0,
            "Floating screenshot previews need average light level metadata for constrained HDR presentation")
        for (expected, actual) in zip(reference, copied) {
            #expect(abs(actual - expected) < 0.002,
                "Measuring HDR statistics must not change reference white or amplify highlights")
        }
        let preview = try Self.previewPixels(detached, targetHeadroom: 2)
        #expect(preview.allSatisfy { $0 <= 2.002 }, "HDR previews must fit the display's current headroom; got \(preview)")
        let visible = preview.map { min($0, 2) }
        #expect(visible[5] < visible[6] && visible[6] < visible[7],
            "Distinct HDR highlights must roll off instead of clipping to the same display white; got \(visible)")
    }

    @Test
    func knownHeadroomIsPreservedWhileAverageBrightnessFollowsEditedPixels() throws {
        guard #available(macOS 26.0, *) else { return }
        let source = try Self.hdrGradient(headroom: 8)
        let detached = try #require(ScreenshotCaptureService.detachedImage(from: source))
        #expect(detached.contentHeadroom == 8, "A capture's known mastering headroom must not become its maximum channel")
        #expect(detached.contentAverageLightLevel > 0)
        let cropped = try #require(detached.cropping(to: CGRect(x: 0, y: 0, width: 4, height: 8)))
        let edited = try #require(ScreenshotImageRendering.render(CIImage(cgImage: cropped), matching: detached,
            context: Self.context))
        #expect(edited.contentHeadroom == detached.contentHeadroom)
        #expect(edited.contentAverageLightLevel > 0
            && edited.contentAverageLightLevel < detached.contentAverageLightLevel,
            "Cropped or obscured previews must use their own average brightness rather than the full capture's statistics")
        #expect(abs(try Self.pixel(edited, x: 3, y: 4)[0] - 1) < 0.002)
        let selection = try #require(ScreenshotCaptureService.image(from: detached,
            cropInScreenPoints: CGRect(x: 0, y: 0, width: 4, height: 8), screenSize: CGSize(width: 8, height: 8)))
        let selected = try #require(selection.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(selected.contentHeadroom == detached.contentHeadroom)
        #expect(abs(selected.contentAverageLightLevel - edited.contentAverageLightLevel) < 0.01,
            "The initial selection preview must measure the cropped pixels before any annotation is applied")
    }

    @Test(arguments: [Float(0), Float(1)], [Float(0), Float(4)])
    func darkAndTransparentHDRFramesRemainValid(alpha: Float, headroom: Float) throws {
        guard #available(macOS 26.0, *) else { return }
        let source = try Self.hdrGradient(headroom: headroom, levels: [Float](repeating: 0, count: 8), alpha: alpha)
        let detached = try #require(ScreenshotCaptureService.detachedImage(from: source))
        #expect(detached.contentAverageLightLevel == 0)
        #expect(detached.contentHeadroom == headroom)
        let sample = try Self.pixel(detached, x: 4, y: 4)
        #expect(sample[0] == 0 && sample[1] == 0 && sample[2] == 0 && sample[3] == alpha,
            "HDR statistics must not drop black or fully transparent captures")
    }

    @Test(arguments: [false, true])
    func captureConfigurationsRequestTheSelectedRangeWithoutChangingGeometry(includeHDR: Bool) {
        let stream = ScreenshotCaptureService.streamConfiguration(width: 320, height: 240, includeHDR: includeHDR)
        #expect(stream.width == 320 && stream.height == 240)
        #expect(!stream.showsCursor)
        if #available(macOS 15.0, *) {
            #expect(stream.captureDynamicRange == (includeHDR ? .hdrLocalDisplay : .SDR))
        }
        if #available(macOS 26.0, *) {
            let screenshot = ScreenshotCaptureService.screenshotConfiguration(width: 320, height: 240, includeHDR: includeHDR)
            #expect(screenshot.width == 320 && screenshot.height == 240)
            #expect(screenshot.dynamicRange == (includeHDR ? .bothSDRAndHDR : .sdr))
            #expect(screenshot.displayIntent == .local && !screenshot.showsCursor)
        }
    }

    @Test
    func switchingHDRPreservesTheFrozenCaptureAnnotationsAndUndoHistory() throws {
        let hdr = try Self.hdrImage()
        let sdr = try #require(ScreenshotImageRendering.sdrImage(from: hdr))
        let size = CGSize(width: hdr.width, height: hdr.height)
        let source = NSImage(cgImage: hdr, size: size)
        let standard = NSImage(cgImage: sdr, size: size)
        let model = ScreenshotEditorModel(image: source, sdrImage: standard)
        let annotation = ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 2, y: 2, width: 10, height: 8))
        model.add(annotation)
        #expect(model.canPreserveHDR && !model.preservesHDR)

        for enabled in [true, false, true, false] {
            model.preservesHDR = enabled
            let image = try #require(model.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
            let preview = try #require(model.mosaicPreviewImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
            #expect(try Self.pixel(preview, x: 24, y: 16)[0] > (enabled ? 3.9 : 0.9))
            if !enabled { #expect(try Self.pixel(preview, x: 24, y: 16)[0] <= 1.001) }
            #expect(try Self.pixel(image, x: 24, y: 16)[0] > (enabled ? 3.9 : 0.9))
            if !enabled { #expect(try Self.pixel(image, x: 24, y: 16)[0] <= 1.001) }
            #expect(model.image === source && model.sdrImage === standard)
            #expect(model.annotations == [annotation] && model.canUndo && !model.canRedo)
        }
        model.undo()
        #expect(model.annotations.isEmpty && !model.canUndo && model.canRedo)
        #expect(model.sdrImage === standard)
        model.redo()
        #expect(model.annotations == [annotation] && model.sdrImage === standard)
    }

    @Test(arguments: ["bitmap", "coreImage"], [false, true])
    func failedRenderingKeepsTheSelectedDynamicRange(stage: String, preservesHDR: Bool) throws {
        let hdr = try Self.hdrImage()
        let image = NSImage(cgImage: hdr, size: CGSize(width: hdr.width, height: hdr.height))
        let model = ScreenshotEditorModel(image: image)
        model.preservesHDR = preservesHDR
        model.add(ScreenshotAnnotation(kind: .mosaic, rect: CGRect(x: 4, y: 4, width: 12, height: 8)))
        var dependencies = ScreenshotEditorModel.RenderingDependencies()
        if stage == "bitmap" { dependencies.makeBitmap = { _, _, _ in nil } }
        else { dependencies.makeCoreImage = { _, _ in nil } }
        model.renderingDependencies = dependencies
        let rendered = model.renderedImage()
        let result = try #require(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(ScreenshotImageRendering.isHDR(result) == preservesHDR)
        if stage == "coreImage" {
            let preview = try #require(model.imageApplyingMosaics().cgImage(forProposedRect: nil, context: nil, hints: nil))
            #expect(ScreenshotImageRendering.isHDR(preview) == preservesHDR)
        }
        #expect(throws: (any Error).self) { try model.renderedImage(requireCompleteRendering: true) }
        #expect(model.pngData(requireCompleteRendering: true) == nil)
        #expect(model.image === image && model.annotations.count == 1)
    }

    @Test(arguments: [false, true], [Float(2), Float(4), Float(16)])
    func exportedPNGRoundTripsHighlightsAndTransparency(preservesHDR: Bool, highlight: Float) throws {
        let hdr = try Self.hdrImage(highlight: highlight)
        let source = NSImage(cgImage: hdr, size: CGSize(width: 16, height: 12))
        let model = ScreenshotEditorModel(image: source)
        model.preservesHDR = preservesHDR
        model.setCornerRadius(4)
        let data = try #require(model.pngData())
        let imageSource = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(imageSource) == UTType.png.identifier as CFString)
        let decoded = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, [
            kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR,
            kCGImageSourceShouldAllowFloat: true,
        ] as CFDictionary))
        #expect(decoded.width == hdr.width && decoded.height == hdr.height)
        #expect(try Self.pixel(decoded, x: 0, y: 0)[3] == 0, "Rounded corners must stay transparent in HDR PNGs")
        let center = try Self.pixel(decoded, x: 16, y: 12)
        #expect(center[3] == 1)
        if preservesHDR {
            #expect(abs(center[0] - Float(highlight)) < 0.01 && abs(center[1] - Float(highlight / 2)) < 0.01,
                "Encoding and decoding must preserve light levels above SDR white")
            #expect(decoded.bitsPerComponent == 16)
            #expect(decoded.colorSpace.map(CGColorSpaceUsesITUR_2100TF) == true)
        } else {
            #expect(center[0] <= 1.001 && decoded.bitsPerComponent == 8)
        }
    }

    @Test
    func retinaAnnotationsAndDraftsAreRenderedAtTheirOriginalCoordinates() throws {
        let hdr = try Self.hdrImage(width: 80, height: 60)
        let model = ScreenshotEditorModel(image: NSImage(cgImage: hdr, size: CGSize(width: 40, height: 30)))
        model.preservesHDR = true
        let annotation = ScreenshotAnnotation(kind: .brush, points: [CGPoint(x: 12, y: 10), CGPoint(x: 24, y: 10)],
            color: ScreenshotRGBA(red: 0, green: 0, blue: 0), lineWidth: 4)
        model.updatePendingAnnotationDraft(annotation)
        let image = try #require(model.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        let ink = try Self.pixel(image, x: 36, y: 40)
        #expect(ink[0] < 0.01 && ink[1] < 0.01 && ink[2] < 0.01 && ink[3] == 1,
            "Point-space annotations must scale and keep their top-left origin on Retina HDR images; got \(ink)")
        #expect(try Self.pixel(image, x: 36, y: 10)[0] == 4)
        #expect(model.pendingAnnotationDraft == nil && model.annotations == [annotation])
    }

    @Test(arguments: [ScreenshotObscureEffect.blur, .pixelate])
    func obscureEffectsPreserveHDRInsideAndOutsideTheEditedRegion(effect: ScreenshotObscureEffect) throws {
        let model = ScreenshotEditorModel(image: NSImage(cgImage: try Self.hdrImage(width: 80, height: 60),
            size: CGSize(width: 80, height: 60)))
        model.preservesHDR = true
        model.add(ScreenshotAnnotation(kind: .mosaic, rect: CGRect(x: 12, y: 12, width: 30, height: 30),
            obscureEffect: effect, obscureStrength: 2))
        let image = try #require(model.imageApplyingMosaics().cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(try Self.pixel(image, x: 24, y: 30)[0] > 3.9)
        #expect(try Self.pixel(image, x: 65, y: 30)[0] > 3.9)
        #expect(image.bitmapInfo.contains(.floatComponents))
    }

    @Test
    func maskExtractionRetainsHDRAndRejectsMismatchedMasks() throws {
        let hdr = try Self.hdrImage()
        let mask = try #require(try ScreenshotImageExtraction.lassoMask(
            regions: [[CGPoint(x: 8, y: 4), CGPoint(x: 24, y: 4), CGPoint(x: 24, y: 20), CGPoint(x: 8, y: 20)]],
            imageSize: CGSize(width: 32, height: 24), pixelWidth: 32, pixelHeight: 24))
        let extracted = try ScreenshotImageExtraction.applying(mask: mask, to: hdr)
        #expect(try Self.pixel(extracted, x: 16, y: 12)[0] == 4)
        #expect(try Self.pixel(extracted, x: 0, y: 0)[3] == 0)
        #expect(throws: ScreenshotExtractionError.self) {
            try ScreenshotImageExtraction.applying(mask: mask, to: Self.hdrImage(width: 16, height: 12))
        }
        #expect(try Self.pixel(hdr, x: 0, y: 0)[0] == 4, "Failed extraction must not mutate the source")
    }

    @Test
    func croppingKeepsHDRAndRejectsEmptySelections() throws {
        let hdr = try Self.hdrImage()
        let crop = try #require(ScreenshotCaptureService.image(from: hdr,
            cropInScreenPoints: CGRect(x: 2, y: 3, width: 8, height: 6), screenSize: CGSize(width: 16, height: 12)))
        let image = try #require(crop.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(crop.size == CGSize(width: 8, height: 6) && image.width == 16 && image.height == 12)
        #expect(try Self.pixel(image, x: 8, y: 6)[0] == 4)
        for rect in [CGRect.zero, CGRect(x: 100, y: 100, width: 8, height: 6)] {
            #expect(ScreenshotCaptureService.image(from: hdr, cropInScreenPoints: rect,
                screenSize: CGSize(width: 16, height: 12)) == nil)
        }
    }

    @Test
    func resizingSelectionPreservesBothRangesThroughoutUndoAndRedo() throws {
        let hdr = try Self.hdrImage()
        let standard = try #require(ScreenshotImageRendering.sdrImage(from: hdr))
        let size = CGSize(width: 32, height: 24)
        let model = ScreenshotEditorModel(image: NSImage(cgImage: hdr, size: size), sdrImage: NSImage(cgImage: standard, size: size))
        model.add(ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 4, y: 4, width: 8, height: 8)))
        model.undo()
        let rect = CGRect(x: 2, y: 2, width: 16, height: 12)
        let next = try #require(ScreenshotCaptureService.image(from: hdr, cropInScreenPoints: rect, screenSize: size))
        let nextSDR = try #require(ScreenshotCaptureService.image(from: standard, cropInScreenPoints: rect, screenSize: size))
        model.replaceCapture(with: next, translatingAnnotationsBy: CGSize(width: -2, height: -2), sdrImage: nextSDR)
        model.redo()
        #expect(model.image.size == next.size && model.sdrImage === nextSDR)
        #expect(model.annotations.first?.rect.origin == CGPoint(x: 2, y: 2))
        model.undo()
        #expect(model.sdrImage === nextSDR && model.annotations.isEmpty)
    }

    @Test
    func longCaptureStitchingRetainsHDRRegardlessOfExportToggle() throws {
        let first = try Self.hdrImage(width: 12, height: 10)
        let second = try Self.hdrImage(width: 12, height: 8)
        let standard = try #require(ScreenshotImageRendering.sdrImage(from: first))
        let model = ScreenshotEditorModel(image: NSImage(cgImage: first, size: CGSize(width: 12, height: 10)),
            sdrImage: NSImage(cgImage: standard, size: CGSize(width: 12, height: 10)))
        #expect(model.append(image: NSImage(cgImage: second, size: CGSize(width: 12, height: 8))))
        #expect(model.sdrImage == nil && model.displayImage.size == CGSize(width: 12, height: 18),
            "Appending must replace the previous SDR image instead of exporting the first frame alone")
        model.preservesHDR = true
        let combined = try #require(model.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(combined.width == 12 && combined.height == 18)
        #expect(try Self.pixel(combined, x: 6, y: 4)[0] == 4)
        #expect(try Self.pixel(combined, x: 6, y: 14)[0] == 4)
        if #available(macOS 15.0, *) { #expect(combined.contentHeadroom == 4) }
        model.undo()
        #expect(model.image.size == CGSize(width: 12, height: 10) && model.canPreserveHDR)
    }

    @Test(arguments: [false, true], [false, true])
    func longCaptureRequestsTheFrozenRangeRegardlessOfPreviewToggle(hasHDR: Bool, preservesHDR: Bool) async throws {
        let suite = "zisla-hdr-long-capture-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = FeatureSettingsStore(defaults: defaults)
        defer { settings.flushPendingChanges(); defaults.removePersistentDomain(forName: suite) }
        let screen = try #require(NSScreen.screens.first)
        let hdr = try Self.hdrImage(width: 80, height: 60)
        let sdr = try #require(ScreenshotImageRendering.sdrImage(from: hdr))
        let screenSize = screen.frame.size
        let screenImage = NSImage(cgImage: sdr, size: screenSize)
        let rect = CGRect(x: 0, y: 0, width: screenSize.width / 2, height: screenSize.height / 2)
        let initial = try #require(ScreenshotCaptureService.image(from: sdr, cropInScreenPoints: rect, screenSize: screenSize))
        var requests: [Bool] = []
        let controller = ScreenshotEditorWindowController(image: initial,
            screenImage: screenImage, screenCGImage: sdr, hdrScreenCGImage: hasHDR ? hdr : nil,
            screen: screen, captureRect: rect, capturedApplication: nil, settingsStore: settings,
            onStash: { _, _ in }, writeImageToPasteboard: { _ in false }, presentSavePanel: { _, _ in },
            captureScreen: { _, includeHDR in
                requests.append(includeHDR)
                return (screenImage, sdr, hasHDR ? hdr : nil)
            }, scheduleLongCaptureWork: { _, _ in }, onClose: {})
        defer { controller.close() }
        controller.window?.alphaValue = 0
        let host = try #require(controller.window?.contentView as? NSHostingView<AppLanguageEnvironment<ScreenshotEditorView>>)
        let model = host.rootView.content.model
        let frozen = model.image
        model.preservesHDR = preservesHDR
        model.beginLongCapturePreview()
        let task = try #require(controller.captureLongCaptureScreen(on: screen, sessionID: 0))
        await task.value
        #expect(requests == [hasHDR], "HDR capture follows the frozen frame's capability, including while its preview is disabled")
        #expect(model.lastLongCaptureFrameResult == .unchanged,
            "The injected HDR frame must be compared with the frozen HDR pixels instead of its SDR representation")
        #expect(model.image === frozen && model.canPreserveHDR == hasHDR && model.preservesHDR == preservesHDR)
        #expect(!model.canUndo && model.isLongCapturePreviewing)
    }

    @Test
    func PQImagesRemainHDRWhenReopenedAndUnknownHeadroomIsMeasuredWhenSupported() throws {
        let hdr = try Self.hdrImage()
        let pq = try #require(Self.context.createCGImage(CIImage(cgImage: hdr),
            from: CGRect(x: 0, y: 0, width: hdr.width, height: hdr.height), format: .RGBA16,
            colorSpace: CGColorSpace(name: CGColorSpace.itur_2100_PQ)!))
        let detached = try #require(ScreenshotCaptureService.detachedImage(from: pq))
        #expect(ScreenshotImageRendering.isHDR(pq) && ScreenshotImageRendering.isHDR(detached))
        #expect(try Self.pixel(detached, x: 16, y: 12)[0] > 3.99)
        if #available(macOS 15.0, *) {
            let unknown = try #require(CGImageCreateCopyWithContentHeadroom(0, hdr))
            let copy = try #require(ScreenshotCaptureService.detachedImage(from: unknown))
            let highlight = try Self.pixel(copy, x: 16, y: 12)[0]
            #expect(highlight == 4)
            if #available(macOS 26.0, *) {
                #expect(copy.contentHeadroom > 1 && copy.contentAverageLightLevel > 0)
            } else {
                #expect(copy.contentHeadroom == 0)
            }
        }
    }

    @Test
    func extractingAndUndoingKeepsBothDynamicRangesWithoutCommittingTheToggle() async throws {
        let hdr = try Self.hdrImage()
        let source = NSImage(cgImage: hdr, size: CGSize(width: 32, height: 24))
        let standard = NSImage(cgImage: try #require(ScreenshotImageRendering.sdrImage(from: hdr)), size: source.size)
        let model = ScreenshotEditorModel(image: source, sdrImage: standard)
        let extraction = model.selectExtractionMode(.foreground, extractImage: { image, _ in image })
        let task = try #require(extraction)
        await task.value
        #expect(model.hasExtractedImage && model.canPreserveHDR && !model.preservesHDR && model.sdrImage == nil)
        model.preservesHDR = true
        #expect(try Self.pixel(try #require(model.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil)),
            x: 16, y: 12)[0] == 4)
        model.undo()
        #expect(model.image === source && model.sdrImage === standard && model.preservesHDR)
        model.redo()
        #expect(model.hasExtractedImage && model.canPreserveHDR && model.sdrImage == nil)
        model.selectExtractionMode(.foreground)
        #expect(model.image === source && model.sdrImage === standard)
    }

    @Test
    func modalCompositingDoesNotFlattenTheHDRBackground() throws {
        let hdr = try Self.hdrImage()
        let modal = try #require(ScreenshotImageRendering.sdrImage(from: Self.hdrImage(width: 4, height: 4)))
        let composited = try #require(ScreenshotModalWindowSnapshot.composite(modal,
            in: CGRect(x: 4, y: 4, width: 4, height: 4), over: hdr, screenSize: CGSize(width: 32, height: 24)))
        #expect(try Self.pixel(composited, x: 20, y: 12)[0] == 4)
        #expect(try Self.pixel(composited, x: 6, y: 18)[0] <= 1.001)
        #expect(composited.bitmapInfo.contains(.floatComponents))
        if #available(macOS 15.0, *) { #expect(composited.contentHeadroom == 4) }
    }

    @Test(arguments: AppLanguage.allCases)
    func HDRControlHasCompleteTranslationsInEveryLanguage(language: AppLanguage) throws {
        let resource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: resource), format: nil) as? [String: String])
        for key in ["保留 HDR", "已开启", "已关闭"] {
            let value = try #require(table[key], "Missing \(language.rawValue) translation for \(key)")
            #expect(!value.isEmpty && AppLocalization.string(key, language: language) == value)
            if language != .simplifiedChinese && language != .traditionalChinese { #expect(value != key) }
        }
    }

    @Test
    func SDRAndUnresolvedImagesDoNotOfferHDR() throws {
        let hdr = try Self.hdrImage()
        let sdr = try #require(ScreenshotImageRendering.sdrImage(from: hdr))
        let model = ScreenshotEditorModel(image: NSImage(cgImage: sdr, size: CGSize(width: 32, height: 24)))
        #expect(!model.canPreserveHDR && !model.preservesHDR)
        #expect(!ScreenshotEditorModel(image: NSImage(size: CGSize(width: 0, height: 0))).canPreserveHDR)
        let empty = ScreenshotEditorModel(image: NSImage(size: CGSize(width: 0, height: 0)))
        empty.preservesHDR = true
        #expect(empty.pngData() == nil && !empty.canUndo,
            "An unresolved image must not generate a partial PNG or change editor history")
    }

    @Test
    func HDRFilesAndShelfRoundTripWithoutReencodingAndClipboardKeepsThePNG() throws {
        let model = ScreenshotEditorModel(image: NSImage(cgImage: try Self.hdrImage(), size: CGSize(width: 32, height: 24)))
        model.preservesHDR = true
        let data = try #require(model.pngData())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-hdr-exports-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("hdr.png")
        try ScreenshotImageExport.writePNG(data, to: destination)
        #expect(try Data(contentsOf: destination) == data)
        let source = ScreenshotSourceSnapshot(applicationName: nil, bundleIdentifier: nil, processIdentifier: nil,
            capturedAt: Date(timeIntervalSince1970: 42))
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let item = try store.stashScreenshot(png: data, metadata: ShelfScreenshotMetadata(source: source,
            isLongScreenshot: false, initialCaptureRect: .zero, captureRect: .zero, screenFrame: nil,
            displayIdentifier: nil, pixelWidth: 32, pixelHeight: 24))
        #expect(try store.screenshotData(id: item.id) == data)
        let reloaded = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        #expect(try reloaded.screenshotData(id: item.id) == data)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        #expect(ClipboardHistoryPasteboard.write(.image(data), to: board))
        #expect(board.data(forType: .png) == data)
        #expect(ClipboardHistoryPasteboard.readContent(from: board) == .image(data))
        #expect(throws: (any Error).self) {
            try ScreenshotImageExport.writePNG(data, to: directory.appendingPathComponent("missing/hdr.png"))
        }
        #expect(try Data(contentsOf: destination) == data && store.items.count == 1)
        let preview = try #require(NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(ScreenshotImageRendering.isHDR(preview))
        #expect(try Self.pixel(preview, x: 16, y: 12)[0] > 3.99)
        #expect(throws: (any Error).self) {
            try store.stashScreenshot(png: Data(data.dropLast()), metadata: item.screenshotMetadata!)
        }
        let retainedData = try store.screenshotData(id: item.id)
        #expect(store.items.count == 1 && retainedData == data)
    }

    @Test
    func editorInitializesBothRangesAndResizingUsesTheFrozenHDRFrame() throws {
        let suite = "zisla-hdr-editor-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = FeatureSettingsStore(defaults: defaults)
        defer { settings.flushPendingChanges() }
        let screen = try #require(NSScreen.screens.first)
        let hdr = try Self.hdrImage(width: 80, height: 60)
        let sdr = try #require(ScreenshotImageRendering.sdrImage(from: hdr))
        let screenSize = screen.frame.size
        let rect = CGRect(x: 0, y: 0, width: screenSize.width / 2, height: screenSize.height / 2)
        let image = try #require(ScreenshotCaptureService.image(from: sdr, cropInScreenPoints: rect, screenSize: screenSize))
        let controller = ScreenshotEditorWindowController(image: image,
            screenImage: NSImage(cgImage: sdr, size: screenSize), screenCGImage: sdr, hdrScreenCGImage: hdr,
            screen: screen, captureRect: rect, capturedApplication: nil, settingsStore: settings,
            onStash: { _, _ in }, onClose: {})
        defer { controller.close() }
        let host = try #require(controller.window?.contentView as? NSHostingView<AppLanguageEnvironment<ScreenshotEditorView>>)
        let editor = host.rootView.content
        #expect(editor.model.canPreserveHDR && !editor.model.preservesHDR && editor.model.sdrImage === image)
        let configuration = try #require(editor.overlayConfiguration)
        let nextRect = CGRect(x: 0, y: 0, width: screenSize.width / 4, height: screenSize.height / 4)
        let next = try #require(configuration.cropImage(nextRect))
        let nextSDR = try #require(configuration.cropSDRImage?(nextRect))
        editor.model.replaceCapture(with: next, translatingAnnotationsBy: .zero, sdrImage: nextSDR)
        editor.model.preservesHDR = true
        let output = try #require(editor.model.renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(output.width == 20 && output.height == 15)
        #expect(try Self.pixel(output, x: 10, y: 7)[0] == 4)
        editor.model.beginLongCapturePreview()
        #expect(controller.longCaptureToolbarFrame(on: screen).width == ScreenshotToolbarLayout.viewportWidth(
            availableWidth: screen.visibleFrame.width, controlCount: ScreenshotToolbarLayout.controlCount + 1),
            "The floating long-capture toolbar must reserve a slot for its HDR control")
        editor.model.replaceCapture(with: nextSDR, translatingAnnotationsBy: .zero)
        #expect(controller.longCaptureToolbarFrame(on: screen).width == ScreenshotToolbarLayout.viewportWidth(
            availableWidth: screen.visibleFrame.width, controlCount: ScreenshotToolbarLayout.controlCount),
            "SDR toolbars must not reserve an absent HDR control")
    }

    @Test
    func selectionCarriesTheFrozenHDRFrameAndCancellationDropsPreparedCaptures() async throws {
        let screen = try #require(NSScreen.screens.first)
        let hdr = try Self.hdrImage(width: 320, height: 240)
        let sdr = try #require(ScreenshotImageRendering.sdrImage(from: hdr))
        let screenImage = NSImage(cgImage: sdr, size: screen.frame.size)
        var panels: [ScreenshotSelectionPanel] = []
        var result: ScreenshotCaptureResult?
        let controller = ScreenshotSelectionController(captureScreen: { _ in (screenImage, sdr, hdr) },
            presentPanels: { panels = $0 }, snapTargets: { _ in [] })
        controller.onCaptured = { result = $0 }
        await controller.start(on: screen)
        let host = try #require(panels.first?.contentView as? NSHostingView<ScreenshotSelectionView>)
        host.rootView.onSelection(CGRect(x: 10, y: 10, width: 200, height: 120))
        #expect(result?.hdrScreenCGImage === hdr && result?.screenCGImage === sdr)
        #expect(controller.selectionWindowCount == 0)

        var cancelled: ScreenshotSelectionController!
        var presentations = 0
        cancelled = ScreenshotSelectionController(captureScreen: { _ in (screenImage, sdr, hdr) },
            presentPanels: { _ in presentations += 1 }, snapTargets: { _ in [] })
        cancelled.onSelectionWillPresent = { cancelled.cancel() }
        await cancelled.start(on: screen)
        #expect(presentations == 0 && cancelled.selectionWindowCount == 0,
            "Cancelling during preparation must discard both dynamic ranges")
    }

    @Test
    func toolbarButtonTogglesHDRWithoutChangingTheCaptureOrCreatingWindows() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let suite = "zisla-hdr-toolbar-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = FeatureSettingsStore(defaults: defaults)
        defer { settings.flushPendingChanges() }
        let source = NSImage(cgImage: try Self.hdrImage(), size: CGSize(width: 32, height: 24))
        let model = ScreenshotEditorModel(image: source)
        let editor = ScreenshotEditorView(model: model, selectionState: ScreenshotAnnotationSelectionState(),
            settingsStore: settings, onClose: {}, onCopy: {}, onPinToggle: { _ in }, onLongCapture: {})
        let host = NSHostingView(rootView: editor.hdrButton)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: host.fittingSize),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        func button(in object: NSObject) -> NSObject? {
            if object.responds(to: NSSelectorFromString("accessibilityRole")),
               object.value(forKey: "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue {
                return object
            }
            guard object.responds(to: NSSelectorFromString("accessibilityChildren")) else { return nil }
            return (object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [])
                .lazy.compactMap { button(in: $0) }.first
        }
        let control = try #require(button(in: host))
        #expect(host.fittingSize.width == ScreenshotToolbarLayout.controlWidth)
        #expect(host.fittingSize.height == ScreenshotToolbarLayout.controlHeight)
        #expect(!model.preservesHDR)
        press(control)
        #expect(model.preservesHDR && model.image === source && !model.canUndo)
        press(control)
        #expect(!model.preservesHDR && model.image === source && !model.canUndo)
        #expect(!window.isVisible && !window.isKeyWindow)
    }

    private func press(_ control: NSObject) {
        control.performSelector(onMainThread: NSSelectorFromString("accessibilityPerformPress"), with: nil, waitUntilDone: true)
    }

    private static let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private static let context = CIContext()

    private static func hdrGradient(headroom: Float, levels: [Float] = [0, 0.18, 0.5, 1, 1.5, 2, 3, 4],
                                    alpha: Float = 1) throws -> CGImage {
        let row = levels.flatMap { [$0, $0, $0, alpha] }
        let values = (0..<8).flatMap { _ in row }
        let data = values.withUnsafeBytes { Data($0) }
        let provider = try #require(CGDataProvider(data: data as CFData))
        let image = try #require(CGImage(width: 8, height: 8, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: 8 * 16, space: linearSpace,
            bitmapInfo: [.floatComponents, .byteOrder32Little,
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)],
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        if #available(macOS 15.0, *) {
            return try #require(CGImageCreateCopyWithContentHeadroom(headroom, image))
        }
        return image
    }

    private static func pixelValues(_ image: CGImage) throws -> [Float] {
        try (0..<image.width).map { try pixel(image, x: $0, y: 4)[0] }
    }

    @available(macOS 26.0, *)
    private static func previewPixels(_ image: CGImage, targetHeadroom: Float) throws -> [Float] {
        let source = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        let renderer = ImageRenderer(content: HStack(spacing: 0) {
            Image(nsImage: source).allowedDynamicRange(.constrainedHigh).resizable().interpolation(.none)
                .frame(width: CGFloat(image.width), height: CGFloat(image.height))
            Color.gray.frame(width: 1, height: CGFloat(image.height))
        })
        renderer.colorMode = .extendedLinear
        var output: CGImage?
        renderer.render { size, draw in
            guard let bitmap = ScreenshotImageRendering.bitmapContext(width: Int(size.width), height: Int(size.height),
                matching: image) else { return }
            bitmap.setEDRTargetHeadroom(targetHeadroom)
            draw(bitmap)
            output = bitmap.makeImage()
        }
        return try (0..<image.width).map { try pixel(#require(output), x: $0, y: 4)[0] }
    }

    private static func hdrImage(width: Int = 32, height: Int = 24, highlight: Float = 4) throws -> CGImage {
        // Raw IEEE 754 binary16 samples also work on Intel, where Swift's Float16 is unavailable.
        let samples: [Float: [UInt16]] = [
            2: [0x4000, 0x3c00, 0x3800, 0x3c00],
            4: [0x4400, 0x4000, 0x3800, 0x3c00],
            16: [0x4c00, 0x4800, 0x3800, 0x3c00],
        ]
        let components = try #require(samples[highlight])
        let values = (0..<width * height).flatMap { _ in components }
        let data = values.withUnsafeBytes { Data($0) }
        let provider = try #require(CGDataProvider(data: data as CFData))
        let image = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
            bytesPerRow: width * 8, space: linearSpace,
            bitmapInfo: [.floatComponents, .byteOrder16Little,
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)],
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        if #available(macOS 15.0, *) {
            return try #require(CGImageCreateCopyWithContentHeadroom(Float(highlight), image))
        }
        return image
    }

    private static func pixel(_ image: CGImage, x: Int, y: Int) throws -> [Float] {
        var values = [Float](repeating: 0, count: 4)
        values.withUnsafeMutableBytes { bytes in
            context.render(CIImage(cgImage: image), toBitmap: bytes.baseAddress!, rowBytes: 16,
                bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBAf, colorSpace: linearSpace)
        }
        return values
    }
}
