import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct ScreenshotRoundedCornerTests {
    @Test(arguments: [CGSize(width: 701, height: 410), CGSize(width: 410, height: 701)])
    func radiusIsLimitedByTheShorterImageEdge(size: CGSize) {
        #expect(ScreenshotRoundedCornerGeometry.maximumRadius(for: size) == 205)
        #expect(ScreenshotRoundedCornerGeometry.clampedRadius(23, in: size) == 23)
        #expect(ScreenshotRoundedCornerGeometry.clampedRadius(300, in: size) == 205)
        #expect(ScreenshotRoundedCornerGeometry.clampedRadius(-23, in: size) == 0)
    }

    @Test(arguments: [CGFloat.nan, CGFloat.infinity, -CGFloat.infinity])
    func nonfiniteRadiusHasNoRoundedCoverage(radius: CGFloat) {
        #expect(ScreenshotRoundedCornerGeometry.clampedRadius(radius, in: CGSize(width: 200, height: 120)) == 0)
    }

    @Test(arguments: [
        CGSize.zero,
        CGSize(width: 0, height: 100),
        CGSize(width: 100, height: 0),
        CGSize(width: -10, height: 100),
        CGSize(width: 100, height: -10),
        CGSize(width: CGFloat.nan, height: 100),
        CGSize(width: 100, height: CGFloat.nan),
        CGSize(width: CGFloat.infinity, height: 100),
        CGSize(width: 100, height: CGFloat.infinity),
    ])
    func emptyOrInvalidImageSizeDoesNotProduceARadius(size: CGSize) {
        #expect(ScreenshotRoundedCornerGeometry.maximumRadius(for: size) == 0)
        #expect(ScreenshotRoundedCornerGeometry.clampedRadius(23, in: size) == 0)
    }

    @Test(arguments: [CGFloat(0), 23, 205, 300])
    func radiusControlFollowsTheTangentWithoutCoveringResizeHandleCenters(radius: CGFloat) {
        let selection = CGRect(x: 100, y: 80, width: 410, height: 701)
        let position = ScreenshotRoundedCornerGeometry.handlePosition(
            in: selection, radius: radius, within: CGRect(x: 0, y: 0, width: 800, height: 900)
        )
        #expect(position.x == selection.minX + min(radius, 205))
        #expect(position.y == selection.minY - 18)
        for handle in ScreenshotSelectionHandle.allCases {
            let resize = ScreenshotSelectionGeometry.position(of: handle, in: selection)
            #expect(abs(position.x - resize.x) > 14 || abs(position.y - resize.y) > 14,
                    "The radius control must remain outside the existing resize handles' center hit area")
        }
    }

    @Test(arguments: [
        (CGRect(x: 100, y: 0, width: 200, height: 120), CGRect(x: 0, y: 0, width: 800, height: 600)),
        (CGRect(x: 100, y: 20, width: 200, height: 120), CGRect(x: 0, y: 0, width: 800, height: 600)),
        (CGRect(x: 0, y: 80, width: 200, height: 120), CGRect(x: 0, y: 0, width: 800, height: 600)),
        (CGRect(x: 0, y: 0, width: 800, height: 600), CGRect(x: 0, y: 0, width: 800, height: 600)),
        (CGRect(x: 0, y: 0, width: 24, height: 24), CGRect(x: 0, y: 0, width: 800, height: 600)),
        (CGRect(x: 776, y: 0, width: 24, height: 24), CGRect(x: 0, y: 0, width: 800, height: 600)),
        (CGRect(x: 799, y: 0, width: 1, height: 1), CGRect(x: 0, y: 0, width: 800, height: 600)),
        (CGRect(x: 0, y: 20, width: 24, height: 20), CGRect(x: 0, y: 0, width: 80, height: 40)),
        (CGRect(x: 10, y: 20, width: 24, height: 24), CGRect(x: 10, y: 20, width: 800, height: 600)),
    ], [CGFloat(0), 23, 10_000])
    func completeRadiusControlRemainsInsideScreenBounds(scenario: (selection: CGRect, bounds: CGRect), radius: CGFloat) {
        let (selection, bounds) = scenario
        let position = ScreenshotRoundedCornerGeometry.handlePosition(in: selection, radius: radius, within: bounds)
        let frame = CGRect(x: position.x - 8, y: position.y - 8, width: 16, height: 16)
        #expect(bounds.contains(frame), "The complete radius drag target must remain visible at every screen edge")
        for handle in ScreenshotSelectionHandle.allCases {
            #expect(!frame.contains(ScreenshotSelectionGeometry.position(of: handle, in: selection)),
                    "The radius target must leave every resize handle center available")
        }
    }

    @Test(arguments: [CGFloat(452), 472, 480])
    func radiusReadoutFallsInsideWhenOnlyTheDimensionsFitOutside(selectionWidth: CGFloat) throws {
        let selection = CGRect(x: 200, y: 100, width: selectionWidth, height: 300)
        let bounds = CGSize(width: 800, height: 600)
        let dimensions = ScreenshotSelectionSizeBadge(selection: selection, bounds: bounds)
        let rounded = ScreenshotSelectionSizeBadge(selection: selection, bounds: bounds, cornerRadius: 205)
        #expect(rounded.badgeSize.width > dimensions.badgeSize.width)

        let dimensionsPosition = ScreenshotSelectionGeometry.badgePosition(
            for: selection, in: bounds, badgeSize: dimensions.badgeSize
        )
        let roundedPosition = ScreenshotSelectionGeometry.badgePosition(
            for: selection, in: bounds, badgeSize: rounded.badgeSize
        )
        #expect(dimensionsPosition.x - dimensions.badgeSize.width / 2 > selection.maxX)
        #expect(roundedPosition.x + rounded.badgeSize.width / 2 < selection.maxX)
        #expect(roundedPosition.x - rounded.badgeSize.width / 2 >= 0)

        let renderer = ImageRenderer(content: rounded.frame(width: bounds.width, height: bounds.height))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let centerPixel = try #require(bitmap.colorAt(x: Int(roundedPosition.x), y: Int(roundedPosition.y)))
        let edgePixel = try #require(bitmap.colorAt(x: Int(bounds.width) - 1, y: Int(roundedPosition.y)))
        #expect(centerPixel.alphaComponent > 0.6)
        #expect(edgePixel.alphaComponent == 0, "The rendered radius badge must not overflow the screen edge")
    }

    @Test
    func radiusReadoutStaysWithinTopRightScreenBounds() throws {
        let selection = CGRect(x: 660, y: 0, width: 140, height: 20)
        let bounds = CGSize(width: 800, height: 600)
        let badge = ScreenshotSelectionSizeBadge(selection: selection, bounds: bounds, cornerRadius: 10)
        let position = ScreenshotSelectionGeometry.badgePosition(
            for: selection, in: bounds, badgeSize: badge.badgeSize
        )
        #expect(position.x - badge.badgeSize.width / 2 >= 0)
        #expect(position.x + badge.badgeSize.width / 2 <= bounds.width)
        #expect(position.y - badge.badgeSize.height / 2 >= 0)
        #expect(position.y + badge.badgeSize.height / 2 <= bounds.height)

        let renderer = ImageRenderer(content: badge.frame(width: bounds.width, height: bounds.height).padding(30))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        for y in 0..<30 {
            let pixel = try #require(bitmap.colorAt(x: Int(position.x) + 30, y: y))
            #expect(pixel.alphaComponent == 0, "The radius badge must remain below the top screen boundary")
        }
    }

    @Test(arguments: [1, 2])
    func pngCutsAllFourCornersAtPointRadiusAndPreservesSource(pixelScale: Int) throws {
        let source = try sourceImage(pixelScale: pixelScale)
        let model = ScreenshotEditorModel(image: source)
        #expect(model.cornerRadius == 0)
        #expect(!model.canUndo)
        let rectangularPNG = try #require(model.pngData())
        let rectangular = try bitmap(model.renderedImage())
        #expect(try color(rectangular, at: .zero, scale: pixelScale).alphaComponent == 1)

        model.setCornerRadius(23)
        let rendered = try bitmap(model.renderedImage())
        let png = try #require(model.pngData())
        let exported = try #require(NSBitmapImageRep(data: png))
        for output in [rendered, exported] {
            #expect(output.pixelsWide == 200 * pixelScale)
            #expect(output.pixelsHigh == 120 * pixelScale)
            for point in [CGPoint.zero, CGPoint(x: 199, y: 0), CGPoint(x: 0, y: 119), CGPoint(x: 199, y: 119)] {
                #expect(try color(output, at: point, scale: pixelScale).alphaComponent == 0,
                        "Rounded screenshots must export transparent pixels at every outer corner")
            }
            #expect(try color(output, at: CGPoint(x: 5, y: 5), scale: pixelScale).alphaComponent < 0.1,
                    "Radius is measured in screenshot points, including Retina exports")
            for point in [CGPoint(x: 100, y: 0), CGPoint(x: 0, y: 60), CGPoint(x: 100, y: 119), CGPoint(x: 199, y: 60)] {
                #expect(try color(output, at: point, scale: pixelScale).alphaComponent == 1)
            }
            #expect(try color(output, at: CGPoint(x: 100, y: 60), scale: pixelScale).redComponent < 0.02)
        }
        #expect(model.image === source)
        #expect(try color(try bitmap(source), at: .zero, scale: pixelScale).alphaComponent == 1)
        model.setCornerRadius(0)
        #expect(try color(try bitmap(model.renderedImage()), at: .zero, scale: pixelScale).alphaComponent == 1)
        #expect(model.pngData() == rectangularPNG)
    }

    @Test
    func maximumRadiusClipsToCapsuleAndZeroRestoresAnnotationCorners() throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        let annotation = ScreenshotAnnotation(
            kind: .brush,
            points: [.zero, CGPoint(x: 30, y: 0)],
            color: ScreenshotRGBA(red: 1, green: 0, blue: 0),
            lineWidth: 12
        )
        model.add(annotation)
        let original = try #require(model.pngData())
        model.setCornerRadius(1_000)
        #expect(model.cornerRadius == 60)
        let rounded = try bitmap(model.renderedImage())
        #expect(try color(rounded, at: CGPoint(x: 10, y: 10)).alphaComponent == 0,
                "The final mask must clip annotations as well as the base screenshot")
        #expect(try color(rounded, at: .zero).alphaComponent == 0)
        #expect(try color(rounded, at: CGPoint(x: 100, y: 60)).alphaComponent == 1)
        model.setCornerRadius(0)
        #expect(model.annotations == [annotation])
        #expect(model.pngData() == original)
    }

    @Test
    func continuousAdjustmentCreatesOneUndoStepAndIdleAdjustmentsKeepHistoryUntouched() throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        for _ in 0..<2 {
            model.beginCornerRadiusAdjustment()
            model.setCornerRadius(0)
            model.endCornerRadiusAdjustment()
        }
        #expect(!model.canUndo)
        model.beginCornerRadiusAdjustment()
        model.setCornerRadius(10)
        model.setCornerRadius(20)
        model.setCornerRadius(23)
        model.endCornerRadiusAdjustment()
        #expect(model.cornerRadius == 23)
        model.undo()
        #expect(model.cornerRadius == 0)
        #expect(!model.canUndo, "One continuous drag must create one undo step")
        #expect(model.canRedo)

        model.beginCornerRadiusAdjustment()
        model.setCornerRadius(0)
        model.endCornerRadiusAdjustment()
        #expect(model.canRedo, "An idle adjustment must not erase redo history")
        model.redo()
        #expect(model.cornerRadius == 23)
        model.beginCornerRadiusAdjustment()
        model.setCornerRadius(30)
        model.endCornerRadiusAdjustment()
        model.beginCornerRadiusAdjustment()
        model.setCornerRadius(40)
        model.endCornerRadiusAdjustment()
        model.undo()
        #expect(model.cornerRadius == 30)
        model.undo()
        #expect(model.cornerRadius == 23)
    }

    @Test
    func replacingCaptureClampsRadiusInLiveUndoAndRedoSnapshots() throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        let annotation = ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 10, y: 10, width: 20, height: 20))
        model.add(annotation)
        model.setCornerRadius(55)
        model.setCornerRadius(35)
        model.undo()
        #expect(model.cornerRadius == 55)
        let smaller = try sourceImage(size: CGSize(width: 40, height: 30))
        model.replaceCapture(with: smaller, translatingAnnotationsBy: CGSize(width: 5, height: 3))
        #expect(model.cornerRadius == 15)
        #expect(model.annotations[0].rect == annotation.rect.offsetBy(dx: 5, dy: 3))
        model.redo()
        #expect(model.cornerRadius == 15)
        model.undo()
        #expect(model.cornerRadius == 15)
        model.undo()
        #expect(model.cornerRadius == 0)
        #expect(model.image === smaller)
        #expect(model.annotations[0].rect == annotation.rect.offsetBy(dx: 5, dy: 3))
        model.redo()
        #expect(model.cornerRadius == 15)
    }

    @Test
    func changingImageDimensionsAndUndoInterruptAnAdjustment() throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        model.beginCornerRadiusAdjustment()
        model.setCornerRadius(30)
        model.image = try sourceImage(size: CGSize(width: 20, height: 12))
        #expect(model.cornerRadius == 6)
        model.setCornerRadius(4)
        model.undo()
        #expect(model.cornerRadius == 6,
                "Replacing the base image ends an in-flight adjustment so the next edit gets its own undo step")
        model.undo()
        #expect(model.cornerRadius == 0)
        #expect(model.image.size == CGSize(width: 200, height: 120))
        model.setCornerRadius(15)
        model.undo()
        #expect(model.cornerRadius == 0)
    }

    @Test
    func growingSelectionAfterShrinkingDoesNotReviveAnOutOfRangeHistoricalRadius() throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        model.setCornerRadius(55)
        model.setCornerRadius(35)
        model.undo()
        let small = try sourceImage(size: CGSize(width: 40, height: 30))
        model.replaceCapture(with: small, translatingAnnotationsBy: .zero)
        model.replaceCapture(with: try sourceImage(), translatingAnnotationsBy: .zero)
        #expect(model.cornerRadius == 15)
        model.redo()
        #expect(model.cornerRadius == 15, "Growing the selection must preserve the radius that redo stored after shrinking")
        model.undo()
        #expect(model.cornerRadius == 15)
        model.undo()
        #expect(model.cornerRadius == 0)
        model.redo()
        #expect(model.cornerRadius == 15, "Growing the selection must preserve the radius that undo stored after shrinking")
    }

    @Test
    func extractionUsesUnroundedPixelsAndUndoKeepsTheLiveRadius() async throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        model.setCornerRadius(23)
        let annotation = ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 20, y: 20, width: 30, height: 20))
        model.add(annotation)
        let before = try #require(model.pngData())
        model.extractionMode = .lasso
        model.selectAllExtractionRegions()
        let task = try #require(model.extract())
        await task.value
        #expect(model.hasExtractedImage)
        #expect(model.cornerRadius == 23)
        #expect(model.annotations.isEmpty)
        #expect(try color(try bitmap(model.image), at: .zero).alphaComponent == 1,
                "Extraction must keep the corner pixels available when the radius is later reset")
        let extracted = try #require(model.pngData())
        model.undo()
        #expect(model.cornerRadius == 23)
        #expect(!model.hasExtractedImage)
        #expect(model.annotations == [annotation])
        #expect(model.pngData() == before)
        model.redo()
        #expect(model.cornerRadius == 23)
        #expect(model.hasExtractedImage)
        #expect(model.pngData() == extracted)
        model.setCornerRadius(0)
        #expect(try color(try bitmap(model.renderedImage()), at: .zero).alphaComponent == 1)
    }

    @Test
    func changingRadiusCancelsPendingExtractionAndDiscardsItsLateImage() async throws {
        let source = try sourceImage()
        let model = ScreenshotEditorModel(image: source)
        let gate = ExtractionGate()
        let extraction = model.extract(extractImage: { image, operation in
            try await gate.extract(image, operation: operation)
        })
        let task = try #require(extraction)
        await gate.waitUntilStarted()
        let operation = try #require(await gate.operation)
        model.setCornerRadius(0)
        #expect(model.isExtracting, "Selecting the current radius is an idle edit")
        model.setCornerRadius(23)
        #expect(!model.isExtracting)
        #expect(throws: CancellationError.self) { try operation.checkCancellation() }
        model.statusMessage = "new edit"
        await gate.finish()
        await task.value
        #expect(model.image === source)
        #expect(model.cornerRadius == 23)
        #expect(!model.hasExtractedImage)
        #expect(model.statusMessage == "new edit")
        model.undo()
        #expect(model.cornerRadius == 0)
        #expect(!model.canUndo)
    }

    @Test
    func longScreenshotKeepsRadiusAndRestoresItAcrossImageUndo() throws {
        let model = ScreenshotEditorModel(image: try sourceImage(size: CGSize(width: 100, height: 60)))
        model.setCornerRadius(20)
        #expect(model.append(image: try sourceImage(size: CGSize(width: 100, height: 40))))
        model.completeLongCapturePreview()
        #expect(model.image.size == CGSize(width: 100, height: 100))
        #expect(model.cornerRadius == 20)
        model.setCornerRadius(50)
        model.undo()
        #expect(model.cornerRadius == 20)
        model.undo()
        #expect(model.image.size == CGSize(width: 100, height: 60))
        #expect(model.cornerRadius == 20)
        model.redo()
        #expect(model.image.size == CGSize(width: 100, height: 100))
        #expect(model.cornerRadius == 20)
        model.redo()
        #expect(model.cornerRadius == 50)
        #expect(try color(try bitmap(model.renderedImage()), at: .zero).alphaComponent == 0)
    }

    @Test(arguments: [
        CGRect(x: 50, y: 80, width: 200, height: 120),
        CGRect(x: 100, y: 0, width: 200, height: 120),
        CGRect(x: 100, y: 20, width: 200, height: 120),
        CGRect(x: 0, y: 80, width: 200, height: 120),
        CGRect(x: 0, y: 0, width: 600, height: 420),
        CGRect(x: 0, y: 0, width: 24, height: 24),
        CGRect(x: 576, y: 0, width: 24, height: 24),
        CGRect(x: 0, y: 0, width: 600, height: 24),
    ], [1, 2])
    func radiusHandleDragsThroughTheEditorAndGroupsHistory(selection: CGRect, pixelScale: Int) async throws {
        let image = try sourceImage(size: selection.size, pixelScale: pixelScale)
        let model = ScreenshotEditorModel(image: image)
        let suiteName = "zisla-rounded-corner-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let host = NSHostingView(rootView: ScreenshotEditorView(
            model: model,
            selectionState: ScreenshotAnnotationSelectionState(),
            settingsStore: FeatureSettingsStore(defaults: defaults),
            overlayConfiguration: ScreenshotEditorOverlayConfiguration(
                backgroundImage: image,
                initialSelection: selection,
                cropImage: { _ in image }
            ),
            onClose: {}, onCopy: {}, onPinToggle: { _ in }, onLongCapture: {}
        ).frame(width: 600, height: 420))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 420),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = host
        defer { window.contentView = nil }
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        let handle = try #require(findRadiusHandle(in: host))
        let drag = try #require(handle.onDrag)
        let begin = try #require(handle.onDragBegan)
        #expect(handle.bounds.size == CGSize(width: 16, height: 16))
        assertRadiusHandleRemainsVisibleAndHittable(handle, in: host, selection: selection)
        begin()
        drag(.zero, .zero, false)
        drag(.zero, .zero, true)
        #expect(!model.canUndo)
        let targetRadius = min(23, ScreenshotRoundedCornerGeometry.maximumRadius(for: image.size))
        begin()
        drag(.zero, CGPoint(x: 10, y: 0), false)
        drag(.zero, CGPoint(x: targetRadius, y: 0), false)
        drag(.zero, CGPoint(x: targetRadius, y: 0), true)
        #expect(model.cornerRadius == targetRadius)
        #expect(model.annotations.isEmpty)
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        assertRadiusHandleRemainsVisibleAndHittable(handle, in: host, selection: selection)
        model.undo()
        #expect(model.cornerRadius == 0)
        #expect(!model.canUndo)
        model.redo()
        #expect(model.cornerRadius == targetRadius)
    }

    @Test(arguments: AppLanguage.allCases)
    func cornerRadiusLabelExistsAndRendersInEveryLanguage(language: AppLanguage) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/ScreenshotEditorView.swift"), encoding: .utf8)
        let sourceRange = try #require(source.range(of: "private func cornerRadiusButton"))
        let label = try NSRegularExpression(pattern: #"AppLocalization\.text\("([^"]+)"\)"#)
        let body = String(source[sourceRange.lowerBound...])
        let match = try #require(label.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)))
        let key = String(body[try #require(Range(match.range(at: 1), in: body))])
        let resource = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: resource), format: nil) as? [String: String])
        let translated = try #require(table[key], "Missing \(language.rawValue) translation for the radius control")
        #expect(!translated.isEmpty)
        #expect(AppLocalization.string(key, language: language) == translated)
        if language != .simplifiedChinese { #expect(translated != key) }
        if language != .simplifiedChinese && language != .english {
            #expect(translated != AppLocalization.string(key, language: .english))
        }
        if language == .english { #expect(translated == "Corner radius") }
        if language == .arabic { #expect(translated == "نصف قطر الزوايا") }
    }

    private func sourceImage(size: CGSize = CGSize(width: 200, height: 120), pixelScale: Int = 1) throws -> NSImage {
        let context = try #require(CGContext(
            data: nil, width: Int(size.width) * pixelScale, height: Int(size.height) * pixelScale,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.scaleBy(x: CGFloat(pixelScale), y: CGFloat(pixelScale))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: size.width / 2 - 5, y: size.height / 2 - 5, width: 10, height: 10))
        return NSImage(cgImage: try #require(context.makeImage()), size: size)
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        let source = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return NSBitmapImageRep(cgImage: source)
    }

    private func color(_ bitmap: NSBitmapImageRep, at point: CGPoint, scale: Int = 1) throws -> NSColor {
        try #require(bitmap.colorAt(x: Int(point.x) * scale, y: Int(point.y) * scale)?.usingColorSpace(.deviceRGB))
    }

    private func findRadiusHandle(in view: NSView) -> ScreenshotPointerInteractionNSView? {
        if let handle = view as? ScreenshotPointerInteractionNSView, handle.usesScreenCoordinatesForDrag { return handle }
        return view.subviews.lazy.compactMap { findRadiusHandle(in: $0) }.first
    }

    private func assertRadiusHandleRemainsVisibleAndHittable(
        _ handle: ScreenshotPointerInteractionNSView,
        in host: NSView,
        selection: CGRect
    ) {
        let frame = host.convert(handle.bounds, from: handle)
        #expect(host.bounds.contains(frame), "The editor must display all 16 points of the radius drag target")
        let point = host.convert(CGPoint(x: frame.midX, y: frame.midY), to: host.superview)
        let hit = host.hitTest(point)
        let receivesPointerInput = hit === handle
        #expect(receivesPointerInput,
                "The visible radius control must receive pointer input; frame=\(frame), point=\(point), hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
        for resizeHandle in ScreenshotSelectionHandle.allCases {
            let center = ScreenshotSelectionGeometry.position(of: resizeHandle, in: selection)
            let point = host.convert(center, to: host.superview)
            let coversResizeHandle = host.hitTest(point) === handle
            #expect(!coversResizeHandle, "The radius control must not cover the \(resizeHandle) resize handle center")
        }
    }

    private actor ExtractionGate {
        var operation: ScreenshotExtractionOperation?
        private var source: CGImage?
        private var continuation: CheckedContinuation<CGImage?, any Error>?
        private var startedWaiters: [CheckedContinuation<Void, Never>] = []

        func extract(_ source: CGImage, operation: ScreenshotExtractionOperation) async throws -> CGImage? {
            self.source = source
            self.operation = operation
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                startedWaiters.forEach { $0.resume() }
                startedWaiters = []
            }
        }

        func waitUntilStarted() async {
            if continuation != nil { return }
            await withCheckedContinuation { startedWaiters.append($0) }
        }

        func finish() {
            continuation?.resume(returning: source)
            continuation = nil
        }
    }
}
