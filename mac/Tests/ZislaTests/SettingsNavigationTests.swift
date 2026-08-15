import Testing

@testable import Zisla

struct SettingsNavigationTests {
    @Test
    func keepsPrivacySeparateFromGeneralSettings() {
        #expect(SettingsSection.allCases.map(\.title) == [
            "通用",
            "功能",
            "工作流",
            "信息",
            "AI",
            "语音",
            "模型",
            "桌面宠物",
            "隐私",
            "下载",
            "天气",
            "推荐",
            "更新",
        ])
        #expect(SettingsSection.general.subtitle == "调整语言、外观、启动与展开方式。")
        #expect(SettingsSection.privacy.subtitle == "管理剪贴板访问与本机数据。")
    }
}
