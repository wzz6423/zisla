import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum TransferDropItem: Hashable, Sendable {
    case file(URL)
    case link(URL)
    case text(String)
    case image(Data)

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
        for provider in providers {
            load(provider, into: loader)
        }
        return true
    }

    private func load(_ provider: NSItemProvider, into loader: TransferDropLoader) {
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
            loader.finish(with: Self.dropItem(from: value))
        }
    }

    nonisolated private static func dropItem(from value: NSSecureCoding?) -> TransferDropItem? {
        let url: URL?
        if let value = value as? URL {
            url = value
        } else if let value = value as? NSURL {
            url = value as URL
        } else if let data = value as? Data {
            url = URL(dataRepresentation: data, relativeTo: nil)
        } else {
            url = nil
        }

        if let url {
            return url.isFileURL ? .file(url) : .link(url)
        }

        if let data = value as? Data,
           let string = String(data: data, encoding: .utf8) {
            return textItem(from: string)
        }

        guard let string = (value as? String) ?? (value as? NSString).map({ String($0) }) else {
            return nil
        }
        return textItem(from: string)
    }

    nonisolated private static func textItem(from string: String) -> TransferDropItem? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased()) {
            return .link(url)
        }
        return trimmed.isEmpty ? nil : .text(trimmed)
    }
}

private final class TransferDropLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var items: [TransferDropItem] = []
    private let completion: @MainActor @Sendable ([TransferDropItem]) -> Void

    init(
        count: Int,
        completion: @escaping @MainActor @Sendable ([TransferDropItem]) -> Void
    ) {
        remaining = count
        self.completion = completion
    }

    func finish(with item: TransferDropItem?) {
        lock.lock()
        if let item { items.append(item) }
        remaining -= 1
        let result = remaining == 0 ? items : nil
        lock.unlock()

        guard let result else { return }
        Task { @MainActor [completion] in
            completion(result)
        }
    }
}
