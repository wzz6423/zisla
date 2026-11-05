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
    @State private var previewTemplate: DailyBriefingTemplate?
    @State private var previewError: String?

    init(model: AppModel) {
        self.model = model
        settingsStore = model.settingsStore
        controller = model.dailyBriefing
    }

    private var language: AppLanguage { model.languageStore.language }

    var body: some View {
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
                .controlSize(.small)
            }

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
                Button { previewTemplate = settingsStore.settings.dailyBriefing.template } label: {
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
        .task(id: language) { await renderThumbnails() }
        .sheet(item: $previewTemplate) { template in
            DailyBriefingPreview(template: template, language: language)
        }
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

    private func renderThumbnails() async {
        let report = DailyBriefingReport.example()
        do {
            var images: [DailyBriefingTemplate: NSImage] = [:]
            for template in DailyBriefingTemplate.allCases {
                try Task.checkCancellation()
                let image = try DailyBriefingRenderer.image(report: report, template: template, language: language, scale: 0.25)
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

private struct DailyBriefingPreview: View {
    let template: DailyBriefingTemplate
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                AppLocalizedText("示例数据")
                Spacer()
                Button { dismiss() } label: { AppLocalizedText("关闭") }
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else if let error {
                    Text(error).foregroundStyle(Color.zislaError)
                } else {
                    ProgressView()
                }
            }
        }
        .padding(20)
        .frame(width: 600, height: 760)
        .task {
            do {
                let rendered = try DailyBriefingRenderer.image(report: .example(), template: template, language: language, scale: 1)
                image = NSImage(cgImage: rendered, size: .zero)
            } catch { self.error = error.localizedDescription }
        }
    }
}
