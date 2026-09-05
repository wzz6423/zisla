import ZislaCore
import ZislaKit
import SwiftUI

/// "Quick Notes" module: uses the system Notes app as its data source.
///
/// The left column lists existing notes from Notes (with refresh/create/delete actions); the right side
/// edits the note body in a rich-text editor. Drafts are automatically written back to Notes 0.8 s after
/// the user stops typing, enabling both viewing/editing existing notes and creating new ones — not just appending.
struct QuickNoteModuleView: View {
    @ObservedObject var model: AppModel

    @State private var draftHTML: String = "<div><br></div>"
    @State private var draftPlainText: String = ""
    @State private var noteContent: NotesAppBridge.NoteContent?
    @State private var draftLoadGeneration = 0
    @State private var editorCommand: RichNoteEditorCommand?
    @State private var isTransferTarget = false

    private var service: QuickNotesService { model.quickNotes }

    var body: some View {
        HStack(spacing: 0) {
            noteListColumn
                .frame(width: 152)
            Hairline()
            editorColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await service.refresh()
            cancelAndLoadDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Sync the list when returning from an external app such as Notes (removes stale entries after external deletions).
            Task { await service.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // When a menu-bar accessory app returns from Notes or another external app the app may not become active again,
            // but the panel/window becomes the key window — do an extra refresh here to keep the list in sync.
            Task { await service.refresh() }
        }
        .onChange(of: service.selectedID) { _, _ in
            cancelAndLoadDraft()
        }
    }

    // MARK: - Note list

    private var noteListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(AppLocalization.text("随记"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                Text("\(service.notes.count)")
                    .font(.islandMicro())
                    .foregroundStyle(.secondary)
                IconButton(symbol: "arrow.clockwise", help: AppLocalization.text("刷新备忘录"), size: .compact) {
                    Task { await service.refresh() }
                }
                IconButton(symbol: "plus", help: AppLocalization.text("新建随记"), size: .compact) {
                    Task { await createNew() }
                }
            }
            .frame(height: 28)
            .padding(.horizontal, 4)

            Group {
                if service.isLoadingList && service.notes.isEmpty && service.welcomeNote == nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = service.errorMessage, service.notes.isEmpty, service.welcomeNote == nil {
                    listErrorView(error)
                } else if service.notes.isEmpty, service.welcomeNote == nil {
                    EmptyState(symbol: "note.text", title: AppLocalization.text("备忘录暂无笔记"), detail: AppLocalization.text("点 + 新建一条"))
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            if let welcomeNote = service.welcomeNote {
                                noteRow(welcomeNote)
                            }
                            if service.welcomeNote != nil && !service.regularNotes.isEmpty {
                                Divider()
                                    .overlay(Color.dividerSubtle)
                                    .padding(.vertical, 3)
                            }
                            ForEach(service.regularNotes) { note in
                                noteRow(note)
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                    .thinScrollChrome()
                }
            }
        }
        .padding(.trailing, 8)
    }

    private func listErrorView(_ message: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.zislaWarning)
            Text(AppLocalization.text("无法读取备忘录"))
                .font(.system(size: 10, weight: .semibold))
            Text(message)
                .font(.islandMicro())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button(AppLocalization.text("重试")) { Task { await service.refresh() } }
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func noteRow(_ note: NotesAppBridge.NoteSummary) -> some View {
        let selected = note.id == service.selectedID
        return Button {
            service.select(id: note.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? AppLocalization.text("无标题") : note.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.86))
                    .lineLimit(2)
                HStack(spacing: 3) {
                    if note.isPasswordProtected {
                        Image(systemName: "lock.fill")
                    }
                    Text(service.isBuiltInWelcomeNote(id: note.id) ? AppLocalization.text("内置说明") : note.modifiedAt.map { relativeTime($0) } ?? "—")
                }
                .font(.islandMicro())
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if selected {
                    SelectionGlassBackground(cornerRadius: 7)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(AppLocalization.text("删除"), role: .destructive) {
                Task { await service.delete(id: note.id) }
            }
        }
    }

    // MARK: - Editing

    private var editorPaneShape: UnevenRoundedRectangle {
        IslandSurfaceGeometry.moduleContentShape(
            bottomTrailingRadius: IslandSurfaceGeometry.moduleOuterBottomCornerRadius
        )
    }

    private var editorColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorToolbar
                .frame(height: 34)
                .padding(.bottom, 2)

            if let noteContent {
                ReadOnlyNoteMetadata(
                    content: noteContent,
                    showNote: service.showSelectedNoteInNotes,
                    showAttachment: { service.showAttachmentInNotes(id: $0.id) },
                    wordCount: draftPlainText.count
                )
                .frame(height: 20)
                .padding(.bottom, 2)
            }

            editorPane
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .islandGlassSurface(
                .input,
                cornerRadius: IslandSurfaceGeometry.moduleInnerCornerRadius,
                bottomTrailingRadius: IslandSurfaceGeometry.moduleOuterBottomCornerRadius
            )
        }
        .padding(.leading, 10)
    }

    private var editorToolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(service.selectedNote?.title ?? AppLocalization.text("随记"))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if service.isLoadingNote {
                ProgressView().controlSize(.mini)
            } else if service.isSaving {
                ProgressView().controlSize(.mini)
            }
            Spacer(minLength: 6)
            RichNoteToolbar(command: $editorCommand)
                .frame(maxWidth: .infinity)
                .disabled(service.isBuiltInWelcomeNoteSelected)
            IconButton(symbol: "text.viewfinder", help: AppLocalization.text("发送到提词器"), size: .compact) {
                model.sendQuickNoteToTeleprompter(draftPlainText)
            }
            .disabled(draftPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            IconButton(symbol: "arrow.up.left.and.arrow.down.right", help: AppLocalization.text("展开大窗口编辑"), size: .compact) {
                (NSApp.delegate as? AppDelegate)?.openQuickNotesEditor()
            }
            IconButton(symbol: "square.and.arrow.up", help: AppLocalization.text("系统共享"), size: .compact) {
                model.share([.text(draftPlainText)])
            }
            .disabled(draftPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var editorPane: some View {
        Group {
            if noteContent?.isPasswordProtected == true {
                LockedNotePlaceholder(showNote: service.showSelectedNoteInNotes)
            } else {
                RichNoteEditor(
                    html: draftHTML,
                    command: service.isBuiltInWelcomeNoteSelected ? nil : editorCommand,
                    isEditable: !service.isBuiltInWelcomeNoteSelected
                ) { html, plainText in
                    draftHTML = html
                    draftPlainText = plainText
                    if let id = service.selectedID, !service.isBuiltInWelcomeNote(id: id) {
                        service.scheduleSave(id: id, html: html)
                    }
                }
            }
        }
        .overlay {
            if isTransferTarget {
                editorPaneShape
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: TransferDropDelegate.supportedTypes,
            delegate: TransferDropDelegate(isTargeted: $isTransferTarget) {
                model.receiveQuickNoteTransferItems($0)
            }
        )
    }

    // MARK: - Actions

    private func cancelAndLoadDraft() {
        draftLoadGeneration &+= 1
        let generation = draftLoadGeneration
        let selectedID = service.selectedID
        Task {
            let content = await service.loadNote()
            guard generation == draftLoadGeneration, selectedID == service.selectedID else { return }
            noteContent = content
            draftHTML = RichNoteEditor.editableHTML(for: content)
            draftPlainText = content?.plainText ?? ""
        }
    }

    private func createNew() async {
        _ = await service.create(html: RichNoteEditor.newNoteHTML)
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return AppLocalization.text("刚刚") }
        if interval < 3600 { return AppLocalization.text("%ld 分钟前", Int(interval / 60)) }
        if interval < 86400 { return AppLocalization.text("%ld 小时前", Int(interval / 3600)) }
        let calendar = Calendar.current
        if calendar.isDateInYesterday(date) { return AppLocalization.text("昨天") }
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
