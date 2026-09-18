import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

/// Catalog lookup and clipboard routing for English, Chinese, and shortcode emoji names.
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
    func offersInputMethodStyleCandidatesForNaturalChineseNames() {
        for name in ["微笑的猫", "得意地笑的猫脸", "露齿而笑的猫脸"] {
            #expect(
                EmojiNameCatalog.emojiCandidates(for: name).contains("😺"),
                "\(name) should include grinning cat among its candidates"
            )
        }
    }

    @Test
    func resolvesShortcodeForms() {
        #expect(EmojiNameCatalog.emoji(for: ":fire:") == "🔥")
        #expect(EmojiNameCatalog.emoji(for: ":thumbs_up:") == "👍")
        #expect(EmojiNameCatalog.emoji(for: ":thumbsup:") == "👍")
        #expect(EmojiNameCatalog.emoji(for: ":red-heart:") == "❤️")
        #expect(EmojiNameCatalog.emoji(for: ":100:") == "💯")
        #expect(EmojiNameCatalog.emoji(for: ":grinning_cat:") == "😺")
        #expect(EmojiNameCatalog.emoji(for: ":world:") == "🌍")
    }

    @Test
    func reservesSupplementalKeywordsForExplicitShortcodes() {
        for name in ["no", "test", "run", "walk", "safari"] {
            #expect(
                EmojiNameCatalog.emojiCandidates(for: name, language: .english).isEmpty,
                "\(name) should remain plain copied text"
            )
        }
        #expect(EmojiNameCatalog.emojiCandidates(for: ":run:", language: .english).contains("🏃"))
        #expect(EmojiNameCatalog.emojiCandidates(for: ":safari:", language: .english).contains("🦁"))
    }

    @Test
    func resolvesEmoji17AdditionsFromTheBundledCatalog() {
        #expect(EmojiNameCatalog.emojiCandidates(for: "distorted face", language: .english).contains("🫪"))
        #expect(EmojiNameCatalog.emojiCandidates(for: "orca", language: .english).contains("🫍"))
    }

    @Test(arguments: AppLanguage.allCases)
    func bundledCatalogCoversTheStableRosterInEverySupportedLanguage(language: AppLanguage) throws {
        let englishCount = try #require(EmojiNameCatalog.supplementalEmojiCount(for: .english))
        let count = try #require(EmojiNameCatalog.supplementalEmojiCount(for: language))
        let sample = try #require(EmojiNameCatalog.supplementalSampleAlias(for: language))

        #expect(englishCount >= 3_944)
        #expect(count == englishCount)
        #expect(EmojiNameCatalog.emojiCandidates(for: sample.alias, language: language).contains(sample.emoji))
    }

    @Test
    func rejectsOrdinaryProseAndUnknownNames() {
        #expect(EmojiNameCatalog.emoji(for: "hello world") == nil)
        #expect(EmojiNameCatalog.emoji(for: "the fire spread quickly") == nil)
        #expect(EmojiNameCatalog.emoji(for: "12345") == nil)
        #expect(EmojiNameCatalog.emoji(for: "🔥") == nil)
        #expect(EmojiNameCatalog.emoji(for: "我喜欢微笑的猫") == nil)
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
        // Verify every source alias resolves through the same normalization path as a query.
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
        // Cross-entry duplicates would make the result depend on dictionary iteration order.
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
        // A Chinese emoji name must resolve before the language and plain-text fallbacks.
        let detection = ClipboardAssistantDetector.detect(text: "微笑", enabledKinds: allKinds)
        #expect(detection?.kind == .emojiName)
        #expect(detection?.emoji == "🙂")
    }

    @Test
    func detectorOffersChineseSystemEmojiCandidatesBeforeLanguageFallback() {
        let detection = ClipboardAssistantDetector.detect(text: "得意地笑的猫脸", enabledKinds: allKinds)
        #expect(detection?.kind == .emojiName)
        #expect(detection?.actions.contains(.copyEmoji("😺")) == true)
        let identifiers = detection?.actions.map(\.identifier) ?? []
        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test
    func detectorKeepsSentencesOnTextKinds() {
        let detection = ClipboardAssistantDetector.detect(text: "I love fire", enabledKinds: allKinds)
        #expect(detection?.kind != .emojiName)
        #expect(detection?.emoji == nil)

        let chinese = ClipboardAssistantDetector.detect(text: "我喜欢微笑的猫", enabledKinds: allKinds)
        #expect(chinese?.kind != .emojiName)
        #expect(chinese?.emoji == nil)

        let imperative = ClipboardAssistantDetector.detect(text: "go for a walk", enabledKinds: allKinds)
        #expect(imperative?.kind != .emojiName)
        #expect(imperative?.emoji == nil)
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

    @Test
    func emojiCandidateActionsHaveDistinctIdentifiers() {
        #expect(ClipboardAssistantAction.copyEmoji("😸").identifier != ClipboardAssistantAction.copyEmoji("😺").identifier)
    }
}
