import AppKit
import ImageIO
import ZislaCore
import ZislaKit
import SwiftUI

struct ShelfModuleView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var noteEditor: ContextNoteShelfEditor
    @StateObject private var dropState = FileDropState()
    @State private var searchText = ""

    @State private var screenshotPreview: ShelfScreenshotPreview?

    private static let shelfShape = IslandSurfaceGeometry.moduleContentShape(
        bottomTrailingRadius: IslandSurfaceGeometry.moduleOuterBottomCornerRadius
    )

    private static let shareShoulderShape = IslandSurfaceGeometry.moduleContentShape(
        bottomLeadingRadius: IslandSurfaceGeometry.moduleOuterBottomCornerRadius
    )

    init(model: AppModel) {
        self.model = model
        noteEditor = model.contextNoteEditor
    }

    var body: some View {
        HStack(spacing: IslandModuleLayout.shelfColumnSpacing) {
            shareShoulder
                .frame(width: IslandModuleLayout.shelfShareWidth)
                .onDrop(
                    of: TransferDropDelegate.supportedTypes,
                    delegate: TransferDropDelegate(isTargeted: $dropState.shareTargeted) {
                        model.share($0)
                    }
                )

            VStack(spacing: 0) {
                HStack {
                    Label(AppLocalization.text("中转站"), systemImage: "tray.full")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(filteredItems.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button {
                        if !noteEditor.resumeNew() { model.onBeginContextNote?() }
                    } label: {
                        Label(AppLocalization.text("记录便签"), systemImage: "square.and.pencil")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.pasteFilesToShelf()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 11, weight: .medium))
                            Text(AppLocalization.text("粘贴"))
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(AppLocalization.text("粘贴内容到中转站"))
                    .keyboardShortcut(noteEditor.isPresented ? nil : KeyboardShortcut("v", modifiers: .command))

                    if !model.shelf.items.isEmpty {
                        Button {
                            model.receiveQuickNoteTransferItems(model.shelfTransferItems(model.shelf.items))
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 11, weight: .medium))
                                Text(AppLocalization.text("随记"))
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .help(AppLocalization.text("全部发送到随记"))

                        Button {
                            model.copyShelfItems(model.shelf.items)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11, weight: .medium))
                                Text(AppLocalization.text("复制"))
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .help(AppLocalization.text("复制全部内容"))

                        Button {
                            model.share(model.shelfTransferItems(model.shelf.items))
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 11, weight: .medium))
                                Text(AppLocalization.text("分享"))
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .help(AppLocalization.text("系统分享"))

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                model.shelf.items.filter { $0.text == nil }.map(\.url)
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11, weight: .medium))
                                Text(AppLocalization.text("显示"))
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .help(AppLocalization.text("在 Finder 中显示"))
                        .disabled(!model.shelf.items.contains { $0.text == nil })
                    }
                }
                .frame(height: 30)
                .padding(.horizontal, 10)

                categoryFilterBar

                searchBar

                Hairline()

                Group {
                    if noteEditor.isPresented, let draft = noteEditor.draft {
                        ContextNoteDetailView(draft: draft, onCopy: { model.copyContextNoteText(draft.text) },
                                              onNavigate: { model.navigateToContextNote(draft.location) },
                                              onSave: { model.saveShelfContextNote() },
                                              onClose: { noteEditor.close() })
                            .id(ObjectIdentifier(draft))
                    } else if model.shelf.items.isEmpty {
                        EmptyState(
                            symbol: "tray.and.arrow.down",
                            title: AppLocalization.text("中转站为空"),
                            tint: dropState.shelfTargeted
                                ? Color(red: 0.48, green: 0.9, blue: 0.62)
                                : .secondary
                        )
                    } else if filteredItems.isEmpty {
                        EmptyState(
                            symbol: "line.3.horizontal.decrease.circle",
                            title: AppLocalization.text("无符合条件的内容"),
                            tint: .secondary
                        )
                    } else {
                        ScrollView(.vertical) {
                            ShelfItemCollection(items: filteredItems, category: model.selectedShelfCategory) { item in
                                ShelfItemView(
                                    item: item,
                                    onOpen: {
                                        if item.noteLocation != nil { noteEditor.open(item) }
                                        else if item.screenshotMetadata != nil {
                                            do {
                                                screenshotPreview = ShelfScreenshotPreview(id: item.id,
                                                    data: try model.shelf.screenshotData(id: item.id))
                                            } catch { model.transientMessage = error.localizedDescription }
                                        }
                                        else { NSWorkspace.shared.open(item.linkURL ?? item.url) }
                                    },
                                    onCopy: { model.copyShelfItems([item]) },
                                    onSave: { model.saveShelfScreenshot(item) },
                                    prepareDragPayload: {
                                        guard item.screenshotMetadata != nil else { return item.payload }
                                        do { return .file(try model.shelf.screenshotFileURL(id: item.id)) }
                                        catch {
                                            model.transientMessage = error.localizedDescription
                                            return nil
                                        }
                                    },
                                    onSendToQuickNote: {
                                        model.receiveQuickNoteTransferItems([TransferDropItem(payload: item.payload)])
                                    },
                                    onRemove: {
                                        model.shelf.remove(id: item.id)
                                        if let error = model.shelf.errorDescription { model.transientMessage = error }
                                        if !model.shelf.items.contains(where: { $0.id == item.id }) { noteEditor.removed(item.id) }
                                    }
                                )
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 8)
                            .padding(.vertical, 7)
                        }
                        .scrollIndicators(.visible)
                        .thinScrollChrome()
                    }
                }
                .shelfDropTarget(isTargeted: $dropState.shelfTargeted) {
                    model.receiveShelfDropItems($0)
                }
            }
            .background {
                moduleBackground(shape: Self.shelfShape, targeted: dropState.shelfTargeted)
            }
            .clipShape(Self.shelfShape)
            .overlay {
                Self.shelfShape
                    .strokeBorder(
                        moduleStroke(targeted: dropState.shelfTargeted),
                        lineWidth: 1
                    )
            }
        }
        .frame(height: IslandModuleLayout.shelfContentHeight)
        .sheet(item: $screenshotPreview) { preview in
            VStack(spacing: 12) {
                if let image = NSImage(data: preview.data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    Button(AppLocalization.text("复制")) {
                        if let item = model.shelf.items.first(where: { $0.id == preview.id }) { model.copyShelfItems([item]) }
                    }
                    Button(AppLocalization.text("保存")) {
                        if let item = model.shelf.items.first(where: { $0.id == preview.id }) { model.saveShelfScreenshot(item) }
                    }
                    Spacer()
                    Button(AppLocalization.text("关闭")) { screenshotPreview = nil }
                }
            }
            .padding(16)
            .frame(width: 600, height: 480)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(AppLocalization.text("搜索中转内容"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(FileShelfCategory.fileShelfCases) { category in
                    let count = categoryCount(for: category)
                    let isSelected = model.selectedShelfCategory == category
                    Button {
                        model.selectedShelfCategory = category
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 10, weight: .medium))
                            Text(category.title)
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
                    .disabled(count == 0 && category != .all)
                    .opacity(count == 0 && category != .all ? 0.4 : 1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private var filteredItems: [FileShelfItem] {
        Self.filteredItems(in: model.shelf.items, category: model.selectedShelfCategory, searchText: searchText)
    }

    static func filteredItems(in source: [FileShelfItem], category: FileShelfCategory, searchText: String) -> [FileShelfItem] {
        var items = source

        // Apply the category filter.
        if category != .all {
            items = items.filter { $0.category == category }
        }

        // Apply the search filter.
        if !searchText.isEmpty {
            items = items.filter { item in
                item.searchText.localizedCaseInsensitiveContains(searchText)
            }
        }

        return items
    }

    private func categoryCount(for category: FileShelfCategory) -> Int {
        Self.categoryCount(for: category, in: model.shelf.items)
    }

    static func categoryCount(for category: FileShelfCategory, in items: [FileShelfItem]) -> Int {
        if category == .all {
            return items.count
        }
        return items.filter { $0.category == category }.count
    }

    private var shareShoulder: some View {
        return VStack(spacing: 6) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(AppLocalization.text("共享"))
                .font(.system(size: 11, weight: .semibold))
            Button {
                model.shareFromPasteboard()
            } label: {
                Label(AppLocalization.text("粘贴"), systemImage: "doc.on.clipboard")
                    .font(.system(size: 10, weight: .medium))
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .background(Color.fillCard)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .help(AppLocalization.text("从剪贴板共享（文件或文字）"))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background {
            moduleBackground(shape: Self.shareShoulderShape, targeted: dropState.shareTargeted)
        }
        .clipShape(Self.shareShoulderShape)
        .overlay {
            Self.shareShoulderShape
                .strokeBorder(
                    moduleStroke(targeted: dropState.shareTargeted),
                    lineWidth: 1
                )
        }
        .help(AppLocalization.text("拖入或粘贴后系统共享"))
    }

    /// Relay and shared blocks use plain card fills because Liquid Glass competes with their file icons;
    /// transparent themes also avoid the glass branch and retain only targeted drag-and-drop feedback.
    @ViewBuilder
    private func moduleBackground<Surface: Shape>(
        shape: Surface,
        targeted: Bool
    ) -> some View {
        ZStack {
            shape.fill(Color.fillCard)

            if targeted {
                shape.fill(Color.accentColor.opacity(0.12))
            }
        }
        .allowsHitTesting(false)
    }

    private func moduleStroke(targeted: Bool) -> Color {
        targeted ? .accentColor : .strokeCard
    }
}

private struct ShelfScreenshotPreview: Identifiable {
    let id: UUID
    let data: Data
}

struct ShelfNoteApplicationGroup: Identifiable {
    enum ID: Hashable {
        case application(String)
        case desktop
    }

    let id: ID
    var items: [FileShelfItem]

    var title: String {
        switch id {
        case .application(let name): name
        case .desktop: AppLocalization.text("桌面")
        }
    }

    static func groups(in items: [FileShelfItem]) -> [Self] {
        var groups: [Self] = []
        for item in items {
            guard let location = item.noteLocation else { continue }
            let id: ID
            switch location {
            case .webPage(_, _, let name), .window(_, let name, _): id = .application(name)
            case .desktop: id = .desktop
            }
            if let index = groups.firstIndex(where: { $0.id == id }) {
                groups[index].items.append(item)
            } else {
                groups.append(Self(id: id, items: [item]))
            }
        }
        return groups
    }
}

struct ShelfItemCollection<Content: View>: View {
    let items: [FileShelfItem]
    let category: FileShelfCategory
    @ViewBuilder var content: (FileShelfItem) -> Content

    var body: some View {
        if category == .note {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ShelfNoteApplicationGroup.groups(in: items)) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        grid(group.items)
                    }
                }
            }
        } else {
            grid(items)
        }
    }

    private func grid(_ items: [FileShelfItem]) -> some View {
        ShelfGridLayout() {
            ForEach(items) { item in
                content(item)
                    .layoutValue(key: ShelfColumnSpan.self, value: item.noteLocation == nil && item.screenshotMetadata == nil ? 1 : 2)
            }
        }
    }
}

private struct ShelfColumnSpan: LayoutValueKey {
    static let defaultValue = 1
}

struct ShelfGridLayout: Layout {
    var layoutDirection: LayoutDirection = .leftToRight

    static func frames(columnSpans: [Int], width: CGFloat, layoutDirection: LayoutDirection = .leftToRight) -> [CGRect] {
        let columns = max(columnSpans.max() ?? 1, Int((width + 8) / 74))
        var column = 0
        var row = 0
        return columnSpans.map { span in
            if column + span > columns {
                column = 0
                row += 1
            }
            let itemWidth = CGFloat(span * 74 - 8)
            let leading = CGFloat(column * 74)
            let frame = CGRect(
                x: layoutDirection == .rightToLeft ? width - leading - itemWidth : leading,
                y: CGFloat(row * 92), width: itemWidth, height: 84
            )
            column += span
            return frame
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let spans = subviews.map { $0[ShelfColumnSpan.self] }
        let width = max(proposal.width ?? 140, CGFloat((spans.max() ?? 1) * 74 - 8))
        let frames = Self.frames(columnSpans: spans, width: width)
        return CGSize(width: width, height: frames.last?.maxY ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = Self.frames(columnSpans: subviews.map { $0[ShelfColumnSpan.self] }, width: bounds.width,
                                 layoutDirection: layoutDirection)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}

struct ShelfItemView: View {
    var item: FileShelfItem
    var onOpen: () -> Void
    var onCopy: () -> Void
    var onSave: () -> Void = {}
    var prepareDragPayload: (() -> TransferPasteboardPayload?)? = nil
    var onSendToQuickNote: () -> Void
    var onRemove: () -> Void

    var body: some View {
        Group {
            if let location = item.noteLocation {
                contextNoteCard(location: location)
            } else if item.screenshotMetadata != nil {
                screenshotCard
            } else {
                fileCard
            }
        }
        .contextMenu {
            Button(AppLocalization.text(item.screenshotMetadata == nil ? "打开" : "预览"), action: onOpen)
            if item.text == nil && item.screenshotMetadata == nil {
                Button(AppLocalization.text("在 Finder 中显示")) {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
            }
            Button(AppLocalization.text("复制"), action: onCopy)
            if item.screenshotMetadata != nil {
                Button(AppLocalization.text("保存"), action: onSave)
            } else {
                Button(AppLocalization.text("发送到随记"), action: onSendToQuickNote)
            }
            Divider()
            Button(AppLocalization.text("移除"), role: .destructive, action: onRemove)
        }
    }

    private var screenshotCard: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                FileShelfDragSourceView(
                    payload: item.payload,
                    image: FileIconCache.shared.icon(for: item.url.path),
                    onOpen: onOpen,
                    onReveal: onOpen,
                    onCopy: onCopy,
                    onRemove: onRemove,
                    onSave: onSave,
                    preparePayload: prepareDragPayload
                )
                .frame(width: 124, height: 48)
                Text(item.screenshotMetadata?.source.applicationName ?? AppLocalization.text("截图"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(width: 140, height: 84, alignment: .topLeading)
            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.strokeCard, lineWidth: 1))
            removeButton.padding(2)
        }
    }

    private func contextNoteCard(location: ContextNoteLocation) -> some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(AppLocalization.text("位置便签"), systemImage: "note.text")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 20)
                    Text(item.text ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    Text(ContextNoteDetailView.locationDescription(location))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(8)
                .frame(width: 140, height: 84, alignment: .topLeading)
                .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.strokeCard, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(AppLocalization.text("查看便签"))
            .accessibilityLabel(item.displayName)
            removeButton.padding(2)
        }
    }

    private var fileCard: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                FileShelfDragSourceView(
                    payload: item.payload,
                    image: FileIconCache.shared.icon(for: item.url.path),
                    onOpen: onOpen,
                    onReveal: {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    },
                    onCopy: onCopy,
                    onRemove: onRemove
                )
                    .frame(width: 42, height: 42)
                    .frame(width: 66, height: 50)
                removeButton
            }
            Text(item.displayName)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 64, height: 24, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: onOpen)
        }
        .frame(width: 66, height: 84)
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.72))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(AppLocalization.text("移除"))
    }
}

@MainActor
private final class FileDropState: ObservableObject {
    @Published var shareTargeted = false
    @Published var shelfTargeted = false
}

@MainActor
final class FileIconCache {
    static let shared = FileIconCache()
    private final class CachedIcon: NSObject {
        let image: NSImage
        let fileSize: Int?
        let modifiedAt: Date?

        init(image: NSImage, values: URLResourceValues?) {
            self.image = image
            fileSize = values?.fileSize
            modifiedAt = values?.contentModificationDate
        }
    }

    private let cache = NSCache<NSString, CachedIcon>()

    func icon(for path: String) -> NSImage {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        if let cached = cache.object(forKey: path as NSString),
           cached.fileSize == values?.fileSize, cached.modifiedAt == values?.contentModificationDate {
            return cached.image
        }
        let image = Self.thumbnail(for: url, values: values) ?? NSWorkspace.shared.icon(forFile: path)
        cache.setObject(CachedIcon(image: image, values: values), forKey: path as NSString)
        return image
    }

    private static func thumbnail(for url: URL, values: URLResourceValues?) -> NSImage? {
        guard values?.isRegularFile == true,
              let fileSize = values?.fileSize, fileSize <= 32 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_000_000 / height else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 84,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
}
