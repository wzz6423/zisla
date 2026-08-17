import AppKit
import ZislaKit
import SwiftUI

struct ShelfModuleView: View {
    @ObservedObject var model: AppModel
    @StateObject private var dropState = FileDropState()
    @State private var searchText = ""
    private static let itemColumns = [
        GridItem(.adaptive(minimum: 66, maximum: 66), spacing: 8),
    ]

    private static let shelfShape = IslandSurfaceGeometry.moduleContentShape(
        bottomTrailingRadius: IslandSurfaceGeometry.moduleOuterBottomCornerRadius
    )

    private static let shareShoulderShape = IslandSurfaceGeometry.moduleContentShape(
        bottomLeadingRadius: IslandSurfaceGeometry.moduleOuterBottomCornerRadius
    )

    var body: some View {
        HStack(spacing: 6) {
            shareShoulder
                .frame(width: 84)
                .onDrop(
                    of: TransferDropDelegate.supportedTypes,
                    delegate: TransferDropDelegate(isTargeted: $dropState.shareTargeted) {
                        model.share($0)
                    }
                )

            VStack(spacing: 0) {
                HStack {
                    Label("中转站", systemImage: "tray.full")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(filteredItems.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button {
                        model.pasteFilesToShelf()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 11, weight: .medium))
                            Text("粘贴")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("粘贴文件到中转站")
                    .keyboardShortcut("v", modifiers: .command)

                    if !model.shelf.items.isEmpty {
                        Button {
                            model.receiveQuickNoteTransferItems(model.shelf.items.map { .file($0.url) })
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 11, weight: .medium))
                                Text("随记")
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .help("全部发送到随记")

                        Button {
                            model.copyShelfFiles(model.shelf.items.map(\.url))
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11, weight: .medium))
                                Text("复制")
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .help("复制全部文件")

                        ShareLink(items: model.shelf.items.map(\.url)) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 11, weight: .medium))
                                Text("分享")
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .help("系统分享")

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                model.shelf.items.map(\.url)
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11, weight: .medium))
                                Text("显示")
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .help("在 Finder 中显示")
                    }
                }
                .frame(height: 30)
                .padding(.horizontal, 10)

                categoryFilterBar

                searchBar

                Hairline()

                Group {
                    if model.shelf.items.isEmpty {
                        EmptyState(
                            symbol: "tray.and.arrow.down",
                            title: "中转站为空",
                            tint: dropState.shelfTargeted
                                ? Color(red: 0.48, green: 0.9, blue: 0.62)
                                : .secondary
                        )
                    } else if filteredItems.isEmpty {
                        EmptyState(
                            symbol: "line.3.horizontal.decrease.circle",
                            title: "无符合条件的文件",
                            tint: .secondary
                        )
                    } else {
                        ScrollView(.vertical) {
                            LazyVGrid(columns: Self.itemColumns, alignment: .leading, spacing: 8) {
                                ForEach(filteredItems) { item in
                                    ShelfItemView(
                                        item: item,
                                        onCopy: { model.copyShelfFiles([item.url]) },
                                        onSendToQuickNote: {
                                            model.receiveQuickNoteTransferItems([.file(item.url)])
                                        },
                                        onRemove: { model.shelf.remove(id: item.id) }
                                    )
                                }
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 8)
                            .padding(.vertical, 7)
                        }
                        .scrollIndicators(.visible)
                        .thinScrollChrome()
                    }
                }
                .onDrop(
                    of: TransferDropDelegate.supportedTypes,
                    delegate: TransferDropDelegate(isTargeted: $dropState.shelfTargeted) {
                        model.receiveTransferItems($0)
                    }
                )
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
        .frame(height: 320)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索文件名", text: $searchText)
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
                    .disabled(count == 0 && category != .all)
                    .opacity(count == 0 && category != .all ? 0.4 : 1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private var filteredItems: [FileShelfItem] {
        var items = model.shelf.items

        // Apply the category filter.
        if model.selectedShelfCategory != .all {
            items = items.filter { $0.category == model.selectedShelfCategory }
        }

        // Apply the search filter.
        if !searchText.isEmpty {
            items = items.filter { item in
                item.url.lastPathComponent.localizedCaseInsensitiveContains(searchText)
            }
        }

        return items
    }

    private func categoryCount(for category: FileShelfCategory) -> Int {
        if category == .all {
            return model.shelf.items.count
        }
        return model.shelf.items.filter { $0.category == category }.count
    }

    private var shareShoulder: some View {
        return VStack(spacing: 6) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text("共享")
                .font(.system(size: 11, weight: .semibold))
            Button {
                model.shareFromPasteboard()
            } label: {
                Label("粘贴", systemImage: "doc.on.clipboard")
                    .font(.system(size: 10, weight: .medium))
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .background(Color.fillCard)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .help("从剪贴板共享（文件或文字）")
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
        .help("拖入或粘贴后系统共享")
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

private struct ShelfItemView: View {
    var item: FileShelfItem
    var onCopy: () -> Void
    var onSendToQuickNote: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                FileShelfDragSourceView(
                    url: item.url,
                    image: FileIconCache.shared.icon(for: item.url.path),
                    onOpen: { NSWorkspace.shared.open(item.url) },
                    onReveal: {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    },
                    onRemove: onRemove
                )
                    .frame(width: 42, height: 42)
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.72))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .help("移除")
            }
            Text(item.url.lastPathComponent)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 64, height: 24, alignment: .top)
        }
        .frame(width: 66, height: 84)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(item.url)
        }
        .contextMenu {
            Button("打开") { NSWorkspace.shared.open(item.url) }
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("复制", action: onCopy)
            Button("发送到随记", action: onSendToQuickNote)
            Divider()
            Button("移除", role: .destructive, action: onRemove)
        }
    }
}

@MainActor
private final class FileDropState: ObservableObject {
    @Published var shareTargeted = false
    @Published var shelfTargeted = false
}

@MainActor
private final class FileIconCache {
    static let shared = FileIconCache()
    private let cache = NSCache<NSString, NSImage>()

    func icon(for path: String) -> NSImage {
        if let image = cache.object(forKey: path as NSString) { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
