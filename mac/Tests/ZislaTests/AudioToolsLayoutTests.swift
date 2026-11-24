import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct AudioToolsLayoutTests {
    @Test(arguments: [(CGFloat(560), false), (CGFloat(708), false), (CGFloat(708), true)],
          [AppLanguage.simplifiedChinese, .english, .arabic])
    func operationListFillsThePageAndScrollsIndependently(scenario: (width: CGFloat, search: Bool),
                                                          language: AppLanguage) async throws {
        let (width, search) = scenario
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }

        let target = search ? SettingsSearchAnchor.audioOperation(.generateTone).localized(locale: language.locale) : nil
        let host = NSHostingView(rootView: SettingsSearchScrollView(target: target, resetID: "", scrollsContent: false) {
            VStack(alignment: .leading, spacing: 22) {
                AppLocalizedText("音频工具")
                    .font(.system(size: 23, weight: .semibold))
                DeferredMount {
                    AudioToolsModuleView(initialOperation: search ? .generateTone : .convert)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environment(\.locale, language.locale)
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 580),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }

        func settle() async {
            for _ in 0..<20 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }
        await settle()
        let scrolls = descendants(in: host).compactMap { $0 as? NSScrollView }
        try #require(scrolls.count == 2,
                     "Only the audio operation list and configuration may scroll; the page must remain fixed")
        let scroll = try #require(scrolls.min { $0.frame.width < $1.frame.width })
        let configuration = try #require(scrolls.first { $0 !== scroll })
        let document = try #require(scroll.documentView)

        func frame(_ title: String, in coordinateView: NSView, role: NSAccessibility.Role) throws -> CGRect {
            let text = AppLocalization.string(title, language: language)
            let object = try #require(accessibilityObjects(host).first { object in
                value(object, "accessibilityRole") as? String == role.rawValue
                    && ["accessibilityLabel", "accessibilityValue"].contains { value(object, $0) as? String == text }
            }, "The audio page must expose \(text)")
            let element = try #require(object as? any NSAccessibilityElementProtocol)
            return coordinateView.convert(window.convertFromScreen(element.accessibilityFrame()), from: nil)
        }

        func operationFrames() throws -> [CGRect] {
            try AudioToolOperation.allCases.map { try frame($0.title, in: document, role: .button) }
        }
        let title = try frame("音频工具", in: host, role: .staticText)
        let exportButton = try frame("导出音频", in: host, role: .button)
        let list = host.convert(scroll.bounds, from: scroll)
        let expectedHeight = host.bounds.height - 48 - title.height - 22
        #expect(abs(list.height - expectedHeight) < 1,
                "The operation viewport must fill the available page height below its title")
        #expect(abs(configuration.frame.height - list.height) < 1,
                "Both columns must fit the same page height")
        let frames = try operationFrames()
        let last = try #require(frames.last)
        #expect(last.maxY > scroll.contentView.bounds.height,
                "The long operation list must scroll inside its viewport")
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.maxY <= $1.minY },
                "Every operation must remain ordered without overlapping")
        if search {
            #expect(last.minY >= scroll.contentView.bounds.minY && last.maxY <= scroll.contentView.bounds.maxY,
                    "Searching for the last operation must reveal it inside the operation list")
        }

        let configurationOffset = configuration.contentView.bounds.origin
        scroll.contentView.scroll(to: CGPoint(x: 0, y: document.frame.height - scroll.contentView.bounds.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle()
        let bottom = try #require(try operationFrames().last)
        #expect(bottom.minY >= scroll.contentView.bounds.minY && bottom.maxY <= scroll.contentView.bounds.maxY,
                "Scrolling the operation list must reveal its last button in full")
        #expect(configuration.contentView.bounds.origin == configurationOffset,
                "Scrolling the operation list must preserve the configuration scroll position")
        #expect(try frame("音频工具", in: host, role: .staticText) == title)
        #expect(try frame("导出音频", in: host, role: .button) == exportButton,
                "Scrolling operations must leave the title and export controls in place")

        window.setContentSize(NSSize(width: width, height: 260))
        await settle()
        #expect(abs(scroll.frame.height - (expectedHeight - 320)) < 1,
                "The operation viewport must shrink with the page without keeping a fixed height")
        let configurationDocument = try #require(configuration.documentView)
        try #require(configurationDocument.frame.height > configuration.contentView.bounds.height,
                     "The smaller page must require scrolling configuration content")
        #expect(configuration.hasVerticalScroller && configuration.verticalScroller?.isHidden == false,
                "Overflowing configuration must expose its scrollbar")
        let listOffset = scroll.contentView.bounds.origin
        configuration.contentView.scroll(to: CGPoint(x: 0,
                                                     y: configurationDocument.frame.height - configuration.contentView.bounds.height))
        configuration.reflectScrolledClipView(configuration.contentView)
        await settle()
        let exportFrame = try frame("导出音频", in: configurationDocument, role: .button)
        #expect(exportFrame.minY >= configuration.contentView.bounds.minY
            && exportFrame.maxY <= configuration.contentView.bounds.maxY,
            "Scrolling configuration must reveal the export action inside the page")
        #expect(scroll.contentView.bounds.origin == listOffset,
                "Scrolling configuration must preserve the operation list position")
        #expect(try frame("音频工具", in: host, role: .staticText) == title)
        #expect(!window.isVisible, "Layout tests must not display a window")
    }

    private func descendants(in view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(in: $0) }
    }

    private func value(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }

    private func accessibilityObjects(_ object: NSObject) -> [NSObject] {
        [object] + (value(object, "accessibilityChildren") as? [NSObject] ?? []).flatMap(accessibilityObjects)
    }
}
