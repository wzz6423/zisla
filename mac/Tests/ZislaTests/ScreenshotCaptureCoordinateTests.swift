import AppKit
import SwiftUI
import Testing
import Vision

@testable import Zisla

@MainActor
@Suite("Screenshot capture coordinates")
struct ScreenshotCaptureCoordinateTests {
    @Test
    func snapTargetsUseDisplayLocalTopLeftCoordinates() {
        let displayBounds = CGRect(x: 1_440, y: -900, width: 1_920, height: 1_080)
        let windowBounds = CGRect(x: 1_500, y: -840, width: 500, height: 400)

        #expect(ScreenshotSnapTargetGeometry.localRect(
            windowBounds,
            in: displayBounds
        ) == CGRect(x: 60, y: 60, width: 500, height: 400))
    }

    @Test
    func snapTargetsKeepNegativeDisplayOriginsInLocalCoordinates() {
        let displayBounds = CGRect(x: -1_920, y: -1_080, width: 1_920, height: 1_080)
        let windowBounds = CGRect(x: -1_800, y: -980, width: 500, height: 400)

        #expect(ScreenshotSnapTargetGeometry.localRect(
            windowBounds,
            in: displayBounds
        ) == CGRect(x: 120, y: 100, width: 500, height: 400))
    }

    @Test
    func snapTargetsPreferTheFrontmostContainingWindow() {
        let front = CGRect(x: 80, y: 60, width: 160, height: 120)
        let back = CGRect(x: 20, y: 20, width: 300, height: 240)

        #expect(ScreenshotSnapTargetGeometry.target(
            at: CGPoint(x: 120, y: 100),
            in: [front, back]
        ) == front)
    }

    @Test
    func accessibilityComponentsUseGlobalDisplayCoordinatesAndWinOverWindows() {
        let displayBounds = CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080)
        let localPoint = CGPoint(x: 120, y: 80)
        let component = CGRect(x: 100, y: 60, width: 80, height: 40)
        let window = CGRect(x: 40, y: 20, width: 400, height: 300)

        #expect(ScreenshotSnapTargetGeometry.globalPoint(
            localPoint,
            in: displayBounds
        ) == CGPoint(x: 1_632, y: 80))
        #expect(ScreenshotSnapTargetGeometry.target(
            at: localPoint,
            component: component,
            in: [window]
        ) == component)
    }

    @Test
    func topLeftSelectionCropsTheSameImageRegion() throws {
        let source = try #require(makeCoordinateImage(width: 8, height: 8))
        let selection = CGRect(x: 1, y: 1, width: 4, height: 2)
        let cropped = try #require(ScreenshotCaptureService.image(
            from: source,
            cropInScreenPoints: selection,
            screenSize: CGSize(width: 8, height: 8)
        ))
        let actual = try #require(cropped.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let expected = try #require(source.cropping(to: selection))

        #expect(rgbaPixels(in: actual) == rgbaPixels(in: expected))
    }

    @Test
    func longCaptureRangeConvertsTopLeftSelectionToAppKitScreenFrame() {
        let screenFrame = CGRect(x: 1_440, y: -900, width: 1_920, height: 1_080)
        let selection = CGRect(x: 120, y: 80, width: 500, height: 400)

        #expect(ScreenshotLongCaptureRangeGeometry.windowFrame(
            selection: selection,
            screenFrame: screenFrame
        ) == CGRect(x: 1_560, y: -300, width: 500, height: 400))
    }

    @Test
    func screenBackedPanelsUseLocalContentCoordinates() throws {
        let screenFrame = CGRect(x: 1_512, y: -98, width: 1_920, height: 1_080)
        let localContentRect = ScreenshotWindowGeometry.localContentRect(
            for: screenFrame,
            on: screenFrame
        )

        #expect(localContentRect == CGRect(origin: .zero, size: screenFrame.size))
        #expect(ScreenshotWindowGeometry.localContentRect(
            for: CGRect(x: 1_632, y: 202, width: 220, height: 400),
            on: screenFrame
        ) == CGRect(x: 120, y: 300, width: 220, height: 400))

        guard let screen = NSScreen.screens.first(where: { $0.frame.minX != 0 || $0.frame.minY != 0 }) else {
            return
        }
        let panel = NSPanel(
            contentRect: ScreenshotWindowGeometry.localContentRect(
                for: screen.frame,
                on: screen.frame
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        #expect(panel.frame == screen.frame)
        panel.close()
    }

    @Test
    func longCaptureMaskCoversEveryAreaOutsideTheSelection() {
        let screenSize = CGSize(width: 1_512, height: 982)
        let selection = CGRect(x: 420, y: 80, width: 720, height: 760)
        let masks = ScreenshotLongCaptureRangeGeometry.outsideRects(
            selection: selection,
            screenSize: screenSize
        )

        #expect(masks.count == 4)
        #expect(masks.allSatisfy { $0.width >= 0 && $0.height >= 0 })
        #expect(masks.allSatisfy { !$0.intersects(selection) })
        #expect(masks.contains { $0.contains(CGPoint(x: 8, y: 8)) })
        #expect(masks.contains { $0.contains(CGPoint(x: 1_500, y: 8)) })
        #expect(masks.contains { $0.contains(CGPoint(x: 8, y: 970)) })
        #expect(masks.contains { $0.contains(CGPoint(x: 1_500, y: 970)) })
    }

    @Test
    func longCapturePreviewUsesTheSideWithMoreSpace() {
        let available = CGRect(x: 0, y: 120, width: 1_512, height: 820)
        let imageSize = CGSize(width: 800, height: 1_600)
        let leftPlacement = ScreenshotLongCapturePreviewGeometry.frame(
            selectionFrame: CGRect(x: 620, y: 200, width: 800, height: 600),
            availableFrame: available,
            imageSize: imageSize
        )
        let rightPlacement = ScreenshotLongCapturePreviewGeometry.frame(
            selectionFrame: CGRect(x: 100, y: 200, width: 800, height: 600),
            availableFrame: available,
            imageSize: imageSize
        )

        #expect(leftPlacement.maxX < 620)
        #expect(rightPlacement.minX > 900)
    }

    @Test
    func longCapturePreviewGrowsWithTheImageAndThenFitsTheAvailableHeight() {
        let selection = CGRect(x: 100, y: 200, width: 800, height: 600)
        let available = CGRect(x: 0, y: 120, width: 1_512, height: 820)
        let short = ScreenshotLongCapturePreviewGeometry.frame(
            selectionFrame: selection,
            availableFrame: available,
            imageSize: CGSize(width: 800, height: 400)
        )
        let medium = ScreenshotLongCapturePreviewGeometry.frame(
            selectionFrame: selection,
            availableFrame: available,
            imageSize: CGSize(width: 800, height: 1_600)
        )
        let long = ScreenshotLongCapturePreviewGeometry.frame(
            selectionFrame: selection,
            availableFrame: available,
            imageSize: CGSize(width: 800, height: 8_000)
        )

        #expect(short.height < medium.height)
        #expect(medium.height < long.height)
        #expect(long.height == available.height)
    }

    private func makeCoordinateImage(width: Int, height: Int) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(y * 24)
                pixels[offset + 1] = UInt8(x * 24)
                pixels[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func rgbaPixels(in image: CGImage) -> [UInt8]? {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    @Test
    func recognitionRequestUsesValidLanguages() throws {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supportedLanguages = try request.supportedRecognitionLanguages()
        let proposedLanguages = ["zh-Hans", "en-US"]
        let validLanguages = proposedLanguages.filter { supportedLanguages.contains($0) }
        #expect(!validLanguages.isEmpty, "至少有一种语言被支持")
    }

    @Test
    func tableFormatterGroupsFragmentsByRow() {
        let fragments = [
            ScreenshotRecognizedFragment(text: "A1", boundingBox: CGRect(x: 0, y: 0.8, width: 0.1, height: 0.1)),
            ScreenshotRecognizedFragment(text: "B1", boundingBox: CGRect(x: 0.5, y: 0.8, width: 0.1, height: 0.1)),
            ScreenshotRecognizedFragment(text: "A2", boundingBox: CGRect(x: 0, y: 0.5, width: 0.1, height: 0.1)),
            ScreenshotRecognizedFragment(text: "B2", boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1)),
        ]
        let result = ScreenshotRecognitionFormatter.tableText(from: fragments)
        let lines = result.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("A1") && lines[0].contains("B1"))
        #expect(lines[1].contains("A2") && lines[1].contains("B2"))
    }

    @Test
    func pixelSamplerUsesScreenCoordinatesAndFormatsHex() throws {
        let image = try #require(makeCoordinateImage(width: 8, height: 8))
        let color = try #require(ScreenshotCaptureService.pixelColor(
            at: CGPoint(x: 2, y: 3),
            in: image,
            screenSize: CGSize(width: 8, height: 8)
        ))

        #expect(abs(color.red - 72.0 / 255.0) < 0.001)
        #expect(abs(color.green - 48.0 / 255.0) < 0.001)
        #expect(color.hex == "#483000")
    }

    @Test
    func windowCandidatesCanExcludeTheOverlayProcess() {
        let candidates = [
            ScreenshotWindowCandidate(
                rect: CGRect(x: 0, y: 0, width: 800, height: 600),
                layer: 0,
                alpha: 1,
                ownerProcessIdentifier: 42
            ),
            ScreenshotWindowCandidate(
                rect: CGRect(x: 20, y: 20, width: 200, height: 120),
                layer: 0,
                alpha: 1,
                ownerProcessIdentifier: 99
            ),
        ]

        let filtered = ScreenshotSnapTargetProvider.filteredWindowRects(
            candidates,
            excludingProcessIdentifier: 42
        )

        #expect(filtered == [CGRect(x: 20, y: 20, width: 200, height: 120)])
    }

    @Test
    func windowCandidatesRejectNearFullDisplayWindowsWhenFilteringForSnapping() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let candidates = [
            ScreenshotWindowCandidate(
                rect: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
                layer: 0,
                alpha: 1,
                ownerProcessIdentifier: 42
            ),
            ScreenshotWindowCandidate(
                rect: CGRect(x: 30, y: 40, width: 720, height: 480),
                layer: 0,
                alpha: 1,
                ownerProcessIdentifier: 99
            ),
        ]

        let filtered = ScreenshotSnapTargetProvider.filteredWindowRects(
            candidates,
            excludingProcessIdentifier: nil,
            within: displayBounds
        )

        #expect(filtered == [CGRect(x: 30, y: 40, width: 720, height: 480)])
    }

    @Test
    func pixelSamplerKeepsTheSameColorAcrossRepeatedLookups() throws {
        let image = try #require(makeCoordinateImage(width: 8, height: 8))
        let sampler = try #require(ScreenshotPixelSampler(cgImage: image))

        let first = try #require(sampler.color(
            at: CGPoint(x: 5, y: 1),
            screenSize: CGSize(width: 8, height: 8)
        ))
        let second = try #require(sampler.color(
            at: CGPoint(x: 5, y: 1),
            screenSize: CGSize(width: 8, height: 8)
        ))

        #expect(first == second)
        #expect(first.hex == "#187800")
    }

    @Test
    func selectionPanelCopiesCurrentColorWithCaseInsensitiveC() throws {
        let panel = ScreenshotSelectionPanel(
            contentRect: CGRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        var copyCount = 0
        panel.currentColor = ScreenshotRGBA(red: 1, green: 0, blue: 0)
        panel.onCopyColor = { copyCount += 1 }
        let lowerCaseEvent = try #require(keyEvent(keyCode: 8, characters: "c"))
        let upperCaseEvent = try #require(keyEvent(keyCode: 8, characters: "C"))

        #expect(panel.performKeyEquivalent(with: lowerCaseEvent))
        #expect(panel.performKeyEquivalent(with: upperCaseEvent))
        #expect(copyCount == 2)
    }

    @Test
    func colorCopyFeedbackClearsAfterThreeSeconds() async throws {
        let feedback = ScreenshotColorCopyFeedback()
        let color = ScreenshotRGBA(red: 1, green: 0, blue: 0)

        feedback.show(for: color)
        #expect(feedback.copiedColor == color)

        try await Task.sleep(for: .seconds(3.1))
        #expect(feedback.copiedColor == nil)
    }

    @Test
    func selectionOverlayAcceptsFirstMouseForImmediateDragging() throws {
        let screen = try #require(NSScreen.screens.first)
        let cgImage = try #require(makeCoordinateImage(width: 8, height: 8))
        let image = NSImage(cgImage: cgImage, size: screen.frame.size)
        var panels: [ScreenshotSelectionPanel] = []
        let controller = ScreenshotSelectionController(
            captureScreen: { _ in (image, cgImage) },
            presentPanels: { panels = $0 },
            snapTargets: { _ in [] }
        )
        controller.start(on: screen)
        let contentView = try #require(panels.first?.contentView)

        #expect(contentView.acceptsFirstMouse(for: nil))
        controller.cancel()
    }

    private func keyEvent(keyCode: UInt16, characters: String) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
