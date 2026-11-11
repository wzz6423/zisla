import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct AIProgressTaskListRegressionTests {
    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    func refreshingScrolledTasksDoesNotChangeTheViewportWidth(language: AppLanguage) async throws {
        let fixture = try TaskListFixture(taskCount: 96, language: language)
        defer { fixture.close() }
        await fixture.settle(turns: 8)
        let (scroll, table) = try fixture.list()
        // Commit the installed mini scroller's native metrics before measuring task-update changes.
        scroll.tile()
        var widths = [scroll.contentView.frame.width]
        let observation = scroll.observe(\.scrollerStyle) { _, _ in
            MainActor.assumeIsolated { widths.append(scroll.contentView.frame.width) }
        }
        defer { observation.invalidate() }

        for step in 1...24 {
            try fixture.upsert(index: (step * 37) % 96, step: step)
            fixture.reload()
            let snapshot = fixture.monitor.state
            fixture.scroll(scroll, fraction: CGFloat((step * 17) % 101) / 100)
            await fixture.settle(turns: 2)
            widths.append(scroll.contentView.frame.width)
            #expect(scroll.documentView === table, "Updating a scrolled task must preserve the native list")
            #expect(table.numberOfRows == snapshot.tasks.filter(\.status.isActive).count)
            #expect(fixture.monitor.state == snapshot, "Layout must not mutate monitored tasks")
        }

        #expect((widths.max() ?? 0) - (widths.min() ?? 0) < 0.5,
            "Task refreshes must not repeatedly reserve and release a scrollbar gutter at a fixed window size")
        #expect(!fixture.window.isVisible)
    }

    @Test(arguments: [NSScroller.Style.legacy, .overlay])
    func thinChromeKeepsTheNativeListScrollbarPolicy(style: NSScroller.Style) async throws {
        let fixture = try TaskListFixture(taskCount: 24)
        defer { fixture.close() }
        await fixture.settle(turns: 8)
        let (scroll, table) = try fixture.list()
        fixture.scroll(scroll, fraction: 0.5)
        scroll.scrollerStyle = style
        scroll.tile()
        let viewport = scroll.contentView.frame
        let offset = scroll.contentView.bounds.origin
        let autohides = scroll.autohidesScrollers
        let hasVerticalScroller = scroll.hasVerticalScroller

        // Let deferred chrome callbacks run without asking SwiftUI to reset its native policy.
        for _ in 0..<8 { await fixture.nextTurn() }

        #expect(scroll.scrollerStyle == style, "Thin chrome must retain the native scrollbar policy")
        #expect(scroll.contentView.frame == viewport)
        #expect(scroll.contentView.bounds.origin == offset)
        #expect(scroll.autohidesScrollers == autohides)
        #expect(scroll.hasVerticalScroller == hasVerticalScroller)
        #expect(scroll.documentView === table)
        let scroller = try #require(scroll.verticalScroller as? ThinScroller)
        #expect(scroller.knobProportion > 0 && scroller.knobProportion < 1)
        #expect(try paintedKnobWidth(scroller) == 3,
            "Preserving native policy must retain the three-point scrollbar knob")
    }

    @Test
    func activeRowsCanFinishDisappearAndReturnAfterTheListIsEmpty() async throws {
        let fixture = try TaskListFixture(taskCount: 18)
        defer { fixture.close() }
        await fixture.settle(turns: 8)
        for index in 0..<9 {
            try fixture.repository.finish(id: "fixture-\(index)", failed: false, detail: nil, at: fixture.now)
        }
        fixture.reload()
        await fixture.settle(turns: 4)
        #expect(try fixture.list().1.numberOfRows == 9,
            "Finished tasks must leave the running list")

        try fixture.repository.clearTasks()
        fixture.reload()
        await fixture.settle(turns: 4)
        #expect(fixture.monitor.state.tasks.isEmpty)
        #expect(fixture.descendants.compactMap { $0 as? NSTableView }.isEmpty,
            "The empty task state must release the native task list")
        #expect(fixture.descendants.compactMap { $0 as? NSScrollView }.count == 2,
            "The usage pane and full-width quota surface must remain available while the task list is empty")

        try fixture.upsert(index: 0, step: 1)
        try fixture.upsert(index: 0, step: 2)
        try fixture.upsert(index: 1, step: 2)
        fixture.reload()
        let snapshot = fixture.monitor.state
        await fixture.settle(turns: 8)
        #expect(try fixture.list().1.numberOfRows == 2,
            "Returning tasks must rebuild the list without duplicating an updated task")
        #expect(fixture.monitor.state == snapshot)
        try fixture.repository.remove(id: "fixture-1")
        fixture.reload()
        await fixture.settle(turns: 4)
        #expect(try fixture.list().1.numberOfRows == 1)
        #expect(!fixture.window.isVisible)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ZISLA_AI_LIST_STRESS"] == "1"),
        .timeLimit(.minutes(1)), arguments: [UInt64(0xA1_1157), UInt64(0xC0_DE28)])
    func boundedTaskChurnAndWheelScrollingKeepTheListConsistent(seed: UInt64) async throws {
        let fixture = try TaskListFixture(taskCount: 192)
        defer { fixture.close() }
        await fixture.settle(turns: 8)
        var random = seed
        var wheelSteps = 0
        for step in 1...240 {
            random = random &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let index = Int((random >> 16) % 192)
            if step % 60 == 0 {
                try fixture.repository.clearTasks()
            } else if step % 7 == 0 {
                try fixture.repository.remove(id: "fixture-\(index)")
            } else {
                try fixture.upsert(index: index, step: step, isFinished: step % 11 == 0)
            }
            fixture.reload()
            let snapshot = fixture.monitor.state
            let widths: [CGFloat] = [560, 752, 980]
            fixture.window.setContentSize(NSSize(width: widths[Int(random % 3)],
                height: step % 2 == 0 ? 160 : 240))
            await fixture.settle(turns: 2)
            let activeCount = snapshot.tasks.filter(\.status.isActive).count
            if activeCount > 0 {
                let (scroll, table) = try fixture.list()
                fixture.scroll(scroll, fraction: CGFloat((random >> 24) % 101) / 100)
                let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                    wheelCount: 1, wheel1: step % 2 == 0 ? 54 : -54, wheel2: 0, wheel3: 0))
                scroll.scrollWheel(with: try #require(NSEvent(cgEvent: event)))
                wheelSteps += 1
                await fixture.settle(turns: 2)
                #expect(table.numberOfRows == activeCount, "Seed \(seed), step \(step): active rows must match the snapshot")
                #expect(scroll.documentView === table)
                #expect(table.frame.height.isFinite && scroll.contentView.bounds.minY.isFinite)
                #expect(scroll.contentView.bounds.intersects(table.bounds),
                    "Seed \(seed), step \(step): wheel scrolling must leave task content in the viewport")
            } else {
                #expect(fixture.descendants.compactMap { $0 as? NSTableView }.isEmpty)
            }
            #expect(fixture.monitor.state == snapshot, "Seed \(seed), step \(step): scrolling must preserve AI state")
        }
        #expect(wheelSteps > 200, "The fixed budget must exercise native wheel scrolling as well as empty states")
        #expect(!fixture.window.isVisible)
    }

    private func paintedKnobWidth(_ scroller: NSScroller) throws -> Int {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(scroller.bounds.width), pixelsHigh: Int(scroller.bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        scroller.bounds.fill(using: .copy)
        scroller.drawKnob()
        var columns = Set<Int>()
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
                    columns.insert(x)
                }
            }
        }
        return columns.count
    }
}

@MainActor
private final class TaskListFixture {
    let directory: URL
    let repository: AIStateRepository
    let monitor: AIStateMonitor
    let host: NSHostingView<AnyView>
    let window: NSWindow
    let now = Date(timeIntervalSince1970: 1_794_301_200)

    init(taskCount: Int, language: AppLanguage = .english) throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-task-list-\(UUID().uuidString)", isDirectory: true)
        repository = AIStateRepository(directoryURL: directory)
        let date = now
        monitor = AIStateMonitor(directoryURL: directory, activityDetectors: [], now: { date })
        host = NSHostingView(rootView: AnyView(AIProgressModuleView(monitor: monitor, monitoredBalanceProviders: [])
            .environment(\.colorScheme, .dark)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)))
        host.sizingOptions = []
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 752, height: 160),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        do {
            for index in 0..<taskCount { try upsert(index: index, step: 0) }
            reload()
        } catch {
            close()
            throw error
        }
    }

    func upsert(index: Int, step: Int, isFinished: Bool = false) throws {
        let variant = (index + step) % 5
        try repository.upsert(AIProgressTask(id: "fixture-\(index)", provider: .codex,
            title: "Synthetic task \(index)", detail: "gpt-6.1-sol", progress: variant == 0 ? 0.5 : nil,
            status: isFinished ? .succeeded : variant == 1 ? .blocked : variant == 2 ? .error : .running,
            updatedAt: now.addingTimeInterval(Double(step * 100 + index)),
            sessionURL: variant == 3 ? nil : URL(string: "codex://fixture/\(index)"),
            effort: "max", startedAt: now.addingTimeInterval(-120),
            failureReason: variant == 2 ? "Synthetic failure" : nil,
            processIdentifier: Int32(10_000 + index)))
    }

    func reload() { monitor.reload(includeUsageSamples: false) }

    var descendants: [NSView] {
        func collect(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + collect($0) }
        }
        return collect(host)
    }

    func list() throws -> (NSScrollView, NSTableView) {
        let scroll = try #require(descendants.compactMap { $0 as? NSScrollView }
            .first { $0.documentView is NSTableView })
        return (scroll, try #require(scroll.documentView as? NSTableView))
    }

    func scroll(_ scroll: NSScrollView, fraction: CGFloat) {
        let maximumOffset = max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: maximumOffset * fraction))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func settle(turns: Int) async {
        for _ in 0..<turns {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            await nextTurn()
        }
    }

    func nextTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    func close() {
        monitor.stop()
        window.contentView = nil
        window.close()
        try? FileManager.default.removeItem(at: directory)
    }
}
