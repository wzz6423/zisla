import Foundation
import ZislaCore
import ZislaKit

enum SettingsSearchAnchor: Hashable {
    case row(String)
    case group(String)

    func localized(locale: Locale) -> Self {
        switch self {
        case .row(let key): .row(AppLocalization.string(key, locale: locale))
        case .group(let key): .group(AppLocalization.string(key, locale: locale))
        }
    }
}

struct SettingsSearchItem: Identifiable, Equatable {
    let section: SettingsSection
    let title: String
    let anchor: SettingsSearchAnchor
    let keywords: [String]

    var id: String { "\(section.rawValue):\(title)" }
}

enum SettingsSearchIndex {
    static func results(for query: String, settings: FeatureSettings, locale: Locale) -> [SettingsSearchItem] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

        let matches = items(settings: settings).filter { item in
            let keys = [item.title, item.section.title] + item.keywords
            let text = keys.flatMap {
                [$0, AppLocalization.string($0, locale: locale)]
            }.joined(separator: "\n")
            return terms.allSatisfy {
                text.range(of: $0, options: options, locale: locale) != nil
            }
        }
        let titleQuery = terms.joined(separator: " ")
        func matchesExactTitle(_ item: SettingsSearchItem) -> Bool {
            [item.title, AppLocalization.string(item.title, locale: locale)].contains {
                $0.compare(titleQuery, options: options, locale: locale) == .orderedSame
            }
        }
        return matches.sorted { matchesExactTitle($0) && !matchesExactTitle($1) }
    }

    static func items(settings: FeatureSettings) -> [SettingsSearchItem] {
        var items: [SettingsSearchItem] = []

        func rows(_ section: SettingsSection, _ titles: [String]) {
            items += titles.map {
                SettingsSearchItem(section: section, title: $0, anchor: .row($0), keywords: [])
            }
        }

        func entry(_ section: SettingsSection, _ title: String, anchor: SettingsSearchAnchor, keywords: [String] = []) {
            items.append(SettingsSearchItem(section: section, title: title, anchor: anchor, keywords: keywords))
        }

        rows(.general, ["界面语言", "界面外观", "灵动岛样式", "刘海背景"])
        entry(.general, "登录时启动", anchor: .row("登录时启动"), keywords: ["开机或登录后自动在后台运行", "需要系统批准"])

        rows(.features, [
            "显示推荐工具", "媒体播放", "Mac 未使用时关闭背景音", "中转站", "晃动唤出中转窗口",
            "链接下载", "剪贴板历史", "剪贴板链接检测", "快捷操作", "日历日程", "天气", "邮件",
            "侧翼通知", "锁屏信息", "专注倒计时", "工具箱提醒", "AI 进度与用量", "AI 任务结果扫光",
            "语音输入", "窗口预览", "小工具", "随记", "PDF 工具", "系统状态与清理", "电池监控",
            "键盘音效", "合盖动画", "预览动画", "启用截图", "鼠标移入展开", "显示 zisla 图标",
            "始终置顶", "提示条进度光效", "浏览器下载进度", "原生下载进度", "静音 Zisla 通知",
            "宠物", "自动检查更新", "自动下载更新",
        ])
        if settings.recommendedToolsEnabled {
            rows(.features, ["自动更新推荐工具"])
        }
        entry(.features, "工具", anchor: .group("工具"), keywords: ["恢复默认顺序"] + IslandModuleOrder.allCases.map(\.title))

        rows(.info, ["播放来源", "歌词与歌曲信息", "收起态音乐样式", "活动展示", "专注模式展示"])
        if settings.systemMonitorEnabled {
            entry(.info, "菜单栏常驻", anchor: .row("菜单栏常驻"), keywords: ["独立"])
            if settings.systemMonitorMenuBarLayout.individualEnabled {
                rows(.info, ["监控样式"] + SystemMonitorMenuBarMetric.allCases.map(\.menuTitle))
            }
            entry(.info, "合并", anchor: .group("settings-search-monitor-layout"), keywords: ["显示数量", "上行", "下行"])
            entry(.info, "合并状态图标", anchor: .group("settings-search-monitor-layout"), keywords: [
                "底部指标", "显示电池百分比", "显示充电标记", "接通电源时显示百分比", "电量状态颜色",
                "底部指示样式", "电量环粗细", "图标大小", "Wi-Fi 大小", "电量文字大小",
                "连接时短暂显示耳机图标", "优先显示网络错误", "耳机图标大小", "蓝牙音量颜色",
            ])
            entry(.info, "记录历史", anchor: .row("记录历史"), keywords: ["按分钟记录 CPU、GPU、内存、硬盘、风扇与网络，可随时查看趋势并导出表格"])
        }
        if settings.lockScreenInfoEnabled {
            rows(.info, ["锁屏文字", "显示农历"])
        }
        entry(.info, "收起态展示优先级", anchor: .group("收起态展示优先级"), keywords: ["恢复默认顺序"])
        entry(.info, "通知显示器", anchor: .group("通知显示器"), keywords: ["播放与 AI 活动通知显示在此屏幕"])

        rows(.clipboardAssistant, [
            "关闭弹窗快捷键", "鼠标侧键", "轻量提醒模式",
            "存在时长", "每次保存文件时选择位置", "应用黑名单", "下载与 AirDrop 完成提示", "摇动鼠标记便签",
        ])
        entry(.clipboardAssistant, "快速触发快捷键", anchor: .row("快速触发快捷键"), keywords: ["输入监控"])
        entry(.clipboardAssistant, "鼠标手势快速复制", anchor: .row("鼠标手势快速复制"), keywords: ["辅助功能"])
        entry(.clipboardAssistant, "搜索引擎", anchor: .row("搜索引擎"), keywords: ["自定义搜索网址", "文本搜索使用的搜索引擎"])
        if settings.clipboardAssistantSearchEngine == .custom {
            rows(.clipboardAssistant, ["自定义搜索网址"])
        }
        if settings.contextNotesEnabled {
            rows(.clipboardAssistant, ["便签快捷键"])
        }
        entry(.clipboardAssistant, "识别类型", anchor: .row("识别类型"), keywords: [
            "链接", "文件路径", "邮箱", "电话号码", "颜色值", "算式", "汇率换算", "换算", "日期时间",
            "地址", "航班", "火车车次", "快递单号", "会议日程", "Emoji 名称", "代码", "Shell 命令",
            "应用程序", "非 Zisla 全局语言文本", "文本", "图片", "文件", "主动作", "恢复默认顺序",
            "单位换算", "日期间隔", "跨时区时间",
        ])

        entry(.screenshot, "截图快捷键", anchor: .row("截图快捷键"), keywords: ["输入监控"])
        rows(.screenshot, ["钉图快捷键", "长截图", "显示钉图控制条", "鼠标操作", "触控板手势"])
        rows(.screenshot, ScreenshotTool.allCases.map(\.title))

        entry(.ai, "CLI 与 Skills", anchor: .group("CLI 与 Skills"), keywords: ["自动更新 CLI", "下载命令", "更新命令"])
        rows(.voice, ["录音模式", "使用模型", "格式化整理", "保留原始录音", "自动清理录音", "记录目录", "自定义热词"])
        entry(.voice, "快捷键", anchor: .row("快捷键"), keywords: ["输入监控"])
        entry(.voice, "本地模型", anchor: .group("本地模型"), keywords: ["添加本地模型", "URL / IP:端口", "模型名"])
        entry(.voice, "远端模型与凭据", anchor: .group("远端模型与凭据"), keywords: ["添加远端模型", "协议", "模型名"])
        for lexicon in VoiceLexicon.allCases {
            entry(.voice, lexicon.title, anchor: .row(lexicon.title), keywords: [lexicon.detail])
        }

        rows(.mail, ["新邮件展示"])
        entry(.mail, "邮件账户", anchor: .group("邮件"))
        rows(.keyboardSound, ["键盘音色", "键盘音量", "播放键盘回弹音", "自然音高变化", "记录本地输入统计", "输入监控权限"])
        rows(.download, ["默认下载目录", ManagedTool.ytDLP.displayName, ManagedTool.libreOffice.displayName])
        entry(.weather, "地点", anchor: .group("地点"), keywords: ["城市、区县或地区", "搜索地区"])
        rows(.weather, ["天气数据"])
        rows(.networkProxy, ["代理链接", "启用本地代理", "代理状态"])
        rows(.pet, ["当前宠物", "在岛的哪一侧"])
        entry(.recommendations, "一键管理", anchor: .group("一键管理"), keywords: ["一键下载所有未安装的推荐工具", "一键更新所有已安装的推荐工具"])
        for tool in ManagedTool.allCases {
            entry(.recommendations, tool.displayName, anchor: .row(tool.displayName), keywords: [tool.purpose])
        }
        rows(.updates, ["更新通道"])
        entry(.updates, "版本", anchor: .group("版本"), keywords: ["检查更新"])
        entry(.updates, "反馈问题", anchor: .row("settings-search-feedback"))

        return items.filter { $0.section.isVisible(settings: settings) }
    }
}
