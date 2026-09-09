import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct QuickNotesServiceTests {
    @Test
    func displaysBuiltInWelcomeWithoutAddingItToNotes() throws {
        let suiteName = "Zisla.QuickNotesServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = QuickNotesService(welcomeDismissalDefaults: defaults)
        let regular = NotesAppBridge.NoteSummary(
            id: "regular",
            title: "普通备忘录",
            modifiedAt: .now
        )
        let legacyWelcome = NotesAppBridge.NoteSummary(
            id: "legacy-welcome",
            title: QuickNotesService.welcomeNoteTitle,
            modifiedAt: .distantPast
        )

        service.applyFetchedNotes([legacyWelcome, regular])

        let welcome = try #require(service.welcomeNote)
        #expect(service.notes == [regular])
        #expect(service.regularNotes == [regular])
        #expect(service.selectedNote == welcome)
        #expect(service.isBuiltInWelcomeNote(id: welcome.id))
    }

    @Test
    func commandNumberShortcutsUseOnlyRegularNotesStopAtNineAndShowMatchingLabels() throws {
        let source = try String(
            contentsOf: sourceRoot.appendingPathComponent("Sources/Zisla/QuickNoteModuleView.swift"),
            encoding: .utf8
        )
        let regularNotesStart = try #require(source.range(of: "ForEach(Array(service.regularNotes.enumerated())"))
        let regularNotesBlock = source[regularNotesStart.lowerBound...]

        #expect(!source[..<regularNotesStart.lowerBound].contains("keyboardShortcut"))
        #expect(!source[..<regularNotesStart.lowerBound].contains("shortcutNumber:"))
        #expect(regularNotesBlock.contains("index < 9"))
        #expect(regularNotesBlock.contains("noteRow(note, shortcutNumber: index + 1)"))
        #expect(regularNotesBlock.contains("KeyEquivalent(Character(String(index + 1)))"))
        #expect(source.contains("if let shortcutNumber {"))
        #expect(source.contains("Text(\"⌘\\(shortcutNumber)\")"))
    }

    @Test
    func loadsWelcomeNoteTextFromBundledResource() {
        let chinese = QuickNotesService.welcomeNoteText(language: .simplifiedChinese)
        #expect(chinese.contains("从现在开始，你可以在记事本中写记事了。"))
        #expect(chinese.contains("愿你能愉快而轻松地使用这个小工具~"))
    }

    /// A missing `welcome-note-<language>.md` silently falls back to the Simplified Chinese source,
    /// so matching that text is how an untranslated language shows up.
    @Test
    func loadsTranslatedWelcomeNoteForEveryLanguage() {
        let chinese = QuickNotesService.welcomeNoteText(language: .simplifiedChinese)
        for language in AppLanguage.allCases where language != .simplifiedChinese {
            let text = QuickNotesService.welcomeNoteText(language: language)
            #expect(!text.isEmpty, "\(language.rawValue) welcome note is empty")
            #expect(text != chinese, "\(language.rawValue) welcome note is untranslated")
        }
    }

    @Test
    func loadsAndDismissesBuiltInWelcomeLocally() async throws {
        let suiteName = "Zisla.QuickNotesServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = QuickNotesService(welcomeDismissalDefaults: defaults)
        let regular = NotesAppBridge.NoteSummary(id: "regular", title: "普通备忘录", modifiedAt: .now)
        service.applyFetchedNotes([regular])
        let welcome = try #require(service.welcomeNote)

        service.select(id: welcome.id)
        let content = try #require(await service.loadNote())
        #expect(content.plainText == QuickNotesService.welcomeNoteText)

        await service.delete(id: welcome.id)

        #expect(service.welcomeNote == nil)
        #expect(service.notes == [regular])
        #expect(service.selectedID == regular.id)

        let reloaded = QuickNotesService(welcomeDismissalDefaults: defaults)
        #expect(reloaded.welcomeNote == nil)
    }

    @Test
    func dropsSelectionWhenSelectedNoteMissingFromRefresh() {
        let suiteName = "Zisla.QuickNotesServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = QuickNotesService(welcomeDismissalDefaults: defaults)
        let kept = NotesAppBridge.NoteSummary(id: "keep", title: "保留", modifiedAt: .now)
        let removed = NotesAppBridge.NoteSummary(id: "gone", title: "已删", modifiedAt: .distantPast)

        service.applyFetchedNotes([removed, kept])
        service.select(id: removed.id)
        #expect(service.selectedID == removed.id)

        service.applyFetchedNotes([kept])
        #expect(service.selectedID == kept.id)
        #expect(service.notes.map(\.id) == [kept.id])
    }

    @Test
    func clearsSelectionWhenAllNotesRemoved() {
        let suiteName = "Zisla.QuickNotesServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = QuickNotesService(welcomeDismissalDefaults: defaults)
        service.applyFetchedNotes([
            NotesAppBridge.NoteSummary(id: "only", title: "唯一", modifiedAt: .now)
        ])
        service.select(id: "only")

        service.applyFetchedNotes([])
        #expect(service.notes.isEmpty)
        #expect(service.selectedID == service.welcomeNote?.id)
    }

    @Test
    func keepsRegularNotesUnselectedOnInitialRefreshWithoutWelcome() async throws {
        let suiteName = "Zisla.QuickNotesServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = QuickNotesService(welcomeDismissalDefaults: defaults)
        if let welcome = service.welcomeNote {
            await service.delete(id: welcome.id)
        }
        let regular = NotesAppBridge.NoteSummary(id: "regular", title: "普通备忘录", modifiedAt: .now)

        service.applyFetchedNotes([regular])

        #expect(service.notes == [regular])
        #expect(service.selectedID == nil)
        #expect(service.selectedNote == nil)
    }

    @Test
    func refreshListsSummariesWithoutReadingRegularNoteBodies() async throws {
        let loads = ControlledImmediateNoteLoads()
        let regular = NotesAppBridge.NoteSummary(id: "regular", title: "普通备忘录", modifiedAt: .now)
        let suiteName = "Zisla.QuickNotesServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = QuickNotesService(
            welcomeDismissalDefaults: defaults,
            operations: QuickNotesService.Operations(
                listNotes: { .success([regular]) },
                readNote: { id in await loads.readNote(id: id) },
                writeNote: { _, _ in .success(()) },
                createNote: { _, _ in .success("created") },
                deleteNote: { _ in .success(()) }
            )
        )
        if let welcome = service.welcomeNote {
            await service.delete(id: welcome.id)
        }

        await service.refresh()

        #expect(service.notes == [regular])
        #expect(service.selectedID == nil)
        #expect(await loads.callCount == 0)
    }

    @Test
    func savesSeparateNotesWithoutCancellingTheirDebounce() async throws {
        let writes = ControlledNoteWrites()
        let service = makeService(writes: writes, saveDelay: .milliseconds(1))

        service.scheduleSave(id: "first", html: "first body")
        service.scheduleSave(id: "second", html: "second body")

        let bothWritesStarted = await writes.waitForCallCount(2)
        let calls = await writes.calls
        #expect(bothWritesStarted)
        #expect(Set(calls.map(\.id)) == ["first", "second"])
        await writes.resolveAll()
    }

    @Test
    func preservesPendingSaveWhenLoadingAnotherNote() async throws {
        let writes = ControlledNoteWrites()
        let service = makeService(writes: writes, saveDelay: .milliseconds(1))
        let first = NotesAppBridge.NoteSummary(id: "first", title: "第一条", modifiedAt: .now)
        let second = NotesAppBridge.NoteSummary(id: "second", title: "第二条", modifiedAt: .now)
        service.applyFetchedNotes([first, second])
        service.select(id: first.id)

        service.scheduleSave(id: first.id, html: "first body")
        service.select(id: second.id)
        _ = await service.loadNote()

        let firstWriteStarted = await writes.waitForCallCount(1)
        let calls = await writes.calls
        #expect(firstWriteStarted)
        #expect(calls == [.init(id: first.id, html: "first body")])
        await writes.resolveAll()
    }

    @Test
    func loadingDraftInEitherQuickNoteViewDoesNotDiscardCapturedWrites() throws {
        let root = sourceRoot
        let expandedSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Zisla/QuickNoteExpandedView.swift"),
            encoding: .utf8
        )
        let moduleSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Zisla/QuickNoteModuleView.swift"),
            encoding: .utf8
        )

        #expect(!expandedSource.contains("cancelPendingSave()"))
        #expect(!moduleSource.contains("cancelPendingSave()"))
        #expect(moduleSource.contains("@State private var draftLoadGeneration = 0"))
        #expect(moduleSource.contains("guard generation == draftLoadGeneration, selectedID == service.selectedID else { return }"))
        #expect(expandedSource.contains(".task {\n            await service.refresh()\n            if service.selectedID != nil"))
        #expect(moduleSource.contains(".task {\n            await service.refresh()\n            if service.selectedID != nil"))
    }

    @Test
    func skipsSupersededPendingWriteAfterAnOlderWriteFinishes() async throws {
        let writes = ControlledNoteWrites()
        let service = makeService(writes: writes, saveDelay: .milliseconds(20))

        service.scheduleSave(id: "note", html: "old")
        let firstWriteStarted = await writes.waitForCallCount(1)
        #expect(firstWriteStarted)

        service.scheduleSave(id: "note", html: "superseded")
        try await Task.sleep(for: .milliseconds(40))
        service.scheduleSave(id: "note", html: "latest")
        await writes.resolveNext()

        try await Task.sleep(for: .milliseconds(5))
        let callCountAfterFirstWrite = await writes.callCount
        let latestWriteStarted = await writes.waitForCallCount(2)
        let calls = await writes.calls
        #expect(callCountAfterFirstWrite == 1)
        #expect(latestWriteStarted)
        #expect(calls[1].html == "latest")
        await writes.resolveAll()
    }

    @Test
    func deletingNoteInvalidatesDebouncedWrite() async throws {
        let writes = ControlledNoteWrites()
        let deletes = ControlledNoteDeletes()
        let service = makeService(
            writes: writes,
            deletes: deletes,
            saveDelay: .milliseconds(20)
        )

        service.scheduleSave(id: "note", html: "stale")
        await service.delete(id: "note")
        try await Task.sleep(for: .milliseconds(40))

        #expect(await writes.callCount == 0)
        #expect(await deletes.calls == ["note"])
    }

    @Test
    func deletingNoteWaitsForAnInFlightWrite() async throws {
        let writes = ControlledNoteWrites()
        let deletes = ControlledNoteDeletes()
        let service = makeService(
            writes: writes,
            deletes: deletes,
            saveDelay: .milliseconds(1)
        )

        service.scheduleSave(id: "note", html: "stale")
        #expect(await writes.waitForCallCount(1))

        let deletion = Task { await service.delete(id: "note") }
        try await Task.sleep(for: .milliseconds(10))
        #expect(await deletes.callCount == 0)

        await writes.resolveNext()
        #expect(await deletes.waitForCallCount(1))
        await deletes.resolveAll()
        await deletion.value
        #expect(await deletes.calls == ["note"])
    }

    @Test
    func loadingWelcomeAfterRegularNoteClearsThePreviousLoadingState() async throws {
        let writes = ControlledNoteWrites()
        let loads = ControlledNoteLoads()
        let service = makeService(writes: writes, loads: loads, saveDelay: .milliseconds(1))
        let regular = NotesAppBridge.NoteSummary(id: "regular", title: "普通备忘录", modifiedAt: .now)
        service.applyFetchedNotes([regular])
        service.select(id: regular.id)

        let regularLoad = Task { await service.loadNote() }
        let regularLoadStarted = await loads.waitForCallCount(1)
        #expect(regularLoadStarted)
        #expect(service.isLoadingNote)

        let welcome = try #require(service.welcomeNote)
        service.select(id: welcome.id)
        _ = await service.loadNote()
        #expect(!service.isLoadingNote)

        await loads.resolveAll()
        let staleContent = await regularLoad.value
        #expect(staleContent == nil)
        #expect(!service.isLoadingNote)
    }

    @Test
    func simultaneousLoadsForTheSameSelectedNoteBothReceiveContent() async throws {
        let writes = ControlledNoteWrites()
        let loads = ControlledNoteLoads()
        let service = makeService(writes: writes, loads: loads, saveDelay: .milliseconds(1))
        let regular = NotesAppBridge.NoteSummary(id: "regular", title: "普通备忘录", modifiedAt: .now)
        service.applyFetchedNotes([regular])
        service.select(id: regular.id)

        let firstLoad = Task { await service.loadNote() }
        let firstLoadStarted = await loads.waitForCallCount(1)
        #expect(firstLoadStarted)
        let secondLoad = Task { await service.loadNote() }
        try await Task.sleep(for: .milliseconds(5))
        #expect(await loads.callCount == 1)

        await loads.resolveAll()
        let firstContent = await firstLoad.value
        let secondContent = await secondLoad.value
        #expect(firstContent != nil)
        #expect(secondContent != nil)
        #expect(!service.isLoadingNote)
    }

    @Test
    func switchingAwayAndBackInvalidatesTheEarlierLoadForTheSameNote() async throws {
        let writes = ControlledNoteWrites()
        let loads = ControlledNoteLoads()
        let service = makeService(writes: writes, loads: loads, saveDelay: .milliseconds(1))
        let first = NotesAppBridge.NoteSummary(id: "first", title: "第一条", modifiedAt: .now)
        let second = NotesAppBridge.NoteSummary(id: "second", title: "第二条", modifiedAt: .now)
        service.applyFetchedNotes([first, second])
        service.select(id: first.id)

        let earlierLoad = Task { await service.loadNote() }
        #expect(await loads.waitForCallCount(1))

        service.select(id: second.id)
        service.select(id: first.id)
        let currentLoad = Task { await service.loadNote() }
        #expect(await loads.waitForCallCount(1))

        await loads.resolveAll()
        #expect(await earlierLoad.value == nil)
        #expect(await currentLoad.value != nil)
        #expect(!service.isLoadingNote)
    }

    @Test
    func refreshesConcurrentlyWithOneListQuery() async throws {
        let lists = ControlledNoteLists()
        let service = QuickNotesService(
            welcomeDismissalDefaults: UserDefaults(suiteName: "Zisla.QuickNotesServiceTests.\(UUID().uuidString)")!,
            operations: QuickNotesService.Operations(
                listNotes: { await lists.listNotes() },
                readNote: { _ in .success(NotesAppBridge.NoteContent(plainText: "", bodyHTML: "")) },
                writeNote: { _, _ in .success(()) },
                createNote: { _, _ in .success("created") },
                deleteNote: { _ in .success(()) }
            )
        )

        let firstRefresh = Task { await service.refresh() }
        #expect(await lists.waitForCallCount(1))
        let secondRefresh = Task { await service.refresh() }
        await lists.resolveNext(with: [])
        await firstRefresh.value
        await secondRefresh.value

        #expect(await lists.callCount == 1)
        #expect(!service.isLoadingList)
    }

    @Test
    func refreshesAgainAfterDeletingDuringAnInFlightRefresh() async throws {
        let lists = ControlledNoteLists()
        let service = QuickNotesService(
            welcomeDismissalDefaults: UserDefaults(suiteName: "Zisla.QuickNotesServiceTests.\(UUID().uuidString)")!,
            operations: QuickNotesService.Operations(
                listNotes: { await lists.listNotes() },
                readNote: { _ in .success(NotesAppBridge.NoteContent(plainText: "", bodyHTML: "")) },
                writeNote: { _, _ in .success(()) },
                createNote: { _, _ in .success("created") },
                deleteNote: { _ in .success(()) }
            )
        )
        let note = NotesAppBridge.NoteSummary(id: "note", title: "随记", modifiedAt: .now)
        service.applyFetchedNotes([note])
        service.select(id: note.id)

        let firstRefresh = Task { await service.refresh() }
        #expect(await lists.waitForCallCount(1))
        let deletion = Task { await service.delete(id: note.id) }
        await lists.resolveNext(with: [note])
        #expect(await lists.waitForCallCount(2))
        await lists.resolveNext(with: [])
        await firstRefresh.value
        await deletion.value

        #expect(service.notes.isEmpty)
        #expect(service.selectedID == service.welcomeNote?.id)
    }

    @Test
    func invalidatesCachedContentWhenPasswordProtectionChanges() async throws {
        let loads = ControlledImmediateNoteLoads()
        let service = QuickNotesService(
            welcomeDismissalDefaults: UserDefaults(suiteName: "Zisla.QuickNotesServiceTests.\(UUID().uuidString)")!,
            operations: QuickNotesService.Operations(
                listNotes: { .success([]) },
                readNote: { id in await loads.readNote(id: id) },
                writeNote: { _, _ in .success(()) },
                createNote: { _, _ in .success("created") },
                deleteNote: { _ in .success(()) }
            )
        )
        let modifiedAt = Date(timeIntervalSinceReferenceDate: 1)
        let unlocked = NotesAppBridge.NoteSummary(id: "note", title: "随记", modifiedAt: modifiedAt)
        service.applyFetchedNotes([unlocked])
        service.select(id: unlocked.id)

        _ = await service.loadNote()
        #expect(await loads.callCount == 1)

        let locked = NotesAppBridge.NoteSummary(
            id: unlocked.id,
            title: unlocked.title,
            modifiedAt: modifiedAt,
            isPasswordProtected: true
        )
        service.applyFetchedNotes([locked])
        let content = await service.loadNote()

        #expect(content == nil)
        #expect(await loads.callCount == 2)
    }

    @Test
    func doesNotReuseAnInFlightLoadAfterItsSummaryChanges() async throws {
        let writes = ControlledNoteWrites()
        let loads = ControlledNoteLoads()
        let service = makeService(writes: writes, loads: loads, saveDelay: .milliseconds(1))
        let old = NotesAppBridge.NoteSummary(
            id: "note",
            title: "随记",
            modifiedAt: Date(timeIntervalSinceReferenceDate: 1)
        )
        let updated = NotesAppBridge.NoteSummary(
            id: old.id,
            title: old.title,
            modifiedAt: Date(timeIntervalSinceReferenceDate: 2)
        )
        service.applyFetchedNotes([old])
        service.select(id: old.id)

        let oldLoad = Task { await service.loadNote() }
        #expect(await loads.waitForCallCount(1))

        service.applyFetchedNotes([updated])
        let currentLoad = Task { await service.loadNote() }
        #expect(await loads.waitForCallCount(2))

        await loads.resolveNext(with: .init(plainText: "旧内容", bodyHTML: "<div>旧内容</div>"))
        #expect(await oldLoad.value == nil)
        await loads.resolveNext(with: .init(plainText: "新内容", bodyHTML: "<div>新内容</div>"))
        #expect(await currentLoad.value?.plainText == "新内容")

        _ = await service.loadNote()
        #expect(await loads.callCount == 2)
    }

    @Test
    func reusesCachedContentUntilItsSummaryChanges() async throws {
        let loads = ControlledImmediateNoteLoads()
        let service = QuickNotesService(
            welcomeDismissalDefaults: UserDefaults(suiteName: "Zisla.QuickNotesServiceTests.\(UUID().uuidString)")!,
            operations: QuickNotesService.Operations(
                listNotes: { .success([]) },
                readNote: { id in await loads.readNote(id: id) },
                writeNote: { _, _ in .success(()) },
                createNote: { _, _ in .success("created") },
                deleteNote: { _ in .success(()) }
            )
        )
        let first = NotesAppBridge.NoteSummary(id: "note", title: "随记", modifiedAt: .distantPast)
        service.applyFetchedNotes([first])
        service.select(id: first.id)

        _ = await service.loadNote()
        _ = await service.loadNote()
        #expect(await loads.callCount == 1)

        service.applyFetchedNotes([
            NotesAppBridge.NoteSummary(id: first.id, title: first.title, modifiedAt: .now)
        ])
        _ = await service.loadNote()
        #expect(await loads.callCount == 2)
    }

    @Test
    func returnsBodyBeforeAsynchronouslyHydratingAttachments() async throws {
        let hydrator = ControlledNoteAttachments()
        let note = NotesAppBridge.NoteSummary(id: "note", title: "随记", modifiedAt: .now)
        let service = QuickNotesService(
            welcomeDismissalDefaults: UserDefaults(suiteName: "Zisla.QuickNotesServiceTests.\(UUID().uuidString)")!,
            operations: QuickNotesService.Operations(
                listNotes: { .success([]) },
                readNote: { _ in .success(.init(plainText: "正文", bodyHTML: "<div>正文</div>")) },
                readAttachments: { id in await hydrator.readAttachments(noteID: id) },
                writeNote: { _, _ in .success(()) },
                createNote: { _, _ in .success("created") },
                deleteNote: { _ in .success(()) }
            )
        )
        service.applyFetchedNotes([note])
        service.select(id: note.id)

        let initial = try #require(await service.loadNote())
        #expect(initial.attachments.isEmpty)
        #expect(await hydrator.waitForCallCount(1))

        let attachment = NotesAppBridge.NoteAttachment(id: "image", name: "image.png", contentIdentifier: "cid", url: "")
        await hydrator.resolveNext(with: [attachment])
        #expect(await waitForCachedAttachments(service, id: note.id, expected: [attachment]))
    }

    @Test
    func cancelsAnOutdatedAttachmentHydrationAfterSelectionChanges() async throws {
        let hydrator = ControlledNoteAttachments()
        let first = NotesAppBridge.NoteSummary(id: "first", title: "第一条", modifiedAt: .now)
        let second = NotesAppBridge.NoteSummary(id: "second", title: "第二条", modifiedAt: .distantPast)
        let service = QuickNotesService(
            welcomeDismissalDefaults: UserDefaults(suiteName: "Zisla.QuickNotesServiceTests.\(UUID().uuidString)")!,
            operations: QuickNotesService.Operations(
                listNotes: { .success([]) },
                readNote: { id in .success(.init(plainText: id, bodyHTML: "<div>\(id)</div>")) },
                readAttachments: { id in await hydrator.readAttachments(noteID: id) },
                writeNote: { _, _ in .success(()) },
                createNote: { _, _ in .success("created") },
                deleteNote: { _ in .success(()) }
            )
        )
        service.applyFetchedNotes([first, second])
        service.select(id: first.id)
        _ = await service.loadNote()
        #expect(await hydrator.waitForCallCount(1))

        service.select(id: second.id)
        _ = await service.loadNote()
        #expect(await hydrator.waitForCallCount(2))
        #expect(await hydrator.waitForCancellation(of: first.id))
        await hydrator.resolveAll()
    }

    @Test
    func createsAndSelectsTheStableNotesIDBeforeTheListConverges() async throws {
        let createdID = "created-note"
        let existing = NotesAppBridge.NoteSummary(id: "existing", title: "新随记", modifiedAt: .now)
        let service = QuickNotesService(
            welcomeDismissalDefaults: UserDefaults(suiteName: "Zisla.QuickNotesServiceTests.\(UUID().uuidString)")!,
            operations: QuickNotesService.Operations(
                listNotes: { .success([existing]) },
                readNote: { id in .success(NotesAppBridge.NoteContent(plainText: id, bodyHTML: "<div>\(id)</div>")) },
                writeNote: { _, _ in .success(()) },
                createNote: { _, _ in .success(createdID) },
                deleteNote: { _ in .success(()) }
            )
        )
        service.applyFetchedNotes([existing])
        service.select(id: existing.id)

        #expect(await service.create(html: "<div><br></div>", title: existing.title))
        #expect(service.selectedID == createdID)
        #expect(service.notes.first?.id == createdID)
        #expect(await service.loadNote()?.plainText == createdID)
    }

    @Test
    func leavesTheCurrentSelectionWhenCreationFails() async throws {
        let existing = NotesAppBridge.NoteSummary(id: "existing", title: "旧随记", modifiedAt: .now)
        let service = QuickNotesService(
            welcomeDismissalDefaults: UserDefaults(suiteName: "Zisla.QuickNotesServiceTests.\(UUID().uuidString)")!,
            operations: QuickNotesService.Operations(
                listNotes: { .success([existing]) },
                readNote: { _ in .success(NotesAppBridge.NoteContent(plainText: "", bodyHTML: "")) },
                writeNote: { _, _ in .success(()) },
                createNote: { _, _ in .failure(.failed("创建失败")) },
                deleteNote: { _ in .success(()) }
            )
        )
        service.applyFetchedNotes([existing])
        service.select(id: existing.id)

        #expect(!(await service.create(html: "<div><br></div>")))
        #expect(service.selectedID == existing.id)
        #expect(service.notes.map(\.id) == [existing.id])
    }

    private func makeService(
        writes: ControlledNoteWrites,
        loads: ControlledNoteLoads? = nil,
        deletes: ControlledNoteDeletes? = nil,
        saveDelay: Duration
    ) -> QuickNotesService {
        QuickNotesService(
            welcomeDismissalDefaults: UserDefaults(suiteName: "Zisla.QuickNotesServiceTests.\(UUID().uuidString)")!,
            operations: QuickNotesService.Operations(
                listNotes: { .success([]) },
                readNote: { id in
                    if let loads {
                        return await loads.readNote(id: id)
                    }
                    return .success(NotesAppBridge.NoteContent(plainText: "", bodyHTML: ""))
                },
                writeNote: { id, html in await writes.write(id: id, html: html) },
                createNote: { _, _ in .success("created") },
                deleteNote: { id in
                    if let deletes {
                        return await deletes.delete(id: id)
                    }
                    return .success(())
                }
            ),
            saveDelay: saveDelay
        )
    }

    private func waitForCachedAttachments(
        _ service: QuickNotesService,
        id: String,
        expected: [NotesAppBridge.NoteAttachment]
    ) async -> Bool {
        for _ in 0..<100 {
            if service.cachedContent(for: id)?.attachments == expected { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private actor ControlledNoteAttachments {
    private struct Pending {
        let id: String
        let continuation: CheckedContinuation<Result<[NotesAppBridge.NoteAttachment], NotesAppError>, Never>
    }

    private var pending: [Pending] = []
    private(set) var callCount = 0
    private(set) var cancelledIDs: Set<String> = []

    func readAttachments(noteID: String) async -> Result<[NotesAppBridge.NoteAttachment], NotesAppError> {
        callCount += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending.append(Pending(id: noteID, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancel(noteID: noteID) }
        }
    }

    func waitForCallCount(_ count: Int) async -> Bool {
        for _ in 0..<100 {
            if callCount >= count { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    func waitForCancellation(of id: String) async -> Bool {
        for _ in 0..<100 {
            if cancelledIDs.contains(id) { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    func resolveNext(with attachments: [NotesAppBridge.NoteAttachment]) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().continuation.resume(returning: .success(attachments))
    }

    func resolveAll() {
        let unresolved = pending
        pending.removeAll()
        for value in unresolved {
            value.continuation.resume(returning: .success([]))
        }
    }

    private func cancel(noteID: String) {
        cancelledIDs.insert(noteID)
        guard let index = pending.firstIndex(where: { $0.id == noteID }) else { return }
        pending.remove(at: index).continuation.resume(returning: .success([]))
    }
}

private actor ControlledNoteLists {
    private var continuations: [CheckedContinuation<Result<[NotesAppBridge.NoteSummary], NotesAppError>, Never>] = []
    private(set) var callCount = 0

    func listNotes() async -> Result<[NotesAppBridge.NoteSummary], NotesAppError> {
        callCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForCallCount(_ count: Int) async -> Bool {
        for _ in 0..<100 {
            if callCount >= count { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    func resolveNext(with notes: [NotesAppBridge.NoteSummary]) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: .success(notes))
    }
}

private actor ControlledImmediateNoteLoads {
    private(set) var callCount = 0

    func readNote(id: String) -> Result<NotesAppBridge.NoteContent, NotesAppError> {
        callCount += 1
        return .success(NotesAppBridge.NoteContent(plainText: id, bodyHTML: "<div>\(id)</div>"))
    }
}

private actor ControlledNoteWrites {
    struct Call: Sendable, Equatable {
        let id: String
        let html: String
    }

    private var continuations: [CheckedContinuation<Result<Void, NotesAppError>, Never>] = []
    private(set) var calls: [Call] = []

    var callCount: Int { calls.count }

    func write(id: String, html: String) async -> Result<Void, NotesAppError> {
        calls.append(Call(id: id, html: html))
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForCallCount(_ count: Int) async -> Bool {
        for _ in 0..<100 {
            if calls.count >= count { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    func resolveNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: .success(()))
    }

    func resolveAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: .success(()))
        }
    }
}

private actor ControlledNoteDeletes {
    private(set) var calls: [String] = []

    var callCount: Int { calls.count }

    func delete(id: String) async -> Result<Void, NotesAppError> {
        calls.append(id)
        return .success(())
    }

    func waitForCallCount(_ count: Int) async -> Bool {
        for _ in 0..<100 {
            if calls.count >= count { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    func resolveAll() {
    }
}

private actor ControlledNoteLoads {
    private var continuations: [CheckedContinuation<Result<NotesAppBridge.NoteContent, NotesAppError>, Never>] = []
    private(set) var callCount = 0

    func readNote(id _: String) async -> Result<NotesAppBridge.NoteContent, NotesAppError> {
        callCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForCallCount(_ count: Int) async -> Bool {
        for _ in 0..<100 {
            if callCount >= count { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    func resolveNext(with content: NotesAppBridge.NoteContent) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: .success(content))
    }

    func resolveAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: .success(NotesAppBridge.NoteContent(plainText: "", bodyHTML: "")))
        }
    }
}
