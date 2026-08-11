import AppKit
import ZislaKit
import SwiftUI

struct ShelfModuleView: View {
    @ObservedObject var model: AppModel
    @StateObject private var dropState = FileDropState()
    private static let itemColumns = [
        GridItem(.adaptive(minimum: 66, maximum: 66), spacing: 8),
    ]

    private static let shelfShape = UnevenRoundedRectangle(
        cornerRadii: .init(
            topLeading: IslandSurfaceGeometry.moduleInnerCornerRadius,
            bottomLeading: IslandSurfaceGeometry.moduleInnerCornerRadius,
            bottomTrailing: IslandSurfaceGeometry.moduleOuterBottomCornerRadius,
            topTrailing: IslandSurfaceGeometry.moduleInnerCornerRadius
        ),
        style: .continuous
    )

    private static let shareShoulderShape = UnevenRoundedRectangle(
        cornerRadii: .init(
            topLeading: IslandSurfaceGeometry.moduleInnerCornerRadius,
            bottomLeading: IslandSurfaceGeometry.moduleOuterBottomCornerRadius,
            bottomTrailing: IslandSurfaceGeometry.moduleInnerCornerRadius,
            topTrailing: IslandSurfaceGeometry.moduleInnerCornerRadius
        ),
        style: .continuous
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
                    Text("\(model.shelf.items.count)/\(model.shelf.capacity)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button {
                        model.pasteFilesToShelf()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("粘贴文件到中转站")
                    .keyboardShortcut("v", modifiers: .command)

                    if !model.shelf.items.isEmpty {
                        Button {
                            model.receiveQuickNoteTransferItems(model.shelf.items.map { .file($0.url) })
                        } label: {
                            Image(systemName: "note.text")
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("全部发送到随记")

                        Button {
                            model.sendTransferItemsToAIAgent(model.shelf.items.map { .file($0.url) })
                        } label: {
                            Image(systemName: "sparkles")
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("全部发送到 AI Agent")

                        Button {
                            model.copyShelfFiles(model.shelf.items.map(\.url))
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("复制全部文件")

                        ShareLink(items: model.shelf.items.map(\.url)) {
                            Image(systemName: "square.and.arrow.up")
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("系统分享")

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                model.shelf.items.map(\.url)
                            )
                        } label: {
                            Image(systemName: "folder")
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("在 Finder 中显示")
                    }
                }
                .frame(height: 30)
                .padding(.horizontal, 10)

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
                    } else {
                        ScrollView(.vertical) {
                            LazyVGrid(columns: Self.itemColumns, spacing: 8) {
                                ForEach(model.shelf.items) { item in
                                    ShelfItemView(
                                        item: item,
                                        onCopy: { model.copyShelfFiles([item.url]) },
                                        onSendToQuickNote: {
                                            model.receiveQuickNoteTransferItems([.file(item.url)])
                                        },
                                        onSendToAIAgent: {
                                            model.sendTransferItemsToAIAgent([.file(item.url)])
                                        },
                                        onRemove: { model.shelf.remove(id: item.id) }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
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
        .frame(height: 228)
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

    /// 中转站/共享块统一用普通卡片填充：Liquid Glass 在这两块上会和内部文件图标抢层次，
    /// 透明主题下也不再走玻璃分支，只保留拖放命中的 targeted 反馈。
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
    var onSendToAIAgent: () -> Void
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
            Button("发送到 AI Agent", action: onSendToAIAgent)
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
