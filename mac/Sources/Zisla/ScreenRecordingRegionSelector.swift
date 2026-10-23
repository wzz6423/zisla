import AppKit
import ZislaCore

enum ScreenRecordingRegionGeometry {
    static func selection(from start: CGPoint, to end: CGPoint, size: CGSize) -> RecordingRect? {
        guard [start.x, start.y, end.x, end.y, size.width, size.height].allSatisfy(\.isFinite),
              size.width > 0, size.height > 0 else { return nil }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y))
            .intersection(CGRect(origin: .zero, size: size))
        guard rect.width >= 2, rect.height >= 2 else { return nil }
        return .init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

@MainActor
final class ScreenRecordingRegionSelector {
    var onFinish: ((RecordingRect?) -> Void)?
    private let panel: RegionPanel
    private let selectionView: RegionView

    init(screen: NSScreen) {
        panel = RegionPanel(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        selectionView = RegionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        panel.contentView = selectionView
        selectionView.finish = { [weak self] value in self?.finish(value) }
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(selectionView)
    }

    func cancel() { finish(nil) }

    private func finish(_ value: RecordingRect?) {
        panel.orderOut(nil)
        let completion = onFinish
        onFinish = nil
        completion?(value)
    }
}

private final class RegionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class RegionView: NSView {
    var finish: ((RecordingRect?) -> Void)?
    private var start: CGPoint?
    private var current: CGPoint?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        let mask = NSBezierPath(rect: bounds)
        if let start, let current, let region = ScreenRecordingRegionGeometry.selection(from: start, to: current, size: bounds.size) {
            let rect = CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
            mask.appendRect(rect)
            mask.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.35).setFill()
            mask.fill()
            NSColor.systemRed.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 2
            border.stroke()
        } else {
            NSColor.black.withAlphaComponent(0.35).setFill()
            mask.fill()
        }
        let instruction = AppLocalization.text("拖动选择录制区域，按 Esc 取消") as NSString
        instruction.draw(at: CGPoint(x: 24, y: 24), withAttributes: [.foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 16, weight: .medium)])
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        if let selection = ScreenRecordingRegionGeometry.selection(from: start, to: end, size: bounds.size) { finish?(selection) }
        else { self.start = nil; current = nil; needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finish?(nil) } else { super.keyDown(with: event) }
    }
}
