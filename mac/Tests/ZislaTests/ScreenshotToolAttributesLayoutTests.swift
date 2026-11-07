import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenshotToolAttributesLayoutTests {
    @Test(arguments: [ScreenshotTool.rectangle, .ellipse, .brush, .highlighter, .arrow, .number, .text],
          AppLanguage.allCases)
    func toolAttributesKeepCompleteLabelsInOneRow(tool: ScreenshotTool, language: AppLanguage) async throws {
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let suiteName = "ScreenshotToolAttributesLayout.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = FeatureSettingsStore(defaults: defaults)
        defer { settings.flushPendingChanges() }
        let image = NSImage(size: CGSize(width: 80, height: 50))
        let model = ScreenshotEditorModel(image: image)
        let editor = ScreenshotEditorView(
            model: model, selectionState: ScreenshotAnnotationSelectionState(), settingsStore: settings,
            onClose: {}, onCopy: {}, onPinToggle: { _ in }, onLongCapture: {}
        )
        let host = NSHostingView(rootView: editor.toolAttributesMenu(for: tool)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: host.fittingSize),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<3 {
            window.setContentSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        #expect(host.fittingSize.height == ScreenshotToolbarLayout.height)
        var frames: [String: CGRect] = [:]
        func visit(_ object: NSObject) {
            func value(_ key: String) -> Any? {
                object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
            }
            let label = ["accessibilityTitle", "accessibilityLabel", "accessibilityValue"]
                .compactMap { value($0) as? String }.first { !$0.isEmpty }
            if let element = object as? any NSAccessibilityElementProtocol, let label {
                frames[label] = host.convert(window.convertFromScreen(element.accessibilityFrame()), from: nil)
            }
            for child in value("accessibilityChildren") as? [NSObject] ?? [] { visit(child) }
        }
        visit(host)
        let keys = switch tool {
        case .highlighter: ["颜色", "粗细", "保留左右标记"]
        case .number: ["颜色", "大小"]
        case .text: ["颜色", "字号"]
        default: ["颜色", "粗细"]
        }
        for key in keys {
            let text = AppLocalization.string(key, language: language)
            let frame = try #require(frames[text], "Missing \(language.rawValue) label: \(text)")
            let font = NSFont.systemFont(ofSize: 12, weight: key == "保留左右标记" ? .regular : .semibold)
            let naturalWidth = (text as NSString).size(withAttributes: [.font: font]).width
            #expect(frame.width + 1 >= naturalWidth,
                "\(tool.rawValue) \(language.rawValue) \(text) requires \(naturalWidth)pt but receives \(frame.width)pt")
            #expect(host.bounds.insetBy(dx: -1, dy: -1).contains(frame),
                "\(tool.rawValue) \(language.rawValue) \(text) must remain inside the 38pt toolbar")
        }
        #expect(model.image === image && model.annotations.isEmpty && !model.canUndo)
        #expect(model.highlighterShowsMarkers)
        #expect(!window.isVisible && !window.isKeyWindow)
    }
}
