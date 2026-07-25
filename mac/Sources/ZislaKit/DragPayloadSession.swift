import AppKit
import UniformTypeIdentifiers

struct DragPayloadSnapshot: Equatable, Sendable {
    var changeCount: Int
    var itemTypeIdentifiers: [[String]]

    var hasSupportedTransferPayload: Bool {
        itemTypeIdentifiers.contains { identifiers in
            identifiers.contains { identifier in
                guard let type = UTType(identifier) else { return false }
                return type.conforms(to: .fileURL)
                    || type.conforms(to: .url)
                    || type.conforms(to: .plainText)
            }
        }
    }

    @MainActor
    init(pasteboard: NSPasteboard) {
        changeCount = pasteboard.changeCount
        itemTypeIdentifiers = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.map(\.rawValue)
        }
    }

    init(changeCount: Int, itemTypeIdentifiers: [[String]]) {
        self.changeCount = changeCount
        self.itemTypeIdentifiers = itemTypeIdentifiers
    }
}

struct DragPayloadSessionClassifier: Equatable, Sendable {
    private var completedChangeCount: Int
    private var activeChangeCount: Int?

    init(initialChangeCount: Int) {
        completedChangeCount = initialChangeCount
    }

    mutating func reset(initialChangeCount: Int) {
        completedChangeCount = initialChangeCount
        activeChangeCount = nil
    }

    mutating func prepareForPointerDrag() {
        if let activeChangeCount {
            completedChangeCount = activeChangeCount
        }
        activeChangeCount = nil
    }

    mutating func inspect(_ snapshot: DragPayloadSnapshot) -> Bool {
        guard snapshot.hasSupportedTransferPayload else {
            activeChangeCount = nil
            return false
        }
        if activeChangeCount == snapshot.changeCount {
            return true
        }
        guard snapshot.changeCount != completedChangeCount else { return false }
        activeChangeCount = snapshot.changeCount
        return true
    }

    mutating func finish(with snapshot: DragPayloadSnapshot) {
        finish(changeCount: snapshot.changeCount)
    }

    mutating func finish(changeCount: Int) {
        completedChangeCount = changeCount
        activeChangeCount = nil
    }
}
