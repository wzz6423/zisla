import AppKit
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ContextNoteScreenshotWindowTests {
    @Test(arguments: [CGSize(width: 80, height: 40), CGSize(width: 40, height: 80), CGSize(width: 80, height: 80)])
    func nativePreviewFillsItsContentWithoutVerticalMargins(imageSize: CGSize) async throws {
        _ = NSApplication.shared
        let screenshot = try makeScreenshot(size: imageSize)
        let screen = try #require(NSScreen.screens.first)
        let window = ContextNoteScreenshotWindow(screenshot: screenshot, onCopy: { _ in }, onSave: { _ in }, screen: screen)
        defer { window.close() }
        #expect(abs(window.frame.midX - screen.visibleFrame.midX) < 1)
        #expect(abs(window.frame.midY - screen.visibleFrame.midY) < 1)
        window.setFrameOrigin(CGPoint(x: -100_000, y: -100_000))
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) })
        window.orderFrontRegardless()
        #expect(window.styleMask == [.titled, .closable, .miniaturizable, .resizable])
        #expect(window.level == .normal)
        #expect(window.title == AppLocalization.text("截图"))
        #expect(window.canBecomeKey)
        #expect(window.canBecomeMain)
        #expect(window.parent == nil && window.sheetParent == nil)
        #expect(window.contentAspectRatio == imageSize)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            #expect(window.standardWindowButton(button) != nil)
        }
        let image = try #require(window.contentView as? NSImageView)
        #expect(image.image === screenshot.image)
        #expect(image.accessibilityLabel() == AppLocalization.text("截图"))
        #expect(abs(image.bounds.width / image.bounds.height - imageSize.width / imageSize.height) < 0.001)
        #expect(abs(image.bounds.height - window.contentLayoutRect.height) < 0.01)
        #expect(abs(image.bounds.width - window.contentLayoutRect.width) < 0.01)
        for _ in 0..<3 {
            image.layoutSubtreeIfNeeded()
            image.displayIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let bitmap = try #require(image.bitmapImageRepForCachingDisplay(in: image.bounds))
        image.cacheDisplay(in: image.bounds, to: bitmap)
        let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
            .usingColorSpace(.deviceRGB))
        #expect(center.alphaComponent > 0.9 && center.redComponent > center.greenComponent + 0.3
                && center.redComponent > center.blueComponent + 0.3)
        for y in [1, bitmap.pixelsHigh / 2, bitmap.pixelsHigh - 2] {
            let pixel = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: y)?.usingColorSpace(.deviceRGB))
            #expect(abs(pixel.redComponent - center.redComponent) < 0.01
                    && abs(pixel.greenComponent - center.greenComponent) < 0.01
                    && abs(pixel.blueComponent - center.blueComponent) < 0.01
                    && abs(pixel.alphaComponent - center.alphaComponent) < 0.01,
                    "The screenshot must reach both vertical content edges: \(pixel)")
        }
        #expect(window.isVisible)
    }

    @Test(arguments: [CGSize(width: 1600, height: 900), CGSize(width: 900, height: 2400)], [CGSize(width: 800, height: 600), CGSize(width: 1920, height: 1080)])
    func initialPreviewFitsTheWorkingScreenAndPreservesTheImageRatio(imageSize: CGSize, screenSize: CGSize) {
        let visibleFrame = CGRect(origin: CGPoint(x: -1200, y: 400), size: screenSize)
        let size = ContextNoteScreenshotWindow.initialContentSize(for: imageSize, visibleFrame: visibleFrame)
        let frame = NSWindow.frameRect(forContentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable])
        #expect(size.width > 0 && size.height > 0)
        #expect(size.width <= 640)
        #expect(frame.width <= screenSize.width + 0.01 && frame.height <= screenSize.height + 0.01)
        #expect(abs(size.width / size.height - imageSize.width / imageSize.height) < 0.0001)
        let withoutScreen = ContextNoteScreenshotWindow.initialContentSize(for: imageSize, visibleFrame: nil)
        #expect(withoutScreen.width == 640)
        #expect(abs(withoutScreen.width / withoutScreen.height - imageSize.width / imageSize.height) < 0.0001)
    }

    @Test
    func hidingAndClosingTheNoteLeavesThePreviewAndItsSnapshotUsable() throws {
        _ = NSApplication.shared
        let controller = ContextNoteScreenshotWindowController(presentWindow: { window in
            window.setFrameOrigin(CGPoint(x: -100_000, y: -100_000))
            window.orderFrontRegardless()
        })
        let editor = ContextNoteShelfEditor(screenshotPreview: controller)
        let draft = ContextNoteDraft(location: Self.location)
        draft.text = "Keep the note separate from its preview"
        editor.begin(draft)
        let screenshot = try ContextNoteScreenshot(png: ContextNoteScreenshotTestImage.make().png)
        var copies: [Data] = []
        controller.present(screenshot, onCopy: { copies.append($0) }, onSave: { _ in })
        let preview = try #require(controller.window)
        editor.hide()
        #expect(controller.window === preview && preview.isVisible && !editor.isPresented)
        editor.close()
        #expect(editor.draft == nil && controller.window === preview && preview.isVisible)
        #expect(preview.performKeyEquivalent(with: try key("c", in: preview)))
        #expect(copies == [screenshot.png])
        #expect(draft.text == "Keep the note separate from its preview")
        preview.cancelOperation(nil)
        #expect(controller.window == nil)
    }

    @Test(arguments: [NSEvent.ModifierFlags.command, [.command, .capsLock], [.command, .shift], [.command, .option]])
    func commandCCopiesTheOriginalPNGWithOnlyTheIntendedModifiers(modifiers: NSEvent.ModifierFlags) throws {
        _ = NSApplication.shared
        let screenshot = try ContextNoteScreenshot(png: ContextNoteScreenshotTestImage.make().png)
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        var copies = 0
        let preview = ContextNoteScreenshotWindow(screenshot: screenshot, onCopy: { png in
            copies += 1
            #expect(ClipboardHistoryPasteboard.write(.image(png), to: pasteboard))
        }, onSave: { _ in Issue.record("Copying must not open a save panel") })
        defer { preview.close() }
        let intended = modifiers == .command || modifiers == [.command, .capsLock]
        _ = preview.performKeyEquivalent(with: try key("c", in: preview, modifiers: modifiers))
        #expect(copies == (intended ? 1 : 0))
        #expect(pasteboard.data(forType: .png) == (intended ? screenshot.png : nil))
        if intended {
            #expect(pasteboard.canReadObject(forClasses: [NSImage.self], options: nil))
        }
    }

    @Test(arguments: ["save", "cancel", "write failure"])
    func commandSImmediatelyBeginsTheSharedSavePanelWithoutClosingThePreview(outcome: String) async throws {
        _ = NSApplication.shared
        let fixture = try SaveFixture()
        defer { fixture.close() }
        let screenshot = try ContextNoteScreenshot(png: ContextNoteScreenshotTestImage.make().png)
        let destination = fixture.directory.appendingPathComponent("screenshot.png")
        let existing = Data("existing destination".utf8)
        try existing.write(to: destination)
        fixture.panel.selectedURL = outcome == "write failure"
            ? fixture.directory.appendingPathComponent("missing/screenshot.png") : destination
        let controller = ContextNoteScreenshotWindowController(presentWindow: { _ in })
        let message: String? = await withCheckedContinuation { continuation in
            controller.present(screenshot, onCopy: { _ in Issue.record("Saving must not copy") }, onSave: { png in
                #expect(png == screenshot.png)
                ScreenshotImageExport.presentSavePanel(for: png, panel: fixture.panel,
                    systemPreferences: fixture.preferences, themeNotifications: fixture.notifications) {
                    continuation.resume(returning: $0)
                }
            })
            do {
                let preview = try #require(controller.window)
                try #require(preview.performKeyEquivalent(with: try key("s", in: preview)))
                try #require(fixture.panel.didBeginStandalone,
                        "Command-S must begin the existing save panel before returning")
                #expect(fixture.panel.sheetParent == nil && preview.attachedSheet == nil)
                #expect(fixture.panel.allowedContentTypes == [.png])
                #expect(fixture.panel.nameFieldStringValue == AppLocalization.text("截图.png"))
                #expect(controller.window === preview)
                fixture.panel.respond(outcome == "cancel" ? .cancel : .OK)
            } catch {
                Issue.record(error)
                continuation.resume(returning: nil)
            }
        }
        let preview = try #require(controller.window)
        defer { preview.close() }
        #expect(try Data(contentsOf: destination) == (outcome == "save" ? screenshot.png : existing))
        if outcome == "save" {
            #expect(message == AppLocalization.text("已保存：%@", destination.lastPathComponent))
        } else if outcome == "write failure" {
            #expect(message?.hasPrefix(AppLocalization.text("保存失败：%@", "")) == true)
        } else {
            #expect(message == nil)
        }
        #expect(controller.window === preview)
        #expect(preview.performKeyEquivalent(with: try key("w", in: preview)))
        #expect(controller.window == nil)
    }

    @Test(arguments: ["close", "replace", "release owner"])
    func previewClosesAndReleasesItsImageAndActionOwners(action: String) throws {
        _ = NSApplication.shared
        weak var oldPreview: ContextNoteScreenshotWindow?
        weak var image: NSImage?
        weak var owner: Owner?
        try autoreleasepool {
            var current: Owner? = Owner()
            owner = current
            let screenshot = try ContextNoteScreenshot(png: ContextNoteScreenshotTestImage.make().png)
            image = screenshot.image
            current?.editor.screenshotPreview.present(screenshot, onCopy: { [weak current] png in
                current?.copies.append(png)
            }, onSave: { [weak current] _ in current?.saves += 1 })
            oldPreview = current?.editor.screenshotPreview.window
            #expect(oldPreview != nil && image != nil)
            switch action {
            case "close":
                current?.editor.screenshotPreview.window?.performClose(nil)
                #expect(current?.editor.screenshotPreview.window == nil)
            case "replace":
                let replacement = try makeScreenshot(size: CGSize(width: 40, height: 80))
                current?.editor.screenshotPreview.present(replacement, onCopy: { _ in }, onSave: { _ in })
                #expect(current?.editor.screenshotPreview.window !== oldPreview)
            default: break
            }
            current = nil
        }
        #expect(owner == nil, "The preview's copy/save closures must not keep its owner alive")
        #expect(oldPreview == nil && image == nil, "Closed previews must release the original image")
    }

    private func key(_ character: String, in window: NSWindow, modifiers: NSEvent.ModifierFlags = .command) throws -> NSEvent {
        let characters = modifiers.contains(.capsLock) ? character.uppercased() : character
        return try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: character == "c" ? 8 : character == "s" ? 1 : 13))
    }

    private func makeScreenshot(size: CGSize) throws -> ContextNoteScreenshot {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        let image = try #require(context.makeImage())
        return try ContextNoteScreenshot(png: #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])))
    }

    private static let location = ContextNoteLocation.window(
        bundleIdentifier: "test.preview", applicationName: "Test", title: "Note"
    )

    @MainActor
    private final class Owner {
        let editor = ContextNoteShelfEditor(screenshotPreview: ContextNoteScreenshotWindowController(presentWindow: { window in
            window.setFrameOrigin(CGPoint(x: -100_000, y: -100_000))
            window.orderFrontRegardless()
        }))
        var copies: [Data] = []
        var saves = 0
    }

    @MainActor
    private final class SaveFixture {
        let directory: URL
        let preferences: UserDefaults
        let preferencesName = "note-preview-save-\(UUID())"
        let notifications = NotificationCenter()
        let panel = SavePanel()

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("note-preview-save-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            preferences = try #require(UserDefaults(suiteName: preferencesName))
            panel.directoryURL = directory
            panel.isReleasedWhenClosed = false
        }

        func close() {
            panel.close()
            preferences.removePersistentDomain(forName: preferencesName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private final class SavePanel: NSSavePanel {
        var didBeginStandalone = false
        var selectedURL: URL?
        private var completion: ((NSApplication.ModalResponse) -> Void)?
        override var url: URL? { selectedURL }

        override func begin(completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
            didBeginStandalone = true
            completion = handler
        }

        override func beginSheetModal(for window: NSWindow, completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
            Issue.record("The screenshot save panel must not be attached to the island or preview")
        }

        func respond(_ response: NSApplication.ModalResponse) {
            let handler = completion
            completion = nil
            handler?(response)
        }
    }
}
