import AppKit
import SwiftUI

@MainActor
public struct FileShelfDragSourceView: NSViewRepresentable {
    public typealias NSViewType = NSView

    private var url: URL
    private var image: NSImage
    private var onOpen: () -> Void
    private var onReveal: () -> Void
    private var onRemove: () -> Void

    public init(
        url: URL,
        image: NSImage,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.url = url
        self.image = image
        self.onOpen = onOpen
        self.onReveal = onReveal
        self.onRemove = onRemove
    }

    public func makeNSView(context: Context) -> NSView {
        let view = FileShelfDraggingView()
        configure(view)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? FileShelfDraggingView else { return }
        configure(view)
    }

    private func configure(_ view: FileShelfDraggingView) {
        view.fileURL = url
        view.image = image
        view.onOpen = onOpen
        view.onReveal = onReveal
        view.onRemove = onRemove
    }
}

@MainActor
final class FileShelfDraggingView: NSImageView, NSDraggingSource {
    var fileURL: URL?
    var onOpen: (() -> Void)?
    var onReveal: (() -> Void)?
    var onRemove: (() -> Void)?
    private var didBeginDragging = false

    var ignoresModifierKeys: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageAlignment = .alignCenter
        imageScaling = .scaleProportionallyUpOrDown
        isEditable = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        didBeginDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didBeginDragging, let fileURL else { return }
        didBeginDragging = true

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardWriter(for: fileURL))
        draggingItem.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didBeginDragging, event.clickCount == 2 {
            onOpen?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard fileURL != nil else { return nil }

        let menu = NSMenu()
        menu.addItem(menuItem(title: "打开", action: #selector(openItem)))
        menu.addItem(menuItem(title: "在 Finder 中显示", action: #selector(revealItem)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "移除", action: #selector(removeItem)))
        return menu
    }

    func sourceOperationMask(for context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func pasteboardWriter(for url: URL) -> NSURL {
        url as NSURL
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        sourceOperationMask(for: context)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        ignoresModifierKeys
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openItem() {
        onOpen?()
    }

    @objc private func revealItem() {
        onReveal?()
    }

    @objc private func removeItem() {
        onRemove?()
    }
}
