import Foundation

/// Clipboard file item: stores the file URL, display name, and a security-scoped bookmark,
/// following FileShelfStore's bookmark approach to allow reading and writing sandbox-external
/// files after a restart.
public struct ClipboardFileReference: Codable, Sendable {
    public var url: URL
    public var displayName: String
    public var bookmark: Data

    public init(url: URL, displayName: String, bookmark: Data) {
        self.url = url.standardizedFileURL
        self.displayName = displayName
        self.bookmark = bookmark
    }

    static func makeBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }
}

/// File items are compared by standardized path: the same file is treated as a duplicate even if
/// the bookmark or display name differs, so deduplication and the existing UI flow of
/// "pin-to-top on copy by content" both work correctly.
extension ClipboardFileReference: Equatable {
    public static func == (lhs: ClipboardFileReference, rhs: ClipboardFileReference) -> Bool {
        lhs.url.standardizedFileURL == rhs.url.standardizedFileURL
    }
}

public enum ClipboardHistoryContent: Codable, Equatable, Sendable {
    case text(String)
    case image(Data)
    case file(ClipboardFileReference)

    public var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    public var isFile: Bool {
        if case .file = self { return true }
        return false
    }

    public var previewText: String {
        switch self {
        case .text(let value):
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:
            "图片"
        case .file(let reference):
            reference.displayName
        }
    }

    var isStorable: Bool {
        switch self {
        case .text(let value):
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image(let data):
            !data.isEmpty
        case .file(let reference):
            !reference.bookmark.isEmpty && !reference.displayName.isEmpty
        }
    }

    /// Constructs a file-item content from a file URL: validates existence and generates a bookmark (throws on failure).
    /// Intended to be called by UI/AppModel directly after a file picker selection.
    public static func file(at url: URL) throws -> ClipboardHistoryContent {
        let normalized = url.standardizedFileURL
        guard normalized.isFileURL else {
            throw ClipboardHistoryContentError.notAFileURL(url)
        }
        guard FileManager.default.fileExists(atPath: normalized.path) else {
            throw ClipboardHistoryContentError.fileMissing(normalized)
        }
        let bookmark = try ClipboardFileReference.makeBookmark(for: normalized)
        return .file(ClipboardFileReference(
            url: normalized,
            displayName: normalized.lastPathComponent,
            bookmark: bookmark
        ))
    }
}

public enum ClipboardHistoryContentError: LocalizedError {
    case notAFileURL(URL)
    case fileMissing(URL)

    public var errorDescription: String? {
        switch self {
        case .notAFileURL:
            "该项目不是文件"
        case .fileMissing(let url):
            "文件不存在：\(url.lastPathComponent)"
        }
    }
}

public enum ClipboardHistoryScope: Sendable {
    case all
    case pinned
    case history
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
