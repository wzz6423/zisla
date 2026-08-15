import AppKit
import ImageIO
import ZislaKit
import SwiftUI
import UniformTypeIdentifiers

/// Filter dimension for the clipboard list.
/// - `all`: everything (pinned + history); the default view, equivalent to showing both sections simultaneously.
/// - `pinned`: favorites (pinned/starred items).
/// - `history`: non-favorites (regular history items).
private enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all
    case pinned
    case history

    var id: String { rawValue }

    var scope: ClipboardHistoryScope {
        switch self {
        case .all: .all
        case .pinned: .pinned
        case .history: .history
        }
    }

    var title: String {
        switch self {
        case .all: "全部"
        case .pinned: "常用"
        case .history: "非常用"
        }
    }

    /// Outline icon when not selected.
    var icon: String {
        switch self {
        case .all: "tray.full"
        case .pinned: "star"
        case .history: "clock"
        }
    }

    /// Filled icon when selected (active), providing a clear visual difference from the unselected state.
    var activeIcon: String {
        switch self {
        case .all: "tray.full.fill"
        case .pinned: "star.fill"
        case .history: "clock.fill"
        }
    }
}

private enum ClipboardAdditionPresentation: Equatable {
    case picker
    case textEditor
}

struct ClipboardHistoryModuleView: View {
    @ObservedObject private var store: ClipboardHistoryStore
    @State private var filter: ClipboardFilter = .all
    @State private var categoryFilter: FileShelfCategory = .all
    @State private var additionPresentation: ClipboardAdditionPresentation?
    @State private var draftText = ""
    @State private var searchText = ""
    @FocusState private var isDraftTextFocused: Bool
    @FocusState private var isSearchFocused: Bool
    private let copyItem: (ClipboardHistoryItem) -> Void
    private let sendToQuickNote: (ClipboardHistoryItem) -> Void
    private let sendToAIAgent: (ClipboardHistoryItem) -> Void
    private static let surfaceShape = UnevenRoundedRectangle(
        cornerRadii: .init(
            topLeading: IslandSurfaceGeometry.moduleInnerCornerRadius,
            bottomLeading: IslandSurfaceGeometry.moduleOuterBottomCornerRadius,
            bottomTrailing: IslandSurfaceGeometry.moduleOuterBottomCornerRadius,
            topTrailing: IslandSurfaceGeometry.moduleInnerCornerRadius
        ),
        style: .continuous
    )

    init(model: AppModel) {
        _store = ObservedObject(wrappedValue: model.clipboardHistory)
        copyItem = { model.copyClipboardHistoryItem($0) }
        sendToQuickNote = { model.sendClipboardHistoryItemToQuickNote($0) }
        sendToAIAgent = { model.sendClipboardHistoryItemToAIAgent($0) }
    }

    private var visibleItems: [ClipboardHistoryItem] {
        switch filter {
        case .all: visiblePinnedItems + visibleHistoryItems
        case .pinned: visiblePinnedItems
        case .history: visibleHistoryItems
        }
    }

    private var visiblePinnedItems: [ClipboardHistoryItem] {
        store.pinnedItems
    }

    private var visibleHistoryItems: [ClipboardHistoryItem] {
        store.historyItems
    }

    private var queryID: String {
        filter.rawValue + "\u{0}" + categoryFilter.rawValue + "\u{0}" + searchText
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("剪贴板", systemImage: "clipboard")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(store.totalItemCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                if filter == .pinned {
                    IconButton(
                        symbol: "plus",
                        help: "添加常用信息",
                        isActive: additionPresentation != nil,
                        size: .compact
                    ) {
                        additionPresentation = .picker
                    }
                }
                IconButton(
                    symbol: "trash",
                    help: "清空历史（保留常用）",
                    size: .compact
                ) {
                    store.removeAllHistory()
                }
            }
            .frame(height: 30)
            .padding(.horizontal, 10)

            Hairline()

            ClipboardFilterSegmentedControl(selection: $filter)
                .padding(.horizontal, 10)
                .padding(.top, 8)

            categoryFilterBar
                .padding(.horizontal, 10)
                .padding(.top, 6)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("搜索", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .padding(.top, 6)

            Hairline()

            if store.isLoading && visibleItems.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleItems.isEmpty {
                EmptyState(
                    symbol: filter == .pinned ? "star" : "clipboard",
                    title: emptyStateTitle,
                    detail: emptyStateDetail
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if filter == .all {
                            if !visiblePinnedItems.isEmpty {
                                sectionTitle("常用")
                                ForEach(visiblePinnedItems) { item in
                                    itemRow(item)
                                }
                            }
                            if !visibleHistoryItems.isEmpty {
                                sectionTitle("非常用")
                                ForEach(visibleHistoryItems) { item in
                                    itemRow(item)
                                }
                            }
                        } else {
                            ForEach(visibleItems) { item in
                                itemRow(item)
                            }
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.visible)
                .thinScrollChrome()
            }

            if store.pageCount > 1 {
                Hairline()
                HStack(spacing: 8) {
                    Button {
                        store.loadPreviousPage()
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canLoadPreviousPage)
                    .help("上一页")

                    Text("\(store.currentPage + 1)/\(store.pageCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 42)

                    Button {
                        store.loadNextPage()
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canLoadNextPage)
                    .help("下一页")
                }
                .frame(height: 30)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.fillCard)
        .clipShape(Self.surfaceShape)
        .overlay {
            Self.surfaceShape
                .strokeBorder(Color.strokeCard, lineWidth: 1)
        }
        .overlay {
            if additionPresentation != nil {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: dismissAddition)

                    additionOverlay
                        .padding(.top, 38)
                        .padding(.trailing, 10)
                }
                .zIndex(1)
            }
        }
        .task(id: queryID) {
            if !searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !Task.isCancelled else { return }
            store.updateQuery(scope: filter.scope, searchText: searchText, category: categoryFilter)
        }
    }

    @ViewBuilder
    private var additionOverlay: some View {
        switch additionPresentation {
        case .picker:
            additionPicker
        case .textEditor:
            textAdditionEditor
        case nil:
            EmptyView()
        }
    }

    private var additionPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("添加常用项")
                .font(.islandMicro(weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 3)

            additionPickerAction("text.alignleft", title: "文字") {
                draftText = ""
                additionPresentation = .textEditor
            }
            additionPickerAction("photo", title: "图片") {
                dismissAddition()
                chooseImage()
            }
            additionPickerAction("doc", title: "文件") {
                dismissAddition()
                chooseFile()
            }
        }
        .frame(width: 148, alignment: .leading)
        .padding(5)
        .islandGlassSurface(.card, cornerRadius: 8)
    }

    private var textAdditionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("添加常用文字")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Button(action: dismissAddition) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("取消")
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $draftText)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .focused($isDraftTextFocused)
                    .padding(7)

                if draftText.isEmpty {
                    Text("输入文字或 Emoji")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 420, height: 170)
            .islandGlassSurface(.input, cornerRadius: 8)

            HStack(spacing: 8) {
                Spacer()
                Button("取消", action: dismissAddition)
                    .controlSize(.small)
                Button("添加", action: addDraftText)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(width: 440, alignment: .leading)
        .padding(10)
        .islandGlassSurface(.card, cornerRadius: 10)
        .onAppear { isDraftTextFocused = true }
        .onDisappear { isDraftTextFocused = false }
    }

    private func additionPickerAction(
        _ symbol: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func dismissAddition() {
        isDraftTextFocused = false
        additionPresentation = nil
    }

    private func addDraftText() {
        guard !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        addPinned(.text(draftText))
        dismissAddition()
    }

    private var emptyStateTitle: String {
        switch filter {
        case .all: "还没有剪贴板历史"
        case .pinned: "还没有常用项"
        case .history: "这里空空如也"
        }
    }

    private var emptyStateDetail: String? {
        switch filter {
        case .all: "复制内容后会自动记录"
        case .pinned: "点击右上角加号，添加文字、图片或文件"
        case .history: nil
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.islandMicro(weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
            .padding(.top, 2)
    }

    private func itemRow(_ item: ClipboardHistoryItem) -> some View {
        ClipboardHistoryItemRow(
            item: item,
            onCopy: copyItem,
            onSendToQuickNote: sendToQuickNote,
            onSendToAIAgent: sendToAIAgent,
            onSetPinned: { store.setPinned(id: item.id, isPinned: $0) },
            onRemove: { store.remove(id: item.id) }
        )
        .equatable()
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else { return }
        addPinned(.image(pngData))
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.item]
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        guard panel.runModal() == .OK, let url = panel.url,
              let content = try? ClipboardHistoryContent.file(at: url)
        else { return }
        addPinned(content)
    }

    private func addPinned(_ content: ClipboardHistoryContent) {
        _ = store.recordPinned(content)
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(FileShelfCategory.clipboardCases) { category in
                    let count = categoryCount(for: category)
                    let isSelected = categoryFilter == category
                    let hasItems = category == .all || count > 0

                    Button {
                        categoryFilter = category
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 10, weight: .medium))
                            Text(category.rawValue)
                                .font(.system(size: 10, weight: .medium))
                            if category != .all {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(Color.fillCard)
                                    .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(hasItems ? .primary : .tertiary)
                    .disabled(!hasItems)
                }
            }
        }
        .frame(height: 28)
    }

    private func categoryCount(for category: FileShelfCategory) -> Int {
        guard category != .all else { return 0 }
        return store.categoryCounts[category, default: 0]
    }
}

/// Top All / Favorites / Non-favorites segmented control.
/// Selected segment: filled icon + white outline; unselected: outline icon + secondary color.
/// The two states are visually distinct to avoid "Favorites" and "Non-favorites" looking the same.
private struct ClipboardFilterSegmentedControl: View {
    @Binding var selection: ClipboardFilter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ClipboardFilter.allCases) { filter in
                let isActive = selection == filter
                Button {
                    guard selection != filter else { return }
                    if reduceMotion {
                        selection = filter
                    } else {
                        withAnimation(ZislaMotion.selection) {
                            selection = filter
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isActive ? filter.activeIcon : filter.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(filter.title)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .background {
                        if isActive {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.fillCard)
                                .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                                .matchedGeometryEffect(
                                    id: "clipboard-filter-selection",
                                    in: selectionNamespace
                                )
                        }
                    }
                }
                .buttonStyle(PressableStyle(hoverScale: 1.025, pressedScale: 0.95))
                .help("只看\(filter.title)")
            }
        }
        .padding(2)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(reduceMotion ? nil : ZislaMotion.selection, value: selection)
    }
}

private struct ClipboardHistoryItemRow: View, Equatable {
    let item: ClipboardHistoryItem
    let onCopy: (ClipboardHistoryItem) -> Void
    let onSendToQuickNote: (ClipboardHistoryItem) -> Void
    let onSendToAIAgent: (ClipboardHistoryItem) -> Void
    let onSetPinned: (Bool) -> Void
    let onRemove: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item
    }

    var body: some View {
        HStack(spacing: 9) {
            Button {
                onCopy(item)
            } label: {
                HStack(spacing: 9) {
                    preview
                        .frame(width: 42, height: 42)
                        .background(Color.fillControl)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.content.previewText)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(contentTypeName)
                            .font(.islandMicro())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .help("复制到剪贴板")

            Button {
                onSendToQuickNote(item)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "note.text")
                        .font(.system(size: 10))
                    Text("随记")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("发送到随记")

            Button {
                onSendToAIAgent(item)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("AI")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("发送到 AI Agent")

            // Favorites toggle: filled star = already in favorites; tap to add/remove from favorites.
            Button {
                onSetPinned(!item.isPinned)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: item.isPinned ? "star.fill" : "star")
                        .font(.system(size: 10))
                    Text("常用")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isPinned ? Color.accentColor : .secondary)
            .help(item.isPinned ? "移出常用" : "设为常用")

            Button {
                onRemove()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                    Text("删除")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("删除")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.fillControl)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onDrag { dragProvider }
        .contextMenu {
            Button("复制") { onCopy(item) }
            Button("发送到随记") { onSendToQuickNote(item) }
            Button("发送到 AI Agent") { onSendToAIAgent(item) }
            Button(item.isPinned ? "移出常用" : "设为常用") {
                onSetPinned(!item.isPinned)
            }
            Divider()
            Button("删除", role: .destructive) {
                onRemove()
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.content {
        case .text:
            Image(systemName: "text.alignleft")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        case .image(let data):
            if let image = ClipboardImagePreviewCache.shared.image(for: item.id, data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .file:
            Image(systemName: "doc")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var contentTypeName: String {
        switch item.content {
        case .text: "文本"
        case .image: "图片"
        case .file: "文件"
        }
    }

    private var dragProvider: NSItemProvider {
        switch item.content {
        case let .text(value):
            NSItemProvider(object: value as NSString)
        case let .file(reference):
            NSItemProvider(object: reference.url as NSURL)
        case .image:
            NSItemProvider()
        }
    }
}

@MainActor
private final class ClipboardImagePreviewCache {
    static let shared = ClipboardImagePreviewCache()

    private let images = NSCache<NSUUID, NSImage>()

    private init() {
        images.countLimit = 30
        images.totalCostLimit = 1_200_000
    }

    func image(for id: UUID, data: Data) -> NSImage? {
        let key = id as NSUUID
        if let cached = images.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 84,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        images.setObject(image, forKey: key, cost: thumbnail.width * thumbnail.height * 4)
        return image
    }
}
