import AppKit
import Foundation
import Sparkle
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct UpdateReleaseNotesPresentationTests {
    @Test(arguments: [SPUUserUpdateStage.notDownloaded, .downloaded, .installing])
    func preservesSparklesAvailableUpdateActions(stage: SPUUserUpdateStage) {
        let presentation = UpdateReleaseNotesPresentation.available(stage: stage, critical: false, informationURL: nil)
        #expect(presentation.titleKey == "发现新版本 %@")
        #expect(presentation.installKey == (stage == .installing ? "安装并重新启动" : "安装更新"))
        #expect(presentation.dismissKey == (stage == .installing ? "退出时安装" : "稍后提醒"))
        #expect(presentation.allowsSkipping)
        #expect(presentation.allowsDeferral)
    }

    @Test
    func completedUpdatesOnlyOfferClosingTheNotes() {
        let presentation = UpdateReleaseNotesPresentation.installed
        #expect(presentation.titleKey == "已更新至 %@")
        #expect(presentation.installKey == nil)
        #expect(presentation.dismissKey == "关闭")
        #expect(!presentation.allowsSkipping)
        #expect(presentation.allowsDeferral)
    }

    @Test
    func criticalUpdatesCannotBeSkippedAndInformationalUpdatesCannotInstall() throws {
        let critical = UpdateReleaseNotesPresentation.available(stage: .notDownloaded, critical: true, informationURL: nil)
        #expect(!critical.allowsSkipping)
        #expect(!critical.allowsDeferral)
        let url = try #require(URL(string: "https://github.com/wzz6423/zisla/releases"))
        #expect(UpdateReleaseNotesPresentation.available(stage: .notDownloaded, critical: false, informationURL: url).installKey == "了解更多")
    }

    @Test
    @MainActor
    func releaseNotesOnlyOpenWebAndMailLinks() throws {
        let coordinator = MarkdownWebView.Coordinator(allowedLinkSchemes: ["https", "http", "mailto"])
        for scheme in ["file", "javascript", "data", "zisla", "x-apple.systempreferences"] {
            #expect(!coordinator.allowsExternalLink(try #require(URL(string: "\(scheme):test"))))
        }
        for scheme in ["https", "http", "mailto"] {
            #expect(coordinator.allowsExternalLink(try #require(URL(string: "\(scheme):test"))))
        }
        #expect(MarkdownWebView.Coordinator().allowsExternalLink(try #require(URL(string: "zisla:test"))))
    }

    @Test
    func everyLanguageTranslatesTheReleaseNotesControls() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let keys = [
            "更新日志", "已更新至 %@", "正在加载更新日志", "无法加载更新日志", "查看发布页面",
            "安装更新", "安装并重新启动", "退出时安装", "稍后提醒", "跳过此版本", "了解更多",
            "发现新版本 %@", "关闭", "重试",
        ]
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/UpdateReleaseNotesWindow.swift"), encoding: .utf8)
        let callPattern = try NSRegularExpression(pattern: #"AppLocalized(?:Format)?Text\("([^"]+)""#)
        let directKeys = try callPattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
            String(source[try #require(Range($0.range(at: 1), in: source))])
        }
        #expect(Set(directKeys).isSubset(of: Set(keys)))
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let url = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for key in keys {
                let translated = try #require(table[key], "\(language.rawValue) is missing \(key)")
                #expect(!translated.isEmpty)
                #expect(translated.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count)
                #expect(AppLocalization.string(key, language: language) == translated)
                if language != .simplifiedChinese && language != .traditionalChinese {
                    #expect(translated != key)
                }
            }
        }
    }

    @Test
    @MainActor
    func windowActionsReplyOnlyOnceAndProgrammaticDismissalDoesNotChoose() throws {
        let suite = "zisla-release-notes-window-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = UpdateReleaseNotesModel(
            release: UpdateRelease(version: "1.2.3", build: "23", tagName: "v1.2.3"),
            preference: .githubFirst,
            notes: UpdateReleaseNotes(markdown: "# Notes", releaseURL: URL(string: "https://github.com/wzz6423/zisla/releases/tag/v1.2.3")!)
        )
        var replies: [SPUUserUpdateChoice] = []
        let window = UpdateReleaseNotesWindowController(
            model: model,
            presentation: .installed,
            languageStore: AppLanguageStore(defaults: defaults),
            reply: { replies.append($0) }
        )
        window.finish(.install)
        window.finish(.skip)
        #expect(replies == [.install])
        let dismissed = UpdateReleaseNotesWindowController(
            model: model,
            presentation: .installed,
            languageStore: AppLanguageStore(defaults: defaults),
            reply: { replies.append($0) }
        )
        dismissed.dismiss()
        dismissed.finish(.dismiss)
        #expect(replies == [.install])

        let closed = UpdateReleaseNotesWindowController(
            model: model,
            presentation: .installed,
            languageStore: AppLanguageStore(defaults: defaults),
            reply: { replies.append($0) }
        )
        let notification = Notification(name: NSWindow.willCloseNotification, object: closed.window)
        closed.windowWillClose(notification)
        closed.windowWillClose(notification)
        #expect(replies == [.install, .dismiss])
    }
}
