import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ContextNoteCornerTests {
    @Test(arguments: [CGSize(width: 320, height: 270), CGSize(width: 436, height: 320)])
    func editorCornersFollowTheIslandsInsetContinuousContour(size: CGSize) async throws {
        _ = NSApplication.shared
        let draft = ContextNoteDraft(location: .window(
            bundleIdentifier: "test.note", applicationName: "Test", title: "Window"
        ))
        draft.text = "A note"
        let window = NSPanel(
            contentRect: CGRect(origin: CGPoint(x: -100_000, y: -100_000), size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: ContextNoteDetailView(
            draft: draft, onCopy: {}, onNavigate: {}, onSave: {}, onClose: {}, onCopyScreenshot: { _ in }, onOpenScreenshot: { _ in }
        ).environment(\.colorScheme, .dark).background(Color.black))
        host.sizingOptions = []
        window.contentView = host
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) })
        window.orderFrontRegardless()

        var editor: NSTextView?
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            var pending = [host as NSView]
            while let view = pending.popLast() {
                if let textView = view as? NSTextView { editor = textView }
                pending.append(contentsOf: view.subviews)
            }
            if editor?.enclosingScrollView != nil { break }
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        let textView = try #require(editor)
        let scroll = try #require(textView.enclosingScrollView)
        #expect(textView.string == draft.text)
        let surface = host.convert(scroll.bounds, from: scroll).insetBy(dx: -6, dy: -6)
        #expect(host.bounds.contains(surface))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let contour = IslandSurfaceGeometry.moduleContentShape(
            cornerRadius: IslandSurfaceGeometry.nestedBottomCornerRadius(inset: 10)
        ).path(in: surface)
        func fill(at point: CGPoint) throws -> CGFloat {
            let y = host.isFlipped ? point.y : host.bounds.maxY - point.y
            let color = try #require(bitmap.colorAt(x: Int(point.x * scale), y: Int(y * scale))?
                .usingColorSpace(.deviceRGB))
            return color.redComponent * color.alphaComponent
        }
        let middle = CGPoint(x: surface.midX, y: host.isFlipped ? surface.maxY - 18 : surface.minY + 18)
        let cardFill = try fill(at: middle)
        #expect(cardFill > 0.06, "The editor must still render its visible card fill")
        var comparedPixels = 0
        for trailing in [false, true] {
            for dx in 1..<20 {
                for dy in 1..<20 {
                    let point = CGPoint(
                        x: trailing ? surface.maxX - CGFloat(dx) : surface.minX + CGFloat(dx),
                        y: host.isFlipped ? surface.maxY - CGFloat(dy) : surface.minY + CGFloat(dy)
                    )
                    let inside = contour.contains(point)
                    let neighbors = [CGPoint(x: -0.75, y: 0), CGPoint(x: 0.75, y: 0),
                                     CGPoint(x: 0, y: -0.75), CGPoint(x: 0, y: 0.75)]
                    guard neighbors.allSatisfy({ contour.contains(CGPoint(x: point.x + $0.x, y: point.y + $0.y)) == inside }) else { continue }
                    #expect((try fill(at: point) > cardFill / 2) == inside,
                            "The editor bottom corner must follow the shared inset continuous contour at \(point)")
                    comparedPixels += 1
                }
            }
        }
        #expect(comparedPixels > 500)
        #expect(draft.text == "A note")
    }
}
