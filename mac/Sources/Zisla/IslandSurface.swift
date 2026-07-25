import AppKit
import ZislaKit
import SwiftUI

/// The island's visual surface: a solid-black top that smoothly fades through a
/// smoked transition into a transmissive frosted-glass bottom. The frosted glass
/// is rendered in dark appearance so it reads as a smoked, non-white translucent
/// material that refracts the desktop behind — an iOS 27 Siri–like feel.
struct IslandSurface<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder private let content: () -> Content
    private let isCollapsed: Bool
    private let collapsedSize: CGSize
    private let expandedSize: CGSize

    init(
        isCollapsed: Bool = false,
        collapsedSize: CGSize = CGSize(width: 240, height: 34),
        expandedSize: CGSize = CGSize(width: 748, height: 324),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isCollapsed = isCollapsed
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 岛面：顶部实黑（贴合菜单栏/刘海），经烟灰过渡带淡入下方透明磨砂玻璃；
            // 底部为烟灰色透射磨砂玻璃（折射桌面、不泛白），整体观感趋近 iOS 27 Siri 弹窗。
            unifiedSurface
                .allowsHitTesting(false)

            // IslandRootView keeps the content on the fixed dark appearance.
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 保持遮罩的布局尺寸不变，只在其画布内重绘轮廓。动画期间若改动遮罩 view
        // 的 frame，SwiftUI/AppKit 的布局插值会让轮廓短暂从左侧偏移。
        .mask {
            IslandRevealMask(
                collapsedSize: collapsedSize,
                expandedSize: expandedSize,
                isCollapsed: isCollapsed
            )
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: isCollapsed ? 0.18 : 0.22),
                value: isCollapsed
            )
        }
    }

    // MARK: - 岛面表面

    @ViewBuilder
    private var unifiedSurface: some View {
        ZStack(alignment: .top) {
            // 收起态底色始终铺底，展开时被 crown + glass 完全覆盖。
            Color.black
            if !isCollapsed && !reduceTransparency {
                // 底部透射磨砂玻璃（烟灰、折射桌面、不泛白）。
                glassBody
                // 顶部实黑 crown + 烟灰过渡。
                crown
            } else if !isCollapsed && reduceTransparency {
                // 无障碍：不透明黑→烟灰渐变。
                surfaceGradient
            }
        }
    }

    /// 顶部实黑 crown + 向下平滑过渡。
    /// 实黑段覆盖 NowPlayingHeader + 工具栏（白字）；其下用缓动渐变把黑淡入
    /// 烟灰磨砂玻璃。渐变 stops 均匀递减，避免中段出现密度跳变（"矮了一截"感）。
    private var crown: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(crownOpacity))
                .frame(height: crownHeight)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(crownOpacity), location: 0),
                    .init(color: .black.opacity(crownOpacity * 0.70), location: 0.3),
                    .init(color: .black.opacity(crownOpacity * 0.35), location: 0.65),
                    .init(color: .black.opacity(0.0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: crownBlend)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    /// crown 实黑高度：覆盖标题(NowPlayingHeader ~72pt + padding) + 工具栏(30pt)。
    private let crownHeight: CGFloat = 132
    /// 视觉保持黑色，同时让透明面板保留极轻的透光感。
    private let crownOpacity: CGFloat = 0.98
    /// crown 向下淡入磨砂玻璃的过渡高度。加长至 60pt 让黑→烟灰融合更平滑。
    private let crownBlend: CGFloat = 60

    /// 岛面底色：透射式烟灰磨砂玻璃。
    ///
    /// 放弃 `.glassEffect(.regular)` 作大面积背景——它在深色 colorScheme 下会坍缩成
    /// 实色黑（Liquid Glass 设计用途是悬浮控件，非整面背景）。改用 `NSVisualEffectView`
    /// 的 `.hudWindow` + `.behindWindow` + 深色外观：真正透射窗口后方桌面，深色下呈
    /// 烟灰半透磨砂、不泛白也不纯黑，行为稳定可控。顶部黑 crown 负责与黑顶衔接。
    private var glassBody: some View {
        VisualEffectBackground()
    }

    // MARK: - 表面渐变（无障碍：不透明黑 → 烟灰）

    /// 无障碍（Reduce Transparency）模式：不透明黑→烟灰竖向渐变，
    /// 去掉磨砂与透明，配合浅色文字保证对比度。
    private var surfaceGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.00),
                .init(color: .black, location: 0.40),
                .init(color: Color(white: 0.10), location: 0.62),
                .init(color: Color(white: 0.16), location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct IslandRevealMask: Shape {
    let collapsedSize: CGSize
    let expandedSize: CGSize
    private var revealProgress: CGFloat

    init(collapsedSize: CGSize, expandedSize: CGSize, isCollapsed: Bool) {
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
        revealProgress = isCollapsed ? 0 : 1
    }

    var animatableData: CGFloat {
        get { revealProgress }
        set { revealProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let transform = IslandSurfaceTransform(
            collapsedSize: collapsedSize,
            expandedSize: expandedSize,
            revealProgress: revealProgress
        )
        let visibleFrame = transform.visibleFrame(in: rect.size)
        let frame = CGRect(
            x: rect.midX - visibleFrame.width / 2,
            y: rect.minY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
        let progress = min(1, max(0, revealProgress))

        return IslandSilhouette(
            topCornerRadius: 5 * (1 - progress),
            bottomCornerRadius: 14 + (IslandSurfaceGeometry.expandedBottomCornerRadius - 14) * progress
        )
        .path(in: frame)
    }
}

/// 灵动岛轮廓：展开态直接贴合屏幕顶部，底部使用连续大圆角收束。
struct IslandSilhouette: InsettableShape {
    var topCornerRadius: CGFloat = 0
    var bottomCornerRadius: CGFloat = 34
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let topRadius = max(0, min(topCornerRadius - insetAmount, r.height / 2, r.width / 2))
        let bottomRadius = max(0, min(bottomCornerRadius - insetAmount, r.height / 2, r.width / 2))
        return UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: topRadius,
                bottomLeading: bottomRadius,
                bottomTrailing: bottomRadius,
                topTrailing: topRadius
            ),
            style: .continuous
        )
        .path(in: r)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    /// 0…1，降低后整体材质更通透；nil 表示使用系统默认（1.0）。
    var alphaValue: CGFloat? = nil

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        // 深色外观：让 HUD 材质渲染为烟灰半透磨砂玻璃，与 macOS 26 的
        // Liquid Glass 深色分支观感一致，底部不泛白。
        view.appearance = NSAppearance(named: .darkAqua)
        if let alphaValue {
            view.alphaValue = alphaValue
        }
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// `IconButton` 已迁移至 DesignSystem.swift（统一实现，含尺寸与激活态令牌）。
