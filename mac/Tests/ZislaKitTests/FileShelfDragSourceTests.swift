import AppKit
import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct FileShelfDragSourceTests {
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

        let source = FileShelfDraggingView()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))

        for url in [fileURL, directoryURL] {
            pasteboard.clearContents()
            #expect(pasteboard.writeObjects([source.pasteboardWriter(for: url)]))

            let values = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [NSURL]
            #expect(values?.map { $0 as URL } == [url])
        }
    }
}
