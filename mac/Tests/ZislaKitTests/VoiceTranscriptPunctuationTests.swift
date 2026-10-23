import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct VoiceTranscriptPunctuationTests {
    @Test(arguments: [
        ("你好 , 世界 !", "你好，世界！"),
        ("明天开会吗 ?可以的话 ,请回复。", "明天开会吗？可以的话，请回复。"),
        ("请使用 Swift,然后打开 GitHub.", "请使用 Swift，然后打开 GitHub。"),
        ("第一项:更新模型;第二项:更新词库.", "第一项：更新模型；第二项：更新词库。"),
        ("价格 3.14 元,开会时间 10:30.", "价格 3.14 元，开会时间 10:30。"),
        ("你好，，世界，。", "你好，世界。"),
        ("你好 , !请等等 , , 世界 , 。", "你好！请等等，世界。"),
        ("明天开会吗？。真的！！。", "明天开会吗？真的！！"),
        ("Hello ,world!Please wait.", "Hello, world! Please wait."),
        ("Hello,world!\n你好 , 世界 !", "Hello, world!\n你好，世界！"),
        ("Hello,world\n你好,世界", "Hello, world\n你好，世界"),
        ("Hello,world.你好,世界.", "Hello, world. 你好，世界。"),
        ("He said “你好”,then left.", "He said “你好”, then left."),
        ("He said,\"wait\".", "He said, \"wait\"."),
        ("原话是“甲\n乙”,请保留.", "原话是“甲\n乙”，请保留。"),
        ("我说“甲\n乙”,then returned.", "我说“甲\n乙”，then returned。"),
        ("请运行 `fn(a,b)` ,然后返回 .", "请运行 `fn(a,b)`，然后返回。"),
        ("请运行 `print(a,b)` ,然后返回 .", "请运行 `print(a,b)`，然后返回。"),
        ("调用 process(a,b) ,然后返回 .", "调用 process(a,b)，然后返回。"),
        ("请联系 Dr. Lee,稍后确认.", "请联系 Dr. Lee，稍后确认。"),
        ("事项 :\n  1、检查 ,完成\n\t2、提交 ;完成", "事项：\n  1、检查，完成\n\t2、提交；完成"),
        ("1. 检查,完成\n2. 提交.", "1. 检查，完成\n2. 提交。"),
        ("1.检查,完成\n2.提交.", "1.检查，完成\n2.提交。"),
        ("你好\u{00A0},\u{3000}世界\u{3000}!", "你好，世界！"),
        ("你好\t,\t世界\t!", "你好，世界！"),
        ("你好\u{2002},\u{202F}世界\u{205F}!", "你好，世界！"),
        ("こんにちは ,世界 !", "こんにちは，世界！"),
        ("ありがとう ,またね !", "ありがとう，またね！"),
        ("スイフト ,テスト !", "スイフト，テスト！"),
    ])
    func normalizesPunctuationWithoutChangingWords(_ input: String, _ expected: String) {
        #expect(VoiceTranscriptPostProcessor.deliveredText(input, fallback: input) == expected)
    }

    @Test(arguments: [
        "今天先检查，确认后再提交。",
        "Hello, world! What changed?",
        "你好...我还在想",
        "等等……让我想想",
        "真的假的？！太好了！！",
        "我想先",
        "git commit -m 'hello,world'",
        "let values = [1,2,3]; print(values)",
        "SELECT id,name FROM users;",
        "文档里的 ‘你好 , 世界 !’ 要原样保留。",
        "原话是“为什么 , 不行 ?”，不要改动。",
        "参数是 1,000、3.14、10:30、v3.5-4B 和 192.168.1.1。",
        "地址 https://example.com/a,b?q=1,2#x:y 和 /tmp/a,b.txt 都原样保留。",
        "Namespace::Type",
        "Wait . . . let me think",
        "你好,...我还在想",
        "例如 e.g. 或 i.e. 这种缩写不改。",
        "Dr. Lee, please wait.",
        "git log --pretty=format:%h,%s",
        "git -c key=a,b status",
        "curl -H Accept:a,b https://example.com",
        "echo 你好,world!",
        "printf hello,world",
        "ssh host echo a,b",
        "npm run test,a,b",
        "pnpm run test,a,b",
        "swift run hello,world",
        "python -m module a,b",
        "python3 -m module a,b",
        "make targets=a,b",
        "{\"label\":\"你好,world!\"}",
    ])
    func preservesCorrectPunctuationAndTechnicalLiterals(_ input: String) {
        #expect(VoiceTranscriptPostProcessor.deliveredText(input, fallback: input) == input)
    }

    @Test(arguments: ["", " \t\r\n ", "🙂", "、……", "？！", ",;"])
    func emptyAndPunctuationOnlyInputsRemainIntact(_ input: String) {
        #expect(VoiceTranscriptPunctuation.normalize(input) == input)
    }

    @Test
    func keepsIndentationAndMarkdownLineBreaks() {
        #expect(VoiceTranscriptPunctuation.normalize("  ,你好 .  \n\t,请等一下 .") == "  ，你好。  \n\t，请等一下。")
        #expect(VoiceTranscriptPunctuation.normalize("你好 .  ") == "你好。  ")
    }

    @Test(arguments: [
        "A:B!", "Nova,Desk", "A+B,C", "你好,world!", "团队;甲", "https://example.com/资料?a=1,2",
        "/tmp/資料📁/a,b.txt", "e\u{301}.txt", "\"quoted , text !\"", "`fn(a,b)`",
    ])
    func literalsAndPersonalSpellingSurviveSurroundingPunctuationCleanup(_ literal: String) {
        let input = "请保留 \(literal) ,然后返回 ."
        let expected = "请保留 \(literal)，然后返回。"
        let actual = VoiceTranscriptPunctuation.normalize(input, customHotwords: [literal])
        #expect(actual.utf8.elementsEqual(expected.utf8))
        #expect(VoiceTranscriptPunctuation.normalize(actual, customHotwords: [literal]) == actual)
        #expect(VoiceTranscriptPostProcessor.deliveredText(input, fallback: input, customHotwords: [literal]) == expected)
        let local = VoiceLexicon.normalizeTranscript(input, for: [], customTerms: [literal])
        #expect(VoiceTranscriptPunctuation.normalize(local, customHotwords: [literal]) == expected)
    }

    @Test(arguments: [
        ("请使用 nova,desk,稍后继续.", ["Nova,Desk"], "请使用 nova,desk，稍后继续。"),
        ("请使用 xNova,Desk,稍后继续.", ["Nova,Desk"], "请使用 xNova，Desk，稍后继续。"),
        ("请使用 Nova,DeskX,稍后继续.", ["Nova,Desk"], "请使用 Nova，DeskX，稍后继续。"),
        ("A! !B", ["A!", "!B"], "A! !B"),
        ("A!\u{2002}!B", ["A!", "!B"], "A!\u{2002}!B"),
    ])
    func personalHotwordsMatchWholeLiteralsIgnoringCase(_ input: String, _ hotwords: [String], _ expected: String) {
        #expect(VoiceTranscriptPunctuation.normalize(input, customHotwords: hotwords) == expected)
    }

    @Test
    func boundedUnicodeInputsAreIdempotentAndPreserveAllNonPunctuationContent() {
        let atoms = ["你好", "world", "🙂", "é", "e\u{301}", ",", ".", "?", "!", ":", ";", "，", "。", "……", " ", "\t", "\r\n", "3.14", "10:30", "`a,b`", "https://example.com/a,b", "我"]
        var seed: UInt64 = 0x51_5A_2026
        func content(_ text: String) -> [Unicode.Scalar] {
            text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && !",.;:!?，。；：！？".unicodeScalars.contains($0) }
        }
        for _ in 0..<128 {
            let input = (0..<12).map { _ -> String in
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                return atoms[Int(seed % UInt64(atoms.count))]
            }.joined()
            let result = VoiceTranscriptPunctuation.normalize(input)
            #expect(content(result) == content(input), "Changed words at seed \(seed)")
            #expect(VoiceTranscriptPunctuation.normalize(result) == result, "Non-idempotent at seed \(seed)")
        }
    }

    @MainActor
    @Test
    func proofreadingFailureKeepsLocallyFormattedCleanup() async throws {
        let raw = "明天开会 , 稍后确认 ."
        let cleaned = "明天开会，稍后确认。"
        var requests = 0
        let result = try await VoiceTranscriptPostProcessor.process(
            rawTranscript: raw,
            lexiconNormalizedTranscript: VoiceTranscriptPunctuation.normalize(raw),
            proofreadingEnabled: true
        ) { _, messages in
            requests += 1
            let message = try #require(messages.first)
            let payload = try #require(JSONSerialization.jsonObject(with: Data(message.content.utf8)) as? [String: Any])
            #expect(payload["raw_transcript"] as? String == (requests == 1 ? raw : cleaned))
            #expect(payload["lexicon_transcript"] as? String == cleaned)
            if requests == 1 { return raw }
            throw URLError(.timedOut)
        }
        #expect(result == cleaned)
        #expect(requests == 2)
    }

    @MainActor
    @Test(arguments: [false, true])
    func bothModelPassesReceiveSemanticPunctuationRules(_ structuredFormatting: Bool) async throws {
        var prompts: [String] = []
        _ = try await VoiceTranscriptPostProcessor.process(
            rawTranscript: "我想知道是否可行",
            lexiconNormalizedTranscript: "我想知道是否可行",
            structuredFormattingEnabled: structuredFormatting,
            proofreadingEnabled: true
        ) { prompt, _ in
            prompts.append(prompt)
            return "我想知道是否可行。"
        }
        #expect(prompts.count == 2)
        for prompt in prompts {
            for rule in [
                "按完整语义断句", "不能按字数", "间接提问", "半截话",
                "当前分句语言", "技术字面量内部标点不改", "讨论标点名称",
            ] {
                #expect(prompt.contains(rule), "Missing punctuation contract: \(rule)")
            }
        }
    }
}
