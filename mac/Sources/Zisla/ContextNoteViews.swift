import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

enum ContextNoteInputCommand {
    static func isDiscard(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return (event.keyCode == 53 && modifiers.isEmpty) || (event.keyCode == 51 && modifiers == .command)
    }

    static func shouldSave(_ command: Selector, hasMarkedText: Bool) -> Bool {
        command == #selector(NSResponder.insertNewline(_:)) && !hasMarkedText
    }
}

private struct ContextNoteTextField: NSViewRepresentable {
    @Binding var text: String
    let onSave: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = .white
        field.usesSingleLineMode = true
        field.delegate = context.coordinator
        DispatchQueue.main.async { [weak field] in
            guard let field, let window = field.window else { return }
            window.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = AppLocalization.string("在这里记点什么…", locale: context.environment.locale)
        field.setAccessibilityLabel(AppLocalization.string("记录内容", locale: context.environment.locale))
        field.alignment = context.environment.layoutDirection == .rightToLeft ? .right : .left
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ContextNoteTextField
        init(_ parent: ContextNoteTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard ContextNoteInputCommand.shouldSave(commandSelector, hasMarkedText: textView.hasMarkedText()) else { return false }
            parent.onSave()
            return true
        }
    }
}

struct ContextNoteInputView: View {
    @ObservedObject var draft: ContextNoteDraft
    @ObservedObject var settingsStore: FeatureSettingsStore
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            ContextNoteTextField(text: $draft.text, onSave: onSave)
                .frame(maxWidth: .infinity)
                .help(ContextNoteDetailView.locationDescription(draft.location))
            if let error = draft.error {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .help(error)
                    .accessibilityLabel(error)
            }
            Button(action: onDiscard) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .help(AppLocalization.text("放弃便签（Esc / ⌘⌫）"))
            .accessibilityLabel(AppLocalization.text("放弃便签（Esc / ⌘⌫）"))
            Button(action: onSave) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.20, green: 0.90, blue: 0.42))
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(AppLocalization.text("保存便签（Enter）"))
            .accessibilityLabel(AppLocalization.text("保存便签（Enter）"))
        }
        .font(.system(size: 15))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .islandGlassSurface(.input, cornerRadius: 14, isStandalone: true)
        .environment(\.islandVisualStyle, settingsStore.settings.islandVisualStyle)
        .environment(\.colorScheme, .dark)
        .onChange(of: draft.text) { _, _ in draft.error = nil }
    }
}

@MainActor
final class ContextNoteShelfEditor: ObservableObject {
    @Published private(set) var draft: ContextNoteDraft?
    @Published private(set) var isPresented = false
    private(set) var itemID: UUID?
    private var newDraft: ContextNoteDraft?
    private var edits: [UUID: ContextNoteDraft] = [:]

    func begin(_ draft: ContextNoteDraft) {
        newDraft = draft
        self.draft = draft
        itemID = nil
        isPresented = true
    }

    func resumeNew() -> Bool {
        guard let newDraft else { return false }
        begin(newDraft)
        return true
    }

    func open(_ item: FileShelfItem) {
        guard let location = item.noteLocation else { return }
        if edits[item.id] == nil {
            let draft = ContextNoteDraft(location: location, createdAt: item.addedAt)
            draft.text = item.text ?? ""
            edits[item.id] = draft
        }
        draft = edits[item.id]
        itemID = item.id
        isPresented = true
    }

    func hide() { isPresented = false }

    func close() {
        if let itemID { edits.removeValue(forKey: itemID) }
        else { newDraft = nil }
        draft = nil
        itemID = nil
        isPresented = false
    }

    func removed(_ id: UUID) {
        edits.removeValue(forKey: id)
        if itemID == id { close() }
    }

    func save(in shelf: FileShelfStore) -> FileShelfItem? {
        guard let draft, !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let item: FileShelfItem?
        if let itemID {
            item = shelf.updateContextNote(id: itemID, text: draft.text)
        } else {
            item = shelf.addContextNote(draft.text, location: draft.location, addedAt: draft.createdAt)
        }
        guard let item else {
            draft.error = shelf.errorDescription
            return nil
        }
        close()
        return item
    }
}

struct ContextNoteDetailView: View {
    @ObservedObject var draft: ContextNoteDraft
    let onCopy: () -> Void
    let onNavigate: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void
    @FocusState private var isEditing: Bool

    static func locationDescription(_ location: ContextNoteLocation) -> String {
        switch location {
        case let .webPage(url, title, applicationName):
            return [applicationName, title, url.absoluteString].filter { !$0.isEmpty }.joined(separator: " · ")
        case let .window(_, applicationName, title):
            return "\(applicationName) · \(title)"
        case let .desktop(_, displayName):
            return "\(AppLocalization.text("桌面")) · \(displayName)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(AppLocalization.text("位置便签"), systemImage: "note.text")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(AppLocalization.text("复制"), action: onCopy)
                    .buttonStyle(.plain)
                    .disabled(draft.text.isEmpty)
                Button(AppLocalization.text("前往记录位置"), action: onNavigate)
                    .buttonStyle(.plain)
                Button(AppLocalization.text("保存"), action: onSave)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 0.20, green: 0.90, blue: 0.42))
                    .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut("s", modifiers: .command)
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .help(AppLocalization.text("关闭"))
                    .accessibilityLabel(AppLocalization.text("关闭"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    AppLocalizedText("记录位置").foregroundStyle(.secondary)
                    Text(Self.locationDescription(draft.location))
                    AppLocalizedText("记录时间").foregroundStyle(.secondary)
                    Text(draft.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                    AppLocalizedText("记录内容").foregroundStyle(.secondary)
                    TextEditor(text: $draft.text)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 90)
                        .background(Color.fillCard, in: RoundedRectangle(cornerRadius: 6))
                        .focused($isEditing)
                        .accessibilityLabel(AppLocalization.text("记录内容"))
                    if let error = draft.error {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .thinScrollChrome()
        }
        .font(.system(size: 11))
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { isEditing = true }
        .onChange(of: draft.text) { _, _ in draft.error = nil }
    }
}
