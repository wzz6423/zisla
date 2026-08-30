import Combine
import Foundation

/// View model for the Quick Notes module, backed by the system Notes app with one local welcome item.
///
/// The note list comes from `NotesAppBridge.listNotes()`; selecting a note reads its text and raw HTML via `readNote`.
/// Note bodies are edited as HTML rich text and written back with debouncing, preserving tables and embedded images.
///
/// Notes remains the storage backend for user content. The dismissible welcome item is local-only.
@MainActor
public final class QuickNotesService: ObservableObject {
    struct Operations {
        let listNotes: () async -> Result<[NotesAppBridge.NoteSummary], NotesAppError>
        let isPasswordProtected: (String) async -> Result<Bool, NotesAppError>
        let readNote: (String) async -> Result<NotesAppBridge.NoteContent, NotesAppError>
        let writeNote: (String, String) async -> Result<Void, NotesAppError>
        let deleteNote: (String) async -> Result<Void, NotesAppError>
    }

    public static let welcomeNoteTitle = "朋友，看这里。"
    private static let builtInWelcomeNoteID = "zisla.builtin.quick-notes-welcome"
    private static let welcomeDismissedDefaultsKey = "QuickNotesService.isBuiltInWelcomeNoteDismissed"
    private static let welcomeNoteResourcePath = "QuickNotes/welcome-note.md"
    private static let fallbackWelcomeNoteText = """
    从现在开始，你可以在记事本中写记事了。 那么，你都能做些什么呢？
    记忆力并不是智慧，但没有记忆力还成什么智慧呢？
    ——哈柏

    科学证明人脑的记忆力是有限的，但生活中接收并需要记下的信息可太多了，真是糟糕。 不过现在，你不用担心了。随时随地在记事本写上一笔，并设置日历提醒，事情不再错过。 “记忆力并不是智慧”，但灵活地使用记事本，拓展你的记忆，正是你的机智所在。 读书感悟、生活体验、团队计划等等，你都可以放进记事本里。 挑出重要的记事并加上星标吧，让它们像这篇使用说明一样显眼。 已完成的记事，你还可以将它们一键分享到微信、QQ等，或者直接通过邮件发送，便捷而高效。 记事本，记录点滴生活。

    愿你能愉快而轻松地使用这个小工具~
    """
    @Published public private(set) var notes: [NotesAppBridge.NoteSummary] = []
    @Published public var selectedID: String? {
        didSet {
            guard oldValue != selectedID else { return }
            noteLoadID = nil
            noteLoadGeneration &+= 1
            isLoadingNote = false
        }
    }
    @Published public private(set) var isLoadingList = false
    @Published public private(set) var isLoadingNote = false
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?

    private var saveTasksByID: [String: Task<Void, Never>] = [:]
    private let welcomeDismissalDefaults: UserDefaults
    private let operations: Operations
    private let saveDelay: Duration
    private var refreshGeneration = 0
    private var noteLoadGeneration = 0
    private var noteLoadID: String?
    private var activeNoteLoadsByGeneration: [Int: Int] = [:]
    private var saveGenerationByID: [String: Int] = [:]
    private var activeSaveGenerationByID: [String: Int] = [:]
    private var activeSaveTasksByID: [String: Task<Void, Never>] = [:]
    private var pendingSaveByID: [String: (generation: Int, html: String)] = [:]
    private var deletingNoteIDs: Set<String> = []

    public init(welcomeDismissalDefaults: UserDefaults = .standard) {
        operations = Operations(
            listNotes: { await NotesAppBridge.listNotes() },
            isPasswordProtected: { await NotesAppBridge.isPasswordProtected(noteID: $0) },
            readNote: { await NotesAppBridge.readNote(id: $0) },
            writeNote: { id, html in await NotesAppBridge.writeNote(id: id, html: html) },
            deleteNote: { await NotesAppBridge.deleteNote(id: $0) }
        )
        self.welcomeDismissalDefaults = welcomeDismissalDefaults
        saveDelay = .milliseconds(800)
    }

    init(
        welcomeDismissalDefaults: UserDefaults,
        operations: Operations,
        saveDelay: Duration = .milliseconds(800)
    ) {
        self.welcomeDismissalDefaults = welcomeDismissalDefaults
        self.operations = operations
        self.saveDelay = saveDelay
    }

    public var selectedNote: NotesAppBridge.NoteSummary? {
        guard let selectedID else { return notes.first }
        if isBuiltInWelcomeNote(id: selectedID) {
            return welcomeNote
        }
        return notes.first { $0.id == selectedID } ?? notes.first
    }

    public var welcomeNote: NotesAppBridge.NoteSummary? {
        guard !welcomeDismissalDefaults.bool(forKey: Self.welcomeDismissedDefaultsKey) else { return nil }
        return NotesAppBridge.NoteSummary(
            id: Self.builtInWelcomeNoteID,
            title: Self.welcomeNoteTitle,
            modifiedAt: nil
        )
    }

    public var regularNotes: [NotesAppBridge.NoteSummary] {
        notes
    }

    public var isBuiltInWelcomeNoteSelected: Bool {
        selectedID.map(isBuiltInWelcomeNote(id:)) ?? false
    }

    public func isBuiltInWelcomeNote(id: String) -> Bool {
        id == Self.builtInWelcomeNoteID
    }

    static var welcomeNoteText: String {
        let sourceResources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        let candidates = [Bundle.main.resourceURL, sourceResources].compactMap { $0 }
        for root in candidates {
            let url = root.appendingPathComponent(welcomeNoteResourcePath, isDirectory: false)
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                return text
            }
        }
        return fallbackWelcomeNoteText
    }

    /// Re-fetches the Notes note list; falls back to the first note if the currently selected item no longer exists.
    public func refresh() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isLoadingList = true
        errorMessage = nil
        let result = await operations.listNotes()
        guard refreshGeneration == generation else { return }
        isLoadingList = false
        switch result {
        case .success(let fetched):
            applyFetchedNotes(fetched)
        case .failure(let error):
            errorMessage = error.message
        }
    }

    /// Updates local state with an external list result (shared by tests and `refresh`).
    /// If the currently selected item is no longer in the list (e.g. deleted in the Notes app), falls back to the first item or clears selection.
    func applyFetchedNotes(_ fetched: [NotesAppBridge.NoteSummary]) {
        // Earlier versions used this reserved title for a generated system note. Leave the
        // system record untouched, but do not show it alongside the local replacement.
        notes = fetched
            .filter { $0.title != Self.welcomeNoteTitle }
            .sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
        guard let selectedID else {
            self.selectedID = welcomeNote?.id ?? notes.first?.id
            return
        }
        if isBuiltInWelcomeNote(id: selectedID) {
            if welcomeNote == nil {
                self.selectedID = notes.first?.id
            }
        } else if !notes.contains(where: { $0.id == selectedID }) {
            self.selectedID = notes.first?.id ?? welcomeNote?.id
        }
    }

    public func select(id: String) {
        guard (isBuiltInWelcomeNote(id: id) && welcomeNote != nil)
            || notes.contains(where: { $0.id == id })
        else { return }
        selectedID = id
    }

    /// Reads the currently selected note for the editor and preview to load.
    public func loadNote() async -> NotesAppBridge.NoteContent? {
        guard let id = selectedID else { return nil }
        let generation = beginNoteLoad(id: id)
        defer { finishNoteLoad(id: id, generation: generation) }
        if isBuiltInWelcomeNote(id: id) {
            return NotesAppBridge.NoteContent(
                plainText: Self.welcomeNoteText,
                bodyHTML: NotesAppBridge.bodyHTML(for: Self.welcomeNoteText)
            )
        }
        let protectionResult = await operations.isPasswordProtected(id)
        guard isCurrentNoteLoad(generation, id: id) else { return nil }
        if case .success(true) = protectionResult {
            return NotesAppBridge.NoteContent(
                plainText: "",
                bodyHTML: "",
                isPasswordProtected: true
            )
        }
        let result = await operations.readNote(id)
        guard isCurrentNoteLoad(generation, id: id) else { return nil }
        switch result {
        case .success(let content):
            return content
        case .failure(let error):
            errorMessage = error.message
            return nil
        }
    }

    /// Debounced write-back: flushes to Notes 0.8 seconds after input stops, avoiding an AppleScript call on every keystroke.
    public func scheduleSave(id: String, markdown: String) {
        scheduleSave(id: id, html: NotesAppBridge.bodyHTML(for: markdown))
    }

    /// Debounced write-back of rich-text body.
    public func scheduleSave(id: String, html: String) {
        guard !isBuiltInWelcomeNote(id: id), !deletingNoteIDs.contains(id) else { return }
        let generation = (saveGenerationByID[id] ?? 0) &+ 1
        saveGenerationByID[id] = generation
        if let oldTask = saveTasksByID[id] {
            oldTask.cancel()
            saveTasksByID.removeValue(forKey: id)
        }
        saveTasksByID[id] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.saveDelay)
            if Task.isCancelled { return }
            self.enqueueSave(id: id, html: html, generation: generation)
        }
    }

    /// Explicitly discards pending write-backs.
    public func cancelPendingSave() {
        let pendingIDs = Set(saveGenerationByID.keys)
            .union(saveTasksByID.keys)
            .union(pendingSaveByID.keys)
        for id in pendingIDs {
            invalidatePendingSave(for: id)
        }
    }

    private func invalidatePendingSave(for id: String) {
        saveGenerationByID[id] = (saveGenerationByID[id] ?? 0) &+ 1
        if let task = saveTasksByID.removeValue(forKey: id) {
            task.cancel()
        }
        pendingSaveByID.removeValue(forKey: id)
    }

    private func isCurrentNoteLoad(_ generation: Int, id: String) -> Bool {
        noteLoadGeneration == generation && noteLoadID == id && selectedID == id
    }

    private func beginNoteLoad(id: String) -> Int {
        if noteLoadID != id {
            noteLoadID = id
            noteLoadGeneration &+= 1
        }
        let generation = noteLoadGeneration
        activeNoteLoadsByGeneration[generation, default: 0] += 1
        isLoadingNote = true
        return generation
    }

    private func finishNoteLoad(id: String, generation: Int) {
        let remaining = max(0, (activeNoteLoadsByGeneration[generation] ?? 0) - 1)
        if remaining == 0 {
            activeNoteLoadsByGeneration[generation] = nil
        } else {
            activeNoteLoadsByGeneration[generation] = remaining
        }
        guard isCurrentNoteLoad(generation, id: id) else { return }
        isLoadingNote = remaining > 0
    }

    private func enqueueSave(id: String, html: String, generation: Int) {
        guard saveGenerationByID[id] == generation else { return }
        saveTasksByID[id] = nil
        guard !deletingNoteIDs.contains(id), activeSaveGenerationByID[id] == nil else {
            pendingSaveByID[id] = (generation, html)
            return
        }
        startSave(id: id, html: html, generation: generation)
    }

    private func startSave(id: String, html: String, generation: Int) {
        guard !deletingNoteIDs.contains(id) else { return }
        activeSaveGenerationByID[id] = generation
        isSaving = true
        let task = Task { [weak self] in
            guard let self else { return }
            let result = await self.operations.writeNote(id, html)
            self.finishSave(id: id, generation: generation, result: result)
        }
        activeSaveTasksByID[id] = task
    }

    private func finishSave(id: String, generation: Int, result: Result<Void, NotesAppError>) {
        guard activeSaveGenerationByID[id] == generation else { return }
        activeSaveGenerationByID[id] = nil
        activeSaveTasksByID[id] = nil

        if saveGenerationByID[id] == generation {
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

        if let pendingSave = pendingSaveByID.removeValue(forKey: id),
           saveGenerationByID[id] == pendingSave.generation,
           !deletingNoteIDs.contains(id) {
            startSave(id: id, html: pendingSave.html, generation: pendingSave.generation)
        } else {
            isSaving = !activeSaveGenerationByID.isEmpty
        }
    }

    /// Creates a new note in Notes, then refreshes the list and selects it.
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

    /// Creates a rich-text note, then refreshes the list and selects it.
    @discardableResult
    public func create(html: String, title: String = "新随记") async -> Bool {
        isSaving = true
        let result = await NotesAppBridge.createNote(title: title, html: html)
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

    /// Deletes the specified note from Notes and refreshes the list.
    public func delete(id: String) async {
        if isBuiltInWelcomeNote(id: id) {
            welcomeDismissalDefaults.set(true, forKey: Self.welcomeDismissedDefaultsKey)
            if selectedID == id {
                selectedID = notes.first?.id
            }
            return
        }
        guard deletingNoteIDs.insert(id).inserted else { return }
        defer { deletingNoteIDs.remove(id) }
        invalidatePendingSave(for: id)
        if let activeSave = activeSaveTasksByID[id] {
            await activeSave.value
        }
        let result = await operations.deleteNote(id)
        if case .failure(let error) = result {
            errorMessage = error.message
        }
        await refresh()
    }

    /// Hands off to the system Notes app to display and unlock the current note; Quick Notes does not handle passwords.
    public func showSelectedNoteInNotes() {
        guard let id = selectedID, !isBuiltInWelcomeNote(id: id) else { return }
        Task {
            if case .failure(let error) = await NotesAppBridge.showNote(id: id) {
                errorMessage = error.message
            }
        }
    }

    /// Hands off to the system Notes app to display an attachment; Quick Notes provides a read-only entry point.
    public func showAttachmentInNotes(id: String) {
        Task {
            if case .failure(let error) = await NotesAppBridge.showAttachment(id: id) {
                errorMessage = error.message
            }
        }
    }

    /// Uses the first line of Markdown (stripped of `#` prefixes) as the note title.
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

}
