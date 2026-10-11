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
                "Gemma", "Qwen3.5", "Google", "LM Studio", "Ollama",
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
            ] + Self.localInferenceTerms + Self.currentAgentEcosystemTerms + Self.supportedAIAgentTerms + Self.supportedAIProviderTerms + Self.gitCollaborationTerms
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
                "小米汽车", "小米SU7", "问界", "鸿蒙智行", "极氪", "零跑", "Google", "Gemma", "LM Studio", "Ollama"
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

    private static let localInferenceTerms: [String] = [
        "llama.cpp", "MLX", "MLX LM", "GGUF", "QAT", "KV cache", "LoRA", "vLLM", "SGLang",
        "Hugging Face", "safetensors", "CUDA", "Metal", "量化", "混合专家", "MoE", "推测解码"
    ]

    private static let gitCollaborationTerms = [
        "repo", "init", "draft", "PR", "pull request", "merge request", "draft PR", "draft pull request",
        "git init", "git clone", "git commit", "git push", "git pull", "git rebase"
    ]

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
        case .claude, .codex, .gemini, .grok, .copilot, .zed, .opencode, .pi:
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
        case .delta:
            ["Delta", "Delta Agent"]
        case .orca:
            ["Orca", "Orca IDE"]
        case .workbuddy:
            ["WorkBuddy"]
        case .workbuddyAI:
            ["WorkBuddy AI"]
        case .harness:
            ["Harnext", "Harnext CLI"]
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

    /// Removes blank and duplicate user-entered hotwords while preserving their display order.
    public static func normalizedCustomTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms.compactMap { term -> String? in
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return trimmed
        }
        .filter { seen.insert($0).inserted }
    }

    /// Apple recommends at most 100 short phrases. Personal words precede a round-robin selection of enabled lexicons.
    public static func contextualTerms(
        for enabled: Set<Self>,
        customTerms: [String] = []
    ) -> [String] {
        var seen = Set<String>()
        var result = normalizedCustomTerms(customTerms)
            .filter { isShortHint($0) && seen.insert($0.lowercased()).inserted }
            .prefix(100).map { $0 }
        let lexicons = allCases.filter { enabled.contains($0) }.map(\.terms)
        for offset in 0..<(lexicons.map(\.count).max() ?? 0) {
            for lexicon in lexicons where offset < lexicon.count {
                guard result.count < 100 else { return result }
                let term = lexicon[offset]
                if isShortHint(term), seen.insert(term.lowercased()).inserted {
                    result.append(term)
                }
            }
        }
        return result
    }

    /// Select vocabulary for this utterance without sending unrelated built-in dictionaries to a small cleanup model.
    public static func postProcessingTerms(
        in transcript: String,
        for enabled: Set<Self>,
        customTerms: [String] = []
    ) -> [String] {
        let custom = normalizedCustomTerms(customTerms).filter(isShortHint)
        let normalized = normalizeTranscript(transcript, for: enabled, customTerms: custom)
        let range = NSRange(location: 0, length: (normalized as NSString).length)
        func isMentioned(_ term: String) -> Bool {
            let candidate = normalizationCandidateCache.candidate(for: term)
            return candidate.expression?.firstMatch(in: normalized, range: range) != nil
        }
        let matchingCustom = custom.filter(isMentioned)
        let matchingBuiltIn = terms(for: enabled).filter(isMentioned)
        let mentionedBuiltIn = Set(matchingBuiltIn)
        let relatedLexicons = enabled.filter { !mentionedBuiltIn.isDisjoint(with: $0.terms) }
        let suggestions = spellingReferences(in: normalized, terms: custom + terms(for: relatedLexicons), customTerms: custom).map(\.term)
        let remainingCustom = custom.filter { !isMentioned($0) }.prefix(16)
        var seen = Set<String>()
        var characterCount = 0
        return (matchingCustom + matchingBuiltIn + suggestions + remainingCustom).filter { term in
            guard isShortHint(term), seen.insert(compactMatchingKey(for: term)).inserted,
                  characterCount + term.unicodeScalars.count <= 1_024 else { return false }
            characterCount += term.unicodeScalars.count
            return true
        }.prefix(48).map { $0 }
    }

    private static func isShortHint(_ term: String) -> Bool {
        !term.isEmpty && term.unicodeScalars.count <= 80 && !term.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// Normalize term variants already emitted by ASR to the canonical spelling from enabled lexicons.
    /// Also correct deterministic phonetic variants when the lexicon context is explicit; never invent terms.
    /// `contextualTranscript` preserves the original sentence context after AI post-processing and is not written to the output.
    public static func normalizeTranscript(
        _ transcript: String,
        for enabled: Set<Self>,
        customTerms: [String] = [],
        contextualTranscript: String? = nil
    ) -> String {
        let custom = normalizedCustomTerms(customTerms)
        let enabledTerms = custom + terms(for: enabled)
        guard !transcript.isEmpty, !enabledTerms.isEmpty else { return transcript }

        let normalized = normalizeSpelling(transcript, terms: enabledTerms)
        let contextual = normalizeContextualComputerAliases(
            normalized,
            enabled: enabled,
            contextualTranscript: contextualTranscript
        )
        guard enabled.contains(.computerTerms) else { return normalizeSpelling(contextual, terms: custom) }
        let corrected = normalizeContextualSpelling(contextual, customTerms: custom)
        return normalizeSpelling(normalizeSpelling(corrected, terms: gitCollaborationTerms), terms: custom)
    }

    public static func literalTextCounts(in transcript: String) -> [Data: Int] {
        let source = transcript as NSString
        var counts: [Data: Int] = [:]
        for range in literalRanges(in: transcript).rangeView {
            let literal = source.substring(with: NSRange(location: range.lowerBound, length: range.count))
            // Byte keys preserve the exact Unicode spelling, not just canonically equivalent text.
            counts[Data(literal.utf8), default: 0] += 1
        }
        return counts
    }

    public static func preservesSpellingSources(
        in response: String,
        source: String,
        for enabled: Set<Self>,
        customTerms: [String] = []
    ) -> Bool {
        func counts(in text: String) -> (all: [String: Int], editable: [String: Int]) {
            let protected = normalizationProtectedRanges(in: text, customTerms: customTerms)
            var all: [String: Int] = [:]
            var editable: [String: Int] = [:]
            for token in spellingWords(in: text) {
                all[token.word, default: 0] += 1
                if !protected.intersects(integersIn: token.range.location..<NSMaxRange(token.range)) {
                    editable[token.word, default: 0] += 1
                }
            }
            return (all, editable)
        }

        let original = counts(in: source)
        let updated = counts(in: response)
        let introduced = updated.all.filter { word, count in
            count > original.all[word, default: 0]
        }
        let candidates = (normalizedCustomTerms(customTerms) + terms(for: enabled)).filter {
            introduced[$0.lowercased()] != nil
        }
        let references = spellingReferences(in: source, terms: candidates, customTerms: customTerms)
        var sources: [String: Set<String>] = [:]
        for reference in references {
            sources[reference.term.lowercased(), default: []].insert(reference.source)
        }
        var available = original.editable
        for word in available.keys {
            available[word] = min(
                original.all[word, default: 0] - updated.all[word, default: 0],
                original.editable[word, default: 0] - updated.editable[word, default: 0]
            )
        }
        var assignments: [String: [String: Int]] = [:]

        func consumeSource(for target: String, visited: inout Set<String>) -> Bool {
            guard visited.insert(target).inserted else { return false }
            for word in sources[target, default: []].sorted() {
                if available[word, default: 0] > 0 {
                    available[word, default: 0] -= 1
                    assignments[word, default: [:]][target, default: 0] += 1
                    return true
                }
                let assigned = assignments[word, default: [:]]
                for previous in assigned.keys.sorted() where assigned[previous, default: 0] > 0 {
                    if consumeSource(for: previous, visited: &visited) {
                        assignments[word, default: [:]][previous, default: 0] -= 1
                        assignments[word, default: [:]][target, default: 0] += 1
                        return true
                    }
                }
            }
            return false
        }

        // A hint can replace a misrecognition, but cannot be inserted elsewhere while that source survives.
        for target in sources.keys.sorted() {
            let addedCount = updated.all[target, default: 0] - original.all[target, default: 0]
            for _ in 0..<addedCount {
                var visited = Set<String>()
                guard consumeSource(for: target, visited: &visited) else { return false }
            }
        }
        return true
    }

    private static func normalizeSpelling(_ transcript: String, terms: [String]) -> String {
        let source = transcript as NSString
        var replacements: [(range: NSRange, term: String)] = []
        var occupied = normalizationProtectedRanges(in: transcript)
        for candidate in normalizationCandidates(for: terms) {
            guard let expression = candidate.expression else { continue }

            let matches = expression.matches(
                in: transcript,
                range: NSRange(location: 0, length: source.length)
            )
            for match in matches {
                let range = match.range.location..<NSMaxRange(match.range)
                guard !occupied.intersects(integersIn: range) else { continue }
                occupied.insert(integersIn: range)
                replacements.append((match.range, candidate.term))
            }
        }
        var normalized = transcript
        // Match the original text once so a shorter built-in term cannot rewrite a personal phrase.
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            normalized = (normalized as NSString).replacingCharacters(in: replacement.range, with: replacement.term)
        }
        return normalized
    }

    private static func literalRanges(in transcript: String) -> IndexSet {
        let range = NSRange(location: 0, length: (transcript as NSString).length)
        let links = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let paths = try! NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9])(?:~?/|\.\.?/|[\p{L}\p{N}_.-]+/)[^\s<>\"'，。！？、；（）【】]+|(?<![A-Za-z0-9_])[\p{L}\p{N}_-]+(?:\.[A-Za-z][A-Za-z0-9_-]*)+"#
        )
        let aliases = githubAliasRanges(in: transcript)
        var result = IndexSet()
        for match in links.matches(in: transcript, range: range) + paths.matches(in: transcript, range: range)
            where !aliases.contains(match.range) {
            result.insert(integersIn: match.range.location..<NSMaxRange(match.range))
        }
        return result
    }

    private static func normalizationProtectedRanges(in transcript: String, customTerms: [String] = []) -> IndexSet {
        let range = NSRange(location: 0, length: (transcript as NSString).length)
        var result = literalRanges(in: transcript)
        let expressions = [quotationExpression] + normalizationCandidates(for: customTerms).compactMap(\.expression)
        for expression in expressions {
            for match in expression.matches(in: transcript, range: range) {
                result.insert(integersIn: match.range.location..<NSMaxRange(match.range))
            }
        }
        return result
    }

    private static func spellingWords(in text: String) -> [(word: String, range: NSRange)] {
        let source = text as NSString
        return spellingWordExpression.matches(in: text, range: NSRange(location: 0, length: source.length)).map {
            (source.substring(with: $0.range).lowercased(), $0.range)
        }
    }

    private static let quotationExpression = try! NSRegularExpression(
        pattern: #"```[\s\S]*?(?:```|$)|`[^`\r\n]*(?:`|$)|"[^"]*"|'[^']*'|“[^”]*”|‘[^’]*’|「[^」]*」|『[^』]*』"#
    )
    private static let spellingWordExpression = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_])[A-Za-z]{2,32}(?![A-Za-z0-9_])"#
    )
    private static let knownComputerWords = Set(computerTerms.terms.flatMap { spellingWords(in: $0).map(\.word) })
    private static let computerSpellingPhrases = spellingPhrases(in: computerTerms.terms)

    private static func spellingPhrases(in terms: [String]) -> [[String]] {
        terms.map { $0.split(separator: " ").map(String.init) }.filter { phrase in
            phrase.count >= 2 && phrase.allSatisfy { $0.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) } }
        }
    }

    private static func spellingReferences(in transcript: String, terms: [String], customTerms: [String]) -> [(source: String, term: String)] {
        let candidates = terms.filter { term in
            (3...32).contains(term.utf8.count) && term.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) }
        }
        let knownWords = Set(candidates.map { $0.lowercased() })
        let protected = normalizationProtectedRanges(in: transcript, customTerms: customTerms)
        var seen = Set<String>()
        var result: [(source: String, term: String)] = []
        for token in spellingWords(in: transcript) {
            guard token.word.count >= 3, !knownWords.contains(token.word),
                  !protected.intersects(integersIn: token.range.location..<NSMaxRange(token.range)),
                  seen.insert(token.word).inserted else { continue }
            let consonants = token.word.filter { !"aeiouy".contains($0) }
            let matches = candidates.compactMap { term -> (term: String, phoneticPenalty: Int, distance: Int)? in
                let word = term.lowercased()
                let limit = max(word.count, token.word.count) >= 4 ? 2 : 1
                guard let distance = spellingDistance(token.word, word, limit: limit) else { return nil }
                // This coarse vowel-insensitive key only ranks bounded hints; it never authorizes a replacement.
                let penalty = consonants == word.filter { !"aeiouy".contains($0) } ? 0 : 1
                return (term, penalty, distance)
            }.sorted {
                if $0.phoneticPenalty != $1.phoneticPenalty { return $0.phoneticPenalty < $1.phoneticPenalty }
                if $0.distance != $1.distance { return $0.distance < $1.distance }
                return $0.term < $1.term
            }
            result.append(contentsOf: matches.prefix(8).map { (token.word, $0.term) })
        }
        return result
    }

    private static func normalizeContextualSpelling(_ transcript: String, customTerms: [String]) -> String {
        let source = transcript as NSString
        let words = spellingWords(in: transcript)
        let protected = normalizationProtectedRanges(in: transcript, customTerms: customTerms)
        var replacements: [NSRange: Set<String>] = [:]
        for phrase in spellingPhrases(in: customTerms) + computerSpellingPhrases where phrase.count <= words.count {
            for start in 0...(words.count - phrase.count) {
                let window = Array(words[start..<(start + phrase.count)])
                let differences = phrase.indices.filter { phrase[$0].lowercased() != window[$0].word }
                guard differences.count == 1 else { continue }
                let index = differences[0]
                let token = window[index]
                guard token.word.count >= 4, phrase[index].count >= 4, !knownComputerWords.contains(token.word),
                      !protected.intersects(integersIn: token.range.location..<NSMaxRange(token.range)),
                      spellingDistance(token.word, phrase[index].lowercased(), limit: 1) != nil else { continue }
                let adjacent = window.indices.dropFirst().allSatisfy { offset in
                    let end = NSMaxRange(window[offset - 1].range)
                    let separator = source.substring(with: NSRange(location: end, length: window[offset].range.location - end))
                    return separator.range(of: #"\A\h*(?:的\h*)?\z"#, options: .regularExpression) != nil
                }
                guard adjacent else { continue }
                let phraseRange = NSRange(location: window[0].range.location, length: NSMaxRange(window[window.count - 1].range) - window[0].range.location)
                let before = source.substring(to: phraseRange.location)
                let after = source.substring(from: NSMaxRange(phraseRange))
                guard before.range(of: #"[A-Za-z]\h+\z"#, options: .regularExpression) == nil,
                      after.range(of: #"^\h+[A-Za-z]"#, options: .regularExpression) == nil else { continue }
                // An exact neighboring word alone is insufficient: "a daft PR campaign" is ordinary English.
                guard hasComputerLexiconContext(in: source, excluding: phraseRange) else { continue }
                replacements[token.range, default: []].insert(phrase[index])
            }
        }
        var normalized = transcript
        for (range, candidates) in replacements.sorted(by: { $0.key.location > $1.key.location }) where candidates.count == 1 {
            normalized = (normalized as NSString).replacingCharacters(in: range, with: candidates.first!)
        }
        return normalized
    }

    private static func spellingDistance(_ left: String, _ right: String, limit: Int) -> Int? {
        let lhs = Array(left.utf8)
        let rhs = Array(right.utf8)
        guard abs(lhs.count - rhs.count) <= limit else { return nil }
        var previous = Array(0...rhs.count)
        var beforePrevious = previous
        for row in 1...lhs.count {
            var current = [row] + Array(repeating: 0, count: rhs.count)
            for column in 1...rhs.count {
                current[column] = min(previous[column] + 1, current[column - 1] + 1,
                                      previous[column - 1] + (lhs[row - 1] == rhs[column - 1] ? 0 : 1))
                if row > 1, column > 1, lhs[row - 1] == rhs[column - 2], lhs[row - 2] == rhs[column - 1] {
                    current[column] = min(current[column], beforePrevious[column - 2] + 1)
                }
            }
            guard current.min()! <= limit else { return nil }
            beforePrevious = previous
            previous = current
        }
        return previous[rhs.count] <= limit ? previous[rhs.count] : nil
    }

    struct NormalizationCandidate: Sendable {
        let term: String
        let key: String
        let scalarCount: Int
        let expression: NSRegularExpression?

        init(term: String) {
            self.term = term
            key = compactMatchingKey(for: term)
            scalarCount = term.unicodeScalars.count
            expression = try? NSRegularExpression(
                pattern: normalizationPattern(for: term),
                options: [.caseInsensitive]
            )
        }
    }

    final class NormalizationCandidateCache: @unchecked Sendable {
        private struct Entry {
            let candidate: NormalizationCandidate
            let textBytes: Int
            var access: UInt64
        }

        private let lock = NSLock()
        private var entries: [Data: Entry] = [:]
        private var access: UInt64 = 0
        private var textBytes = 0

        func candidate(for term: String) -> NormalizationCandidate {
            guard isShortHint(term) else { return NormalizationCandidate(term: term) }
            let cacheKey = Data(term.utf8)
            lock.lock()
            defer { lock.unlock() }
            access &+= 1
            if var existing = entries[cacheKey] {
                existing.access = access
                entries[cacheKey] = existing
                return existing.candidate
            }

            // A short word can still share an oversized buffer reserved by its caller.
            let candidate = NormalizationCandidate(term: String(decoding: cacheKey, as: UTF8.self))
            // This budget counts retained text, not Foundation's private compiled-pattern storage.
            let cost = cacheKey.count + term.utf8.count + candidate.key.utf8.count
                + (candidate.expression?.pattern.utf8.count ?? 0)
            while entries.count >= 2_048 || textBytes + cost > 1_048_576 {
                // Short hints always fit the byte budget, so eviction cannot exhaust the cache here.
                let oldest = entries.min { $0.value.access < $1.value.access }!
                entries.removeValue(forKey: oldest.key)
                textBytes -= oldest.value.textBytes
            }
            entries[cacheKey] = Entry(candidate: candidate, textBytes: cost, access: access)
            textBytes += cost
            return candidate
        }

        var retainedResources: (count: Int, textBytes: Int) {
            lock.lock()
            defer { lock.unlock() }
            return (entries.count, textBytes)
        }
    }

    private static let normalizationCandidateCache = NormalizationCandidateCache()

    private static func normalizationCandidates(for terms: [String]) -> [NormalizationCandidate] {
        var seen = Set<String>()
        return terms.compactMap { term -> NormalizationCandidate? in
            let candidate = normalizationCandidateCache.candidate(for: term)
            guard !candidate.key.isEmpty, seen.insert(candidate.key).inserted else { return nil }
            return candidate
        }
        .sorted {
            let leftLength = $0.scalarCount
            let rightLength = $1.scalarCount
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
        if gitCollaborationTerms.contains(term), term.contains(" ") {
            let body = term.split(separator: " ").map { asciiTokenPattern(String($0)) }.joined(separator: #"\h+"#)
            return "(?<![A-Za-z0-9])\(body)(?![A-Za-z0-9])"
        }
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
                if index > 0, index + 1 < scalars.count,
                   scalars[index - 1].properties.numericType != nil,
                   scalars[index + 1].properties.numericType != nil {
                    pieces.append(NSRegularExpression.escapedPattern(for: String(scalar)))
                    index += 1
                    continue
                }
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
        let literals = normalizationProtectedRanges(in: transcript)
        var normalized = transcript
        let contextualMatches = contextualTranscript.map(githubAliasRanges(in:)) ?? []
        for index in matches.indices.reversed() {
            let match = matches[index]
            guard !literals.intersects(integersIn: match.location..<NSMaxRange(match)) else { continue }
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
        normalizeContextualModelAliases(
            normalizeContextualOpenSourceAlias(
                normalizeContextualGitHubAlias(
                    transcript,
                    enabled: enabled,
                    contextualTranscript: contextualTranscript
                ),
                enabled: enabled
            ),
            enabled: enabled
        )
    }

    private static func normalizeContextualModelAliases(_ transcript: String, enabled: Set<Self>) -> String {
        guard enabled.contains(.computerTerms) || enabled.contains(.brandsAndProducts) else { return transcript }
        let expression = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])Q运(?=\s*[0-9])|伽马"#, options: [.caseInsensitive])
        let source = transcript as NSString
        let literals = normalizationProtectedRanges(in: transcript)
        var normalized = transcript
        for match in expression.matches(in: transcript, range: NSRange(location: 0, length: source.length)).reversed() {
            guard !literals.intersects(integersIn: match.range.location..<NSMaxRange(match.range)) else { continue }
            let sentence = sentenceRange(containing: match.range, in: source)
            let before = source.substring(with: NSRange(location: sentence.location, length: match.range.location - sentence.location))
            let after = source.substring(with: NSRange(location: NSMaxRange(match.range), length: NSMaxRange(sentence) - NSMaxRange(match.range)))
            let replacement: String
            if source.substring(with: match.range) == "伽马" {
                // Gamma is also a scientific term; only a vendor-qualified model name is unambiguous.
                guard before.range(of: #"(?<![A-Za-z0-9])(?:Google|谷歌)\s*的?\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil,
                      after.range(of: #"^\s*(?:[0-9一二三四五六七八九十]+(?:\.[0-9]+)?)?\s*(?:系列|模型)"#, options: .regularExpression) != nil else { continue }
                replacement = "Gemma"
            } else {
                let followsModelLabel = before.range(
                    of: #"(?:模型|LLM)\s*(?:是|为|选用|换成)?\s*$"#,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil
                let switchesModel = before.range(
                    of: #"(?:模型|LLM)\s*(?:从|由)\s*$"#, options: [.regularExpression, .caseInsensitive]
                ) != nil && after.range(
                    of: #"^\s*[0-9]+(?:\.[0-9]+)*(?:-[A-Za-z0-9]+)?\s*(?:改成|换成|改为|切换到)"#,
                    options: .regularExpression
                ) != nil
                let precedesModelLabel = after.range(
                    of: #"^\s*[0-9]+(?:\.[0-9]+)*(?:-[A-Za-z0-9]+)?\s*(?:系列|模型)"#,
                    options: .regularExpression
                ) != nil
                guard followsModelLabel || switchesModel || precedesModelLabel else { continue }
                replacement = "Qwen"
            }
            normalized = (normalized as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return normalized
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
        let literals = normalizationProtectedRanges(in: transcript)
        for match in matches.reversed() {
            guard !literals.intersects(integersIn: match.location..<NSMaxRange(match)) else { continue }
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
            .filter { !["github", "repo", "init", "draft"].contains(compactMatchingKey(for: $0)) }
            .contains { containsCompactTerm($0, in: maskedSentence) }
    }

    private static func sentenceRange(containing range: NSRange, in transcript: NSString) -> NSRange {
        var start = range.location
        while start > 0, !isSentenceBoundary(at: start - 1, in: transcript) {
            start -= 1
        }

        var end = NSMaxRange(range)
        while end < transcript.length, !isSentenceBoundary(at: end, in: transcript) {
            end += 1
        }
        return NSRange(location: start, length: end - start)
    }

    private static func isSentenceBoundary(at index: Int, in transcript: NSString) -> Bool {
        let scalar = transcript.character(at: index)
        if scalar == 46, index > 0, index + 1 < transcript.length,
           (48...57).contains(transcript.character(at: index - 1)),
           (48...57).contains(transcript.character(at: index + 1)) {
            return false
        }
        return switch scalar {
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
                let separatesDigits = (48...57).contains(previous) && (48...57).contains(current)
                if !separatesDigits && (isAcronym || (65...90).contains(current) && (97...122).contains(previous)) {
                    result += #"[\s\p{P}\p{S}]*"#
                }
            }
            result += NSRegularExpression.escapedPattern(for: String(scalar))
        }
        return result
    }
}
