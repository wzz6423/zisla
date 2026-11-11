import AppKit
import Combine
import Darwin
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ImageToolsRecognitionTests {
    @Test
    func batchRecognitionReusesScreenshotReadingOrderAndContinuesAfterEachFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        let urls = ["first.png", "empty.png", "corrupt.png", "unavailable.png", "last.png"].map { fixture.root.appendingPathComponent($0) }
        let image = try makeImage()
        let gate = RecognitionGate()
        let fragments = [
            ScreenshotRecognizedFragment(text: "second", boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1)),
            ScreenshotRecognizedFragment(text: "first", boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.1)),
        ]
        let pendingTask = model.start(urls: urls, service: service,
            loadImage: { url in
                Self.checkBackgroundThread()
                if url.lastPathComponent == "corrupt.png" { throw SyntheticFailure() }
                return image
            }, recognizeImage: { _, operation in
                Self.checkBackgroundThread()
                let call = await gate.nextCall()
                if call == 1 { return try await gate.recognize(operation) }
                if call == 2 { return [] }
                if call == 3 { throw ImageProcessingError.engineUnavailable }
                return fragments
            })
        let task = try #require(pendingTask)
        await gate.waitUntilStarted()
        #expect(model.isProcessing && model.completed == 0 && model.total == 5)
        #expect(model.currentInputURL == urls[0])
        await gate.finish(fragments)
        await task.value
        #expect(model.results.map(\.inputURL) == [urls[0], urls[4]])
        #expect(model.results.allSatisfy { $0.text == "first\nsecond" })
        #expect(model.results.allSatisfy { !$0.table.isEmpty })
        #expect(model.failures.map(\.inputURL) == [urls[1], urls[2], urls[3]])
        #expect(model.failures[0].message == AppLocalization.text("未识别到文字"))
        #expect(model.completed == 5 && model.total == 5)
        #expect(!model.isProcessing && model.currentInputURL == nil)
        #expect(model.message == AppLocalization.text("已识别 %ld 张图片，失败 %ld 项", 2, 3))
    }

    @Test(arguments: [false, true])
    func emptyAndWhitespaceResultsHaveNoExportableDocuments(whitespace: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        let image = try makeImage()
        let pendingTask = model.start(urls: [fixture.image], service: service, loadImage: { _ in image }, recognizeImage: { _, _ in
            whitespace ? Self.fragments(" \n\t ") : []
        })
        let task = try #require(pendingTask)
        await task.value
        #expect(model.results.isEmpty)
        #expect(model.failures.count == 1)
        #expect(model.failures[0].message == AppLocalization.text("未识别到文字"))
        let export = try #require(model.exportTexts(to: fixture.root))
        await export.value
        #expect(model.message == ImageProcessingError.emptyInput.localizedDescription)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == ["source.png"])
    }

    @Test
    func emptyInputClearsOldResultsAndDoesNotDispatchRecognition() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        try await recognize(model, image: makeImage(), urls: [fixture.image])
        #expect(model.results.count == 1)
        let task = model.start(urls: [], service: service, loadImage: { _ in
            Issue.record("Empty input must not load an image")
            throw SyntheticFailure()
        }, recognizeImage: { _, _ in
            Issue.record("Empty input must not invoke Vision")
            return []
        })
        #expect(task == nil)
        #expect(model.results.isEmpty && model.failures.isEmpty)
        #expect(model.completed == 0 && model.total == 0 && !model.isProcessing)
        #expect(model.message == ImageProcessingError.emptyInput.localizedDescription)
    }

    @Test
    func invalidInputsAndMissingCodecReportEachFailureWithoutEnteringVision() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let corrupt = fixture.root.appendingPathComponent("corrupt.png")
        try Data("invalid raster".utf8).write(to: corrupt)
        let unsupported = fixture.root.appendingPathComponent("source.txt")
        try Data("text".utf8).write(to: unsupported)
        let linked = fixture.root.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: fixture.image)
        let codec = fixture.root.appendingPathComponent("codec.jxl")
        try Data([0xff, 0x0a, 0, 0, 0, 0, 0, 0]).write(to: codec)
        let urls = [URL(string: "https://example.invalid/source.png")!, fixture.root.appendingPathComponent("missing.png"),
                    unsupported, linked, corrupt, codec]
        let model = ImageToolsRecognitionModel()
        let pendingTask = model.start(urls: urls, service: service, recognizeImage: { _, _ in
            Issue.record("Unusable input must not reach Vision")
            return []
        })
        let task = try #require(pendingTask)
        await task.value
        #expect(model.results.isEmpty)
        #expect(model.failures.map(\.inputURL) == urls)
        #expect(model.completed == urls.count && !model.isProcessing)
        #expect(model.failures.last?.message == ImageProcessingError.engineUnavailable.localizedDescription)
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
    }

    @Test
    func cancellationBeforeDispatchPreservesTheClearedState() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        let pendingTask = model.start(urls: [fixture.image], service: service, loadImage: { _ in
            Issue.record("Cancellation before dispatch must not load an image")
            throw SyntheticFailure()
        })
        let task = try #require(pendingTask)
        model.clear()
        await task.value
        #expect(!model.isProcessing && model.completed == 0 && model.total == 0)
        #expect(model.results.isEmpty && model.failures.isEmpty && model.message == nil)
        #expect(model.currentInputURL == nil)
    }

    @Test(arguments: [false, true])
    func cancellationDuringLoadingDiscardsLateImagesAndNeverStartsVision(replace: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        let image = try makeImage()
        let gate = LoadingGate()
        let pendingTask = model.start(urls: [fixture.image], service: service, loadImage: { _ in
            try await gate.load()
        }, recognizeImage: { _, _ in
            Issue.record("An image returned after cancellation must not start Vision")
            return []
        })
        let task = try #require(pendingTask)
        await gate.waitUntilStarted()
        if replace {
            model.clear()
            try await recognize(model, image: image, urls: [fixture.root.appendingPathComponent("new.png")], text: "new capture")
        } else { model.cancel() }
        let expectedMessage = model.message
        await gate.finish(image)
        await task.value
        #expect(!model.isProcessing)
        #expect(model.message == expectedMessage)
        #expect(model.results.map(\.text) == (replace ? ["new capture"] : []))
        #expect(model.failures.isEmpty)
    }

    @Test
    func repeatedStartIsIgnoredAndAStaleRecognitionCannotReplaceNewResults() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        let image = try makeImage()
        let gate = RecognitionGate()
        let pendingOld = model.start(urls: [fixture.image], service: service, loadImage: { _ in image }, recognizeImage: { _, operation in
            try await gate.recognize(operation)
        })
        let old = try #require(pendingOld)
        await gate.waitUntilStarted()
        let duplicate = model.start(urls: [fixture.root.appendingPathComponent("duplicate.png")], service: service,
            loadImage: { _ in Issue.record("Repeated start must not load another image"); return image })
        #expect(duplicate == nil)
        #expect(model.total == 1 && model.currentInputURL == fixture.image)
        model.cancel()
        #expect(await gate.isCancelled())
        let newURL = fixture.root.appendingPathComponent("new.png")
        try await recognize(model, image: image, urls: [newURL], text: "new text")
        let expectedMessage = model.message
        await gate.finish(Self.fragments("stale text"))
        await old.value
        #expect(model.results.map(\.inputURL) == [newURL])
        #expect(model.results.map(\.text) == ["new text"])
        #expect(model.message == expectedMessage && !model.isProcessing)
        #expect(model.completed == 1 && model.total == 1)
    }

    @Test
    func cancelledBatchKeepsCompletedResultsAndStopsBeforeTheNextImage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        let image = try makeImage()
        let gate = RecognitionGate()
        let urls = [fixture.image, fixture.root.appendingPathComponent("second.png"), fixture.root.appendingPathComponent("third.png")]
        let pendingTask = model.start(urls: urls, service: service, loadImage: { _ in image }, recognizeImage: { _, operation in
            let call = await gate.nextCall()
            if call == 1 { return Self.fragments("completed") }
            if call == 2 { return try await gate.recognize(operation) }
            Issue.record("Cancelling must stop the remaining batch")
            return []
        })
        let task = try #require(pendingTask)
        await gate.waitUntilStarted()
        #expect(model.results.map(\.text) == ["completed"] && model.completed == 1)
        model.cancel()
        await gate.finish(Self.fragments("late second"))
        await task.value
        #expect(model.results.map(\.inputURL) == [urls[0]])
        #expect(model.failures.isEmpty && model.completed == 1 && model.total == 3)
        #expect(model.message == AppLocalization.text("已取消") && !model.isProcessing)
    }

    @Test
    func releasingTheModelCancelsVisionWithoutRetainingTheOwner() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var model: ImageToolsRecognitionModel? = ImageToolsRecognitionModel()
        let image = try makeImage()
        let gate = RecognitionGate()
        let pendingTask = model?.start(urls: [fixture.image], service: service, loadImage: { _ in image }, recognizeImage: { _, operation in
            try await gate.recognize(operation)
        })
        let task = try #require(pendingTask)
        await gate.waitUntilStarted()
        weak let released = model
        model = nil
        #expect(released == nil, "Pending OCR must not keep its view model alive")
        #expect(await gate.isCancelled(), "Releasing OCR must cancel the system request")
        await gate.finish(Self.fragments("late released result"))
        await task.value
    }

    @Test
    func textCopyOnlyRunsWhenInvokedAndPreservesTheCompleteRecognition() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        let text = "  Synthetic text\n第二行 + & <text>  "
        try await recognize(model, image: makeImage(), urls: [fixture.image], text: text)
        let item = try #require(model.results.first)
        var copies: [String] = []
        #expect(copies.isEmpty)
        model.copyText(item) { copies.append($0); return true }
        #expect(copies == [text])
        #expect(model.message == AppLocalization.text("已复制"))
        model.copyText(item) { _ in false }
        #expect(model.message == AppLocalization.text("无法写入剪贴板"))
    }

    @Test
    func textAndWorkbookExportsReuseTheScreenshotWorkbookAndPreserveTheOriginal() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        let text = "识别结果 42\n<synthetic> & value"
        try await recognize(model, image: makeImage(), urls: [fixture.image], text: text)
        let result = try #require(model.results.first)
        let destination = fixture.root.appendingPathComponent("result.txt")
        let textTask = try #require(model.exportText(result, to: destination))
        await textTask.value
        #expect(try String(contentsOf: destination, encoding: .utf8) == text)
        #expect(model.message == AppLocalization.text("已保存 %@", destination.lastPathComponent))
        let workbook = fixture.root.appendingPathComponent("result.xlsx")
        let tableTask = try #require(model.exportTable(result, to: workbook))
        await tableTask.value
        let output = try await AIAgentProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-p", workbook.path, "xl/worksheets/sheet1.xml"], workingDirectoryURL: fixture.root)
        #expect(output.status == 0)
        #expect(String(data: output.standardOutput, encoding: .utf8) == ScreenshotXLSXExporter.worksheetXML(for: result.table))
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
        #expect(model.results == [result] && !model.isProcessing)
    }

    @Test
    func exportPermissionsFollowTheCallingProcessUmaskAndKeepStagingPrivate() async throws {
        let maskKey = "ZISLA_OCR_EXPORT_TEST_UMASK"
        if let maskText = ProcessInfo.processInfo.environment[maskKey] {
            let mask = try #require(mode_t(maskText, radix: 8))
            // This branch only runs in the dedicated child, never in the shared test host.
            umask(mask)
            let fixture = try Fixture()
            defer { fixture.remove() }
            let result = Self.result(inputURL: fixture.image)
            let documents: [ImageToolsRecognitionDocument] = [
                .init(result: result, format: .text, destination: fixture.root.appendingPathComponent("result.txt")),
                .init(result: result, format: .table, destination: fixture.root.appendingPathComponent("result.xlsx")),
            ]
            var sawStaging = false
            _ = try ImageToolsRecognitionExporter.write(documents, stagingParent: fixture.root, checkCancellation: {
                for url in try FileManager.default.contentsOfDirectory(at: fixture.root, includingPropertiesForKeys: nil)
                    where url.lastPathComponent.hasPrefix("zisla-image-ocr-export-") {
                    sawStaging = true
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    #expect((attributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o700)
                }
            })
            #expect(sawStaging)
            for document in documents {
                let attributes = try FileManager.default.attributesOfItem(atPath: document.destination.path)
                #expect((attributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o666 & ~mask,
                    "Final exports must honor the caller's sharing policy for both formats")
                #expect(!(try Data(contentsOf: document.destination)).isEmpty)
            }
            #expect(try String(contentsOf: documents[0].destination, encoding: .utf8) == result.text)
            #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
            #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted() == ["result.txt", "result.xlsx", "source.png"])
            print("OCR export permissions verified for umask \(maskText)")
            return
        }

        let fixture = try Fixture()
        defer { fixture.remove() }
        var arguments: [String] = []
        if let bundleIndex = CommandLine.arguments.firstIndex(of: "--test-bundle-path") {
            arguments = ["--test-bundle-path", CommandLine.arguments[bundleIndex + 1]]
        }
        arguments += ["--testing-library", "swift-testing", "--filter",
            "ImageToolsRecognitionTests/exportPermissionsFollowTheCallingProcessUmaskAndKeepStagingPrivate"]
        for mask in ["022", "027", "077"] {
            var environment = ProcessInfo.processInfo.environment
            environment[maskKey] = mask
            let child = try await AIAgentProcessRunner.run(
                executableURL: URL(fileURLWithPath: CommandLine.arguments[0]), arguments: arguments,
                environment: environment, workingDirectoryURL: fixture.root, timeout: 30,
                maximumOutputBytes: 128 * 1_024, maximumErrorBytes: 128 * 1_024)
            #expect(child.status == 0 && !child.didTimeout,
                "Isolated umask \(mask) regression: \(String(decoding: child.standardOutput, as: UTF8.self)) \(child.standardError)")
            #expect(String(decoding: child.standardOutput, as: UTF8.self).contains("OCR export permissions verified for umask \(mask)"))
        }
    }

    @Test
    func batchTextExportUsesUniqueCaseInsensitiveNamesAndRejectsExistingFilesBeforeWriting() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        let urls = [fixture.root.appendingPathComponent("one/Photo.png"), fixture.root.appendingPathComponent("two/photo.png"),
                    fixture.root.appendingPathComponent("three/Photo-2.png")]
        try await recognize(model, image: makeImage(), urls: urls, text: "same text")
        let directory = fixture.root.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let documents = ImageToolsRecognitionExporter.textDocuments(model.results, in: directory)
        #expect(documents.map(\.destination.lastPathComponent) == ["Photo-ocr.txt", "photo-ocr-2.txt", "Photo-2-ocr.txt"])
        let existing = documents[1].destination
        try Data("existing text".utf8).write(to: existing)
        let failed = try #require(model.exportTexts(to: directory))
        await failed.value
        #expect(!model.isProcessing && model.message?.contains(existing.lastPathComponent) == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [existing.lastPathComponent])
        #expect(try String(contentsOf: existing, encoding: .utf8) == "existing text")
        try FileManager.default.removeItem(at: existing)
        let successful = try #require(model.exportTexts(to: directory))
        await successful.value
        #expect(model.message == AppLocalization.text("已导出 %ld 份文字", 3))
        #expect(try documents.allSatisfy { try String(contentsOf: $0.destination, encoding: .utf8) == "same text" })
    }

    @Test(arguments: ["original", "existing", "link", "dangling link", "directory", "duplicate", "invalid URL", "null path", "missing directory", "parent link", "empty text", "empty table"])
    func exportRejectsUnsafeDestinationsAndEmptyResultsWithoutSideEffects(outcome: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let result = Self.result(inputURL: fixture.image)
        let destination = fixture.root.appendingPathComponent("result.txt")
        var documents: [ImageToolsRecognitionDocument] = [.init(result: result, format: .text, destination: destination)]
        switch outcome {
        case "original": documents = [.init(result: result, format: .text, destination: fixture.image)]
        case "existing": try Data("existing".utf8).write(to: destination)
        case "link": try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: fixture.image)
        case "dangling link": try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: fixture.root.appendingPathComponent("missing"))
        case "directory": try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        case "duplicate": documents += documents
        case "invalid URL": documents = [.init(result: result, format: .text, destination: URL(string: "https://example.invalid/result.txt")!)]
        case "null path": documents = [.init(result: result, format: .text, destination: URL(fileURLWithPath: fixture.root.path + "/bad\0name"))]
        case "missing directory": documents = [.init(result: result, format: .text, destination: fixture.root.appendingPathComponent("missing/result.txt"))]
        case "parent link":
            let parent = fixture.root.appendingPathComponent("parent")
            try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: fixture.root)
            documents = [.init(result: result, format: .text, destination: parent.appendingPathComponent("result.txt"))]
        case "empty text":
            documents = [.init(result: .init(inputURL: fixture.image, text: "", table: result.table), format: .text, destination: destination)]
        default:
            documents = [.init(result: .init(inputURL: fixture.image, text: "text", table: .init(rows: [], merges: [])), format: .table, destination: destination)]
        }
        let before = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
        #expect(throws: (any Error).self) {
            try ImageToolsRecognitionExporter.write(documents, stagingParent: fixture.root)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted() == before)
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
        if outcome == "existing" { #expect(try String(contentsOf: destination, encoding: .utf8) == "existing") }
        if outcome == "link" || outcome == "dangling link" {
            #expect(try destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        }
    }

    @Test
    func aDeletedOriginalPathStillCannotBeUsedAsAnExportDestination() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.image)
        let result = Self.result(inputURL: fixture.image)
        #expect(throws: ImageProcessingError.outputAlreadyExists(fixture.image)) {
            try ImageToolsRecognitionExporter.write([.init(result: result, format: .text, destination: fixture.image)], stagingParent: fixture.root)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).isEmpty)
    }

    @Test(arguments: [false, true])
    func exportCancellationAndFailureRollBackAllOwnedFilesAndRemoveStaging(cancel: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = fixture.root.appendingPathComponent("first.txt")
        let second = fixture.root.appendingPathComponent("second.txt")
        let result = Self.result(inputURL: fixture.image, text: String(repeating: "x", count: 200_000))
        let documents = [first, second].map { ImageToolsRecognitionDocument(result: result, format: .text, destination: $0) }
        var injected = false
        #expect(throws: (any Error).self) {
            try ImageToolsRecognitionExporter.write(documents, stagingParent: fixture.root, checkCancellation: {
                if FileManager.default.fileExists(atPath: first.path) {
                    injected = true
                    if cancel { throw CancellationError() }
                    throw SyntheticFailure()
                }
            })
        }
        #expect(injected)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == ["source.png"])
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
    }

    @Test(arguments: [false, true])
    func aDestinationCreatedAfterPreflightSurvivesWithoutOverwritingOrPartialSiblings(link: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = fixture.root.appendingPathComponent("first.txt")
        let second = fixture.root.appendingPathComponent("second.txt")
        let result = Self.result(inputURL: fixture.image)
        let documents = [first, second].map { ImageToolsRecognitionDocument(result: result, format: .text, destination: $0) }
        var injected = false
        #expect(throws: ImageProcessingError.outputAlreadyExists(second)) {
            try ImageToolsRecognitionExporter.write(documents, stagingParent: fixture.root, checkCancellation: {
                let names = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
                if !injected && names.contains(where: { $0.hasPrefix("zisla-image-ocr-export-") }) {
                    injected = true
                    if link { try FileManager.default.createSymbolicLink(at: second, withDestinationURL: fixture.root.appendingPathComponent("missing")) }
                    else { try Data("concurrent file".utf8).write(to: second) }
                }
            })
        }
        #expect(injected)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        if link { #expect(try second.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true) }
        else { #expect(try String(contentsOf: second, encoding: .utf8) == "concurrent file") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted() == ["second.txt", "source.png"])
    }

    @Test
    func rollbackPreservesAConcurrentReplacementOfAnOwnedFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let destination = fixture.root.appendingPathComponent("result.txt")
        let result = Self.result(inputURL: fixture.image)
        var injected = false
        #expect(throws: CancellationError.self) {
            try ImageToolsRecognitionExporter.write([.init(result: result, format: .text, destination: destination)], stagingParent: fixture.root,
                checkCancellation: {
                    if !injected && FileManager.default.fileExists(atPath: destination.path) {
                        injected = true
                        let replacement = fixture.root.appendingPathComponent("replacement")
                        try Data("replacement by another process".utf8).write(to: replacement)
                        try FileManager.default.removeItem(at: destination)
                        try FileManager.default.moveItem(at: replacement, to: destination)
                        throw CancellationError()
                    }
                })
        }
        #expect(injected)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "replacement by another process")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted() == ["result.txt", "source.png"])
    }

    @Test
    func pinnedDirectoryPreventsAConcurrentParentSwapFromWritingThroughALink() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let parent = fixture.root.appendingPathComponent("exports", isDirectory: true)
        let originalParent = fixture.root.appendingPathComponent("original-exports", isDirectory: true)
        let unwanted = fixture.root.appendingPathComponent("unwanted", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: unwanted, withIntermediateDirectories: false)
        let destination = parent.appendingPathComponent("result.txt")
        var replaced = false
        let result = Self.result(inputURL: fixture.image)
        _ = try ImageToolsRecognitionExporter.write([.init(result: result, format: .text, destination: destination)], stagingParent: fixture.root,
            checkCancellation: {
                let names = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
                if !replaced && names.contains(where: { $0.hasPrefix("zisla-image-ocr-export-") }) {
                    replaced = true
                    try FileManager.default.moveItem(at: parent, to: originalParent)
                    try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: unwanted)
                }
            })
        #expect(replaced)
        #expect(try FileManager.default.contentsOfDirectory(atPath: unwanted.path).isEmpty)
        #expect(try String(contentsOf: originalParent.appendingPathComponent("result.txt"), encoding: .utf8) == result.text)
    }

    @Test
    func cancellationDuringWorkbookPackagingRemovesItsStagingWithoutCreatingOutput() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let destination = fixture.root.appendingPathComponent("result.xlsx")
        var reachedPackage = false
        #expect(throws: CancellationError.self) {
            try ImageToolsRecognitionExporter.write([.init(result: Self.result(inputURL: fixture.image), format: .table, destination: destination)],
                stagingParent: fixture.root, checkCancellation: {
                    let names = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
                    if names.contains(where: { $0.hasPrefix("zisla-image-ocr-export-") }) {
                        reachedPackage = true
                        throw CancellationError()
                    }
                })
        }
        #expect(reachedPackage)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == ["source.png"])
    }

    @Test
    func cancellingAQueuedModelExportPreservesSourcesAndAllowsAnImmediateRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        try await recognize(model, image: makeImage(), urls: [fixture.image])
        let item = try #require(model.results.first)
        let destination = fixture.root.appendingPathComponent("result.txt")
        let old = try #require(model.exportText(item, to: destination))
        #expect(model.exportText(item, to: destination) == nil)
        model.cancel()
        let new = try #require(model.exportText(item, to: destination))
        await new.value
        let expectedMessage = model.message
        await old.value
        #expect(try String(contentsOf: destination, encoding: .utf8) == item.text)
        #expect(model.message == expectedMessage && !model.isProcessing)
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
    }

    @Test
    func productionLoaderAndVisionRecognizeOnlySyntheticLocalText() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("synthetic.png")
        let image = try makeImage(text: "Image OCR 2468")
        let destination = try #require(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let model = ImageToolsRecognitionModel()
        let pendingTask = model.start(urls: [source], service: service)
        let task = try #require(pendingTask)
        await task.value
        #expect(model.results.count == 1 && model.failures.isEmpty)
        #expect(model.results.first?.text.contains("Image OCR 2468") == true)
        #expect(!model.isProcessing && model.completed == 1)
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
    }

    @Test
    func everyOCRSavePanelReadsTheLatestImageSaveDirectoryAndCancellingCreatesNothing() async throws {
        _ = NSApplication.shared
        let fixture = try Fixture()
        defer { fixture.remove() }
        let preferencesName = "zisla-image-ocr-panel-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: preferencesName))
        defer { preferences.removePersistentDomain(forName: preferencesName) }
        let locations = SaveLocationStore(defaults: preferences)
        let model = ImageToolsRecognitionModel()
        try await recognize(model, image: makeImage(), urls: [fixture.image])
        let result = try #require(model.results.first)
        let view = ImageToolsRecognitionResultsView(model: model, saveLocations: locations)
        let panel = NSSavePanel()
        let folderPanel = NSOpenPanel()
        panel.isReleasedWhenClosed = false
        folderPanel.isReleasedWhenClosed = false
        defer { panel.close(); folderPanel.close() }
        let initialMessage = model.message
        for name in ["Initial images", "Updated images"] {
            let directory = fixture.root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try locations.setDirectory(directory, for: .imageTools)
            for format in [ImageToolsRecognitionDocument.Format.text, .table] {
                let task = view.export(result, format: format, panel: panel) { configured in
                    #expect(configured.directoryURL?.standardizedFileURL == directory.standardizedFileURL)
                    let fileExtension = format == .text ? "txt" : "xlsx"
                    #expect(configured.allowedContentTypes == (UTType(filenameExtension: fileExtension).map { [$0] } ?? []))
                    #expect(configured.nameFieldStringValue == "source-ocr." + fileExtension)
                    return nil
                }
                #expect(task == nil)
            }
            let task = view.exportTexts(panel: folderPanel) { configured in
                #expect(configured.directoryURL?.standardizedFileURL == directory.standardizedFileURL)
                #expect(configured.canChooseDirectories && !configured.canChooseFiles)
                return nil
            }
            #expect(task == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
        #expect(model.results == [result] && model.message == initialMessage && !model.isProcessing)
    }

    @Test(arguments: [ImageToolsRecognitionDocument.Format.text, .table],
          ["existing", "original", "deleted original", "other deleted input", "input alias", "dot alias", "case alias", "link", "dangling link", "directory"])
    func singleExportPanelsRejectProtectedAndExistingTargetsBeforeClosing(format: ImageToolsRecognitionDocument.Format, target: String) async throws {
        _ = NSApplication.shared
        let fixture = try Fixture()
        defer { fixture.remove() }
        let preferencesName = "zisla-image-ocr-conflict-panel-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: preferencesName))
        defer { preferences.removePersistentDomain(forName: preferencesName) }
        let model = ImageToolsRecognitionModel()
        let otherInput = fixture.root.appendingPathComponent("other.png")
        try await recognize(model, image: makeImage(), urls: [fixture.image, otherInput])
        let result = try #require(model.results.first)
        let view = ImageToolsRecognitionResultsView(model: model, saveLocations: SaveLocationStore(defaults: preferences))
        let fileExtension = format == .text ? "txt" : "xlsx"
        var destination = fixture.root.appendingPathComponent("existing." + fileExtension)
        switch target {
        case "original": destination = fixture.image
        case "deleted original":
            try FileManager.default.removeItem(at: fixture.image)
            destination = fixture.image
        case "other deleted input": destination = otherInput
        case "input alias":
            let alias = fixture.root.appendingPathComponent("input-directory")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.root)
            destination = alias.appendingPathComponent(otherInput.lastPathComponent)
        case "dot alias":
            let nested = fixture.root.appendingPathComponent("nested", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
            destination = nested.appendingPathComponent("../" + otherInput.lastPathComponent)
        case "case alias": destination = fixture.root.appendingPathComponent("OTHER.png")
        case "link": try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: fixture.image)
        case "dangling link": try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: fixture.root.appendingPathComponent("missing"))
        case "directory": try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        default: try Data("existing output".utf8).write(to: destination)
        }
        let before = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
        let initialMessage = model.message
        let panel = NSSavePanel()
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let previousDelegate = SavePanelDelegate()
        panel.delegate = previousDelegate
        let openDescriptorCount = Self.openDescriptorCount()
        var didValidate = false
        let task = view.export(result, format: format, panel: panel) { configured in
            guard let delegate = configured.delegate as? ImageToolsRecognitionSavePanelDelegate else {
                Issue.record("OCR panels must validate before closing"); return nil
            }
            #expect(delegate !== previousDelegate)
            do {
                try delegate.panel(configured, validate: destination)
                Issue.record("A conflict must keep the save panel open")
            } catch {
                if target == "input alias" {
                    #expect((error as NSError).domain == NSPOSIXErrorDomain)
                    #expect([Int(ELOOP), Int(ENOTDIR)].contains((error as NSError).code))
                } else {
                    #expect((error as NSError).localizedDescription == ImageProcessingError.outputAlreadyExists(destination).localizedDescription)
                }
            }
            didValidate = true
            return nil
        }
        #expect(task == nil && didValidate)
        #expect(Self.openDescriptorCount() == openDescriptorCount, "Cancelled validation must release its directory descriptor")
        #expect(panel.delegate === previousDelegate, "Closing or cancelling must release only the OCR panel's validation")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted() == before)
        #expect(model.results.first == result && model.message == initialMessage && !model.isProcessing)
        if target == "existing" { #expect(try String(contentsOf: destination, encoding: .utf8) == "existing output") }
        if target != "deleted original" { #expect(try Data(contentsOf: fixture.image) == fixture.bytes) }
        if target == "link" || target == "dangling link" {
            #expect(try destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        }
    }

    @Test(arguments: [false, true])
    func singleExportPanelReportsAnUnusablePathBeforeClosing(longName: Bool) async throws {
        _ = NSApplication.shared
        let fixture = try Fixture()
        defer { fixture.remove() }
        let preferencesName = "zisla-image-ocr-parent-panel-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: preferencesName))
        defer { preferences.removePersistentDomain(forName: preferencesName) }
        let model = ImageToolsRecognitionModel()
        try await recognize(model, image: makeImage(), urls: [fixture.image])
        let result = try #require(model.results.first)
        let view = ImageToolsRecognitionResultsView(model: model, saveLocations: SaveLocationStore(defaults: preferences))
        let parent = fixture.root.appendingPathComponent("replaced-directory")
        try Data("concurrent file".utf8).write(to: parent)
        let destination = longName ? fixture.root.appendingPathComponent(String(repeating: "x", count: 256) + ".txt")
            : parent.appendingPathComponent("result.txt")
        let panel = NSSavePanel()
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let initialMessage = model.message
        let openDescriptorCount = Self.openDescriptorCount()
        let task = view.export(result, format: .text, panel: panel) { configured in
            guard let delegate = configured.delegate as? ImageToolsRecognitionSavePanelDelegate else {
                Issue.record("OCR panels must validate before closing"); return nil
            }
            do {
                try delegate.panel(configured, validate: destination)
                Issue.record("An unreadable destination must keep the panel open")
            } catch {
                #expect((error as NSError).domain == NSPOSIXErrorDomain)
                #expect((error as NSError).code == Int(longName ? ENAMETOOLONG : ENOTDIR))
            }
            return nil
        }
        #expect(task == nil && panel.delegate == nil)
        #expect(Self.openDescriptorCount() == openDescriptorCount, "Failed validation must release its directory descriptor")
        #expect(model.message == initialMessage && !model.isProcessing)
        #expect(try String(contentsOf: parent, encoding: .utf8) == "concurrent file")
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted() == ["replaced-directory", "source.png"])
    }

    @Test(arguments: [ImageToolsRecognitionDocument.Format.text, .table], ["new", "concurrent file", "concurrent link"])
    func singleExportPanelsAcceptNewTargetsAndExclusiveCreationProtectsLaterConflicts(format: ImageToolsRecognitionDocument.Format, outcome: String) async throws {
        _ = NSApplication.shared
        let fixture = try Fixture()
        defer { fixture.remove() }
        let preferencesName = "zisla-image-ocr-new-panel-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: preferencesName))
        defer { preferences.removePersistentDomain(forName: preferencesName) }
        let model = ImageToolsRecognitionModel()
        try await recognize(model, image: makeImage(), urls: [fixture.image])
        let result = try #require(model.results.first)
        let view = ImageToolsRecognitionResultsView(model: model, saveLocations: SaveLocationStore(defaults: preferences))
        let destination = fixture.root.appendingPathComponent("result." + (format == .text ? "txt" : "xlsx"))
        let panel = NSSavePanel()
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let openDescriptorCount = Self.openDescriptorCount()
        let task = view.export(result, format: format, panel: panel) { configured in
            guard let delegate = configured.delegate as? ImageToolsRecognitionSavePanelDelegate else {
                Issue.record("OCR panels must validate before closing"); return nil
            }
            do {
                try delegate.panel(configured, validate: destination)
                if outcome == "concurrent file" { try Data("concurrent output".utf8).write(to: destination) }
                if outcome == "concurrent link" {
                    try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: fixture.root.appendingPathComponent("missing"))
                }
            } catch { Issue.record(error) }
            return destination
        }
        #expect(Self.openDescriptorCount() == openDescriptorCount, "Confirmed validation must release its directory descriptor")
        await (try #require(task)).value
        #expect(panel.delegate == nil)
        if outcome == "new" {
            #expect(model.message == AppLocalization.text("已保存 %@", destination.lastPathComponent))
            if format == .text { #expect(try String(contentsOf: destination, encoding: .utf8) == result.text) }
            else { #expect(try Data(contentsOf: destination).starts(with: [0x50, 0x4b])) }
        } else {
            #expect(model.message == ImageProcessingError.outputAlreadyExists(destination).localizedDescription)
            if outcome == "concurrent file" { #expect(try String(contentsOf: destination, encoding: .utf8) == "concurrent output") }
            else { #expect(try destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true) }
        }
        #expect(model.results == [result] && !model.isProcessing)
        #expect(try Data(contentsOf: fixture.image) == fixture.bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted() == [destination.lastPathComponent, "source.png"].sorted())
    }

    @Test
    func dependentCancellationStopsTheBatchWithoutPublishingAnImageFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        let image = try makeImage()
        let pendingTask = model.start(urls: [fixture.image, fixture.root.appendingPathComponent("second.png")],
            service: service, loadImage: { _ in image }, recognizeImage: { _, _ in throw CancellationError() })
        let task = try #require(pendingTask)
        await task.value
        #expect(model.results.isEmpty && model.failures.isEmpty && model.completed == 0)
        #expect(model.message == AppLocalization.text("已取消") && !model.isProcessing)
    }

    @Test
    func cancellingTheFinalPublishedItemDiscardsItsQueuedCompletionMessage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        let image = try makeImage()
        let observed = model.$completed.dropFirst().sink { completed in
            if completed == 1 { model.cancel() }
        }
        defer { observed.cancel() }
        let pending = model.start(urls: [fixture.image], service: service, loadImage: { _ in image }, recognizeImage: { _, _ in
            Self.fragments("completed text")
        })
        await (try #require(pending)).value
        #expect(model.results.map(\.text) == ["completed text"])
        #expect(model.message == AppLocalization.text("已取消"), "A worker queued to return success must not replace a cancellation message")
        #expect(!model.isProcessing && model.currentInputURL == nil)
    }

    @Test
    func conflictingBatchTargetsAreCheckedBeforeGeneratingAnyTemporaryDocuments() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = fixture.root.appendingPathComponent("first.txt")
        let second = fixture.root.appendingPathComponent("second.txt")
        try Data("existing".utf8).write(to: second)
        let result = Self.result(inputURL: fixture.image)
        let documents = [first, second].map { ImageToolsRecognitionDocument(result: result, format: .text, destination: $0) }
        var enteredStaging = false
        #expect(throws: ImageProcessingError.outputAlreadyExists(second)) {
            try ImageToolsRecognitionExporter.write(documents, stagingParent: fixture.root, checkCancellation: {
                let names = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
                if names.contains(where: { $0.hasPrefix("zisla-image-ocr-export-") }) { enteredStaging = true }
            })
        }
        #expect(!enteredStaging, "A known conflict must be reported before allocating and formatting export documents")
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(try String(contentsOf: second, encoding: .utf8) == "existing")
    }

    @Test
    func cancellationAfterRecognitionBeforePublishingCannotAppendToANewBatch() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = ImageToolsRecognitionModel()
        let image = try makeImage()
        let gate = PublicationGate()
        let pending = model.start(urls: [fixture.image], service: service, loadImage: { _ in image }, beforePublish: { _ in await gate.wait() },
            recognizeImage: { _, _ in Self.fragments("old batch") })
        let task = try #require(pending)
        await gate.waitUntilStarted()
        model.cancel()
        let newURL = fixture.root.appendingPathComponent("new.png")
        try await recognize(model, image: image, urls: [newURL], text: "new batch")
        let expectedMessage = model.message
        await gate.finish()
        await task.value
        #expect(model.results.map(\.inputURL) == [newURL])
        #expect(model.results.map(\.text) == ["new batch"])
        #expect(model.message == expectedMessage && model.completed == 1 && !model.isProcessing)
    }

    private var service: ImageProcessingService { ImageProcessingService(executableURL: nil) }

    private func recognize(_ model: ImageToolsRecognitionModel, image: CGImage, urls: [URL], text: String = "synthetic") async throws {
        let pendingTask = model.start(urls: urls, service: service, loadImage: { _ in image }, recognizeImage: { _, _ in Self.fragments(text) })
        let task = try #require(pendingTask)
        await task.value
        #expect(model.failures.isEmpty)
    }

    private nonisolated static func checkBackgroundThread() {
        #expect(!Thread.isMainThread, "Image loading and recognition must stay outside the UI thread")
    }

    private nonisolated static func fragments(_ text: String) -> [ScreenshotRecognizedFragment] {
        [.init(text: text, boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.2))]
    }

    private nonisolated static func result(inputURL: URL, text: String = "synthetic") -> ImageToolsRecognitionResult {
        ImageToolsRecognitionResult(inputURL: inputURL, text: text, table: .init(rows: [[text, "42"]], merges: []))
    }

    private nonisolated static func openDescriptorCount() -> Int {
        let count = sysconf(_SC_OPEN_MAX)
        return (0..<Int32(count)).reduce(into: 0) { count, descriptor in
            if fcntl(descriptor, F_GETFD) >= 0 { count += 1 }
        }
    }

    private func makeImage(text: String = "Synthetic") throws -> CGImage {
        let size = CGSize(width: 720, height: 160)
        let context = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        text.draw(at: CGPoint(x: 24, y: 60), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 42, weight: .regular),
            .foregroundColor: NSColor.black,
        ])
        return try #require(context.makeImage())
    }

    private struct Fixture {
        let root: URL
        let image: URL
        let bytes: Data
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-image-ocr-test-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            image = root.appendingPathComponent("source.png")
            bytes = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
            try bytes.write(to: image)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private struct SyntheticFailure: LocalizedError {
        var errorDescription: String? { "Synthetic OCR or export failure" }
    }

    private final class SavePanelDelegate: NSObject, NSOpenSavePanelDelegate {}

    private actor RecognitionGate {
        private var operation: ScreenshotRecognitionOperation?
        private var continuation: CheckedContinuation<[ScreenshotRecognizedFragment], any Error>?
        private var startedWaiters: [CheckedContinuation<Void, Never>] = []
        private var callCount = 0

        func nextCall() -> Int { callCount += 1; return callCount }

        func recognize(_ operation: ScreenshotRecognitionOperation) async throws -> [ScreenshotRecognizedFragment] {
            self.operation = operation
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                startedWaiters.forEach { $0.resume() }
                startedWaiters = []
            }
        }

        func waitUntilStarted() async {
            if continuation != nil { return }
            await withCheckedContinuation { startedWaiters.append($0) }
        }

        func isCancelled() -> Bool {
            do { try operation?.checkCancellation(); return false }
            catch { return error is CancellationError }
        }

        func finish(_ fragments: [ScreenshotRecognizedFragment]) {
            continuation?.resume(returning: fragments)
            continuation = nil
        }
    }

    private actor LoadingGate {
        private var continuation: CheckedContinuation<CGImage, any Error>?
        private var startedWaiters: [CheckedContinuation<Void, Never>] = []

        func load() async throws -> CGImage {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                startedWaiters.forEach { $0.resume() }
                startedWaiters = []
            }
        }

        func waitUntilStarted() async {
            if continuation != nil { return }
            await withCheckedContinuation { startedWaiters.append($0) }
        }

        func finish(_ image: CGImage) { continuation?.resume(returning: image); continuation = nil }
    }

    private actor PublicationGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var startedWaiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                startedWaiters.forEach { $0.resume() }
                startedWaiters = []
            }
        }

        func waitUntilStarted() async {
            if continuation != nil { return }
            await withCheckedContinuation { startedWaiters.append($0) }
        }

        func finish() { continuation?.resume(); continuation = nil }
    }
}
