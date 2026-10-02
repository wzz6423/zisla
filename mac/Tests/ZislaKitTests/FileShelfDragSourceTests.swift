import AppKit
import Foundation
import SwiftUI
import Testing

@testable import ZislaKit

@MainActor
struct FileShelfDragSourceTests {
    @Test(arguments: [
        NSSize(width: 84, height: 84),
        NSSize(width: 84, height: 21),
        NSSize(width: 21, height: 84),
        NSSize(width: 512, height: 512),
        NSSize(width: 4, height: 4),
    ])
    func thumbnailFitsProposedFrameWithoutResizingSourceImage(imageSize: NSSize) throws {
        let image = NSImage(size: imageSize, flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let hostingView = NSHostingView(rootView: FileShelfDragSourceView(
            payload: .text("Synthetic image"),
            image: image,
            onOpen: {},
            onReveal: {},
            onCopy: {},
            onRemove: {}
        ).frame(width: 42, height: 42))
        hostingView.frame = NSRect(x: 0, y: 0, width: 42, height: 42)
        hostingView.layoutSubtreeIfNeeded()
        let source = try #require(dragSource(in: hostingView))

        #expect(source.frame.size == NSSize(width: 42, height: 42))
        #expect(hostingView.bounds.contains(source.convert(source.bounds, to: hostingView)))
        #expect(source.image === image)
        #expect(image.size == imageSize)

        let renderedBounds = try renderedImageBounds(in: source)
        let scale = min(42 / imageSize.width, 42 / imageSize.height)
        #expect(abs(renderedBounds.width - imageSize.width * scale) <= 1)
        #expect(abs(renderedBounds.height - imageSize.height * scale) <= 1)
        #expect(abs(renderedBounds.midX - 21) <= 1)
        #expect(abs(renderedBounds.midY - 21) <= 1)
    }

    @Test
    func emptyImageTracksChangingParentConstraints() throws {
        let image = NSImage(size: .zero)
        let content = FileShelfDragSourceView(
            payload: .text("Synthetic empty image"),
            image: image,
            onOpen: {},
            onReveal: {},
            onCopy: {},
            onRemove: {}
        )
        let hostingView = NSHostingView(rootView: content.frame(width: 42, height: 42))
        hostingView.sizingOptions = []

        for size in [NSSize.zero, NSSize(width: 1, height: 1),
                     NSSize(width: 28, height: 56), NSSize(width: 56, height: 28)] {
            hostingView.rootView = content.frame(width: size.width, height: size.height)
            hostingView.frame.size = size
            hostingView.layoutSubtreeIfNeeded()
            let source = try #require(dragSource(in: hostingView))

            #expect(source.frame.size == size)
            #expect(source.image === image)
            #expect(image.size == .zero)
        }
    }

    @Test
    func localAndExternalDragsOnlyAllowCopy() {
        let source = FileShelfDraggingView()

        #expect(source.sourceOperationMask(for: .withinApplication) == .copy)
        #expect(source.sourceOperationMask(for: .outsideApplication) == .copy)
        #expect(source.ignoresModifierKeys)
    }

    @Test
    func fileAndDirectoryURLsUseFileURLPasteboardPayloads() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directoryURL = temporaryDirectory.appendingPathComponent("Folder", isDirectory: true)
        let fileURL = temporaryDirectory.appendingPathComponent("File.txt", isDirectory: false)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try Data().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }

        for url in [fileURL, directoryURL] {
            pasteboard.clearContents()
            #expect(pasteboard.writeObjects([FileShelfPasteboard.pasteboardWriter(for: .file(url))]))

            let values = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [NSURL]
            #expect(values?.map { $0 as URL } == [url])
        }
    }

    private func dragSource(in view: NSView) -> FileShelfDraggingView? {
        if let source = view as? FileShelfDraggingView { return source }
        return view.subviews.lazy.compactMap { dragSource(in: $0) }.first
    }

    private func renderedImageBounds(in view: NSView) throws -> NSRect {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var rect = NSRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.5 {
                    rect = rect.union(NSRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        return NSRect(x: rect.minX / scale, y: rect.minY / scale,
                      width: rect.width / scale, height: rect.height / scale)
    }
}
