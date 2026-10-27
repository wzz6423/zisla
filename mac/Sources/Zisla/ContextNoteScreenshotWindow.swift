import AppKit
import ZislaCore
import ZislaKit

@MainActor
final class ContextNoteScreenshotWindow: NSWindow {
    private let screenshot: ContextNoteScreenshot
    private let onCopy: (Data) -> Void
    private let onSave: (Data) -> Void

    init(screenshot: ContextNoteScreenshot, onCopy: @escaping (Data) -> Void, onSave: @escaping (Data) -> Void,
         screen: NSScreen? = WindowPlacement.screenUnderMouse()) {
        self.screenshot = screenshot
        self.onCopy = onCopy
        self.onSave = onSave
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let size = Self.initialContentSize(for: screenshot.image.size, visibleFrame: screen?.visibleFrame)
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        title = AppLocalization.text("截图")
        contentAspectRatio = screenshot.image.size
        let imageView = NSImageView(frame: CGRect(origin: .zero, size: size))
        imageView.image = screenshot.image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityLabel(AppLocalization.text("截图"))
        contentView = imageView
        WindowPlacement.center(self, on: screen)
    }

    static func initialContentSize(for imageSize: CGSize, visibleFrame: CGRect?) -> CGSize {
        var scale = 640 / imageSize.width
        if let visibleFrame {
            let available = contentRect(forFrameRect: visibleFrame, styleMask: [.titled, .closable, .miniaturizable, .resizable]).size
            scale = min(scale, available.width / imageSize.width, available.height / imageSize.height)
        }
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        if modifiers == .command {
            switch event.charactersIgnoringModifiers {
            case "c": onCopy(screenshot.png); return true
            case "s": onSave(screenshot.png); return true
            case "w": performClose(nil); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

@MainActor
final class ContextNoteScreenshotWindowController: NSObject, NSWindowDelegate {
    private(set) var window: ContextNoteScreenshotWindow?
    private let presentWindow: (NSWindow) -> Void

    init(presentWindow: @escaping (NSWindow) -> Void = {
        NSApp.activate(ignoringOtherApps: true)
        $0.makeKeyAndOrderFront(nil)
    }) {
        self.presentWindow = presentWindow
    }

    func present(_ screenshot: ContextNoteScreenshot, onCopy: @escaping (Data) -> Void, onSave: @escaping (Data) -> Void) {
        window?.close()
        let preview = ContextNoteScreenshotWindow(screenshot: screenshot, onCopy: onCopy, onSave: onSave)
        preview.delegate = self
        window = preview
        presentWindow(preview)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    isolated deinit {
        window?.close()
    }
}
