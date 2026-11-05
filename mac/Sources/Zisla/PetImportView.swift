import SwiftUI
import ZislaCore
import ZislaKit

struct PetImportView: View {
    let sourceURL: URL
    var onImported: (PetLibrary.Entry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isImporting = false
    @State private var errorMessage: String?

    init(sourceURL: URL, onImported: @escaping (PetLibrary.Entry) -> Void) {
        self.sourceURL = sourceURL
        self.onImported = onImported
        _name = State(initialValue: String(sourceURL.deletingPathExtension().lastPathComponent.prefix(80)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppLocalization.text("导入宠物"))
                .font(.headline)
            Text(sourceURL.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            TextField(AppLocalization.text("宠物名称"), text: $name)
                .textFieldStyle(.roundedBorder)
                .disabled(isImporting)
            Text(AppLocalization.text("支持图片和视频，动画最长 30 秒，文件最大 100 MB。"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.zislaError)
                    .textSelection(.enabled)
            }
            HStack {
                if isImporting { ProgressView().controlSize(.small) }
                Spacer()
                Button(AppLocalization.text("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isImporting)
                Button(AppLocalization.text("导入宠物"), action: importPet)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isImporting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .interactiveDismissDisabled(isImporting)
    }

    private func importPet() {
        isImporting = true
        errorMessage = nil
        Task {
            defer { isImporting = false }
            do {
                let entry = try await PetMediaImporter.importPet(from: sourceURL, name: name)
                onImported(entry)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
