import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct AIModelUsagePresentationTests {
    private static let keys = ["每日模型用量", "暂无模型用量", "未分类", "未知模型", "输入 %@ · 输出 %@", "AI 模型用量"]

    @Test
    /// Runtime lookups are asserted because missing localization keys silently fall back despite a successful build.
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
        #expect(DailyModelUsageList.modelName(unknown, language: .english) == "ZED · Unknown Model")
        #expect(DailyModelUsageList.modelName(unclassified, language: .english) == "Unclassified")
        #expect(DailyModelUsageList.tokenBreakdown(unknown, language: .english) == "Input 10 · Output 2")
    }

    @Test @MainActor
    /// Long identities and RTL must wrap within narrow island widths instead of expanding the panel.
    func modelRowsFitNarrowIslandWidthsWithLongNamesAndRTL() throws {
        let model = AIModelUsage(provider: .codex, model: String(repeating: "gpt-model-long-name-", count: 8),
            inputTokens: Int.max, outputTokens: 99_999)
        let day = AIDailyModelUsage(date: Date(timeIntervalSince1970: 1_800_000_000),
            inputTokens: Int.max, outputTokens: 99_999, models: [model])
        for width in [CGFloat(120), 220, 340] {
            let view = DailyModelUsageList(days: [day])
                .frame(width: width)
                .environment(\.locale, AppLanguage.arabic.locale)
                .environment(\.layoutDirection, .rightToLeft)
            let hosting = NSHostingView(rootView: view)
            let size = hosting.fittingSize
            #expect(size.width <= width + 1, "Model rows overflow an island width of \(width)")
            #expect(size.height.isFinite && size.height > 0)
        }
    }

    @Test @MainActor
    /// The export must receive the selected day's totals without requesting usage when that section is disabled.
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
}
