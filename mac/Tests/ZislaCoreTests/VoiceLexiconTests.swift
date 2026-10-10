import Foundation
import Testing
@testable import ZislaCore

struct VoiceLexiconTests {
    @Test(arguments: [
        ("再给他上创建一个rap，然后unite这个rap，然后提交推送到远端并开个daft的PR", "再给他上创建一个rap，然后unite这个rap，然后提交推送到远端并开个draft的PR"),
        ("在仓库执行 git iniy。", "在仓库执行 git init。"),
        ("提交分支前打开 drafft PR。", "提交分支前打开 draft PR。"),
        ("仓库需要一个 draf 的 PR。", "仓库需要一个 draft 的 PR。"),
        ("仓库里新建 drfat PR。", "仓库里新建 draft PR。"),
        ("提交前准备 pull reqeust。", "提交前准备 pull request。"),
        ("请在仓库执行 git commiy，再执行 git push。", "请在仓库执行 git commit，再执行 git push。"),
        ("不要提交 3 次，仓库只开 1 个 daft 的 PR，版本仍是 3.5。", "不要提交 3 次，仓库只开 1 个 draft 的 PR，版本仍是 3.5。"),
        ("Heading \ndaft PR 提交到仓库。", "Heading \ndraft PR 提交到仓库。"),
    ])
    func correctsOneEditOnlyInAnchoredDictionaryPhrases(_ input: String, _ expected: String) {
        let output = VoiceLexicon.normalizeTranscript(input, for: [.computerTerms])
        #expect(output == expected)
        #expect(VoiceLexicon.normalizeTranscript(output, for: [.computerTerms]) == output)
    }

    @Test(arguments: [
        "I enjoy rap and we unite for a good cause.",
        "GitHub 的音乐项目里记录 rap，we unite through music。",
        "a daft PR campaign",
        "GitHub 的市场团队评价这是一场 daft PR campaign。",
        "GitHub 仓库讨论这个 daft PR campaign 的文案。",
        "GitHub 仓库里写 please open daft PR now。",
        "仓库里的 daft clown 不需要修改。",
        "仓库里的 draff pro 没有完整搭配。",
        "仓库里只有 daf PR。",
        "我在仓库整理 doft PR。",
        "daft PR。仓库在后一句。",
        "GitHub 仓库里的 daft，PR 需要写说明。",
        "GitHub 仓库标识 daft2 PR 和 v2daft PR 不能改。",
        "今天只做三个是，名字叫再给他。",
        "I get up and write a draft.",
        "I get up and read about repo and init.",
    ])
    func fuzzySpellingKeepsOrdinaryWordsAndInsufficientEvidence(_ input: String) {
        #expect(VoiceLexicon.normalizeTranscript(input, for: [.computerTerms]) == input)
    }

    @Test(arguments: [
        "仓库里保留 `daft PR`、\"git iniy\" 和 “pull reqeust”。",
        "仓库里原样保留 'daft PR'、‘git iniy’ 和「pull reqeust」。",
        "仓库里的 ```\ngit iniy\ndaft PR\n``` 按原样保留。",
        "仓库里这个未闭合代码片段 `daft PR",
        "仓库里的 https://example.com/daft/PR?q=unite 和 /tmp/daft/PR 不修改。",
        "仓库里的 daft@example.com 和 ./daft PR.txt 不修改。",
    ])
    func fuzzySpellingPreservesQuotedAndLiteralText(_ input: String) {
        #expect(VoiceLexicon.normalizeTranscript(input, for: [.computerTerms]) == input)
    }

    @Test
    func fuzzySpellingHonorsPersonalWordsAndRejectsTiedPhrases() {
        for custom in [["daft"], ["daft PR"]] {
            let input = "提交仓库，开 daft PR。"
            #expect(VoiceLexicon.normalizeTranscript(input, for: [.computerTerms], customTerms: custom) == input)
        }
        #expect(VoiceLexicon.normalizeTranscript(
            "提交仓库，开 daft PR。", for: [.computerTerms], customTerms: ["DraFt"]
        ) == "提交仓库，开 DraFt PR。")
        #expect(VoiceLexicon.normalizeTranscript(
            "仓库需要一个 graft PR。", for: [.computerTerms], customTerms: ["craft PR"]
        ) == "仓库需要一个 graft PR。")
        #expect(VoiceLexicon.normalizeTranscript(
            "仓库需要一个 draft PR。", for: [.computerTerms], customTerms: ["craft PR"]
        ) == "仓库需要一个 draft PR。")
    }

    @Test
    func fuzzyReferencesRecallSoundAlikeWordsWithoutReplacingThem() {
        let input = "再给他上创建一个rap，然后unite这个rap，然后提交推送到远端并开个daft的PR"
        let references = VoiceLexicon.postProcessingTerms(in: input, for: [.computerTerms])
        #expect(references.contains("repo"))
        #expect(references.contains("init"))
        #expect(references.contains("draft"))
        if let repoIndex = references.firstIndex(of: "repo"), let ragIndex = references.firstIndex(of: "RAG") {
            #expect(repoIndex < ragIndex)
        }
        #expect(!VoiceLexicon.postProcessingTerms(
            in: "I enjoy rap and we unite for a good cause.", for: [.computerTerms]
        ).contains("repo"))
        #expect(!VoiceLexicon.postProcessingTerms(
            in: input, for: [.computerTerms], customTerms: ["rap"]
        ).contains("repo"))
        #expect(VoiceLexicon.postProcessingTerms(
            in: "仓库里原样引用 `rap unite`。", for: [.computerTerms]
        ).allSatisfy { !["repo", "init"].contains($0) })
    }

    @Test
    func fuzzyCorrectionsRespectLexiconSwitchesAndReferenceBudgets() {
        let input = "仓库里创建 rap，unite 后开 daft 的 PR。"
        for enabled: Set<VoiceLexicon> in [[], [.brandsAndProducts], [.filmAndMusic]] {
            #expect(VoiceLexicon.normalizeTranscript(input, for: enabled) == input)
            let references = VoiceLexicon.postProcessingTerms(in: input, for: enabled)
            #expect(references.allSatisfy { !["repo", "init", "draft"].contains($0) })
        }
        let custom = (0..<100).map { "PersonalWord\($0)" }
        let references = VoiceLexicon.postProcessingTerms(
            in: input + " " + custom.joined(separator: " "), for: [.computerTerms], customTerms: custom
        )
        #expect(references.count <= 48)
        #expect(references.reduce(0) { $0 + $1.unicodeScalars.count } <= 1_024)
        #expect(references.first == custom.first)
    }

    @Test
    func sharedMatchersPreservePerCallVocabularyAndPersonalPatterns() async {
        let configurations: [(Set<VoiceLexicon>, [String], String)] = [
            ([.computerTerms], [], "用 GPT 和 Gemma。"),
            ([.computerTerms], ["gpt", "gemma"], "用 g p t 和 gemma。"),
            ([], ["GPT", "gEmMa"], "用 GPT 和 gEmMa。"),
            ([], [], "用 g p t 和 gemma。"),
        ]
        await withTaskGroup(of: Void.self) { group in
            for (enabled, custom, expected) in configurations {
                group.addTask {
                    let input = "用 g p t 和 gemma。"
                    #expect(VoiceLexicon.normalizeTranscript(input, for: enabled, customTerms: custom) == expected)
                    _ = VoiceLexicon.postProcessingTerms(in: input, for: enabled, customTerms: custom)
                    #expect(VoiceLexicon.normalizeTranscript(input, for: enabled, customTerms: custom) == expected)
                }
            }
        }
    }

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

struct VoiceLexiconCacheTests {
    @Test
    func cacheReusesCandidatesAndEvictsTheLeastRecentlyUsedExpression() throws {
        let cache = VoiceLexicon.NormalizationCandidateCache()
        weak var first: NSRegularExpression?
        weak var second: NSRegularExpression?
        autoreleasepool {
            first = cache.candidate(for: "Cache0").expression
            second = cache.candidate(for: "Cache1").expression
        }
        #expect(first != nil)
        #expect(second != nil)
        for index in 2..<2_048 {
            _ = cache.candidate(for: "Cache\(index)")
        }
        let touched = try #require(cache.candidate(for: "Cache0").expression)
        #expect(touched === first)
        let previousBytes = cache.retainedResources.textBytes
        let removedBytes = "Cache1".utf8.count * 3 + (second?.pattern.utf8.count ?? 0)
        let inserted = cache.candidate(for: "Cache2048")
        let insertedBytes = inserted.term.utf8.count * 3 + (inserted.expression?.pattern.utf8.count ?? 0)
        #expect(second == nil)
        #expect(cache.retainedResources.textBytes == previousBytes - removedBytes + insertedBytes)
        #expect(cache.candidate(for: "Cache0").expression === touched)
        #expect(cache.retainedResources.count == 2_048)
        let rebuilt = cache.candidate(for: "Cache1")
        #expect(rebuilt.term == "Cache1")
        #expect(rebuilt.expression?.firstMatch(in: "cache1", range: NSRange(location: 0, length: 6)) != nil)
        #expect(cache.retainedResources.count == 2_048)
    }

    @Test
    func cacheTextBudgetReleasesLongPatternsBeforeTheEntryLimit() {
        let cache = VoiceLexicon.NormalizationCandidateCache()
        let terms = (0..<1_200).map { String(format: "%04d", $0) + String(repeating: "A", count: 76) }
        let observed = terms.map { term in
            autoreleasepool { WeakExpression(cache.candidate(for: term).expression) }
        }
        #expect(observed.first?.value == nil)
        #expect(observed.last?.value != nil)
        var retainedBytes = 0
        var retainedCount = 0
        for (term, observed) in zip(terms, observed) {
            if let expression = observed.value {
                retainedCount += 1
                retainedBytes += term.utf8.count * 3 + expression.pattern.utf8.count
            }
        }
        #expect(retainedCount > 0 && retainedCount < terms.count)
        #expect(retainedBytes <= 1_048_576)
        #expect(cache.retainedResources == (retainedCount, retainedBytes))
    }

    @Test(arguments: [
        String(repeating: "A", count: 81),
        String(repeating: "长", count: 81),
        "a" + String(repeating: "\u{0301}", count: 80),
        "Line\nBreak",
    ])
    func oversizedAndControlCharacterTermsAreReturnedWithoutBeingRetained(_ term: String) {
        let cache = VoiceLexicon.NormalizationCandidateCache()
        weak var expression: NSRegularExpression?
        autoreleasepool {
            let candidate = cache.candidate(for: term)
            #expect(Data(candidate.term.utf8) == Data(term.utf8))
            #expect(candidate.expression != nil)
            expression = candidate.expression
        }
        #expect(expression == nil)
        #expect(cache.retainedResources == (0, 0))
    }

    @Test
    func allBuiltInsAndOneHundredOnePersonalTermsFitTheWarmCache() {
        let cache = VoiceLexicon.NormalizationCandidateCache()
        let terms = VoiceLexicon.terms(for: VoiceLexicon.defaultEnabled)
            + (0..<101).map { "PersonalProduct\($0)" }
        let expressions = terms.map { cache.candidate(for: $0).expression }
        for (term, expression) in zip(terms, expressions) {
            #expect(cache.candidate(for: term).expression === expression)
        }
        #expect(cache.retainedResources.count == terms.count)
        #expect(cache.retainedResources.textBytes <= 1_048_576)
    }

    @Test
    func cacheKeysPreserveCaseSeparatorsAndUnicodeBytes() {
        let cache = VoiceLexicon.NormalizationCandidateCache()
        let terms = ["GPT", "gpt", "A+B", "A-B", "A B", "CaféDesk", "Cafe\u{0301}Desk"]
        for _ in 0..<2 {
            for term in terms {
                #expect(Data(cache.candidate(for: term).term.utf8) == Data(term.utf8))
            }
        }
        #expect(cache.retainedResources.count == terms.count)
    }

    @Test
    func cachedTermsDoNotRetainOversizedCallerStorage() throws {
        let cache = VoiceLexicon.NormalizationCandidateCache()
        var term = "PersonalProductWithReservedStorage"
        term.reserveCapacity(1_048_576)
        let callerStorage = try #require(term.utf8.withContiguousStorageIfAvailable {
            UInt(bitPattern: $0.baseAddress!)
        })
        let candidate = cache.candidate(for: term)
        let cachedStorage = try #require(candidate.term.utf8.withContiguousStorageIfAvailable {
            UInt(bitPattern: $0.baseAddress!)
        })
        withExtendedLifetime(term) {
            #expect(cachedStorage != callerStorage)
            #expect(Data(candidate.term.utf8) == Data(term.utf8))
        }
    }

    @Test
    func simultaneousMissesShareOneCompiledCandidate() async {
        let cache = VoiceLexicon.NormalizationCandidateCache()
        let candidates = await withTaskGroup(of: VoiceLexicon.NormalizationCandidate.self) { group in
            for _ in 0..<64 {
                group.addTask { cache.candidate(for: "ConcurrentProduct") }
            }
            var result: [VoiceLexicon.NormalizationCandidate] = []
            for await candidate in group { result.append(candidate) }
            return result
        }
        let first = candidates.first?.expression
        #expect(first != nil)
        #expect(candidates.allSatisfy { $0.expression === first })
        #expect(cache.retainedResources.count == 1)
    }

    @Test
    func concurrentVocabularyChurnPreservesResourceBoundsAndSpellings() async {
        let cache = VoiceLexicon.NormalizationCandidateCache()
        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    for index in 0..<512 {
                        let term = "Worker\(worker)Product\(index)"
                        #expect(cache.candidate(for: term).term == term)
                        let resources = cache.retainedResources
                        #expect(resources.count <= 2_048)
                        #expect(resources.textBytes <= 1_048_576)
                    }
                }
            }
        }
        #expect(cache.retainedResources.count == 2_048)
    }

    @Test
    func destroyingTheCacheReleasesItsCompiledExpressions() {
        weak var expression: NSRegularExpression?
        autoreleasepool {
            let cache = VoiceLexicon.NormalizationCandidateCache()
            expression = cache.candidate(for: "TemporaryProduct").expression
            #expect(expression != nil)
        }
        #expect(expression == nil)
    }

    @Test
    func normalizationKeepsExactUnicodeSpellingsAfterCacheWarmup() {
        for _ in 0..<2 {
            for term in ["CaféDesk", "Cafe\u{0301}Desk"] {
                let output = VoiceLexicon.normalizeTranscript("用 \(term.lowercased())。", for: [], customTerms: [term])
                #expect(Data(output.utf8) == Data("用 \(term)。".utf8))
            }
        }
    }

    @Test
    func evictionDoesNotTruncateCurrentVocabularyOrRetainRemovedPersonalWords() {
        let terms = (0..<2_050).map { "PersonalWord\($0)" } + ["TailWord"]
        #expect(VoiceLexicon.normalizeTranscript("tail word", for: [], customTerms: terms) == "TailWord")
        #expect(VoiceLexicon.normalizeTranscript("tail word", for: [], customTerms: ["DifferentWord"]) == "tail word")
        #expect(VoiceLexicon.normalizeTranscript("gemma", for: [.computerTerms], customTerms: ["gEmMa"]) == "gEmMa")
        #expect(VoiceLexicon.normalizeTranscript("gemma", for: []) == "gemma")
        #expect(VoiceLexicon.postProcessingTerms(in: "gemma", for: []).isEmpty)
    }

    @Test(arguments: ["Brand" + String(repeating: "a", count: 80), "Brand" + String(repeating: "\u{0301}", count: 80)])
    func oversizedPersonalWordsKeepExistingNormalizationBehavior(_ term: String) {
        let output = VoiceLexicon.normalizeTranscript(term.lowercased(), for: [], customTerms: [term])
        #expect(Data(output.utf8) == Data(term.utf8))
    }

    private final class WeakExpression {
        weak var value: NSRegularExpression?

        init(_ value: NSRegularExpression?) {
            self.value = value
        }
    }
}

extension VoiceLexiconTests {
    @Test(arguments: [
        "仓库原话是“get up 的 SSH key”，保留逐字引用。",
        "仓库原话是“Google 的伽马四模型”，保留逐字引用。",
        "仓库原话是“开元项目”，保留逐字引用。",
        "仓库里的名字是 Gemna。",
        "仓库执行 Git ini。",
        "仓库执行 gitt pull。",
        "GitHub 仓库里写 please open daft PR。",
        "仓库里的 drax PR。",
        "早上 get up，下午写 draft。",
        "早上 get up，今天只学 repo 和 init 这两个单词。",
    ])
    func conservativeCorrectionBoundariesRemainLiteral(_ input: String) {
        #expect(VoiceLexicon.normalizeTranscript(input, for: [.computerTerms]) == input)
    }

    @Test
    func approximateHintsHaveTightDistanceAndTokenBudgets() {
        #expect(!VoiceLexicon.postProcessingTerms(in: "仓库 Git", for: [.computerTerms]).contains("init"))
        #expect(VoiceLexicon.postProcessingTerms(in: "仓库 completelyunrelatedword", for: [.computerTerms]) == ["仓库"])
        #expect(!VoiceLexicon.postProcessingTerms(in: "仓库 pi", for: [.computerTerms]).contains("API"))
        #expect(!VoiceLexicon.postProcessingTerms(in: "仓库 gao", for: [.computerTerms]).contains("RAG"))
        let ranked = VoiceLexicon.postProcessingTerms(in: "仓库 azaaab", for: [.computerTerms], customTerms: ["aaaaaa", "azaaaa"])
        #expect(ranked.filter { ["aaaaaa", "azaaaa"].contains($0) }.first == "azaaaa")
        let personal = (65...90).map { "Draft" + String(Unicode.Scalar($0)!) }
        let references = VoiceLexicon.postProcessingTerms(in: "仓库 dratf", for: [.computerTerms], customTerms: personal)
        #expect(references.filter { !personal.prefix(16).contains($0) && $0 != "仓库" }.count <= 8)
        #expect(VoiceLexicon.normalizeTranscript("仓库保留 Nova aaaab。", for: [.computerTerms], customTerms: ["Nova aaaa-"]) == "仓库保留 Nova aaaab。")
    }

}

struct VoicePhraseBoundaryTests {
    @Test(arguments: [
        "仓库里的 daft\nPR 分行书写。",
        "仓库记录 Git\niniy。",
        "仓库里的 daft\r\nPR 分行书写。",
        "GitHub 仓库记录 please\u{00A0}open\u{00A0}daft\u{00A0}PR。",
        "仓库有 daft\u{00A0}PR\u{00A0}campaign。",
    ])
    func spellingCorrectionsRespectLineAndEnglishPhraseBoundaries(_ input: String) {
        #expect(VoiceLexicon.normalizeTranscript(input, for: [.computerTerms]) == input)
    }

    @Test(arguments: [
        "这些词是 draft、PR、repo，不要合并。",
        "仓库里的 draft，PR 分别表示不同内容。",
        "仓库里的 draft。PR 在下一句。",
        "仓库里的 draft\nPR 分行书写。",
        "Git，init 是两个术语。",
        "仓库说明 pull、request 的区别。",
        "仓库说明 merge；request 的区别。",
        "仓库记录 draft+PR 这个表达式。",
        "仓库名字 draftpr 保持原样。",
    ])
    func gitPhrasesPreservePunctuationAndLineBreaks(_ input: String) {
        #expect(VoiceLexicon.normalizeTranscript(input, for: [.computerTerms]) == input)
    }

    @Test(arguments: [
        ("仓库需要一个 draft pr。", "仓库需要一个 draft PR。"),
        ("仓库需要一个 draft\tpr。", "仓库需要一个 draft PR。"),
        ("仓库执行 Git INIT。", "仓库执行 git init。"),
        ("仓库执行 git   init。", "仓库执行 git init。"),
    ])
    func gitPhrasesStillNormalizeWhitespaceAndCase(_ input: String, _ expected: String) {
        #expect(VoiceLexicon.normalizeTranscript(input, for: [.computerTerms]) == expected)
    }
}

struct VoiceSpellingReferenceTests {
    @Test(arguments: [
        "GitHub 原文“rap”，另一个 rap。",
        "GitHub 原文 `rap`，另一个 rap。",
        "GitHub 路径 /tmp/rap，另一个 rap。",
    ])
    func protectedOccurrencesDoNotConsumeEditableCandidateBudget(_ input: String) {
        #expect(VoiceLexicon.postProcessingTerms(in: input, for: [.computerTerms]).contains("repo"))
    }

    @Test(arguments: [
        "GitHub 原文“rap”。",
        "GitHub 原文 `rap`。",
        "GitHub 路径 /tmp/rap。",
    ])
    func protectedOccurrencesAloneDoNotProduceCandidates(_ input: String) {
        #expect(!VoiceLexicon.postProcessingTerms(in: input, for: [.computerTerms]).contains("repo"))
    }
}

struct VoiceSpellingSourceTests {
    @Test(arguments: [
        ("GitHub 创建 rap，再 unite 这个 rap。", "GitHub 创建 repo，再 init 这个 repo。"),
        ("GitHub 创建 rap 和 rap。", "GitHub 创建 repo 和 rap。"),
        ("GitHub 创建 RAP。", "GitHub 创建 repo。"),
        ("GitHub 分享 rap 音乐。", "GitHub 分享 rap 音乐。"),
        ("GitHub 仓库", "GitHub 仓库。"),
        ("在给他创建仓库", "在 GitHub 创建仓库"),
        ("", ""),
    ])
    func acceptsCorrectionsWithConsumedSources(_ source: String, _ response: String) {
        #expect(VoiceLexicon.preservesSpellingSources(in: response, source: source, for: [.computerTerms]))
    }

    @Test(arguments: [
        ("我在 GitHub 分享 rap 音乐，歌名是 unite，票价 7.31 元。", "我在 GitHub 分享 rap 音乐，歌名是 unite，repo 7.31 元。"),
        ("GitHub 创建 rap。", "GitHub 创建 repo 和 repo。"),
        ("GitHub 记录 rap 和 rap。", "GitHub 记录 rap 和 repo 与 repo。"),
        ("GitHub 记录 rap 和 “rap”。", "GitHub 记录 rap 和 repo。"),
        ("GitHub 记录 rap。", "GitHub 记录 “rap” 和 repo。"),
        ("GitHub 记录 rap、unite。", "GitHub 记录 repo、init、init。"),
        ("GitHub 记录 “rap”、rap。", "GitHub 记录 “rap”、rap、repo。"),
        ("GitHub 用 rap，路径 /tmp/rap.md。", "GitHub 用 rap，路径 /tmp/repo.md。"),
    ])
    func rejectsHintsThatDoNotReplaceAvailableOccurrences(_ source: String, _ response: String) {
        #expect(!VoiceLexicon.preservesSpellingSources(in: response, source: source, for: [.computerTerms]))
    }

    @Test(arguments: ["cap cot", "cap cap"])
    func assignsOverlappingCandidatesWithoutReusingAnOccurrence(_ source: String) {
        #expect(VoiceLexicon.preservesSpellingSources(
            in: "cat map", source: source, for: [], customTerms: ["cat", "map"]
        ))
        #expect(!VoiceLexicon.preservesSpellingSources(
            in: "cat map map", source: source, for: [], customTerms: ["cat", "map"]
        ))
    }

    @Test
    func inactiveDictionariesDoNotRestrictTheResponse() {
        #expect(VoiceLexicon.preservesSpellingSources(in: "rap repo", source: "rap", for: []))
        #expect(VoiceLexicon.preservesSpellingSources(in: "cat map", source: "cap cot", for: [], customTerms: [" cat ", "map", "cat"]))
    }
}
