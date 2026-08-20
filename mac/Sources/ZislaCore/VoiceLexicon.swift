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

    /// Apple Speech accepts at most 100 contextual phrases per request.
    public static let maximumContextualTerms = 100

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
                "人工智能", "AI", "机器学习", "深度学习", "大语言模型", "生成式 AI", "提示词", "上下文",
                "向量数据库", "嵌入", "Transformer", "神经网络", "模型推理", "微调", "RAG", "检索增强生成",
                "API", "SDK", "CLI", "HTTP", "HTTPS", "URL", "JSON", "XML", "YAML", "SQL", "SQLite",
                "数据库", "MySQL", "PostgreSQL", "Redis", "Docker", "Kubernetes", "Git", "GitHub", "GitLab",
                "Swift", "SwiftUI", "Objective-C", "Python", "JavaScript", "TypeScript", "Node.js", "React", "Vue",
                "编译器", "运行时", "调试", "断点", "线程", "进程", "异步", "并发", "缓存", "前端", "后端",
                "全栈", "接口", "仓库", "分支", "提交", "合并请求", "持续集成", "macOS", "iOS", "Xcode", "AppKit",
                "Foundation"
            ]
        case .classicalPoetry:
            [
                "唐诗", "宋词", "古诗", "古文", "李白", "杜甫", "白居易", "王维", "孟浩然", "苏轼", "李清照",
                "床前明月光", "疑是地上霜", "举头望明月", "低头思故乡", "白日依山尽", "黄河入海流", "欲穷千里目",
                "更上一层楼", "海内存知己", "天涯若比邻", "春眠不觉晓", "处处闻啼鸟", "随风潜入夜", "润物细无声",
                "会当凌绝顶", "一览众山小", "大漠孤烟直", "长河落日圆", "独在异乡为异客", "每逢佳节倍思亲",
                "桃花潭水深千尺", "不及汪伦送我情", "明月几时有", "把酒问青天", "但愿人长久", "千里共婵娟",
                "先天下之忧而忧", "后天下之乐而乐", "醉翁之意不在酒", "海上生明月", "天涯共此时", "山重水复疑无路",
                "柳暗花明又一村", "人生自古谁无死", "留取丹心照汗青", "天生我材必有用", "千金散尽还复来"
            ]
        case .internetBuzzwords:
            [
                "YYDS", "yyds", "绝绝子", "破防", "破防了", "内卷", "躺平", "摆烂", "凡尔赛", "社恐", "社牛",
                "上头", "下头", "种草", "拔草", "安利", "吃瓜", "打卡", "emo", "CPU", "拿捏", "松弛感",
                "显眼包", "电子榨菜", "多巴胺", "赛博", "人机", "尊嘟假嘟", "泰酷辣", "遥遥领先", "硬控",
                "主打一个", "不明觉厉", "细思极恐", "蚌埠住了", "我真的会谢", "栓Q", "家人们", "宝藏",
                "神仙打架", "天花板", "顶流", "流量密码", "情绪价值", "狠狠地", "浅浅地", "在线等"
            ]
        case .peopleAndPlaces:
            [
                "北京", "上海", "广州", "深圳", "杭州", "成都", "重庆", "西安", "武汉", "南京", "苏州", "香港",
                "澳门", "台北", "天安门", "故宫", "长城", "黄山", "张伟", "王伟", "李娜", "马云", "任正非",
                "雷军", "乔布斯", "埃隆·马斯克", "诸葛亮", "司马迁", "鲁迅", "莫言", "屠呦呦", "袁隆平"
            ]
        case .brandsAndProducts:
            [
                "Apple", "iPhone", "iPad", "MacBook", "AirPods", "华为", "鸿蒙", "小米", "米家", "大疆", "比亚迪",
                "特斯拉", "理想汽车", "蔚来", "小鹏", "阿里巴巴", "淘宝", "支付宝", "微信", "抖音", "小红书",
                "美团", "京东", "拼多多", "Notion", "Figma", "ChatGPT", "Claude", "Gemini", "Copilot", "DeepSeek"
            ]
        case .medicineAndHealth:
            [
                "新冠", "流感", "过敏性鼻炎", "高血压", "糖尿病", "心电图", "核磁共振", "CT", "超声", "血常规",
                "血糖", "血脂", "维生素", "阿莫西林", "布洛芬", "对乙酰氨基酚", "奥司他韦", "二甲双胍", "青霉素",
                "抗生素", "处方药", "非处方药", "挂号", "急诊", "康复", "心理咨询", "疫苗", "免疫力", "体检"
            ]
        case .lawAndGovernment:
            [
                "民法典", "刑法", "劳动法", "知识产权", "著作权", "商标权", "专利权", "合同", "违约", "诉讼",
                "仲裁", "证据", "法院", "检察院", "公安", "行政许可", "行政处罚", "个人信息保护法", "网络安全法",
                "数据安全法", "营业执照", "身份证", "居住证", "社保", "公积金", "电子签名", "法律援助", "律师事务所"
            ]
        case .financeAndBusiness:
            [
                "股票", "基金", "债券", "期货", "期权", "ETF", "指数", "A股", "港股", "美股", "上证指数",
                "深证成指", "创业板", "科创板", "市盈率", "市净率", "分红", "股息", "利率", "通货膨胀", "GDP",
                "央行", "商业银行", "微信支付", "融资", "估值", "现金流", "资产负债表", "利润表", "现金流量表"
            ]
        case .educationAndResearch:
            [
                "高等数学", "线性代数", "概率论", "物理", "化学", "生物", "语文", "英语", "考研", "高考", "中考",
                "论文", "摘要", "参考文献", "实验室", "学术", "期刊", "开题报告", "答辩", "自然语言处理", "计算机视觉",
                "量子计算", "基因组", "诺贝尔奖", "中国科学院", "清华大学", "北京大学", "知识图谱", "数据分析"
            ]
        case .filmAndMusic:
            [
                "电影", "电视剧", "综艺", "纪录片", "动画", "导演", "编剧", "演员", "奥斯卡", "金鸡奖", "戛纳电影节",
                "周杰伦", "林俊杰", "邓紫棋", "五月天", "Taylor Swift", "Spotify", "网易云音乐", "QQ音乐", "漫威", "DC",
                "哈利·波特", "星球大战", "流浪地球", "三体", "甄嬛传", "红楼梦", "音乐节", "演唱会"
            ]
        case .gamesAndAnime:
            [
                "英雄联盟", "王者荣耀", "原神", "崩坏：星穹铁道", "绝区零", "和平精英", "蛋仔派对", "Minecraft", "我的世界",
                "Steam", "任天堂", "PlayStation", "Xbox", "Switch", "宝可梦", "塞尔达传说", "最终幻想", "魔兽世界",
                "炉石传说", "Dota 2", "CS2", "黑神话：悟空", "哆啦A梦", "名侦探柯南", "海贼王", "火影忍者", "鬼灭之刃",
                "进击的巨人"
            ]
        case .travelAndTransport:
            [
                "高铁", "动车", "地铁", "公交", "出租车", "网约车", "飞机", "航班", "机场", "火车站", "导航", "高德地图",
                "百度地图", "滴滴出行", "新能源", "电动车", "充电桩", "自动驾驶", "驾驶证", "高速公路", "服务区", "ETC",
                "停车场", "共享单车", "绿灯", "红绿灯", "过路费", "旅行社", "签证"
            ]
        case .dailyLife:
            [
                "外卖", "快递", "菜鸟", "顺丰", "圆通", "中通", "饿了么", "直播", "短视频", "健身", "瑜伽", "咖啡",
                "奶茶", "火锅", "露营", "旅游", "酒店", "民宿", "携程", "去哪儿", "大众点评", "家政", "装修", "家居",
                "洗衣店", "便利店", "超市", "会员卡", "优惠券", "售后"
            ]
        }
    }

    public static func terms(for enabled: Set<Self>) -> [String] {
        var seen = Set<String>()
        return allCases
            .filter { enabled.contains($0) }
            .flatMap(\.terms)
            .filter { seen.insert($0).inserted }
    }

    /// Distributes the system-recognizer hints across enabled dictionaries instead of exhausting the first one.
    public static func contextualTerms(
        for enabled: Set<Self>,
        maxCount: Int = maximumContextualTerms
    ) -> [String] {
        guard maxCount > 0 else { return [] }
        let lexicons = allCases.filter { enabled.contains($0) }
        var offsets = Array(repeating: 0, count: lexicons.count)
        var seen = Set<String>()
        var result: [String] = []

        while result.count < maxCount {
            var added = false
            for index in lexicons.indices {
                let terms = lexicons[index].terms
                while offsets[index] < terms.count {
                    let term = terms[offsets[index]]
                    offsets[index] += 1
                    guard seen.insert(term).inserted else { continue }
                    result.append(term)
                    added = true
                    break
                }
                if result.count == maxCount { break }
            }
            if !added { break }
        }
        return result
    }
}
