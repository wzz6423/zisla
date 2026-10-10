import Foundation
import Testing
@testable import ZislaCore

struct VoiceLexiconTests {
    @Test
    func computerDictionaryIncludesLocalModelsAndInferenceTools() {
        let terms = VoiceLexicon.terms(for: [.computerTerms])
        for term in ["Gemma", "Qwen3.5", "Google", "LM Studio", "Ollama", "llama.cpp", "MLX", "GGUF", "QAT", "KV cache", "LoRA", "Hugging Face"] {
            #expect(terms.contains(term), "Missing local inference term: \(term)")
        }
    }

    @Test
    func recognitionHintsStayWithinSpeechBudgetAndPrioritizePersonalWords() {
        let hints = VoiceLexicon.contextualTerms(
            for: VoiceLexicon.defaultEnabled,
            customTerms: [" MyProduct ", "Gemma", "gemma", "", String(repeating: "长", count: 81), "a" + String(repeating: "\u{0301}", count: 1_000)]
        )
        #expect(hints.count == 100)
        #expect(Array(hints.prefix(2)) == ["MyProduct", "Gemma"])
        #expect(Set(hints.map { $0.lowercased() }).count == hints.count)
        #expect(hints.allSatisfy { $0.unicodeScalars.count <= 80 })
        for term in ["Qwen3.5", "GitHub", "SSH key", "唐诗", "新冠", "民法典"] {
            #expect(hints.contains(term), "Missing recognition hint: \(term)")
        }
        #expect(VoiceLexicon.contextualTerms(for: [], customTerms: []).isEmpty)
        #expect(VoiceLexicon.contextualTerms(for: [], customTerms: (0..<150).map { "Term\($0)" }).count == 100)
    }

    @Test
    func recognitionBudgetDoesNotLimitDeterministicNormalization() {
        let custom = (0..<110).map { "PersonalTerm\($0)" } + ["TailWord"]
        #expect(!VoiceLexicon.contextualTerms(for: [.computerTerms], customTerms: custom).contains("TailWord"))
        #expect(VoiceLexicon.normalizeTranscript("tail word 和 mcp registry", for: [.computerTerms], customTerms: custom)
            == "TailWord 和 MCP Registry")
    }

    @Test
    func personalSpellingsSurviveBuiltInMatchesAndContextualCorrection() {
        #expect(VoiceLexicon.normalizeTranscript(
            "gemma 系列", for: [.computerTerms], customTerms: ["gemma 系列"]
        ) == "gemma 系列")
        #expect(VoiceLexicon.normalizeTranscript(
            "Google 的伽马四模型", for: [.computerTerms], customTerms: ["gemma"]
        ) == "Google 的gemma四模型")
        #expect(VoiceLexicon.normalizeTranscript(
            "get up 的 SSH key", for: [.computerTerms], customTerms: ["github"]
        ) == "github 的 SSH key")
    }

    @Test
    func contextSelectionKeepsRelatedTermsAndBoundsPersonalVocabulary() {
        let text = "把推荐模型从Qwen3.5改成Google的gemma四系列吧，我实测下来反而gemma会快一点"
        let terms = VoiceLexicon.postProcessingTerms(
            in: text,
            for: VoiceLexicon.defaultEnabled,
            customTerms: ["MyProduct", "gemma"]
        )
        #expect(terms.first == "gemma")
        #expect(terms.contains("Qwen3.5"))
        #expect(terms.contains("Google"))
        #expect(!terms.contains("Gemma"))
        #expect(!terms.contains("床前明月光"))
        #expect(!terms.contains("玛巴洛沙韦"))
        #expect(VoiceLexicon.postProcessingTerms(in: text, for: []).isEmpty)
        let bounded = VoiceLexicon.postProcessingTerms(
            in: "Gemma 模型",
            for: VoiceLexicon.defaultEnabled,
            customTerms: (0..<200).map { "PersonalTerm\($0)" + String(repeating: "x", count: 50) }
                + [String(repeating: "长", count: 100_000), "New\nInstruction", "a" + String(repeating: "\u{0301}", count: 100_000)]
        )
        #expect(bounded.count <= 48)
        #expect(bounded.reduce(0) { $0 + $1.unicodeScalars.count } <= 1_024)
        #expect(bounded.allSatisfy { $0.unicodeScalars.count <= 80 && !$0.contains("\n") })
        #expect(bounded.allSatisfy { $0.utf8.count <= 320 })
        #expect(bounded.contains("Gemma"))
    }

    @Test
    func contextSelectionPrioritizesMentionedPersonalWordsWithinBothBudgets() {
        let shortTerms = (0..<100).map { "Hotword\($0)" }
        let selected = VoiceLexicon.postProcessingTerms(
            in: shortTerms.joined(separator: " "), for: [], customTerms: shortTerms
        )
        #expect(selected.count == 48)
        let longTerms = shortTerms.map { $0 + String(repeating: "x", count: 60) }
        let characterBounded = VoiceLexicon.postProcessingTerms(
            in: longTerms.joined(separator: " "), for: [], customTerms: longTerms
        )
        #expect(characterBounded.reduce(0) { $0 + $1.unicodeScalars.count } <= 1_024)
        #expect(characterBounded.count < selected.count)
        #expect(VoiceLexicon.postProcessingTerms(
            in: "NovaDesk", for: [], customTerms: shortTerms + ["NovaDesk"]
        ).first == "NovaDesk")
        #expect(VoiceLexicon.postProcessingTerms(
            in: "明天开会", for: [], customTerms: shortTerms
        ).count == 16)
    }

    @Test
    func correctsOnlyExplicitModelAliasesWithoutChangingVersionDigits() {
        let input = "把推荐模型从Q运3.5改成Google的伽马四系列吧，我实测下来反而感冒会快一点"
        #expect(VoiceLexicon.normalizeTranscript(input, for: [.computerTerms])
            == "把推荐模型从Qwen3.5改成Google的Gemma四系列吧，我实测下来反而感冒会快一点")
        #expect(VoiceLexicon.normalizeTranscript(input, for: []) == input)
        #expect(VoiceLexicon.postProcessingTerms(in: input, for: [.computerTerms]).contains("Gemma"))
        #expect(VoiceLexicon.postProcessingTerms(in: input, for: [.computerTerms]).contains("Qwen3.5"))
        #expect(VoiceLexicon.normalizeTranscript("Q运3.5 模型", for: [.computerTerms]) == "Qwen3.5 模型")
    }

    @Test(arguments: [
        "今天感冒了，我实测下来反而感冒会快一点。",
        "用 Google 搜索伽马射线和伽马函数。",
        "Google 的 Gemma 模型可以解释伽马射线，今天我感冒了。",
        "Google 的伽马射线模型和伽马分布是两个概念。",
        "伽马四系列吧，我也不确定是什么。",
        "Q运3.5 是我随手写的记号。",
        "用 Google 查询 Q运3.5 线路。",
        "用 Q运3.5 线路测试 Gemma 模型。",
        "这个模型从 Q运3.5 线路获取数据。",
        "NotGoogle 的伽马四系列。",
    ])
    func preservesOrdinaryHomophones(_ transcript: String) {
        #expect(VoiceLexicon.normalizeTranscript(transcript, for: [.computerTerms]) == transcript)
    }

    @Test(arguments: [
        "Qwen3.5 和 Qwen3.5-4B、Gemma 4 E4B、Gemma四系列。",
        "Qwen35、Qwen3-5、Qwen3/5、Gemma四系列都按原样保留。",
        "3.5、35、三点五、4、四，不要互换。",
        "使用 https://example.com/Qwen3.5?q=4 和 /tmp/Gemma4.txt。",
        "使用 https://github.com 和 /tmp/gemma4.swift。",
        "读取 Gemma.swift、qwen.py 和 gemma.test.swift。",
        "读取 gemma/source.swift、文档/gemma.swift 和 模型.swift。",
        "读取 /tmp/get.hub 和 get.hub/config 里的 SSH key。",
        "打开 https://get-up.example.com 和 /tmp/开元项目/Google的伽马四模型.txt。",
    ])
    func preservesModelVersionsAndNumberForms(_ transcript: String) {
        #expect(VoiceLexicon.normalizeTranscript(transcript, for: [.computerTerms]) == transcript)
    }

    @Test(arguments: [
        (VoiceLexicon.computerTerms, "比较 Gemma 与 Qwen3.5，使用 LM Studio。", ["Gemma", "Qwen3.5", "LM Studio"]),
        (.classicalPoetry, "李白写下床前明月光，苏轼作水调歌头。", ["李白", "床前明月光", "苏轼", "水调歌头"]),
        (.internetBuzzwords, "这段电子榨菜 YYDS，氛围很有松弛感。", ["电子榨菜", "YYDS", "松弛感"]),
        (.peopleAndPlaces, "张伟从北京到上海，与埃隆·马斯克见面。", ["张伟", "北京", "上海", "埃隆·马斯克"]),
        (.brandsAndProducts, "用 ChatGPT 整理 MacBook 上的 Notion 笔记。", ["ChatGPT", "MacBook", "Notion"]),
        (.medicineAndHealth, "布洛芬、CT 和 HPV疫苗是记录中的三个术语。", ["布洛芬", "CT", "HPV疫苗"]),
        (.lawAndGovernment, "依据民法典和个人信息保护法准备合同。", ["民法典", "个人信息保护法", "合同"]),
        (.financeAndBusiness, "这只 ETF 的市盈率较低，关注现金流。", ["ETF", "市盈率", "现金流"]),
        (.educationAndResearch, "论文引用6G和因果推断，补全参考文献。", ["论文", "6G", "因果推断", "参考文献"]),
        (.filmAndMusic, "用 Spotify 听 Taylor Swift，再看流浪地球。", ["Spotify", "Taylor Swift", "流浪地球"]),
        (.gamesAndAnime, "在 PlayStation 玩原神，也使用 Steam。", ["PlayStation", "原神", "Steam"]),
        (.travelAndTransport, "乘坐 C919，使用铁路12306和高德地图。", ["C919", "铁路12306", "高德地图"]),
        (.dailyLife, "通过小程序点低GI轻食，周末去Citywalk。", ["小程序", "低GI", "轻食", "Citywalk"]),
    ])
    func keepsCorrectNamesAndSelectsOnlyMentionedReferences(
        _ lexicon: VoiceLexicon,
        _ transcript: String,
        _ names: [String]
    ) {
        #expect(VoiceLexicon.normalizeTranscript(transcript, for: [lexicon]) == transcript)
        let references = VoiceLexicon.postProcessingTerms(in: transcript, for: [lexicon])
        #expect(names.allSatisfy(references.contains))
        #expect(references.allSatisfy { transcript.localizedCaseInsensitiveContains($0) })
    }

    @Test(arguments: [
        (VoiceLexicon.computerTerms, "用 l m studio 加载 gemma，比较 qwen3.5。", "用 LM Studio 加载 Gemma，比较 Qwen3.5。"),
        (.classicalPoetry, "读念奴娇 赤壁怀古，再读水调歌头。", "读念奴娇·赤壁怀古，再读水调歌头。"),
        (.internetBuzzwords, "这段演出 y y d s，今天有点 EMO。", "这段演出 YYDS，今天有点 emo。"),
        (.peopleAndPlaces, "埃隆 马斯克与萨姆 奥特曼会面。", "埃隆·马斯克与萨姆·奥特曼会面。"),
        (.brandsAndProducts, "在 mac book 上打开 chat gpt 和 open ai。", "在 MacBook 上打开 ChatGPT 和 OpenAI。"),
        (.medicineAndHealth, "预约 c t，记录 h p v 疫苗。", "预约 CT，记录 HPV疫苗。"),
        (.lawAndGovernment, "参照《民法典》，保留“个人信息 保护法”的原始分隔。", "参照《民法典》，保留“个人信息 保护法”的原始分隔。"),
        (.financeAndBusiness, "关注 e t f、g d p 和 a 股。", "关注 ETF、GDP 和 A股。"),
        (.educationAndResearch, "研究 6 G 与人工智能 + X。", "研究 6G 与人工智能+X。"),
        (.filmAndMusic, "用 spotify 播放 taylor swift 和 apple music。", "用 Spotify 播放 Taylor Swift 和 Apple Music。"),
        (.gamesAndAnime, "记录 play station、c s 2 和 p u b g 的名称。", "记录 PlayStation、CS2 和 PUBG 的名称。"),
        (.travelAndTransport, "乘坐 c 919，使用铁路 12306 和 e t c。", "乘坐 C919，使用铁路12306 和 ETC。"),
        (.dailyLife, "通过小程序购买低 gi 食品，周末 citywalk。", "通过小程序购买低GI 食品，周末 Citywalk。"),
    ])
    func normalizesSupportedCaseAndSpacingVariants(
        _ lexicon: VoiceLexicon,
        _ transcript: String,
        _ expected: String
    ) {
        #expect(VoiceLexicon.normalizeTranscript(transcript, for: [lexicon]) == expected)
    }

    @Test(arguments: [
        (VoiceLexicon.computerTerms, "把这个词写成 Gemna，不要猜成其他模型。"),
        (.classicalPoetry, "原文写的是床前明月广，不确定是否抄错。"),
        (.internetBuzzwords, "他说绝绝仔，这个新词我还不认识。"),
        (.peopleAndPlaces, "联系人叫张维，请按这个姓名记录。"),
        (.brandsAndProducts, "设备显示 ChatGBT，请保留报错中的拼写。"),
        (.medicineAndHealth, "处方上写布洛风，药名需要人工核对。"),
        (.lawAndGovernment, "记录里写民发典，需要核对原件。"),
        (.financeAndBusiness, "字段名称是市银率，先照抄。"),
        (.educationAndResearch, "研究标签写作六G，暂时不要转成数字。"),
        (.filmAndMusic, "艺人署名 Taylor Swiff，需要重新核对。"),
        (.gamesAndAnime, "账号标签是 PlayStaiton，原文如此。"),
        (.travelAndTransport, "航空记录为 C91O，最后一位是字母O。"),
        (.dailyLife, "店家自称蜜雪冰诚，先核对招牌。"),
    ])
    func doesNotGuessUnknownSpellings(_ lexicon: VoiceLexicon, _ transcript: String) {
        #expect(VoiceLexicon.normalizeTranscript(transcript, for: [lexicon]) == transcript)
    }

    @Test(arguments: [
        (VoiceLexicon.computerTerms, "Google 的 Gemma 可以解释伽马射线，但我今天感冒了。"),
        (.classicalPoetry, "今天随口说举头看看月亮，并不是在背古诗。"),
        (.internetBuzzwords, "院子里要拔草，米缸里还有谷子。"),
        (.peopleAndPlaces, "张伟只是示例名，这里谈的是长城的砖。"),
        (.brandsAndProducts, "苹果熟了，我们准备吃苹果。"),
        (.medicineAndHealth, "今天只是普通感冒，先测体温再休息。"),
        (.lawAndGovernment, "我说的合同是纸质原件，别补充未说的法律。"),
        (.financeAndBusiness, "他说给生活一点利息，这是比喻，不是在讨论利率。"),
        (.educationAndResearch, "世界模型只是标题，这里不改动三点五和3.5。"),
        (.filmAndMusic, "这句台词是我编的，别补成电影剧情。"),
        (.gamesAndAnime, "请把灯的开关关掉，再打开房门。"),
        (.travelAndTransport, "这里的绿灯只是桌面台灯，今天不出行。"),
        (.dailyLife, "我在院子里种草，雨停后去取快递。"),
    ])
    func preservesAmbiguousEverydayMeanings(_ lexicon: VoiceLexicon, _ transcript: String) {
        #expect(VoiceLexicon.normalizeTranscript(transcript, for: [lexicon]) == transcript)
    }

    @Test(arguments: [
        (VoiceLexicon.computerTerms, "读取 gemma.swift 和 /tmp/qwen3.5.json。"),
        (.classicalPoetry, "打开 /tmp/念奴娇_赤壁怀古.txt 和 ./床前明月广.md。"),
        (.internetBuzzwords, "读取 /tmp/yyds.txt、emo.log 和 https://example.com/Y_Y_D_S。"),
        (.peopleAndPlaces, "读取 /tmp/埃隆-马斯克.txt 和 ./萨姆_奥特曼.md。"),
        (.brandsAndProducts, "打开 chatgpt.md、/tmp/macbook.json 和 https://example.com/open-ai。"),
        (.medicineAndHealth, "读取 ct.csv、./h_p_v.txt 和 /tmp/布洛风.txt。"),
        (.lawAndGovernment, "读取 /tmp/民发典.txt 和 ./个人信息保护法.md。"),
        (.financeAndBusiness, "读取 etf.csv、/tmp/g_d_p.txt 和 https://example.com/a-shares。"),
        (.educationAndResearch, "读取 /tmp/6-G.txt 和 ./人工智能-X.md。"),
        (.filmAndMusic, "读取 taylor-swift.mp3、/tmp/731.txt 和 https://example.com/7.31。"),
        (.gamesAndAnime, "读取 playstation.log 和 ./c_s_2.txt。"),
        (.travelAndTransport, "打开 c919.csv、/tmp/铁路12306.txt 和 https://booking.com/trip。"),
        (.dailyLife, "读取 citywalk.md、/tmp/低gi.csv 和 https://example.com/小程序。"),
    ])
    func preservesLiteralNamesWithinEveryLexicon(_ lexicon: VoiceLexicon, _ transcript: String) {
        #expect(VoiceLexicon.normalizeTranscript(transcript, for: [lexicon]) == transcript)
    }

    @Test(arguments: [
        (VoiceLexicon.filmAndMusic, "票价是 7.31 元，日期记成 7-31。"),
        (.filmAndMusic, "第731页记录7.31、7-31和73.1，不能混同。"),
        (.travelAndTransport, "标识 C9.19、C9-19、C9/19 和 C 9.19 按原样记录。"),
        (.travelAndTransport, "备注为铁路1.2306，不是铁路12306。"),
        (.medicineAndHealth, "记录“0.5、12.5、GLP-1”，按字面保存。"),
        (.financeAndBusiness, "持仓比例3.5%，收益率0.731，编号ETF123。"),
        (.educationAndResearch, "记录6G、6.0和六G，不要混淆。"),
        (.dailyLife, "账单是7.31元，低GI餐单存于 menu.731.txt。"),
    ])
    func preservesNumericSeparatorsOutsideModelVocabulary(_ lexicon: VoiceLexicon, _ transcript: String) {
        #expect(VoiceLexicon.normalizeTranscript(transcript, for: [lexicon]) == transcript)
    }

    @Test(arguments: VoiceLexicon.allCases)
    func singleLexiconHintsKeepPersonalPriorityAndSpeechLimits(_ lexicon: VoiceLexicon) {
        let hints = VoiceLexicon.contextualTerms(for: [lexicon], customTerms: ["NovaDesk", "novadesk"])
        #expect(hints.first == "NovaDesk")
        #expect(hints.count > 1 && hints.count <= 100)
        #expect(Set(hints.map { $0.lowercased() }).count == hints.count)
        #expect(hints.allSatisfy { $0.unicodeScalars.count <= 80 })
        #expect(hints.dropFirst().allSatisfy(lexicon.terms.contains))
    }

    @Test(arguments: VoiceLexicon.allCases)
    func emptyAndUnrelatedUtterancesDoNotInjectDictionaryWords(_ lexicon: VoiceLexicon) {
        for transcript in ["", "   ", "\n", "明天在这里见面。"] {
            #expect(VoiceLexicon.normalizeTranscript(transcript, for: [lexicon]) == transcript)
            #expect(VoiceLexicon.postProcessingTerms(in: transcript, for: [lexicon]).isEmpty)
        }
    }

    @Test(arguments: [
        (["NovaDesk", "RSP-VSR"], "用 nova desk 整理 rsp vsr。", "用 NovaDesk 整理 RSP-VSR。"),
        (["宇航"], "请让宇航审核。", "请让宇航审核。"),
        (["gemma"], "Gemma 模型", "gemma 模型"),
        (["C919"], "C9.19 是编号。", "C9.19 是编号。"),
        (["a+b"], "A+B 项目", "a+b 项目"),
    ])
    func customOnlyVocabularyKeepsUserSpellingWithoutInventingCorrections(
        _ customTerms: [String],
        _ transcript: String,
        _ expected: String
    ) {
        #expect(VoiceLexicon.normalizeTranscript(transcript, for: [], customTerms: customTerms) == expected)
        #expect(VoiceLexicon.contextualTerms(for: [], customTerms: customTerms) == customTerms)
        let references = VoiceLexicon.postProcessingTerms(in: transcript, for: [], customTerms: customTerms)
        #expect(Set(references) == Set(customTerms))
    }

    @Test(arguments: ["", "gemma 与 qwen3.5", "床前明月广，名字是张维。", "价格7.31，文件在 /tmp/ct.csv。"])
    func disabledDictionariesLeaveAllUtterancesAlone(_ transcript: String) {
        #expect(VoiceLexicon.normalizeTranscript(transcript, for: []) == transcript)
        #expect(VoiceLexicon.postProcessingTerms(in: transcript, for: []).isEmpty)
        #expect(VoiceLexicon.contextualTerms(for: []).isEmpty)
    }

    @Test
    func combinedDictionariesKeepNamesNumbersAndPersonalSpellings() {
        let all = Set(VoiceLexicon.allCases)
        let transcript = "nova desk 配合 gemma 和 chat gpt 整理 ct 报告，使用铁路 12306 买票，花了7.31元。"
        let expected = "NovaDesk 配合 gemma 和 ChatGPT 整理 CT 报告，使用铁路12306 买票，花了7.31元。"
        let personal = ["NovaDesk", "gemma"]
        #expect(VoiceLexicon.normalizeTranscript(transcript, for: all, customTerms: personal) == expected)
        let references = VoiceLexicon.postProcessingTerms(in: transcript, for: all, customTerms: personal)
        #expect(Array(references.prefix(2)) == personal)
        #expect(["ChatGPT", "CT", "铁路12306"].allSatisfy(references.contains))
        #expect(!references.contains("Gemma"))
        #expect(!references.contains("731"))
        #expect(!references.contains("玛巴洛沙韦"))
        let hints = VoiceLexicon.contextualTerms(for: all, customTerms: personal)
        #expect(hints.count == 100)
        #expect(Array(hints.prefix(2)) == personal)
        #expect(["唐诗", "YYDS", "北京", "Apple", "新冠", "民法典", "股票", "高等数学", "电影", "英雄联盟", "高铁", "外卖"]
            .allSatisfy(hints.contains))
    }
}
