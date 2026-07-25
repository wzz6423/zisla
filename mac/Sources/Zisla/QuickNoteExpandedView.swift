import ZislaKit
import SwiftUI

/// 随记的「大窗口」编辑视图：左侧 Markdown 源文编辑、右侧实时富预览（图片/表格等），
/// 区域远大于灵动岛内嵌面板，便于撰写较长、含富媒体的笔记。
///
/// 直接读写系统「备忘录」当前选中笔记（与灵动岛内的随记共用 `QuickNotesService`），
/// 停止输入 0.8 秒后防抖写回。
struct QuickNoteExpandedView: View {
    @ObservedObject var model: AppModel

    @State private var draft: String = ""
    @State private var lastLoadedDraft: String = ""
    @State private var noteContent: NotesAppBridge.NoteContent?
    @State private var isPreviewOnly = false

    private var service: QuickNotesService { model.quickNotes }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 38)
                .padding(.horizontal, 12)

            Divider().overlay(Color.dividerSubtle)

            HStack(spacing: 0) {
                if !isPreviewOnly {
                    editorPane
                        .frame(minWidth: 340, idealWidth: 460, maxWidth: .infinity)
                    Divider().overlay(Color.dividerSubtle)
                }
                previewPane
                    .frame(minWidth: 340, idealWidth: 460, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
                .frame(height: 22)
                .padding(.horizontal, 12)
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
            // 菜单栏 accessory 应用从备忘录等外部切回时，app 不一定重新 active，
            // 但窗口会成为 key window，此时补一次刷新确保列表同步。
            Task { await service.refresh() }
        }
        .onChange(of: service.selectedID) { _, _ in
            Task { await loadDraft() }
        }
        .onChange(of: draft) { _, newValue in
            guard let id = service.selectedID,
                  noteContent?.usesNativeHTML != true,
                  newValue != lastLoadedDraft
            else { return }
            service.scheduleSave(id: id, markdown: newValue)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(service.selectedNote?.title ?? "随记")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if service.isLoadingNote || service.isSaving {
                ProgressView().controlSize(.small)
            }
            Spacer(minLength: 6)
            Picker("", selection: $isPreviewOnly) {
                Image(systemName: "square.split.2x2").tag(false)
                Image(systemName: "eye").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 72)
            .help("并排 / 仅预览")
            .disabled(noteContent?.usesNativeHTML == true)
            IconButton(symbol: "square.and.arrow.up", help: "系统共享", size: .compact) {
                model.share([.text(draft)])
            }
            .disabled(draft.isEmpty)
        }
    }

    // MARK: - 编辑

    private var editorPane: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draft)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            if draft.isEmpty {
                Text("在此输入 Markdown…\n# 标题  ·  **粗体**  ·  *斜体*  ·  `代码`  ·  - 列表\n| 表头 | 表头 |\n| --- | --- |")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.fillCard)
    }

    // MARK: - 预览

    private var previewPane: some View {
        MarkdownWebView(
            html: previewHTML,
            baseURL: URL(fileURLWithPath: NSHomeDirectory())
        )
        .background(Color.fillCard)
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 8) {
            if let note = service.selectedNote, let modified = note.modifiedAt {
                Text("更新于 \(relativeTime(modified))")
            }
            Spacer(minLength: 4)
            Text("\(draft.count) 字")
        }
        .font(.islandMicro())
        .foregroundStyle(.tertiary)
    }

    // MARK: - 动作

    private func loadDraft() async {
        service.cancelPendingSave()
        let content = await service.loadNote()
        noteContent = content
        let text = content?.plainText ?? ""
        lastLoadedDraft = text
        draft = text
        isPreviewOnly = content?.usesNativeHTML == true
    }

    private var previewHTML: String {
        if let content = noteContent, content.usesNativeHTML {
            return MarkdownHTMLRenderer.html(fromNotesHTML: content.bodyHTML)
        }
        return MarkdownHTMLRenderer.html(from: draft)
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        let calendar = Calendar.current
        if calendar.isDateInYesterday(date) { return "昨天" }
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
