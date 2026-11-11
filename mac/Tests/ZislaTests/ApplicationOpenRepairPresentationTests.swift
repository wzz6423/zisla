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
    func copiedApplicationReachesTheSingleActionThroughTheClipboardMonitor() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pasteboard = NSPasteboard(name: .init("dev.zisla.tests.repair.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var captured: [ClipboardHistoryContent] = []
        let monitor = ClipboardHistoryMonitor(pasteboard: pasteboard) { captured.append($0) }
        monitor.setEnabled(true)
        defer { monitor.setEnabled(false) }
        #expect(FileShelfPasteboard.writeFileURLs([fixture.app], to: pasteboard))
        monitor.pollNow()
        monitor.pollNow()
        #expect(captured.count == 1)
        let content = try #require(captured.first)
        let detection = try #require(await ClipboardAssistantDetector.detectInBackground(
            content: content, enabledKinds: Set(ClipboardAssistantKind.allCases)))
        let result = AppModel.augmentedClipboardAssistantDetection(detection, content: content,
            sourceApplication: NSRunningApplication.current, orders: FeatureSettings.default.clipboardAssistantActionOrders)
        #expect(result.actions == [.repairAndOpenApp(fixture.app.standardizedFileURL)])
        #expect(result.kind == .appCannotOpen)
        #expect(getxattr(fixture.app.path, "com.apple.quarantine", nil, 0, 0, 0) > 0)
    }

    @Test
    func nativeShelfDropKeepsTheAppAndQueuesItsRepairPrompt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pasteboard = NSPasteboard(name: .init("dev.zisla.tests.repair-drop.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let store = FileShelfStore(storageURL: fixture.directory.appendingPathComponent("shelf.json"))
        let controller = makeController()
        let availability = PresentationAvailability()
        let presenter = ApplicationOpenRepairPresenter(controller: controller, settings: { .default },
            canPresent: { availability.canPresent })
        #expect(FileShelfPasteboard.writeFileURLs([fixture.app], to: pasteboard))
        var added = 0
        store.receive(TransferPasteboard.readShelfDropItems(from: pasteboard)) { count in
            added = count
            presenter.receive(store.items.map(\.url))
        }
        #expect(added == 1)
        #expect(store.items.map(\.url) == [fixture.app.standardizedFileURL])
        await presenter.task?.value
        #expect(controller.presentation.detection == nil)
        availability.canPresent = true
        presenter.flush()
        #expect(controller.presentation.detection?.actions == [.repairAndOpenApp(fixture.app.standardizedFileURL)])
        #expect(getxattr(fixture.app.path, "com.apple.quarantine", nil, 0, 0, 0) > 0)
    }

    @Test
    func promisedApplicationCopyKeepsQuarantineAndPromptsForTheManagedCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = FileShelfStore(storageURL: fixture.directory.appendingPathComponent("shelf.json"))
        let receiver = ApplicationPromiseReceiver(app: fixture.app)
        let controller = makeController()
        let presenter = ApplicationOpenRepairPresenter(controller: controller, settings: { .default }, canPresent: { true })
        var added = 0
        store.receive([.promise(receiver)]) { count in
            added = count
            presenter.receive(store.items.map(\.url))
        }
        #expect(added == 0 && controller.presentation.detection == nil)
        try receiver.deliver()
        #expect(added == 1)
        let item = try #require(store.items.first)
        #expect(item.isManaged && item.url != fixture.app.standardizedFileURL)
        #expect(item.url.pathExtension == "app")
        #expect(getxattr(item.url.path, "com.apple.quarantine", nil, 0, 0, 0) > 0)
        await presenter.task?.value
        #expect(controller.presentation.detection?.actions == [.repairAndOpenApp(item.url.standardizedFileURL)])
        #expect(getxattr(fixture.app.path, "com.apple.quarantine", nil, 0, 0, 0) > 0)
        #expect(!FileManager.default.fileExists(atPath: try #require(receiver.destination).path))
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
    func unrelatedShelfDropsPreserveQueuedRepairPrompts() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let unrelated: [[URL]] = [[], [fixture.directory.appendingPathComponent("readme.txt")],
            [URL(string: "https://example.com/Other.app")!]]
        for fromSystemAlert in [false, true] {
            for urls in unrelated {
                let controller = makeController()
                let availability = PresentationAvailability()
                var settings = FeatureSettings.default
                settings.applicationOpenFailureMonitoringEnabled = true
                let presenter = ApplicationOpenRepairPresenter(controller: controller, settings: { settings },
                    canPresent: { availability.canPresent })
                presenter.receive([fixture.app], fromSystemAlert: fromSystemAlert)
                await presenter.task?.value
                presenter.receive(urls)
                await presenter.task?.value
                #expect(controller.presentation.detection == nil)
                availability.canPresent = true
                presenter.flush()
                #expect(controller.presentation.detection?.actions == [.repairAndOpenApp(fixture.app.standardizedFileURL)],
                    "Unrelated drop \(urls) must preserve the queued repair prompt")
            }
        }
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

    private final class ApplicationPromiseReceiver: NSFilePromiseReceiver, @unchecked Sendable {
        private let app: URL
        private var reader: ((URL, Error?) -> Void)?
        private(set) var destination: URL?

        init(app: URL) { self.app = app; super.init() }
        required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) { nil }
        override var fileNames: [String] { [app.lastPathComponent] }
        override func receivePromisedFiles(atDestination destinationDir: URL, options: [AnyHashable: Any] = [:],
                                          operationQueue: OperationQueue, reader: @escaping (URL, Error?) -> Void) {
            destination = destinationDir
            self.reader = reader
        }

        func deliver() throws {
            let url = try #require(destination).appendingPathComponent(app.lastPathComponent)
            try FileManager.default.copyItem(at: app, to: url)
            reader?(url, nil)
        }
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
