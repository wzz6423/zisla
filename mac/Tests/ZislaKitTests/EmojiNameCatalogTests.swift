import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

/// Emoji 名称识别：目录查找（英文、中文、shortcode、大小写与空白归一化）
/// 以及复制助手检测分支的路由与开关行为。
struct EmojiNameCatalogTests {
    private let allKinds = Set(ClipboardAssistantKind.allCases)

    // MARK: - Catalog lookups

    @Test
    func resolvesCanonicalEnglishNames() {
        #expect(EmojiNameCatalog.emoji(for: "fire") == "🔥")
        #expect(EmojiNameCatalog.emoji(for: "thumbs up") == "👍")
        #expect(EmojiNameCatalog.emoji(for: "grinning face") == "😀")
        #expect(EmojiNameCatalog.emoji(for: "red heart") == "❤️")
        #expect(EmojiNameCatalog.emoji(for: "party popper") == "🎉")
        #expect(EmojiNameCatalog.emoji(for: "birthday cake") == "🎂")
        #expect(EmojiNameCatalog.emoji(for: "smiling face with smiling eyes") == "😊")
        #expect(EmojiNameCatalog.emoji(for: "rocket") == "🚀")
    }

    @Test
    func resolvesCaseAndWhitespaceVariants() {
        #expect(EmojiNameCatalog.emoji(for: "Fire") == "🔥")
        #expect(EmojiNameCatalog.emoji(for: "  THUMBS   UP  ") == "👍")
        #expect(EmojiNameCatalog.emoji(for: "Rocket") == "🚀")
        #expect(EmojiNameCatalog.emoji(for: "RED\nHEART") == "❤️")
    }

    @Test
    func resolvesChineseNames() {
        #expect(EmojiNameCatalog.emoji(for: "火") == "🔥")
        #expect(EmojiNameCatalog.emoji(for: "火箭") == "🚀")
        #expect(EmojiNameCatalog.emoji(for: "点赞") == "👍")
        #expect(EmojiNameCatalog.emoji(for: "竖起大拇指") == "👍")
        #expect(EmojiNameCatalog.emoji(for: "笑哭") == "😂")
        #expect(EmojiNameCatalog.emoji(for: "爱心") == "❤️")
        #expect(EmojiNameCatalog.emoji(for: "红包") == "🧧")
        #expect(EmojiNameCatalog.emoji(for: "狗") == "🐶")
        #expect(EmojiNameCatalog.emoji(for: "龙") == "🐉")
        #expect(EmojiNameCatalog.emoji(for: "烟花") == "🎆")
    }

    @Test
    func resolvesShortcodeForms() {
        #expect(EmojiNameCatalog.emoji(for: ":fire:") == "🔥")
        #expect(EmojiNameCatalog.emoji(for: ":thumbs_up:") == "👍")
        #expect(EmojiNameCatalog.emoji(for: ":thumbsup:") == "👍")
        #expect(EmojiNameCatalog.emoji(for: ":red-heart:") == "❤️")
        #expect(EmojiNameCatalog.emoji(for: ":100:") == "💯")
    }

    @Test
    func rejectsOrdinaryProseAndUnknownNames() {
        #expect(EmojiNameCatalog.emoji(for: "hello world") == nil)
        #expect(EmojiNameCatalog.emoji(for: "the fire spread quickly") == nil)
        #expect(EmojiNameCatalog.emoji(for: "12345") == nil)
        #expect(EmojiNameCatalog.emoji(for: "🔥") == nil)
        #expect(EmojiNameCatalog.emoji(for: "") == nil)
        #expect(EmojiNameCatalog.emoji(for: "   ") == nil)
        #expect(EmojiNameCatalog.emoji(for: ":") == nil)
        #expect(EmojiNameCatalog.emoji(for: String(repeating: "a", count: 65)) == nil)
    }

    @Test
    func catalogIsLargeEnoughToBeUseful() {
        #expect(EmojiNameCatalog.entries.count >= 400, "目录条目意外变少：\(EmojiNameCatalog.entries.count)")
    }

    @Test
    func everyAliasResolvesThroughTheLookup() {
        // 查找表由条目构建而成；这里反向核对每个别名都能命中所属 emoji，
        // 防止归一化在构建与查询两侧走偏。
        for (emoji, names) in EmojiNameCatalog.entries {
            for alias in names.english + names.chinese {
                #expect(
                    EmojiNameCatalog.emoji(for: alias) == emoji,
                    "别名「\(alias)」应解析为 \(emoji)"
                )
            }
        }
    }

    @Test
    func noAliasMapsToTwoEmoji() {
        // 查找表是 last-write-wins，别名一旦跨条目重复，结果将随字典顺序漂移。
        var owners: [String: String] = [:]
        var duplicates: [String] = []
        for (emoji, names) in EmojiNameCatalog.entries {
            for alias in names.english + names.chinese {
                let key = EmojiNameCatalog.normalizedKey(alias)
                if let owner = owners[key], owner != emoji {
                    duplicates.append("「\(alias)」同时属于 \(owner) 和 \(emoji)")
                }
                owners[key] = emoji
            }
        }
        #expect(duplicates.isEmpty, "发现重复别名：\(duplicates.joined(separator: "；"))")
    }

    // MARK: - Detector routing

    @Test
    func detectorRecognizesEmojiNames() {
        let detection = ClipboardAssistantDetector.detect(text: "fire", enabledKinds: allKinds)
        #expect(detection?.kind == .emojiName)
        #expect(detection?.emoji == "🔥")
        #expect(detection?.title == "fire")
        #expect(detection?.action == .copyEmoji("🔥"))
        #expect(detection?.secondaryActions == [])
    }

    @Test
    func detectorRecognizesChineseNamesBeforeLanguageFallback() {
        // 「微笑」在英文系统上会被非系统语言分支抢去翻译、被普通文本分支抢去搜索；
        // emoji 名称分支必须先命中。
        let detection = ClipboardAssistantDetector.detect(text: "微笑", enabledKinds: allKinds)
        #expect(detection?.kind == .emojiName)
        #expect(detection?.emoji == "🙂")
    }

    @Test
    func detectorKeepsSentencesOnTextKinds() {
        let detection = ClipboardAssistantDetector.detect(text: "I love fire", enabledKinds: allKinds)
        #expect(detection?.kind != .emojiName)
        #expect(detection?.emoji == nil)
    }

    @Test
    func detectorHonorsDisabledEmojiKind() {
        let kinds = allKinds.subtracting([.emojiName])
        let detection = ClipboardAssistantDetector.detect(text: "fire", enabledKinds: kinds)
        #expect(detection?.kind != .emojiName)
        #expect(detection?.emoji == nil)
    }

    // MARK: - Action ordering contract

    @Test
    func emojiActionOrderPutsCopyFirstAndSharingLast() {
        let order = ClipboardAssistantActionOrder.defaults(for: .emojiName)
        #expect(order.first == .copyEmoji)
        #expect(order.last == .share)
    }

    @Test
    func normalizedOrdersMigrateUnknownKindsToDefaults() {
        let normalized = ClipboardAssistantActionOrder.normalized(
            [ClipboardAssistantKind: [ClipboardAssistantActionKind]]()
        )
        #expect(normalized[.emojiName] == ClipboardAssistantActionOrder.defaults(for: .emojiName))
    }
}
