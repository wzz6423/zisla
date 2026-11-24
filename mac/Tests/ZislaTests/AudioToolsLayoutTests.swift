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
    func completeOperationListUsesSettingsPageHeight(scenario: (width: CGFloat, search: Bool),
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
        let host = NSHostingView(rootView: SettingsSearchScrollView(target: target, resetID: "") {
            AudioToolsModuleView(initialOperation: search ? .generateTone : .convert)
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
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
            for _ in 0..<8 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }
        await settle()
        let scrolls = descendants(in: host).compactMap { $0 as? NSScrollView }
        try #require(scrolls.count == 1,
                     "The complete audio operation list must scroll with the settings page")
        let scroll = try #require(scrolls.first)
        let document = try #require(scroll.documentView)

        func operationFrames() throws -> [CGRect] {
            let buttons = accessibilityObjects(host).filter {
                value($0, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue
            }
            return try AudioToolOperation.allCases.map { operation in
                let title = AppLocalization.string(operation.title, language: language)
                let button = try #require(buttons.first { value($0, "accessibilityLabel") as? String == title },
                                          "The settings page must expose \(title)")
                let element = try #require(button as? any NSAccessibilityElementProtocol)
                return document.convert(window.convertFromScreen(element.accessibilityFrame()), from: nil)
            }
        }

        let frames = try operationFrames()
        let first = try #require(frames.first)
        let last = try #require(frames.last)
        #expect(abs(first.minY - 24) < 1, "The list must start at the settings page's top padding")
        #expect(abs(document.bounds.maxY - last.maxY - 24) < 1,
                "The last operation must determine the page bottom without an empty fixed-height region")
        #expect(last.maxY > scroll.contentView.bounds.height,
                "The complete list must extend beyond the initial viewport")
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.maxY <= $1.minY },
                "Every operation must remain ordered without overlapping")
        if search {
            #expect(last.minY >= scroll.contentView.bounds.minY && last.maxY <= scroll.contentView.bounds.maxY,
                    "Searching for the last operation must reveal it through the settings page")
        }

        window.setContentSize(NSSize(width: width, height: 320))
        await settle()
        let resizedFrames = try operationFrames()
        #expect(zip(frames, resizedFrames).allSatisfy { before, after in
            before.minY == after.minY && before.size == after.size
        }, "Resizing the settings viewport must preserve each operation's vertical position and size")
        #expect(resizedFrames.allSatisfy { $0.minX >= 0 && $0.maxX <= document.bounds.width },
                "The list must fit the document width after native scrollbar layout")
        scroll.contentView.scroll(to: CGPoint(x: 0, y: document.frame.height - scroll.contentView.bounds.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle()
        let bottom = try #require(try operationFrames().last)
        #expect(bottom.minY >= scroll.contentView.bounds.minY && bottom.maxY <= scroll.contentView.bounds.maxY,
                "Scrolling the settings page must reveal the last audio operation in full")
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
