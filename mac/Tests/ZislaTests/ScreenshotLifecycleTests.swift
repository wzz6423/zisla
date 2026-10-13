import AppKit
import Foundation
import Testing

@testable import Zisla

@Suite("Screenshot lifecycle")
struct ScreenshotLifecycleTests {
    @Test @MainActor
    func screenshotSelectionDismissesOnlyAnActiveModalSession() {
        var abortCount = 0

        ScreenshotModalSession.dismissForSelectionPresentation(
            modalWindow: nil,
            abortModal: { abortCount += 1 }
        )
        #expect(abortCount == 0)

        ScreenshotModalSession.dismissForSelectionPresentation(
            modalWindow: NSWindow(
                contentRect: .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            ),
            abortModal: { abortCount += 1 }
        )
        #expect(abortCount == 1)
    }

    @Test
    func modalSnapshotUsesTopLeftDisplayCoordinates() {
        let screenFrame = CGRect(x: 1_440, y: -900, width: 1_920, height: 1_080)
        let modalFrame = CGRect(x: 1_560, y: -300, width: 500, height: 400)

        #expect(ScreenshotModalWindowSnapshot.localTopLeftFrame(
            for: modalFrame,
            on: screenFrame
        ) == CGRect(x: 120, y: 80, width: 500, height: 400))
    }

    @Test
    func modalSnapshotIsCompositedAtItsTopLeftScreenPosition() throws {
        let background = try #require(Self.solidImage(width: 8, height: 8, color: (0, 0, 0)))
        let modal = try #require(Self.solidImage(width: 2, height: 2, color: (255, 0, 0)))
        let image = try #require(ScreenshotModalWindowSnapshot.composite(
            modal,
            in: CGRect(x: 2, y: 3, width: 2, height: 2),
            over: background,
            screenSize: CGSize(width: 8, height: 8)
        ))

        let inside = try #require(ScreenshotCaptureService.pixelColor(
            at: CGPoint(x: 2, y: 3),
            in: image,
            screenSize: CGSize(width: 8, height: 8)
        ))
        let above = try #require(ScreenshotCaptureService.pixelColor(
            at: CGPoint(x: 2, y: 2),
            in: image,
            screenSize: CGSize(width: 8, height: 8)
        ))
        #expect(inside.hex == "#FF0000")
        #expect(above.hex == "#000000")
    }

    @Test
    func clipboardAssistantSnapshotIsCompositedAtRetinaScale() throws {
        let background = try #require(Self.solidImage(width: 16, height: 16, color: (0, 0, 0)))
        let assistant = try #require(Self.solidImage(width: 2, height: 1, color: (0, 255, 0)))
        let image = try #require(ScreenshotModalWindowSnapshot.composite(
            assistant,
            in: CGRect(x: 2, y: 3, width: 2, height: 1),
            over: background,
            screenSize: CGSize(width: 8, height: 8)
        ))

        let progressPixel = try #require(ScreenshotCaptureService.pixelColor(
            at: CGPoint(x: 2, y: 3),
            in: image,
            screenSize: CGSize(width: 8, height: 8)
        ))
        let below = try #require(ScreenshotCaptureService.pixelColor(
            at: CGPoint(x: 2, y: 4),
            in: image,
            screenSize: CGSize(width: 8, height: 8)
        ))
        #expect(progressPixel.hex == "#00FF00")
        #expect(below.hex == "#000000")
    }

    private static func solidImage(
        width: Int,
        height: Int,
        color: (UInt8, UInt8, UInt8)
    ) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = color.0
            pixels[offset + 1] = color.1
            pixels[offset + 2] = color.2
            pixels[offset + 3] = 255
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
}
