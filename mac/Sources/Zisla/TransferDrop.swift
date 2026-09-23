import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ZislaKit

enum TransferDropItem: Hashable, Sendable {
    case file(URL)
    case link(URL)
    case text(String)
    case image(Data)

    init(payload: TransferPasteboardPayload) {
        switch payload {
        case .file(let url): self = .file(url)
        case .text(let text):
            self = TransferPasteboard.webURL(from: text).map(Self.link) ?? .text(text)
        }
    }

    var shelfPayload: TransferPasteboardPayload? {
        switch self {
        case .file(let url): .file(url)
        case .link(let url): .text(url.absoluteString)
        case .text(let text): .text(text)
        case .image: nil
        }
    }

    var shareValue: Any {
        switch self {
        case .file(let url), .link(let url): url
        case .text(let value): value
        case .image(let data): NSImage(data: data) ?? data
        }
    }
}

struct TransferDropDelegate: DropDelegate {
    static let supportedContentTypes: [UTType] = [
        .fileURL,
        .url,
        .plainText,
        .utf8PlainText,
    ]
    static let supportedTypes = supportedContentTypes.map(\.identifier)

    @Binding var isTargeted: Bool
    var onItems: @MainActor @Sendable ([TransferDropItem]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: Self.supportedTypes)
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let providers = info.itemProviders(for: Self.supportedTypes)
        guard !providers.isEmpty else { return false }

        let loader = TransferDropLoader(count: providers.count, completion: onItems)
        for (index, provider) in providers.enumerated() {
            load(provider, at: index, into: loader)
        }
        return true
    }

    private func load(_ provider: NSItemProvider, at index: Int, into loader: TransferDropLoader) {
        let type: String
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            type = UTType.fileURL.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            type = UTType.url.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
            type = UTType.utf8PlainText.identifier
        } else {
            type = UTType.plainText.identifier
        }

        provider.loadItem(forTypeIdentifier: type) { value, _ in
            loader.finish(at: index, with: Self.dropItem(from: value, type: type))
        }
    }

    nonisolated static func dropItem(from value: NSSecureCoding?, type: String) -> TransferDropItem? {
        let string: String?
        if let url = value as? URL {
            string = url.absoluteString
        } else if let data = value as? Data {
            string = String(data: data, encoding: .utf8)
        } else {
            string = (value as? String) ?? (value as? NSString).map(String.init)
        }
        guard let string else { return nil }
        if type == UTType.fileURL.identifier {
            guard let url = URL(string: string), url.isFileURL else { return nil }
            return .file(url)
        }
        if let url = TransferPasteboard.webURL(from: string) { return .link(url) }
        if type == UTType.url.identifier { return nil }
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .text(string)
    }
}

final class TransferDropLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var items: [Int: TransferDropItem] = [:]
    private var completed = Set<Int>()
    private let completion: @MainActor @Sendable ([TransferDropItem]) -> Void

    init(
        count: Int,
        completion: @escaping @MainActor @Sendable ([TransferDropItem]) -> Void
    ) {
        remaining = count
        self.completion = completion
    }

    func finish(at index: Int, with item: TransferDropItem?) {
        lock.lock()
        guard completed.insert(index).inserted else {
            lock.unlock()
            return
        }
        if let item { items[index] = item }
        remaining -= 1
        let result = remaining == 0 ? items.sorted { $0.key < $1.key }.map(\.value) : nil
        lock.unlock()

        guard let result else { return }
        Task { @MainActor [completion] in
            completion(result)
        }
    }
}

@MainActor
struct ShelfDropTarget<Content: View>: NSViewRepresentable {
    @Binding var isTargeted: Bool
    var onItems: ([FileShelfDropItem]) -> Void
    var content: Content

    func makeNSView(context: Context) -> ShelfDropHostingView {
        let view = ShelfDropHostingView(rootView: AnyView(content.environment(\.self, context.environment)))
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ShelfDropHostingView, context: Context) {
        view.rootView = AnyView(content.environment(\.self, context.environment))
        view.onTargeted = { isTargeted = $0 }
        view.onItems = onItems
    }
}

@MainActor
final class ShelfDropHostingView: NSHostingView<AnyView> {
    var onTargeted: ((Bool) -> Void)?
    var onItems: (([FileShelfDropItem]) -> Void)?

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        registerForDraggedTypes(TransferPasteboard.shelfDropTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let accepts = sender.draggingPasteboard.availableType(from: TransferPasteboard.shelfDropTypes) != nil
        onTargeted?(accepts)
        return accepts ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { onTargeted?(false) }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onTargeted?(false)
        let items = TransferPasteboard.readShelfDropItems(from: sender.draggingPasteboard)
        guard !items.isEmpty else { return false }
        onItems?(items)
        return true
    }
}

extension View {
    func shelfDropTarget(
        isTargeted: Binding<Bool>,
        onItems: @escaping ([FileShelfDropItem]) -> Void
    ) -> some View {
        ShelfDropTarget(isTargeted: isTargeted, onItems: onItems, content: self)
    }
}
