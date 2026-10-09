import AppKit
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenshotImageExportTests {
    @Test(arguments: [false, true], [false, true])
    func savesIndependentlyAtScreenCenterWithSystemAppearance(systemIsDark: Bool, appIsDark: Bool) async throws {
        _ = NSApplication.shared
        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: appIsDark ? .darkAqua : .aqua)
        defer { NSApp.appearance = previousAppearance }
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.preferences.set(systemIsDark ? "Dark" : "Light", forKey: "AppleInterfaceStyle")
        let screen = try #require(WindowPlacement.screenUnderMouse())
        let island = IslandPanel(contentView: NSView(), frame: CGRect(x: -100_000, y: -100_000, width: 436, height: 500))
        island.allowsKeyWindow = true
        island.alphaValue = 0
        island.orderFrontRegardless()
        island.makeKey()
        defer { island.close() }
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(island.frame) })
        #expect(NSApp.keyWindow === island)

        let message: String? = await withCheckedContinuation { continuation in
            ScreenshotImageExport.presentSavePanel(for: Self.png, panel: fixture.panel,
                systemPreferences: fixture.preferences, themeNotifications: fixture.notifications) {
                continuation.resume(returning: $0)
            }
            #expect(fixture.panel.presentedStandalone)
            #expect(fixture.panel.presentedSheetParent == nil)
            #expect(island.attachedSheet == nil)
            #expect(abs(fixture.panel.frame.midX - screen.visibleFrame.midX) <= 1)
            #expect(abs(fixture.panel.frame.midY - screen.visibleFrame.midY) <= 1)
            #expect(fixture.panel.level.rawValue > island.level.rawValue)
            #expect(fixture.panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == (systemIsDark ? .darkAqua : .aqua))
            #expect(NSApp.appearance?.name == (appIsDark ? .darkAqua : .aqua))
            #expect(island.appearance?.name == .darkAqua)
            #expect(fixture.panel.allowedContentTypes == [.png])
            #expect(fixture.panel.canCreateDirectories)
            #expect(fixture.panel.nameFieldStringValue == AppLocalization.text("截图.png"))
            fixture.panel.respond(.cancel)
        }
        #expect(message == nil)
    }

    @Test
    func followsSystemChangesWhileOpenAndStopsObservingWhenClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let message: String? = await withCheckedContinuation { continuation in
            ScreenshotImageExport.presentSavePanel(for: Self.png, panel: fixture.panel,
                systemPreferences: fixture.preferences, themeNotifications: fixture.notifications) {
                continuation.resume(returning: $0)
            }
            for isDark in [false, true, false] {
                fixture.preferences.set(isDark ? "Dark" : "Light", forKey: "AppleInterfaceStyle")
                fixture.notifications.post(name: Self.themeChanged, object: nil)
                #expect(fixture.panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == (isDark ? .darkAqua : .aqua))
            }
            fixture.panel.respond(.cancel)
        }
        #expect(message == nil)
        fixture.preferences.set("Dark", forKey: "AppleInterfaceStyle")
        fixture.notifications.post(name: Self.themeChanged, object: nil)
        #expect(fixture.panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
    }

    @Test(arguments: ["save", "cancel", "abort", "missing URL", "write failure"])
    func writesPNGOrPreservesDestinationOnCancellationAndFailure(outcome: String) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let destination = fixture.directory.appendingPathComponent("screenshot.png")
        let original = Data("existing destination".utf8)
        try original.write(to: destination)
        fixture.panel.selectedURL = outcome == "missing URL" ? nil : outcome == "write failure"
            ? fixture.directory.appendingPathComponent("missing/screenshot.png") : destination
        let response: NSApplication.ModalResponse = outcome == "cancel" ? .cancel : outcome == "abort" ? .abort : .OK
        let message: String? = await withCheckedContinuation { continuation in
            ScreenshotImageExport.presentSavePanel(for: Self.png, panel: fixture.panel,
                systemPreferences: fixture.preferences, themeNotifications: fixture.notifications) {
                continuation.resume(returning: $0)
            }
            fixture.panel.respond(response)
        }
        #expect(try Data(contentsOf: destination) == (outcome == "save" ? Self.png : original))
        if outcome == "save" {
            #expect(message == AppLocalization.text("已保存：%@", destination.lastPathComponent))
        } else if outcome == "write failure" {
            #expect(message?.hasPrefix(AppLocalization.text("保存失败：%@", "")) == true)
        } else {
            #expect(message == nil)
        }
        fixture.preferences.set("Dark", forKey: "AppleInterfaceStyle")
        fixture.notifications.post(name: Self.themeChanged, object: nil)
        #expect(fixture.panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
    }

    private static let themeChanged = Notification.Name("AppleInterfaceThemeChangedNotification")
    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aF9sAAAAASUVORK5CYII=")!

    @MainActor
    private final class Fixture {
        let directory: URL
        let preferences: UserDefaults
        let preferencesName = "zisla-save-panel-tests-\(UUID())"
        let notifications = NotificationCenter()
        let panel = SavePanel()

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-save-panel-tests-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            preferences = try #require(UserDefaults(suiteName: preferencesName))
            preferences.set("Light", forKey: "AppleInterfaceStyle")
            panel.directoryURL = directory
            panel.isReleasedWhenClosed = false
        }

        func close() {
            panel.close()
            preferences.removePersistentDomain(forName: preferencesName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private final class SavePanel: NSSavePanel {
        var presentedStandalone = false
        var presentedSheetParent: NSWindow?
        var selectedURL: URL?
        private var completion: ((NSApplication.ModalResponse) -> Void)?

        override var url: URL? { selectedURL }

        override func begin(completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
            presentedStandalone = true
            completion = handler
        }

        override func beginSheetModal(for window: NSWindow, completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
            presentedSheetParent = window
            completion = handler
        }

        func respond(_ response: NSApplication.ModalResponse) {
            let handler = completion
            completion = nil
            handler?(response)
        }
    }
}
