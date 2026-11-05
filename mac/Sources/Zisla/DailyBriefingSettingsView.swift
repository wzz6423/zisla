import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct DailyBriefingSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settingsStore: FeatureSettingsStore
    @ObservedObject private var controller: DailyBriefingController
    @Environment(\.locale) private var locale
    @State private var thumbnails: [DailyBriefingTemplate: NSImage] = [:]
    @State private var previewWindowController: DailyBriefingPreviewWindowController?
    @State private var previewError: String?
    @State private var contentExpanded = false

    private struct PreviewRequest: Hashable {
        let language: AppLanguage
        let selectedContent: Set<DailyBriefingContent>
    }

    init(model: AppModel) {
        self.model = model
        settingsStore = model.settingsStore
        controller = model.dailyBriefing
    }

    private var language: AppLanguage { model.languageStore.language }
    private var selectedContent: Set<DailyBriefingContent> { settingsStore.settings.dailyBriefing.selectedContent }

    var body: some View {
        let request = PreviewRequest(language: language, selectedContent: selectedContent)
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $settingsStore.settings.dailyBriefing.enabled) {
                AppLocalizedText("每日简报")
            }
            .toggleStyle(.switch)
            .settingsSearchAnchor(.row(AppLocalization.string("每日简报", locale: locale)))

            HStack {
                AppLocalizedText("导出时间")
                Spacer()
                DatePicker("", selection: exportTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityLabel(AppLocalization.string("导出时间", locale: locale))
            }
            .disabled(!settingsStore.settings.dailyBriefing.enabled)

            HStack(spacing: 12) {
                Toggle(isOn: $settingsStore.settings.dailyBriefing.readsSystemScreenTime) {
                    AppLocalizedText("读取系统屏幕使用时间")
                }
                .toggleStyle(.switch)
                .disabled(!settingsStore.settings.dailyBriefing.enabled)

                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                } label: { AppLocalizedText("完全磁盘访问") }
            }

            Divider()
            DisclosureGroup(isExpanded: $contentExpanded) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Spacer()
                        Button { settingsStore.settings.dailyBriefing.selectedContent = DailyBriefingContent.defaultSelection } label: {
                            AppLocalizedText("全选")
                        }
                        .disabled(selectedContent == DailyBriefingContent.defaultSelection)
                        Button { settingsStore.settings.dailyBriefing.selectedContent = [] } label: {
                            AppLocalizedText("取消全选")
                        }
                        .disabled(selectedContent.isEmpty)
                    }
                    .controlSize(.small)
                    ForEach(DailyBriefingContentGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            AppLocalizedText(group.title).font(.caption.weight(.medium))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 8) {
                                ForEach(group.contents) { content in
                                    Toggle(isOn: contentBinding(content)) { AppLocalizedText(content.title) }
                                        .toggleStyle(.checkbox)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 12)
            } label: {
                AppLocalizedText("简报内容").font(.subheadline.weight(.medium))
            }
            .settingsSearchAnchor(.row(AppLocalization.string("简报内容", locale: locale)))

            Divider()
            HStack {
                AppLocalizedText("简报模板").font(.subheadline.weight(.medium))
                Spacer()
                AppLocalizedText("示例数据").font(.caption).foregroundStyle(.secondary)
            }
            .settingsSearchAnchor(.row(AppLocalization.string("简报模板", locale: locale)))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], spacing: 12) {
                ForEach(DailyBriefingTemplate.allCases) { template in
                    templateButton(template)
                }
            }

            HStack(spacing: 12) {
                Button { showPreview() } label: {
                    Label(AppLocalization.string("预览", locale: locale), systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Spacer()
                if controller.isExporting { ProgressView().controlSize(.small) }
                Button { Task { await controller.exportToday() } } label: {
                    Label(AppLocalization.string("导出今日简报", locale: locale), systemImage: "square.and.arrow.down")
                }
                .disabled(!settingsStore.settings.dailyBriefing.enabled || controller.isExporting)
            }

            if let error = controller.errorMessage ?? previewError {
                Text(error).font(.caption).foregroundStyle(Color.zislaError).textSelection(.enabled)
            }
            if let url = controller.lastExportURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Label(url.lastPathComponent, systemImage: "checkmark.circle")
                }
                .font(.caption).buttonStyle(.plain).foregroundStyle(Color.zislaSuccess)
            }
        }
        .font(.system(size: 11))
        .padding(.vertical, 8)
        .task(id: request) { await renderThumbnails(request) }
        .onChange(of: request) { _, request in
            previewWindowController?.update(template: settingsStore.settings.dailyBriefing.template,
                language: request.language, selectedContent: request.selectedContent)
        }
        .onChange(of: settingsStore.settings.dailyBriefing.template) { _, template in
            previewWindowController?.update(template: template, language: language, selectedContent: selectedContent)
        }
    }

    private func showPreview() {
        let preview = previewWindowController ?? DailyBriefingPreviewWindowController()
        previewWindowController = preview
        preview.update(template: settingsStore.settings.dailyBriefing.template, language: language, selectedContent: selectedContent)
        preview.showWindow(nil)
    }

    private func contentBinding(_ content: DailyBriefingContent) -> Binding<Bool> {
        Binding(
            get: { selectedContent.contains(content) },
            set: { selected in
                if selected { settingsStore.settings.dailyBriefing.selectedContent.insert(content) }
                else { settingsStore.settings.dailyBriefing.selectedContent.remove(content) }
            }
        )
    }

    private var exportTime: Binding<Date> {
        Binding(
            get: {
                let calendar = DailyBriefingDay.calendar
                return settingsStore.settings.dailyBriefing.exportDate(on: Date(), calendar: calendar)
            },
            set: { date in
                let parts = DailyBriefingDay.calendar.dateComponents([.hour, .minute], from: date)
                settingsStore.settings.dailyBriefing.minuteOfDay = parts.hour! * 60 + parts.minute!
            }
        )
    }

    private func templateButton(_ template: DailyBriefingTemplate) -> some View {
        let selected = settingsStore.settings.dailyBriefing.template == template
        return Button { settingsStore.settings.dailyBriefing.template = template } label: {
            VStack(spacing: 8) {
                Group {
                    if let thumbnail = thumbnails[template] {
                        Image(nsImage: thumbnail).resizable().scaledToFit()
                    } else {
                        Rectangle().fill(.quaternary).overlay { ProgressView().controlSize(.small) }
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                HStack {
                    AppLocalizedText(template.title)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
                .font(.caption)
            }
            .padding(9)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1) }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.string(template.title, locale: locale))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func renderThumbnails(_ request: PreviewRequest) async {
        let report = DailyBriefingReport.example(selectedContent: request.selectedContent)
        do {
            var images: [DailyBriefingTemplate: NSImage] = [:]
            for template in DailyBriefingTemplate.allCases {
                try Task.checkCancellation()
                let image = try DailyBriefingRenderer.image(report: report, template: template, language: request.language, scale: 0.25)
                images[template] = NSImage(cgImage: image, size: .zero)
                await Task.yield()
            }
            try Task.checkCancellation()
            thumbnails = images
            previewError = nil
        } catch is CancellationError {
        } catch { previewError = error.localizedDescription }
    }
}

@MainActor
final class DailyBriefingPreviewWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = NSSize(width: 360, height: 320)
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(template: DailyBriefingTemplate, language: AppLanguage,
                selectedContent: Set<DailyBriefingContent> = DailyBriefingContent.defaultSelection) {
        window?.title = AppLocalization.string("每日简报", language: language)
            + " · " + AppLocalization.string(template.title, language: language)
        window?.contentView = NSHostingView(rootView: DailyBriefingPreview(template: template, language: language, selectedContent: selectedContent))
    }
}

struct DailyBriefingPreview: View {
    let template: DailyBriefingTemplate
    let language: AppLanguage
    var selectedContent: Set<DailyBriefingContent> = DailyBriefingContent.defaultSelection
    @State private var image: NSImage?
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let error {
                Text(error).foregroundStyle(Color.zislaError)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            do {
                let rendered = try DailyBriefingRenderer.image(report: .example(selectedContent: selectedContent), template: template, language: language, scale: 1)
                image = NSImage(cgImage: rendered, size: .zero)
            } catch { self.error = error.localizedDescription }
        }
    }
}
