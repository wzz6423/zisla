import AppKit
import SwiftUI
import Testing

@testable import Zisla

@MainActor
@Suite(.serialized)
struct SettingsSearchScrollTests {
    @Test
    func resultScrollsAfterDeferredPageLayoutAndTracksLateGeometry() async throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        await fixture.layout()
        fixture.input.searching = false
        fixture.input.target = .row("键盘音效")
        await fixture.layout()
        #expect(try fixture.offset() == 0)

        fixture.input.leadingHeight = 1400
        await fixture.layout()
        #expect(abs(try fixture.offset() - 1224) < 1, "The matched row must be centered after its final layout, not left below the viewport")
    }

    @Test
    func repeatedSearchesInOneSectionReachRowsAndGroups() async throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        fixture.input.leadingHeight = 1400
        await fixture.layout()
        fixture.input.searching = false
        fixture.input.target = .row("键盘音效")
        await fixture.layout()
        #expect(abs(try fixture.offset() - 1224) < 1)

        fixture.input.target = .group("宠物与更新")
        await fixture.layout()
        #expect(abs(try fixture.offset() - 1672) < 1)

        fixture.input.searching = true
        fixture.input.target = nil
        await fixture.layout()
        fixture.input.searching = false
        fixture.input.target = .row("键盘音效")
        await fixture.layout()
        #expect(abs(try fixture.offset() - 1224) < 1)
    }

    @Test
    func clearedOrMissingTargetsDoNotScrollThePage() async throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        fixture.input.searching = false
        fixture.input.target = .row("键盘音效")
        await fixture.layout()
        fixture.input.target = nil
        fixture.input.leadingHeight = 1400
        await fixture.layout()
        #expect(try fixture.offset() == 0)
        fixture.input.target = .row("不存在的项目")
        await fixture.layout()
        #expect(try fixture.offset() == 0)
    }

    private final class Input: ObservableObject {
        @Published var searching = true
        @Published var leadingHeight: CGFloat = 0
        @Published var target: SettingsSearchAnchor?
    }

    private struct Page: View {
        @ObservedObject var input: Input

        var body: some View {
            SettingsSearchScrollView(target: input.target, resetID: input.searching ? "query" : "") {
                VStack(spacing: 0) {
                    if input.searching {
                        Text("Search results")
                    } else {
                        DeferredMount {
                            AnyView(VStack(spacing: 0) {
                                Color.clear.frame(height: input.leadingHeight)
                                Text("键盘音效").frame(height: 48)
                                    .settingsSearchAnchor(.row("键盘音效"))
                                Color.clear.frame(height: 400)
                                Text("宠物与更新").frame(height: 48)
                                    .settingsSearchAnchor(.group("宠物与更新"))
                                Color.clear.frame(height: 600)
                            })
                            .id("features")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @MainActor
    private final class Fixture {
        let input = Input()
        let window: NSWindow
        let host: NSHostingView<Page>

        init() {
            _ = NSApplication.shared
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            host = NSHostingView(rootView: Page(input: input))
            host.sizingOptions = []
            window.contentView = host
        }

        func layout() async {
            // Drain deferred mounting and preference updates without presenting a real settings window.
            for _ in 0..<20 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }

        func offset() throws -> CGFloat {
            var pending = [host as NSView]
            while let view = pending.popLast() {
                if let scrollView = view as? NSScrollView {
                    return scrollView.contentView.bounds.minY
                }
                pending.append(contentsOf: view.subviews)
            }
            throw MissingScrollView()
        }
    }

    private struct MissingScrollView: Error {}
}
