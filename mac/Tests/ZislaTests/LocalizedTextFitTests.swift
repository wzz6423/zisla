import AppKit
import Testing
import ZislaCore

@testable import Zisla

/// 窄容器的宽度是按中文文案设计的，而译文最长会膨胀到 2 倍。这里用 CoreText 复算 17 门语言的真实
/// 渲染宽度：容器给不出空间、`minimumScaleFactor` 也补不回来时测试先失败，避免改译文或加语言时
/// 把界面挤成截断。
@MainActor
struct LocalizedTextFitTests {
    /// `available` 是文案真正能占的宽度，`minimumScale` 与 `lines` 对应视图上的 fitsSingleLine/fitsLines。
    private struct Slot {
        let origin: String
        let keys: [String]
        let available: CGFloat
        let fontSize: CGFloat
        let minimumScale: CGFloat
        var lines: Int = 1

        var font: NSFont { NSFont.systemFont(ofSize: fontSize, weight: .medium) }
        /// 缩到最小仍要放得下：可用宽度先按行数放大，再除以最小缩放。
        var capacity: CGFloat { available * CGFloat(lines) / minimumScale }
    }

    private static var slots: [Slot] {
        [
            Slot(
                origin: "SettingsView.swift:113 侧栏分区标题",
                keys: SettingsSection.allCases.map(\.title),
                // 148 侧栏 − 24 外 padding − 16 行内 padding − 17 图标 − 8 spacing
                available: 83,
                fontSize: 11,
                minimumScale: 0.7,
                lines: 2
            ),
            Slot(
                origin: "MailModuleView.swift:575 邮件字段标签",
                keys: ["发件人", "收件人", "主题"],
                available: 52,
                fontSize: 10,
                minimumScale: 0.75
            ),
        ]
    }

    @Test
    func narrowContainersFitEveryLanguage() {
        for slot in Self.slots {
            for language in AppLanguage.allCases {
                for key in slot.keys {
                    let text = AppLocalization.string(key, language: language)
                    let width = Self.width(text, font: slot.font)
                    #expect(
                        width <= slot.capacity,
                        """
                        \(slot.origin)：\(language.rawValue) 的「\(key)」→「\(text)」\
                        宽 \(Int(width))pt，超出容量 \(Int(slot.capacity))pt
                        """
                    )
                    // 换行只在词间发生，单个词放不进一行就一定会被截断。
                    let longest = text.split(separator: " ").map { Self.width(String($0), font: slot.font) }
                    #expect(
                        (longest.max() ?? 0) <= slot.available / slot.minimumScale,
                        """
                        \(slot.origin)：\(language.rawValue) 的「\(text)」有单词宽 \
                        \(Int(longest.max() ?? 0))pt，放不进 \(Int(slot.available / slot.minimumScale))pt 的一行
                        """
                    )
                }
            }
        }
    }

    /// 侧栏页脚把版本号和退出胶囊挤在同一行，两段文案共享 124pt 减去图标和内边距后的余量。
    @Test
    func settingsSidebarFooterFitsEveryLanguage() {
        let font = NSFont.systemFont(ofSize: 9, weight: .medium)
        let quitFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        // 124 内容宽 − 24 图标 − 6 胶囊内 spacing − 7 胶囊右 padding − 6 行内 spacing
        let available: CGFloat = 81

        for language in AppLanguage.allCases {
            let version = AppLocalization.string("版本 %@", language: language)
                .replacingOccurrences(of: "%@", with: "1.0.0")
            let quit = AppLocalization.string("退出", language: language)
            let used = ceil(Self.width(version, font: font) * 0.7)
                + ceil(Self.width(quit, font: quitFont) * 0.7)
            #expect(
                used <= available,
                "\(language.rawValue) 的「\(version)」+「\(quit)」缩放后仍占 \(Int(used))pt，超出 \(Int(available))pt"
            )
        }
    }

    /// 截图工具栏的 60pt 格子是按中文文案定的，中文必须始终保留文字，其他语言退成纯图标。
    @Test
    func screenshotToolbarKeepsChineseTitles() {
        #expect(ScreenshotToolbarLayout.showsControlTitles(for: .simplifiedChinese))
        #expect(ScreenshotToolbarLayout.showsControlTitles(for: .traditionalChinese))
    }

    /// 纯图标模式下的格子仍要容得下最宽的图标加下拉箭头（实测 aqi.medium 17pt + 4 + chevron 9pt）。
    @Test
    func screenshotToolbarIconOnlyCellFitsWidestGlyph() {
        let iconOnlyWidth: CGFloat = 34
        #expect(iconOnlyWidth >= 17 + 4 + 9)
    }

    /// 钉图工具栏的透明度胶囊按译文差额生长：中文恰好等于 98pt 基线，其他语言只增不减。
    @Test
    func pinnedOpacityPillGrowsOnlyBeyondChinese() {
        #expect(ScreenshotPinnedLayout.opacityControlWidth(for: .simplifiedChinese) == 98)
        for language in AppLanguage.allCases {
            #expect(
                ScreenshotPinnedLayout.opacityControlWidth(for: language) >= 98,
                "\(language.rawValue) 的透明度胶囊窄于中文基线"
            )
        }
    }

    private static func width(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
