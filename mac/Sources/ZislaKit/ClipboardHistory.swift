import Foundation

public enum ClipboardHistoryContent: Codable, Equatable, Sendable {
    case text(String)
    case image(Data)

    public var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    public var previewText: String {
        switch self {
        case .text(let value):
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:
            "图片"
        }
    }

    var isStorable: Bool {
        switch self {
        case .text(let value):
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image(let data):
            !data.isEmpty
        }
    }
}

public struct ClipboardHistoryItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var content: ClipboardHistoryContent
    public var lastCopiedAt: Date
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        content: ClipboardHistoryContent,
        lastCopiedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.content = content
        self.lastCopiedAt = lastCopiedAt
        self.isPinned = isPinned
    }
}
