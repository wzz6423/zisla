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
    func modesAndBusyOrFailureStatesKeepOneRowInEveryLanguage(language: AppLanguage) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let model = ScreenshotEditorModel(image: sourceImage())
        let gate = AsyncStream<Void>.makeStream()
        var tasks: [Task<Void, Never>] = []
        let fixture = Fixture(model: model, language: language, onSelectMode: { mode in
            if let task = model.selectExtractionMode(mode, extractImage: { source, _ in
                for await _ in gate.stream {}
                return source
            }) { tasks.append(task) }
        })
        defer { fixture.window.close() }
        defer { model.cancelExtraction(); gate.continuation.finish() }
        await fixture.settle()
        let picker = try #require(fixture.segmentedControl())
        #expect(picker.segmentCount == ScreenshotExtractionMode.allCases.count)
        #expect(picker.accessibilityLabel() == AppLocalization.string("提取方式", language: language))
        #expect(picker.userInterfaceLayoutDirection == (language.isRightToLeft ? .rightToLeft : .leftToRight))
        for (index, option) in ScreenshotExtractionMode.allCases.enumerated() {
            #expect(picker.label(forSegment: index) == AppLocalization.string(option.title, language: language))
            #expect(!picker.isSelected(forSegment: index))
        }
        try fixture.expectSingleRow()
        let idleSize = fixture.host.fittingSize
        for mode in [ScreenshotExtractionMode.lasso, .foreground, .background] {
            try fixture.press(mode)
            await fixture.settle()
            #expect(model.extractionMode == mode)
            #expect(picker.isEnabled, "Modes must stay available so the current request can be cancelled or replaced")
            #expect(fixture.host.fittingSize == idleSize)
            if mode != .lasso {
                #expect(model.isExtracting)
                let index = try #require(ScreenshotExtractionMode.allCases.firstIndex(of: mode))
                #expect(picker.toolTip(forSegment: index) == AppLocalization.string("正在提取...", language: language))
                for other in ScreenshotExtractionMode.allCases.indices where other != index {
                    #expect(picker.toolTip(forSegment: other) == nil)
                }
            }
            try fixture.expectSingleRow()
        }
        try fixture.press(.background)
        await fixture.settle()
        #expect(!model.isExtracting && model.extractionMode == nil)
        #expect(model.statusMessage == nil && fixture.host.fittingSize == idleSize)
        gate.continuation.finish()
        for task in tasks { await task.value }
        try fixture.press(.lasso)
        let failure = AppLocalization.format("提取失败：%@", locale: language.locale, [String(repeating: "failure ", count: 100)])
        model.statusMessage = failure
        await fixture.settle()
        #expect(picker.toolTip(forSegment: 2) == failure)
        #expect(fixture.host.fittingSize == idleSize)
        try fixture.expectSingleRow()
    }

    @Test
    func nativeSegmentsToggleAndSwitchBeforeSwiftUIRefresh() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let image = sourceImage()
        let model = ScreenshotEditorModel(image: image)
        var modes: [ScreenshotExtractionMode] = []
        var tasks: [Task<Void, Never>] = []
        let fixture = Fixture(model: model, onSelectMode: { mode in
            modes.append(mode)
            if let task = model.selectExtractionMode(mode, extractImage: { source, _ in source }) { tasks.append(task) }
        })
        defer { fixture.window.close() }
        await fixture.settle()
        let picker = try #require(fixture.segmentedControl())
        #expect(picker.sendAction(picker.action, to: picker.target))
        #expect(modes.isEmpty && model.extractionMode == nil)
        for mode in [ScreenshotExtractionMode.lasso, .lasso, .foreground, .background, .lasso, .lasso] {
            let wasSelected = model.extractionMode == mode
            try fixture.press(mode)
            #expect(model.extractionMode == (wasSelected ? nil : mode))
            for (index, option) in ScreenshotExtractionMode.allCases.enumerated() {
                #expect(picker.isSelected(forSegment: index) == (model.extractionMode == option))
            }
        }
        #expect(modes == [.lasso, .lasso, .foreground, .background, .lasso, .lasso])
        for task in tasks { await task.value }
        #expect(model.image === image && !model.canUndo && !model.isExtracting)
        #expect(model.extractionMode == nil)
        model.selectExtractionMode(.lasso)
        await fixture.settle()
        #expect(picker.isSelected(forSegment: 2))
        try fixture.press(.lasso)
        #expect(model.extractionMode == nil)
        #expect(!picker.isSelected(forSegment: 2))
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

        convenience init(model: ScreenshotEditorModel, language: AppLanguage = .simplifiedChinese,
                         onSelectMode: ((ScreenshotExtractionMode) -> Void)? = nil) {
            self.init(ScreenshotExtractionControls(
                model: model, onSelectMode: onSelectMode ?? { model.selectExtractionMode($0) }
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

        func press(_ mode: ScreenshotExtractionMode) throws {
            let picker = try #require(segmentedControl())
            let index = try #require(ScreenshotExtractionMode.allCases.firstIndex(of: mode))
            picker.setSelected(true, forSegment: index)
            #expect(picker.sendAction(picker.action, to: picker.target))
        }

        func expectSingleRow() throws {
            let picker = try #require(segmentedControl())
            #expect(host.fittingSize.height == 38)
            #expect(host.fittingSize.height == ScreenshotToolbarLayout.height)
            #expect(host.fittingSize.width < 1024)
            let frame = picker.convert(picker.bounds, to: host)
            #expect(frame.height == 24)
            #expect(frame.width > 0 && host.bounds.contains(frame))
            #expect(frame.minY > host.bounds.minY && frame.maxY < host.bounds.maxY)
            func buttons(in view: NSView) -> [NSButton] {
                (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
            }
            #expect(buttons(in: host).isEmpty, "Extraction must only expose its three native mode segments")
            #expect(!window.isVisible)
        }
    }
}
