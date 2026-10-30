import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingOutputDirectorySettingsTests {
    @Test(arguments: AppLanguage.allCases)
    func saveLocationIsSearchableInRecordingSettings(language: AppLanguage) throws {
        var settings = FeatureSettings.default
        settings.screenRecordingEnabled = true
        let title = AppLocalization.string("保存位置", language: language)
        let result = try #require(SettingsSearchIndex.results(for: title, settings: settings, locale: language.locale)
            .first { $0.section == .recording && $0.title == "保存位置" })
        #expect(result.anchor.localized(locale: language.locale) == .row(title))
    }

    @Test
    func settingsReflectTheStudioDirectoryAndRejectedChangesKeepTheExistingLocation() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let fixture = try Fixture()
        defer { fixture.close() }
        await fixture.settle()
        #expect(try fixture.path() == fixture.root.path(percentEncoded: false))
        let custom = fixture.root.appendingPathComponent("Custom directory", isDirectory: true)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: false)
        try fixture.model.setRecordingOutputDirectory(custom)
        await fixture.settle()
        #expect(try fixture.path() == custom.path(percentEncoded: false))
        #expect(fixture.model.directory == fixture.projectDirectory, "Changing the default location must leave the open project in place")
        let restored = ScreenRecordingOutputDirectoryStore(defaults: fixture.defaults)
        #expect(restored.directory.path == custom.path)

        #expect(throws: (any Error).self) {
            try fixture.model.setRecordingOutputDirectory(fixture.root.appendingPathComponent("missing", isDirectory: true))
        }
        await fixture.settle()
        #expect(try fixture.path() == custom.path(percentEncoded: false))
        #expect(fixture.model.projectStore.root.path == custom.path)
        #expect(fixture.window.isVisible == false)
    }

    @Test
    func settingsDisableDirectoryChangesWhileChoosingAnOutputAndRestoreThemOnCancel() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let fixture = try Fixture()
        defer { fixture.close() }
        await fixture.settle()
        #expect(try fixture.chooseButtonEnabled())
        fixture.model.export()
        await fixture.settle()
        #expect(fixture.model.isChoosingFile)
        #expect(try !fixture.chooseButtonEnabled())
        let completion = try #require(fixture.completeOutputPanel)
        completion(nil)
        await fixture.settle()
        #expect(!fixture.model.isChoosingFile)
        #expect(try fixture.chooseButtonEnabled())
        #expect(try fixture.path() == fixture.root.path(percentEncoded: false))
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let projectDirectory: URL
        let defaults: UserDefaults
        let suite: String
        let model: ScreenRecordingStudioModel
        let window: NSWindow
        let host: NSHostingView<ScreenRecordingOutputDirectorySettingsView>
        var completeOutputPanel: ((URL?) -> Void)?

        init() throws {
            suite = "zisla-recording-settings-test-\(UUID())"
            defaults = try #require(UserDefaults(suiteName: suite))
            root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            let store = ScreenRecordingProjectStore(root: root)
            projectDirectory = try store.createDirectory()
            try Data([1]).write(to: projectDirectory.appendingPathComponent("screen.mp4"))
            let project = ScreenRecordingProject(name: "Settings", videoFile: "screen.mp4", duration: 5, width: 64, height: 48)
            try store.save(project, in: projectDirectory)
            let panel = OutputPanel()
            model = ScreenRecordingStudioModel(projectStore: store,
                outputDirectoryStore: ScreenRecordingOutputDirectoryStore(defaults: defaults),
                renderPreview: { _, _, _ in throw ScreenRecordingExportError.cannotRender },
                presentExportPanel: { _, completion in panel.complete = completion })
            model.install(project, directory: projectDirectory)
            host = NSHostingView(rootView: ScreenRecordingOutputDirectorySettingsView(model: model))
            window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 440, height: 70),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            completeOutputPanel = { url in panel.complete?(url) }
        }

        func settle() async {
            for _ in 0..<5 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
        }

        func path() throws -> String {
            let element = try #require(self.element("screenRecording.settingsSaveDirectory"))
            return try #require(element.value(forKey: "accessibilityValue") as? String)
        }

        func chooseButtonEnabled() throws -> Bool {
            let element = try #require(self.element("screenRecording.chooseSaveDirectory"))
            return try #require(element.value(forKey: "accessibilityEnabled") as? Bool)
        }

        private func element(_ identifier: String) -> NSObject? {
            func visit(_ object: NSObject) -> NSObject? {
                if object.responds(to: NSSelectorFromString("accessibilityIdentifier")),
                   object.value(forKey: "accessibilityIdentifier") as? String == identifier { return object }
                guard object.responds(to: NSSelectorFromString("accessibilityChildren")) else { return nil }
                for child in object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] {
                    if let result = visit(child) { return result }
                }
                return nil
            }
            return visit(host)
        }

        func close() {
            completeOutputPanel = nil
            model.shutdown()
            window.contentView = nil
            window.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private final class OutputPanel {
        var complete: ((URL?) -> Void)?
    }
}
