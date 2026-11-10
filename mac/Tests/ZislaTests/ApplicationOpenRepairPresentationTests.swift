import AppKit
import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct ApplicationOpenRepairPresentationTests {
    @Test
    func clipboardRepairKeepsExactlyOneAction() throws {
        let url = URL(fileURLWithPath: "/tmp/Example.app")
        let content = ClipboardHistoryContent.file(ClipboardFileReference(url: url, displayName: "Example.app", bookmark: Data()))
        let detection = ClipboardAssistantDetection(kind: .appCannotOpen, title: "Example.app", actions: [.repairAndOpenApp(url)])
        let result = AppModel.augmentedClipboardAssistantDetection(detection, content: content,
            sourceApplication: NSRunningApplication.current, orders: FeatureSettings.default.clipboardAssistantActionOrders)
        #expect(result.actions == [.repairAndOpenApp(url)])
        #expect(result == detection)
    }

    @Test
    func shelfDropWaitsForTheIslandToCollapseAndShowsOnce() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let controller = makeController()
        let availability = PresentationAvailability()
        var settings = FeatureSettings.default
        settings.clipboardAssistantEnabled = true
        settings.clipboardAssistantDisplayDuration = .never
        let presenter = ApplicationOpenRepairPresenter(controller: controller, settings: { settings }, canPresent: { availability.canPresent })

        presenter.receive([fixture.app])
        await presenter.task?.value
        #expect(controller.presentation.detection == nil)
        availability.canPresent = true
        presenter.flush()
        let result = try #require(controller.presentation.detection)
        #expect(result.kind == .appCannotOpen)
        #expect(result.actions == [.repairAndOpenApp(fixture.app.standardizedFileURL)])
        #expect(result.detail == .localizedMessage("应用无法打开"))
        controller.dismiss(animated: false)
        presenter.flush()
        #expect(controller.presentation.detection == nil)
    }

    @Test
    func collapseDuringInspectionDoesNotLoseTheDrop() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let controller = makeController()
        let availability = PresentationAvailability()
        var settings = FeatureSettings.default
        settings.clipboardAssistantEnabled = true
        let presenter = ApplicationOpenRepairPresenter(controller: controller, settings: { settings }, canPresent: { availability.canPresent })
        presenter.receive([fixture.app])
        availability.canPresent = true
        presenter.flush()
        await presenter.task?.value
        #expect(controller.presentation.detection?.kind == .appCannotOpen)
    }

    @Test
    func disablingRepairDiscardsAPendingPrompt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let controller = makeController()
        var settings = FeatureSettings.default
        settings.clipboardAssistantEnabled = true
        let availability = PresentationAvailability()
        let presenter = ApplicationOpenRepairPresenter(controller: controller, settings: { settings }, canPresent: { availability.canPresent })
        presenter.receive([fixture.app])
        await presenter.task?.value
        settings.clipboardAssistantEnabledKinds.remove(.appCannotOpen)
        availability.canPresent = true
        presenter.flush()
        #expect(controller.presentation.detection == nil)
        settings.clipboardAssistantEnabledKinds.insert(.appCannotOpen)
        presenter.flush()
        #expect(controller.presentation.detection == nil)
    }

    @Test
    func cancellationDiscardsTheDropAndQueuedPrompt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let controller = makeController()
        var settings = FeatureSettings.default
        settings.clipboardAssistantEnabled = true
        let availability = PresentationAvailability()
        let presenter = ApplicationOpenRepairPresenter(controller: controller, settings: { settings }, canPresent: { availability.canPresent })
        for finishInspection in [false, true] {
            presenter.receive([fixture.app])
            let task = presenter.task
            if finishInspection { await task?.value }
            presenter.cancel()
            await task?.value
            availability.canPresent = true
            presenter.flush()
            #expect(presenter.task == nil)
            #expect(controller.presentation.detection == nil)
            availability.canPresent = false
        }
    }

    @Test
    func disablingQuickActionsDuringInspectionSuppressesThePrompt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let controller = makeController()
        var settings = FeatureSettings.default
        settings.clipboardAssistantEnabled = true
        let presenter = ApplicationOpenRepairPresenter(controller: controller, settings: { settings }, canPresent: { true })
        presenter.receive([fixture.app])
        settings.clipboardAssistantEnabled = false
        await presenter.task?.value
        #expect(controller.presentation.detection == nil)
    }

    @Test
    func systemMonitoringOptOutDiscardsItsQueuedPromptButAllowsDrops() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let controller = makeController()
        var settings = FeatureSettings.default
        settings.applicationOpenFailureMonitoringEnabled = true
        let availability = PresentationAvailability()
        let presenter = ApplicationOpenRepairPresenter(controller: controller, settings: { settings }, canPresent: { availability.canPresent })
        presenter.receive([fixture.app], fromSystemAlert: true)
        await presenter.task?.value
        settings.applicationOpenFailureMonitoringEnabled = false
        availability.canPresent = true
        presenter.flush()
        #expect(controller.presentation.detection == nil)
        presenter.receive([fixture.app], fromSystemAlert: true)
        await presenter.task?.value
        #expect(controller.presentation.detection == nil)
        presenter.receive([fixture.app])
        await presenter.task?.value
        #expect(controller.presentation.detection?.kind == .appCannotOpen)
    }

    private final class PresentationAvailability {
        var canPresent = false
    }

    @Test
    func latestDropSupersedesAnOlderQueuedPrompt() async throws {
        let first = try Fixture(name: "First.app")
        let second = try Fixture(name: "Second.app")
        defer { first.remove(); second.remove() }
        let controller = makeController()
        var settings = FeatureSettings.default
        settings.clipboardAssistantEnabled = true
        let presenter = ApplicationOpenRepairPresenter(controller: controller, settings: { settings }, canPresent: { true })
        presenter.receive([first.app])
        presenter.receive([second.app])
        await presenter.task?.value
        #expect(controller.presentation.detection?.title == "Second.app")
        #expect(controller.presentation.detection?.actions == [.repairAndOpenApp(second.app.standardizedFileURL)])
    }

    @Test
    func normalFileDropsAndDisabledRepairDoNotPrompt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let controller = makeController()
        var settings = FeatureSettings.default
        settings.clipboardAssistantEnabled = true
        let presenter = ApplicationOpenRepairPresenter(controller: controller, settings: { settings }, canPresent: { true })
        for urls in [[], [fixture.directory.appendingPathComponent("not-app.txt")]] {
            presenter.receive(urls)
            await presenter.task?.value
            #expect(controller.presentation.detection == nil)
        }
        settings.clipboardAssistantEnabledKinds.remove(.appCannotOpen)
        presenter.receive([fixture.app])
        await presenter.task?.value
        #expect(controller.presentation.detection == nil)
        settings.clipboardAssistantEnabledKinds = []
        presenter.receive([fixture.app])
        await presenter.task?.value
        #expect(controller.presentation.detection?.kind == .appCannotOpen)
    }

    @Test
    func repairActionWaitsForAnExplicitClickAndFiresOnce() throws {
        let controller = makeController()
        let url = URL(fileURLWithPath: "/tmp/Example.app")
        var actions: [ClipboardAssistantAction] = []
        controller.onPerformAction = { actions.append($0) }
        controller.present(ClipboardAssistantDetection(kind: .appCannotOpen, title: "Example.app", actions: [.repairAndOpenApp(url)]), visualStyle: .transparent)
        #expect(actions.isEmpty)
        controller.perform(.repairAndOpenApp(url))
        controller.perform(.repairAndOpenApp(url))
        #expect(actions == [.repairAndOpenApp(url)])
    }

    @Test
    func helpExplainsTheRealFileTriggersAndTheOnlyAction() throws {
        let groups = try #require(SettingsView.clipboardAssistantExampleGroups[.appCannotOpen])
        let group = try #require(groups.first)
        #expect(groups.count == 1)
        #expect(group.examples.isEmpty)
        #expect(group.instructions.count == 4)
        #expect(group.instructions[0].contains(".app") && group.instructions[0].contains("复制") && group.instructions[0].contains("中转站"))
        #expect(group.instructions[1].contains("解决并打开"))
        #expect(SettingsView.clipboardAssistantActionTitle(.repairAndOpenApp) == "解决并打开")
        #expect(ClipboardAssistantToastView.actionLabel(.repairAndOpenApp(URL(fileURLWithPath: "/tmp/Example.app"))) == "解决并打开")
    }

    @Test
    func repairHelpAndErrorsTranslateInEveryLanguage() throws {
        let groups = try #require(SettingsView.clipboardAssistantExampleGroups[.appCannotOpen])
        let errors: [ApplicationOpenRepairError] = [.invalidApplication, .protectedApplication, .readOnly,
            .unsupportedBundle, .inspectionLimit, .readFailed, .applicationChanged, .signatureInvalid,
            .assessmentRejected, .assessmentUnavailable, .quarantineRemovalFailed, .openFailed]
        let keys = ["应用无法打开", "解决并打开", "系统打不开应用时提醒", "需要辅助功能权限；通过系统窗口事件提醒，不定时扫描"]
            + groups.flatMap { [$0.title] + $0.instructions }
            + errors.map(\.localizationKey)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Localization")
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let table = try #require(NSDictionary(contentsOf: root.appendingPathComponent("\(language.rawValue).lproj/Localizable.strings")) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
                #expect(!value.isEmpty)
                #expect(AppLocalization.string(key, language: language) == value)
                if language != .simplifiedChinese { #expect(value != key) }
                if language != .english { #expect(value != AppLocalization.string(key, language: .english)) }
            }
            #expect(ClipboardAssistantToastView.detailText(.localizedMessage("应用无法打开"), locale: language.locale) == table["应用无法打开"])
            var settings = FeatureSettings.default
            settings.clipboardAssistantEnabled = true
            #expect(SettingsSearchIndex.results(for: AppLocalization.string("应用无法打开", language: language),
                settings: settings, locale: language.locale).contains { $0.section == .clipboardAssistant })
        }
        #expect(AppLocalization.string("解决并打开", language: .english) == "Fix and Open")
        #expect(AppLocalization.string("应用无法打开", language: .arabic) == "تعذّر فتح التطبيق")
    }

    private func makeController() -> ClipboardAssistantController {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        controller.displayDuration = .never
        return controller
    }

    private struct Fixture {
        let directory: URL
        let app: URL
        init(name: String = "Example.app") throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-repair-presentation-\(UUID().uuidString)")
            app = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            let data = Data("0081;00000000;ZislaTest;".utf8)
            try #require(data.withUnsafeBytes { setxattr(app.path, "com.apple.quarantine", $0.baseAddress, $0.count, 0, 0) } == 0)
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
}
