import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingInspectorLayoutTests {
    @Test(arguments: AppLanguage.allCases, [296.0, 366.0])
    func preciseInputsKeepCompactWidthsInsideTheInspector(language: AppLanguage, width: Double) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let section = ScreenRecordingInspectorSection(AppLocalization.string("手动缩放", language: language), symbol: "plus.magnifyingglass") {
            ScreenRecordingNumberField(title: AppLocalization.string("起点（秒）", language: language),
                value: .constant(12.375), identifier: "start")
            ScreenRecordingNumberField(title: AppLocalization.string("焦点水平位置", language: language),
                value: .constant(0.125), identifier: "focus")
        }
        let fixture = Fixture(section.frame(width: width), language: language)
        defer { fixture.window.close() }
        await fixture.settle()
        let inputs = fixture.editableFields()
        #expect(inputs.count == 2)
        for input in inputs {
            let frame = input.convert(input.bounds, to: fixture.host)
            #expect(frame.width > 0 && frame.width <= 84.5, "Seconds and coordinates must not stretch into full-width form fields")
            #expect(fixture.host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame))
        }
        #expect(abs(fixture.host.fittingSize.width - width) <= 0.5)
        #expect(!fixture.window.isVisible)
    }

    @Test
    func collapsedSectionsLeaveThePreviewSpaceForTheTimeline() async {
        let expanded = Fixture(section(expanded: true), language: .english)
        let collapsed = Fixture(section(expanded: false), language: .english)
        defer { expanded.window.close(); collapsed.window.close() }
        await expanded.settle()
        await collapsed.settle()
        #expect(expanded.host.fittingSize.height > collapsed.host.fittingSize.height + 100)
        #expect(collapsed.host.fittingSize.height < 60)
    }

    private func section(expanded: Bool) -> some View {
        ScreenRecordingInspectorSection("Canvas", symbol: "rectangle", expanded: expanded) {
            ScreenRecordingParameterRow(title: "Padding", value: .constant(0.06), range: 0...0.3, identifier: "padding")
            ScreenRecordingParameterRow(title: "Corner Radius", value: .constant(0.02), range: 0...0.2, identifier: "corner")
            ScreenRecordingParameterRow(title: "Shadow", value: .constant(0.3), range: 0...1, identifier: "shadow")
        }.frame(width: 296)
    }

    @MainActor
    private final class Fixture {
        let window: NSWindow
        let host: NSView

        init<Content: View>(_ content: Content, language: AppLanguage) {
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

        func editableFields(in view: NSView? = nil) -> [NSTextField] {
            let view = view ?? host
            if let field = view as? NSTextField, field.isEditable { return [field] }
            return view.subviews.flatMap { editableFields(in: $0) }
        }
    }
}
