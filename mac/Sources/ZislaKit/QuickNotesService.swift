import Combine
import Foundation
import ZislaCore

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
        let readNote: (String) async -> Result<NotesAppBridge.NoteContent, NotesAppError>
        let readAttachments: (String) async -> Result<[NotesAppBridge.NoteAttachment], NotesAppError>
        let writeNote: (String, String) async -> Result<Void, NotesAppError>
        let createNote: (String, String) async -> Result<String, NotesAppError>
        let deleteNote: (String) async -> Result<Void, NotesAppError>

        init(
            listNotes: @escaping () async -> Result<[NotesAppBridge.NoteSummary], NotesAppError>,
            readNote: @escaping (String) async -> Result<NotesAppBridge.NoteContent, NotesAppError>,
            readAttachments: @escaping (String) async -> Result<[NotesAppBridge.NoteAttachment], NotesAppError> = { _ in .success([]) },
            writeNote: @escaping (String, String) async -> Result<Void, NotesAppError>,
            createNote: @escaping (String, String) async -> Result<String, NotesAppError>,
            deleteNote: @escaping (String) async -> Result<Void, NotesAppError>
        ) {
            self.listNotes = listNotes
            self.readNote = readNote
            self.readAttachments = readAttachments
            self.writeNote = writeNote
            self.createNote = createNote
            self.deleteNote = deleteNote
        }
    }

    public static var welcomeNoteTitle: String { AppLocalization.text("朋友，看这里。") }
    private static let builtInWelcomeNoteID = "zisla.builtin.quick-notes-welcome"
    private static let welcomeDismissedDefaultsKey = "QuickNotesService.isBuiltInWelcomeNoteDismissed"
    private static let welcomeNoteResourceFolder = "QuickNotes"
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
            cancelAttachmentLoads(except: selectedID)
            noteLoadID = nil
            noteLoadGeneration &+= 1
            isLoadingNote = false
        }
    }
    @Published public private(set) var isLoadingList = false
    @Published public private(set) var isLoadingNote = false
    @Published public private(set) var isSaving = false
    @Published public private(set) var attachmentHydrationGeneration = 0
    @Published public var errorMessage: String?

    private struct NoteRevision: Equatable {
        let modifiedAt: Date?
        let isPasswordProtected: Bool
        let unknownRevisionGeneration: Int?

        init(summary: NotesAppBridge.NoteSummary, unknownRevisionGeneration: Int) {
            modifiedAt = summary.modifiedAt
            isPasswordProtected = summary.isPasswordProtected
            self.unknownRevisionGeneration = summary.modifiedAt == nil ? unknownRevisionGeneration : nil
        }

        var canCache: Bool { modifiedAt != nil }
    }

    private struct CachedNoteContent {
        let content: NotesAppBridge.NoteContent
        let revision: NoteRevision
    }

    private struct InFlightNoteLoad {
        let token = UUID()
        let revision: NoteRevision
        let task: Task<Result<NotesAppBridge.NoteContent, NotesAppError>, Never>
    }

    private struct CachedAttachments {
        let attachments: [NotesAppBridge.NoteAttachment]
        let revision: NoteRevision
    }

    private struct InFlightAttachmentLoad {
        let token = UUID()
        let revision: NoteRevision
        let task: Task<Result<[NotesAppBridge.NoteAttachment], NotesAppError>, Never>
    }

    private var saveTasksByID: [String: Task<Void, Never>] = [:]
    private var refreshTask: Task<Void, Never>?
    private var lastSuccessfulRefreshAt = Date.distantPast
    private var refreshGeneration = 0
    private var inFlightRefreshGeneration: Int?
    private var noteSummaryGeneration = 0
    private var cachedNoteContents: [String: CachedNoteContent] = [:]
    private var cachedAttachments: [String: CachedAttachments] = [:]
    private var pendingCreatedNotes: [String: NotesAppBridge.NoteSummary] = [:]
    private var inFlightNoteLoads: [String: InFlightNoteLoad] = [:]
    private var inFlightAttachmentLoads: [String: InFlightAttachmentLoad] = [:]
    private let welcomeDismissalDefaults: UserDefaults
    private let operations: Operations
    private let saveDelay: Duration
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
            readNote: { await NotesAppBridge.readNote(id: $0) },
            readAttachments: { await NotesAppBridge.readAttachments(noteID: $0) },
            writeNote: { id, html in await NotesAppBridge.writeNote(id: id, html: html) },
            createNote: { title, html in await NotesAppBridge.createNote(title: title, html: html) },
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
        guard let selectedID else { return nil }
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

    public func cachedContent(for id: String) -> NotesAppBridge.NoteContent? {
        guard let summary = notes.first(where: { $0.id == id }),
              let cached = cachedNoteContents[id],
              cached.revision == noteRevision(for: summary)
        else { return nil }
        return cached.content
    }

    static var welcomeNoteText: String {
        welcomeNoteText(language: AppLocalization.currentLanguage)
    }

    /// Reads `welcome-note-<language>.md`, then the Simplified Chinese source note, then the inline copy.
    static func welcomeNoteText(language: AppLanguage) -> String {
        let sourceResources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        let roots = [Bundle.main.resourceURL, sourceResources].compactMap { $0 }
        let names = ["welcome-note-\(language.rawValue).md", "welcome-note.md"]
        for name in names {
            for root in roots {
                let url = root
                    .appendingPathComponent(welcomeNoteResourceFolder, isDirectory: true)
                    .appendingPathComponent(name, isDirectory: false)
                if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                    return text
                }
            }
        }
        return fallbackWelcomeNoteText
    }

    /// Re-fetches the Notes note list; concurrent callers share one current list query.
    public func refresh() async {
        await refresh(force: true)
    }

    /// Refreshes automatically only while a list query is already in flight or when the last
    /// successful list snapshot is stale, avoiding back-to-back activation/key-window queries.
    public func refreshIfNeeded() async {
        if refreshTask != nil {
            await refresh(force: false)
            return
        }
        guard Date().timeIntervalSince(lastSuccessfulRefreshAt) >= 2 else { return }
        await refresh(force: false)
    }

    private func refresh(force: Bool) async {
        if !force, refreshTask == nil,
           Date().timeIntervalSince(lastSuccessfulRefreshAt) < 2 {
            return
        }
        while true {
            if let refreshTask {
                let taskGeneration = inFlightRefreshGeneration
                await refreshTask.value
                if refreshGeneration == taskGeneration { return }
                continue
            }

            let generation = refreshGeneration
            isLoadingList = true
            errorMessage = nil
            inFlightRefreshGeneration = generation
            let task = Task { [weak self] in
                guard let self else { return }
                let result = await self.operations.listNotes()
                self.finishRefresh(result, generation: generation)
            }
            refreshTask = task
            await task.value
            if refreshGeneration == generation { return }
        }
    }

    private func finishRefresh(
        _ result: Result<[NotesAppBridge.NoteSummary], NotesAppError>,
        generation: Int
    ) {
        guard inFlightRefreshGeneration == generation else { return }
        refreshTask = nil
        inFlightRefreshGeneration = nil
        isLoadingList = false
        guard refreshGeneration == generation else { return }
        switch result {
        case .success(let fetched):
            lastSuccessfulRefreshAt = Date()
            applyFetchedNotes(fetched)
        case .failure(let error):
            errorMessage = error.message
        }
    }

    private func invalidateRefresh() {
        refreshGeneration &+= 1
    }

    /// Updates local state with an external list result (shared by tests and `refresh`).
    /// Keep an empty initial selection for regular notes so loading their bodies remains explicit.
    /// If an existing selection is no longer in the list (e.g. deleted in Notes), falls back to the first item or clears selection.
    func applyFetchedNotes(_ fetched: [NotesAppBridge.NoteSummary]) {
        // Earlier versions used this reserved title for a generated system note. Leave the
        // system record untouched, but do not show it alongside the local replacement.
        let updatedNotes = fetched
            .filter { $0.title != Self.welcomeNoteTitle }
            .sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
        let fetchedIDs = Set(updatedNotes.map(\.id))
        pendingCreatedNotes = pendingCreatedNotes.filter { !fetchedIDs.contains($0.key) }
        let displayedNotes = (updatedNotes + pendingCreatedNotes.values)
            .sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
        noteSummaryGeneration &+= 1
        let summariesByID = Dictionary(uniqueKeysWithValues: displayedNotes.map { ($0.id, $0) })
        cachedNoteContents = cachedNoteContents.filter { id, cached in
            guard let summary = summariesByID[id] else { return false }
            return cached.revision == noteRevision(for: summary)
        }
        cachedAttachments = cachedAttachments.filter { id, cached in
            guard let summary = summariesByID[id] else { return false }
            return cached.revision == noteRevision(for: summary)
        }
        inFlightNoteLoads = inFlightNoteLoads.filter { id, inFlight in
            guard let summary = summariesByID[id] else { return false }
            return inFlight.revision == noteRevision(for: summary)
        }
        let staleAttachmentLoadIDs = inFlightAttachmentLoads.keys.filter { id in
            guard let summary = summariesByID[id] else { return true }
            return inFlightAttachmentLoads[id]?.revision != noteRevision(for: summary)
        }
        for id in staleAttachmentLoadIDs {
            inFlightAttachmentLoads[id]?.task.cancel()
            inFlightAttachmentLoads[id] = nil
        }
        inFlightAttachmentLoads = inFlightAttachmentLoads.filter { id, _ in
            summariesByID[id] != nil
        }
        notes = displayedNotes
        guard let selectedID else {
            self.selectedID = welcomeNote?.id
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
        guard let summary = notes.first(where: { $0.id == id }) else { return nil }
        let revision = noteRevision(for: summary)
        if let cached = cachedNoteContents[id], cached.revision == revision {
            scheduleAttachmentLoad(for: id, revision: revision, content: cached.content)
            return cached.content
        }
        let result = await noteLoadResult(for: id, revision: revision)
        guard isCurrentNoteLoad(generation, id: id), currentNoteRevision(for: id) == revision else {
            return nil
        }
        switch result {
        case .success(let content):
            guard content.isPasswordProtected == revision.isPasswordProtected else { return nil }
            let content = contentWithCachedAttachments(for: id, revision: revision, content: content)
            if revision.canCache {
                cachedNoteContents[id] = CachedNoteContent(content: content, revision: revision)
            }
            scheduleAttachmentLoad(for: id, revision: revision, content: content)
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

    private func noteRevision(for summary: NotesAppBridge.NoteSummary) -> NoteRevision {
        NoteRevision(summary: summary, unknownRevisionGeneration: noteSummaryGeneration)
    }

    private func currentNoteRevision(for id: String) -> NoteRevision? {
        notes.first(where: { $0.id == id }).map(noteRevision(for:))
    }

    private func noteLoadResult(
        for id: String,
        revision: NoteRevision
    ) async -> Result<NotesAppBridge.NoteContent, NotesAppError> {
        if let inFlight = inFlightNoteLoads[id], inFlight.revision == revision {
            return await inFlight.task.value
        }
        let task = Task { [operations] in
            await operations.readNote(id)
        }
        let inFlight = InFlightNoteLoad(revision: revision, task: task)
        inFlightNoteLoads[id] = inFlight
        let result = await task.value
        if inFlightNoteLoads[id]?.token == inFlight.token {
            inFlightNoteLoads[id] = nil
        }
        return result
    }

    private func contentWithCachedAttachments(
        for id: String,
        revision: NoteRevision,
        content: NotesAppBridge.NoteContent
    ) -> NotesAppBridge.NoteContent {
        guard let cached = cachedAttachments[id], cached.revision == revision else { return content }
        return NotesAppBridge.NoteContent(
            plainText: content.plainText,
            bodyHTML: content.bodyHTML,
            isPasswordProtected: content.isPasswordProtected,
            attachments: cached.attachments
        )
    }

    private func scheduleAttachmentLoad(
        for id: String,
        revision: NoteRevision,
        content: NotesAppBridge.NoteContent
    ) {
        guard !content.isPasswordProtected,
              cachedAttachments[id]?.revision != revision,
              inFlightAttachmentLoads[id]?.revision != revision
        else { return }
        let task = Task { [operations] in
            await operations.readAttachments(id)
        }
        let inFlight = InFlightAttachmentLoad(revision: revision, task: task)
        inFlightAttachmentLoads[id] = inFlight
        Task { [weak self] in
            let result = await task.value
            self?.finishAttachmentLoad(for: id, revision: revision, token: inFlight.token, result: result)
        }
    }

    private func finishAttachmentLoad(
        for id: String,
        revision: NoteRevision,
        token: UUID,
        result: Result<[NotesAppBridge.NoteAttachment], NotesAppError>
    ) {
        guard inFlightAttachmentLoads[id]?.token == token else { return }
        inFlightAttachmentLoads[id] = nil
        guard currentNoteRevision(for: id) == revision else { return }
        guard case .success(let attachments) = result else { return }
        cachedAttachments[id] = CachedAttachments(attachments: attachments, revision: revision)
        guard let cached = cachedNoteContents[id], cached.revision == revision else { return }
        cachedNoteContents[id] = CachedNoteContent(
            content: NotesAppBridge.NoteContent(
                plainText: cached.content.plainText,
                bodyHTML: cached.content.bodyHTML,
                isPasswordProtected: cached.content.isPasswordProtected,
                attachments: attachments
            ),
            revision: revision
        )
        attachmentHydrationGeneration &+= 1
    }

    private func cancelAttachmentLoads(except selectedID: String?) {
        let inactiveIDs = inFlightAttachmentLoads.keys.filter { $0 != selectedID }
        for id in inactiveIDs {
            inFlightAttachmentLoads[id]?.task.cancel()
            inFlightAttachmentLoads[id] = nil
        }
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
                cachedNoteContents[id] = nil
                invalidateRefresh()
                if let index = notes.firstIndex(where: { $0.id == id }) {
                    notes[index] = NotesAppBridge.NoteSummary(
                        id: id,
                        title: notes[index].title,
                        modifiedAt: Date(),
                        isPasswordProtected: notes[index].isPasswordProtected
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
    public func create(markdown: String? = nil) async -> Bool {
        let markdown = markdown ?? "# \(AppLocalization.text("新随记"))\n"
        return await create(html: NotesAppBridge.bodyHTML(for: markdown), title: Self.title(for: markdown))
    }

    /// Creates a rich-text note, then refreshes the list and selects it.
    @discardableResult
    public func create(html: String, title: String? = nil) async -> Bool {
        let title = title ?? AppLocalization.text("新随记")
        isSaving = true
        let result = await operations.createNote(title, html)
        isSaving = false
        switch result {
        case .success(let id):
            invalidateRefresh()
            let summary = NotesAppBridge.NoteSummary(
                id: id,
                title: title,
                modifiedAt: Date()
            )
            pendingCreatedNotes[id] = summary
            notes.removeAll { $0.id == id }
            notes.insert(summary, at: 0)
            selectedID = id
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
        cachedNoteContents[id] = nil
        invalidatePendingSave(for: id)
        if let activeSave = activeSaveTasksByID[id] {
            await activeSave.value
        }
        let result = await operations.deleteNote(id)
        if case .failure(let error) = result {
            errorMessage = error.message
        } else {
            invalidateRefresh()
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
        return stripped.isEmpty ? AppLocalization.text("新随记") : stripped
    }

}
