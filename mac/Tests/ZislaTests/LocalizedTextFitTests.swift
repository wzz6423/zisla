import AppKit
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

/// Translations can double the width of Chinese labels. Measure every language
/// to catch truncation that the available width and minimum scale cannot avoid.
@MainActor
struct LocalizedTextFitTests {
    /// Use the actual text width and the same scale and line limits as the view.
    private struct Slot {
        let origin: String
        let keys: [String]
        let available: CGFloat
        let fontSize: CGFloat
        let minimumScale: CGFloat
        var lines: Int = 1

        var font: NSFont { NSFont.systemFont(ofSize: fontSize, weight: .medium) }
        var capacity: CGFloat { available * CGFloat(lines) / minimumScale }
    }

    private static var slots: [Slot] {
        [
            Slot(
                origin: "SettingsView.swift:113 侧栏分区标题",
                keys: SettingsSection.allCases.map(\.title),
                // 148pt sidebar minus 24pt outer padding, 16pt row padding, 17pt icon, and 8pt spacing.
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
                    // Wrapping only happens between words; a word wider than one line still truncates.
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

    /// The version and quit labels share the footer width after icons and padding.
    @Test
    func settingsSidebarFooterFitsEveryLanguage() {
        let font = NSFont.systemFont(ofSize: 9, weight: .medium)
        let quitFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        // 124pt content minus 24pt icon, 6pt pill spacing, 7pt pill padding, and 6pt row spacing.
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

    /// The 60pt toolbar cells fit Chinese titles; other languages use icons only.
    @Test
    func screenshotToolbarKeepsChineseTitles() {
        #expect(ScreenshotToolbarLayout.showsControlTitles(for: .simplifiedChinese))
        #expect(ScreenshotToolbarLayout.showsControlTitles(for: .traditionalChinese))
    }

    /// The widest icon needs 17pt, plus 4pt spacing and a 9pt dropdown chevron.
    @Test
    func screenshotToolbarIconOnlyCellFitsWidestGlyph() {
        let iconOnlyWidth: CGFloat = 34
        #expect(iconOnlyWidth >= 17 + 4 + 9)
    }

    /// Translations can widen the pinned opacity control beyond its 98pt Chinese baseline.
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

    /// The strength column must fit its widest translation without shrinking below
    /// the 36pt Chinese baseline, or the slider will truncate the label.
    @Test
    func obscureStrengthLabelColumnFitsEveryLanguage() {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        #expect(ScreenshotToolbarLayout.obscureStrengthLabelWidth(for: .simplifiedChinese) == 36)

        for language in AppLanguage.allCases {
            let column = ScreenshotToolbarLayout.obscureStrengthLabelWidth(for: language)
            #expect(column >= 36, "\(language.rawValue) 的强度标签列窄于中文基线")
            for key in ["粗细", "模糊度", "格子"] {
                let text = AppLocalization.string(key, language: language)
                let width = Self.width(text, font: font)
                #expect(
                    width <= column,
                    "\(language.rawValue) 的「\(key)」→「\(text)」宽 \(Int(width))pt，超出 \(Int(column))pt 的标签列"
                )
            }
        }
    }

    /// A missing strength label silently falls back to Chinese in any of the language tables.
    @Test
    func obscurePanelLabelsAreTranslated() {
        for key in ["粗细", "模糊度", "格子", "画笔粗细"] {
            for language in AppLanguage.allCases {
                let text = AppLocalization.string(key, language: language)
                #expect(!text.isEmpty, "\(language.rawValue) 的「\(key)」为空")
                guard language != .simplifiedChinese, language != .traditionalChinese else { continue }
                #expect(text != key, "\(language.rawValue) 缺「\(key)」的译文")
            }
        }
    }

    @Test
    func clipboardRowSubtitleFitsEveryLanguage() {
        let font = NSFont.systemFont(ofSize: 9, weight: .medium)
        // Remaining width after module, list, thumbnail, and action insets in the 820pt island.
        let available: CGFloat = 386
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let copiedAt = calendar.date(
            from: DateComponents(year: 2025, month: 12, day: 31, hour: 23, minute: 59, second: 59)
        )!
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let timestamp = ClipboardHistoryItem(content: .text("剪贴板内容"), lastCopiedAt: copiedAt)
            .lastCopiedAtText(now: now, calendar: calendar)

        for language in AppLanguage.allCases {
            for kind in ["文本", "图片", "文件"] {
                let copiedAtText = AppLocalization.string("拷贝于 %@", language: language)
                #expect(copiedAtText.contains("%@"), "\(language.rawValue) 的拷贝时间译文缺少占位符")
                if language != .simplifiedChinese {
                    #expect(copiedAtText != "拷贝于 %@", "\(language.rawValue) 缺少拷贝时间译文")
                }
                let subtitle = AppLocalization.string(kind, language: language)
                    + " · "
                    + AppLocalization.format("拷贝于 %@", locale: language.locale, [timestamp])
                #expect(subtitle.contains(timestamp), "\(language.rawValue) 的时间戳未进入剪贴板副标题")
                let width = Self.width(subtitle, font: font)
                #expect(
                    width <= available,
                    "\(language.rawValue) 的「\(subtitle)」宽 \(Int(width))pt，超出 \(Int(available))pt"
                )
            }
        }
    }

    private static func width(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
