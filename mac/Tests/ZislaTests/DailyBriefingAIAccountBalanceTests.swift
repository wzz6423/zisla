import AppKit
import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct DailyBriefingAIAccountBalanceTests {
    @Test func quotaIsIndependentSelectedAndDebugOrUnavailableDataDoesNotAllocateSection() throws {
        let date = Date(timeIntervalSince1970: 1_910_000_000)
        var report = DailyBriefingReport(day: DailyBriefingDay(date: date, calendar: DailyBriefingDay.calendar), generatedAt: date, typing: nil,
            allDeviceSeconds: nil, selectedContent: [.aiAccountBalances])
        #expect(report.aiAccountBalances.isEmpty)
        #expect(DailyBriefingPoster(report: report, template: .minimal, language: .english).displayedContent.isEmpty)
        var reading = balance(date)
        report.aiAccountBalances = [reading]
        #expect(DailyBriefingPoster(report: report, template: .minimal, language: .english).displayedContent == [.aiAccountBalances])
        #expect(DailyBriefingContent.aiAccountBalances.group == .zisla && !DailyBriefingContent.aiAccountBalances.isDetailMetric)
        report.selectedContent = []
        #expect(DailyBriefingPoster(report: report, template: .minimal, language: .english).displayedContent.isEmpty)
        report.selectedContent = [.aiAccountBalances]
        reading.isDebug = true; report.aiAccountBalances = [reading]
        #expect(DailyBriefingPoster(report: report, template: .minimal, language: .english).displayedContent.isEmpty)
        reading.isDebug = false; reading.status = .unavailable; report.aiAccountBalances = [reading]
        #expect(DailyBriefingPoster(report: report, template: .minimal, language: .english).displayedContent.isEmpty)
    }

    @Test func currentQuotaKeepsItsSamplingTimestampWhenExportingAnOlderDay() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-balance-briefing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let selectedDay = Date(timeIntervalSince1970: 1_900_000_000), sampleDate = Date(timeIntervalSince1970: 1_910_000_000)
        let reading = balance(sampleDate)
        var reports: [DailyBriefingReport] = []
        let controller = DailyBriefingController(store: DailyBriefingStore(fileURL: root.appendingPathComponent("history.json")),
            observation: { .init(date: $0, applicationID: "fixture", applicationName: "Fixture", category: .work, isActive: false, isListening: false) },
            aiAccountBalances: { [reading] }, typing: { _ in nil }, readScreenTime: { _ in .init() },
            export: { report, _, _, directory in reports.append(report); return directory.appendingPathComponent("fixture.png") })
        controller.configure(settings: .init(enabled: true, selectedContent: [.aiAccountBalances]), directory: root, language: .english, startsTimer: false)
        await controller.exportToday(at: selectedDay)
        let report = try #require(reports.first)
        #expect(report.aiAccountBalances.first?.updatedAt == sampleDate)
        #expect(report.day.date != sampleDate)
        let text = DailyBriefingAIAccountBalanceSection(balances: report.aiAccountBalances, language: .english, ink: .black)
        #expect(text.rows.count == 1)
        let actual = try DailyBriefingRenderer.image(report: report, template: .minimal, language: .english, scale: 0.25)
        var old = report
        old.selectedContent = []
        let empty = try DailyBriefingRenderer.image(report: old, template: .minimal, language: .english, scale: 0.25)
        #expect(actual.height > empty.height)
    }

    private func balance(_ sampledAt: Date) -> AIAccountBalance {
        .init(id: "fixture", providers: [.gpt], status: .available,
            windows: [.init(id: "rolling", kind: .rolling, remainingPercent: 10)], updatedAt: sampledAt)
    }
}
