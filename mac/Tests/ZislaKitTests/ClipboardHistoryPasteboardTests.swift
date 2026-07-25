import AppKit
import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct ClipboardHistoryPasteboardTests {
    @Test
    func textRoundTripsThroughPasteboard() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        #expect(ClipboardHistoryPasteboard.write(.text("  hello history  "), to: pasteboard))
        #expect(ClipboardHistoryPasteboard.readContent(from: pasteboard) == .text("  hello history  "))
    }

    @Test
    func pngRoundTripsThroughPasteboard() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let data = try #require(makePNGData())

        #expect(ClipboardHistoryPasteboard.write(.image(data), to: pasteboard))
        #expect(ClipboardHistoryPasteboard.readContent(from: pasteboard) == .image(data))
    }

    @Test
    func monitorCapturesOneChangedValueOnlyOnce() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        var captured: [ClipboardHistoryContent] = []
        let monitor = ClipboardHistoryMonitor(pasteboard: pasteboard, pollInterval: 10) {
            captured.append($0)
        }

        monitor.setEnabled(true)
        #expect(ClipboardHistoryPasteboard.write(.text("new value"), to: pasteboard))
        monitor.pollNow()
        monitor.pollNow()

        #expect(captured == [.text("new value")])
        monitor.setEnabled(false)
    }

    @Test
    func concealedContentIsIgnored() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("secret", forType: .string))
        #expect(pasteboard.setData(
            Data(),
            forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        ))

        #expect(ClipboardHistoryPasteboard.readContent(from: pasteboard) == nil)
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("dev.wzz.zisla.tests.clipboard-history.\(UUID().uuidString)"))
    }

    private func makePNGData() -> Data? {
        let image = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: .alphaFirst,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        image?.setColor(
            NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.96, alpha: 1),
            atX: 0,
            y: 0
        )
        return image?.representation(using: .png, properties: [:])
    }
}
