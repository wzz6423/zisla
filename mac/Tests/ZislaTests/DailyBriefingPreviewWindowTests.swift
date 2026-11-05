import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct DailyBriefingPreviewWindowTests {
    @Test
    func previewUsesNativeWindowControls() throws {
        let controller = DailyBriefingPreviewWindowController()
        let window = try #require(controller.window)
        defer { window.contentView = nil; controller.close() }

        #expect(!(window is NSPanel))
        #expect(window.styleMask == [.titled, .closable, .miniaturizable, .resizable])
        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            let button = try #require(window.standardWindowButton(buttonType))
            #expect(!button.isHidden)
            #expect(button.isEnabled)
            #expect(button.superview != nil)
        }
        #expect(window.titleVisibility == .visible)
        #expect(!window.titlebarAppearsTransparent)
        #expect(window.sheetParent == nil)
        #expect(window.level == .normal)
        #expect(!window.isReleasedWhenClosed)
        #expect(window.contentMinSize == NSSize(width: 360, height: 320))
    }

    @Test(arguments: [NSSize(width: 360, height: 320), NSSize(width: 600, height: 760), NSSize(width: 1_200, height: 900)])
    func previewContentFitsTheResizableViewport(viewport: NSSize) {
        let content = NSHostingController(rootView: DailyBriefingPreview(template: .minimal, language: .english))
        let size = content.sizeThatFits(in: viewport)

        #expect(size.width == viewport.width)
        #expect(size.height == viewport.height)
    }

    @Test(arguments: AppLanguage.allCases)
    func previewUpdatesTemplateAndLanguageInTheSameWindow(language: AppLanguage) throws {
        let controller = DailyBriefingPreviewWindowController()
        let window = try #require(controller.window)
        defer { window.contentView = nil; controller.close() }

        for template in DailyBriefingTemplate.allCases {
            controller.update(template: template, language: language)

            #expect(controller.window === window)
            #expect(window.title == AppLocalization.string("每日简报", language: language)
                + " · " + AppLocalization.string(template.title, language: language))
            let content = try #require(window.contentView as? NSHostingView<DailyBriefingPreview>)
            #expect(content.rootView.template == template)
            #expect(content.rootView.language == language)
            #expect(window.sheetParent == nil)
        }
    }

    @Test
    func closingAndPreparingAnotherPreviewKeepsAReusableNativeWindow() throws {
        let controller = DailyBriefingPreviewWindowController()
        let window = try #require(controller.window)
        defer { window.contentView = nil; controller.close() }
        controller.update(template: .minimal, language: .english)
        let previousContent = window.contentView

        window.performClose(nil)
        controller.update(template: .terminal, language: .arabic)

        #expect(controller.window === window)
        #expect(!window.isVisible)
        #expect(window.contentView !== previousContent)
        let content = try #require(window.contentView as? NSHostingView<DailyBriefingPreview>)
        #expect(content.rootView.template == .terminal)
        #expect(content.rootView.language == .arabic)
        #expect(window.title == "التقرير اليومي · طرفية")
    }

    @Test
    func settingsRoutePreviewToTheWindowWithoutASheetOrCustomCloseBar() throws {
        let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/DailyBriefingSettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(!source.contains(".sheet("))
        #expect(!source.contains(#"AppLocalizedText("关闭")"#))
        #expect(source.contains("previewWindowController ?? DailyBriefingPreviewWindowController()"))
        #expect(source.contains("previewWindowController = preview"))
        #expect(source.contains("preview.update(template: settingsStore.settings.dailyBriefing.template, language: language)"))
        #expect(source.contains("preview.showWindow(nil)"))
    }
}
