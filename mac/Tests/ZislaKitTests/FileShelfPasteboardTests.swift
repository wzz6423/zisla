import AppKit
import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct FileShelfPasteboardTests {
    @Test
    func fileURLsRoundTripThroughPasteboardWithoutDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("first.txt")
        let second = directory.appendingPathComponent("second.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        #expect(FileShelfPasteboard.writeFileURLs([first, first, second], to: pasteboard))
        #expect(
            FileShelfPasteboard.readFileURLs(from: pasteboard)
                == [first.standardizedFileURL, second.standardizedFileURL]
        )
    }

    @Test
    func pasteboardReaderIgnoresNonFilesAndMissingFiles() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-missing-\(UUID().uuidString).txt")
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([missing as NSURL]))

        #expect(FileShelfPasteboard.readFileURLs(from: pasteboard).isEmpty)
        #expect(!FileShelfPasteboard.writeFileURLs([], to: pasteboard))
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("dev.wzz.zisla.tests.file-shelf.\(UUID().uuidString)"))
    }
}
