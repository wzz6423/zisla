import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenshotExtractionControlsLayoutTests {
    @Test
    func extractionMatchesTheExistingToolAttributeRegionAndControlInsets() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let suiteName = "zisla-extraction-layout-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = FeatureSettingsStore(defaults: defaults)
        defer { settings.flushPendingChanges() }
        let model = ScreenshotEditorModel(image: sourceImage())
        let editor = ScreenshotEditorView(
            model: model, selectionState: ScreenshotAnnotationSelectionState(), settingsStore: settings,
            onClose: {}, onCopy: {}, onPinToggle: { _ in }, onLongCapture: {}
        )
        let reference = Fixture(editor.toolAttributesMenu(for: .arrow))
        let extraction = Fixture(model: model)
        defer { reference.window.close(); extraction.window.close() }
        await reference.settle()
        await extraction.settle()

        #expect(reference.host.fittingSize.height == ScreenshotToolbarLayout.height)
        #expect(extraction.host.fittingSize.height == reference.host.fittingSize.height)
        let referencePicker = try #require(reference.segmentedControl())
        let extractionPicker = try #require(extraction.segmentedControl())
        let referenceFrame = referencePicker.convert(referencePicker.bounds, to: reference.host)
        let extractionFrame = extractionPicker.convert(extractionPicker.bounds, to: extraction.host)
        #expect(referenceFrame.height == 24)
        #expect(extractionFrame.height == referenceFrame.height)
        #expect(reference.host.bounds.contains(referenceFrame))
        #expect(extraction.host.bounds.contains(extractionFrame))
        let referenceInsets = [referenceFrame.minY, reference.host.bounds.maxY - referenceFrame.maxY]
        let extractionInsets = [extractionFrame.minY, extraction.host.bounds.maxY - extractionFrame.maxY]
        for (expected, actual) in zip(referenceInsets, extractionInsets) {
            #expect(expected > 0 && actual > 0, "Native controls must have space above and below the shared region")
            #expect(abs(actual - expected) <= 0.5, "Extraction must preserve the existing tool region's vertical insets")
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func everyModeAndItsActionsFitOneRowInEveryLanguage(language: AppLanguage) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        for mode in ScreenshotExtractionMode.allCases {
            let model = ScreenshotEditorModel(image: sourceImage())
            model.extractionMode = mode
            let fixture = Fixture(model: model, language: language)
            defer { fixture.window.close() }
            await fixture.settle()

            let picker = try #require(fixture.segmentedControl())
            #expect(picker.segmentCount == ScreenshotExtractionMode.allCases.count)
            for (index, option) in ScreenshotExtractionMode.allCases.enumerated() {
                #expect(picker.label(forSegment: index) == AppLocalization.string(option.title, language: language))
            }
            var labels = [AppLocalization.string(mode == .lasso ? "提取所选区域" : mode.title, language: language)]
            if mode == .lasso {
                labels += ["全选", "清除"].map { AppLocalization.string($0, language: language) }
                labels.append(AppLocalization.format("已圈选 %ld 个区域", locale: language.locale, [0]))
            }
            try fixture.expectSingleRow(labels: labels)
            #expect(try fixture.button(mode == .lasso ? "提取所选区域" : mode.title).isEnabled == (mode != .lasso))
        }
    }

    @Test
    func lassoActionsUpdateSelectionAndModeWithoutChangingTheImage() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let image = sourceImage()
        let model = ScreenshotEditorModel(image: image)
        model.extractionMode = .lasso
        var extractions = 0
        let fixture = Fixture(model: model, onExtract: { extractions += 1 })
        defer { fixture.window.close() }
        await fixture.settle()
        #expect(try fixture.button("提取所选区域").isEnabled == false)

        try fixture.press("全选")
        await fixture.settle()
        #expect(model.extractionRegions.count == 1)
        #expect(try fixture.button("提取所选区域").isEnabled == true)
        #expect(fixture.elements().contains { $0.label == "已圈选 1 个区域" })
        try fixture.press("提取所选区域")
        #expect(extractions == 1)

        try fixture.press("清除")
        await fixture.settle()
        #expect(model.extractionRegions.isEmpty)
        #expect(try fixture.button("提取所选区域").isEnabled == false)
        let picker = try #require(fixture.segmentedControl())
        picker.selectedSegment = 1
        picker.sendAction(picker.action, to: picker.target)
        #expect(model.extractionMode == .background)
        #expect(model.image === image)
        #expect(!model.canUndo)
    }

    @Test
    func busyCancellationAndLongFailureKeepTheControlsOnOneRow() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let model = ScreenshotEditorModel(image: sourceImage())
        model.extractionMode = .lasso
        model.selectAllExtractionRegions()
        let gate = AsyncStream<Void>.makeStream()
        let taskResult = model.extract(extractImage: { _, _ in
            for await _ in gate.stream {}
            throw CancellationError()
        })
        let task = try #require(taskResult)
        defer { model.cancelExtraction(); gate.continuation.finish() }
        let fixture = Fixture(model: model)
        defer { fixture.window.close() }
        await fixture.settle()
        #expect(try #require(fixture.segmentedControl()).isEnabled == false)
        #expect(try fixture.button("全选").isEnabled == false)
        #expect(try fixture.button("清除").isEnabled == false)
        #expect(try fixture.button("取消").isEnabled == true)
        try fixture.expectSingleRow(labels: ["全选", "清除", "已圈选 1 个区域", "正在提取...", "取消"])
        #expect(fixture.elements().filter { $0.label == "正在提取..." }.count == 1)

        try fixture.press("取消")
        await fixture.settle()
        #expect(!model.isExtracting)
        #expect(model.statusMessage == nil)
        #expect(try fixture.button("提取所选区域").isEnabled == true)
        gate.continuation.finish()
        await task.value

        let failure = AppLocalization.text("提取失败：%@", String(repeating: "failure ", count: 100))
        model.statusMessage = failure
        await fixture.settle()
        let status = try #require(fixture.elements().first { $0.label == failure })
        #expect(fixture.host.fittingSize.width < 1024, "Failure details must not push controls beyond a compact display")
        #expect(status.help == failure)
        try fixture.expectSingleRow(labels: ["全选", "清除", "已圈选 1 个区域", "提取所选区域", failure])
    }

    private func sourceImage() -> NSImage {
        NSImage(size: CGSize(width: 80, height: 50), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
    }

    @MainActor
    private final class Fixture {
        let window: NSWindow
        let host: NSView
        let language: AppLanguage

        convenience init(model: ScreenshotEditorModel, language: AppLanguage = .simplifiedChinese, onExtract: @escaping () -> Void = {}) {
            self.init(ScreenshotExtractionControls(
                model: model, onSelectAll: { model.selectAllExtractionRegions() },
                onClear: { model.clearExtractionSelection() }, onExtract: onExtract
            ), language: language)
        }

        init<Content: View>(_ content: Content, language: AppLanguage = .simplifiedChinese) {
            self.language = language
            let hosting = NSHostingView(rootView: content.environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
            host = hosting
            window = NSWindow(contentRect: CGRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
        }

        func settle() async {
            for _ in 0..<3 {
                window.setContentSize(host.fittingSize)
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
        }

        func segmentedControl(in view: NSView? = nil) -> NSSegmentedControl? {
            let view = view ?? host
            if let picker = view as? NSSegmentedControl { return picker }
            return view.subviews.lazy.compactMap { self.segmentedControl(in: $0) }.first
        }

        struct Element {
            let object: NSObject
            let label: String?
            let role: String?
            let frame: CGRect
            let isEnabled: Bool?
            let help: String?
        }

        func elements() -> [Element] {
            var result: [Element] = []
            func visit(_ object: NSObject) {
                func value(_ key: String) -> Any? {
                    object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
                }
                if let element = object as? any NSAccessibilityElementProtocol {
                    let label = ["accessibilityTitle", "accessibilityLabel", "accessibilityValue"]
                        .compactMap { value($0) as? String }.first { !$0.isEmpty }
                    result.append(Element(object: object, label: label, role: value("accessibilityRole") as? String,
                        frame: element.accessibilityFrame(), isEnabled: value("isAccessibilityEnabled") as? Bool,
                        help: value("accessibilityHelp") as? String))
                }
                for child in value("accessibilityChildren") as? [NSObject] ?? [] { visit(child) }
            }
            for child in host.accessibilityChildren() as? [NSObject] ?? [] { visit(child) }
            return result
        }

        func button(_ key: String) throws -> Element {
            let title = AppLocalization.string(key, language: language)
            return try #require(elements().first { $0.label == title && $0.role == NSAccessibility.Role.button.rawValue })
        }

        func press(_ key: String) throws {
            let element = try button(key)
            let selector = NSSelectorFromString("accessibilityPerformPress")
            #expect(element.object.responds(to: selector))
            _ = element.object.perform(selector)
        }

        func expectSingleRow(labels: [String]) throws {
            let elements = elements()
            let group = try #require(elements.first { $0.role == NSAccessibility.Role.radioGroup.rawValue })
            let row = try [group] + labels.map { title in
                try #require(elements.first { $0.label == title }, "Missing visible control: \(title)")
            }
            #expect(host.fittingSize.height == ScreenshotToolbarLayout.height)
            let bounds = window.convertToScreen(host.convert(host.bounds, to: nil))
            for element in row {
                #expect(element.frame.width > 0 && element.frame.height > 0)
                #expect(bounds.insetBy(dx: -1, dy: -1).contains(element.frame))
                #expect(element.frame.minY > bounds.minY && element.frame.maxY < bounds.maxY,
                        "Extraction controls must preserve vertical space inside the shared tool region")
            }
            let centers = row.map(\.frame.midY)
            #expect(try #require(centers.max()) - #require(centers.min()) <= 2,
                    "All extraction controls must share one row in \(language.rawValue)")
            #expect(!window.isVisible)
        }
    }
}
