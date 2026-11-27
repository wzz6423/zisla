import SwiftUI
import ZislaCore
import ZislaKit

struct PetSelectionDraft {
    let mode: PetSelectionMode
    let availableIDs: Set<String>
    var selectedIDs: Set<String>
    var previewID: String?

    init(settings: FeatureSettings, availableIDs: [String], currentID: String?) {
        mode = settings.petSelectionMode
        self.availableIDs = Set(availableIDs)
        selectedIDs = settings.petRandomPool.map { $0.intersection(availableIDs) } ?? self.availableIDs
        previewID = currentID ?? availableIDs.first
    }

    var canApply: Bool {
        switch mode {
        case .fixed: previewID != nil
        case .randomRotation: !selectedIDs.isEmpty
        }
    }

    func apply(to settings: inout FeatureSettings) {
        switch mode {
        case .fixed:
            if let previewID { settings.petID = previewID }
        case .randomRotation:
            guard !selectedIDs.isEmpty else { return }
            settings.petRandomPool = selectedIDs == availableIDs ? nil : selectedIDs
        }
    }
}

struct PetSelectionView: View {
    let entries: [PetLibrary.Entry]
    let displayLabel: (PetLibrary.Entry) -> String
    @Binding private var settings: FeatureSettings
    @State private var draft: PetSelectionDraft
    @Environment(\.dismiss) private var dismiss

    init(entries: [PetLibrary.Entry], settings: Binding<FeatureSettings>, currentID: String?,
         displayLabel: @escaping (PetLibrary.Entry) -> String) {
        self.entries = entries
        self.displayLabel = displayLabel
        _settings = settings
        _draft = State(initialValue: PetSelectionDraft(settings: settings.wrappedValue,
                                                       availableIDs: entries.map(\.id), currentID: currentID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppLocalizedText(draft.mode == .randomRotation ? "随机范围" : "选择宠物")
                .font(.headline)
            HStack(spacing: 16) {
                List(entries, selection: $draft.previewID) { entry in
                    HStack {
                        if draft.mode == .randomRotation {
                            Toggle(displayLabel(entry), isOn: Binding(
                                get: { draft.selectedIDs.contains(entry.id) },
                                set: { included in
                                    if included { draft.selectedIDs.insert(entry.id) }
                                    else { draft.selectedIDs.remove(entry.id) }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        }
                        Text(displayLabel(entry))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .tag(entry.id)
                }
                .listStyle(.inset)
                if let entry = entries.first(where: { $0.id == draft.previewID }) {
                    VStack(spacing: 10) {
                        PetPreviewView(petID: entry.id, size: CGSize(width: 112, height: 112))
                        Text(displayLabel(entry))
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 140)
                }
            }
            .frame(height: 248)
            HStack {
                if draft.mode == .randomRotation {
                    Button(AppLocalization.text("全选")) { draft.selectedIDs = draft.availableIDs }
                        .disabled(draft.selectedIDs == draft.availableIDs)
                    Button(AppLocalization.text("取消全选")) { draft.selectedIDs.removeAll() }
                        .disabled(draft.selectedIDs.isEmpty)
                }
                Spacer()
                Button(AppLocalization.text("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(AppLocalization.text("完成")) {
                    draft.apply(to: &settings)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canApply)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}
