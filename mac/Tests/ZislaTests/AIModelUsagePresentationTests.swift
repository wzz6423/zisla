import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite(.serialized)
struct AIModelUsagePresentationTests {
    private static let keys = ["每日模型用量", "暂无模型用量", "未分类", "未知模型", "输入 %@ · 输出 %@", "AI 模型用量"]

    /// Runtime lookups are asserted because missing localization keys silently fall back despite a successful build.
    @Test
    func everyLanguageTranslatesRuntimeModelUsageKeysWithMatchingPlaceholders() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: package.appendingPathComponent("Sources/Zisla/AIProgressModuleView.swift"), encoding: .utf8)
        for key in Self.keys.dropLast() { #expect(source.contains("\"\(key)\"")) }
        #expect(DailyBriefingContent.aiModelUsage.title == Self.keys.last)
        for language in AppLanguage.allCases {
            let path = package.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: path) as? [String: String])
            for key in Self.keys {
                let value = try #require(table[key], "Missing model usage key \(key) for \(language.rawValue)")
                #expect(!value.isEmpty)
                #expect(value.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count)
                #expect(AppLocalization.string(key, language: language) == value)
            }
        }
        #expect(AppLocalization.string("每日模型用量", language: .english) == "Daily Model Usage")
        #expect(AppLocalization.string("未分类", language: .arabic) == "غير مصنّف")
    }

    @Test @MainActor
    func unknownAndUnclassifiedDisplayDoNotPresentAnInventedProviderOrModel() {
        let unknown = AIModelUsage(provider: .zed, model: nil, inputTokens: 10, outputTokens: 2)
        let unclassified = AIModelUsage(provider: nil, model: nil, inputTokens: 5, outputTokens: 1)
        #expect(DailyModelUsageList.modelName(unknown, locale: AppLanguage.english.locale) == "Unknown Model")
        #expect(DailyModelUsageList.modelName(unclassified, locale: AppLanguage.english.locale) == "Unknown Model")
        #expect(DailyModelUsageList.tokenBreakdown(unknown, locale: AppLanguage.english.locale) == "Input 0.00001 M · Output 0.000002 M")
    }

    @Test @MainActor
    func modelNamesAndCountsRemainIndependentOfTheStoredProviderAndAxisUnits() {
        let model = AIModelUsage(provider: .codex, model: "gpt-6.1-sol", inputTokens: 2_000_000_000, outputTokens: 7_300_000)
        #expect(DailyModelUsageList.modelName(model, locale: AppLanguage.english.locale) == "gpt-6.1-sol")
        #expect(DailyModelUsageList.tokenBreakdown(model, locale: AppLanguage.english.locale) == "Input 2000 M · Output 7.3 M")
        #expect(DailyModelUsageList.tokenBreakdown(model, locale: AppLanguage.german.locale) == "Eingabe 2000 M · Ausgabe 7,3 M")
        #expect(DailyModelUsageList.tokenBreakdown(model, locale: Locale(identifier: "en_US")) == "Input 2000 M · Output 7.3 M")
        #expect(DailyModelUsageList.modelName(AIModelUsage(provider: .claude, model: nil, inputTokens: 1, outputTokens: 0),
            locale: Locale(identifier: "ar_EG")) == AppLocalization.string("未知模型", language: .arabic))
        #expect(model.provider == .codex)
        #expect(AIUsageAnalytics.formatTokenAxisValue(model.inputTokens) == "2B")
    }

    @Test @MainActor
    func chatGPTGroupingMergesSameModelsWithoutChangingOtherBrandsOrSourceRecords() throws {
        let models = [
            AIModelUsage(provider: .codex, model: "gpt-6.1-sol", inputTokens: 2_000_000_000, outputTokens: 7_300_000),
            AIModelUsage(provider: .gpt, model: "gpt-6.1-sol", inputTokens: 3_000_000, outputTokens: 2_000_000),
            AIModelUsage(provider: .codex, model: "gpt-6-astra", inputTokens: 1_300_000, outputTokens: 8_000),
            AIModelUsage(provider: .claude, model: "gpt-6.1-sol", inputTokens: 54_100_000, outputTokens: 1_000_000),
            AIModelUsage(provider: nil, model: nil, inputTokens: 1, outputTokens: 2),
        ]
        let groups = DailyModelUsageList.providerGroups(models)
        #expect(groups.count == 3)
        let chatGPT = try #require(groups.first { $0.provider == .gpt })
        #expect(chatGPT.identity == .gpt && chatGPT.name(locale: AppLanguage.english.locale) == "ChatGPT")
        #expect(chatGPT.models.count == 2)
        let merged = try #require(chatGPT.models.first { $0.model == "gpt-6.1-sol" })
        #expect(merged.inputTokens == 2_003_000_000 && merged.outputTokens == 9_300_000)
        let claude = try #require(groups.first { $0.provider == .claude })
        #expect(claude.identity == .claude && claude.name(locale: AppLanguage.english.locale) == "Claude")
        #expect(claude.models == [models[3]])
        let unclassified = try #require(groups.first { $0.provider == nil })
        #expect(unclassified.identity == nil && unclassified.name(locale: AppLanguage.arabic.locale) == "غير مصنّف")
        #expect(models[0].provider == .codex && models[1].provider == .gpt)
        #expect(DailyModelUsageList.providerGroups([]).isEmpty)
        #expect(AIMascotIdentity(provider: .codex, taskID: "fixture").displayName == "Codex")
    }

    @Test @MainActor
    func mergingDisplayModelsSaturatesAndKeepsUnknownUsageInItsBrand() throws {
        let groups = DailyModelUsageList.providerGroups([
            AIModelUsage(provider: .codex, model: nil, inputTokens: Int.max, outputTokens: 2),
            AIModelUsage(provider: .gpt, model: "  ", inputTokens: 1, outputTokens: Int.max),
        ])
        let group = try #require(groups.first)
        #expect(groups.count == 1 && group.models.count == 1)
        #expect(group.models[0].inputTokens == Int.max && group.models[0].outputTokens == Int.max)
        #expect(group.models[0].model == nil && group.name(locale: AppLanguage.english.locale) == "ChatGPT")
    }

    /// Normal model names and both counts must share a visible line at the island's narrow usage width.
    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic]) @MainActor
    func normalModelRowsRetainReadableNamesAndCountsAt220Points(language: AppLanguage) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let models = [
            AIModelUsage(provider: .codex, model: "gpt-6.1-sol", inputTokens: 2_000_000_000, outputTokens: 7_300_000),
            AIModelUsage(provider: .codex, model: "gpt-6-astra", inputTokens: 1_300_000, outputTokens: 8_000),
            AIModelUsage(provider: .claude, model: "claude-fable-5.2", inputTokens: 54_100_000, outputTokens: 1_000_000),
        ]
        let day = AIDailyModelUsage(date: Date(timeIntervalSince1970: 1_800_000_000),
            inputTokens: 2_055_400_000, outputTokens: 8_308_000, models: models)
        let root = DailyModelUsageList(day: day)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
            .frame(width: 220)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -100_000, y: -100_000, width: 220, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let objects = accessibilityObjects(host)
        let contentBounds = window.convertToScreen(host.convert(host.bounds, to: nil))
        for model in models {
            let name = try #require(objects.first { value($0, "accessibilityValue") as? String == model.model }
                as? any NSAccessibilityElementProtocol, "Missing model name \(model.model ?? "")")
            let counts = try #require(objects.first {
                value($0, "accessibilityValue") as? String == DailyModelUsageList.tokenBreakdown(model, locale: language.locale)
            } as? any NSAccessibilityElementProtocol, "Missing input/output values")
            let nameFrame = name.accessibilityFrame()
            let countsFrame = counts.accessibilityFrame()
            let referenceWidth = NSAttributedString(string: model.model ?? "", attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium)]).size().width
            #expect(nameFrame.width >= referenceWidth * 0.75 - 1 && nameFrame.height >= 9,
                "Model \(model.model ?? "") cannot collapse: frame \(nameFrame), natural width \(referenceWidth)")
            #expect(countsFrame.width > 0 && countsFrame.height >= 9)
            #expect(abs(nameFrame.midY - countsFrame.midY) < 2, "Model name and counts must occupy one line")
            #expect(contentBounds.insetBy(dx: -1, dy: -1).contains(nameFrame))
            #expect(contentBounds.insetBy(dx: -1, dy: -1).contains(countsFrame))
            #expect(!nameFrame.intersects(countsFrame), "Counts must not cover the model name")
        }
        #expect(objects.contains { value($0, "accessibilityValue") as? String == "ChatGPT" })
        #expect(objects.contains { value($0, "accessibilityValue") as? String == "Claude" })
        #expect(!objects.contains { (value($0, "accessibilityValue") as? String)?.contains("CODEX") == true })
        #expect(!window.isVisible)
    }

    /// Long identities and RTL must wrap within narrow island widths instead of expanding the panel.
    @Test @MainActor
    func modelRowsFitNarrowIslandWidthsWithLongNamesAndRTL() throws {
        let model = AIModelUsage(provider: .codex, model: String(repeating: "gpt-model-long-name-", count: 8),
            inputTokens: Int.max, outputTokens: 99_999)
        let day = AIDailyModelUsage(date: Date(timeIntervalSince1970: 1_800_000_000),
            inputTokens: Int.max, outputTokens: 99_999, models: [model])
        for width in [CGFloat(120), 220, 340] {
            let view = DailyModelUsageList(day: day)
                .frame(width: width)
                .environment(\.locale, AppLanguage.arabic.locale)
                .environment(\.layoutDirection, .rightToLeft)
            let hosting = NSHostingView(rootView: view)
            let size = hosting.fittingSize
            #expect(size.width <= width + 1, "Model rows overflow an island width of \(width)")
            #expect(size.height.isFinite && size.height > 0)
        }
    }

    /// Exported poster colors and brand identities cannot depend on the desktop's appearance.
    @Test(arguments: DailyBriefingTemplate.allCases, [AppLanguage.simplifiedChinese, .english, .arabic]) @MainActor
    func briefingModelRowsKeepBrandAndMillionUnitsInEveryPosterPalette(template: DailyBriefingTemplate, language: AppLanguage) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        var report = DailyBriefingReport.example(at: Date(timeIntervalSince1970: 1_800_000_000), selectedContent: [.aiModelUsage])
        report.aiUsage = AIDailyModelUsage(date: report.day.date, inputTokens: 4_000_000, outputTokens: 500_000, models: [
            AIModelUsage(provider: .codex, model: "gpt-6.1-sol", inputTokens: 3_000_000, outputTokens: 300_000),
            AIModelUsage(provider: .claude, model: "claude-fable-5.2", inputTokens: 1_000_000, outputTokens: 200_000),
        ])
        let poster = DailyBriefingPoster(report: report, template: template, language: language)
        let host = NSHostingView(rootView: poster)
        let window = NSWindow(contentRect: CGRect(x: -100_000, y: -100_000, width: 900, height: 800),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let objects = accessibilityObjects(host)
        let values = objects.compactMap { value($0, "accessibilityValue") as? String }
        #expect(values.contains("ChatGPT") && values.contains("Claude"))
        #expect(!values.contains { $0.contains("CODEX") || $0.contains("Codex") })
        let models = try #require(report.aiUsage?.models)
        for model in models {
            let name = try #require(objects.first { value($0, "accessibilityValue") as? String == model.model }
                as? any NSAccessibilityElementProtocol)
            let counts = try #require(objects.first {
                value($0, "accessibilityValue") as? String == DailyModelUsageList.tokenBreakdown(model, locale: language.locale)
            } as? any NSAccessibilityElementProtocol)
            #expect(abs(name.accessibilityFrame().midY - counts.accessibilityFrame().midY) < 3)
            #expect(!name.accessibilityFrame().intersects(counts.accessibilityFrame()))
        }
        let light = ImageRenderer(content: poster.environment(\.colorScheme, .light))
        let dark = ImageRenderer(content: poster.environment(\.colorScheme, .dark))
        light.scale = 1
        dark.scale = 1
        let lightImage = try #require(light.cgImage)
        let darkImage = try #require(dark.cgImage)
        #expect(lightImage.width == darkImage.width && lightImage.height == darkImage.height)
        #expect(try #require(lightImage.dataProvider?.data) as Data == #require(darkImage.dataProvider?.data) as Data,
            "The poster's fixed background must keep matching brand icon colors in both desktop appearances")
        #expect(!window.isVisible)
    }

    /// The export must receive the selected day's totals without requesting usage when that section is disabled.
    @Test @MainActor
    func briefingReadsOnlySelectedUsageAndCarriesDailyTotalAndModelRowsToExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-model-briefing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let day = DailyBriefingDay.calendar.startOfDay(for: date)
        let repository = AIStateRepository(directoryURL: root.appendingPathComponent("ai"))
        try repository.recordDetectedUsage([AIUsageSample(sourceID: "briefing", provider: .codex,
            timestamp: date, inputTokens: 10, outputTokens: 2, model: "gpt-6.1-sol")])
        var exported: [DailyBriefingReport] = []
        let controller = DailyBriefingController(store: DailyBriefingStore(fileURL: root.appendingPathComponent("briefing.json")),
            observation: { .init(date: $0, applicationID: "editor", applicationName: "Editor", category: .work, isActive: true, isListening: nil) },
            typing: { _ in nil }, readScreenTime: { _ in .init() },
            readAIUsage: { range in
                #expect(range.start == day)
                return try repository.loadUsageHistory(startingAt: range.start, endingBefore: range.end)
            }, export: { report, _, _, folder in
                exported.append(report)
                return folder.appendingPathComponent("fixture.png")
            })
        controller.configure(settings: .init(readsSystemScreenTime: false, selectedContent: [.aiModelUsage]),
            directory: root, language: .english, startsTimer: false)
        await controller.exportToday(at: date.addingTimeInterval(30))
        let report = try #require(exported.first)
        #expect(report.aiUsage?.totalTokens == 12)
        #expect(report.aiUsage?.models.first?.model == "gpt-6.1-sol")
        #expect(DailyBriefingPoster(report: report, template: .minimal, language: .english).displayedContent == [.aiModelUsage])
        controller.configure(settings: .init(readsSystemScreenTime: false, selectedContent: []),
            directory: root, language: .english, startsTimer: false)
        await controller.exportToday(at: date.addingTimeInterval(60))
        #expect(exported.count == 2)
        #expect(exported.last?.aiUsage == nil)
    }

    @Test @MainActor
    func unavailableAIUsageIsOmittedAndReadFailurePreventsAnIncompleteExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-model-briefing-error-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var exports = 0
        let controller = DailyBriefingController(store: DailyBriefingStore(fileURL: root.appendingPathComponent("briefing.json")),
            observation: { .init(date: $0, applicationID: "editor", applicationName: "Editor", category: .work, isActive: false, isListening: nil) },
            typing: { _ in nil }, readScreenTime: { _ in .init() }, readAIUsage: { _ in throw CocoaError(.fileReadCorruptFile) },
            export: { _, _, _, folder in exports += 1; return folder.appendingPathComponent("fixture.png") })
        controller.configure(settings: .init(readsSystemScreenTime: false, selectedContent: [.aiModelUsage]),
            directory: root, language: .english, startsTimer: false)
        await controller.exportToday(at: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(exports == 0)
        #expect(controller.errorMessage != nil)
        #expect(!controller.isExporting)
        var report = DailyBriefingReport.example(selectedContent: [.aiModelUsage])
        report.aiUsage = nil
        #expect(DailyBriefingPoster(report: report, template: .minimal, language: .english).displayedContent.isEmpty)
    }

    @MainActor
    private func value(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }

    @MainActor
    private func accessibilityObjects(_ object: NSObject) -> [NSObject] {
        [object] + (value(object, "accessibilityChildren") as? [NSObject] ?? []).flatMap(accessibilityObjects)
    }
}
