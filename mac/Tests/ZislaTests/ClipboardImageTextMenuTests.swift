import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
@testable import Zisla
@testable import ZislaKit

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ClipboardImageTextMenuTests {
    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    func imageMenuDispatchesRecognitionAndTextCopyWhileNormalCopyKeepsImage(language: AppLanguage) async throws {
        let fixture = try Fixture(language: language)
        defer { fixture.close() }
        await fixture.store.waitUntilLoaded()
        let item = try #require(fixture.store.items.first)
        var copied: ClipboardHistoryItem?
        var recognized: UUID?
        var textCopied: UUID?
        let host = fixture.host(copyItem: { copied = $0 }, recognizeImageText: { recognized = $0.id }, copyImageText: { textCopied = $0.id })
        await settle(host)
        let menu = try fixture.contextMenu(in: host)
        let titles = menu.items.map(\.title)
        #expect(titles.contains(AppLocalization.string("识别图片文字", language: language)))
        #expect(titles.contains(AppLocalization.string("复制图片文字", language: language)))
        #expect(!titles.contains(AppLocalization.string("取消图片文字识别", language: language)))
        try activate("识别图片文字", in: menu, language: language)
        #expect(recognized == item.id && textCopied == nil && copied == nil)
        try activate("复制图片文字", in: menu, language: language)
        #expect(textCopied == item.id && copied == nil)
        try activate("复制", in: menu, language: language)
        #expect(copied == item)
        #expect(copied?.content == .image(Data([1])))
        #expect(fixture.store.items == [item])
    }

    @Test
    func processingImageMenuOnlyOffersCancellationAndCancellationDiscardsLateResult() async throws {
        let gate = MenuRecognitionGate()
        let fixture = try Fixture(language: .english, recognizer: { try await gate.recognize($0) })
        defer { fixture.close() }
        await fixture.store.waitUntilLoaded()
        let item = try #require(fixture.store.items.first)
        let recognition = Task { try await fixture.store.recognizeImageText(id: item.id) }
        await gate.waitUntilStarted()
        let host = fixture.host()
        await settle(host)
        let menu = try fixture.contextMenu(in: host)
        #expect(menu.items.map(\.title).contains("Cancel image text recognition"))
        #expect(!menu.items.map(\.title).contains("Recognize image text"))
        #expect(!menu.items.map(\.title).contains("Copy image text"))
        try activate("取消图片文字识别", in: menu, language: .english)
        await #expect(throws: CancellationError.self) { try await recognition.value }
        await gate.finish()
        await fixture.store.waitUntilImageRecognitionFinished()
        #expect(fixture.store.items.first?.recognizedImageText == nil)
        #expect(fixture.store.imageRecognitionStates.isEmpty)
    }

    @Test
    func textRowsDoNotOfferImageActionsOrTranslateUserText() async throws {
        let fixture = try Fixture(language: .english, content: .text("删除"))
        defer { fixture.close() }
        await fixture.store.waitUntilLoaded()
        let item = try #require(fixture.store.items.first)
        let host = fixture.host()
        await settle(host)
        let menu = try fixture.contextMenu(in: host)
        #expect(!menu.items.map(\.title).contains("Recognize image text"))
        #expect(!menu.items.map(\.title).contains("Copy image text"))
        let labels = objects(in: host).flatMap { object in
            ["accessibilityValue", "accessibilityLabel"].compactMap { key in
                object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) as? String : nil
            }
        }
        #expect(labels.contains { $0.contains("删除") }, "The copy button must keep user-authored text: \(labels)")
    }

    private func activate(_ key: String, in menu: NSMenu, language: AppLanguage) throws {
        let item = try #require(menu.items.first { $0.title == AppLocalization.string(key, language: language) })
        let action = try #require(item.action)
        #expect(NSApp.sendAction(action, to: item.target, from: item))
    }

    private func settle(_ host: NSView) async {
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }

    private func objects(in object: NSObject) -> [NSObject] {
        let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
            ? object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
        return [object] + children.flatMap { objects(in: $0) }
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let store: ClipboardHistoryStore
        let window: NSPanel
        let language: AppLanguage
        let previousArguments: [String: Any]
        let releaseAccessibility: () -> Void

        init(language: AppLanguage, content: ClipboardHistoryContent = .image(Data([1])), recognizer: (@Sendable (Data) async throws -> String)? = nil) throws {
            self.language = language
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-image-menu-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            let url = root.appendingPathComponent("history.sqlite")
            try ClipboardHistoryDatabase(storageURL: url).flush([.upsert(ClipboardHistoryItem(content: content), capacity: nil)])
            store = ClipboardHistoryStore(storageURL: url, persistenceDelay: .seconds(60), imageTextRecognizer: recognizer)
            previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            var arguments = previousArguments
            arguments[AppLocalization.defaultsKey] = language.rawValue
            UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
            window = NSPanel(contentRect: NSRect(x: -100_000, y: -100_000, width: 620, height: 440),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
        }

        func host(copyItem: @escaping (ClipboardHistoryItem) -> Void = { _ in },
                  recognizeImageText: @escaping (ClipboardHistoryItem) -> Void = { _ in },
                  copyImageText: @escaping (ClipboardHistoryItem) -> Void = { _ in }) -> NSView {
            let host = NSHostingView(rootView: ClipboardHistoryModuleView(store: store, copyItem: copyItem,
                                                                          copyImageText: copyImageText, recognizeImageText: recognizeImageText, sendToQuickNote: { _ in })
                    .frame(width: 620, height: 440)
                    .environment(\.locale, language.locale)
                    .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
            host.sizingOptions = []
            window.contentView = host
            window.orderFrontRegardless()
            return host
        }

        func contextMenu(in host: NSView) throws -> NSMenu {
            func objects(_ object: NSObject) -> [NSObject] {
                let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
                    ? object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
                return [object] + children.flatMap(objects)
            }
            let element = try #require(objects(host).first {
                $0.responds(to: NSSelectorFromString("accessibilityHelp"))
                    && $0.value(forKey: "accessibilityHelp") as? String == AppLocalization.string("复制到剪贴板", language: language)
            } as? any NSAccessibilityElementProtocol)
            let frame = element.accessibilityFrame()
            let point = window.convertPoint(fromScreen: CGPoint(x: frame.minX + 20, y: frame.midY))
            let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [],
                                                        timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            var target = host.hitTest(host.convert(point, from: nil))
            while let view = target {
                if let menu = view.menu(for: event) { return menu }
                target = view.superview
            }
            Issue.record("Clipboard image rows must expose their native context menu")
            throw CocoaError(.featureUnsupported)
        }

        func close() {
            store.cancelImageRecognition()
            store.flushPendingChanges()
            window.contentView = nil
            window.close()
            releaseAccessibility()
            UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain)
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private actor MenuRecognitionGate {
    private var continuation: CheckedContinuation<String, any Error>?
    private var started: CheckedContinuation<Void, Never>?
    private var running = false

    func recognize(_ data: Data) async throws -> String {
        running = true
        started?.resume()
        started = nil
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if running { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() {
        continuation?.resume(returning: "late menu result")
        continuation = nil
    }
}
