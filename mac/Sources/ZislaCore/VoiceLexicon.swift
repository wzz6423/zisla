import Foundation

/// Built-in vocabulary that can improve speech recognition of common proper nouns and phrases.
public enum VoiceLexicon: String, Codable, CaseIterable, Identifiable, Sendable, Equatable, Hashable {
    case computerTerms
    case classicalPoetry
    case internetBuzzwords
    case peopleAndPlaces
    case brandsAndProducts
    case medicineAndHealth
    case lawAndGovernment
    case financeAndBusiness
    case educationAndResearch
    case filmAndMusic
    case gamesAndAnime
    case travelAndTransport
    case dailyLife

    public var id: String { rawValue }

    public static let defaultEnabled: Set<Self> = Set(allCases)

    public var title: String {
        switch self {
        case .computerTerms: "计算机术语"
        case .classicalPoetry: "唐诗古诗"
        case .internetBuzzwords: "网络热词"
        case .peopleAndPlaces: "人名地名"
        case .brandsAndProducts: "品牌产品"
        case .medicineAndHealth: "医学健康"
        case .lawAndGovernment: "法律政务"
        case .financeAndBusiness: "财经金融"
        case .educationAndResearch: "教育科研"
        case .filmAndMusic: "影视音乐"
        case .gamesAndAnime: "游戏动漫"
        case .travelAndTransport: "出行交通"
        case .dailyLife: "生活服务"
        }
    }

    public var detail: String {
        switch self {
        case .computerTerms: "帮助识别开发、AI 和软件工程相关术语"
        case .classicalPoetry: "帮助识别诗句、篇名与常见古典人名"
        case .internetBuzzwords: "帮助识别常见网络表达和缩写"
        case .peopleAndPlaces: "帮助识别常见人物、城市与地名"
        case .brandsAndProducts: "帮助识别品牌、产品和应用名称"
        case .medicineAndHealth: "帮助识别疾病、药品与医疗术语"
        case .lawAndGovernment: "帮助识别法律法规与政务用语"
        case .financeAndBusiness: "帮助识别金融市场与商业术语"
        case .educationAndResearch: "帮助识别学习、论文与科研术语"
        case .filmAndMusic: "帮助识别影视作品、音乐人与平台"
        case .gamesAndAnime: "帮助识别游戏、动漫作品与角色"
        case .travelAndTransport: "帮助识别交通、地图与出行用语"
        case .dailyLife: "帮助识别电商、餐饮与日常服务用语"
        }
    }

    public var symbol: String {
        switch self {
        case .computerTerms: "desktopcomputer"
        case .classicalPoetry: "book.closed"
        case .internetBuzzwords: "bubble.left.and.bubble.right"
        case .peopleAndPlaces: "person.2"
        case .brandsAndProducts: "shippingbox"
        case .medicineAndHealth: "cross.case"
        case .lawAndGovernment: "building.columns"
        case .financeAndBusiness: "chart.line.uptrend.xyaxis"
        case .educationAndResearch: "graduationcap"
        case .filmAndMusic: "film"
        case .gamesAndAnime: "gamecontroller"
        case .travelAndTransport: "car"
        case .dailyLife: "house"
        }
    }

    /// Terms are used as recognition hints and typo-correction references, never as content to insert.
    public var terms: [String] {
        switch self {
        case .computerTerms:
            [
                "GitHub", "SSH", "SSH key", "ssh key", "SSH 密钥", "人工智能", "Git", "GitLab",
                "GitHub Actions", "AI", "AI Agent", "智能体", "Agentic Coding", "Vibe Coding", "MCP", "MCP Server",
                "Model Context Protocol", "工具调用", "Function Calling", "Tool Calling", "上下文窗口", "上下文工程", "子代理", "subagent",
                "AGENTS.md", "CLAUDE.md", "SKILL.md", "机器学习", "深度学习", "大语言模型", "生成式 AI", "提示词", "上下文",
                "向量数据库", "嵌入", "Transformer", "神经网络", "模型推理", "微调", "RAG", "检索增强生成",
                "API", "SDK", "CLI", "HTTP", "HTTPS", "URL", "JSON", "XML", "YAML", "SQL", "SQLite",
                "OpenAPI", "GraphQL", "gRPC", "REST API", "WebSocket", "数据库", "MySQL", "PostgreSQL", "Redis", "Docker", "Docker Compose", "Kubernetes", "Terraform",
                "Swift", "SwiftUI", "Objective-C", "Python", "JavaScript", "TypeScript", "Node.js", "React", "Vue",
                "pnpm", "Bun", "Deno", "uv", "npm", "Homebrew", "编译器", "运行时", "调试", "断点", "线程", "进程", "异步", "并发", "缓存", "前端", "后端",
                "全栈", "接口", "仓库", "分支", "提交", "合并请求", "持续集成", "macOS", "iOS", "Xcode", "AppKit",
                "Foundation", "Yarn", "Volta", "fnm", "nvm", "asdf", "Cursor", "Windsurf", "Cline", "Roo Code", "Aider", "Continue", "VS Code", "Visual Studio Code", "Zed",
                "开源", "开源项目", "开源软件", "开源代码", "开源社区", "开源模型", "开源大模型", "开源协议", "开源框架", "开源仓库", "开源工具", "开源生态", "开源许可证", "开放源代码"
            ] + Self.currentAgentEcosystemTerms + Self.supportedAIAgentTerms + Self.supportedAIProviderTerms
        case .classicalPoetry:
            [
                "唐诗", "宋词", "古诗", "古文", "李白", "杜甫", "白居易", "王维", "孟浩然", "苏轼", "李清照",
                "床前明月光", "疑是地上霜", "举头望明月", "低头思故乡", "白日依山尽", "黄河入海流", "欲穷千里目",
                "更上一层楼", "海内存知己", "天涯若比邻", "春眠不觉晓", "处处闻啼鸟", "随风潜入夜", "润物细无声",
                "会当凌绝顶", "一览众山小", "大漠孤烟直", "长河落日圆", "独在异乡为异客", "每逢佳节倍思亲",
                "桃花潭水深千尺", "不及汪伦送我情", "明月几时有", "把酒问青天", "但愿人长久", "千里共婵娟",
                "先天下之忧而忧", "后天下之乐而乐", "醉翁之意不在酒", "海上生明月", "天涯共此时", "山重水复疑无路",
                "柳暗花明又一村", "人生自古谁无死", "留取丹心照汗青", "天生我材必有用", "千金散尽还复来",
                "将进酒", "琵琶行", "春江花月夜", "木兰辞", "滕王阁序", "岳阳楼记", "水调歌头", "念奴娇·赤壁怀古", "短歌行"
            ]
        case .internetBuzzwords:
            [
                "YYDS", "yyds", "绝绝子", "破防", "破防了", "内卷", "躺平", "摆烂", "凡尔赛", "社恐", "社牛",
                "上头", "下头", "种草", "拔草", "安利", "吃瓜", "打卡", "emo", "CPU", "拿捏", "松弛感",
                "显眼包", "电子榨菜", "多巴胺", "赛博", "人机", "尊嘟假嘟", "泰酷辣", "遥遥领先", "硬控",
                "主打一个", "不明觉厉", "细思极恐", "蚌埠住了", "我真的会谢", "栓Q", "家人们", "宝藏",
                "神仙打架", "天花板", "顶流", "流量密码", "情绪价值", "狠狠地", "浅浅地", "在线等",
                "活人感", "主理人", "谷子", "村咖", "拉布布", "苏超", "票根经济", "育儿补贴", "十五五",
                "人形机器人", "杭州六小龙", "对等关税", "跨境支付通", "新大众文艺", "轻体", "敬自己一杯", "助我破鼎",
                "基础不基础", "××基础××不基础", "千百次练习只为这一刻", "如何呢又能怎", "来财", "浪浪山小妖怪",
                "人工智能+", "低空经济", "新质生产力", "Citywalk", "特种兵式旅游", "班味"
            ]
        case .peopleAndPlaces:
            [
                "北京", "上海", "广州", "深圳", "杭州", "成都", "重庆", "西安", "武汉", "南京", "苏州", "香港",
                "澳门", "台北", "天安门", "故宫", "长城", "黄山", "张伟", "王伟", "李娜", "马云", "任正非",
                "雷军", "乔布斯", "埃隆·马斯克", "诸葛亮", "司马迁", "鲁迅", "莫言", "屠呦呦", "袁隆平",
                "梁文锋", "黄仁勋", "张一鸣", "李彦宏", "周鸿祎", "王兴兴", "钟南山", "张文宏", "杨利伟", "萨姆·奥特曼",
                "新加坡", "东京", "大阪", "首尔", "纽约", "伦敦", "巴黎", "旧金山", "硅谷", "迪拜", "雄安新区",
                "粤港澳大湾区", "长三角", "成渝地区双城经济圈", "海南自由贸易港", "杭州六小龙"
            ]
        case .brandsAndProducts:
            [
                "Apple", "iPhone", "iPad", "MacBook", "AirPods", "华为", "鸿蒙", "小米", "米家", "大疆", "比亚迪",
                "特斯拉", "理想汽车", "蔚来", "小鹏", "阿里巴巴", "淘宝", "支付宝", "微信", "抖音", "小红书",
                "美团", "京东", "拼多多", "Notion", "Figma", "ChatGPT", "Claude", "Gemini", "Copilot", "DeepSeek",
                "OpenAI", "Anthropic", "xAI", "Moonshot AI", "通义千问", "豆包", "Doubao", "TRAE", "Qoder", "Z.ai", "Amazon Q",
                "DeepSeek-R1", "DeepSeek-V3", "Kimi", "Kimi K2", "腾讯元宝", "元宝", "Qwen", "文心一言", "文小言", "智谱清言",
                "讯飞星火", "夸克", "秘塔AI", "可灵AI", "即梦AI", "Suno", "Perplexity", "Midjourney", "Grok", "GitHub Copilot",
                "小米汽车", "小米SU7", "问界", "鸿蒙智行", "极氪", "零跑"
            ]
        case .medicineAndHealth:
            [
                "新冠", "流感", "过敏性鼻炎", "高血压", "糖尿病", "心电图", "核磁共振", "CT", "超声", "血常规",
                "血糖", "血脂", "维生素", "阿莫西林", "布洛芬", "对乙酰氨基酚", "奥司他韦", "二甲双胍", "青霉素",
                "抗生素", "处方药", "非处方药", "挂号", "急诊", "康复", "心理咨询", "疫苗", "免疫力", "体检",
                "甲流", "乙流", "甲型H1N1流感", "肺炎支原体", "人偏肺病毒", "呼吸道合胞病毒", "呼吸道疾病",
                "玛巴洛沙韦", "帕拉米韦", "扎那米韦", "流感疫苗", "HPV", "HPV疫苗", "带状疱疹疫苗", "GLP-1",
                "司美格鲁肽", "替尔泊肽", "体重管理", "阿尔茨海默病", "抗原检测", "核酸检测", "互联网医院", "远程医疗"
            ]
        case .lawAndGovernment:
            [
                "民法典", "刑法", "劳动法", "知识产权", "著作权", "商标权", "专利权", "合同", "违约", "诉讼",
                "仲裁", "证据", "法院", "检察院", "公安", "行政许可", "行政处罚", "个人信息保护法", "网络安全法",
                "数据安全法", "营业执照", "身份证", "居住证", "社保", "公积金", "电子签名", "法律援助", "律师事务所",
                "人工智能生成合成内容标识办法", "显式标识", "隐式标识", "深度合成", "生成式人工智能服务管理暂行办法",
                "算法备案", "个人信息保护合规审计", "数据出境", "跨境数据流动", "未成年人网络保护条例", "网络暴力信息治理",
                "反电信网络诈骗法", "反垄断法", "电子商务法", "电子签名法", "行政复议法", "民营经济促进法", "公司法",
                "消费者权益保护法", "平台责任", "涉企行政检查", "政务服务", "一网通办", "跨境数据"
            ]
        case .financeAndBusiness:
            [
                "股票", "基金", "债券", "期货", "期权", "ETF", "指数", "A股", "港股", "美股", "上证指数",
                "深证成指", "创业板", "科创板", "市盈率", "市净率", "分红", "股息", "利率", "通货膨胀", "GDP",
                "央行", "商业银行", "微信支付", "融资", "估值", "现金流", "资产负债表", "利润表", "现金流量表",
                "对等关税", "跨境支付通", "票根经济", "低空经济", "人工智能+", "算力", "智算中心", "算电协同", "耐心资本",
                "长期资本", "专精特新", "独角兽企业", "融资融券", "北向资金", "南向资金", "REITs", "可转债", "国债逆回购",
                "量化交易", "量化私募", "LPR", "MLF", "降准", "降息", "CPI", "PPI", "PMI", "数字人民币", "稳定币", "RWA",
                "资产证券化", "人民币国际化", "跨境支付"
            ]
        case .educationAndResearch:
            [
                "高等数学", "线性代数", "概率论", "物理", "化学", "生物", "语文", "英语", "考研", "高考", "中考",
                "论文", "摘要", "参考文献", "实验室", "学术", "期刊", "开题报告", "答辩", "自然语言处理", "计算机视觉",
                "量子计算", "基因组", "诺贝尔奖", "中国科学院", "清华大学", "北京大学", "知识图谱", "数据分析",
                "人工智能+教育", "教育大模型", "多模态语料库", "高质量数据集", "算法安全评估", "能力图谱", "智能学伴",
                "数字导师", "云端学校", "未来学习中心", "人工智能+X", "教育专网", "教育行业云", "多模态", "扩散模型",
                "强化学习", "联邦学习", "知识蒸馏", "因果推断", "合成数据", "基准测试", "预训练", "后训练", "推理时计算",
                "世界模型", "具身智能", "脑机接口", "生物制造", "量子科技", "第六代移动通信", "6G", "卫星互联网", "算力网络",
                "大科学装置", "交叉学科", "拔尖创新人才", "双一流"
            ]
        case .filmAndMusic:
            [
                "电影", "电视剧", "综艺", "纪录片", "动画", "导演", "编剧", "演员", "奥斯卡", "金鸡奖", "戛纳电影节",
                "周杰伦", "林俊杰", "邓紫棋", "五月天", "Taylor Swift", "Spotify", "网易云音乐", "QQ音乐", "漫威", "DC",
                "哈利·波特", "星球大战", "流浪地球", "三体", "甄嬛传", "红楼梦", "音乐节", "演唱会",
                "哪吒之魔童闹海", "哪吒2", "唐探1900", "疯狂动物城2", "南京照相馆", "731", "浪浪山小妖怪",
                "熊出没·重启未来", "罗小黑战记2", "聊斋：兰若寺", "长安的荔枝", "捕风追影", "戏台", "阿凡达3",
                "中国奇谭", "庆余年", "繁花", "狂飙", "周深", "陈奕迅", "毛不易", "告五人", "单依纯", "BLACKPINK",
                "Apple Music", "YouTube Music", "TME"
            ]
        case .gamesAndAnime:
            [
                "英雄联盟", "王者荣耀", "原神", "崩坏：星穹铁道", "绝区零", "和平精英", "蛋仔派对", "Minecraft", "我的世界",
                "Steam", "任天堂", "PlayStation", "Xbox", "Switch", "宝可梦", "塞尔达传说", "最终幻想", "魔兽世界",
                "炉石传说", "Dota 2", "CS2", "黑神话：悟空", "哆啦A梦", "名侦探柯南", "海贼王", "火影忍者", "鬼灭之刃",
                "进击的巨人", "三角洲行动", "燕云十六声", "鸣潮", "无限暖暖", "逆水寒", "PUBG", "Roblox", "Fortnite",
                "抽卡", "卡池", "保底", "肉鸽", "开放世界", "大逃杀", "赛季", "排位", "副本", "联机", "声骸", "共鸣者"
            ]
        case .travelAndTransport:
            [
                "高铁", "动车", "地铁", "公交", "出租车", "网约车", "飞机", "航班", "机场", "火车站", "导航", "高德地图",
                "百度地图", "滴滴出行", "新能源", "电动车", "充电桩", "自动驾驶", "驾驶证", "高速公路", "服务区", "ETC",
                "停车场", "共享单车", "绿灯", "红绿灯", "过路费", "旅行社", "签证",
                "240小时过境免签", "过境免签", "免签入境", "联程客票", "开放口岸", "电子登机牌", "电子签证", "C919",
                "大兴国际机场", "虹桥国际机场", "航旅纵横", "铁路12306", "城际铁路", "市域铁路", "机场快线", "eVTOL",
                "低空经济", "无人机", "智能网联汽车", "高德打车", "滴滴打车", "顺风车", "飞猪", "Airbnb", "Booking.com"
            ]
        case .dailyLife:
            [
                "外卖", "快递", "菜鸟", "顺丰", "圆通", "中通", "饿了么", "直播", "短视频", "健身", "瑜伽", "咖啡",
                "奶茶", "火锅", "露营", "旅游", "酒店", "民宿", "携程", "去哪儿", "大众点评", "家政", "装修", "家居",
                "洗衣店", "便利店", "超市", "会员卡", "优惠券", "售后",
                "村咖", "拉布布", "票根经济", "育儿补贴", "以旧换新", "国补", "即时零售", "社区团购", "直播带货", "探店",
                "团购", "小程序", "Citywalk", "特种兵式旅游", "轻体", "新大众文艺", "谷子", "主理人", "活人感", "预制菜",
                "轻食", "无糖", "低GI", "胖东来", "山姆会员店", "盒马", "瑞幸咖啡", "喜茶", "奈雪的茶", "蜜雪冰城",
                "叮咚买菜", "朴朴", "闪送", "淘宝闪购", "美团外卖", "京东物流", "家装厨卫焕新", "消费券"
            ]
        }
    }

    private static let currentAgentEcosystemTerms: [String] = [
        "Amazon Q Developer", "Amazon Q Developer CLI", "OpenHands", "Goose", "Browser Use", "LangGraph", "AutoGen", "CrewAI",
        "PydanticAI", "Semantic Kernel", "Google ADK", "OpenAI Agents SDK", "Agent Harness", "多智能体", "Multi-Agent",
        "A2A", "A2A Protocol", "Agent-to-Agent", "Agent Card", "MCP Registry", "Streamable HTTP", "JSON-RPC", "OAuth 2.1", "Responses API",
        "OpenAI Compatible", "Anthropic Messages", "Gemini Generate Content", "New API", "One API"
    ]

    /// When adding a supported Agent CLI, this exhaustive switch requires its recognition terms to be added here as well.
    private static let supportedAIAgentTerms: [String] = AgentCLIKind.allCases.flatMap { kind in
        switch kind {
        case .claude:
            ["Claude Code", "Claude"]
        case .codex:
            ["Codex", "OpenAI Codex", "Codex CLI", "Codex App", "Codex Web"]
        case .gemini:
            ["Gemini CLI", "Gemini Code Assist", "GEMINI.md", "Gemini"]
        case .grok:
            ["Grok CLI", "Grok"]
        case .opencode:
            ["OpenCode", "OpenCode CLI"]
        case .kimi:
            ["Kimi Code", "Kimi"]
        case .qwen:
            ["Qwen Code", "通义千问", "Qwen"]
        case .qoder:
            ["Qoder CLI", "Qoder Work", "Qoder"]
        case .glm:
            ["GLM Coding", "GLM"]
        case .copilot:
            ["GitHub Copilot", "GitHub Copilot CLI", "Copilot coding agent", "Copilot"]
        case .dsh:
            ["DeepSeek Harness", "DeepSeek", "dsh", "Cordis"]
        case .pi:
            ["Pi Coding Agent", "Pi"]
        }
    }

    /// When adding an AI provider supported by the app, this exhaustive switch requires its dedicated terms to be added here as well.
    private static let supportedAIProviderTerms: [String] = AIProvider.allCases.flatMap { provider -> [String] in
        switch provider {
        case .claude, .codex, .gemini, .grok, .copilot, .opencode, .pi:
            []
        case .gpt:
            ["GPT", "OpenAI", "ChatGPT"]
        case .kimi:
            ["Moonshot AI"]
        case .qwen:
            []
        case .coder:
            ["Qwen Coder"]
        case .zcode:
            ["ZCode", "Z.ai", "Z.ai Coding"]
        case .trae:
            ["TRAE", "TRAE Solo"]
        case .harness:
            ["Harnext", "Harnext CLI", "WorkBuddy"]
        case .doubao:
            ["豆包", "Doubao"]
        }
    }

    public static func terms(for enabled: Set<Self>) -> [String] {
        var seen = Set<String>()
        return allCases
            .filter { enabled.contains($0) }
            .flatMap(\.terms)
            .filter { seen.insert($0).inserted }
    }

    /// Return the complete terms from all enabled lexicons; the app layer does not quota, sort, or weight terms by lexicon or term order.
    public static func contextualTerms(for enabled: Set<Self>) -> [String] {
        terms(for: enabled)
    }

    /// Normalize term variants already emitted by ASR to the canonical spelling from enabled lexicons.
    /// Also correct deterministic phonetic variants when the lexicon context is explicit; never invent terms.
    /// `contextualTranscript` preserves the original sentence context after AI post-processing and is not written to the output.
    public static func normalizeTranscript(
        _ transcript: String,
        for enabled: Set<Self>,
        contextualTranscript: String? = nil
    ) -> String {
        let enabledTerms = terms(for: enabled)
        guard !transcript.isEmpty, !enabledTerms.isEmpty else { return transcript }

        var normalized = transcript
        for candidate in normalizationCandidates(for: enabledTerms) {
            guard let expression = try? NSRegularExpression(
                pattern: candidate.pattern,
                options: [.caseInsensitive]
            ) else { continue }

            let matches = expression.matches(
                in: normalized,
                range: NSRange(location: 0, length: (normalized as NSString).length)
            )
            for match in matches.reversed() {
                normalized = (normalized as NSString).replacingCharacters(
                    in: match.range,
                    with: candidate.term
                )
            }
        }
        return normalizeContextualComputerAliases(
            normalized,
            enabled: enabled,
            contextualTranscript: contextualTranscript
        )
    }

    private struct NormalizationCandidate {
        let term: String
        let pattern: String
    }

    private static func normalizationCandidates(for terms: [String]) -> [NormalizationCandidate] {
        var seen = Set<String>()
        return terms.compactMap { term in
            let key = compactMatchingKey(for: term)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return NormalizationCandidate(term: term, pattern: normalizationPattern(for: term))
        }
        .sorted {
            let leftLength = $0.term.unicodeScalars.count
            let rightLength = $1.term.unicodeScalars.count
            if leftLength != rightLength { return leftLength > rightLength }
            return $0.term < $1.term
        }
    }

    private static func compactMatchingKey(for term: String) -> String {
        String(String.UnicodeScalarView(compactMatchingScalars(for: term))).lowercased()
    }

    private static func compactMatchingScalars(for text: String) -> [Unicode.Scalar] {
        text.unicodeScalars.filter { $0.properties.isAlphabetic || $0.properties.numericType != nil }
    }

    private static func containsCompactTerm(_ term: String, in text: String) -> Bool {
        let source = compactMatchingScalars(for: text)
        let target = compactMatchingScalars(for: term)
        guard !source.isEmpty, !target.isEmpty, target.count <= source.count else { return false }

        func normalized(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
            guard scalar.value >= 65, scalar.value <= 90 else { return scalar }
            return Unicode.Scalar(scalar.value + 32)!
        }

        for start in 0...(source.count - target.count) {
            let end = start + target.count
            guard zip(source[start..<end], target).allSatisfy({ normalized($0) == normalized($1) }) else {
                continue
            }
            let startsInsideASCIIWord = start > 0 && isASCIIWordScalar(source[start - 1]) && isASCIIWordScalar(target[0])
            let endsInsideASCIIWord = end < source.count && isASCIIWordScalar(source[end]) && isASCIIWordScalar(target[target.count - 1])
            if !startsInsideASCIIWord && !endsInsideASCIIWord { return true }
        }
        return false
    }

    private static func normalizationPattern(for term: String) -> String {
        let matchingKey = compactMatchingKey(for: term)
        if matchingKey == "sshkey" {
            return #"(?<![A-Za-z0-9])s[\s\p{P}\p{S}]*s?[\s\p{P}\p{S}]*h[\s\p{P}\p{S}]*(?:key|k|密钥|密匙)(?![A-Za-z0-9])"#
        }
        if matchingKey == "github" {
            return #"(?<![A-Za-z0-9])git[\s\p{P}\p{S}]*hub(?![A-Za-z0-9])"#
        }

        var pieces: [String] = []
        let scalars = Array(term.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if index > 0,
               !isTermSeparator(scalars[index - 1]),
               isASCIIWordScalar(scalars[index - 1]) != isASCIIWordScalar(scalar) {
                pieces.append(#"[\s\p{P}\p{S}]*"#)
            }
            if isTermSeparator(scalar) {
                while index < scalars.count, isTermSeparator(scalars[index]) {
                    index += 1
                }
                pieces.append(#"[\s\p{P}\p{S}]*"#)
                continue
            }

            if isASCIIWordScalar(scalar) {
                var token = ""
                while index < scalars.count, isASCIIWordScalar(scalars[index]) {
                    token.append(Character(String(scalars[index])))
                    index += 1
                }
                pieces.append(asciiTokenPattern(token))
                continue
            }

            pieces.append(NSRegularExpression.escapedPattern(for: String(scalar)))
            index += 1
        }

        let body = pieces.joined()
        let hasASCIIWord = term.unicodeScalars.contains(where: isASCIIWordScalar)
        return hasASCIIWord ? "(?<![A-Za-z0-9])\(body)(?![A-Za-z0-9])" : body
    }

    private static func normalizeContextualGitHubAlias(
        _ transcript: String,
        enabled: Set<Self>,
        contextualTranscript: String?
    ) -> String {
        guard enabled.contains(.computerTerms) else { return transcript }

        // Ordinary "get up" must remain unchanged without lexicon context, so term correction does not alter everyday speech.
        let matches = githubAliasRanges(in: transcript)
        var normalized = transcript
        let contextualMatches = contextualTranscript.map(githubAliasRanges(in:)) ?? []
        for index in matches.indices.reversed() {
            let match = matches[index]
            let current = normalized as NSString
            let localContext = hasComputerLexiconContext(in: current, excluding: match)
            let originalContext: Bool
            if let contextualTranscript, contextualMatches.indices.contains(index) {
                originalContext = hasComputerLexiconContext(
                    in: contextualTranscript as NSString,
                    excluding: contextualMatches[index]
                )
            } else {
                originalContext = false
            }
            guard localContext || originalContext else { continue }
            normalized = current.replacingCharacters(in: match, with: "GitHub")
        }
        return normalized
    }

    private static func githubAliasRanges(in transcript: String) -> [NSRange] {
        let scalars = Array(transcript.unicodeScalars)
        var utf16Offsets = Array(repeating: 0, count: scalars.count + 1)
        for index in scalars.indices {
            utf16Offsets[index + 1] = utf16Offsets[index] + String(scalars[index]).utf16.count
        }

        func readWord(from index: inout Int) -> String {
            let start = index
            while index < scalars.count, isASCIIWordScalar(scalars[index]) { index += 1 }
            return String(String.UnicodeScalarView(scalars[start..<index]))
        }

        var matches: [NSRange] = []
        var index = 0
        while index < scalars.count {
            guard isASCIIWordScalar(scalars[index]) else {
                index += 1
                continue
            }

            let start = index
            let firstWord = readWord(from: &index).lowercased()
            if firstWord == "github" {
                matches.append(NSRange(
                    location: utf16Offsets[start],
                    length: utf16Offsets[index] - utf16Offsets[start]
                ))
                continue
            }
            guard firstWord == "git" || firstWord == "get" else { continue }

            let separatorStart = index
            while index < scalars.count, isTermSeparator(scalars[index]) { index += 1 }
            guard index > separatorStart, index < scalars.count, isASCIIWordScalar(scalars[index]) else { continue }

            let secondWord = readWord(from: &index).lowercased()
            guard secondWord == "hub" || secondWord == "up" else { continue }
            matches.append(NSRange(
                location: utf16Offsets[start],
                length: utf16Offsets[index] - utf16Offsets[start]
            ))
        }
        return matches
    }

    private static func normalizeContextualComputerAliases(
        _ transcript: String,
        enabled: Set<Self>,
        contextualTranscript: String?
    ) -> String {
        normalizeContextualOpenSourceAlias(
            normalizeContextualGitHubAlias(
                transcript,
                enabled: enabled,
                contextualTranscript: contextualTranscript
            ),
            enabled: enabled
        )
    }

    private static func normalizeContextualOpenSourceAlias(
        _ transcript: String,
        enabled: Set<Self>
    ) -> String {
        guard enabled.contains(.computerTerms) else { return transcript }

        let source = transcript as NSString
        var matches: [NSRange] = []
        var searchLocation = 0
        while searchLocation < source.length {
            let searchRange = NSRange(location: searchLocation, length: source.length - searchLocation)
            let match = source.range(of: "开元", options: [], range: searchRange)
            guard match.location != NSNotFound else { break }
            matches.append(match)
            searchLocation = NSMaxRange(match)
        }
        var normalized = transcript
        for match in matches.reversed() {
            let current = normalized as NSString
            guard hasOpenSourceLexiconContext(in: current, excluding: match) else { continue }
            normalized = current.replacingCharacters(in: match, with: "开源")
        }
        return normalized
    }

    private static func hasOpenSourceLexiconContext(
        in transcript: NSString,
        excluding aliasRange: NSRange
    ) -> Bool {
        let sentence = sentenceRange(containing: aliasRange, in: transcript)
        let sentenceText = transcript.substring(with: sentence) as NSString
        let relativeAliasRange = NSRange(
            location: aliasRange.location - sentence.location,
            length: aliasRange.length
        )
        let maskedSentence = sentenceText.replacingCharacters(
            in: relativeAliasRange,
            with: String(repeating: " ", count: aliasRange.length)
        ) as NSString
        let windowStart = max(0, relativeAliasRange.location - 12)
        let windowEnd = min(maskedSentence.length, NSMaxRange(relativeAliasRange) + 12)
        let windowRange = NSRange(location: windowStart, length: windowEnd - windowStart)
        let nearbyOriginal = sentenceText.substring(with: windowRange)
        let historicalMarkers = ["年间", "年号", "元年", "大道", "街道", "路", "寺", "盛世", "通宝"]
        if historicalMarkers.contains(where: { nearbyOriginal.contains($0) }) {
            return false
        }
        let contextTerms = [
            "项目", "软件", "代码", "源码", "代码库", "社区", "模型", "大模型", "协议", "框架",
            "仓库", "工具", "平台", "生态", "许可证", "许可"
        ]
        let nearbyMasked = maskedSentence.substring(with: windowRange)
        if contextTerms.contains(where: { nearbyMasked.contains($0) }) {
            return true
        }

        return hasComputerLexiconContext(in: transcript, excluding: aliasRange)
    }

    private static func hasComputerLexiconContext(
        in transcript: NSString,
        excluding aliasRange: NSRange
    ) -> Bool {
        let sentence = sentenceRange(containing: aliasRange, in: transcript)
        let sentenceText = transcript.substring(with: sentence) as NSString
        let relativeAliasRange = NSRange(
            location: aliasRange.location - sentence.location,
            length: aliasRange.length
        )
        let maskedSentence = sentenceText.replacingCharacters(
            in: relativeAliasRange,
            with: String(repeating: " ", count: aliasRange.length)
        )

        // These collaboration abbreviations may not yet be in the user's custom lexicon, but they are sufficient to establish GitHub context.
        let collaborationAliases = ["PR", "MR", "pull request", "merge request"]
        if collaborationAliases.contains(where: { containsCompactTerm($0, in: maskedSentence) }) {
            return true
        }

        return VoiceLexicon.computerTerms.terms
            .filter { compactMatchingKey(for: $0) != "github" }
            .contains { containsCompactTerm($0, in: maskedSentence) }
    }

    private static func sentenceRange(containing range: NSRange, in transcript: NSString) -> NSRange {
        var start = range.location
        while start > 0, !isSentenceBoundary(transcript.character(at: start - 1)) {
            start -= 1
        }

        var end = NSMaxRange(range)
        while end < transcript.length, !isSentenceBoundary(transcript.character(at: end)) {
            end += 1
        }
        return NSRange(location: start, length: end - start)
    }

    private static func isSentenceBoundary(_ scalar: unichar) -> Bool {
        switch scalar {
        case 10, 13, 33, 46, 63, 59, 12290, 65281, 65307, 65311:
            true
        default:
            false
        }
    }

    private static func isASCIIWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            true
        default:
            false
        }
    }

    private static func isTermSeparator(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator,
             .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            true
        default:
            false
        }
    }

    private static func asciiTokenPattern(_ token: String) -> String {
        let scalars = Array(token.unicodeScalars)
        let isAcronym = scalars.count > 1 && scalars.allSatisfy { scalar in
            (65...90).contains(scalar.value) || (48...57).contains(scalar.value)
        }
        var result = ""
        for (offset, scalar) in scalars.enumerated() {
            if offset > 0 {
                let previous = scalars[offset - 1].value
                let current = scalar.value
                if isAcronym || (65...90).contains(current) && (97...122).contains(previous) {
                    result += #"[\s\p{P}\p{S}]*"#
                }
            }
            result += NSRegularExpression.escapedPattern(for: String(scalar))
        }
        return result
    }
}
