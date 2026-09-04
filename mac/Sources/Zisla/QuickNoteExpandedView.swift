import ZislaCore
import ZislaKit
import SwiftUI

/// The "large window" editing view for Quick Note: provides rich-text editing on par with
/// the system Notes app, in a space far larger than the inline Dynamic Island panel, making
/// it convenient to write longer notes with rich media.
///
/// Reads and writes directly to the currently selected note in the system Notes app
/// (sharing `QuickNotesService` with the inline Dynamic Island note), with a 0.8 s
/// debounce before writing back.
struct QuickNoteExpandedView: View {
    @ObservedObject var model: AppModel

    @State private var draftHTML: String = "<div><br></div>"
    @State private var draftPlainText: String = ""
    @State private var noteContent: NotesAppBridge.NoteContent?
    @State private var draftLoadGeneration = 0
    @State private var editorCommand: RichNoteEditorCommand?

    private var service: QuickNotesService { model.quickNotes }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 38)
                .padding(.horizontal, 12)

            Divider().overlay(Color.dividerSubtle)

            toolbarWithWordCount
                .frame(height: 34)
                .padding(.horizontal, 12)

            if let noteContent, shouldShowMetadata(noteContent) {
                ReadOnlyNoteMetadata(
                    content: noteContent,
                    showNote: service.showSelectedNoteInNotes,
                    showAttachment: { service.showAttachmentInNotes(id: $0.id) },
                    wordCount: draftPlainText.count,
                    showsWordCount: false
                )
                    .frame(height: 30)
                    .padding(.horizontal, 12)
            }

            editorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 540)
        .task {
            await service.refresh()
            await loadDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await service.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Menu-bar accessory apps don't always re-activate when switching back from Notes or
            // another external app, but the window will become key — do an extra refresh here to
            // keep the list in sync.
            Task { await service.refresh() }
        }
        .onChange(of: service.selectedID) { _, _ in
            Task { await loadDraft() }
        }
    }

    // MARK: - Toolbar with word count

    private var toolbarWithWordCount: some View {
        HStack(spacing: 0) {
            RichNoteToolbar(command: $editorCommand)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(service.isBuiltInWelcomeNoteSelected)

            if noteContent != nil {
                Text(AppLocalization.text("%ld 字", draftPlainText.count))
                    .font(.islandMicro())
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .padding(.leading, 12)
            }
        }
    }

    private func shouldShowMetadata(_ content: NotesAppBridge.NoteContent) -> Bool {
        content.isPasswordProtected || !content.tags.isEmpty || !content.attachments.isEmpty
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(service.selectedNote?.title ?? AppLocalization.text("随记"))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if service.isLoadingNote || service.isSaving {
                ProgressView().controlSize(.small)
            }
            Spacer(minLength: 6)
            IconButton(symbol: "square.and.arrow.up", help: AppLocalization.text("系统共享"), size: .compact) {
                model.share([.text(draftPlainText)])
            }
            .disabled(draftPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Editor

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
        .background(
            VisualEffectBackground()
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(edgeHighlight, lineWidth: 1)
        }
    }

    private var edgeHighlight: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.26), location: 0),
                .init(color: .white.opacity(0.07), location: 0.5),
                .init(color: .white.opacity(0.03), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Actions

    private func loadDraft() async {
        draftLoadGeneration &+= 1
        let generation = draftLoadGeneration
        let selectedID = service.selectedID
        let content = await service.loadNote()
        guard generation == draftLoadGeneration, selectedID == service.selectedID else { return }
        noteContent = content
        draftHTML = RichNoteEditor.editableHTML(for: content)
        draftPlainText = content?.plainText ?? ""
    }

}
