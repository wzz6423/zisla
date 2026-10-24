import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct ScreenshotHighlighterTests {
    @Test
    func highlighterFollowsBrushAndDefaultsToKeepingMarkers() throws {
        let brushIndex = try #require(ScreenshotTool.allCases.firstIndex(of: .brush))
        #expect(ScreenshotTool.allCases[brushIndex + 1] == .highlighter)
        #expect(ScreenshotTool.highlighter.title == "荧光笔")
        #expect(ScreenshotAnnotation(kind: .highlighter).highlighterShowsMarkers)
        #expect(ScreenshotEditorModel(image: NSImage(size: CGSize(width: 200, height: 120)))
            .highlighterShowsMarkers)
    }

    @Test(arguments: [1, 2])
    func pngKeepsSourceReadableAndExportsOpaqueMarkers(pixelScale: Int) throws {
        let model = ScreenshotEditorModel(image: try sourceImage(pixelScale: pixelScale))
        model.add(highlighter())
        let png = try #require(model.pngData())
        let bitmap = try #require(NSBitmapImageRep(data: png))
        #expect(bitmap.pixelsWide == 200 * pixelScale)
        #expect(bitmap.pixelsHigh == 120 * pixelScale)

        let highlight = try pixel(bitmap, x: 80, y: 45, scale: pixelScale)
        #expect(highlight.redComponent > 0.98)
        #expect(abs(highlight.greenComponent - 0.7) < 0.03)
        #expect(abs(highlight.blueComponent - 0.7) < 0.03)

        let darkSource = try pixel(bitmap, x: 80, y: 60, scale: pixelScale)
        #expect(abs(darkSource.redComponent - 0.3) < 0.03)
        #expect(darkSource.greenComponent < 0.02)
        #expect(darkSource.blueComponent < 0.02)

        for point in [CGPoint(x: 36, y: 34), CGPoint(x: 164, y: 76), CGPoint(x: 40, y: 55), CGPoint(x: 160, y: 55)] {
            let marker = try pixel(bitmap, x: Int(point.x), y: Int(point.y), scale: pixelScale)
            #expect(marker.redComponent > 0.98)
            #expect(marker.greenComponent < 0.02)
            #expect(marker.blueComponent < 0.02)
        }
        let outside = try pixel(bitmap, x: 20, y: 100, scale: pixelScale)
        #expect(outside.redComponent > 0.99 && outside.greenComponent > 0.99 && outside.blueComponent > 0.99)
    }

    @Test
    func hidingMarkersRemovesDotsAndEndLinesFromPNG() throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        model.add(highlighter(showsMarkers: false))
        let png = try #require(model.pngData())
        let bitmap = try #require(NSBitmapImageRep(data: png))
        for point in [CGPoint(x: 40, y: 34), CGPoint(x: 160, y: 76)] {
            let dot = try pixel(bitmap, x: Int(point.x), y: Int(point.y))
            #expect(dot.redComponent > 0.99 && dot.greenComponent > 0.99 && dot.blueComponent > 0.99)
        }
        let endLine = try pixel(bitmap, x: 41, y: 55)
        #expect(abs(endLine.greenComponent - 0.7) < 0.03)
        let fill = try pixel(bitmap, x: 80, y: 45)
        #expect(abs(fill.greenComponent - 0.7) < 0.03)
    }

    @Test
    func pngUsesSRGBColorsMatchingTheCanvasAtBothPixelScales() throws {
        let image = try sourceImage()
        let model = ScreenshotEditorModel(image: image)
        let annotation = highlighter()
        model.add(annotation)
        let png = try #require(model.pngData())
        let exported = try #require(NSBitmapImageRep(data: png))
        #expect(exported.colorSpace == NSColorSpace.sRGB)
        let marker = try pixel(exported, x: 40, y: 34)
        #expect(marker.redComponent > 0.98 && marker.greenComponent < 0.02 && marker.blueComponent < 0.02)
        for scale: CGFloat in [1, 2] {
            let renderer = ImageRenderer(content: ScreenshotHighlighterReferencePreview(
                annotation: annotation, image: image, canvasScale: scale
            ))
            renderer.scale = 1
            let rendered = try #require(renderer.cgImage)
            let preview = NSBitmapImageRep(cgImage: rendered)
            for point in [CGPoint(x: 80, y: 45), CGPoint(x: 36, y: 34), CGPoint(x: 164, y: 76), CGPoint(x: 160, y: 55)] {
                let expected = try pixel(exported, x: Int(point.x), y: Int(point.y))
                let actual = try pixel(preview, x: Int(point.x), y: Int(point.y), scale: Int(scale))
                #expect(abs(actual.redComponent - expected.redComponent) <= 2.0 / 255)
                #expect(abs(actual.greenComponent - expected.greenComponent) <= 2.0 / 255)
                #expect(abs(actual.blueComponent - expected.blueComponent) <= 2.0 / 255)
            }
        }
    }

    @Test
    func fillAndMarkersPreserveTheChosenColorAlpha() throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        var annotation = highlighter()
        annotation.color.alpha = 0.4
        model.add(annotation)
        let png = try #require(model.pngData())
        let bitmap = try #require(NSBitmapImageRep(data: png))
        let fill = try pixel(bitmap, x: 80, y: 45)
        #expect(abs(fill.greenComponent - 0.88) < 0.02)
        let marker = try pixel(bitmap, x: 40, y: 34)
        #expect(abs(marker.greenComponent - 0.6) < 0.02)
    }

    @Test
    func negativeRectangleUsesTheSameVisibleMarkerBounds() throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        var annotation = highlighter()
        annotation.rect = CGRect(x: 160, y: 70, width: -120, height: -30)
        model.add(annotation)
        let png = try #require(model.pngData())
        let bitmap = try #require(NSBitmapImageRep(data: png))
        let marker = try pixel(bitmap, x: 36, y: 34)
        #expect(marker.redComponent > 0.98 && marker.greenComponent < 0.02 && marker.blueComponent < 0.02)
    }

    @Test
    func markerStyleChangesAreUndoableAndDoNotTouchOtherAnnotations() throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        let annotation = highlighter()
        let rectangle = ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 5, y: 5, width: 20, height: 20))
        model.add(rectangle)
        model.add(annotation)
        model.applySelectedStyle(to: annotation.id, color: .black, lineWidth: 5, highlighterShowsMarkers: false)
        #expect(model.annotations[0] == rectangle)
        #expect(model.annotations[1].color == .black)
        #expect(model.annotations[1].lineWidth == 5)
        #expect(!model.annotations[1].highlighterShowsMarkers)

        model.undo()
        #expect(model.annotations == [rectangle, annotation])
        model.redo()
        #expect(!model.annotations[1].highlighterShowsMarkers)
        model.applySelectedStyle(to: annotation.id, highlighterShowsMarkers: false)
        model.applySelectedStyle(to: UUID(), highlighterShowsMarkers: false)
        model.applySelectedStyle(to: rectangle.id, highlighterShowsMarkers: false)
        model.undo()
        #expect(model.annotations == [rectangle, annotation])
    }

    @Test
    func editingPreservesMarkerPreferenceAndSupportsEdgesAndRotation() throws {
        let original = highlighter(showsMarkers: false)
        let moved = ScreenshotAnnotationGeometry.transform(
            original, handle: nil, from: .zero, to: CGPoint(x: 10, y: 5)
        )
        #expect(moved.rect == original.rect.offsetBy(dx: 10, dy: 5))
        #expect(!moved.highlighterShowsMarkers)
        let scaled = ScreenshotAnnotationTransform.scaled(moved, by: 2)
        #expect(scaled.rect.size == CGSize(width: 240, height: 60))
        #expect(!scaled.highlighterShowsMarkers)

        #expect(ScreenshotAnnotationGeometry.handle(at: CGPoint(x: 100, y: 40), in: original) == .top)
        #expect(ScreenshotAnnotationGeometry.handle(at: CGPoint(x: 160, y: 55), in: original) == .right)
        #expect(ScreenshotAnnotationGeometry.handle(at: CGPoint(x: 100, y: 70), in: original) == .bottom)
        #expect(ScreenshotAnnotationGeometry.handle(at: CGPoint(x: 40, y: 55), in: original) == .left)
        #expect(ScreenshotAnnotationGeometry.handle(at: CGPoint(x: 100, y: 16), in: original) == .rotation)
        let resized = ScreenshotAnnotationGeometry.transform(
            original, handle: .bottomRight, from: CGPoint(x: 160, y: 70), to: CGPoint(x: 190, y: 90)
        )
        #expect(resized.rect == CGRect(x: 40, y: 40, width: 150, height: 50))
        #expect(!resized.highlighterShowsMarkers)
        #expect(ScreenshotAnnotationGeometry.contains(CGPoint(x: 80, y: 55), in: original))
        #expect(!ScreenshotAnnotationGeometry.contains(CGPoint(x: 5, y: 5), in: original))
    }

    @Test
    func rotatedMarkersFollowTheSameDirectionAsCanvasGeometry() throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        var annotation = highlighter()
        annotation.rect = CGRect(x: 60, y: 40, width: 80, height: 30)
        annotation.rotation = .pi / 4
        model.add(annotation)
        let png = try #require(model.pngData())
        let bitmap = try #require(NSBitmapImageRep(data: png))
        let clockwiseLeftDot = try pixel(bitmap, x: 87, y: 12)
        #expect(clockwiseLeftDot.redComponent > 0.98)
        #expect(clockwiseLeftDot.greenComponent < 0.02)
        let oppositeDirection = try pixel(bitmap, x: 57, y: 68)
        #expect(oppositeDirection.redComponent > 0.99 && oppositeDirection.greenComponent > 0.99
            && oppositeDirection.blueComponent > 0.99)
    }

    @Test
    func emptyHighlighterDoesNotExportOrIntroduceMarkers() throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        let before = try #require(model.pngData())
        model.add(ScreenshotAnnotation(kind: .highlighter, color: ScreenshotRGBA(red: 1, green: 0, blue: 0)))
        #expect(ScreenshotHighlighterGeometry.markersPath(in: .zero, lineWidth: 3).isEmpty)
        #expect(model.pngData() == before)
    }

    @Test
    func exportingPendingHighlighterCommitsItOnceAndKeepsMarkerPreference() throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        let draft = highlighter(showsMarkers: false)
        model.updatePendingAnnotationDraft(draft)
        let first = try #require(model.pngData())
        #expect(model.annotations == [draft])
        #expect(model.pendingAnnotationDraft == nil)
        #expect(model.pngData() == first)
        model.undo()
        #expect(model.annotations.isEmpty)
        model.redo()
        #expect(model.annotations == [draft])
        model.undo()
        #expect(model.annotations.isEmpty)
    }

    @Test
    func canvasCommitsReverseDragRejectsTinyRegionsAndSynchronizesUndo() async throws {
        let size = CGSize(width: 400, height: 300)
        let selection = CGRect(x: 40, y: 40, width: 200, height: 120)
        let image = try sourceImage()
        let model = ScreenshotEditorModel(image: image)
        let state = ScreenshotAnnotationSelectionState()
        let suiteName = "zisla-highlighter-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = FeatureSettingsStore(defaults: defaults)
        model.tool = .highlighter
        model.highlighterShowsMarkers = false
        let host = NSHostingView(rootView: ScreenshotEditorView(
            model: model,
            selectionState: state,
            settingsStore: settings,
            overlayConfiguration: ScreenshotEditorOverlayConfiguration(
                backgroundImage: image,
                initialSelection: selection,
                cropImage: { _ in image }
            ),
            onClose: {}, onCopy: {}, onPinToggle: { _ in }, onLongCapture: {}
        ).frame(width: size.width, height: size.height))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.alphaValue = 0
        window.contentView = host
        defer { window.contentView = nil }
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        let canvas = try #require(findCanvas(in: host))
        let drag = try #require(canvas.onDrag)
        drag(CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 60), false)
        #expect(model.pendingAnnotationDraft == nil)
        drag(CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 60), true)
        #expect(model.annotations.isEmpty)

        drag(CGPoint(x: 160, y: 70), CGPoint(x: 40, y: 40), false)
        #expect(model.pendingAnnotationDraft?.rect == CGRect(x: 40, y: 40, width: 120, height: 30))
        #expect(model.pendingAnnotationDraft?.highlighterShowsMarkers == false)
        drag(CGPoint(x: 160, y: 70), CGPoint(x: 40, y: 40), true)
        #expect(model.annotations.count == 1)
        let annotation = try #require(model.annotations.first)
        #expect(annotation.kind == .highlighter)
        #expect(!annotation.highlighterShowsMarkers)
        state.selectedAnnotationID = annotation.id
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        model.highlighterShowsMarkers = true
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        #expect(model.annotations.first?.highlighterShowsMarkers == true)
        model.undo()
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        #expect(model.annotations.first?.highlighterShowsMarkers == false)
        #expect(!model.highlighterShowsMarkers)
        model.redo()
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        #expect(model.annotations.first?.highlighterShowsMarkers == true)
        #expect(model.highlighterShowsMarkers)
    }

    @Test
    func everyLanguageTranslatesTheHighlighterAndActualMarkerToggle() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/ScreenshotEditorView.swift"), encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"Toggle\(AppLocalization\.text\("([^"]+)"\), isOn: \$model\.highlighterShowsMarkers\)"#
        )
        let match = try #require(expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        let toggleKey = String(source[try #require(Range(match.range(at: 1), in: source))])
        let keys = [ScreenshotTool.highlighter.title, toggleKey]
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let table = try #require(NSDictionary(contentsOf: root.appendingPathComponent(
                "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
            )) as? [String: String])
            for key in keys {
                let translation = try #require(table[key], "\(language.rawValue) missing \(key)")
                #expect(!translation.isEmpty)
                if language != .simplifiedChinese { #expect(translation != key) }
                if language != .english && language != .simplifiedChinese {
                    #expect(translation != AppLocalization.string(key, language: .english))
                }
                #expect(AppLocalization.string(key, language: language) == translation)
            }
        }
        #expect(AppLocalization.string("荧光笔", language: .english) == "Highlighter")
        #expect(AppLocalization.string(toggleKey, language: .arabic) == "الاحتفاظ بعلامات الطرفين")
    }

    private func highlighter(showsMarkers: Bool = true) -> ScreenshotAnnotation {
        ScreenshotAnnotation(
            kind: .highlighter,
            rect: CGRect(x: 40, y: 40, width: 120, height: 30),
            color: ScreenshotRGBA(red: 1, green: 0, blue: 0),
            highlighterShowsMarkers: showsMarkers
        )
    }

    private func sourceImage(pixelScale: Int = 1) throws -> NSImage {
        let context = try #require(CGContext(
            data: nil, width: 200 * pixelScale, height: 120 * pixelScale,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.scaleBy(x: CGFloat(pixelScale), y: CGFloat(pixelScale))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 75, y: 55, width: 12, height: 10))
        return NSImage(cgImage: try #require(context.makeImage()), size: CGSize(width: 200, height: 120))
    }

    private func pixel(_ bitmap: NSBitmapImageRep, x: Int, y: Int, scale: Int = 1) throws -> NSColor {
        try #require(bitmap.colorAt(x: x * scale, y: y * scale))
    }

    private func findCanvas(in view: NSView) -> ScreenshotPointerInteractionNSView? {
        if let canvas = view as? ScreenshotPointerInteractionNSView { return canvas }
        return view.subviews.lazy.compactMap { findCanvas(in: $0) }.first
    }
}

@MainActor
private struct ScreenshotHighlighterReferencePreview: View {
    let annotation: ScreenshotAnnotation
    let image: NSImage
    var canvasScale: CGFloat = 1

    var body: some View {
        let geometry = ScreenshotCanvasGeometry(
            canvasSize: CGSize(width: image.size.width * canvasScale, height: image.size.height * canvasScale),
            imageSize: image.size
        )
        let canvasRect = geometry.canvasRect(from: annotation.rect)
        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .frame(width: geometry.renderedSize.width, height: geometry.renderedSize.height)
            Rectangle()
                .fill(annotation.color.swiftUIColor.opacity(Double(ScreenshotHighlighterGeometry.opacity)))
                .frame(width: canvasRect.width, height: canvasRect.height)
                .position(x: canvasRect.midX, y: canvasRect.midY)
            ScreenshotHighlighterGeometry.markersPath(in: canvasRect, lineWidth: annotation.lineWidth * geometry.scale)
                .fill(annotation.color.swiftUIColor)
        }
        .frame(width: geometry.renderedSize.width, height: geometry.renderedSize.height)
    }
}
