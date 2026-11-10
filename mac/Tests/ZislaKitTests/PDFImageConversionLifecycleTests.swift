import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import ZislaKit

struct PDFImageConversionLifecycleTests {
    @Test func imagesBecomePagesInSelectionOrderWithoutChangingSources() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try image(root, name: "first", width: 24, height: 12)
        let second = try image(root, name: "second", width: 36, height: 18)
        let before = try [Data(contentsOf: first), Data(contentsOf: second)]
        let output = root.appendingPathComponent("images.pdf")
        try PDFProcessingService().convertImagesToPDF([second, first], to: output)
        let pdf = try #require(PDFDocument(url: output))
        #expect(pdf.pageCount == 2)
        #expect(pdf.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 36, height: 18))
        #expect(pdf.page(at: 1)?.bounds(for: .mediaBox).size == CGSize(width: 24, height: 12))
        #expect(try [Data(contentsOf: first), Data(contentsOf: second)] == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["first.png", "images.pdf", "second.png"])
    }

    @Test(arguments: ["cancel before", "cancel during", "cancel before commit", "corrupt second"])
    func failedOrCancelledConversionRemovesOnlyItsPartialOutput(_ failure: String) throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try image(root, name: "first", width: 24, height: 12)
        let second = try image(root, name: "second", width: 36, height: 18)
        if failure == "corrupt second" { try Data("corrupt image".utf8).write(to: second) }
        let before = try [Data(contentsOf: first), Data(contentsOf: second)]
        let output = root.appendingPathComponent("images.pdf")
        let cancellation = CancellationProbe(stopAt: ["cancel before": 1, "cancel during": 3, "cancel before commit": 4][failure])
        if failure == "corrupt second" {
            #expect(throws: PDFProcessingError.unsupportedImage(second)) {
                try PDFProcessingService().convertImagesToPDF([first, second], to: output)
            }
        } else {
            #expect(throws: CancellationError.self) {
                try PDFProcessingService().convertImagesToPDF([first, second], to: output, checkCancellation: cancellation.check)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try [Data(contentsOf: first), Data(contentsOf: second)] == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["first.png", "second.png"])
    }

    @Test func existingOutputAndDestinationCreatedDuringWorkArePreserved() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try image(root, name: "source", width: 24, height: 12)
        let output = root.appendingPathComponent("images.pdf")
        let old = Data("existing PDF".utf8)
        try old.write(to: output)
        #expect(throws: PDFProcessingError.outputAlreadyExists(output)) {
            try PDFProcessingService().convertImagesToPDF([source], to: output)
        }
        #expect(try Data(contentsOf: output) == old)
        #expect(throws: PDFProcessingError.outputMatchesInput(source)) {
            try PDFProcessingService().convertImagesToPDF([source], to: source)
        }
        try FileManager.default.removeItem(at: output)
        let race = DestinationProbe(url: output, data: old)
        #expect(throws: (any Error).self) {
            try PDFProcessingService().convertImagesToPDF([source], to: output, checkCancellation: race.check)
        }
        #expect(try Data(contentsOf: output) == old)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["images.pdf", "source.png"])
    }

    @Test func emptyConversionCreatesNoOutputOrDirectory() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: PDFProcessingError.emptyPageSelection) {
            try PDFProcessingService().convertImagesToPDF([], to: root.appendingPathComponent("missing/images.pdf"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-image-lifecycle-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func image(_ root: URL, name: String, width: Int, height: Int) throws -> URL {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = root.appendingPathComponent(name + ".png")
        let writer = try #require(CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(writer))
        return output
    }

    private final class CancellationProbe: @unchecked Sendable {
        let stopAt: Int?
        private let lock = NSLock()
        private var count = 0
        init(stopAt: Int?) { self.stopAt = stopAt }
        func check() throws {
            if lock.withLock({ count += 1; return count == stopAt }) { throw CancellationError() }
        }
    }

    private final class DestinationProbe: @unchecked Sendable {
        let url: URL
        let data: Data
        private let lock = NSLock()
        private var count = 0
        init(url: URL, data: Data) { self.url = url; self.data = data }
        func check() throws {
            if lock.withLock({ count += 1; return count == 3 }) { try data.write(to: url) }
        }
    }
}
