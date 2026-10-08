import AppKit
import SwiftUI
import ZislaCore

@MainActor
public struct FileShelfDragSourceView: NSViewRepresentable {
    public typealias NSViewType = NSView

    private var payload: TransferPasteboardPayload
    private var image: NSImage
    private var onOpen: () -> Void
    private var onReveal: () -> Void
    private var onCopy: () -> Void
    private var onRemove: () -> Void
    private var onSave: (() -> Void)?
    private var preparePayload: (() -> TransferPasteboardPayload?)?

    public init(
        payload: TransferPasteboardPayload,
        image: NSImage,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onRemove: @escaping () -> Void,
        onSave: (() -> Void)? = nil,
        preparePayload: (() -> TransferPasteboardPayload?)? = nil
    ) {
        self.payload = payload
        self.image = image
        self.onOpen = onOpen
        self.onReveal = onReveal
        self.onCopy = onCopy
        self.onRemove = onRemove
        self.onSave = onSave
        self.preparePayload = preparePayload
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

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    private func configure(_ view: FileShelfDraggingView) {
        view.payload = payload
        view.image = image
        view.onOpen = onOpen
        view.onReveal = onReveal
        view.onCopy = onCopy
        view.onRemove = onRemove
        view.onSave = onSave
        view.preparePayload = preparePayload
    }
}

@MainActor
final class FileShelfDraggingView: NSImageView, NSDraggingSource {
    var payload: TransferPasteboardPayload?
    var onOpen: (() -> Void)?
    var onReveal: (() -> Void)?
    var onCopy: (() -> Void)?
    var onRemove: (() -> Void)?
    var onSave: (() -> Void)?
    var preparePayload: (() -> TransferPasteboardPayload?)?
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
        guard !didBeginDragging, let payload else { return }
        let preparedPayload: TransferPasteboardPayload
        if let preparePayload {
            guard let value = preparePayload() else { return }
            preparedPayload = value
        } else { preparedPayload = payload }
        didBeginDragging = true

        let draggingItem = NSDraggingItem(pasteboardWriter: FileShelfPasteboard.pasteboardWriter(for: preparedPayload))
        draggingItem.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didBeginDragging, event.clickCount == 2 {
            onOpen?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard payload != nil else { return nil }

        let menu = NSMenu()
        menu.addItem(menuItem(title: onSave == nil ? "打开" : "预览", action: #selector(openItem)))
        if case .file = payload, onSave == nil {
            menu.addItem(menuItem(title: "在 Finder 中显示", action: #selector(revealItem)))
        }
        menu.addItem(menuItem(title: "复制", action: #selector(copyItem)))
        if onSave != nil { menu.addItem(menuItem(title: "保存", action: #selector(saveItem))) }
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "移除", action: #selector(removeItem)))
        return menu
    }

    func sourceOperationMask(for context: NSDraggingContext) -> NSDragOperation {
        .copy
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
        let item = NSMenuItem(title: AppLocalization.text(title), action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openItem() {
        onOpen?()
    }

    @objc private func revealItem() {
        onReveal?()
    }

    @objc private func copyItem() {
        onCopy?()
    }

    @objc private func saveItem() {
        onSave?()
    }

    @objc private func removeItem() {
        onRemove?()
    }
}
