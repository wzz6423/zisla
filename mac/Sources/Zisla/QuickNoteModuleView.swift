import ZislaKit
import SwiftUI

/// 「随记」模块：以系统「备忘录」为数据源。
///
/// 左侧列出备忘录中已有的笔记（可刷新/新建/删除），右侧编辑或预览：编辑态用
/// `TextEditor` 读写选中笔记的 Markdown 原文，预览态用 `MarkdownRenderer` 渲染；
/// 草稿停止输入 0.8 秒后自动写回备忘录。这样既能查看、编辑已有的备忘录笔记，
/// 也能新建——而不仅限于新增。
struct QuickNoteModuleView: View {
    @ObservedObject var model: AppModel

    @State private var draft: String = ""
    @State private var lastLoadedDraft: String = ""
    @State private var noteContent: NotesAppBridge.NoteContent?
    @State private var isPreview = false

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
            // 从备忘录 App 等外部返回时同步列表（外部删除后清掉陈旧条目）
            Task { await service.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // 菜单栏 accessory 应用从备忘录等外部切回时，app 不一定重新 active，
            // 但面板/窗口会成为 key window，此时补一次刷新确保列表同步。
            Task { await service.refresh() }
        }
        .onChange(of: service.selectedID) { _, _ in
            cancelAndLoadDraft()
        }
        .onChange(of: draft) { _, newValue in
            // 载入产生的相同内容不触发写回；只有用户改动才保存
            guard let id = service.selectedID,
                  noteContent?.usesNativeHTML != true,
                  newValue != lastLoadedDraft
            else { return }
            service.scheduleSave(id: id, markdown: newValue)
        }
    }

    // MARK: - 笔记列表

    private var noteListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("随记")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                Text("\(service.notes.count)")
                    .font(.islandMicro())
                    .foregroundStyle(.secondary)
                IconButton(symbol: "arrow.clockwise", help: "刷新备忘录", size: .compact) {
                    Task { await service.refresh() }
                }
                IconButton(symbol: "plus", help: "新建随记", size: .compact) {
                    Task { await createNew() }
                }
            }
            .frame(height: 28)
            .padding(.horizontal, 4)

            Group {
                if service.isLoadingList && service.notes.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = service.errorMessage, service.notes.isEmpty {
                    listErrorView(error)
                } else if service.notes.isEmpty {
                    EmptyState(symbol: "note.text", title: "备忘录暂无笔记", detail: "点 + 新建一条")
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
            Text("无法读取备忘录")
                .font(.system(size: 10, weight: .semibold))
            Text(message)
                .font(.islandMicro())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button("重试") { Task { await service.refresh() } }
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func noteRow(_ note: NotesAppBridge.NoteSummary) -> some View {
        let selected = note.id == service.selectedID
        return Button {
            service.select(id: note.id)
            isPreview = false
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "无标题" : note.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.86))
                    .lineLimit(2)
                Text(note.modifiedAt.map { relativeTime($0) } ?? "—")
                    .font(.islandMicro())
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.16) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("删除", role: .destructive) {
                Task { await service.delete(id: note.id) }
            }
        }
    }

    // MARK: - 编辑 / 预览

    private var editorColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorToolbar
                .frame(height: 30)
                .padding(.bottom, 6)

            Group {
                if isPreview {
                    previewPane
                } else {
                    editorPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fillCard)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.strokeCard, lineWidth: 1)
            }

            editorFooter
                .frame(height: 18)
                .padding(.top, 5)
        }
        .padding(.leading, 10)
    }

    private var editorToolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(service.selectedNote?.title ?? "随记")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if service.isLoadingNote {
                ProgressView().controlSize(.mini)
            } else if service.isSaving {
                ProgressView().controlSize(.mini)
            }
            Spacer(minLength: 6)
            Picker("", selection: $isPreview) {
                Image(systemName: "square.and.pencil").tag(false)
                Image(systemName: "eye").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .frame(width: 64)
            .disabled(noteContent?.usesNativeHTML == true)
            IconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "展开大窗口编辑", size: .compact) {
                (NSApp.delegate as? AppDelegate)?.openQuickNotesEditor()
            }
            IconButton(symbol: "square.and.arrow.up", help: "系统共享", size: .compact) {
                model.share([.text(draft)])
            }
            .disabled(draft.isEmpty)
        }
    }

    private var editorPane: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draft)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            if draft.isEmpty {
                Text("在此输入 Markdown…\n# 标题  ·  **粗体**  ·  *斜体*  ·  `代码`  ·  - 列表")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
    }

    private var previewPane: some View {
        MarkdownWebView(
            html: previewHTML,
            baseURL: URL(fileURLWithPath: NSHomeDirectory())
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorFooter: some View {
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

    private func cancelAndLoadDraft() {
        service.cancelPendingSave()
        Task {
            let content = await service.loadNote()
            noteContent = content
            let text = content?.plainText ?? ""
            lastLoadedDraft = text
            draft = text
            isPreview = content?.usesNativeHTML == true
        }
    }

    private var previewHTML: String {
        if let content = noteContent, content.usesNativeHTML {
            return MarkdownHTMLRenderer.html(fromNotesHTML: content.bodyHTML)
        }
        return MarkdownHTMLRenderer.html(from: draft)
    }

    private func createNew() async {
        let success = await service.create(markdown: "# 新随记\n")
        if success {
            isPreview = false
            // 新建后 selectedID 变化会触发 cancelAndLoadDraft 载入草稿
        }
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
