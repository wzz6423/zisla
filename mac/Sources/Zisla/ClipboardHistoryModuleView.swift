import AppKit
import ImageIO
import ZislaKit
import SwiftUI

/// 剪贴板列表的筛选维度。
/// - `all`：全部（常用 + 历史），默认视图，等价于改动前同时展示两个分区。
/// - `pinned`：常用（被置顶/收藏的项）。
/// - `history`：非常用（普通历史项）。
private enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all
    case pinned
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .pinned: "常用"
        case .history: "非常用"
        }
    }

    /// 未选中时的轮廓图标。
    var icon: String {
        switch self {
        case .all: "tray.full"
        case .pinned: "star"
        case .history: "clock"
        }
    }

    /// 选中（激活）时填充的图标，与未选中形成明显差异。
    var activeIcon: String {
        switch self {
        case .all: "tray.full.fill"
        case .pinned: "star.fill"
        case .history: "clock.fill"
        }
    }
}

struct ClipboardHistoryModuleView: View {
    @ObservedObject private var store: ClipboardHistoryStore
    @State private var filter: ClipboardFilter = .all
    private let copyItem: (ClipboardHistoryItem) -> Void
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
    }

    /// 当前筛选下应展示的项（用于计数与空状态判断）。
    private var visibleItems: [ClipboardHistoryItem] {
        switch filter {
        case .all: return store.pinnedItems + store.historyItems
        case .pinned: return store.pinnedItems
        case .history: return store.historyItems
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("剪贴板", systemImage: "clipboard")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(visibleItems.count)/\(store.capacity)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                IconButton(
                    symbol: "trash",
                    help: "清空历史（保留常用）",
                    size: .compact
                ) {
                    store.removeAllHistory()
                }
                .disabled(store.historyItems.isEmpty)
            }
            .frame(height: 30)
            .padding(.horizontal, 10)

            Hairline()

            if store.items.isEmpty {
                EmptyState(
                    symbol: "clipboard",
                    title: "还没有剪贴板历史",
                    detail: "复制文本或图片后会自动记录"
                )
            } else {
                ClipboardFilterSegmentedControl(selection: $filter)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)

                if visibleItems.isEmpty {
                    EmptyState(
                        symbol: filter == .pinned ? "star" : "clock",
                        title: filter == .pinned ? "还没有常用项" : "这里空空如也",
                        detail: filter == .pinned ? "点击右侧星标，把常用内容加进来" : nil
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if filter == .all {
                                if !store.pinnedItems.isEmpty {
                                    sectionTitle("常用")
                                    ForEach(store.pinnedItems) { item in
                                        itemRow(item)
                                    }
                                }
                                if !store.historyItems.isEmpty {
                                    sectionTitle("非常用")
                                    ForEach(store.historyItems) { item in
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
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.fillCard)
        .clipShape(Self.surfaceShape)
        .overlay {
            Self.surfaceShape
                .strokeBorder(Color.strokeCard, lineWidth: 1)
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
            onSetPinned: { store.setPinned(id: item.id, isPinned: $0) },
            onRemove: { store.remove(id: item.id) }
        )
        .equatable()
    }
}

/// 顶部 全部 / 常用 / 非常用 分段控件。
/// 选中的分段：图标填充 + 强调底色；未选中的分段：轮廓图标 + 次要色。
/// 两者形成明确差异，避免"常用""非常用"看起来一样。
private struct ClipboardFilterSegmentedControl: View {
    @Binding var selection: ClipboardFilter

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ClipboardFilter.allCases) { filter in
                let isActive = selection == filter
                Button {
                    selection = filter
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isActive ? filter.activeIcon : filter.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(filter.title)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(isActive ? Color.accentTint : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("只看\(filter.title)")
            }
        }
        .padding(2)
        .background(Color.fillControl)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct ClipboardHistoryItemRow: View, Equatable {
    let item: ClipboardHistoryItem
    let onCopy: (ClipboardHistoryItem) -> Void
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
                        Text(item.content.isImage ? "图片" : "文本")
                            .font(.islandMicro())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .help("复制到剪贴板")

            // 常用切换：填充星标 = 已在常用中；点击可移入 / 移出常用。
            Button {
                onSetPinned(!item.isPinned)
            } label: {
                Image(systemName: item.isPinned ? "star.fill" : "star")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isPinned ? Color.accentColor : .secondary)
            .help(item.isPinned ? "移出常用" : "设为常用")

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("删除")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.fillControl)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contextMenu {
            Button("复制") { onCopy(item) }
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
