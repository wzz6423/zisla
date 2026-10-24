import AppKit
import SwiftUI
import Testing
import Vision
import ZislaCore
@testable import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenshotExtractionTests {
    @Test
    func extractionFollowsObscureAndStartsWithoutChangingTheImage() throws {
        let index = try #require(ScreenshotTool.allCases.firstIndex(of: .mosaic))
        #expect(ScreenshotTool.allCases[index + 1] == .extraction)
        let original = try sourceImage()
        let model = ScreenshotEditorModel(image: original)
        model.tool = .extraction
        #expect(model.image === original)
        #expect(model.extractionMode == nil)
        #expect(model.updateExtractionRegion(loop(CGRect(origin: .zero, size: size)), isComplete: true) == nil)
        #expect(!model.hasExtractedImage)
        #expect(!model.isExtracting)
        #expect(!model.canUndo)
    }

    @Test(arguments: [1, 2])
    func lassoUsesTopLeftPointCoordinatesAndKeepsRetinaPixels(pixelScale: Int) throws {
        let source = try pixels(sourceImage(pixelScale: pixelScale))
        let selection = loop(CGRect(x: 5, y: 4, width: 20, height: 12))
        let operation = ScreenshotExtractionOperation(mode: .lasso, imageSize: size, regions: [selection])
        let extracted = try #require(try operation.extract(source))
        #expect(extracted.width == source.width)
        #expect(extracted.height == source.height)
        let retained = try pixel(extracted, x: 10, y: 8, scale: pixelScale)
        #expect(retained.alphaComponent == 1)
        let original = try pixel(source, x: 10, y: 8, scale: pixelScale)
        #expect(abs(retained.redComponent - original.redComponent) < 0.02)
        #expect(abs(retained.greenComponent - original.greenComponent) < 0.02)
        for point in [CGPoint(x: 10, y: 40), CGPoint(x: 50, y: 8), .zero] {
            #expect(try pixel(extracted, x: Int(point.x), y: Int(point.y), scale: pixelScale).alphaComponent == 0)
        }
    }

    @Test
    func lassoUnionsOverlappingLoopsRegardlessOfWindingAndClipsAtCanvasEdge() throws {
        let source = try pixels(sourceImage())
        let regions = [
            loop(CGRect(x: -10, y: -10, width: 45, height: 40)),
            Array(loop(CGRect(x: 15, y: 15, width: 45, height: 25)).reversed()),
        ]
        let operation = ScreenshotExtractionOperation(mode: .lasso, imageSize: size, regions: regions)
        let extracted = try #require(try operation.extract(source))
        for point in [CGPoint(x: 1, y: 1), CGPoint(x: 25, y: 20), CGPoint(x: 55, y: 35)] {
            #expect(try pixel(extracted, x: Int(point.x), y: Int(point.y)).alphaComponent == 1,
                "Overlaps of differently wound selections must remain visible")
        }
        #expect(try pixel(extracted, x: 70, y: 45).alphaComponent == 0)
    }

    @Test(arguments: ["empty", "line", "outside", "invalid", "nonfinite", "size"])
    func emptyAndInvalidSelectionsDoNotExtractUnselectedPixels(outcome: String) throws {
        let regions: [[CGPoint]]
        switch outcome {
        case "empty": regions = []
        case "line": regions = [[CGPoint(x: 4, y: 8), CGPoint(x: 10, y: 8), CGPoint(x: 18, y: 8)]]
        case "outside": regions = [loop(CGRect(x: 100, y: 100, width: 10, height: 10))]
        case "invalid": regions = [[.zero, CGPoint(x: 10, y: 10)]]
        case "nonfinite": regions = [[.zero, CGPoint(x: CGFloat.infinity, y: 10), CGPoint(x: 10, y: 20)]]
        default: regions = [loop(CGRect(x: 5, y: 5, width: 10, height: 10))]
        }
        let operation = ScreenshotExtractionOperation(mode: .lasso,
            imageSize: outcome == "size" ? .zero : size, regions: regions)
        if ["invalid", "nonfinite", "size"].contains(outcome) {
            #expect(throws: ScreenshotExtractionError.self) { try operation.extract(try pixels(sourceImage())) }
        } else {
            #expect(try operation.extract(try pixels(sourceImage())) == nil)
        }
    }

    @Test
    func cancellationStopsVisionRequestAndRejectsManualWork() throws {
        let request = CancellationProbeRequest()
        let operation = ScreenshotExtractionOperation(mode: .foreground, imageSize: size, request: request)
        operation.cancel()
        #expect(request.wasCancelled)
        #expect(throws: CancellationError.self) { try operation.extract(try pixels(sourceImage())) }
        let manual = ScreenshotExtractionOperation(mode: .lasso, imageSize: size,
            regions: [loop(CGRect(origin: .zero, size: size))])
        manual.cancel()
        #expect(throws: CancellationError.self) { try manual.extract(try pixels(sourceImage())) }
    }

    @Test
    func maskSizeMismatchAndCancellationCannotReturnAnImage() throws {
        let source = try pixels(sourceImage())
        let wrongMask = try #require(try ScreenshotImageExtraction.lassoMask(
            regions: [loop(CGRect(origin: .zero, size: size))], imageSize: size, pixelWidth: 40, pixelHeight: 25))
        #expect(throws: ScreenshotExtractionError.self) {
            try ScreenshotImageExtraction.applying(mask: wrongMask, to: source)
        }
        #expect(throws: CancellationError.self) {
            try ScreenshotImageExtraction.lassoMask(regions: [], imageSize: size,
                pixelWidth: 80, pixelHeight: 50, checkCancellation: { throw CancellationError() })
        }
        let mask = try #require(try ScreenshotImageExtraction.lassoMask(
            regions: [loop(CGRect(origin: .zero, size: size))], imageSize: size, pixelWidth: 80, pixelHeight: 50))
        #expect(throws: CancellationError.self) {
            try ScreenshotImageExtraction.applying(mask: mask, to: source, checkCancellation: { throw CancellationError() })
        }
    }

    @Test
    func completedLoopsExtractImmediatelyAndAccumulateTheirUnion() async throws {
        let original = try sourceImage()
        let model = ScreenshotEditorModel(image: original)
        model.tool = .extraction
        #expect(model.selectExtractionMode(.lasso) == nil)
        #expect(model.image === original)
        #expect(!model.canUndo)
        let first = loop(CGRect(x: 5, y: 5, width: 25, height: 20))
        let second = Array(loop(CGRect(x: 20, y: 15, width: 40, height: 20)).reversed())
        model.updateExtractionRegion(first, isComplete: false)
        #expect(model.pendingExtractionRegion == first)
        #expect(model.extractionRegions.isEmpty)
        #expect(model.updateExtractionRegion(Array(first.prefix(2)), isComplete: true) == nil)
        #expect(model.image === original && !model.canUndo)
        let firstTask = try #require(model.updateExtractionRegion(first, isComplete: true))
        await firstTask.value
        let firstPNG = try #require(model.pngData())
        #expect(try pixel(try pixels(model.image), x: 50, y: 25).alphaComponent == 0)
        let secondTask = try #require(model.updateExtractionRegion(second, isComplete: true))
        await secondTask.value
        #expect(model.pendingExtractionRegion.isEmpty)
        #expect(model.extractionRegions == [first, second])
        for point in [CGPoint(x: 10, y: 10), CGPoint(x: 25, y: 20), CGPoint(x: 50, y: 25)] {
            #expect(try pixel(try pixels(model.image), x: Int(point.x), y: Int(point.y)).alphaComponent == 1)
        }
        #expect(try pixel(try pixels(model.image), x: 70, y: 40).alphaComponent == 0)
        let unionPNG = try #require(model.pngData())
        model.undo()
        #expect(model.extractionRegions == [first])
        #expect(model.pngData() == firstPNG)
        model.redo()
        #expect(model.extractionRegions == [first, second])
        #expect(model.pngData() == unionPNG)
        #expect(model.selectExtractionMode(.lasso) == nil)
        #expect(model.image === original)
        #expect(model.extractionMode == nil && model.extractionRegions.isEmpty)
        model.undo()
        #expect(model.extractionMode == .lasso && model.extractionRegions == [first, second])
        #expect(model.pngData() == unionPNG)
        model.redo()
        #expect(model.image === original && model.extractionMode == nil)
    }

    @Test
    func switchingModesClearsPendingAndUncommittedLassoRegions() async throws {
        let original = try sourceImage()
        let model = ScreenshotEditorModel(image: original)
        model.selectExtractionMode(.lasso)
        let first = ExtractionGate()
        let firstResult = model.updateExtractionRegion(loop(CGRect(x: 3, y: 3, width: 20, height: 20)), isComplete: true,
            extractImage: { image, operation in try await first.extract(image, operation: operation) })
        let firstTask = try #require(firstResult)
        await first.waitUntilStarted()
        model.updateExtractionRegion(loop(CGRect(x: 35, y: 20, width: 20, height: 20)), isComplete: false)
        let next = ExtractionGate()
        let nextResult = model.selectExtractionMode(.foreground, extractImage: { image, operation in
            #expect(operation.regions.isEmpty, "An automatic extraction must not inherit lasso regions")
            return try await next.extract(image, operation: operation)
        })
        let nextTask = try #require(nextResult)
        #expect(model.extractionRegions.isEmpty && model.pendingExtractionRegion.isEmpty)
        await next.waitUntilStarted()
        model.selectExtractionMode(.foreground)
        await first.finish()
        await next.finish()
        await firstTask.value
        await nextTask.value
        #expect(model.image === original && !model.canUndo && model.extractionMode == nil)
    }

    @Test(arguments: [1, 2])
    func extractionFlattensAnnotationsExportsTransparentPNGAndIsOneUndoStep(pixelScale: Int) async throws {
        let model = ScreenshotEditorModel(image: try sourceImage(pixelScale: pixelScale))
        let annotation = ScreenshotAnnotation(kind: .brush,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10)], color: .black, lineWidth: 4)
        model.add(annotation)
        let before = try #require(model.pngData())
        model.selectExtractionMode(.lasso)
        let selection = loop(CGRect(x: 3, y: 3, width: 40, height: 25))
        let taskResult = model.updateExtractionRegion(selection, isComplete: true)
        let task = try #require(taskResult)
        #expect(model.isExtracting)
        await task.value
        #expect(!model.isExtracting)
        #expect(model.hasExtractedImage)
        #expect(model.annotations.isEmpty)
        #expect(model.extractionRegions == [selection])
        #expect(model.statusMessage == AppLocalization.text("提取完成"))
        #expect(model.image.size == size)
        let extracted = try #require(model.pngData())
        let bitmap = try #require(NSBitmapImageRep(data: extracted))
        #expect(bitmap.pixelsWide == 80 * pixelScale)
        #expect(bitmap.pixelsHigh == 50 * pixelScale)
        #expect(try pixel(try pixels(model.renderedImage()), x: 20, y: 10, scale: pixelScale).redComponent < 0.02)
        #expect(try pixel(try pixels(model.mosaicPreviewImage), x: 60, y: 40, scale: pixelScale).alphaComponent == 0)
        let outside = try #require(bitmap.colorAt(x: 60 * pixelScale, y: 40 * pixelScale))
        #expect(outside.alphaComponent == 0)

        model.undo()
        #expect(model.annotations == [annotation])
        #expect(!model.hasExtractedImage)
        #expect(model.pngData() == before)
        model.redo()
        #expect(model.hasExtractedImage)
        #expect(model.pngData() == extracted)
        model.undo()
        model.undo()
        #expect(model.annotations.isEmpty, "Extraction must create exactly one undo step")
    }

    @Test(arguments: [ScreenshotExtractionMode.foreground, .background])
    func automaticModesUseTheAnnotatedSourceAndKeepCanvasSize(mode: ScreenshotExtractionMode) async throws {
        let model = ScreenshotEditorModel(image: try sourceImage(pixelScale: 2))
        model.add(ScreenshotAnnotation(kind: .brush,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10)], color: .black, lineWidth: 4))
        let expected = try pixels(model.renderedImage())
        let taskResult = model.selectExtractionMode(mode, extractImage: { source, operation in
            #expect(operation.mode == mode)
            #expect(operation.imageSize == CGSize(width: 80, height: 50))
            #expect(source.width == expected.width && source.height == expected.height)
            return source
        })
        let task = try #require(taskResult)
        await task.value
        #expect(model.hasExtractedImage)
        #expect(model.annotations.isEmpty)
        #expect(try pixel(try pixels(model.image), x: 20, y: 10, scale: 2).redComponent < 0.02)
    }

    @Test(arguments: ScreenshotExtractionMode.allCases)
    func deselectingRestoresOriginalAndKeepsLaterAnnotationsRadiusAndHistory(mode: ScreenshotExtractionMode) async throws {
        let original = try sourceImage()
        let model = ScreenshotEditorModel(image: original)
        let annotation = ScreenshotAnnotation(kind: .brush,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10)], color: .black, lineWidth: 4)
        model.add(annotation)
        let selection = loop(CGRect(x: 3, y: 3, width: 40, height: 25))
        let extractImage: @Sendable (CGImage, ScreenshotExtractionOperation) async throws -> CGImage? = { source, operation in
            try ScreenshotExtractionOperation(mode: .lasso, imageSize: operation.imageSize, regions: [selection]).extract(source)
        }
        let taskResult: Task<Void, Never>?
        if mode == .lasso {
            model.selectExtractionMode(mode)
            taskResult = model.updateExtractionRegion(selection, isComplete: true, extractImage: extractImage)
        } else {
            taskResult = model.selectExtractionMode(mode, extractImage: extractImage)
        }
        await (try #require(taskResult)).value
        let extracted = model.image
        model.addNumber(at: CGPoint(x: 60, y: 30))
        let later = try #require(model.annotations.first)
        model.setCornerRadius(12)
        model.selectExtractionMode(mode)
        #expect(model.image === original && !model.hasExtractedImage)
        #expect(model.annotations == [annotation, later])
        #expect(model.cornerRadius == 12 && model.numberAnnotation(at: .zero).number == 2)
        #expect(model.extractionMode == nil && model.extractionRegions.isEmpty)
        model.undo()
        #expect(model.image === extracted && model.hasExtractedImage)
        #expect(model.annotations == [later] && model.cornerRadius == 12)
        #expect(model.extractionMode == mode)
        model.redo()
        #expect(model.image === original && model.annotations == [annotation, later])
        #expect(model.cornerRadius == 12 && model.extractionMode == nil)
    }

    @Test
    func switchingAutomaticModesRecomputesOriginalAndLassoStartsFromOriginal() async throws {
        let original = try sourceImage()
        let model = ScreenshotEditorModel(image: original)
        let annotation = ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 5, y: 5, width: 20, height: 20))
        model.add(annotation)
        let selection = loop(CGRect(x: 3, y: 3, width: 30, height: 25))
        let firstResult = model.selectExtractionMode(.foreground, extractImage: { source, operation in
            try ScreenshotExtractionOperation(mode: .lasso, imageSize: operation.imageSize, regions: [selection]).extract(source)
        })
        let first = try #require(firstResult)
        await first.value
        #expect(try pixel(try pixels(model.image), x: 60, y: 30).alphaComponent == 0)
        let secondResult = model.selectExtractionMode(.background, extractImage: { source, operation in
            #expect(operation.mode == .background && operation.regions.isEmpty)
            #expect(NSBitmapImageRep(cgImage: source).colorAt(x: 60, y: 30)?.alphaComponent == 1)
            return source
        })
        let second = try #require(secondResult)
        await second.value
        #expect(model.extractionMode == .background && model.hasExtractedImage)
        #expect(model.selectExtractionMode(.lasso) == nil)
        #expect(model.image === original && model.annotations == [annotation])
        #expect(model.extractionMode == .lasso && model.extractionRegions.isEmpty)
        #expect(!model.hasExtractedImage && !model.isExtracting)
    }

    @Test
    func undoingExtractionDoesNotResurrectAnAnnotationDeletedAfterUndo() async throws {
        let original = try sourceImage()
        let model = ScreenshotEditorModel(image: original)
        let firstResult = model.selectExtractionMode(.foreground, extractImage: { source, _ in source })
        let first = try #require(firstResult)
        await first.value
        let annotation = ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 5, y: 5, width: 20, height: 20))
        model.add(annotation)
        let secondResult = model.selectExtractionMode(.background, extractImage: { source, _ in source })
        let second = try #require(secondResult)
        await second.value
        model.undo()
        #expect(model.annotations == [annotation] && model.extractionMode == .foreground)
        model.remove(id: annotation.id)
        model.selectExtractionMode(.foreground)
        #expect(model.image === original && model.annotations.isEmpty,
            "Undo must restore its own source so deleting a live annotation cannot resurrect it from a later extraction")
    }

    @Test
    func deselectingKeepsPendingDraftsOnTheRestoredOriginal() async throws {
        let original = try sourceImage()
        let model = ScreenshotEditorModel(image: original)
        let firstResult = model.selectExtractionMode(.foreground, extractImage: { source, _ in source })
        let first = try #require(firstResult)
        await first.value
        let text = ScreenshotAnnotation(kind: .text, points: [CGPoint(x: 5, y: 20)],
            rect: CGRect(x: 5, y: 12, width: 50, height: 18), text: "old")
        let draft = ScreenshotAnnotation(kind: .number, points: [CGPoint(x: 60, y: 30)], number: 7)
        model.add(text)
        model.beginTextDraft(id: text.id, text: "edited", isNew: false)
        model.updatePendingAnnotationDraft(draft)
        model.selectExtractionMode(.foreground)
        #expect(model.image === original && model.annotations == [text])
        #expect(model.pendingTextDraft?.text == "edited" && model.pendingAnnotationDraft == draft)
        #expect(!model.hasExtractedImage && model.extractionMode == nil)
    }

    @Test(arguments: ["annotation", "text draft", "shape draft"])
    func cancellingASwitchDoesNotRestoreRemovedOrDiscardedEdits(action: String) async throws {
        let original = try sourceImage()
        let model = ScreenshotEditorModel(image: original)
        let firstResult = model.selectExtractionMode(.foreground, extractImage: { source, _ in source })
        let first = try #require(firstResult)
        await first.value
        let annotation = ScreenshotAnnotation(kind: .text, points: [CGPoint(x: 5, y: 20)],
            rect: CGRect(x: 5, y: 12, width: 50, height: 18), text: "old")
        if action == "shape draft" {
            model.updatePendingAnnotationDraft(ScreenshotAnnotation(kind: .rectangle,
                rect: CGRect(x: 5, y: 5, width: 20, height: 20)))
        } else {
            model.add(annotation)
            if action == "text draft" { model.beginTextDraft(id: annotation.id, text: "edited", isNew: false) }
        }
        let gate = ExtractionGate()
        let secondResult = model.selectExtractionMode(.background, extractImage: { image, operation in
            try await gate.extract(image, operation: operation)
        })
        let second = try #require(secondResult)
        await gate.waitUntilStarted()
        switch action {
        case "annotation": model.remove(id: annotation.id)
        case "text draft": model.discardPendingTextDraft()
        default: model.discardPendingAnnotationDraft()
        }
        let expectedAnnotations = model.annotations
        model.selectExtractionMode(.background)
        #expect(model.image === original && model.annotations == expectedAnnotations)
        #expect(model.pendingTextDraft == nil && model.pendingAnnotationDraft == nil,
            "A cancelled request must not retain a draft that the user has discarded")
        await gate.finish()
        await second.value
        #expect(model.image === original && model.extractionMode == nil && !model.isExtracting)
    }

    @Test(arguments: ["empty", "failure", "transparent", "wrong size", "invalid image", "cancelled"])
    func unsuccessfulExtractionPreservesImageAnnotationsHistoryAndDrafts(outcome: String) async throws {
        let original = outcome == "invalid image" ? NSImage() : try sourceImage()
        let model = ScreenshotEditorModel(image: original)
        let text = ScreenshotAnnotation(kind: .text, points: [CGPoint(x: 5, y: 15)],
            rect: CGRect(x: 5, y: 10, width: 30, height: 15), text: "old")
        let draft = ScreenshotAnnotation(kind: .brush, points: [CGPoint(x: 5, y: 5), CGPoint(x: 20, y: 5)])
        model.add(text, saveUndo: false)
        model.beginTextDraft(id: text.id, text: "edited", isNew: false)
        model.updatePendingAnnotationDraft(draft)
        let taskResult = model.selectExtractionMode(.foreground, extractImage: { _, _ in
            switch outcome {
            case "invalid image": Issue.record("Invalid image must not reach Vision"); return nil
            case "failure": throw ExtractionFailure()
            case "cancelled": throw CancellationError()
            case "transparent": return try Self.transparentPixels(width: 80, height: 50)
            case "wrong size": return try Self.transparentPixels(width: 1, height: 1)
            default: return nil
            }
        })
        let task = try #require(taskResult)
        await task.value
        #expect(model.image === original)
        #expect(model.annotations == [text])
        #expect(model.pendingTextDraft?.text == "edited")
        #expect(model.pendingAnnotationDraft == draft)
        #expect(!model.canUndo && !model.canRedo)
        #expect(!model.hasExtractedImage)
        #expect(!model.isExtracting)
        if outcome == "invalid image" {
            #expect(model.statusMessage == AppLocalization.text("无法读取图片"))
        } else if outcome == "cancelled" {
            #expect(model.statusMessage == nil)
        } else if ["empty", "transparent"].contains(outcome) {
            #expect(model.statusMessage == AppLocalization.text("未找到可提取区域"))
        } else {
            #expect(model.statusMessage?.hasPrefix(AppLocalization.text("提取失败：%@", "")) == true)
        }
    }

    @Test(arguments: [false, true])
    func successfulExtractionIncludesPendingDraftsAndUndoRestoresTheirVisibleContent(alreadyExtracted: Bool) async throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        let base = ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 20, y: 20, width: 30, height: 20))
        if alreadyExtracted {
            model.add(base, saveUndo: false)
            let initialResult = model.selectExtractionMode(.foreground, extractImage: { source, _ in source })
            let initial = try #require(initialResult)
            await initial.value
        }
        let text = ScreenshotAnnotation(kind: .text, points: [CGPoint(x: 5, y: 20)],
            rect: CGRect(x: 5, y: 12, width: 50, height: 18), text: "old", color: .black)
        let number = ScreenshotAnnotation(kind: .number, points: [CGPoint(x: 60, y: 30)], number: 7)
        model.add(text, saveUndo: false)
        model.beginTextDraft(id: text.id, text: "edited", isNew: false)
        model.updatePendingAnnotationDraft(number)
        let taskResult = model.selectExtractionMode(alreadyExtracted ? .background : .foreground,
            extractImage: { source, _ in source })
        let task = try #require(taskResult)
        await task.value
        #expect(model.annotations.isEmpty)
        #expect(model.pendingTextDraft == nil && model.pendingAnnotationDraft == nil)
        #expect(model.numberAnnotation(at: .zero).number == 8)
        model.undo()
        #expect(model.annotations.map(\.text).contains("edited"))
        #expect(model.annotations.contains(number))
        #expect(!model.annotations.contains(base), "Undo must keep annotations already flattened in the extracted base out of the live layer")
        #expect(model.numberAnnotation(at: .zero).number == 8)
        #expect(model.canUndo == alreadyExtracted, "Rendering pending drafts must not add extra history to the live editor")
    }

    @Test(arguments: ["explicit", "parent task", "annotation", "draft", "text", "replacement", "tool", "mode", "same mode", "selection", "undo", "discard annotation", "discard text", "pin"])
    func cancelledOrSupersededExtractionDiscardsItsLateSuccess(action: String) async throws {
        let original = try sourceImage()
        let model = ScreenshotEditorModel(image: original)
        let annotationDraft = ScreenshotAnnotation(kind: .brush, points: [.zero, CGPoint(x: 10, y: 10)])
        if action == "discard annotation" { model.updatePendingAnnotationDraft(annotationDraft) }
        if action == "discard text" { model.beginTextDraft(id: UUID(), text: "pending", isNew: false) }
        let gate = ExtractionGate()
        if action == "selection" { model.selectExtractionMode(.lasso) }
        let extractImage: @Sendable (CGImage, ScreenshotExtractionOperation) async throws -> CGImage? = { image, operation in
            try await gate.extract(image, operation: operation)
        }
        let taskResult = action == "selection"
            ? model.updateExtractionRegion(loop(CGRect(x: 3, y: 3, width: 10, height: 10)), isComplete: true, extractImage: extractImage)
            : model.selectExtractionMode(.foreground, extractImage: extractImage)
        let task = try #require(taskResult)
        await gate.waitUntilStarted()
        let operation = try #require(await gate.operation)
        switch action {
        case "explicit": model.cancelExtraction()
        case "parent task": task.cancel()
        case "annotation": model.add(ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 5, y: 5, width: 20, height: 20)))
        case "draft": model.updatePendingAnnotationDraft(ScreenshotAnnotation(kind: .brush, points: [.zero, CGPoint(x: 10, y: 10)]))
        case "text": model.beginTextDraft(id: UUID(), text: "new", isNew: true)
        case "replacement": model.replaceCapture(with: try sourceImage(pixelScale: 2), translatingAnnotationsBy: .zero)
        case "tool": model.tool = .brush
        case "mode": model.selectExtractionMode(.lasso)
        case "same mode": model.selectExtractionMode(.foreground)
        case "selection": model.updateExtractionRegion(loop(CGRect(x: 3, y: 3, width: 10, height: 10)), isComplete: false)
        case "discard annotation": model.discardPendingAnnotationDraft()
        case "discard text": model.discardPendingTextDraft()
        case "pin": model.isPinned = true
        default: model.undo()
        }
        #expect(throws: CancellationError.self) { try operation.checkCancellation() }
        if action != "parent task" { model.statusMessage = "new editor state" }
        let expectedImage = model.image
        let expectedAnnotations = model.annotations
        await gate.finish()
        await task.value
        #expect(model.image === expectedImage)
        #expect(model.annotations == expectedAnnotations)
        #expect(!model.hasExtractedImage)
        #expect(!model.isExtracting)
        if action != "parent task" { #expect(model.statusMessage == "new editor state") }
    }

    @Test(arguments: [false, true])
    func rapidModeSwitchIgnoresOldSuccessAndFailureAndCurrentModeCancels(oldFails: Bool) async throws {
        let original = try sourceImage()
        let model = ScreenshotEditorModel(image: original)
        let old = ExtractionGate()
        let next = ExtractionGate()
        let firstResult = model.selectExtractionMode(.foreground, extractImage: { image, operation in
            try await old.extract(image, operation: operation)
        })
        let first = try #require(firstResult)
        await old.waitUntilStarted()
        let secondResult = model.selectExtractionMode(.background, extractImage: { image, operation in
            try await next.extract(image, operation: operation)
        })
        let second = try #require(secondResult)
        await next.waitUntilStarted()
        let operation = try #require(await old.operation)
        #expect(throws: CancellationError.self) { try operation.checkCancellation() }
        await old.finish(fails: oldFails)
        await first.value
        #expect(model.isExtracting)
        #expect(model.extractionMode == .background)
        #expect(model.statusMessage == AppLocalization.text("正在提取..."))
        #expect(!model.hasExtractedImage)
        await next.finish()
        await second.value
        #expect(model.hasExtractedImage)
        #expect(!model.isExtracting)
        #expect(model.selectExtractionMode(.background) == nil)
        #expect(!model.isExtracting && model.extractionMode == nil)
        #expect(model.image === original && !model.hasExtractedImage)
    }

    @Test
    func clearingAbsentDraftsKeepsAnActiveExtraction() async throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        let gate = ExtractionGate()
        let taskResult = model.selectExtractionMode(.foreground, extractImage: { image, operation in
            try await gate.extract(image, operation: operation)
        })
        let task = try #require(taskResult)
        await gate.waitUntilStarted()
        model.discardPendingAnnotationDraft()
        model.discardPendingTextDraft()
        #expect(model.isExtracting, "Canvas cleanup without a draft must not cancel the request")
        await gate.finish()
        await task.value
        #expect(model.hasExtractedImage)
    }

    @Test
    func selectingExtractionByHotkeyCommitsLostMouseUpOnce() throws {
        _ = NSApplication.shared
        let fixture = try Fixture(image: sourceImage())
        defer { fixture.close() }
        let draft = ScreenshotAnnotation(kind: .brush, points: [.zero, CGPoint(x: 10, y: 10)])
        fixture.model.updatePendingAnnotationDraft(draft)
        let hotkey = try #require(fixture.settings.settings.screenshotToolHotkeys["extraction"])
        #expect(fixture.controller.performEditorShortcut(keyCode: hotkey.keyCode, modifiers: hotkey.carbonModifiers))
        #expect(fixture.model.tool == .extraction)
        #expect(fixture.model.pendingAnnotationDraft == nil)
        #expect(fixture.model.annotations == [draft])
        fixture.model.undo()
        #expect(fixture.model.annotations.isEmpty)
        #expect(!fixture.model.canUndo, "Switching tools must commit the existing draft exactly once")
    }

    @Test
    func cancellationBeforeDispatchDoesNotRenderOrStartDependency() async throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        let draft = ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 5, y: 5, width: 20, height: 20))
        model.updatePendingAnnotationDraft(draft)
        let taskResult = model.selectExtractionMode(.foreground, extractImage: { _, _ in
            Issue.record("Closing before dispatch must not call the extraction dependency")
            return nil
        })
        let task = try #require(taskResult)
        model.cancelExtraction()
        model.statusMessage = "closed"
        await task.value
        #expect(model.pendingAnnotationDraft == draft)
        #expect(model.annotations.isEmpty)
        #expect(!model.canUndo)
        #expect(model.statusMessage == "closed")
    }

    @Test
    func replacingExtractedCaptureClearsItsTransparencyAndSelectionHistory() async throws {
        let model = ScreenshotEditorModel(image: try sourceImage())
        model.selectExtractionMode(.lasso)
        let taskResult = model.updateExtractionRegion(loop(CGRect(origin: .zero, size: size)), isComplete: true)
        let task = try #require(taskResult)
        await task.value
        #expect(model.hasExtractedImage)
        model.updateExtractionRegion(loop(CGRect(x: 5, y: 5, width: 10, height: 10)), isComplete: false)
        model.replaceCapture(with: try sourceImage(pixelScale: 2), translatingAnnotationsBy: .zero)
        #expect(!model.hasExtractedImage)
        #expect(model.extractionMode == nil)
        #expect(model.pendingExtractionRegion.isEmpty && model.extractionRegions.isEmpty)
        let nextResult = model.selectExtractionMode(.foreground, extractImage: { source, _ in
            #expect(source.width == 160 && source.height == 100, "A new capture must replace the extraction source")
            return source
        })
        await (try #require(nextResult)).value
        model.undo()
        #expect(!model.hasExtractedImage)
        model.undo()
        #expect(!model.hasExtractedImage, "Capture-bound changes also replace the base image in undo history")
    }

    @Test
    func closingEditorCancelsItsRequestAndPreservesItsLateFailure() async throws {
        _ = NSApplication.shared
        let fixture = try Fixture(image: sourceImage())
        defer { fixture.close() }
        let gate = ExtractionGate()
        let taskResult = fixture.model.selectExtractionMode(.foreground, extractImage: { image, operation in
            try await gate.extract(image, operation: operation)
        })
        let task = try #require(taskResult)
        await gate.waitUntilStarted()
        fixture.controller.close()
        #expect(!fixture.model.isExtracting)
        let operation = try #require(await gate.operation)
        #expect(throws: CancellationError.self) { try operation.checkCancellation() }
        fixture.model.statusMessage = "closed editor"
        await gate.finish(fails: true)
        await task.value
        #expect(fixture.model.statusMessage == "closed editor")
        #expect(!fixture.model.hasExtractedImage)
    }

    private let size = CGSize(width: 80, height: 50)

    private func sourceImage(pixelScale: Int = 1) throws -> NSImage {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 80 * pixelScale, pixelsHigh: 50 * pixelScale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                bitmap.setColor(NSColor(deviceRed: CGFloat(x) / CGFloat(bitmap.pixelsWide),
                    green: CGFloat(y) / CGFloat(bitmap.pixelsHigh), blue: 0.5, alpha: 1), atX: x, y: y)
            }
        }
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    private func pixels(_ image: NSImage) throws -> CGImage {
        try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    private func pixel(_ image: CGImage, x: Int, y: Int, scale: Int = 1) throws -> NSColor {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let color = try #require(bitmap.colorAt(x: x * scale, y: y * scale))
        return try #require(color.usingColorSpace(.deviceRGB))
    }

    private func loop(_ rect: CGRect) -> [CGPoint] {
        [rect.origin, CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    nonisolated private static func transparentPixels(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }

    private struct ExtractionFailure: LocalizedError {
        var errorDescription: String? { "Synthetic extraction failure" }
    }

    private actor ExtractionGate {
        var operation: ScreenshotExtractionOperation?
        private var source: CGImage?
        private var continuation: CheckedContinuation<CGImage?, any Error>?
        private var startedWaiters: [CheckedContinuation<Void, Never>] = []

        func extract(_ image: CGImage, operation: ScreenshotExtractionOperation) async throws -> CGImage? {
            self.operation = operation
            source = image
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

        func finish(fails: Bool = false) {
            if fails { continuation?.resume(throwing: ExtractionFailure()) }
            else { continuation?.resume(returning: source) }
            continuation = nil
        }
    }

    private final class CancellationProbeRequest: VNGenerateForegroundInstanceMaskRequest, @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var wasCancelled: Bool { lock.withLock { cancelled } }
        override func cancel() { lock.withLock { cancelled = true }; super.cancel() }
    }

    @MainActor
    private final class Fixture {
        let defaults: UserDefaults
        let defaultsName = "zisla-extraction-tests-\(UUID())"
        let settings: FeatureSettingsStore
        let controller: ScreenshotEditorWindowController
        let model: ScreenshotEditorModel

        init(image: NSImage) throws {
            defaults = try #require(UserDefaults(suiteName: defaultsName))
            settings = FeatureSettingsStore(defaults: defaults)
            let source = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            controller = ScreenshotEditorWindowController(image: image, screenImage: image, screenCGImage: source,
                screen: nil, captureRect: CGRect(origin: .zero, size: image.size), capturedApplication: nil,
                settingsStore: settings, onStash: { _, _ in }, writeImageToPasteboard: { _ in false }, onClose: {})
            controller.window?.alphaValue = 0
            let hosting = try #require(controller.window?.contentView as? NSHostingView<AppLanguageEnvironment<ScreenshotEditorView>>)
            model = hosting.rootView.content.model
        }

        func close() {
            controller.close()
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: defaultsName)
        }
    }
}
