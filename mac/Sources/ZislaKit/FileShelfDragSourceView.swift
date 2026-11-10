import AppKit
import SwiftUI
import ZislaCore

@MainActor
public final class FileShelfContextMenuItem: NSMenuItem {
    private let handler: () -> Void

    public init(title: String, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: AppLocalization.text(title), action: #selector(invoke), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func invoke() { handler() }
}

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
    private var preparePayloads: (() -> [TransferPasteboardPayload])?
    private var onSelect: (() -> Void)?
    private var makeContextMenu: (() -> NSMenu)?

    public init(
        payload: TransferPasteboardPayload,
        image: NSImage,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onRemove: @escaping () -> Void,
        onSave: (() -> Void)? = nil,
        preparePayload: (() -> TransferPasteboardPayload?)? = nil,
        preparePayloads: (() -> [TransferPasteboardPayload])? = nil,
        onSelect: (() -> Void)? = nil,
        makeContextMenu: (() -> NSMenu)? = nil
    ) {
        self.payload = payload
        self.image = image
        self.onOpen = onOpen
        self.onReveal = onReveal
        self.onCopy = onCopy
        self.onRemove = onRemove
        self.onSave = onSave
        self.preparePayload = preparePayload
        self.preparePayloads = preparePayloads
        self.onSelect = onSelect
        self.makeContextMenu = makeContextMenu
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
        view.preparePayloads = preparePayloads
        view.onSelect = onSelect
        view.makeContextMenu = makeContextMenu
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
    var preparePayloads: (() -> [TransferPasteboardPayload])?
    var onSelect: (() -> Void)?
    var makeContextMenu: (() -> NSMenu)?
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
        guard !didBeginDragging else { return }
        let items = draggingItems()
        guard !items.isEmpty else { return }
        didBeginDragging = true
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingItems() -> [NSDraggingItem] {
        let payloads: [TransferPasteboardPayload]
        if let preparePayloads { payloads = preparePayloads() }
        else if let preparePayload {
            guard let value = preparePayload() else { return [] }
            payloads = [value]
        } else { payloads = payload.map { [$0] } ?? [] }
        return payloads.map { payload in
            let item = NSDraggingItem(pasteboardWriter: FileShelfPasteboard.pasteboardWriter(for: payload))
            item.setDraggingFrame(bounds, contents: image)
            return item
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !didBeginDragging {
            if let onSelect { if event.clickCount == 1 { onSelect() } }
            else if event.clickCount == 2 { onOpen?() }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let makeContextMenu { return makeContextMenu() }
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
