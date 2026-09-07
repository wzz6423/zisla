import Foundation
import UniformTypeIdentifiers
import ZislaCore

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
            AppLocalization.text("文件不存在：%@", url.lastPathComponent)
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

    public func lastCopiedAtText(now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone

        if calendar.isDate(lastCopiedAt, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm:ss"
        } else if calendar.component(.year, from: lastCopiedAt) == calendar.component(.year, from: now) {
            formatter.dateFormat = "MM-dd HH:mm:ss"
        } else {
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        }
        return formatter.string(from: lastCopiedAt)
    }

    public var category: FileShelfCategory {
        switch content {
        case .text(let value):
            if HTTPURLParser.url(from: value) != nil {
                return .url
            }
            return isLocalFilePath(value) ? .path : .text
        case .image:
            return .image
        case .file(let reference):
            return categoryForFile(url: reference.url)
        }
    }

    private func isLocalFilePath(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isNewline }) else { return false }
        if trimmed == "~" || trimmed.hasPrefix("~/") || trimmed.hasPrefix("/") {
            return true
        }
        guard let url = URL(string: trimmed), url.isFileURL else { return false }
        return !url.path.isEmpty
    }

    private func categoryForFile(url: URL) -> FileShelfCategory {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return .folder
        }

        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return .other
        }

        if contentType.conforms(to: .image) {
            return .image
        } else if contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
            return .video
        } else if contentType.conforms(to: .audio) {
            return .audio
        } else if contentType.conforms(to: .archive) || contentType.conforms(to: .zip) {
            return .archive
        } else if contentType.conforms(to: .sourceCode) || contentType.conforms(to: .script) {
            return .code
        } else if contentType.conforms(to: .text) || contentType.conforms(to: .pdf) ||
                  contentType.conforms(to: .spreadsheet) || contentType.conforms(to: .presentation) {
            return .document
        }

        return .other
    }
}
