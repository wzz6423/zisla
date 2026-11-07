import AppKit
import Foundation
import Testing

@testable import Zisla
@testable import ZislaKit

@Suite("Screenshot lifecycle")
struct ScreenshotLifecycleTests {
    @Test(arguments: [
        (selecting: false, pins: [Bool](), active: false),
        (selecting: true, pins: [], active: true),
        (selecting: false, pins: [false], active: true),
        (selecting: false, pins: [true], active: false),
        (selecting: false, pins: [true, true], active: false),
        (selecting: true, pins: [true, true], active: true),
        (selecting: false, pins: [true, false, true], active: true),
        (selecting: false, pins: [false, true, false], active: true),
    ])
    func screenshotSessionRequiresSelectionOrUnpinnedEditor(selecting: Bool, pins: [Bool], active: Bool) {
        #expect(ScreenshotHotkeyContext.isScreenshotSessionActive(
            selecting: selecting,
            editorPinnedStates: pins
        ) == active, "Retained pins must not keep the screenshot session frozen")
    }

    @Test @MainActor
    func pinAndCloseEventsEndTheSessionOnlyAfterSelectionAndUnpinnedEditorsAreGone() throws {
        let suiteName = "Zisla.ScreenshotLifecycle.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = FeatureSettingsStore(defaults: defaults)
        defer {
            store.flushPendingChanges()
            defaults.removePersistentDomain(forName: suiteName)
        }
        let pixels = try #require(Self.solidImage(width: 40, height: 40, color: (255, 255, 255)))
        let image = NSImage(cgImage: pixels, size: CGSize(width: 40, height: 40))
        var retainedEditors: [(id: Int, controller: ScreenshotEditorWindowController)] = []
        var selecting = false
        var sessionActive = true
        var closedEditors = 0
        let editors = (0..<3).map { id in
            let controller = ScreenshotEditorWindowController(
                image: image,
                screenImage: image,
                screenCGImage: pixels,
                screen: nil,
                captureRect: CGRect(x: 0, y: 0, width: 40, height: 40),
                capturedApplication: nil,
                settingsStore: store,
                onStash: { _, _ in },
                writeImageToPasteboard: { _ in false },
                presentSavePanel: { _, _ in },
                onClose: {
                    closedEditors += 1
                    retainedEditors.removeAll { $0.id == id }
                    sessionActive = ScreenshotHotkeyContext.isScreenshotSessionActive(
                        selecting: selecting,
                        editorPinnedStates: retainedEditors.map { $0.controller.isPinnedPresentation }
                    )
                }
            )
            controller.window?.alphaValue = 0
            controller.onHotkeyContextChanged = {
                sessionActive = ScreenshotHotkeyContext.isScreenshotSessionActive(
                    selecting: selecting,
                    editorPinnedStates: retainedEditors.map { $0.controller.isPinnedPresentation }
                )
            }
            retainedEditors.append((id, controller))
            return controller
        }
        defer { editors.forEach { $0.close() } }
        let firstWindow = try #require(editors[0].window)
        let lastWindow = try #require(editors[2].window)

        editors[0].setPinned(true)
        #expect(sessionActive, "Another unpinned editor must keep the session active")
        #expect(closedEditors == 0)
        editors[2].setPinned(true)
        #expect(sessionActive, "A remaining unpinned editor must still keep the session active")
        editors[1].setPinned(true)
        #expect(!sessionActive, "Pinning the last editor must end the frozen session immediately")
        #expect(closedEditors == 0)
        #expect(retainedEditors.count == 3)

        selecting = true
        sessionActive = true
        editors[1].close()
        #expect(sessionActive, "Closing a pin must not finish a pending selection")
        #expect(closedEditors == 1)
        editors[2].windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: lastWindow))
        #expect(sessionActive, "A pin's focus event must not finish a pending selection")
        selecting = false
        sessionActive = ScreenshotHotkeyContext.isScreenshotSessionActive(
            selecting: selecting,
            editorPinnedStates: retainedEditors.map { $0.controller.isPinnedPresentation }
        )
        #expect(!sessionActive, "Cancelling selection with only pins must restore the live presentation")
        #expect(retainedEditors.count == 2)
        #expect(firstWindow.contentView != nil && lastWindow.contentView != nil)
        #expect(editors[0].isPinnedPresentation && editors[2].isPinnedPresentation)

        editors[0].windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: firstWindow))
        #expect(!sessionActive, "Focusing a pin must not refreeze the screenshot session")
        editors[0].windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: firstWindow))
        #expect(!sessionActive)
        editors[2].close()
        #expect(!sessionActive)
        #expect(retainedEditors.count == 1)
        #expect(firstWindow.contentView != nil && editors[0].isPinnedPresentation)
        editors[0].close()
        editors[0].close()
        #expect(!sessionActive && retainedEditors.isEmpty)
        #expect(closedEditors == 3, "Duplicate close events must not retire another pin")
        #expect(firstWindow.contentView == nil && lastWindow.contentView == nil)
        #expect(!firstWindow.isVisible && !lastWindow.isVisible)
    }

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

    @Test
    func restoringEditorPresentationInstallsContentBeforePaintingTheWindow() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/ScreenshotEditorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let restore = try #require(source.range(of: "private func restoreEditorPresentation()"))
        let dismissOverlays = try #require(source.range(
            of: "private func dismissLongCaptureOverlays()",
            range: restore.upperBound..<source.endIndex
        ))
        let restoreLifecycle = source[restore.lowerBound..<dismissOverlays.lowerBound]
        let restoresContent = try #require(restoreLifecycle.range(of: "configureOverlayView(in: window)"))
        let turnsOpaque = try #require(restoreLifecycle.range(of: "window.isOpaque = true"))
        let paintsBlack = try #require(restoreLifecycle.range(of: "window.backgroundColor = .black"))
        // Restoring opacity before the editor content causes a full-screen black flash.
        #expect(restoresContent.lowerBound < turnsOpaque.lowerBound)
        #expect(restoresContent.lowerBound < paintsBlack.lowerBound)
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
