import AppKit
import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import ZislaKit

struct PDFProcessingServiceTests {
    @Test
    func inspectionReturnsDocumentMetadata() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        try writePDF(to: source, pageCount: 2)

        let summary = try PDFProcessingService().inspect(source)

        #expect(summary.pageCount == 2)
        #expect(summary.fileSize > 0)
        #expect(!summary.isLocked)
    }

    @Test
    func parsesPageRangesAndExportsDocumentText() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("source.txt")
        try writeTextPDF(to: source, text: "Zisla PDF text", pageCount: 3)
        let service = PDFProcessingService()

        #expect(try service.pageIndexes(in: source, matching: "3, 1-2, 1") == [2, 0, 1])
        // A Chinese keyboard produces these separators and digits; they must parse like their ASCII twins.
        #expect(try service.pageIndexes(in: source, matching: "３，１ - ２") == [2, 0, 1])
        #expect(throws: PDFProcessingError.invalidPageSelection("1-4")) {
            try service.pageIndexes(in: source, matching: "1-4")
        }
        try service.exportText(from: source, pageIndexes: [1], outputURL: output)

        let exported = try String(contentsOf: output, encoding: .utf8)
        #expect(exported.contains("Zisla PDF text"))
    }

    @Test
    func mergePreservesPageCountAndInputOrder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.pdf")
        let second = directory.appendingPathComponent("second.pdf")
        let output = directory.appendingPathComponent("merged.pdf")
        try writePDF(to: first, pageCount: 1)
        try writePDF(to: second, pageCount: 2)

        try PDFProcessingService().merge([first, second], to: output)

        #expect(try PDFProcessingService().inspect(output).pageCount == 3)
    }

    @Test
    func exportAndRotateOnlyAffectsRequestedPages() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let exported = directory.appendingPathComponent("exported.pdf")
        let rotated = directory.appendingPathComponent("rotated.pdf")
        try writePDF(to: source, pageCount: 3)
        let service = PDFProcessingService()

        try service.exportPages(from: source, pageIndexes: [2, 0], to: exported)
        try service.rotate(exported, pageIndexes: [1], degrees: 90, to: rotated)

        let document = try #require(PDFDocument(url: rotated))
        #expect(document.pageCount == 2)
        #expect(document.page(at: 0)?.rotation == 0)
        #expect(document.page(at: 1)?.rotation == 90)
    }

    @Test
    func splitWritesEachRequestedPageGroup() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let firstOutput = directory.appendingPathComponent("part-1.pdf")
        let secondOutput = directory.appendingPathComponent("part-2.pdf")
        try writePDF(to: source, pageCount: 3)

        try PDFProcessingService().split(
            source,
            pageGroups: [[0], [1, 2]],
            outputURLs: [firstOutput, secondOutput]
        )

        #expect(try PDFProcessingService().inspect(firstOutput).pageCount == 1)
        #expect(try PDFProcessingService().inspect(secondOutput).pageCount == 2)
    }

    @Test
    func refusesToOverwriteInputOrExistingOutput() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let existing = directory.appendingPathComponent("existing.pdf")
        try writePDF(to: source, pageCount: 1)
        try writePDF(to: existing, pageCount: 1)
        let service = PDFProcessingService()

        #expect(throws: PDFProcessingError.outputMatchesInput(source)) {
            try service.exportPages(from: source, pageIndexes: [0], to: source)
        }
        #expect(throws: PDFProcessingError.outputAlreadyExists(existing)) {
            try service.exportPages(from: source, pageIndexes: [0], to: existing)
        }
    }

    @Test
    func splitRejectsDuplicateOutputsBeforeWritingFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("part.pdf")
        try writePDF(to: source, pageCount: 2)

        #expect(throws: PDFProcessingError.duplicateOutput(output)) {
            try PDFProcessingService().split(
                source,
                pageGroups: [[0], [1]],
                outputURLs: [output, output]
            )
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test
    func convertsImagesToPDFAndRendersPagesBackToPNG() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("source.png")
        let pdf = directory.appendingPathComponent("images.pdf")
        let renderedDirectory = directory.appendingPathComponent("rendered", isDirectory: true)
        try writePNG(to: image)
        let service = PDFProcessingService()

        try service.convertImagesToPDF([image], to: pdf)
        let rendered = try service.renderPages(from: pdf, to: renderedDirectory, dpi: 72)

        #expect(try service.inspect(pdf).pageCount == 1)
        #expect(rendered.count == 1)
        #expect(NSImage(contentsOf: rendered[0]) != nil)
    }

    @Test
    func textWatermarkWritesASeparatePDF() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("watermarked.pdf")
        try writePDF(to: source, pageCount: 2)

        try PDFProcessingService().addTextWatermark(
            to: source,
            watermark: PDFTextWatermark(text: "CONFIDENTIAL"),
            outputURL: output
        )

        #expect(try PDFProcessingService().inspect(output).pageCount == 2)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test
    func cropsOnlyTheRequestedPages() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("cropped.pdf")
        try writePDF(to: source, pageCount: 2)

        try PDFProcessingService().crop(
            source,
            pageIndexes: [1],
            to: CGRect(x: 20, y: 20, width: 160, height: 150),
            outputURL: output
        )

        let document = try #require(PDFDocument(url: output))
        #expect(document.page(at: 0)?.bounds(for: .cropBox) == CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(document.page(at: 1)?.bounds(for: .cropBox) == CGRect(x: 20, y: 20, width: 160, height: 150))
    }

    @Test
    func addsImageWatermarkAndPageNumbersToEveryPage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let image = directory.appendingPathComponent("watermark.png")
        let imageWatermarked = directory.appendingPathComponent("image-watermarked.pdf")
        let numbered = directory.appendingPathComponent("numbered.pdf")
        try writePDF(to: source, pageCount: 2)
        try writePNG(to: image)
        let service = PDFProcessingService()

        try service.addImageWatermark(
            to: source,
            imageURL: image,
            position: .topTrailing,
            outputURL: imageWatermarked
        )
        try service.addPageNumbers(
            to: imageWatermarked,
            style: PDFPageNumberStyle(prefix: "Page ", position: .bottom),
            outputURL: numbered
        )

        #expect(try service.inspect(numbered).pageCount == 2)
        let firstPageText = try #require(PDFDocument(url: numbered)?.page(at: 0)?.string)
        let secondPageText = try #require(PDFDocument(url: numbered)?.page(at: 1)?.string)
        #expect(firstPageText.contains("Page 1"))
        #expect(secondPageText.contains("Page 2"))
    }

    @Test
    func protectsAndUnlocksPDFWithTheCorrectPassword() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let protected = directory.appendingPathComponent("protected.pdf")
        let unlocked = directory.appendingPathComponent("unlocked.pdf")
        try writePDF(to: source, pageCount: 1)
        let service = PDFProcessingService()

        try service.protect(
            source,
            with: PDFPasswordProtection(userPassword: "open-sesame", ownerPassword: "owner-secret"),
            outputURL: protected
        )

        let protectedDocument = try #require(PDFDocument(url: protected))
        #expect(protectedDocument.isEncrypted)
        #expect(protectedDocument.isLocked)
        let protectedSummary = try service.inspect(protected)
        #expect(protectedSummary.isEncrypted)
        #expect(protectedSummary.isLocked)
        #expect(throws: PDFProcessingError.incorrectPassword) {
            try service.unlock(protected, password: "incorrect", outputURL: unlocked)
        }

        try service.unlock(protected, password: "open-sesame", outputURL: unlocked)
        #expect(try service.inspect(unlocked).pageCount == 1)
    }

    @Test
    func updatesStandardMetadataWithoutChangingTheInput() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("metadata.pdf")
        try writePDF(to: source, pageCount: 1)
        let service = PDFProcessingService()

        try service.updateMetadata(
            of: source,
            metadata: PDFDocumentMetadata(
                title: "Project Plan",
                author: "zisla",
                keywords: ["internal", "2026"]
            ),
            outputURL: output
        )

        let metadata = try service.metadata(for: output)
        #expect(metadata.title == "Project Plan")
        #expect(metadata.author == "zisla")
        #expect(metadata.keywords == ["internal", "2026"])
        #expect(try service.inspect(source).pageCount == 1)
    }

    @Test
    func pageCopyOperationsPreserveDocumentMetadata() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("exported.pdf")
        try writePDF(to: source, pageCount: 2)
        let document = try #require(PDFDocument(url: source))
        document.documentAttributes = [
            AnyHashable(PDFDocumentAttribute.titleAttribute): "Preserved title",
            AnyHashable(PDFDocumentAttribute.authorAttribute): "zisla",
        ]
        #expect(document.write(to: source))

        let service = PDFProcessingService()
        try service.exportPages(from: source, pageIndexes: [1], to: output)

        let metadata = try service.metadata(for: output)
        #expect(metadata.title == "Preserved title")
        #expect(metadata.author == "zisla")
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func writePDF(to url: URL, pageCount: Int) throws {
    var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 200)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    for _ in 0..<pageCount {
        context.beginPDFPage(nil)
        context.endPDFPage()
    }
    context.closePDF()
}

private func writeTextPDF(to url: URL, text: String, pageCount: Int) throws {
    var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 200)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: text,
        attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.black,
        ]
    ))
    for _ in 0..<pageCount {
        context.beginPDFPage(nil)
        context.textPosition = CGPoint(x: 20, y: 100)
        CTLineDraw(line, context)
        context.endPDFPage()
    }
    context.closePDF()
}

private func writePNG(to url: URL) throws {
    let image = NSImage(size: NSSize(width: 120, height: 80))
    image.lockFocus()
    NSColor.systemRed.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 120, height: 80)).fill()
    image.unlockFocus()
    guard let representation = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()),
          let data = representation.representation(using: .png, properties: [:])
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}
