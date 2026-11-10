import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor @Suite(.serialized)
struct SystemMetricsHistorySettingsActionsTests {
    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic], [false, true])
    func buttonsFollowArchivedHistoryWithoutChangingRecording(language: AppLanguage, empty: Bool) async throws {
        let persistence = SettingsHistoryPersistence(records: empty ? [] : [
            SystemMetricsRecord(timestamp: Date(timeIntervalSince1970: 60), cpuUsage: 0.42),
        ])
        let service = SystemMonitorService(historyPersistence: persistence)
        let fixture = ActionsFixture(service: service, language: language)
        defer { fixture.close() }
        await fixture.layout()
        #expect(service.historyStats.count == (empty ? 0 : 1))

        let viewButton = try #require(fixture.button("查看历史记录"))
        #expect(try fixture.isEnabled("查看历史记录"))
        #expect(try fixture.isEnabled("导出") == !empty)
        #expect(try fixture.isEnabled("清空") == !empty)
        for key in ["查看历史记录", "导出", "清空"] {
            let button = try #require(fixture.button(key) as? any NSAccessibilityElementProtocol)
            let frame = fixture.host.convert(fixture.window.convertFromScreen(button.accessibilityFrame()), from: nil)
            #expect(frame.width > 0 && frame.height > 0)
            #expect(frame.minX >= 0 && frame.maxX <= fixture.host.bounds.width)
        }
        try fixture.press(viewButton)
        #expect(fixture.viewRequests == 1)
        #expect(persistence.loadRecords().count == (empty ? 0 : 1))

        service.clearHistory()
        await service.loadHistoryStats()
        await fixture.layout()

        #expect(try fixture.isEnabled("查看历史记录"))
        #expect(try !fixture.isEnabled("导出"))
        #expect(try !fixture.isEnabled("清空"))
        #expect(!service.isRecordingHistory)
        #expect(!fixture.window.isVisible)
    }

    @Test
    func historyWindowReloadsAfterAnotherEntryPointClearsTheArchive() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let now = Date(timeIntervalSince1970: 120)
        let service = SystemMonitorService(
            dateProvider: { now },
            historyPersistence: SettingsHistoryPersistence(records: [
                SystemMetricsRecord(timestamp: now.addingTimeInterval(-60), cpuUsage: 0.42),
            ])
        )
        let host = NSHostingView(rootView: SystemMetricsHistoryContent(service: service))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: CGRect(x: -100_000, y: -100_000, width: 720, height: 560),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        func displayedText(_ key: String) -> Bool {
            func descendants(_ object: NSObject) -> [NSObject] {
                let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
                    ? object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
                return [object] + children.flatMap(descendants)
            }
            return descendants(host).contains { object in
                ["accessibilityLabel", "accessibilityValue"].contains { attribute in
                    object.responds(to: NSSelectorFromString(attribute))
                        && object.value(forKey: attribute) as? String == AppLocalization.text(key)
                }
            }
        }
        func awaitText(_ key: String, removing staleKey: String? = nil) async {
            for _ in 0..<100 where !displayedText(key) || staleKey.map(displayedText) == true {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }
        await awaitText("CPU 利用率")
        #expect(displayedText("CPU 利用率"))

        service.clearHistory()
        await service.loadHistoryStats()
        await awaitText("暂无历史记录", removing: "CPU 利用率")

        #expect(displayedText("暂无历史记录"))
        #expect(!displayedText("CPU 利用率"))
        #expect(!window.isVisible)
    }

    @Test(arguments: [false, true])
    func exportWritesAllArchivedRecordsWithoutEnablingRecording(empty: Bool) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = empty ? [] : [
            SystemMetricsRecord(timestamp: Date(timeIntervalSince1970: 60), cpuUsage: 0.42),
            SystemMetricsRecord(timestamp: Date(timeIntervalSince1970: 120), cpuUsage: 0.75),
        ]
        let persistence = SettingsHistoryPersistence(records: records)
        let service = SystemMonitorService(volumeURL: directory, historyPersistence: persistence)
        let destination = directory.appendingPathComponent("history.xlsx")

        let message = await SystemMetricsHistoryExporter.write(service: service, to: destination)

        #expect(message == AppLocalization.text("已保存到 %@", destination.path))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", destination.path, "xl/worksheets/sheet1.xml"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let sheet = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(sheet.components(separatedBy: "<row ").count - 1 == records.count + 1)
        if !empty {
            #expect(sheet.contains("<v>0.42</v>"))
            #expect(sheet.contains("<v>0.75</v>"))
        }
        #expect(!service.isRecordingHistory)
        #expect(persistence.loadRecords() == records)
    }

    @Test
    func exportFailureKeepsHistoryAndExistingDestinationContents() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("history.xlsx", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let existingFile = destination.appendingPathComponent("existing.txt")
        let originalContents = Data("keep existing data".utf8)
        try originalContents.write(to: existingFile)
        let records = [SystemMetricsRecord(timestamp: Date(timeIntervalSince1970: 60), cpuUsage: 0.42)]
        let persistence = SettingsHistoryPersistence(records: records)
        let service = SystemMonitorService(volumeURL: directory, historyPersistence: persistence)

        let message = await SystemMetricsHistoryExporter.write(service: service, to: destination)

        #expect(message.hasPrefix(AppLocalization.text("导出失败：%@", "")))
        #expect(try Data(contentsOf: existingFile) == originalContents)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["history.xlsx"])
        #expect(persistence.loadRecords() == records)
        #expect(!service.isRecordingHistory)
    }

    @Test
    func clearRemovesArchivedRecordsWhileRecordingIsDisabled() async {
        let persistence = SettingsHistoryPersistence(records: [
            SystemMetricsRecord(timestamp: Date(timeIntervalSince1970: 60), cpuUsage: 0.42),
        ])
        let service = SystemMonitorService(historyPersistence: persistence)
        await service.loadHistoryStats()
        #expect(service.historyStats.count == 1)

        service.clearHistory()
        #expect(service.historyStats == .empty)
        await service.loadHistoryStats()

        #expect(persistence.loadRecords().isEmpty)
        #expect(await service.historySections(range: .all) == [])
        #expect(service.historyStats == .empty)
        #expect(!service.isRecordingHistory)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-history-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    @MainActor
    private final class ActionsFixture {
        let window: NSWindow
        let host: NSView
        let language: AppLanguage
        var viewRequests = 0
        private let releaseAccessibility: @MainActor () -> Void

        init(service: SystemMonitorService, language: AppLanguage) {
            self.language = language
            releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
            window = NSWindow(
                contentRect: CGRect(x: -100_000, y: -100_000, width: 540, height: 120),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            let view = NSHostingView(rootView: SystemMetricsHistorySettingsActions(
                service: service, onViewHistory: {}
            ).environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
            view.sizingOptions = []
            host = view
            window.contentView = view
            view.rootView = SystemMetricsHistorySettingsActions(
                service: service, onViewHistory: { [unowned self] in viewRequests += 1 }
            ).environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        }

        func layout() async {
            for _ in 0..<10 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }

        func button(_ key: String) -> NSObject? {
            func descendants(_ object: NSObject) -> [NSObject] {
                let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
                    ? object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
                return [object] + children.flatMap(descendants)
            }
            let title = AppLocalization.string(key, language: language)
            return descendants(host).first { object in
                object.responds(to: NSSelectorFromString("accessibilityRole"))
                    && object.value(forKey: "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue
                    && ["accessibilityLabel", "accessibilityTitle"].contains { attribute in
                        object.responds(to: NSSelectorFromString(attribute))
                            && object.value(forKey: attribute) as? String == title
                    }
            }
        }

        func isEnabled(_ key: String) throws -> Bool {
            try #require(button(key)?.value(forKey: "accessibilityEnabled") as? Bool)
        }

        func press(_ button: NSObject) throws {
            let action = NSSelectorFromString("accessibilityPerformPress")
            try #require(button.responds(to: action))
            button.performSelector(onMainThread: action, with: nil, waitUntilDone: true)
        }

        func close() {
            window.contentView = nil
            window.close()
            releaseAccessibility()
        }
    }
}

private final class SettingsHistoryPersistence: SystemMetricsHistoryPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [SystemMetricsRecord]

    init(records: [SystemMetricsRecord]) {
        self.records = records
    }

    func loadRecords() -> [SystemMetricsRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    func appendRecord(_ record: SystemMetricsRecord, capacity: Int?) {
        lock.lock()
        defer { lock.unlock() }
        records.append(record)
        if let capacity { records = Array(records.suffix(max(1, capacity))) }
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        records = []
    }
}
