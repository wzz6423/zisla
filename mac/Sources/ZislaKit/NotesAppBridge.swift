import AppKit
import Foundation

/// 与系统「备忘录」App 的集成：随记模块以备忘录为数据源，支持列出、查看、编辑、
/// 新建、删除其中已有的笔记。
///
/// 备忘录没有公开 Swift API，统一通过 AppleScript/JXA 操作：
/// - `listNotes` 用 JXA（`osascript -l JavaScript`）返回 JSON，避免解析 AppleScript 记录描述符；
/// - `readNote`/`writeNote`/`createNote`/`deleteNote` 用 `NSAppleScript`（进程内、TCC 归属正确）。
///
/// Zisla 新建/更新的笔记把 Markdown 原文按普通文本行写入备忘录 body（每行一个
/// `<div>`，空行为 `<div><br></div>`，并转义 `&<>`），在备忘录 App 中显示为普通文本
/// 而非预格式化代码块；读取时用 `plaintext` 回读源文继续编辑。已有的原生备忘录则
/// 同时保留 `body` HTML，避免表格和附件在转换成纯文本后丢失。历史以 `<pre>` 存储
/// 的 Zisla 笔记仍可识别并编辑。
///
/// 首次调用时 macOS 会弹出自动化授权弹窗，要求允许 Zisla 控制「备忘录」。
public enum NotesAppError: Error, Sendable, Equatable {
    case failed(String)

    public var message: String {
        if case .failed(let value) = self { return value }
        return "未知错误"
    }
}

@MainActor
public enum NotesAppBridge {
    /// 备忘录中一条笔记的摘要。
    public struct NoteSummary: Identifiable, Sendable, Equatable, Hashable {
        public let id: String
        public let title: String
        public let modifiedAt: Date?

        public init(id: String, title: String, modifiedAt: Date?) {
            self.id = id
            self.title = title
            self.modifiedAt = modifiedAt
        }
    }

    /// 笔记的可编辑文本和原始 HTML。含结构化内容的原生笔记只预览，避免纯文本写回破坏附件。
    public struct NoteContent: Sendable, Equatable {
        public let plainText: String
        public let bodyHTML: String
        public let usesNativeHTML: Bool

        public init(plainText: String, bodyHTML: String) {
            self.plainText = plainText
            self.bodyHTML = bodyHTML
            usesNativeHTML = Self.requiresNativePreview(bodyHTML)
        }

        private static func requiresNativePreview(_ bodyHTML: String) -> Bool {
            guard !isMarkdownStorage(bodyHTML) else { return false }
            let lowercased = bodyHTML.lowercased()
            return ["<table", "<img", "<figure", "<video", "<audio", "<object", "<iframe", "attachment"]
                .contains { lowercased.contains($0) }
        }

        private static func isMarkdownStorage(_ bodyHTML: String) -> Bool {
            let trimmed = bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("<pre>"), trimmed.hasSuffix("</pre>") else { return false }
            let content = trimmed.dropFirst("<pre>".count).dropLast("</pre>".count)
            return !content.contains("</pre>")
        }
    }

    // MARK: - 最近删除过滤

    /// 已知各系统语言下「最近删除」文件夹的本地化名称。
    /// 备忘录没有公开 API 直接识别该系统文件夹，通过名称匹配作为最可靠的跨语言方案。
    public static let recentlyDeletedFolderNames: Set<String> = [
        "Recently Deleted",          // en
        "最近删除",                    // zh-Hans
        "最近刪除",                    // zh-Hant
        "Kürzlich gelöscht",         // de
        "Supprimés récemment",       // fr
        "Eliminados recientemente",  // es
        "Eliminati di recente",      // it
        "Recentelijk verwijderd",    // nl
        "Nyligen raderade",          // sv
        "Недавно удалённые",         // ru
        "最近削除した項目",              // ja
        "최근 삭제된 항목",              // ko
    ]

    /// 判断笔记的容器文件夹名是否为系统「最近删除」文件夹，兼容多语言系统。
    /// 这是可测的纯逻辑 seam，供 `parseSummaries` 和单元测试共用。
    public static func isInRecentlyDeletedFolder(_ containerName: String) -> Bool {
        recentlyDeletedFolderNames.contains(containerName)
    }

    // MARK: - 列出（JXA → JSON）

    /// 获取备忘录中全部笔记的摘要（id / 标题 / 修改时间），按原顺序返回；排序由调用方处理。
    /// 已自动排除「最近删除」文件夹中的笔记，兼容多语言系统。
    public static func listNotes() async -> Result<[NoteSummary], NotesAppError> {
        let script = #"""
        (() => {
          const Notes = Application('Notes');
          const out = [];
          const notes = Notes.notes();
          for (const n of notes) {
            let modified = null;
            var container = null;
            try { const d = n.modificationDate(); if (d) modified = d.getTime(); } catch (e) {}
            try { container = n.container().name(); } catch (e) {}
            out.push({ id: String(n.id()), title: String(n.name()), modified: modified, container: container });
          }
          return JSON.stringify(out);
        })()
        """#
        switch await runJXA(script) {
        case .success(let json):
            if let summaries = parseSummaries(json) {
                return .success(summaries)
            }
            return .failure(.failed("解析备忘录列表失败"))
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - 读取

    public static func readNote(id: String) async -> Result<NoteContent, NotesAppError> {
        let script = """
        tell application "Notes"
            set n to (note id \(escapeForAppleScript(id)))
            return {plaintext of n, body of n}
        end tell
        """
        switch await runAppleScriptReturningStrings(script) {
        case .success(let values):
            guard values.count == 2 else {
                return .failure(.failed("读取备忘录内容失败"))
            }
            return .success(NoteContent(plainText: values[0], bodyHTML: values[1]))
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - 编辑（写回 body）

    public static func writeNote(id: String, markdown: String) async -> Result<Void, NotesAppError> {
        let html = bodyHTML(for: markdown)
        let script = """
        tell application "Notes"
            set n to (note id \(escapeForAppleScript(id)))
            set body of n to \(escapeForAppleScript(html))
        end tell
        """
        return await runAppleScriptVoid(script)
    }

    // MARK: - 新建

    public static func createNote(title: String, markdown: String) async -> Result<Void, NotesAppError> {
        let html = bodyHTML(for: markdown)
        let script = """
        tell application "Notes"
            make new note with properties {name:\(escapeForAppleScript(title)), body:\(escapeForAppleScript(html))}
        end tell
        """
        return await runAppleScriptVoid(script)
    }

    // MARK: - 删除

    public static func deleteNote(id: String) async -> Result<Void, NotesAppError> {
        let script = """
        tell application "Notes"
            set n to (note id \(escapeForAppleScript(id)))
            delete n
        end tell
        """
        return await runAppleScriptVoid(script)
    }

    // MARK: - 打开备忘录

    public static func openNotes() {
        if let url = URL(string: "mobilenotes://") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
        }
    }

    // MARK: - 存储格式

    /// 把 Markdown 原文转成备忘录 body 用的 HTML：按行拆成普通 `<div>` 段落并转义 `&<>`。
    /// 与备忘录原生纯文本笔记一致，避免 `<pre>` 的等宽预格式化样式；读取 `plaintext`
    /// 时 Notes 会按段落还原换行，随记编辑器仍得到 Markdown 源文本。
    public static func bodyHTML(for markdown: String) -> String {
        if markdown.isEmpty { return "" }
        return markdown
            .components(separatedBy: "\n")
            .map { line -> String in
                if line.isEmpty { return "<div><br></div>" }
                let escaped = line
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                return "<div>\(escaped)</div>"
            }
            .joined()
    }

    // MARK: - 执行

    /// 在后台线程运行 JXA（`osascript -l JavaScript`），返回标准输出文本。
    private static func runJXA(_ script: String) async -> Result<String, NotesAppError> {
        await Task.detached(priority: .userInitiated) { () -> Result<String, NotesAppError> in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-l", "JavaScript", "-e", script]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                return .failure(.failed("无法启动 osascript：\(error.localizedDescription)"))
            }
            process.waitUntilExit()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus != 0 {
                let message = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "备忘录访问失败"
                return .failure(.failed(message))
            }
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .success(output)
        }.value
    }

    /// 进程内执行 AppleScript，返回字符串列表（用于同时读取 plaintext 与 body）。
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
                return .failure(.failed("备忘录没有返回内容"))
            }
            let itemCount = descriptor.numberOfItems
            guard itemCount > 0 else {
                return .failure(.failed("备忘录返回了无效内容"))
            }
            return .success((1...itemCount).map {
                descriptor.atIndex($0)?.stringValue ?? ""
            })
        }.value
    }

    /// 进程内执行 AppleScript，无返回值。
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

    // MARK: - 工具

    static func parseSummaries(_ json: String) -> [NoteSummary]? {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return array.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            // 排除「最近删除」文件夹中的笔记（用户在备忘录删除后进入该文件夹，但 Notes.notes() 仍会返回它们）
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
            return NoteSummary(id: id, title: title, modifiedAt: modifiedAt)
        }
    }

    /// 转义 AppleScript 字符串字面量中的 `\` 与 `"`。
    private static func escapeForAppleScript(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private extension NotesAppError {
    static func failureMessage(from errorInfo: NSDictionary) -> NotesAppError {
        let message = (errorInfo[NSAppleScript.errorMessage] as? String)
            ?? (errorInfo[NSLocalizedDescriptionKey] as? String)
            ?? "备忘录操作失败，请检查自动化授权"
        return .failed(message)
    }
}
