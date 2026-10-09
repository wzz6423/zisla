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
                    .foregroundStyle(Color(red: 0.32, green: 1.0, blue: 0.50))
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
    @Published private(set) var screenshot: ShelfScreenshotDetail?
    private(set) var itemID: UUID?
    private var newDraft: ContextNoteDraft?
    private var edits: [UUID: ContextNoteDraft] = [:]

    func begin(_ draft: ContextNoteDraft) {
        screenshot = nil
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
        screenshot = nil
        if edits[item.id] == nil {
            let draft = ContextNoteDraft(location: location, createdAt: item.addedAt)
            draft.text = item.text ?? ""
            edits[item.id] = draft
        }
        draft = edits[item.id]
        itemID = item.id
        isPresented = true
    }

    func openScreenshot(_ item: FileShelfItem, in shelf: FileShelfStore) throws {
        guard let metadata = item.screenshotMetadata,
              let image = NSImage(data: try shelf.screenshotData(id: item.id)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        screenshot = ShelfScreenshotDetail(id: item.id, metadata: metadata, image: image)
        isPresented = false
    }

    func hide() {
        screenshot = nil
        isPresented = false
    }

    func close() {
        if screenshot != nil {
            screenshot = nil
            return
        }
        if let itemID { edits.removeValue(forKey: itemID) }
        else { newDraft = nil }
        draft = nil
        itemID = nil
        isPresented = false
    }

    func removed(_ id: UUID) {
        if screenshot?.id == id { screenshot = nil }
        edits.removeValue(forKey: id)
        if itemID == id {
            draft = nil
            itemID = nil
            isPresented = false
        }
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
        ShelfDetailView(title: AppLocalization.text("位置便签"), systemImage: "note.text",
                        locationDescription: Self.locationDescription(draft.location), createdAt: draft.createdAt,
                        onCopy: onCopy, onNavigate: onNavigate, onSave: onSave, onClose: onClose,
                        canCopy: !draft.text.isEmpty,
                        canSave: !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
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
        .onAppear { isEditing = true }
        .onChange(of: draft.text) { _, _ in draft.error = nil }
    }
}

struct ShelfScreenshotDetail {
    let id: UUID
    let metadata: ShelfScreenshotMetadata
    let image: NSImage
}

struct ShelfScreenshotDetailView: View {
    let detail: ShelfScreenshotDetail
    let onCopy: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        ShelfDetailView(title: AppLocalization.text("暂存截图"), systemImage: "camera",
                        locationDescription: detail.metadata.source.applicationName
                            ?? detail.metadata.source.bundleIdentifier ?? AppLocalization.text("截图"),
                        createdAt: detail.metadata.source.capturedAt,
                        onCopy: onCopy, onSave: onSave, onClose: onClose) {
            Image(nsImage: detail.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(AppLocalization.text(detail.metadata.isLongScreenshot ? "长截图" : "截图"))
            Text("\(detail.metadata.pixelWidth) × \(detail.metadata.pixelHeight)")
                .foregroundStyle(.secondary)
        }
    }
}

struct ShelfDetailView<Content: View>: View {
    let title: String
    let systemImage: String
    let locationDescription: String
    let createdAt: Date
    let onCopy: () -> Void
    var onNavigate: (() -> Void)?
    let onSave: () -> Void
    let onClose: () -> Void
    var canCopy = true
    var canSave = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(AppLocalization.text("复制"), action: onCopy)
                    .buttonStyle(.plain)
                    .disabled(!canCopy)
                if let onNavigate {
                    Button(AppLocalization.text("前往记录位置"), action: onNavigate)
                        .buttonStyle(.plain)
                }
                Button(AppLocalization.text("保存"), action: onSave)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 0.32, green: 1.0, blue: 0.50))
                    .disabled(!canSave)
                    .keyboardShortcut("s", modifiers: .command)
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .help(AppLocalization.text("关闭"))
                    .accessibilityLabel(AppLocalization.text("关闭"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    AppLocalizedText("记录位置").foregroundStyle(.secondary)
                    Text(locationDescription)
                    AppLocalizedText("记录时间").foregroundStyle(.secondary)
                    Text(createdAt, format: .dateTime.year().month().day().hour().minute().second())
                    AppLocalizedText("记录内容").foregroundStyle(.secondary)
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .thinScrollChrome()
        }
        .font(.system(size: 11))
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
