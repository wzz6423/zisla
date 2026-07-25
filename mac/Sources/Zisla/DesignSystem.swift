import ZislaCore
import SwiftUI

/// Zisla 的设计令牌与基础组件库。
///
/// 目标：为灵动岛与设置窗口提供**单一、可复用**的视觉来源，消除散落的
/// 魔法颜色/字号/描边值，保证各模块观感一致，并为无障碍（对比度、字号下限）
/// 提供统一的可调点。
///
/// - 颜色令牌基于 `Color.primary`，在深色灵动岛（primary=white）与
///   主题自适应的设置窗口（primary 随系统）中都能正确解析。
/// - 字号令牌设定 9pt 为可阅读微文案的下限（此前存在 7–8pt，低于舒适阈值）。

// MARK: - 品牌色（AI 供应方，单一来源）

/// 各 AI 供应方的品牌色。**唯一**定义处；进度条、图标着色等全部引用这里，
/// 避免同一供应方在不同模块显示成不同颜色。
enum ProviderBrand {
    static func color(for provider: AIProvider) -> Color {
        switch provider {
        case .claude: Color(red: 0.95, green: 0.48, blue: 0.34)
        case .codex: Color(red: 0.36, green: 0.90, blue: 0.66)
        case .gemini: Color(red: 0.50, green: 0.68, blue: 1.00)
        case .grok: .primary
        case .gpt: Color(red: 0.42, green: 0.82, blue: 0.72)
        case .qwen: Color(red: 0.48, green: 0.62, blue: 1.00)
        case .coder: Color(red: 0.98, green: 0.78, blue: 0.30)
        case .trae: Color(red: 0.40, green: 0.56, blue: 1.00)
        case .opencode: Color(red: 0.55, green: 0.85, blue: 0.55)
        case .harness: Color(red: 0.90, green: 0.45, blue: 0.50)
        case .doubao: Color(red: 0.35, green: 0.72, blue: 1.00)
        }
    }
}

// MARK: - 颜色令牌

extension Color {
    /// 卡片 / 模块容器填充（中等强度）。
    static let fillCard = Color.primary.opacity(0.12)
    /// 控件 / 图标按钮的低调填充。
    static let fillControl = Color.primary.opacity(0.10)
    /// 卡片描边。
    static let strokeCard = Color.primary.opacity(0.14)
    /// 细分隔线。
    static let dividerSubtle = Color.primary.opacity(0.08)
    /// 激活态的强调色底。
    static let accentTint = Color.accentColor.opacity(0.16)

    // 语义色：错误=红，警告=橙，成功=绿，信息=青。全局统一，避免混用。
    static let zislaError = Color.red
    static let zislaWarning = Color.orange
    static let zislaSuccess = Color.green
    static let zislaInfo = Color.cyan
}

// MARK: - 字号令牌

extension Font {
    /// 灵动岛上**可阅读**微文案的下限字号（9pt）。
    /// 此前图表轴标、进度时间、图例等使用 7–8pt，在 240pt 宽面板上低于舒适阈值。
    static func islandMicro(
        weight: Font.Weight = .medium,
        design: Font.Design = .default
    ) -> Font {
        .system(size: 9, weight: weight, design: design)
    }
}

// MARK: - 灵动岛几何

enum IslandSurfaceGeometry {
    static let expandedBottomCornerRadius: CGFloat = 34
    static let moduleInset: CGFloat = 12
    static let moduleOuterBottomCornerRadius = expandedBottomCornerRadius - moduleInset
    static let moduleInnerCornerRadius: CGFloat = 8
}

// MARK: - 细分隔线

/// 统一的细分隔线，替代各处的 `Divider().overlay(Color.primary.opacity(0.06))`。
struct Hairline: View {
    var body: some View {
        Divider().overlay(Color.dividerSubtle)
    }
}

// MARK: - 图标按钮（统一实现）

/// 圆形图标按钮的统一视觉标签；既可直接作为 `IconButton` 的内容，
/// 也可作为 `Menu` 的标签复用，保证三种入口（工具条 / 媒体控制 / 模块切换）
/// 观感与激活态完全一致。
struct IconButtonLabel: View {
    enum Size {
        case compact
        case regular

        var dimension: CGFloat { self == .compact ? 24 : 28 }
        var symbolSize: CGFloat { self == .compact ? 11 : 13 }
    }

    var symbol: String
    var isActive = false
    var activeColor: Color? = nil
    var size: Size = .regular
    /// 非激活时是否用次要色（用于"选中才高亮"的标签式切换，如模块选择器）。
    var dimmedWhenInactive = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size.symbolSize, weight: .semibold))
            .foregroundStyle(
                isActive ? (activeColor ?? Color.accentColor) : (dimmedWhenInactive ? .secondary : .primary)
            )
            .frame(width: size.dimension, height: size.dimension)
            .background(isActive ? (activeColor ?? Color.accentColor).opacity(0.16) : Color.fillControl)
            .clipShape(Circle())
            .contentShape(Circle())
            .clipped()
    }
}

/// 统一的圆形图标按钮。
struct IconButton: View {
    var symbol: String
    var help: String
    var isActive = false
    var activeColor: Color? = nil
    var size: IconButtonLabel.Size = .regular
    var dimmedWhenInactive = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            IconButtonLabel(
                symbol: symbol,
                isActive: isActive,
                activeColor: activeColor,
                size: size,
                dimmedWhenInactive: dimmedWhenInactive
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - 空状态（统一实现）

/// 紧凑空状态，适配灵动岛的深色玻璃与受限高度。
/// 替代各模块自绘的空态，保证图标尺度、字号、配色一致。
struct EmptyState: View {
    var symbol: String
    var title: String
    var detail: String? = nil
    /// 整体着色；默认次要色，拖拽悬停等场景可传入强调色。
    var tint: Color = .secondary

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.system(size: 10, weight: .medium))
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.islandMicro())
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
