import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct IslandDashboardAIWorkTests {
    @Test
    func concurrentTasksProduceOneCardPerApplicationWithRunningCounts() {
        let tasks = [
            task("gpt-1", provider: .gpt),
            task("gpt-2", provider: .gpt),
            task("gpt-3", provider: .gpt),
            task("gemini-1", provider: .gemini),
            task("gemini-2", provider: .gemini),
            task("claude-1", provider: .claude),
            task("codex-complete", provider: .codex, status: .succeeded),
        ]
        let original = tasks
        let summaries = DashboardAIWorkSummary.groups(from: tasks, enabled: true)
        let counts = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0.count) })

        #expect(counts == ["ChatGPT": 3, "Gemini": 2, "Claude": 1],
                "Every running application must be visible once with its own task count")
        #expect(tasks == original, "Preparing dashboard cards must not change task state")
        #expect(IslandDashboardLayout.cardRowCount(forCardCount: summaries.count) == 2,
                "Three application cards must reserve two dashboard rows")
    }

    @Test(arguments: [AIProgressStatus.queued, .running, .blocked, .error, .succeeded, .failed])
    func onlyRunningTasksAppearOrContributeToTheCount(status: AIProgressStatus) {
        let tasks = [task("running", provider: .gpt), task("candidate", provider: .gpt, status: status),
                     task("other-app", provider: .claude, status: status)]
        let summaries = DashboardAIWorkSummary.groups(from: tasks, enabled: true)
        #expect(summaries.first { $0.id == "ChatGPT" }?.count == (status == .running ? 2 : 1))
        #expect(summaries.contains { $0.id == "Claude" } == (status == .running),
                "Applications without running tasks must not produce a card")
    }

    @Test(arguments: [false, true])
    func emptyInputAndTheFeatureSwitchControlCardVisibility(enabled: Bool) {
        #expect(DashboardAIWorkSummary.groups(from: [], enabled: enabled).isEmpty)
        let summaries = DashboardAIWorkSummary.groups(from: [task("running", provider: .gpt)], enabled: enabled)
        #expect(summaries.count == (enabled ? 1 : 0))
    }

    @Test
    func cardsKeepTheLatestTaskAndOrderApplicationsByRecentActivity() throws {
        let latest = task("latest-gpt", provider: .gpt, updatedAt: 30)
        let tasks = [task("old-gpt", provider: .gpt, updatedAt: 10),
                     task("claude", provider: .claude, updatedAt: 20), latest]
        let summaries = DashboardAIWorkSummary.groups(from: tasks, enabled: true)
        #expect(summaries.map(\.id) == ["ChatGPT", "Claude"])
        #expect(try #require(summaries.first).task == latest,
                "An application card must retain its newest running task as its representative")
    }

    @Test
    func simultaneousApplicationUpdatesKeepAStableCardOrder() {
        let tasks = [task("gemini", provider: .gemini), task("claude", provider: .claude),
                     task("gpt", provider: .gpt)]
        #expect(DashboardAIWorkSummary.groups(from: tasks, enabled: true).map(\.id) == ["ChatGPT", "Claude", "Gemini"])
        #expect(DashboardAIWorkSummary.groups(from: tasks.reversed(), enabled: true).map(\.id) == ["ChatGPT", "Claude", "Gemini"],
                "Equal timestamps must not reorder cards when the input order changes")
    }

    @Test(arguments: [Double?.none, 0, 0.5, 1])
    func singleTasksKeepTheirTitleAndProgressWhileGroupsShowTheApplication(progress: Double?) throws {
        let first = task("first", provider: .gpt, progress: progress)
        let single = try #require(DashboardAIWorkSummary.groups(from: [first], enabled: true).first)
        #expect(single.title == first.title)
        #expect(single.progress == progress)

        let multiple = try #require(DashboardAIWorkSummary.groups(
            from: [first, task("second", provider: .gpt, progress: 0.75)], enabled: true
        ).first)
        #expect(multiple.title == "ChatGPT", "A group must identify the application instead of one arbitrary task")
        #expect(multiple.progress == nil, "One task's percentage cannot represent several running tasks")
    }

    @Test
    func finishingTasksRestoresTheRemainingTitleAndThenRemovesTheCard() throws {
        var tasks = [task("first", provider: .gpt), task("second", provider: .gpt)]
        #expect(DashboardAIWorkSummary.groups(from: tasks, enabled: true).first?.count == 2)
        tasks[1].status = .succeeded
        let single = try #require(DashboardAIWorkSummary.groups(from: tasks, enabled: true).first)
        #expect(single.count == 1)
        #expect(single.title == tasks[0].title)
        tasks[0].status = .failed
        #expect(DashboardAIWorkSummary.groups(from: tasks, enabled: true).isEmpty)
    }

    @Test
    func geminiDesktopAndCLITasksShareTheGeminiCardAndKeepTheLatestLogo() throws {
        let tasks = [task("gemini-session-cli", provider: .gemini, updatedAt: 10),
                     task("gemini-desktop-chat-latest", provider: .gemini, updatedAt: 20)]
        let summaries = DashboardAIWorkSummary.groups(from: tasks, enabled: true)
        let summary = try #require(summaries.first)
        #expect(summaries.count == 1)
        #expect(summary.id == "Gemini")
        #expect(summary.count == 2)
        #expect(summary.identity == .geminiDesktop)
    }

    @Test
    func applicationsSharingAHistoricalProviderKeepSeparateCards() {
        let tasks = [task("dsh-session", provider: .harness, title: "DeepSeek Harness"),
                     task("harnext-session", provider: .harness, title: "harnext"),
                     task("workbuddy-session-legacy", provider: .harness),
                     task("workbuddy-session-current", provider: .workbuddy)]
        let summaries = DashboardAIWorkSummary.groups(from: tasks, enabled: true)
        let counts = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0.count) })
        #expect(counts == ["DeepSeek Harness": 1, "harnext": 1, "WorkBuddy": 2],
                "Application identity must follow the existing brand mapping rather than the stored provider alone")
    }

    @Test(arguments: AppLanguage.allCases)
    func runningCountUsesTheExistingTranslationInEveryLanguage(language: AppLanguage) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/IslandDashboardView.swift"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"AppLocalization\.string\("([^"]+)", locale: locale\)"#)
        let keys = try regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
            String(source[try #require(Range($0.range(at: 1), in: source))])
        }
        #expect(keys == ["正在运行"], "Verify the status key actually used by the dashboard")
        #expect(AppLanguage.allCases.count == 17)
        let tableURL = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        let key = try #require(keys.first)
        let translation = try #require(table[key], "Missing running status for \(language.rawValue)")
        let status = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!status.isEmpty)
        #expect(AppLocalization.string(key, locale: language.locale) == translation)
        if language != .simplifiedChinese { #expect(translation != key) }

        let first = task("first", provider: .gpt)
        let single = try #require(DashboardAIWorkSummary.groups(from: [first], enabled: true).first)
        let multiple = try #require(DashboardAIWorkSummary.groups(
            from: [first, task("second", provider: .gpt)], enabled: true
        ).first)
        #expect(single.statusText(locale: language.locale) == "1 \(status)")
        #expect(multiple.statusText(locale: language.locale) == "2 \(status)")
        if language == .english { #expect(multiple.statusText(locale: language.locale) == "2 running") }
        if language == .simplifiedChinese { #expect(multiple.statusText(locale: language.locale) == "2 正在运行") }
    }

    @Test(.serialized, arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    @MainActor
    func cardContentRendersTheGroupCountAndRestoresSingleTaskProgress(language: AppLanguage) async throws {
        let tasks = [task("first", provider: .gpt, progress: 0.5),
                     task("second", provider: .gpt, progress: 0.75)]
        let grouped = try #require(DashboardAIWorkSummary.groups(from: tasks, enabled: true).first)
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: DashboardAIWorkContent(summary: grouped)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        host.sizingOptions = []
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 280, height: 36),
                            styleMask: .borderless, backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        defer { panel.contentView = nil; panel.close() }
        await settle(host)
        let groupedText = text(in: host)
        #expect(groupedText.contains("ChatGPT"))
        #expect(groupedText.contains(grouped.statusText(locale: language.locale)),
                "The group card must render the count and the requested language's running status")
        #expect(!groupedText.contains("50%") && !groupedText.contains("75%"))

        let single = try #require(DashboardAIWorkSummary.groups(from: [tasks[0]], enabled: true).first)
        host.rootView = DashboardAIWorkContent(summary: single)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        await settle(host)
        let singleText = text(in: host)
        #expect(singleText.contains(tasks[0].title))
        #expect(singleText.contains("50%"), "A single task must retain its actual progress percentage")
        #expect(!singleText.contains(grouped.statusText(locale: language.locale)))
        #expect(!panel.isVisible, "Rendering contract tests must not show a window")
    }

    @MainActor
    private func settle(_ host: NSView) async {
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }

    @MainActor
    private func text(in object: NSObject) -> Set<String> {
        var strings = Set<String>()
        for key in ["accessibilityLabel", "accessibilityValue"]
        where object.responds(to: NSSelectorFromString(key)) {
            if let value = object.value(forKey: key) as? String { strings.insert(value) }
        }
        if object.responds(to: NSSelectorFromString("accessibilityChildren")) {
            for child in object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] {
                strings.formUnion(text(in: child))
            }
        }
        return strings
    }

    private func task(
        _ id: String, provider: AIProvider, status: AIProgressStatus = .running,
        title: String? = nil, progress: Double? = nil, updatedAt: TimeInterval = 10
    ) -> AIProgressTask {
        AIProgressTask(id: id, provider: provider, title: title ?? "Task \(id)", progress: progress,
                       status: status, updatedAt: Date(timeIntervalSince1970: updatedAt))
    }
}
