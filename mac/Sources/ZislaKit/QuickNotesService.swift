import Combine
import Foundation

/// 随记模块的视图模型：以系统「备忘录」为唯一数据源。
///
/// 笔记列表来自 `NotesAppBridge.listNotes()`；选中某条后用 `readNote` 读取文本与原始 HTML。
/// Markdown 笔记可编辑并防抖写回，原生富内容只预览，防止写回时丢失表格和附件。
///
/// 不再做本地 JSON 持久化——备忘录即存储后端，避免双份数据与同步问题。
@MainActor
public final class QuickNotesService: ObservableObject {
    public static let welcomeNoteTitle = "朋友，看这里。"

    @Published public private(set) var notes: [NotesAppBridge.NoteSummary] = []
    @Published public var selectedID: String?
    @Published public private(set) var isLoadingList = false
    @Published public private(set) var isLoadingNote = false
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?

    private var saveTask: Task<Void, Never>?

    public init() {}

    public var selectedNote: NotesAppBridge.NoteSummary? {
        guard let selectedID else { return notes.first }
        return notes.first { $0.id == selectedID } ?? notes.first
    }

    public var welcomeNote: NotesAppBridge.NoteSummary? {
        Self.welcomeNote(in: notes)
    }

    public var regularNotes: [NotesAppBridge.NoteSummary] {
        Self.regularNotes(in: notes)
    }

    static func welcomeNote(in notes: [NotesAppBridge.NoteSummary]) -> NotesAppBridge.NoteSummary? {
        notes.first { $0.title == welcomeNoteTitle }
    }

    static func regularNotes(in notes: [NotesAppBridge.NoteSummary]) -> [NotesAppBridge.NoteSummary] {
        guard let welcomeNote = welcomeNote(in: notes) else { return notes }
        return notes.filter { $0.id != welcomeNote.id }
    }

    /// 重新拉取备忘录笔记列表；若当前选中项已不存在则回退到第一条。
    public func refresh() async {
        isLoadingList = true
        errorMessage = nil
        let result = await NotesAppBridge.listNotes()
        isLoadingList = false
        switch result {
        case .success(let fetched):
            applyFetchedNotes(fetched)
        case .failure(let error):
            errorMessage = error.message
        }
    }

    /// 用外部列表结果更新本地状态（供测试与 `refresh` 共用）。
    /// 当前选中项若已不在列表中（例如在备忘录 App 中被删除），回退到第一条或清空。
    func applyFetchedNotes(_ fetched: [NotesAppBridge.NoteSummary]) {
        notes = fetched.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
        if selectedID == nil || !notes.contains(where: { $0.id == selectedID }) {
            selectedID = notes.first?.id
        }
    }

    public func select(id: String) {
        guard notes.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// 读取当前选中笔记，供编辑器和预览载入。
    public func loadNote() async -> NotesAppBridge.NoteContent? {
        guard let id = selectedID else { return nil }
        isLoadingNote = true
        let result = await NotesAppBridge.readNote(id: id)
        isLoadingNote = false
        switch result {
        case .success(let content):
            return await normalizeWelcomeNoteIfNeeded(content, id: id)
        case .failure(let error):
            errorMessage = error.message
            return nil
        }
    }

    /// 防抖写回：停止输入 0.8 秒后落盘到备忘录，避免每次按键都触发 AppleScript。
    public func scheduleSave(id: String, markdown: String) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            if Task.isCancelled { return }
            await self?.performSave(id: id, markdown: markdown)
        }
    }

    /// 取消尚未落盘的写回（例如切换笔记前）。
    public func cancelPendingSave() {
        saveTask?.cancel()
        saveTask = nil
    }

    private func performSave(id: String, markdown: String) async {
        isSaving = true
        let result = await NotesAppBridge.writeNote(id: id, markdown: markdown)
        isSaving = false
        switch result {
        case .success:
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index] = NotesAppBridge.NoteSummary(
                    id: id,
                    title: notes[index].title,
                    modifiedAt: Date()
                )
            }
        case .failure(let error):
            errorMessage = error.message
        }
    }

    /// 在备忘录新建一条笔记并刷新列表、选中它。
    @discardableResult
    public func create(markdown: String = "# 新随记\n") async -> Bool {
        let title = Self.title(for: markdown)
        isSaving = true
        let result = await NotesAppBridge.createNote(title: title, markdown: markdown)
        isSaving = false
        switch result {
        case .success:
            await refresh()
            return true
        case .failure(let error):
            errorMessage = error.message
            return false
        }
    }

    /// 删除备忘录中的指定笔记并刷新列表。
    public func delete(id: String) async {
        let result = await NotesAppBridge.deleteNote(id: id)
        if case .failure(let error) = result {
            errorMessage = error.message
        }
        await refresh()
    }

    /// 取 Markdown 首行（去掉 `#` 前缀）作为笔记标题。
    public static func title(for markdown: String) -> String {
        let firstLine = markdown
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            ?? ""
        let stripped = firstLine
            .replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? "新随记" : stripped
    }

    static func normalizedWelcomeText(_ text: String) -> String {
        let withoutInvisibleWhitespace = text.replacingOccurrences(of: "\u{00A0}", with: "")
        let withoutChineseSpacing = withoutInvisibleWhitespace.replacingOccurrences(
            of: #"(?<=[\p{Han}])[\p{Zs}\t]+(?=[\p{Han}])"#,
            with: "",
            options: .regularExpression
        )
        var normalizedLines: [String] = []
        var previousLineWasEmpty = false
        for line in withoutChineseSpacing.components(separatedBy: .newlines) {
            let isEmpty = line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if isEmpty {
                guard !normalizedLines.isEmpty, !previousLineWasEmpty else { continue }
                normalizedLines.append("")
            } else {
                normalizedLines.append(line)
            }
            previousLineWasEmpty = isEmpty
        }
        while normalizedLines.last?.isEmpty == true {
            normalizedLines.removeLast()
        }
        return normalizedLines.joined(separator: "\n")
    }

    private func normalizeWelcomeNoteIfNeeded(
        _ content: NotesAppBridge.NoteContent,
        id: String
    ) async -> NotesAppBridge.NoteContent {
        guard welcomeNote?.id == id else { return content }
        let normalized = Self.normalizedWelcomeText(content.plainText)
        guard normalized != content.plainText else { return content }

        isSaving = true
        let result = await NotesAppBridge.writeNote(id: id, markdown: normalized)
        isSaving = false
        switch result {
        case .success:
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index] = NotesAppBridge.NoteSummary(
                    id: id,
                    title: notes[index].title,
                    modifiedAt: Date()
                )
            }
        case .failure(let error):
            errorMessage = error.message
        }
        return NotesAppBridge.NoteContent(plainText: normalized, bodyHTML: content.bodyHTML)
    }
}
