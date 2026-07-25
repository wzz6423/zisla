import AppKit
import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct TransferPasteboardTests {
    @Test
    func emptyPasteboardReturnsNoItems() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()

        #expect(TransferPasteboard.readShareableItems(from: pasteboard).isEmpty)
    }

    @Test
    func plainTextIsReadableAsText() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("  hello share  ", forType: .string))

        #expect(
            TransferPasteboard.readShareableItems(from: pasteboard)
                == [.text("hello share")]
        )
    }

    @Test
    func textURLStaysTextAndIsNotForcedToFile() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let value = "https://example.com/path"
        #expect(pasteboard.setString(value, forType: .string))

        #expect(
            TransferPasteboard.readShareableItems(from: pasteboard)
                == [.text(value)]
        )
    }

    @Test
    func localFileURLsAreReadable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileA = directory.appendingPathComponent("a.txt")
        let fileB = directory.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: fileA)
        try Data("b".utf8).write(to: fileB)

        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([fileA as NSURL, fileB as NSURL]))

        let items = TransferPasteboard.readShareableItems(from: pasteboard)
        #expect(items == [
            .file(fileA.standardizedFileURL),
            .file(fileB.standardizedFileURL),
        ])
    }

    @Test
    func missingLocalFileURLsAreIgnored() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-missing-\(UUID().uuidString).txt")
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([missing as NSURL]))

        #expect(TransferPasteboard.readShareableItems(from: pasteboard).isEmpty)
    }

    @Test
    func filesTakePriorityOverTextOnSamePasteboard() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("only.txt")
        try Data("x".utf8).write(to: file)

        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        item.setString("also text", forType: .string)
        #expect(pasteboard.writeObjects([item]))

        let items = TransferPasteboard.readShareableItems(from: pasteboard)
        #expect(items == [.file(file.standardizedFileURL)])
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("dev.wzz.zisla.tests.transfer.\(UUID().uuidString)"))
    }
}
