import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
import Vision

@testable import Zisla

@MainActor
struct ScreenshotEditorTests {
    @Test
    func captureRejectsMissingScreenRecordingPermissionBeforeReadingDisplay() {
        #expect(throws: ScreenshotCaptureError.permissionRequired) {
            try ScreenshotCaptureService.requirePermission { false }
        }
    }

    @Test
    func selectionHandlesResizeAndClampToScreenBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let source = CGRect(x: 100, y: 120, width: 300, height: 200)

        let expanded = ScreenshotSelectionGeometry.resized(
            source,
            using: .bottomRight,
            translation: CGSize(width: 500, height: 400),
            within: bounds
        )
        #expect(expanded == CGRect(x: 100, y: 120, width: 700, height: 480))

        let narrowed = ScreenshotSelectionGeometry.resized(
            source,
            using: .left,
            translation: CGSize(width: 500, height: 0),
            within: bounds
        )
        #expect(narrowed.width == ScreenshotSelectionGeometry.minimumLength)
        #expect(narrowed.maxX == source.maxX)
    }

    @Test
    func selectionHasFourCornersAndFourEdgeMidpointHandles() {
        let rect = CGRect(x: 100, y: 120, width: 300, height: 200)

        #expect(ScreenshotSelectionHandle.allCases.count == 8)
        #expect(ScreenshotSelectionGeometry.position(of: .top, in: rect) == CGPoint(x: 250, y: 120))
        #expect(ScreenshotSelectionGeometry.position(of: .right, in: rect) == CGPoint(x: 400, y: 220))
        #expect(ScreenshotSelectionGeometry.position(of: .bottom, in: rect) == CGPoint(x: 250, y: 320))
        #expect(ScreenshotSelectionGeometry.position(of: .left, in: rect) == CGPoint(x: 100, y: 220))
    }

    @Test
    func selectionSizeBadgePrefersOutsideRightThenFallsInside() {
        let bounds = CGSize(width: 800, height: 600)
        let badge = ScreenshotSelectionGeometry.badgeEstimatedSize
        let gap: CGFloat = 8

        // Regular selection: place the label outside on the right and align it with the bottom edge.
        let normal = CGRect(x: 200, y: 100, width: 300, height: 200)
        let normalPos = ScreenshotSelectionGeometry.badgePosition(for: normal, in: bounds)
        #expect(normalPos.x == normal.maxX + gap + badge.width / 2)
        #expect(normalPos.y == normal.maxY - badge.height / 2)

        // Bottom-right selection: fall back to placing the label inside on the right.
        let farRight = CGRect(x: 660, y: 400, width: 140, height: 180)
        let farRightPos = ScreenshotSelectionGeometry.badgePosition(for: farRight, in: bounds)
        #expect(farRightPos.x == farRight.maxX - gap - badge.width / 2)
        #expect(farRightPos.x >= badge.width / 2)
        #expect(farRightPos.y == farRight.maxY - badge.height / 2)

        // Narrow top selection: align the label bottoms and clamp it within the screen vertically.
        let topBar = CGRect(x: 0, y: 0, width: 400, height: 20)
        let topBarPos = ScreenshotSelectionGeometry.badgePosition(for: topBar, in: bounds)
        #expect(topBarPos.y >= badge.height / 2)
        #expect(topBarPos.x == topBar.maxX + gap + badge.width / 2)

        // Full-screen selection: fall back to the inside bottom-right corner.
        let fullScreen = ScreenshotSelectionGeometry.badgePosition(
            for: CGRect(origin: .zero, size: bounds),
            in: bounds
        )
        #expect(fullScreen.x == bounds.width - gap - badge.width / 2)
    }

    @Test
    func toolbarUsesCompactControlsAndDragPositionStaysOnScreen() {
        #expect(ScreenshotToolbarLayout.controlCount == 15)
        #expect(ScreenshotToolbarLayout.cornerRadius == 10)
        #expect(ScreenshotToolbarLayout.borderOpacity == 0.08)
        #expect(ScreenshotToolbarLayout.dragHandleColumns == 2)
        #expect(ScreenshotToolbarLayout.dragHandleRows == 3)
        #expect(ScreenshotToolbarLayout.dragHandleWidth == 28)
        #expect(ScreenshotPinnedLayout.toolbarCornerRadius == 10)
        #expect(ScreenshotPinnedLayout.toolbarBorderOpacity == 0.08)
        #expect(ScreenshotPinnedLayout.dragHandleWidth == 28)
        let expectedWidth = ScreenshotToolbarLayout.horizontalPadding * 2
            + ScreenshotToolbarLayout.dragHandleWidth
            + CGFloat(ScreenshotToolbarLayout.controlCount) * ScreenshotToolbarLayout.controlWidth
            + CGFloat(ScreenshotToolbarLayout.controlCount) * ScreenshotToolbarLayout.spacing
        #expect(ScreenshotToolbarLayout.contentWidth == expectedWidth)
        #expect(ScreenshotToolbarLayout.viewportWidth(availableWidth: 2_000) == expectedWidth)
        #expect(ScreenshotToolbarLayout.viewportWidth(availableWidth: 1_200) == 968)
        #expect(ScreenshotToolbarLayout.controlWidth <= 60)
        #expect(ScreenshotToolbarLayout.height <= 38)

        let clamped = ScreenshotToolbarLayout.clampedCenter(
            CGPoint(x: -100, y: 900),
            toolbarSize: CGSize(width: 300, height: ScreenshotToolbarLayout.height),
            in: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        #expect(clamped == CGPoint(x: 150, y: 581))
    }

    @Test
    func changingCaptureBoundsKeepsAnnotationsAtTheirScreenPosition() {
        let model = ScreenshotEditorModel(image: NSImage(size: CGSize(width: 300, height: 200)))
        model.add(ScreenshotAnnotation(
            kind: .rectangle,
            rect: CGRect(x: 40, y: 30, width: 80, height: 50)
        ))
        model.add(ScreenshotAnnotation(
            kind: .brush,
            points: [CGPoint(x: 30, y: 20), CGPoint(x: 90, y: 60)]
        ))

        model.replaceCapture(
            with: NSImage(size: CGSize(width: 380, height: 260)),
            translatingAnnotationsBy: CGSize(width: 30, height: 20)
        )

        #expect(model.image.size == CGSize(width: 380, height: 260))
        #expect(model.annotations[0].rect == CGRect(x: 70, y: 50, width: 80, height: 50))
        #expect(model.annotations[1].points == [CGPoint(x: 60, y: 40), CGPoint(x: 120, y: 80)])
    }

    @Test
    func textFontSizeIsIndependentFromAnnotationLineWidth() {
        let thin = ScreenshotAnnotation(kind: .text, text: "批注", lineWidth: 1, fontSize: 32)
        let thick = ScreenshotAnnotation(kind: .text, text: "批注", lineWidth: 12, fontSize: 32)

        #expect(thin.fontSize == thick.fontSize)
        #expect(thin.lineWidth != thick.lineWidth)
    }

    @Test
    func newAnnotationDefaultsUseThreeForStrokeAndSize() {
        let model = ScreenshotEditorModel(image: NSImage(size: CGSize(width: 100, height: 100)))
        let annotation = ScreenshotAnnotation(kind: .rectangle)

        #expect(model.lineWidth == 3)
        #expect(model.fontSize == 14)
        #expect(annotation.lineWidth == 3)
        #expect(annotation.fontSize == 14)
    }

    @Test
    func rotationHandleExtendsAboveTheAnnotationBoundary() {
        #expect(ScreenshotAnnotationGeometry.rotationOffset > 0)
    }

    @Test
    func rotationPreviewAnimationIsShortAndCriticallyDamped() {
        #expect(ScreenshotCanvasStyle.rotationAnimationResponse <= 0.1)
        #expect(ScreenshotCanvasStyle.rotationAnimationDampingFraction == 1)
    }

    @Test
    func toolbarWidthShrinksWhenHistoryActionsAreHidden() {
        let full = ScreenshotToolbarLayout.contentWidth(forControlCount: 15)
        let withoutHistory = ScreenshotToolbarLayout.contentWidth(forControlCount: 13)
        #expect(withoutHistory < full)
    }

    @Test
    func shapeDraftsUseSolidStrokes() {
        #expect(ScreenshotCanvasStyle.draftDashPattern.isEmpty)
    }

    @Test
    func brushAnnotationHitTestingIncludesTheEntireStroke() {
        let brush = ScreenshotAnnotation(
            kind: .brush,
            points: [
                CGPoint(x: 20, y: 40),
                CGPoint(x: 60, y: 40),
                CGPoint(x: 100, y: 40),
            ],
            lineWidth: 3
        )

        #expect(ScreenshotAnnotationGeometry.contains(CGPoint(x: 80, y: 40), in: brush))
    }

    @Test
    func canvasGeometryRoundTripsImagePoints() {
        let geometry = ScreenshotCanvasGeometry(
            canvasSize: CGSize(width: 800, height: 500),
            imageSize: CGSize(width: 1_600, height: 900)
        )
        let source = CGPoint(x: 420, y: 260)
        let rendered = geometry.canvasPoint(from: source)
        let recovered = geometry.imagePoint(from: rendered)

        #expect(abs(recovered.x - source.x) < 0.01)
        #expect(abs(recovered.y - source.y) < 0.01)
    }

    @Test
    func zoomedCanvasGeometryKeepsImagePointsAligned() {
        let geometry = ScreenshotCanvasGeometry(
            canvasSize: CGSize(width: 800, height: 500),
            imageSize: CGSize(width: 1_600, height: 900),
            zoom: 2
        )
        let source = CGPoint(x: 420, y: 260)
        let rendered = geometry.canvasPoint(from: source)
        let recovered = geometry.imagePoint(from: rendered)

        #expect(abs(geometry.scale - 1) < 0.01)
        #expect(geometry.origin.x < 0 || geometry.origin.y < 0)
        #expect(abs(recovered.x - source.x) < 0.01)
        #expect(abs(recovered.y - source.y) < 0.01)
    }

    @Test
    func canvasZoomClampsToItsEditingRange() {
        let range: ClosedRange<CGFloat> = 0.5...4

        #expect(ScreenshotPinnedInteraction.scale(current: 1, magnification: -0.9, range: range) == 0.5)
        #expect(ScreenshotPinnedInteraction.scale(current: 1, magnification: 10, range: range) == 4)
    }

    @Test
    func canvasGeometryClampsPanOffsetToRenderedBounds() {
        let geometry = ScreenshotCanvasGeometry(
            canvasSize: CGSize(width: 800, height: 500),
            imageSize: CGSize(width: 1_600, height: 900),
            zoom: 2,
            offset: CGSize(width: 1_000, height: -1_000)
        )

        #expect(geometry.offset == CGSize(width: 400, height: -200))
        #expect(geometry.origin == CGPoint(x: 0, y: -400))
    }

    @Test
    func pointerInteractionReportsTwoAxisScrollDeltas() {
        var offsets: [CGSize] = []
        let interactionView = ScreenshotPointerInteractionNSView()
        interactionView.onScrollPan = { offsets.append($0) }

        interactionView.handleScroll(
            deltaX: 12,
            deltaY: -20,
            directionInverted: true,
            precise: true
        )

        #expect(offsets == [CGSize(width: -12, height: 20)])
    }

    @Test
    func emptyOverlayCanvasCommitsGesturesForEveryDrawableTool() async throws {
        let size = CGSize(width: 400, height: 300)
        let selection = CGRect(x: 60, y: 50, width: 220, height: 140)
        let image = try #require(makeGradientImage(width: 400, height: 300))
        let model = ScreenshotEditorModel(image: NSImage(size: selection.size))
        model.tool = .rectangle
        let hostingView = NSHostingView(rootView:
            ScreenshotEditorView(
                model: model,
                selectionState: ScreenshotAnnotationSelectionState(),
                overlayConfiguration: ScreenshotEditorOverlayConfiguration(
                    backgroundImage: image,
                    initialSelection: selection,
                    cropImage: { _ in image }
                ),
                onClose: {},
                onCopy: {},
                onPinToggle: { _ in },
                onLongCapture: {}
            )
            .frame(width: size.width, height: size.height)
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.contentView = hostingView
        for _ in 0..<3 {
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        #expect(hostingView.frame.size == size)
        let interactionView = try #require(
            findSubview(ScreenshotPointerInteractionNSView.self, in: hostingView)
        )
        #expect(interactionView.frame.size == selection.size)

        try sendMouseDrag(
            from: CGPoint(x: 30, y: 30),
            to: CGPoint(x: 120, y: 90),
            through: interactionView,
            in: window
        )

        #expect(model.annotations.count == 1)
        #expect(model.annotations.first?.kind == .rectangle)

        let tools: [(ScreenshotTool, ScreenshotAnnotation.Kind)] = [
            (.ellipse, .ellipse),
            (.brush, .brush),
            (.arrow, .arrow),
            (.number, .number),
            (.emoji, .emoji),
        ]
        for (tool, expectedKind) in tools {
            let previousCount = model.annotations.count
            model.tool = tool
            try sendMouseDrag(
                from: CGPoint(x: 35, y: 35),
                to: CGPoint(x: 125, y: 95),
                through: interactionView,
                in: window
            )
            #expect(model.annotations.count == previousCount + 1)
            #expect(model.annotations.last?.kind == expectedKind)
        }

        model.tool = .mosaic
        for shape in ScreenshotObscureShape.allCases {
            let previousCount = model.annotations.count
            model.obscureShape = shape
            try sendMouseDrag(
                from: CGPoint(x: 40, y: 40),
                to: CGPoint(x: 130, y: 100),
                through: interactionView,
                in: window
            )
            #expect(model.annotations.count == previousCount + 1)
            #expect(model.annotations.last?.kind == .mosaic)
            #expect(model.annotations.last?.obscureShape == shape)
        }
    }

    @Test
    func annotationHistorySupportsUndoAndRedo() {
        let model = ScreenshotEditorModel(image: NSImage(size: CGSize(width: 320, height: 200)))
        model.add(ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 10, y: 12, width: 80, height: 40)))
        #expect(model.annotations.count == 1)
        #expect(model.canUndo)

        model.undo()
        #expect(model.annotations.isEmpty)
        #expect(model.canRedo)

        model.redo()
        #expect(model.annotations.count == 1)
    }

    @Test
    func cropClampsToDisplayBounds() throws {
        let bytes = Data(repeating: 0xff, count: 16)
        let provider = CGDataProvider(data: bytes as CFData)!
        let image = CGImage(
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let cropped = try #require(
            ScreenshotCaptureService.image(
                from: image,
                cropInScreenPoints: CGRect(x: -10, y: -10, width: 40, height: 40),
                screenSize: CGSize(width: 20, height: 20)
            )
        )
        #expect(cropped.size == CGSize(width: 20, height: 20))
    }

    @Test
    func fullScreenCropPreservesLogicalSizeAndAllBackingPixels() throws {
        let source = try #require(makeGradientImage(width: 400, height: 200))
        let cgImage = try #require(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let cropped = try #require(ScreenshotCaptureService.image(
            from: cgImage,
            cropInScreenPoints: CGRect(x: 0, y: 0, width: 200, height: 100),
            screenSize: CGSize(width: 200, height: 100)
        ))
        let croppedCGImage = try #require(
            cropped.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )

        #expect(cropped.size == CGSize(width: 200, height: 100))
        #expect(croppedCGImage.width == 400)
        #expect(croppedCGImage.height == 200)
    }

    @Test
    func editorWindowRoutesEnterToCopyAndEscapeToCancel() throws {
        let window = ScreenshotEditorWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        var confirmCount = 0
        var cancelCount = 0
        window.onConfirm = { confirmCount += 1 }
        window.onCancelEditing = { cancelCount += 1 }

        let enter = try #require(keyEvent(keyCode: UInt16(kVK_Return), characters: "\r"))
        let escape = try #require(keyEvent(keyCode: UInt16(kVK_Escape), characters: "\u{1b}"))

        #expect(window.performKeyEquivalent(with: enter))
        #expect(confirmCount == 1)
        #expect(cancelCount == 0)

        #expect(window.performKeyEquivalent(with: escape))
        #expect(confirmCount == 1)
        #expect(cancelCount == 1)
    }

    @Test
    func editorWindowRoutesCommandZToUndoAndCommandShiftZToRedo() throws {
        let window = ScreenshotEditorWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        var undoCount = 0
        var redoCount = 0
        window.onUndo = { undoCount += 1 }
        window.onRedo = { redoCount += 1 }

        let undo = try #require(keyEvent(
            keyCode: UInt16(kVK_ANSI_Z),
            characters: "z",
            modifiers: [.command]
        ))
        let redo = try #require(keyEvent(
            keyCode: UInt16(kVK_ANSI_Z),
            characters: "Z",
            modifiers: [.command, .shift]
        ))

        #expect(window.performKeyEquivalent(with: undo))
        #expect(undoCount == 1)
        #expect(redoCount == 0)

        #expect(window.performKeyEquivalent(with: redo))
        #expect(undoCount == 1)
        #expect(redoCount == 1)
    }

    @Test
    func editorWindowRoutesBackspaceAndDeleteToRemoveAnnotation() throws {
        let window = ScreenshotEditorWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        var deleteCount = 0
        window.onDelete = {
            deleteCount += 1
            return true
        }

        let backspace = try #require(keyEvent(keyCode: UInt16(kVK_Delete), characters: "\u{7f}"))
        let forwardDelete = try #require(keyEvent(keyCode: UInt16(kVK_ForwardDelete), characters: "\u{f728}"))

        #expect(window.performKeyEquivalent(with: backspace))
        #expect(deleteCount == 1)

        #expect(window.performKeyEquivalent(with: forwardDelete))
        #expect(deleteCount == 2)
    }

    @Test
    func editorWindowLeavesDeleteUnconsumedWithoutDeleteHandler() throws {
        let window = ScreenshotEditorWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        let backspace = try #require(keyEvent(keyCode: UInt16(kVK_Delete), characters: "\u{7f}"))
        let forwardDelete = try #require(keyEvent(keyCode: UInt16(kVK_ForwardDelete), characters: "\u{f728}"))

        #expect(!window.performKeyEquivalent(with: backspace))
        #expect(!window.performKeyEquivalent(with: forwardDelete))

        window.onDelete = { false }
        #expect(!window.performKeyEquivalent(with: backspace))
        #expect(!window.performKeyEquivalent(with: forwardDelete))
    }

    @Test
    func selectedAnnotationCanBeDeletedAndUndone() {
        let model = ScreenshotEditorModel(image: NSImage(size: CGSize(width: 320, height: 200)))
        let annotationID = UUID()
        model.add(ScreenshotAnnotation(
            id: annotationID,
            kind: .rectangle,
            rect: CGRect(x: 20, y: 20, width: 80, height: 60)
        ))
        let selectionState = ScreenshotAnnotationSelectionState()
        selectionState.selectedAnnotationID = annotationID
        #expect(model.annotations.count == 1)

        #expect(selectionState.deleteSelectedAnnotation(from: model))
        #expect(model.annotations.isEmpty)
        #expect(model.canUndo)
        #expect(selectionState.selectedAnnotationID == nil)

        model.undo()
        #expect(model.annotations.count == 1)
        #expect(model.annotations.first?.id == annotationID)
    }

    @Test
    func startingAnotherAnnotationDeselectsTheCurrentAnnotation() async throws {
        let size = CGSize(width: 400, height: 300)
        let selection = CGRect(x: 60, y: 50, width: 220, height: 140)
        let image = try #require(makeGradientImage(width: 400, height: 300))
        let model = ScreenshotEditorModel(image: NSImage(size: selection.size))
        let selectedArrow = ScreenshotAnnotation(
            kind: .arrow,
            points: [CGPoint(x: 170, y: 110), CGPoint(x: 200, y: 110)]
        )
        model.add(selectedArrow)
        let selectionState = ScreenshotAnnotationSelectionState()
        selectionState.selectedAnnotationID = selectedArrow.id
        model.tool = .rectangle

        let hostingView = NSHostingView(rootView:
            ScreenshotEditorView(
                model: model,
                selectionState: selectionState,
                overlayConfiguration: ScreenshotEditorOverlayConfiguration(
                    backgroundImage: image,
                    initialSelection: selection,
                    cropImage: { _ in image }
                ),
                onClose: {},
                onCopy: {},
                onPinToggle: { _ in },
                onLongCapture: {}
            )
            .frame(width: size.width, height: size.height)
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.contentView = hostingView
        for _ in 0..<3 {
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        let interactionView = try #require(
            findSubview(ScreenshotPointerInteractionNSView.self, in: hostingView)
        )

        try sendMouseDrag(
            from: CGPoint(x: 30, y: 30),
            to: CGPoint(x: 120, y: 90),
            through: interactionView,
            in: window
        )

        #expect(selectionState.selectedAnnotationID == nil)
        #expect(model.annotations.last?.kind == .rectangle)
    }

    @Test
    func selectedShapesAndTextApplyStyleChangesImmediately() {
        let model = ScreenshotEditorModel(image: NSImage(size: CGSize(width: 320, height: 200)))
        let rectangle = ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 10, y: 10, width: 40, height: 40))
        let ellipse = ScreenshotAnnotation(kind: .ellipse, rect: CGRect(x: 60, y: 10, width: 40, height: 40))
        let text = ScreenshotAnnotation(kind: .text, points: [CGPoint(x: 20, y: 80)], text: "文字")
        let emoji = ScreenshotAnnotation(kind: .emoji, points: [CGPoint(x: 80, y: 80)], text: "⭐️")
        [rectangle, ellipse, text, emoji].forEach { model.add($0) }

        model.applySelectedStyle(to: rectangle.id, lineWidth: 8)
        model.applySelectedStyle(to: ellipse.id, lineWidth: 6)
        model.applySelectedStyle(to: text.id, fontSize: 32)
        model.applySelectedStyle(to: emoji.id, fontSize: 40)

        #expect(model.annotations.first(where: { $0.id == rectangle.id })?.lineWidth == 8)
        #expect(model.annotations.first(where: { $0.id == ellipse.id })?.lineWidth == 6)
        #expect(model.annotations.first(where: { $0.id == text.id })?.fontSize == 32)
        #expect(model.annotations.first(where: { $0.id == emoji.id })?.fontSize == 40)
    }

    @Test
    func selectedTextAppliesColorAndFontSizeImmediately() {
        let model = ScreenshotEditorModel(image: NSImage(size: CGSize(width: 320, height: 200)))
        let text = ScreenshotAnnotation(
            kind: .text,
            points: [CGPoint(x: 20, y: 80)],
            text: "文字",
            color: .black
        )
        model.add(text)

        model.applySelectedStyle(to: text.id, color: .white, fontSize: 32)

        let updated = model.annotations.first(where: { $0.id == text.id })
        #expect(updated?.color == .white)
        #expect(updated?.fontSize == 32)
    }

    @Test
    func inlineTextLayoutExpandsUntilScreenshotRightEdge() {
        let availableWidth = ScreenshotInlineTextLayout.width(from: 90, to: 320)
        let initialWidth = ScreenshotInlineTextLayout.width(
            for: "",
            fontSize: 14,
            from: 90,
            to: 320
        )
        let expandedWidth = ScreenshotInlineTextLayout.width(
            for: "输入文字输入文字",
            fontSize: 14,
            from: 90,
            to: 320
        )
        let fullWidth = ScreenshotInlineTextLayout.width(
            for: String(repeating: "输入文字", count: 10),
            fontSize: 14,
            from: 90,
            to: 320
        )
        let singleLineHeight = ScreenshotInlineTextLayout.contentHeight(
            for: "输入文字",
            fontSize: 14,
            width: initialWidth
        )
        let wrappedHeight = ScreenshotInlineTextLayout.contentHeight(
            for: String(repeating: "输入文字", count: 10),
            fontSize: 14,
            width: fullWidth
        )
        let enteredNewlineHeight = ScreenshotInlineTextLayout.contentHeight(
            for: "输入文字\n输入文字",
            fontSize: 14,
            width: initialWidth
        )

        #expect(initialWidth < availableWidth)
        #expect(expandedWidth > initialWidth)
        #expect(expandedWidth < availableWidth)
        #expect(fullWidth == availableWidth)
        #expect(wrappedHeight > singleLineHeight)
        #expect(enteredNewlineHeight > singleLineHeight)
    }

    @Test
    func selectedAnnotationIsNotDeletedWhileInlineTextIsEditing() {
        let model = ScreenshotEditorModel(image: NSImage(size: CGSize(width: 320, height: 200)))
        let annotationID = UUID()
        model.add(ScreenshotAnnotation(
            id: annotationID,
            kind: .text,
            points: [CGPoint(x: 40, y: 40)],
            text: "待编辑"
        ))
        let selectionState = ScreenshotAnnotationSelectionState()
        selectionState.selectedAnnotationID = annotationID
        selectionState.isInlineTextEditing = true

        #expect(!selectionState.deleteSelectedAnnotation(from: model))
        #expect(model.annotations.map(\.id) == [annotationID])

        selectionState.isInlineTextEditing = false
        #expect(selectionState.deleteSelectedAnnotation(from: model))
        #expect(model.annotations.isEmpty)
    }

    @Test
    func editorControllerStartsAsBorderlessScreenOverlay() throws {
        let image = try #require(makeGradientImage(width: 320, height: 200))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let controller = ScreenshotEditorWindowController(
            image: image,
            screenImage: image,
            screenCGImage: cgImage,
            screen: nil,
            captureRect: CGRect(x: 20, y: 20, width: 160, height: 100),
            capturedApplication: nil,
            onClose: {}
        )
        let window = try #require(controller.window)
        window.alphaValue = 0

        #expect(window.styleMask.contains(.borderless))
        #expect(!window.styleMask.contains(.titled))
        #expect(window.level == .screenSaver)
        #expect(window.frame.size == image.size)
        #expect(window.contentView?.acceptsFirstMouse(for: nil) == true)
    }

    @Test
    func selectionControllerCreatesOneOverlayPerScreenAndTearsThemDownTogether() async throws {
        let screen = try #require(NSScreen.screens.first)
        let image = try #require(makeGradientImage(width: 32, height: 20))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var cancellationCount = 0
        var presentedPanels: [ScreenshotSelectionPanel] = []
        let controller = ScreenshotSelectionController(
            captureScreen: { _ in (image, cgImage) },
            presentPanels: { presentedPanels = $0 }
        )
        controller.onCancelled = { cancellationCount += 1 }

        await controller.start(on: [screen, screen])
        #expect(controller.selectionWindowCount == 2)
        #expect(presentedPanels.count == 2)
        #expect(presentedPanels.allSatisfy { $0.screen === screen })
        #expect(presentedPanels.allSatisfy { $0.frame == screen.frame })

        controller.cancel()
        #expect(controller.selectionWindowCount == 0)
        #expect(cancellationCount == 1)

        controller.cancel()
        #expect(cancellationCount == 1)
    }

    @Test
    func selectionControllerPreparesPresentationBeforeShowingPanels() async throws {
        let screen = try #require(NSScreen.screens.first)
        let image = try #require(makeGradientImage(width: 32, height: 20))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var events: [String] = []
        let controller = ScreenshotSelectionController(
            captureScreen: { _ in (image, cgImage) },
            presentPanels: { _ in events.append("present") }
        )
        controller.onSelectionWillPresent = { events.append("prepare") }

        await controller.start(on: screen)

        #expect(events == ["prepare", "present"])
        controller.cancel()
    }

    @Test
    func selectionControllerCancelsWhilePreparingWithoutPresentingPanels() async throws {
        let screen = try #require(NSScreen.screens.first)
        let image = try #require(makeGradientImage(width: 32, height: 20))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var cancellationCount = 0
        var presentedPanels: [ScreenshotSelectionPanel] = []
        var controller: ScreenshotSelectionController!
        controller = ScreenshotSelectionController(
            captureScreen: { _ in (image, cgImage) },
            presentPanels: { presentedPanels = $0 }
        )
        controller.onCancelled = { cancellationCount += 1 }
        controller.onSelectionWillPresent = { controller.cancel() }

        await controller.start(on: screen)

        #expect(presentedPanels.isEmpty)
        #expect(controller.selectionWindowCount == 0)
        #expect(cancellationCount == 1)
    }

    @Test
    func completingSelectionOnOneScreenClosesEveryOverlayAndReturnsThatScreen() async throws {
        let availableScreens = NSScreen.screens
        let firstScreen = try #require(availableScreens.first)
        let requestedScreens = availableScreens.count > 1
            ? Array(availableScreens.prefix(2))
            : [firstScreen, firstScreen]
        let image = try #require(makeGradientImage(width: 64, height: 40))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var presentedPanels: [ScreenshotSelectionPanel] = []
        var result: ScreenshotCaptureResult?
        let controller = ScreenshotSelectionController(
            captureScreen: { _ in (image, cgImage) },
            presentPanels: { presentedPanels = $0 }
        )
        controller.onCaptured = { result = $0 }

        await controller.start(on: requestedScreens)
        let selectedIndex = requestedScreens.count - 1
        let hostingView = try #require(
            presentedPanels[selectedIndex].contentView as? NSHostingView<ScreenshotSelectionView>
        )
        let selection = CGRect(x: 4, y: 3, width: 16, height: 10)
        hostingView.rootView.onSelection(selection)

        #expect(controller.selectionWindowCount == 0)
        #expect(result?.selectionRect == selection)
        #expect(result?.screen === requestedScreens[selectedIndex])
    }

    @Test
    func dragSelectionIgnoresWindowSnapTargetAndUsesActualDragBounds() async throws {
        let screen = try #require(NSScreen.screens.first)
        let image = try #require(makeGradientImage(width: 800, height: 600))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        let windowRect = CGRect(x: 100, y: 100, width: 400, height: 300)
        let snapTargets: ScreenshotSelectionController.SnapTargets = { _ in [windowRect] }

        var presentedPanels: [ScreenshotSelectionPanel] = []
        var result: ScreenshotCaptureResult?
        let controller = ScreenshotSelectionController(
            captureScreen: { _ in (image, cgImage) },
            presentPanels: { presentedPanels = $0 },
            snapTargets: snapTargets
        )
        controller.onCaptured = { result = $0 }

        await controller.start(on: screen)
        let hostingView = try #require(
            presentedPanels.first?.contentView as? NSHostingView<ScreenshotSelectionView>
        )

        let dragSelection = CGRect(x: 150, y: 150, width: 100, height: 80)
        hostingView.rootView.onSelection(dragSelection)

        #expect(result?.selectionRect == dragSelection)
        #expect(result?.selectionRect != windowRect)
    }

    @Test
    func completedSelectionReturnsTheClampedScreenRect() async throws {
        let screen = try #require(NSScreen.screens.first)
        let image = try #require(makeGradientImage(width: 800, height: 600))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var presentedPanels: [ScreenshotSelectionPanel] = []
        var result: ScreenshotCaptureResult?
        let controller = ScreenshotSelectionController(
            captureScreen: { _ in (image, cgImage) },
            presentPanels: { presentedPanels = $0 }
        )
        controller.onCaptured = { result = $0 }

        await controller.start(on: screen)
        let hostingView = try #require(
            presentedPanels.first?.contentView as? NSHostingView<ScreenshotSelectionView>
        )
        let requested = CGRect(x: -40, y: -20, width: 180, height: 160)
        hostingView.rootView.onSelection(requested)

        #expect(result?.selectionRect == CGRect(x: 0, y: 0, width: 140, height: 140))
    }

    @Test
    func hoverRequeriesWindowCandidatesEachTime() async throws {
        let screen = try #require(NSScreen.screens.first)
        let image = try #require(makeGradientImage(width: 800, height: 600))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        var snapTargetCallCount = 0
        let snapTargets: ScreenshotSelectionController.SnapTargets = { _ in
            snapTargetCallCount += 1
            return [CGRect(x: 100, y: 100, width: 200, height: 150)]
        }

        var presentedPanels: [ScreenshotSelectionPanel] = []
        let controller = ScreenshotSelectionController(
            captureScreen: { _ in (image, cgImage) },
            presentPanels: { presentedPanels = $0 },
            snapTargets: snapTargets
        )

        await controller.start(on: screen)
        let hostingView = try #require(
            presentedPanels.first?.contentView as? NSHostingView<ScreenshotSelectionView>
        )

        let initialCallCount = snapTargetCallCount
        let point1 = CGPoint(x: 150, y: 125)
        let target1 = hostingView.rootView.snapTarget(point1)
        #expect(target1 != nil)

        let point2 = CGPoint(x: 160, y: 130)
        let target2 = hostingView.rootView.snapTarget(point2)
        #expect(target2 != nil)

        #expect(snapTargetCallCount > initialCallCount)
    }

    @Test
    func editorEscapeClosesBorderlessWindowAndNotifiesOnce() throws {
        let image = try #require(makeGradientImage(width: 320, height: 200))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var closeCount = 0
        let controller = ScreenshotEditorWindowController(
            image: image,
            screenImage: image,
            screenCGImage: cgImage,
            screen: nil,
            captureRect: CGRect(x: 20, y: 20, width: 160, height: 100),
            capturedApplication: nil,
            onClose: { closeCount += 1 }
        )
        let window = try #require(controller.window as? ScreenshotEditorWindow)
        window.alphaValue = 0
        let escape = try #require(keyEvent(keyCode: UInt16(kVK_Escape), characters: "\u{1b}"))

        #expect(window.performKeyEquivalent(with: escape))
        #expect(closeCount == 1)

        controller.close()
        #expect(closeCount == 1)
    }

    @Test
    func editorPerformCloseClosesBorderlessWindowAndNotifiesOnce() throws {
        let image = try #require(makeGradientImage(width: 320, height: 200))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var closeCount = 0
        let controller = ScreenshotEditorWindowController(
            image: image,
            screenImage: image,
            screenCGImage: cgImage,
            screen: nil,
            captureRect: CGRect(x: 20, y: 20, width: 160, height: 100),
            capturedApplication: nil,
            onClose: { closeCount += 1 }
        )
        let window = try #require(controller.window)
        window.alphaValue = 0

        window.performClose(nil)

        #expect(closeCount == 1)
        controller.close()
        #expect(closeCount == 1)
    }

    @Test
    func editorEnterCopiesThenClosesThroughTheSameCompletionPath() throws {
        let image = try #require(makeGradientImage(width: 320, height: 200))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var writeCount = 0
        var closeCount = 0
        let controller = ScreenshotEditorWindowController(
            image: image,
            screenImage: image,
            screenCGImage: cgImage,
            screen: nil,
            captureRect: CGRect(x: 20, y: 20, width: 160, height: 100),
            capturedApplication: nil,
            writeImageToPasteboard: { _ in
                writeCount += 1
                return true
            },
            onClose: { closeCount += 1 }
        )
        let window = try #require(controller.window as? ScreenshotEditorWindow)
        window.alphaValue = 0
        let enter = try #require(keyEvent(keyCode: UInt16(kVK_Return), characters: "\r"))

        #expect(window.performKeyEquivalent(with: enter))
        #expect(writeCount == 1)
        #expect(closeCount == 1)
    }

    @Test
    func pinPresentationPlacesACompactToolbarBelowTheImage() throws {
        let image = try #require(makeGradientImage(width: 320, height: 200))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let controller = ScreenshotEditorWindowController(
            image: image,
            screenImage: image,
            screenCGImage: cgImage,
            screen: nil,
            captureRect: CGRect(x: 20, y: 20, width: 160, height: 100),
            capturedApplication: nil,
            onClose: {}
        )

        controller.setPinned(true)

        let window = try #require(controller.window)
        window.alphaValue = 0
        #expect(window.styleMask.contains(.borderless))
        #expect(!window.styleMask.contains(.titled))
        #expect(window.contentView?.frame.size == CGSize(
            width: image.size.width,
            height: image.size.height + ScreenshotPinnedLayout.footerHeight
        ))
        #expect(ScreenshotPinnedLayout.toolbarHeight == 30)
        #expect(ScreenshotPinnedLayout.contentWidth < 340)
        #expect(window.level == .screenSaver)
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(window.isMovableByWindowBackground)
        #expect(!window.hasShadow)
    }

    @Test
    func pinPresentationKeepsTheFullToolbarForSmallImages() throws {
        let image = try #require(makeGradientImage(width: 120, height: 80))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let controller = ScreenshotEditorWindowController(
            image: image,
            screenImage: image,
            screenCGImage: cgImage,
            screen: nil,
            captureRect: CGRect(x: 20, y: 20, width: 80, height: 60),
            capturedApplication: nil,
            onClose: {}
        )

        controller.setPinned(true)

        let window = try #require(controller.window)
        window.alphaValue = 0
        #expect(window.frame.width == ScreenshotPinnedLayout.contentWidth)
        #expect(ScreenshotPinnedLayout.windowWidth(
            forImageWidth: image.size.width,
            toolbarVisible: true
        ) == ScreenshotPinnedLayout.contentWidth)
    }

    @Test
    func pinnedPresentationCanHideToolbarWithoutLeavingFooterSpace() throws {
        let image = try #require(makeGradientImage(width: 320, height: 200))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let controller = ScreenshotEditorWindowController(
            image: image,
            screenImage: image,
            screenCGImage: cgImage,
            screen: nil,
            captureRect: CGRect(x: 20, y: 20, width: 160, height: 100),
            capturedApplication: nil,
            onClose: {},
            pinnedToolbarVisible: false
        )

        controller.setPinned(true)

        let window = try #require(controller.window)
        window.alphaValue = 0
        #expect(ScreenshotPinnedLayout.footerHeight(toolbarVisible: false) == 0)
        #expect(window.contentView?.frame.size == image.size)
    }

    @Test
    func pinnedPresentationUsesThePointerViewForMovement() throws {
        let image = try #require(makeGradientImage(width: 320, height: 200))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let controller = ScreenshotEditorWindowController(
            image: image,
            screenImage: image,
            screenCGImage: cgImage,
            screen: nil,
            captureRect: CGRect(x: 20, y: 20, width: 160, height: 100),
            capturedApplication: nil,
            onClose: {}
        )

        controller.setPinned(true)

        let window = try #require(controller.window)
        window.alphaValue = 0
        #expect(window.isMovableByWindowBackground)
        let pointer = try #require(findSubview(ScreenshotPointerInteractionNSView.self, in: window.contentView!))
        #expect(!pointer.mouseDownCanMoveWindow)
    }

    @Test
    func pinnedResizeUsesEachCornerAndPreservesAspectRatio() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 200)
        #expect(ScreenshotPinnedInteraction.resizeCorner(at: CGPoint(x: 4, y: 4), in: bounds) == .topLeft)
        #expect(ScreenshotPinnedInteraction.resizeCorner(at: CGPoint(x: 316, y: 4), in: bounds) == .topRight)
        #expect(ScreenshotPinnedInteraction.resizeCorner(at: CGPoint(x: 316, y: 196), in: bounds) == .bottomRight)
        #expect(ScreenshotPinnedInteraction.resizeCorner(at: CGPoint(x: 4, y: 196), in: bounds) == .bottomLeft)
        #expect(ScreenshotPinnedInteraction.resizeCorner(at: CGPoint(x: 160, y: 100), in: bounds) == nil)

        let expanded = ScreenshotPinnedInteraction.resizeScale(
            baseScale: 1,
            corner: .topLeft,
            translation: CGSize(width: -32, height: -20),
            imageSize: CGSize(width: 320, height: 200),
            range: 0.2...3
        )
        let narrowed = ScreenshotPinnedInteraction.resizeScale(
            baseScale: 1,
            corner: .bottomRight,
            translation: CGSize(width: -32, height: -20),
            imageSize: CGSize(width: 320, height: 200),
            range: 0.2...3
        )
        #expect(expanded == 1.1)
        #expect(narrowed == 0.9)
    }

    @Test
    func pinnedCornerDragRoutesToResizeInsteadOfMove() throws {
        var resizeEvents: [(ScreenshotPinnedResizeCorner, CGPoint, CGPoint, Bool)] = []
        var moveEvents: [(CGPoint, CGPoint, Bool)] = []
        let view = ScreenshotPointerInteractionNSView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        view.onResize = { resizeEvents.append(($0, $1, $2, $3)) }
        view.onDrag = { moveEvents.append(($0, $1, $2)) }
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.contentView = view

        try sendMouseDrag(
            from: CGPoint(x: 4, y: 4),
            to: CGPoint(x: 24, y: 14),
            through: view,
            in: window
        )

        #expect(resizeEvents.first?.0 == .topLeft)
        #expect(resizeEvents.last?.1 == CGPoint(x: 4, y: 4))
        #expect(resizeEvents.last?.2 == CGPoint(x: 24, y: 14))
        #expect(resizeEvents.last?.3 == true)
        #expect(moveEvents.isEmpty)
    }

    @Test
    func pinnedDragUsesStableScreenCoordinates() throws {
        var dragEvents: [(CGPoint, CGPoint, Bool)] = []
        let view = ScreenshotPointerInteractionNSView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        view.usesScreenCoordinatesForDrag = true
        view.onDrag = { dragEvents.append(($0, $1, $2)) }
        let start = CGPoint(x: 420, y: 260)
        let end = CGPoint(x: 468, y: 294)

        view.mouseDown(with: try #require(screenMouseEvent(type: .leftMouseDown, location: start)))
        view.mouseDragged(with: try #require(screenMouseEvent(type: .leftMouseDragged, location: end)))
        view.mouseUp(with: try #require(screenMouseEvent(type: .leftMouseUp, location: end)))

        #expect(dragEvents.last?.0 == start)
        #expect(dragEvents.last?.1 == end)
        #expect(dragEvents.last?.2 == true)
    }

    @Test
    func pinnedImageSupportsScaleOpacityAndExplicitMovement() throws {
        let image = try #require(makeGradientImage(width: 320, height: 200))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let controller = ScreenshotEditorWindowController(
            image: image,
            screenImage: image,
            screenCGImage: cgImage,
            screen: nil,
            captureRect: CGRect(x: 20, y: 20, width: 160, height: 100),
            capturedApplication: nil,
            onClose: {}
        )
        controller.setPinned(true)
        let window = try #require(controller.window)
        window.alphaValue = 0
        let initialImageCenter = pinnedImageCenter(in: window.frame)

        controller.setPinnedScale(1.5)
        #expect(controller.pinnedScale == 1.5)
        #expect(window.frame.size == CGSize(
            width: 480,
            height: 300 + ScreenshotPinnedLayout.footerHeight
        ))
        #expect(pinnedImageCenter(in: window.frame) == initialImageCenter)

        controller.setPinnedOpacity(0.45)
        #expect(controller.pinnedOpacity == 0.45)
        controller.setPinnedOpacity(0.1)
        #expect(controller.pinnedOpacity == 0.2)

        let origin = window.frame.origin
        let translation = CGSize(width: 24, height: 18)
        controller.movePinnedWindow(by: translation, isComplete: false)
        #expect(window.frame.origin == CGPoint(x: origin.x + 24, y: origin.y - 18))
        controller.movePinnedWindow(by: translation, isComplete: true)
        #expect(window.frame.origin == CGPoint(x: origin.x + 24, y: origin.y - 18))
    }

    @Test
    func pinnedImageCanMovePastTheCurrentScreenBoundary() throws {
        let screen = try #require(NSScreen.screens.first)
        let image = try #require(makeGradientImage(width: 320, height: 200))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let controller = ScreenshotEditorWindowController(
            image: image,
            screenImage: image,
            screenCGImage: cgImage,
            screen: screen,
            captureRect: CGRect(x: 20, y: 20, width: 160, height: 100),
            capturedApplication: nil,
            onClose: {}
        )

        controller.setPinned(true)
        let window = try #require(controller.window)
        window.alphaValue = 0
        let origin = window.frame.origin
        let translation = CGSize(width: screen.frame.width + 128, height: 0)

        controller.movePinnedWindow(by: translation, isComplete: true)

        #expect(window.frame.origin == CGPoint(x: origin.x + translation.width, y: origin.y))
    }

    @Test
    func pinnedTrackpadGesturesUpdateScaleOpacityAndMovement() async throws {
        let image = try #require(makeGradientImage(width: 320, height: 200))
        var scales: [CGFloat] = []
        var opacities: [CGFloat] = []
        var movements: [(CGSize, Bool)] = []
        let size = CGSize(
            width: image.size.width,
            height: image.size.height + ScreenshotPinnedLayout.footerHeight
        )
        let hostingView = NSHostingView(rootView:
            ScreenshotPinnedImageView(
                image: image,
                initialScale: 1,
                scaleRange: 0.2...3,
                initialOpacity: 0.5,
                onScaleChange: { scales.append($0) },
                onOpacityChange: { opacities.append($0) },
                onMove: { movements.append(($0, $1)) },
                onClose: {},
                toolbarVisible: true
            )
            .frame(width: size.width, height: size.height)
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.contentView = hostingView
        for _ in 0..<3 {
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        let interactionView = try #require(
            findSubview(ScreenshotPointerInteractionNSView.self, in: hostingView)
        )

        interactionView.handleMagnification(0.25)
        #expect(scales.last == 1.25)

        interactionView.handleScroll(deltaY: 10, directionInverted: false, precise: true)
        #expect(opacities.last == 0.56)
        hostingView.layoutSubtreeIfNeeded()
        await Task.yield()
        interactionView.handleScroll(deltaY: 10, directionInverted: true, precise: true)
        #expect(opacities.last == 0.5)

        try sendMouseDrag(
            from: CGPoint(x: 40, y: 30),
            to: CGPoint(x: 72, y: 54),
            through: interactionView,
            in: window
        )
        #expect(movements.last?.0 == CGSize(width: 32, height: 24))
        #expect(movements.last?.1 == true)
    }

    @Test
    func pinnedWindowRoutesEscapeToClose() throws {
        let image = try #require(makeGradientImage(width: 320, height: 200))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var closeCount = 0
        let controller = ScreenshotEditorWindowController(
            image: image,
            screenImage: image,
            screenCGImage: cgImage,
            screen: nil,
            captureRect: CGRect(x: 20, y: 20, width: 160, height: 100),
            capturedApplication: nil,
            onClose: { closeCount += 1 }
        )
        controller.setPinned(true)
        let window = try #require(controller.window as? ScreenshotEditorWindow)
        window.alphaValue = 0
        let escape = try #require(keyEvent(keyCode: UInt16(kVK_Escape), characters: "\u{1b}"))

        #expect(window.performKeyEquivalent(with: escape))
        #expect(closeCount == 1)
    }

    @Test
    func plainTextRespectsReadingOrder() {
        let fragments = [
            ScreenshotRecognizedFragment(text: "右上", boundingBox: CGRect(x: 100, y: 100, width: 30, height: 10)),
            ScreenshotRecognizedFragment(text: "左上", boundingBox: CGRect(x: 10, y: 100, width: 30, height: 10)),
            ScreenshotRecognizedFragment(text: "右下", boundingBox: CGRect(x: 100, y: 50, width: 30, height: 10)),
            ScreenshotRecognizedFragment(text: "左下", boundingBox: CGRect(x: 10, y: 50, width: 30, height: 10)),
        ]
        let result = ScreenshotRecognitionFormatter.plainText(from: fragments)
        #expect(result == "左上\n右上\n左下\n右下")
    }

    @Test
    func plainTextMergesSameLineFragmentsByTolerance() {
        let fragments = [
            ScreenshotRecognizedFragment(text: "文字A", boundingBox: CGRect(x: 10, y: 100, width: 30, height: 10)),
            ScreenshotRecognizedFragment(text: "文字B", boundingBox: CGRect(x: 50, y: 101, width: 30, height: 10)),
            ScreenshotRecognizedFragment(text: "下一行", boundingBox: CGRect(x: 10, y: 80, width: 40, height: 10)),
        ]
        let result = ScreenshotRecognitionFormatter.plainText(from: fragments)
        #expect(result == "文字A\n文字B\n下一行")
    }

    @Test
    func tableTextArrangesFragmentsIntoTSVRows() {
        let fragments = [
            ScreenshotRecognizedFragment(text: "A1", boundingBox: CGRect(x: 10, y: 100, width: 20, height: 10)),
            ScreenshotRecognizedFragment(text: "B1", boundingBox: CGRect(x: 50, y: 100, width: 20, height: 10)),
            ScreenshotRecognizedFragment(text: "A2", boundingBox: CGRect(x: 10, y: 80, width: 20, height: 10)),
            ScreenshotRecognizedFragment(text: "B2", boundingBox: CGRect(x: 50, y: 80, width: 20, height: 10)),
        ]
        let result = ScreenshotRecognitionFormatter.tableText(from: fragments)
        #expect(result == "A1\tB1\nA2\tB2")
    }

    @Test
    func tableTextGroupsFragmentsByVerticalTolerance() {
        let fragments = [
            ScreenshotRecognizedFragment(text: "标题1", boundingBox: CGRect(x: 10, y: 100, width: 30, height: 12)),
            ScreenshotRecognizedFragment(text: "标题2", boundingBox: CGRect(x: 60, y: 102, width: 30, height: 12)),
            ScreenshotRecognizedFragment(text: "行1列1", boundingBox: CGRect(x: 10, y: 70, width: 30, height: 10)),
            ScreenshotRecognizedFragment(text: "行1列2", boundingBox: CGRect(x: 60, y: 68, width: 30, height: 10)),
        ]
        let result = ScreenshotRecognitionFormatter.tableText(from: fragments)
        let lines = result.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("\t"))
        #expect(lines[1].contains("\t"))
    }

    @Test
    func tableRecognitionHandlesNoTextFragments() {
        #expect(ScreenshotRecognitionFormatter.table(from: []).isEmpty)
    }

    @Test
    func tableTextKeepsColumnsForMergedCells() {
        let fragments = [
            ScreenshotRecognizedFragment(text: "总计", boundingBox: CGRect(x: 10, y: 100, width: 80, height: 10)),
            ScreenshotRecognizedFragment(text: "A", boundingBox: CGRect(x: 10, y: 80, width: 20, height: 10)),
            ScreenshotRecognizedFragment(text: "B", boundingBox: CGRect(x: 50, y: 80, width: 20, height: 10)),
            ScreenshotRecognizedFragment(text: "C", boundingBox: CGRect(x: 90, y: 80, width: 20, height: 10)),
        ]
        let table = ScreenshotRecognitionFormatter.table(from: fragments)
        #expect(table.rows.map { $0.joined(separator: "\t") }.joined(separator: "\n") == "总计\t\t\nA\tB\tC")
        #expect(table.merges.contains(ScreenshotRecognizedTable.Merge(
            row: 0,
            column: 0,
            rowSpan: 1,
            columnSpan: 3
        )))
    }

    @Test
    func tableTextMergesVerticalLabelFragments() {
        let fragments = [
            ScreenshotRecognizedFragment(text: "责", boundingBox: CGRect(x: 10, y: 100, width: 10, height: 10)),
            ScreenshotRecognizedFragment(text: "项目一", boundingBox: CGRect(x: 50, y: 100, width: 30, height: 10)),
            ScreenshotRecognizedFragment(text: "任", boundingBox: CGRect(x: 10, y: 80, width: 10, height: 10)),
            ScreenshotRecognizedFragment(text: "项目二", boundingBox: CGRect(x: 50, y: 80, width: 30, height: 10)),
            ScreenshotRecognizedFragment(text: "心", boundingBox: CGRect(x: 10, y: 60, width: 10, height: 10)),
            ScreenshotRecognizedFragment(text: "项目三", boundingBox: CGRect(x: 50, y: 60, width: 30, height: 10)),
        ]
        let table = ScreenshotRecognitionFormatter.table(from: fragments)
        #expect(table.rows.map { $0.joined(separator: "\t") }.joined(separator: "\n") == "责任心\t项目一\n\t项目二\n\t项目三")
        #expect(table.merges.contains(ScreenshotRecognizedTable.Merge(
            row: 0,
            column: 0,
            rowSpan: 3,
            columnSpan: 1
        )))
    }

    @Test
    func tableImageGridPreservesHorizontalAndVerticalMerges() throws {
        let image = try #require(makeTableGridImage())
        let fragments = [
            ScreenshotRecognizedFragment(
                text: "纵向",
                boundingBox: CGRect(x: 0.12, y: 0.72, width: 0.12, height: 0.1)
            ),
            ScreenshotRecognizedFragment(
                text: "横向",
                boundingBox: CGRect(x: 0.56, y: 0.16, width: 0.18, height: 0.1)
            ),
        ]

        let table = ScreenshotRecognitionFormatter.table(from: fragments, image: image)

        #expect(table.rows.count == 3)
        #expect(table.rows.allSatisfy { $0.count == 3 })
        #expect(table.columnWidths.count == 3)
        #expect(table.rowHeights.count == 3)
        #expect(table.gridRowRange == 0..<3)
        #expect(table.merges.contains(.init(row: 0, column: 0, rowSpan: 2, columnSpan: 1)))
        #expect(table.merges.contains(.init(row: 2, column: 1, rowSpan: 1, columnSpan: 2)))
        #expect(table.verticalCells.contains(.init(row: 0, column: 0)))
        #expect(table.rows[0][0] == "纵向")
        #expect(table.rows[2][1] == "横向")
    }

    @Test
    func tableXLSXContainsEditableCellsAndMergeRanges() throws {
        let output = ProcessInfo.processInfo.environment["ZISLA_XLSX_TEST_OUTPUT"]
            .map(URL.init(fileURLWithPath:))
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("zisla-xlsx-export-test-\(UUID().uuidString).xlsx")
        let shouldCleanUp = ProcessInfo.processInfo.environment["ZISLA_XLSX_TEST_OUTPUT"] == nil
        defer { if shouldCleanUp { try? FileManager.default.removeItem(at: output) } }
        let table = ScreenshotRecognizedTable(
            rows: [["总计", "", ""], ["项目", "13", "通过"]],
            merges: [.init(row: 0, column: 0, rowSpan: 1, columnSpan: 3)],
            columnWidths: [8, 20, 8],
            rowHeights: [36, 24],
            gridRowRange: 1..<2,
            titleRows: [0],
            verticalCells: [.init(row: 1, column: 0)]
        )

        try ScreenshotXLSXExporter.write(table, to: output)

        let data = try Data(contentsOf: output)
        #expect(data.starts(with: [0x50, 0x4B]))
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-p", output.path, "xl/worksheets/sheet1.xml"]
        task.standardOutput = pipe
        try task.run()
        task.waitUntilExit()
        let xml = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(task.terminationStatus == 0)
        #expect(xml.contains("<mergeCell ref=\"A1:C1\"/>"))
        #expect(xml.contains("<col min=\"2\" max=\"2\" width=\"20.0\" customWidth=\"1\"/>"))
        #expect(xml.contains("<row r=\"1\" ht=\"36.0\" customHeight=\"1\">"))
        #expect(xml.contains("<c r=\"A1\" s=\"4\""))
        #expect(xml.contains("<c r=\"A2\" s=\"3\""))
        #expect(xml.contains("<c r=\"B2\" s=\"2\"><v>13</v></c>"))
        #expect(xml.contains("<t xml:space=\"preserve\">通过</t>"))
    }

    @Test
    func referenceTableImageExportsDetectedGrid() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let imagePath = environment["ZISLA_TABLE_TEST_IMAGE"],
              let outputPath = environment["ZISLA_TABLE_TEST_OUTPUT"]
        else { return }
        let image = try #require(NSImage(contentsOfFile: imagePath))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let preferredLanguages = ["zh-Hans", "zh-Hant", "en-US", "en"]
        let supportedLanguages = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = preferredLanguages.filter { supportedLanguages.contains($0) }
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        let fragments = (request.results ?? []).compactMap { observation -> ScreenshotRecognizedFragment? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return ScreenshotRecognizedFragment(text: candidate.string, boundingBox: observation.boundingBox)
        }
        let table = ScreenshotRecognitionFormatter.table(from: fragments, image: cgImage)

        #expect(!table.isEmpty)
        #expect(table.gridRowRange != nil)
        try ScreenshotXLSXExporter.write(table, to: URL(fileURLWithPath: outputPath))
    }

    @Test
    func appendImageIncreasesHeightAndPreservesUndo() {
        let top = NSImage(size: CGSize(width: 100, height: 60))
        let bottom = NSImage(size: CGSize(width: 100, height: 40))
        let model = ScreenshotEditorModel(image: top)
        let originalHeight = model.image.size.height

        model.append(image: bottom)
        #expect(model.image.size.height == originalHeight + bottom.size.height)
        #expect(model.canUndo)

        model.undo()
        #expect(model.image.size.height == originalHeight)
        #expect(model.canRedo)

        model.redo()
        #expect(model.image.size.height == originalHeight + bottom.size.height)
    }

    @Test
    func longCaptureAppendPreservesSourcePixelResolution() throws {
        let topSource = try #require(makeGradientImage(width: 8, height: 8))
        let bottomSource = try #require(makeGradientImage(width: 8, height: 8))
        let topCGImage = try #require(topSource.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bottomCGImage = try #require(bottomSource.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let top = NSImage(cgImage: topCGImage, size: CGSize(width: 4, height: 4))
        let bottom = NSImage(cgImage: bottomCGImage, size: CGSize(width: 4, height: 4))
        let model = ScreenshotEditorModel(image: top)

        model.append(image: bottom)

        let combined = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(model.image.size == CGSize(width: 4, height: 8))
        #expect(combined.width == 8)
        #expect(combined.height == 16)
    }

    @Test
    func longCaptureIgnoresUnchangedFrames() throws {
        let frame = try #require(makeGradientImage(width: 64, height: 64))
        let model = ScreenshotEditorModel(image: frame)

        model.beginLongCapturePreview()
        model.append(image: frame, direction: .vertical)

        #expect(model.image.size == frame.size)
        #expect(!model.canUndo)
    }

    @Test
    func completingLongCaptureKeepsTheCombinedImageVisible() throws {
        let source = try #require(makeGradientImage(width: 64, height: 96))
        let sourceCGImage = try #require(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let firstCGImage = try #require(sourceCGImage.cropping(to: CGRect(x: 0, y: 0, width: 64, height: 64)))
        let secondCGImage = try #require(sourceCGImage.cropping(to: CGRect(x: 0, y: 32, width: 64, height: 64)))
        let first = NSImage(cgImage: firstCGImage, size: CGSize(width: 64, height: 64))
        let second = NSImage(cgImage: secondCGImage, size: CGSize(width: 64, height: 64))
        let model = ScreenshotEditorModel(image: first)

        model.beginLongCapturePreview()
        _ = model.append(image: second, direction: .vertical)
        model.completeLongCapturePreview()

        #expect(!model.isLongCapturePreviewing)
        #expect(model.hasLongCaptureResult)
        #expect(model.image.size.height > first.size.height)
    }

    @Test
    func longCaptureRejectsFramesWithoutReliableOverlap() throws {
        let first = try #require(makeGradientImage(width: 64, height: 64))
        let unrelated = try #require(makeCheckerboardImage(width: 64, height: 64))
        let model = ScreenshotEditorModel(image: first)

        model.beginLongCapturePreview()
        let didAppend = model.append(image: unrelated, direction: .vertical)

        #expect(!didAppend)
        #expect(model.image.size == first.size)
        #expect(!model.canUndo)
    }

    @Test
    func longCaptureRemovesVerticalOverlap() throws {
        let source = try #require(makeGradientImage(width: 64, height: 96))
        let sourceCGImage = try #require(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let firstCGImage = try #require(sourceCGImage.cropping(to: CGRect(x: 0, y: 0, width: 64, height: 64)))
        let secondCGImage = try #require(sourceCGImage.cropping(to: CGRect(x: 0, y: 32, width: 64, height: 64)))
        let first = NSImage(cgImage: firstCGImage, size: CGSize(width: 64, height: 64))
        let second = NSImage(cgImage: secondCGImage, size: CGSize(width: 64, height: 64))
        let model = ScreenshotEditorModel(image: first)

        model.beginLongCapturePreview()
        model.append(image: second, direction: .vertical)

        #expect(abs(model.image.size.height - 96) < 1)
        #expect(model.image.size.width == 64)
    }

    @Test
    func longCaptureRemovesHorizontalOverlap() throws {
        let source = try #require(makeGradientImage(width: 96, height: 64))
        let sourceCGImage = try #require(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let firstCGImage = try #require(sourceCGImage.cropping(to: CGRect(x: 0, y: 0, width: 64, height: 64)))
        let secondCGImage = try #require(sourceCGImage.cropping(to: CGRect(x: 32, y: 0, width: 64, height: 64)))
        let first = NSImage(cgImage: firstCGImage, size: CGSize(width: 64, height: 64))
        let second = NSImage(cgImage: secondCGImage, size: CGSize(width: 64, height: 64))
        let model = ScreenshotEditorModel(image: first)

        model.beginLongCapturePreview()
        model.append(image: second, direction: .horizontal)

        #expect(abs(model.image.size.width - 96) < 1)
        #expect(model.image.size.height == 64)
    }

    @Test
    func longCapturePrependsVerticalOverlap() throws {
        let source = try #require(makeGradientImage(width: 64, height: 96))
        let sourceCGImage = try #require(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let firstCGImage = try #require(sourceCGImage.cropping(to: CGRect(x: 0, y: 32, width: 64, height: 64)))
        let secondCGImage = try #require(sourceCGImage.cropping(to: CGRect(x: 0, y: 0, width: 64, height: 64)))
        let model = ScreenshotEditorModel(image: NSImage(cgImage: firstCGImage, size: CGSize(width: 64, height: 64)))

        model.beginLongCapturePreview()
        model.append(
            image: NSImage(cgImage: secondCGImage, size: CGSize(width: 64, height: 64)),
            direction: .vertical
        )

        let combined = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(rgbaPixels(in: combined) == rgbaPixels(in: sourceCGImage))
    }

    @Test
    func longCapturePrependsHorizontalOverlap() throws {
        let source = try #require(makeGradientImage(width: 96, height: 64))
        let sourceCGImage = try #require(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let firstCGImage = try #require(sourceCGImage.cropping(to: CGRect(x: 32, y: 0, width: 64, height: 64)))
        let secondCGImage = try #require(sourceCGImage.cropping(to: CGRect(x: 0, y: 0, width: 64, height: 64)))
        let model = ScreenshotEditorModel(image: NSImage(cgImage: firstCGImage, size: CGSize(width: 64, height: 64)))

        model.beginLongCapturePreview()
        model.append(
            image: NSImage(cgImage: secondCGImage, size: CGSize(width: 64, height: 64)),
            direction: .horizontal
        )

        let combined = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(rgbaPixels(in: combined) == rgbaPixels(in: sourceCGImage))
    }

    @Test
    func rectanglePixelateOnlyAffectsSelectedRegion() throws {
        let sourceImage = try #require(makeGradientImage(width: 96, height: 96))
        let model = ScreenshotEditorModel(image: sourceImage)
        let selection = CGRect(x: 24, y: 24, width: 48, height: 48)
        model.add(ScreenshotAnnotation(
            kind: .mosaic,
            rect: selection,
            lineWidth: 8
        ))

        let original = try #require(sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let mosaicked = try #require(
            model.imageApplyingMosaics().cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let preview = try #require(
            model.mosaicPreviewImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        #expect(rgbaPixels(in: preview) == rgbaPixels(in: mosaicked))
        let outsidePoints = [
            CGPoint(x: 8, y: 8),
            CGPoint(x: 87, y: 8),
            CGPoint(x: 8, y: 87),
            CGPoint(x: 87, y: 87),
        ]
        for point in outsidePoints {
            let before = try #require(pixelColor(in: original, at: point))
            let after = try #require(pixelColor(in: mosaicked, at: point))
            #expect(colorDistance(before, after) <= 2, "马赛克选区外像素不应变化")
        }
        try expectPixelsOutside(selection, unchangedFrom: original, to: mosaicked)

        let insidePoints = [
            CGPoint(x: 32, y: 32),
            CGPoint(x: 40, y: 40),
            CGPoint(x: 56, y: 56),
            CGPoint(x: 64, y: 64),
        ]
        let changedInside = insidePoints.contains { point in
            guard let before = pixelColor(in: original, at: point),
                  let after = pixelColor(in: mosaicked, at: point)
            else { return false }
            return colorDistance(before, after) > 8
        }
        #expect(changedInside, "马赛克选区内至少应有像素被真实重采样")
    }

    @Test
    func mosaicDraftPreviewMatchesCommittedEffect() throws {
        let sourceImage = try #require(makeCheckerboardImage(width: 96, height: 96))
        for effect in ScreenshotObscureEffect.allCases {
            let annotation = ScreenshotAnnotation(
                kind: .mosaic,
                rect: CGRect(x: 24, y: 24, width: 48, height: 48),
                lineWidth: 8,
                obscureShape: .rectangle,
                obscureEffect: effect
            )
            let model = ScreenshotEditorModel(image: sourceImage)

            let draft = try #require(
                model.imageApplyingMosaics(adding: annotation)
                    .cgImage(forProposedRect: nil, context: nil, hints: nil)
            )
            model.add(annotation)
            let committed = try #require(
                model.mosaicPreviewImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            )

            #expect(rgbaPixels(in: draft) == rgbaPixels(in: committed))
        }
    }

    @Test
    func brushPixelateOnlyAffectsPaintedPath() throws {
        let sourceImage = try #require(makeGradientImage(width: 96, height: 96))
        let model = ScreenshotEditorModel(image: sourceImage)
        let affectedBounds = CGRect(x: 10, y: 38, width: 76, height: 20)
        model.add(ScreenshotAnnotation(
            kind: .mosaic,
            points: [CGPoint(x: 20, y: 48), CGPoint(x: 76, y: 48)],
            lineWidth: 4,
            obscureShape: .brush,
            obscureEffect: .pixelate
        ))

        let original = try #require(sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let mosaicked = try #require(
            model.imageApplyingMosaics().cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        for point in [CGPoint(x: 48, y: 18), CGPoint(x: 8, y: 8)] {
            let before = try #require(pixelColor(in: original, at: point))
            let after = try #require(pixelColor(in: mosaicked, at: point))
            #expect(colorDistance(before, after) <= 2, "画笔路径外像素不应变化")
        }
        try expectPixelsOutside(affectedBounds, unchangedFrom: original, to: mosaicked)

        let changedOnPath = [32, 40, 56, 64].contains { x in
            guard let before = pixelColor(in: original, at: CGPoint(x: x, y: 48)),
                  let after = pixelColor(in: mosaicked, at: CGPoint(x: x, y: 48))
            else { return false }
            return colorDistance(before, after) > 8
        }
        #expect(changedOnPath, "画笔路径上的像素应被马赛克处理")
    }

    @Test
    func rectangleBlurOnlyAffectsSelectedRegion() throws {
        let sourceImage = try #require(makeCheckerboardImage(width: 96, height: 96))
        let model = ScreenshotEditorModel(image: sourceImage)
        let selection = CGRect(x: 24, y: 24, width: 48, height: 48)
        model.add(ScreenshotAnnotation(
            kind: .mosaic,
            rect: selection,
            lineWidth: 8,
            obscureShape: .rectangle,
            obscureEffect: .blur
        ))

        let original = try #require(sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let blurred = try #require(
            model.imageApplyingMosaics().cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let outside = CGPoint(x: 8, y: 8)
        let outsideBefore = try #require(pixelColor(in: original, at: outside))
        let outsideAfter = try #require(pixelColor(in: blurred, at: outside))
        #expect(colorDistance(outsideBefore, outsideAfter) <= 2, "模糊选区外像素不应变化")
        try expectPixelsOutside(selection, unchangedFrom: original, to: blurred)

        let center = CGPoint(x: 48, y: 48)
        let centerBefore = try #require(pixelColor(in: original, at: center))
        let centerAfter = try #require(pixelColor(in: blurred, at: center))
        #expect(colorDistance(centerBefore, centerAfter) > 30, "模糊选区内的高频像素应被平滑")
    }

    @Test
    func brushBlurOnlyAffectsPaintedPath() throws {
        let sourceImage = try #require(makeCheckerboardImage(width: 96, height: 96))
        let model = ScreenshotEditorModel(image: sourceImage)
        let affectedBounds = CGRect(x: 10, y: 38, width: 76, height: 20)
        model.add(ScreenshotAnnotation(
            kind: .mosaic,
            points: [CGPoint(x: 20, y: 48), CGPoint(x: 76, y: 48)],
            lineWidth: 4,
            obscureShape: .brush,
            obscureEffect: .blur
        ))

        let original = try #require(sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let blurred = try #require(
            model.imageApplyingMosaics().cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        try expectPixelsOutside(affectedBounds, unchangedFrom: original, to: blurred)

        let changedOnPath = [32, 40, 48, 56, 64].contains { x in
            guard let before = pixelColor(in: original, at: CGPoint(x: x, y: 48)),
                  let after = pixelColor(in: blurred, at: CGPoint(x: x, y: 48))
            else { return false }
            return colorDistance(before, after) > 30
        }
        #expect(changedOnPath, "画笔路径上的高频像素应被模糊")
    }

    @Test
    func obscureAnnotationsKeepTheirCreationShapeAndEffectAcrossHistory() {
        let model = ScreenshotEditorModel(image: NSImage(size: CGSize(width: 96, height: 96)))
        model.add(ScreenshotAnnotation(
            kind: .mosaic,
            rect: CGRect(x: 8, y: 8, width: 24, height: 24),
            obscureShape: .rectangle,
            obscureEffect: .pixelate
        ))
        model.add(ScreenshotAnnotation(
            kind: .mosaic,
            points: [CGPoint(x: 40, y: 40), CGPoint(x: 72, y: 72)],
            obscureShape: .brush,
            obscureEffect: .blur
        ))

        model.obscureShape = .rectangle
        model.obscureEffect = .pixelate
        model.undo()
        model.redo()

        #expect(model.annotations.map(\.obscureShape) == [.rectangle, .brush])
        #expect(model.annotations.map(\.obscureEffect) == [.pixelate, .blur])
    }

    @Test
    func obscureOptionsContainOnlyRectangleBrushPixelateAndBlur() {
        #expect(ScreenshotObscureShape.allCases.map(\.rawValue) == ["rectangle", "brush"])
        #expect(ScreenshotObscureEffect.allCases.map(\.rawValue) == ["pixelate", "blur"])
        #expect(!ScreenshotTool.allCases.map(\.rawValue).contains { $0.localizedCaseInsensitiveContains("erase") })
    }

    @Test
    func pinnedFocusStateOnlyActivatesAfterClickWhilePointerAndWindowAreFocused() {
        let state = ScreenshotPinnedFocusState()
        #expect(!state.isActive)

        state.isPointerInside = true
        #expect(!state.isActive)

        state.isSelected = true
        #expect(state.isActive)

        state.windowIsKey = false
        #expect(!state.isActive)

        state.windowIsKey = true
        state.isPointerInside = false
        #expect(!state.isActive)
    }

    @Test
    func pinnedPointerInteractionReportsClickAndPointerBoundary() throws {
        var clickCount = 0
        var focusChanges: [Bool] = []
        let view = ScreenshotPointerInteractionNSView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        view.onPointerClick = { clickCount += 1 }
        view.onPointerFocusChange = { focusChanges.append($0) }
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.contentView = view
        view.updateTrackingAreas()
        let event = try #require(mouseEvent(
            type: .leftMouseDown,
            location: CGPoint(x: 80, y: 50),
            window: window,
            eventNumber: 1
        ))

        #expect(!window.isVisible)
        view.mouseEntered(with: event)
        view.mouseDown(with: event)
        view.mouseExited(with: event)

        #expect(!window.isVisible)
        #expect(clickCount == 1)
        #expect(focusChanges == [true, false])
    }

    @Test
    func rectangleAnnotationCanBeEditedByReplacingWithSameID() {
        let model = ScreenshotEditorModel(image: NSImage(size: CGSize(width: 320, height: 200)))
        let originalID = UUID()
        model.add(ScreenshotAnnotation(
            id: originalID,
            kind: .rectangle,
            rect: CGRect(x: 20, y: 20, width: 60, height: 40),
            color: ScreenshotRGBA.accent,
            lineWidth: 4
        ))
        #expect(model.annotations.count == 1)
        #expect(model.annotations.first?.rect.width == 60)

        model.add(ScreenshotAnnotation(
            id: originalID,
            kind: .rectangle,
            rect: CGRect(x: 20, y: 20, width: 80, height: 50),
            color: ScreenshotRGBA.accent,
            lineWidth: 4
        ))
        #expect(model.annotations.count == 1)
        #expect(model.annotations.first?.rect.width == 80)
    }

    @Test
    func textAnnotationSupportsInPlaceEditing() {
        let model = ScreenshotEditorModel(image: NSImage(size: CGSize(width: 320, height: 200)))
        model.tool = .text
        model.add(ScreenshotAnnotation(
            kind: .text,
            points: [CGPoint(x: 50, y: 50)],
            text: "原始文本",
            color: model.color,
            fontSize: 24
        ))
        #expect(model.annotations.count == 1)
        #expect(model.annotations.first?.text == "原始文本")

        if let existing = model.annotations.first {
            var edited = existing
            edited.text = "修改后文本"
            model.add(edited)
        }
        #expect(model.annotations.count == 1)
        #expect(model.annotations.first?.text == "修改后文本")
    }

    @Test
    func annotationTransformSupportsMoveResizeRotateAndTextBoxSizing() {
        let id = UUID()
        let rectangle = ScreenshotAnnotation(
            id: id,
            kind: .rectangle,
            rect: CGRect(x: 20, y: 30, width: 80, height: 40)
        )

        let moved = ScreenshotAnnotationTransform.translated(
            rectangle,
            by: CGSize(width: 12, height: -8)
        )
        #expect(moved.rect == CGRect(x: 32, y: 22, width: 80, height: 40))

        let scaled = ScreenshotAnnotationTransform.scaled(rectangle, by: 1.5)
        #expect(scaled.rect == CGRect(x: 0, y: 20, width: 120, height: 60))

        let rotated = ScreenshotAnnotationTransform.rotated(rectangle, by: .pi / 2)
        #expect(rotated.rotation == .pi / 2)

        let resized = ScreenshotAnnotationGeometry.transform(
            rectangle,
            handle: .bottomRight,
            from: CGPoint(x: 100, y: 70),
            to: CGPoint(x: 130, y: 90)
        )
        #expect(resized.rect == CGRect(x: 20, y: 30, width: 110, height: 60))

        let text = ScreenshotAnnotation(
            kind: .text,
            rect: CGRect(x: 20, y: 30, width: 80, height: 24),
            text: "批注",
            fontSize: 20
        )
        let textResized = ScreenshotAnnotationGeometry.transform(
            text,
            handle: .bottomRight,
            from: CGPoint(x: 100, y: 54),
            to: CGPoint(x: 140, y: 66)
        )
        #expect(textResized.rect == CGRect(x: 20, y: 30, width: 120, height: 36))
        #expect(textResized.fontSize == 20)

        let movedText = ScreenshotAnnotationGeometry.transform(
            ScreenshotAnnotation(
                kind: .text,
                rect: CGRect(x: 220, y: 30, width: 80, height: 24),
                text: String(repeating: "输入文字", count: 10),
                fontSize: 14
            ),
            handle: nil,
            from: CGPoint(x: 260, y: 42),
            to: CGPoint(x: 120, y: 42),
            textRightEdge: 320
        )
        #expect(movedText.rect.minX == 80)
        #expect(movedText.rect.width > 80)
        #expect(movedText.rect.maxX <= 320)
        #expect(movedText.fontSize == 14)
    }

    @Test
    func rectangleAnnotationSupportsEdgeMidpointResizeAndDetachedRotationHandle() {
        let rectangle = ScreenshotAnnotation(
            kind: .rectangle,
            rect: CGRect(x: 20, y: 30, width: 80, height: 40)
        )
        let rect = ScreenshotAnnotationGeometry.bounds(for: rectangle)

        #expect(ScreenshotAnnotationGeometry.handle(at: CGPoint(x: rect.midX, y: rect.minY), in: rectangle) == .top)
        #expect(ScreenshotAnnotationGeometry.handle(at: CGPoint(x: rect.maxX, y: rect.midY), in: rectangle) == .right)
        #expect(ScreenshotAnnotationGeometry.handle(at: CGPoint(x: rect.midX, y: rect.maxY), in: rectangle) == .bottom)
        #expect(ScreenshotAnnotationGeometry.handle(at: CGPoint(x: rect.minX, y: rect.midY), in: rectangle) == .left)
        #expect(ScreenshotAnnotationGeometry.handle(
            at: CGPoint(x: rect.midX, y: rect.minY - ScreenshotAnnotationGeometry.rotationOffset),
            in: rectangle
        ) == .rotation)

        #expect(ScreenshotAnnotationGeometry.transform(
            rectangle,
            handle: .top,
            from: CGPoint(x: rect.midX, y: rect.minY),
            to: CGPoint(x: rect.midX, y: 10)
        ).rect == CGRect(x: 20, y: 10, width: 80, height: 60))
        #expect(ScreenshotAnnotationGeometry.transform(
            rectangle,
            handle: .right,
            from: CGPoint(x: rect.maxX, y: rect.midY),
            to: CGPoint(x: 130, y: rect.midY)
        ).rect == CGRect(x: 20, y: 30, width: 110, height: 40))
        #expect(ScreenshotAnnotationGeometry.transform(
            rectangle,
            handle: .bottom,
            from: CGPoint(x: rect.midX, y: rect.maxY),
            to: CGPoint(x: rect.midX, y: 90)
        ).rect == CGRect(x: 20, y: 30, width: 80, height: 60))
        #expect(ScreenshotAnnotationGeometry.transform(
            rectangle,
            handle: .left,
            from: CGPoint(x: rect.minX, y: rect.midY),
            to: CGPoint(x: 10, y: rect.midY)
        ).rect == CGRect(x: 10, y: 30, width: 90, height: 40))
    }

    @Test
    func rotatedRectangleKeepsItsOppositeCornerWhileResizingAndCanRotateAgain() {
        let rectangle = ScreenshotAnnotation(
            kind: .rectangle,
            rect: CGRect(x: 20, y: 30, width: 80, height: 40),
            rotation: .pi / 2
        )
        let resized = ScreenshotAnnotationGeometry.transform(
            rectangle,
            handle: .bottomRight,
            from: CGPoint(x: 40, y: 90),
            to: CGPoint(x: 20, y: 110)
        )

        #expect(resized.rect == CGRect(x: 0, y: 30, width: 100, height: 60))
        #expect(ScreenshotAnnotationGeometry.handle(
            at: CGPoint(x: 20, y: 110),
            in: resized
        ) == .bottomRight)

        let rotatedAgain = ScreenshotAnnotationGeometry.transform(
            resized,
            handle: .rotation,
            from: CGPoint(x: 80, y: 60),
            to: CGPoint(x: 50, y: 90)
        )
        #expect(abs(rotatedAgain.rotation - .pi) < 0.0001)
        #expect(rotatedAgain.rect == resized.rect)
    }

    @Test
    func smallTextCenterCanDragWhileEditHandlesRemainAvailable() {
        let text = ScreenshotAnnotation(
            kind: .text,
            points: [CGPoint(x: 46, y: 46)],
            rect: CGRect(x: 40, y: 40, width: 12, height: 12),
            text: "A",
            fontSize: 3
        )
        let bounds = ScreenshotAnnotationGeometry.bounds(for: text)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        #expect(ScreenshotAnnotationGeometry.handle(at: center, in: text) == nil)
        #expect(ScreenshotAnnotationGeometry.handle(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            in: text
        ) == .topLeft)
        #expect(ScreenshotAnnotationGeometry.handle(
            at: CGPoint(x: bounds.midX, y: bounds.minY - ScreenshotAnnotationGeometry.rotationOffset),
            in: text
        ) == .rotation)

        let moved = ScreenshotAnnotationGeometry.transform(
            text,
            handle: nil,
            from: center,
            to: CGPoint(x: bounds.midX + 18, y: bounds.midY - 7)
        )
        #expect(moved.rect == bounds.offsetBy(dx: 18, dy: -7))
        #expect(moved.points == [CGPoint(x: 64, y: 39)])
    }

    @Test
    func rotationUsesShortestAngleAcrossPiBoundary() {
        let delta = ScreenshotAnnotationGeometry.shortestAngleDelta(
            from: CGFloat.pi - 0.05,
            to: -CGFloat.pi + 0.05
        )
        let reverseDelta = ScreenshotAnnotationGeometry.shortestAngleDelta(
            from: -CGFloat.pi + 0.05,
            to: CGFloat.pi - 0.05
        )

        #expect(abs(delta - 0.1) < 0.0001)
        #expect(abs(reverseDelta + 0.1) < 0.0001)
    }

    @Test
    func numberAnnotationSupportsMoveAndCornerResize() {
        let number = ScreenshotAnnotation(
            kind: .number,
            points: [CGPoint(x: 100, y: 100)],
            lineWidth: 4,
            number: 1
        )
        let bounds = ScreenshotAnnotationGeometry.bounds(for: number)
        #expect(bounds == CGRect(x: 86, y: 86, width: 28, height: 28))
        #expect(ScreenshotAnnotationGeometry.handle(
            at: CGPoint(x: bounds.midX, y: bounds.minY - ScreenshotAnnotationGeometry.rotationOffset),
            in: number
        ) == nil)

        let moved = ScreenshotAnnotationGeometry.transform(
            number,
            handle: nil,
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 120, y: 90)
        )
        #expect(moved.points == [CGPoint(x: 120, y: 90)])

        let resized = ScreenshotAnnotationGeometry.transform(
            number,
            handle: .bottomRight,
            from: CGPoint(x: bounds.maxX, y: bounds.maxY),
            to: CGPoint(x: 142, y: 128)
        )
        #expect(ScreenshotAnnotationGeometry.bounds(for: resized) == CGRect(
            x: 86,
            y: 86,
            width: 56,
            height: 56
        ))
        #expect(resized.points == [CGPoint(x: 114, y: 114)])
        #expect(resized.lineWidth == 8)
    }

    @Test
    func temporaryTextRemovalDoesNotCreateHistoryPoint() {
        let model = ScreenshotEditorModel(image: NSImage(size: CGSize(width: 320, height: 200)))
        let id = UUID()
        model.add(ScreenshotAnnotation(id: id, kind: .text, points: [CGPoint(x: 20, y: 20)]), saveUndo: false)
        model.remove(id: id, saveUndo: false)

        #expect(model.annotations.isEmpty)
        #expect(!model.canUndo)
    }

    @Test
    func toolbarUsesNativeDragContainerForResponsiveness() async throws {
        let size = CGSize(width: 800, height: 600)
        let image = try #require(makeGradientImage(width: 400, height: 300))
        let model = ScreenshotEditorModel(image: image)
        let hostingView = NSHostingView(rootView:
            ScreenshotEditorView(
                model: model,
                selectionState: ScreenshotAnnotationSelectionState(),
                onClose: {},
                onCopy: {},
                onPinToggle: { _ in },
                onLongCapture: {}
            )
            .frame(width: size.width, height: size.height)
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.contentView = hostingView
        for _ in 0..<3 {
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        #expect(hostingView.frame.size == size)
        #expect(findSubview(ScreenshotToolbarDragHandleView.self, in: hostingView) != nil)
    }

    @Test
    func toolbarDragMovesNativeContainerBeforeCommittingCenter() throws {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let toolbarSize = CGSize(width: 220, height: ScreenshotToolbarLayout.height)
        let initialCenter = CGPoint(x: 300, y: 260)
        var committedCenters: [CGPoint] = []
        let container = ScreenshotToolbarDragContainer(
            rootView: Text("toolbar"),
            restingCenter: initialCenter,
            toolbarSize: toolbarSize,
            bounds: bounds,
            onDragEnd: { committedCenters.append($0) }
        )
        let window = NSWindow(
            contentRect: bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        let parentView = NSView(frame: bounds)
        window.contentView = parentView
        parentView.addSubview(container)
        container.frame = bounds
        container.layoutSubtreeIfNeeded()

        let handle = try #require(findSubview(ScreenshotToolbarDragHandleView.self, in: container))
        let startLocal = CGPoint(x: 10, y: toolbarSize.height / 2)
        let firstLocal = CGPoint(x: startLocal.x + 18, y: startLocal.y + 12)
        let secondLocal = CGPoint(x: startLocal.x + 44, y: startLocal.y + 28)
        let start = handle.convert(startLocal, to: nil)
        let firstDrag = handle.convert(firstLocal, to: nil)
        let secondDrag = handle.convert(secondLocal, to: nil)
        handle.mouseDown(with: try #require(mouseEvent(
            type: .leftMouseDown,
            location: start,
            window: window,
            eventNumber: 1
        )))
        handle.mouseDragged(with: try #require(mouseEvent(
            type: .leftMouseDragged,
            location: firstDrag,
            window: window,
            eventNumber: 2
        )))

        #expect(committedCenters.isEmpty)
        #expect(handle.superview?.frame.origin == CGPoint(
            x: initialCenter.x - toolbarSize.width / 2 + 18,
            y: initialCenter.y - toolbarSize.height / 2 + 12
        ))

        handle.mouseDragged(with: try #require(mouseEvent(
            type: .leftMouseDragged,
            location: secondDrag,
            window: window,
            eventNumber: 3
        )))
        #expect(committedCenters.isEmpty)

        handle.mouseUp(with: try #require(mouseEvent(
            type: .leftMouseUp,
            location: secondDrag,
            window: window,
            eventNumber: 4
        )))
        #expect(committedCenters == [ScreenshotToolbarLayout.clampedCenter(
            CGPoint(x: initialCenter.x + 44, y: initialCenter.y + 28),
            toolbarSize: toolbarSize,
            in: bounds
        )])
    }

    @Test
    func mosaicRendersWithClampedExtentToPreventWhiteEdges() throws {
        let sourceImage = try #require(makeGradientImage(width: 100, height: 100))
        let model = ScreenshotEditorModel(image: sourceImage)
        model.add(ScreenshotAnnotation(
            kind: .mosaic,
            rect: CGRect(x: 10, y: 10, width: 80, height: 80),
            lineWidth: 8,
            obscureShape: .rectangle,
            obscureEffect: .pixelate
        ))

        let rendered = model.imageApplyingMosaics()
        let cgImage = try #require(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))

        #expect(rendered.size == CGSize(width: 100, height: 100))
        #expect(cgImage.width >= 100)
        #expect(cgImage.height >= 100)

        let centerPoint = CGPoint(x: cgImage.width / 2, y: cgImage.height / 2)
        let centerPixel = try #require(pixelColor(in: cgImage, at: centerPoint))
        #expect(centerPixel.a == 255, "马赛克区域不应出现透明像素")

        let edgePoints = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: cgImage.width - 1, y: 0),
            CGPoint(x: 0, y: cgImage.height - 1),
            CGPoint(x: cgImage.width - 1, y: cgImage.height - 1),
        ]
        for edgePoint in edgePoints {
            let pixel = try #require(pixelColor(in: cgImage, at: edgePoint))
            #expect(pixel.a == 255, "边角不应出现白块或透明像素")
        }
    }

    @Test
    func pinnedImageShowsFocusedStateWhenSelectedHoveredAndWindowActive() async throws {
        let image = try #require(makeGradientImage(width: 160, height: 100))
        let size = CGSize(width: image.size.width, height: image.size.height)
        let focusState = ScreenshotPinnedFocusState()
        let hostingView = NSHostingView(rootView:
            ScreenshotPinnedImageView(
                image: image,
                initialScale: 1,
                scaleRange: 0.2...3,
                initialOpacity: 1,
                onScaleChange: { _ in },
                onOpacityChange: { _ in },
                onMove: { _, _ in },
                onClose: {},
                toolbarVisible: false,
                focusState: focusState
            )
            .frame(width: size.width, height: size.height)
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.contentView = hostingView
        for _ in 0..<3 {
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }

        let interactionView = try #require(
            findSubview(ScreenshotPointerInteractionNSView.self, in: hostingView)
        )

        let event = try #require(mouseEvent(
            type: .leftMouseDown,
            location: CGPoint(x: 80, y: 50),
            window: window,
            eventNumber: 1
        ))
        interactionView.mouseEntered(with: event)
        #expect(!focusState.isActive)

        interactionView.mouseDown(with: event)
        #expect(focusState.isActive)

        interactionView.mouseExited(with: event)
        #expect(!focusState.isActive)

        try sendMouseDrag(
            from: CGPoint(x: 80, y: 50),
            to: CGPoint(x: 80, y: 50),
            through: interactionView,
            in: window
        )

        for _ in 0..<3 {
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }
    }

    private func makeTableGridImage() -> CGImage? {
        let width = 140
        let height = 110
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setShouldAntialias(false)
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1)
        for (start, end) in [
            (CGPoint(x: 10, y: 10), CGPoint(x: 130, y: 10)),
            (CGPoint(x: 10, y: 40), CGPoint(x: 130, y: 40)),
            (CGPoint(x: 50, y: 70), CGPoint(x: 130, y: 70)),
            (CGPoint(x: 10, y: 100), CGPoint(x: 130, y: 100)),
            (CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 100)),
            (CGPoint(x: 50, y: 10), CGPoint(x: 50, y: 100)),
            (CGPoint(x: 90, y: 40), CGPoint(x: 90, y: 100)),
            (CGPoint(x: 130, y: 10), CGPoint(x: 130, y: 100)),
        ] {
            context.move(to: start)
            context.addLine(to: end)
        }
        context.strokePath()
        return context.makeImage()
    }

    private func makeGradientImage(width: Int, height: Int) -> NSImage? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                pixels[offset] = UInt8((x * 2) % 256)
                pixels[offset + 1] = UInt8((y * 2) % 256)
                pixels[offset + 2] = UInt8((x + y) % 256)
                pixels[offset + 3] = 255
            }
        }
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    }

    private func makeCheckerboardImage(width: Int, height: Int) -> NSImage? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let value: UInt8 = ((x / 2) + (y / 2)).isMultiple(of: 2) ? 0 : 255
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
                pixels[offset + 3] = 255
            }
        }
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    }

    private func pixelColor(in cgImage: CGImage, at point: CGPoint) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        let width = cgImage.width
        let height = cgImage.height
        let x = Int(point.x)
        let y = Int(point.y)
        guard x >= 0, y >= 0, x < width, y < height else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let offset = (y * bytesPerRow) + (x * bytesPerPixel)
        return (
            r: pixelData[offset],
            g: pixelData[offset + 1],
            b: pixelData[offset + 2],
            a: pixelData[offset + 3]
        )
    }

    private func expectPixelsOutside(
        _ affectedBounds: CGRect,
        unchangedFrom original: CGImage,
        to rendered: CGImage
    ) throws {
        #expect(original.width == rendered.width)
        #expect(original.height == rendered.height)
        let originalPixels = try #require(rgbaPixels(in: original))
        let renderedPixels = try #require(rgbaPixels(in: rendered))
        var changedOutsideCount = 0

        for y in 0..<original.height {
            for x in 0..<original.width where !affectedBounds.contains(CGPoint(x: x, y: y)) {
                let offset = (y * original.width + x) * 4
                if originalPixels[offset..<(offset + 4)] != renderedPixels[offset..<(offset + 4)] {
                    changedOutsideCount += 1
                }
            }
        }

        #expect(changedOutsideCount == 0, "选区外不得改变任何像素")
    }

    private func rgbaPixels(in cgImage: CGImage) -> [UInt8]? {
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: cgImage.height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return pixels
    }

    private func colorDistance(
        _ left: (r: UInt8, g: UInt8, b: UInt8, a: UInt8),
        _ right: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
    ) -> Int {
        abs(Int(left.r) - Int(right.r))
            + abs(Int(left.g) - Int(right.g))
            + abs(Int(left.b) - Int(right.b))
            + abs(Int(left.a) - Int(right.a))
    }

    private func keyEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    private func pinnedImageCenter(in windowFrame: CGRect) -> CGPoint {
        CGPoint(
            x: windowFrame.midX,
            y: windowFrame.minY
                + ScreenshotPinnedLayout.footerHeight
                + (windowFrame.height - ScreenshotPinnedLayout.footerHeight) / 2
        )
    }

    private func findSubview<View: NSView>(_ type: View.Type, in root: NSView) -> View? {
        if let match = root as? View { return match }
        for subview in root.subviews {
            if let match = findSubview(type, in: subview) { return match }
        }
        return nil
    }

    private func sendMouseDrag(
        from start: CGPoint,
        to end: CGPoint,
        through view: ScreenshotPointerInteractionNSView,
        in window: NSWindow
    ) throws {
        let windowStart = view.convert(start, to: nil)
        let windowEnd = view.convert(end, to: nil)
        let events = [
            mouseEvent(type: .leftMouseDown, location: windowStart, window: window, eventNumber: 1),
            mouseEvent(type: .leftMouseDragged, location: windowEnd, window: window, eventNumber: 2),
            mouseEvent(type: .leftMouseUp, location: windowEnd, window: window, eventNumber: 3),
        ]
        view.mouseDown(with: try #require(events[0]))
        view.mouseDragged(with: try #require(events[1]))
        view.mouseUp(with: try #require(events[2]))
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        location: CGPoint,
        window: NSWindow,
        eventNumber: Int
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: TimeInterval(eventNumber),
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        )
    }

    private func screenMouseEvent(type: CGEventType, location: CGPoint) -> NSEvent? {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                  mouseEventSource: source,
                  mouseType: type,
                  mouseCursorPosition: location,
                  mouseButton: .left
              )
        else { return nil }
        return NSEvent(cgEvent: event)
    }

    @Test
    func emojiAnnotationUsesCircularDefaultSize() {
        let annotation = ScreenshotAnnotation(
            kind: .emoji,
            points: [CGPoint(x: 60, y: 40)],
            text: "⭐️"
        )

        let bounds = ScreenshotAnnotationGeometry.bounds(for: annotation)

        #expect(bounds.size == CGSize(width: 28, height: 28))
    }

    @Test
    func emojiAnnotationMustNotRenderWhiteRectangleBackground() throws {
        let sourceImage = try #require(makeGradientImage(width: 200, height: 150))
        let model = ScreenshotEditorModel(image: sourceImage)
        model.fontSize = 32

        model.add(ScreenshotAnnotation(
            kind: .emoji,
            points: [CGPoint(x: 100, y: 75)],
            text: "⭐️",
            fontSize: 32
        ))

        let original = try #require(sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rendered = model.renderedImage()
        let renderedCG = try #require(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))

        let font = NSFont.systemFont(ofSize: 32, weight: .semibold)
        let emojiTextSize = ("⭐️" as NSString).size(withAttributes: [.font: font])

        let backgroundWidth = max(emojiTextSize.width + 8, 12)
        let backgroundHeight = max(emojiTextSize.height + 4, 12)
        let backgroundBounds = CGRect(
            x: 100 - backgroundWidth / 2,
            y: 75 - backgroundHeight / 2,
            width: backgroundWidth,
            height: backgroundHeight
        )

        let sampleOffset: CGFloat = 6
        let cornerTestPoints = [
            CGPoint(x: backgroundBounds.minX + sampleOffset, y: backgroundBounds.minY + sampleOffset),
            CGPoint(x: backgroundBounds.maxX - sampleOffset, y: backgroundBounds.minY + sampleOffset),
            CGPoint(x: backgroundBounds.minX + sampleOffset, y: backgroundBounds.maxY - sampleOffset),
            CGPoint(x: backgroundBounds.maxX - sampleOffset, y: backgroundBounds.maxY - sampleOffset),
        ]

        var whiteBackgroundPixelCount = 0
        for testPoint in cornerTestPoints {
            let imageY = rendered.size.height - testPoint.y
            let pixelX = Int((testPoint.x * CGFloat(renderedCG.width) / rendered.size.width).rounded())
            let pixelY = Int((imageY * CGFloat(renderedCG.height) / rendered.size.height).rounded())
            let clampedPoint = CGPoint(
                x: min(max(pixelX, 0), renderedCG.width - 1),
                y: min(max(pixelY, 0), renderedCG.height - 1)
            )

            guard let originalPixel = pixelColor(in: original, at: clampedPoint),
                  let renderedPixel = pixelColor(in: renderedCG, at: clampedPoint)
            else { continue }

            let isWhiteBackground = renderedPixel.r > 220
                && renderedPixel.g > 220
                && renderedPixel.b > 220
                && renderedPixel.a > 200
            let changedFromOriginal = colorDistance(originalPixel, renderedPixel) > 50

            if isWhiteBackground && changedFromOriginal {
                whiteBackgroundPixelCount += 1
            }
        }

        #expect(
            whiteBackgroundPixelCount == 0,
            "Emoji 标注不应渲染白色矩形背景（检测到 \(whiteBackgroundPixelCount)/\(cornerTestPoints.count) 个白色背景像素），当前与 text 共享背景渲染导致失败"
        )
    }

    @Test
    func textAnnotationUsesGlyphBackgroundAndPreservesSelectedColor() throws {
        let sourceImage = try #require(makeGradientImage(width: 200, height: 150))
        let model = ScreenshotEditorModel(image: sourceImage)
        model.fontSize = 20

        let redColor = ScreenshotRGBA(red: 1, green: 0, blue: 0)
        let annotation = ScreenshotAnnotation(
            kind: .text,
            points: [CGPoint(x: 100, y: 75)],
            text: "测试",
            color: redColor,
            fontSize: 20
        )
        model.add(annotation)

        let original = try #require(sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rendered = model.renderedImage()
        let renderedCG = try #require(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))

        let font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        let textSize = ("测试" as NSString).size(withAttributes: [.font: font])

        let textBounds = ScreenshotAnnotationGeometry.bounds(for: annotation)
        #expect(
            textBounds.width >= textSize.width + 16,
            "文字字形背景应为轮廓留出足够空间"
        )

        let originalPixels = try #require(rgbaPixels(in: original))
        let renderedPixels = try #require(rgbaPixels(in: renderedCG))
        let glyphBounds = textBounds.integral
        let minX = max(0, Int(glyphBounds.minX))
        let maxX = min(renderedCG.width, Int(glyphBounds.maxX.rounded(.up)))
        let minY = max(0, Int(glyphBounds.minY))
        let maxY = min(renderedCG.height, Int(glyphBounds.maxY.rounded(.up)))
        var redPixelCount = 0
        var whiteBackgroundPixelCount = 0

        for y in minY..<maxY {
            let pixelY = min(max(renderedCG.height - 1 - y, 0), renderedCG.height - 1)
            for x in minX..<maxX {
                let offset = (pixelY * renderedCG.width + x) * 4
                let originalPixel = (
                    r: originalPixels[offset],
                    g: originalPixels[offset + 1],
                    b: originalPixels[offset + 2],
                    a: originalPixels[offset + 3]
                )
                let renderedPixel = (
                    r: renderedPixels[offset],
                    g: renderedPixels[offset + 1],
                    b: renderedPixels[offset + 2],
                    a: renderedPixels[offset + 3]
                )
                guard colorDistance(originalPixel, renderedPixel) > 40 else { continue }

                let red = Int(renderedPixel.r)
                let green = Int(renderedPixel.g)
                let blue = Int(renderedPixel.b)
                if red > green + 50,
                   red > blue + 50,
                   red > 150 {
                    redPixelCount += 1
                }
                if renderedPixel.r > 220,
                   renderedPixel.g > 220,
                   renderedPixel.b > 220 {
                    whiteBackgroundPixelCount += 1
                }
            }
        }

        #expect(redPixelCount > 0, "文本区域应保留用户选择的红色字形")
        #expect(whiteBackgroundPixelCount > 0, "文本字形周围应渲染白色背景")
    }

    @Test
    func textInputUsesWhiteOnDarkBackgroundAndBlackOnLightBackground() {
        #expect(ScreenshotRGBA.contrastingTextColor(for: .black) == .white)
        #expect(ScreenshotRGBA.contrastingTextColor(for: .white) == .black)
        #expect(ScreenshotInlineTextLayout.placeholderOpacity > 0)
        #expect(ScreenshotInlineTextLayout.placeholderOpacity < 1)
    }
}
