import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZislaCore

/// Integration with the system Notes app: the Quick Note module uses Notes as its data source,
/// supporting list, view, edit, create, and delete operations on existing notes.
///
/// Notes has no public Swift API; all operations go through AppleScript/JXA:
/// - `listNotes` uses JXA (`osascript -l JavaScript`) to return JSON, avoiding AppleScript record descriptor parsing;
/// - `readNote`/`writeNote`/`createNote`/`deleteNote` use `NSAppleScript` (in-process, correct TCC attribution).
///
/// Zisla reads and writes the `body` HTML of notes directly. Legacy Markdown notes are migrated to
/// rich text by the UI on first edit; existing native HTML is loaded as-is to avoid downgrading
/// tables and embedded images to plain text in the read/write pipeline.
///
/// On the first call, macOS will present an automation permission dialog asking the user to allow
/// Zisla to control Notes.
public enum NotesAppError: Error, Sendable, Equatable {
    case failed(String)

    public var message: String {
        if case .failed(let value) = self { return value }
        return "未知错误"
    }
}

@MainActor
public enum NotesAppBridge {
    /// Summary of a single note in Notes.
    public struct NoteSummary: Identifiable, Sendable, Equatable, Hashable {
        public let id: String
        public let title: String
        public let modifiedAt: Date?
        public let isPasswordProtected: Bool

        public init(
            id: String,
            title: String,
            modifiedAt: Date?,
            isPasswordProtected: Bool = false
        ) {
            self.id = id
            self.title = title
            self.modifiedAt = modifiedAt
            self.isPasswordProtected = isPasswordProtected
        }
    }

    /// A native attachment from Notes, including inline data when Notes exposes a local file.
    public struct NoteAttachment: Identifiable, Sendable, Equatable, Hashable {
        public let id: String
        public let name: String
        public let contentIdentifier: String
        public let url: String
        public let dataURL: String?

        public init(
            id: String,
            name: String,
            contentIdentifier: String,
            url: String,
            dataURL: String? = nil
        ) {
            self.id = id
            self.name = name
            self.contentIdentifier = contentIdentifier
            self.url = url
            self.dataURL = dataURL
        }
    }

    /// Editable text, raw HTML, and read-only metadata for a note.
    public struct NoteContent: Sendable, Equatable {
        public let plainText: String
        public let bodyHTML: String
        public let usesNativeHTML: Bool
        public let isPasswordProtected: Bool
        public let tags: [String]
        public let attachments: [NoteAttachment]

        public init(
            plainText: String,
            bodyHTML: String,
            isPasswordProtected: Bool = false,
            attachments: [NoteAttachment] = []
        ) {
            self.plainText = plainText
            self.bodyHTML = bodyHTML
            usesNativeHTML = !Self.isMarkdownStorage(bodyHTML)
            self.isPasswordProtected = isPasswordProtected
            tags = NotesAppBridge.tags(in: plainText)
            self.attachments = attachments
        }

        public var hasReadOnlyMetadata: Bool {
            isPasswordProtected || !tags.isEmpty || !attachments.isEmpty
        }

        private static func isMarkdownStorage(_ bodyHTML: String) -> Bool {
            let trimmed = bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("<pre>"), trimmed.hasSuffix("</pre>") else { return false }
            let content = trimmed.dropFirst("<pre>".count).dropLast("</pre>".count)
            return !content.contains("</pre>")
        }
    }

    // MARK: - Recently Deleted filtering

    /// Known localized names of the "Recently Deleted" folder across system languages.
    /// Notes has no public API to identify this system folder directly; name matching is the most reliable cross-language approach.
    public static let recentlyDeletedFolderNames: Set<String> = [
        "Recently Deleted",          // en
        "最近删除",                    // Simplified Chinese
        "最近刪除",                    // Traditional Chinese
        "Kürzlich gelöscht",         // de
        "Supprimés récemment",       // fr
        "Eliminados recientemente",  // es
        "Eliminati di recente",      // it
        "Recentelijk verwijderd",    // nl
        "Nyligen raderade",          // sv
        "Недавно удалённые",         // ru
        "最近削除した項目",              // Japanese
        "최근 삭제된 항목",              // ko
    ]

    /// Returns whether a note's container folder name is the system "Recently Deleted" folder, supporting multilingual systems.
    /// Pure-logic seam that is testable in isolation; shared by `parseSummaries` and unit tests.
    public static func isInRecentlyDeletedFolder(_ containerName: String) -> Bool {
        recentlyDeletedFolderNames.contains(containerName)
    }

    // MARK: - List (JXA → JSON)

    /// Returns summaries (id / title / modification date) for all notes in Notes, in original order; sorting is the caller's responsibility.
    /// Notes in the "Recently Deleted" folder are automatically excluded, across all system languages.
    public static func listNotes() async -> Result<[NoteSummary], NotesAppError> {
        let script = #"""
        (() => {
          const Notes = Application('Notes');
          const out = [];
          const notes = Notes.notes();
          for (const n of notes) {
            var modified = null;
            var passwordProtected = false;
            var container = null;
            try { const d = n.modificationDate(); if (d) modified = d.getTime(); } catch (e) {}
            try { passwordProtected = Boolean(n.passwordProtected()); } catch (e) {}
            try { container = n.container().name(); } catch (e) {}
            out.push({ id: String(n.id()), title: String(n.name()), modified: modified, passwordProtected: passwordProtected, container: container });
          }
          return JSON.stringify(out);
        })()
        """#
        switch await runJXA(script) {
        case .success(let json):
            if let summaries = parseSummaries(json) {
                return .success(summaries)
            }
            return .failure(.failed(AppLocalization.text("解析备忘录列表失败")))
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Read

    public static func readNote(id: String) async -> Result<NoteContent, NotesAppError> {
        let script = """
        tell application "Notes"
            set n to (note id \(escapeForAppleScript(id)))
            return {plaintext of n, body of n, password protected of n}
        end tell
        """
        switch await runAppleScriptReturningStrings(script) {
        case .success(let values):
            guard values.count == 3 else {
                return .failure(.failed(AppLocalization.text("读取备忘录内容失败")))
            }
            let attachmentResult = await readAttachments(noteID: id)
            let attachments: [NoteAttachment]
            switch attachmentResult {
            case .success(let value): attachments = value
            case .failure: attachments = []
            }
            return .success(NoteContent(
                plainText: values[0],
                bodyHTML: values[1],
                isPasswordProtected: values[2].lowercased() == "true",
                attachments: attachments
            ))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Reads the lock state separately to avoid routing locked notes into the body-read or rich-text edit path.
    public static func isPasswordProtected(noteID: String) async -> Result<Bool, NotesAppError> {
        let script = """
        tell application "Notes"
            set n to (note id \(escapeForAppleScript(noteID)))
            return password protected of n
        end tell
        """
        switch await runAppleScriptReturningStrings(script) {
        case .success(let values):
            guard values.count == 1 else {
                return .failure(.failed(AppLocalization.text("读取备忘录锁定状态失败")))
            }
            return .success(["true", "1", "yes"].contains(values[0].lowercased()))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Reads attachment metadata and copies image attachments into data URLs for the editor.
    public static func readAttachments(noteID: String) async -> Result<[NoteAttachment], NotesAppError> {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-notes-attachments-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .failure(.failed(AppLocalization.text("无法准备备忘录附件")))
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        let directoryPath = escapeForAppleScript(directory.path)
        let script = """
        tell application "Notes"
            set n to (note id \(escapeForAppleScript(noteID)))
            set resultList to {}
            set attachmentIndex to 0
            repeat with a in (attachments of n)
                set attachmentIndex to attachmentIndex + 1
                set attachmentURL to ""
                try
                    set attachmentURL to URL of a as text
                end try
                set savedPath to ""
                try
                    set savedPath to \(directoryPath) & "/attachment-" & (attachmentIndex as text)
                    save a in POSIX file savedPath
                on error
                    set savedPath to ""
                end try
                set end of resultList to {id of a as text, name of a as text, content identifier of a as text, attachmentURL, savedPath}
            end repeat
        return resultList
        end tell
        """
        switch await runAppleScriptReturningStringLists(script) {
        case .success(let values):
            return .success(values.compactMap { value in
                guard value.count == 5, !value[0].isEmpty else { return nil }
                let dataURL = Self.dataURL(for: value[4], name: value[1])
                return NoteAttachment(
                    id: value[0],
                    name: value[1] == "missing value" ? "" : value[1],
                    contentIdentifier: value[2] == "missing value" ? "" : value[2],
                    url: value[3] == "missing value" ? "" : value[3],
                    dataURL: dataURL
                )
            })
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Edit (write back body)

    public static func writeNote(id: String, markdown: String) async -> Result<Void, NotesAppError> {
        await writeNote(id: id, html: bodyHTML(for: markdown))
    }

    /// Writes back rich-text HTML. Images are inlined as data URLs, so no temporary file paths are needed.
    public static func writeNote(id: String, html: String) async -> Result<Void, NotesAppError> {
        let script = """
        tell application "Notes"
            set n to (note id \(escapeForAppleScript(id)))
            set body of n to \(escapeForAppleScript(html))
        end tell
        """
        return await runAppleScriptVoid(script)
    }

    // MARK: - Create

    public static func createNote(title: String, markdown: String) async -> Result<Void, NotesAppError> {
        await createNote(title: title, html: bodyHTML(for: markdown))
    }

    /// Creates a note with a rich-text HTML body.
    public static func createNote(title: String, html: String) async -> Result<Void, NotesAppError> {
        let script = """
        tell application "Notes"
            make new note with properties {name:\(escapeForAppleScript(title)), body:\(escapeForAppleScript(html))}
        end tell
        """
        return await runAppleScriptVoid(script)
    }

    // MARK: - Delete

    public static func deleteNote(id: String) async -> Result<Void, NotesAppError> {
        let script = """
        tell application "Notes"
            set n to (note id \(escapeForAppleScript(id)))
            delete n
        end tell
        """
        return await runAppleScriptVoid(script)
    }

    // MARK: - Open Notes

    public static func openNotes() {
        if let url = URL(string: "mobilenotes://") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
        }
    }

    /// Shows the specified note in the system Notes app, e.g. to let the user unlock a password-protected note.
    public static func showNote(id: String) async -> Result<Void, NotesAppError> {
        let script = """
        tell application "Notes"
            show (note id \(escapeForAppleScript(id)))
            activate
        end tell
        """
        return await runAppleScriptVoid(script)
    }

    /// Shows an attachment in the system Notes app. Quick Note does not provide write, delete, or rename operations for attachments.
    public static func showAttachment(id: String) async -> Result<Void, NotesAppError> {
        let script = """
        tell application "Notes"
            show (attachment id \(escapeForAppleScript(id)))
            activate
        end tell
        """
        return await runAppleScriptVoid(script)
    }

    // MARK: - Storage format

    /// Converts Markdown source to the HTML format used for a Notes body: splits into plain `<div>` paragraphs and escapes `&<>`.
    /// Matches the format of native plain-text notes in Notes, avoiding the monospaced preformatted style of `<pre>`;
    /// when Notes returns `plaintext`, it reconstructs newlines from paragraphs so the Quick Note editor still receives Markdown source.
    /// Preserves leading whitespace (spaces and tabs) by converting them to non-breaking spaces.
    public static func bodyHTML(for markdown: String) -> String {
        if markdown.isEmpty { return "" }
        return markdown
            .components(separatedBy: "\n")
            .map { line -> String in
                if line.isEmpty { return "<div><br></div>" }

                // Count and preserve leading whitespace
                var leadingCount = 0
                for char in line {
                    if char == " " || char == "\t" {
                        leadingCount += 1
                    } else {
                        break
                    }
                }

                let content = String(line.dropFirst(leadingCount))
                let escaped = content
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")

                let leadingSpaces = leadingCount > 0 ? String(repeating: "&nbsp;", count: leadingCount) : ""
                return "<div>\(leadingSpaces)\(escaped)</div>"
            }
            .joined()
    }

    // MARK: - Execution

    /// Runs JXA (`osascript -l JavaScript`) on a background thread and returns stdout as text.
    private static func runJXA(_ script: String) async -> Result<String, NotesAppError> {
        do {
            let output = try await AIAgentProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-l", "JavaScript", "-e", script],
                timeout: 30,
                maximumOutputBytes: .max,
                maximumErrorBytes: 256 * 1024
            )
            if output.didTimeout {
                return .failure(.failed(AppLocalization.text("备忘录操作超时")))
            }
            if output.status != 0 {
                let message = output.standardError
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(.failed(message.isEmpty ? AppLocalization.text("备忘录访问失败") : message))
            }
            let text = String(data: output.standardOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .success(text)
        } catch {
            return .failure(.failed(AppLocalization.text("无法启动 osascript：%@", error.localizedDescription)))
        }
    }

    /// Runs AppleScript in-process and returns a list of strings (used to read plaintext and body simultaneously).
    private static func runAppleScriptReturningStrings(
        _ source: String
    ) async -> Result<[String], NotesAppError> {
        await Task.detached(priority: .userInitiated) { () -> Result<[String], NotesAppError> in
            let appleScript = NSAppleScript(source: source)
            var errorInfo: NSDictionary?
            let descriptor = appleScript?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                return .failure(.failureMessage(from: errorInfo))
            }
            guard let descriptor else {
                return .failure(.failed(AppLocalization.text("备忘录没有返回内容")))
            }
            let itemCount = descriptor.numberOfItems
            guard itemCount > 0 else {
                return .failure(.failed(AppLocalization.text("备忘录返回了无效内容")))
            }
            return .success((1...itemCount).map {
                descriptor.atIndex($0)?.stringValue ?? ""
            })
        }.value
    }

    /// Runs AppleScript in-process and returns a 2-D list of strings (used to read attachment metadata).
    private static func runAppleScriptReturningStringLists(
        _ source: String
    ) async -> Result<[[String]], NotesAppError> {
        await Task.detached(priority: .userInitiated) { () -> Result<[[String]], NotesAppError> in
            let appleScript = NSAppleScript(source: source)
            var errorInfo: NSDictionary?
            let descriptor = appleScript?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                return .failure(.failureMessage(from: errorInfo))
            }
            guard let descriptor else {
                return .failure(.failed(AppLocalization.text("备忘录没有返回附件")))
            }
            guard descriptor.numberOfItems > 0 else { return .success([]) }
            return .success((1...descriptor.numberOfItems).map { index in
                guard let item = descriptor.atIndex(index), item.numberOfItems > 0 else { return [] }
                return (1...item.numberOfItems).map { column in
                    item.atIndex(column)?.stringValue ?? ""
                }
            })
        }.value
    }

    /// Runs AppleScript in-process with no return value.
    private static func runAppleScriptVoid(
        _ source: String
    ) async -> Result<Void, NotesAppError> {
        await Task.detached(priority: .userInitiated) { () -> Result<Void, NotesAppError> in
            let appleScript = NSAppleScript(source: source)
            var errorInfo: NSDictionary?
            _ = appleScript?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                return .failure(.failureMessage(from: errorInfo))
            }
            return .success(())
        }.value
    }

    // MARK: - Utilities

    static func parseSummaries(_ json: String) -> [NoteSummary]? {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return array.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            // Exclude notes in the "Recently Deleted" folder (deleted notes land there but are still returned by Notes.notes())
            if let containerName = item["container"] as? String,
               isInRecentlyDeletedFolder(containerName) {
                return nil
            }
            let title = item["title"] as? String ?? ""
            var modifiedAt: Date?
            if let modified = item["modified"] as? Double, modified > 0 {
                modifiedAt = Date(timeIntervalSince1970: modified / 1000.0)
            } else if let modified = item["modified"] as? Int, modified > 0 {
                modifiedAt = Date(timeIntervalSince1970: TimeInterval(modified) / 1000.0)
            }
            return NoteSummary(
                id: id,
                title: title,
                modifiedAt: modifiedAt,
                isPasswordProtected: item["passwordProtected"] as? Bool ?? false
            )
        }
    }

    /// Extracts visible `#tags` from the note body. Notes has no public tag-metadata API,
    /// so tags that do not appear in the body text are not surfaced as readable content.
    nonisolated public static func tags(in plainText: String) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}_])#([\p{L}\p{N}_-]+)"#
        ) else { return [] }
        let source = plainText as NSString
        let range = NSRange(location: 0, length: source.length)
        var seen = Set<String>()
        return expression.matches(in: plainText, range: range).compactMap { match in
            let tag = source.substring(with: match.range(at: 1))
            let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted ? tag : nil
        }
    }

    /// Escapes `\` and `"` in an AppleScript string literal.
    private static func escapeForAppleScript(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func dataURL(for path: String, name: String) -> String? {
        guard !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              !data.isEmpty else { return nil }
        let fileExtension = (name as NSString).pathExtension
        let type = (!fileExtension.isEmpty ? UTType(filenameExtension: fileExtension) : nil)
            ?? imageType(for: data)
        guard type?.conforms(to: .image) == true else { return nil }
        let mimeType = type?.preferredMIMEType ?? "application/octet-stream"
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private static func imageType(for data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String? else { return nil }
        return UTType(identifier)
    }
}

private extension NotesAppError {
    static func failureMessage(from errorInfo: NSDictionary) -> NotesAppError {
        let message = (errorInfo[NSAppleScript.errorMessage] as? String)
            ?? (errorInfo[NSLocalizedDescriptionKey] as? String)
            ?? AppLocalization.text("备忘录操作失败，请检查自动化授权")
        return .failed(message)
    }
}
