import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ShelfContextActionTests {
    @Test func ordinaryOpenAndRevealAllowFoldersAndResolveMovedBookmarksInOrder() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let item = try fixture.file("original.txt", bytes: Data([7]))
        let moved = fixture.root.appendingPathComponent("renamed.txt")
        try FileManager.default.moveItem(at: item.url, to: moved)
        let folder = fixture.root.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        #expect(fixture.shelf.add([folder]) == 1)
        let directory = try #require(fixture.shelf.items.last)
        var opened: [URL] = []
        try ShelfModuleView.openFileItems([directory, item], in: fixture.shelf) { opened.append($0); return true }
        #expect(opened.map { $0.resolvingSymlinksInPath() } == [folder, moved].map { $0.resolvingSymlinksInPath() })
        let revealed = try ShelfContextActions.fileURLs([item, directory], in: fixture.shelf, requiresRegularFile: false)
        defer { revealed.forEach(fixture.shelf.endAccessing) }
        #expect(revealed.map { $0.resolvingSymlinksInPath() } == [moved, folder].map { $0.resolvingSymlinksInPath() })
        #expect(throws: ShelfContextActionError.unavailableFile(directory.displayName)) {
            try ShelfContextActions.fileURLs([directory], in: fixture.shelf)
        }
        #expect(fixture.shelf.items == [item, directory])
    }

    @Test func ordinaryOpenFailsBeforeSideEffectsForMissingFilesAndKeepsLinksAndText() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.file("missing.txt", bytes: Data([7]))
        try FileManager.default.removeItem(at: file.url)
        var opened: [URL] = []
        #expect(throws: ShelfContextActionError.unavailableFile(file.displayName)) {
            try ShelfModuleView.openFileItems([file], in: fixture.shelf) { opened.append($0); return true }
        }
        #expect(opened.isEmpty)
        #expect(fixture.shelf.add(payloads: [.text("https://example.invalid/"), .text("plain text")]) == 2)
        try ShelfModuleView.openFileItems(Array(fixture.shelf.items.dropFirst()), in: fixture.shelf) { opened.append($0); return true }
        #expect(opened == [URL(string: "https://example.invalid/")!, fixture.shelf.items[2].url])
        #expect(throws: ShelfContextActionError.unavailableFile(fixture.shelf.items[2].displayName)) {
            try ShelfModuleView.openFileItems([fixture.shelf.items[2]], in: fixture.shelf) { _ in false }
        }
    }

    @Test func actionsRejectEmptyOrMixedSelectionsBeforeAnySideEffect() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let image = try fixture.image(width: 24)
        let video = try fixture.file("clip.mp4", bytes: Data([1]))
        let text = FileShelfItem(id: UUID(), url: image.url, addedAt: .distantPast, bookmarkData: Data(), text: "text")
        for action in ShelfContextAction.allCases {
            #expect(!action.supports([]))
            #expect(action.supports([image, video]) == (action == .compressFiles || action == .importToStudioLibrary))
            #expect(!action.supports([image, text]))
            #expect(fixture.actions.perform(action, items: [], createQuickNote: { _ in
                Issue.record("Empty input must not write a note"); return false
            }, openStudio: { _, _ in Issue.record("Empty input must not open the studio") }) == nil)
            #expect(!fixture.actions.isProcessing)
        }
        #expect(ShelfContextAction.imagesToPDF.supports([image]))
        #expect(ShelfContextAction.recognizeToQuickNote.supports([image]))
        #expect(ShelfContextAction.editVideo.supports([video]))
        #expect(fixture.shelf.items == [image, video])
    }

    @Test(arguments: [false, true])
    func PDFReturnsToShelfInOrderAndSurvivesStagingCleanup(cleanupFails: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.image(width: 24)
        let second = try fixture.image(width: 36)
        let originals = try [Data(contentsOf: first.url), Data(contentsOf: second.url)]
        var service = PDFProcessingService()
        if cleanupFails {
            service.removeImageStagingDirectory = { staging in
                try FileManager.default.removeItem(at: staging)
                try FileManager.default.removeItem(at: staging)
            }
        }
        let configuredService = service
        let pending = fixture.actions.perform(.imagesToPDF, items: [second, first],
                                              createQuickNote: { _ in false }, openStudio: { _, _ in throw ShelfContextActionError.studioUnavailable }, convertImages: {
                                                  try configuredService.convertImagesToPDF($0, to: $1)
                                              })
        let task = try #require(pending)
        #expect(fixture.actions.isProcessing)
        await task.value
        let result = try #require(fixture.shelf.items.last)
        #expect(fixture.actions.generatedItemID == result.id)
        #expect(fixture.actions.message == AppLocalization.text("已加入 %ld 个项目", 1))
        #expect(result.isManaged && result.url.lastPathComponent == "images.pdf")
        let document = try #require(PDFDocument(url: result.url))
        #expect(document.pageCount == 2)
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).width == 36)
        #expect(document.page(at: 1)?.bounds(for: .mediaBox).width == 24)
        #expect(try [Data(contentsOf: first.url), Data(contentsOf: second.url)] == originals)
        #expect(fixture.shelf.items.prefix(2) == [first, second])
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
        #expect(!fixture.actions.isProcessing && fixture.actions.task == nil)
    }

    @Test(arguments: ["cancelled", "corrupt second", "committed"])
    func outerCleanupFailurePreservesConversionResultAndAllowsNextAction(_ outcome: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.image(width: 24)
        let second = try fixture.image(width: 36)
        if outcome == "corrupt second" { try Data("corrupt image".utf8).write(to: second.url) }
        let originals = try [Data(contentsOf: first.url), Data(contentsOf: second.url)]
        let stage = fixture.stage
        fixture.actions.removeStagingDirectory = { directory in
            #expect(directory.deletingLastPathComponent().standardizedFileURL == stage.standardizedFileURL)
            #expect(directory.lastPathComponent.hasPrefix("zisla-shelf-action-"))
            try FileManager.default.removeItem(at: directory)
            try FileManager.default.removeItem(at: directory)
        }
        let pending = fixture.actions.perform(.imagesToPDF, items: [second, first],
                                              createQuickNote: { _ in false }, openStudio: { _, _ in throw ShelfContextActionError.studioUnavailable }, convertImages: { inputs, output in
                                                  if outcome == "cancelled" { throw CancellationError() }
                                                  try PDFProcessingService().convertImagesToPDF(inputs, to: output)
                                              })
        try await #require(pending).value
        let expectedMessage: String
        if outcome == "committed" {
            let result = try #require(fixture.shelf.items.last)
            #expect(fixture.shelf.items.count == 3 && fixture.shelf.items.prefix(2) == [first, second])
            #expect(fixture.actions.generatedItemID == result.id)
            #expect(result.isManaged && result.url.lastPathComponent == "images.pdf")
            let document = try #require(PDFDocument(url: result.url))
            #expect(document.pageCount == 2)
            #expect(document.page(at: 0)?.bounds(for: .mediaBox).width == 36)
            #expect(document.page(at: 1)?.bounds(for: .mediaBox).width == 24)
            #expect(FileShelfStore(storageURL: fixture.storage).items == fixture.shelf.items)
            expectedMessage = AppLocalization.text("已加入 %ld 个项目", 1)
        } else {
            #expect(fixture.shelf.items == [first, second] && fixture.actions.generatedItemID == nil)
            expectedMessage = outcome == "cancelled" ? AppLocalization.text("已取消操作")
                : AppLocalization.text("操作失败：%@", PDFProcessingError.unsupportedImage(second.url).localizedDescription)
        }
        #expect(fixture.actions.message == expectedMessage, "Staging cleanup must retain the conversion's success, cancellation, or original error")
        #expect(try [Data(contentsOf: first.url), Data(contentsOf: second.url)] == originals)
        #expect(try FileManager.default.contentsOfDirectory(atPath: stage.path).isEmpty)
        #expect(!fixture.actions.isProcessing && !fixture.actions.isCancellable && fixture.actions.task == nil)

        fixture.actions.removeStagingDirectory = { try FileManager.default.removeItem(at: $0) }
        let itemsBeforeRetry = fixture.shelf.items
        try await #require(fixture.perform(.imagesToPDF, items: [first])).value
        #expect(fixture.shelf.items.count == itemsBeforeRetry.count + 1)
        #expect(fixture.shelf.items.dropLast() == itemsBeforeRetry)
        #expect(fixture.actions.generatedItemID == fixture.shelf.items.last?.id)
        #expect(fixture.actions.message == AppLocalization.text("已加入 %ld 个项目", 1))
        #expect(try FileManager.default.contentsOfDirectory(atPath: stage.path).isEmpty)
    }

    @Test func screenshotsRecoverTheirCacheBeforePDFAndNeverChangeStoredPixels() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let png = try Fixture.png(width: 24)
        let metadata = ShelfScreenshotMetadata(source: .init(applicationName: "Synthetic", bundleIdentifier: nil,
                                                             processIdentifier: nil), isLongScreenshot: false, initialCaptureRect: .zero, captureRect: .zero,
                                               screenFrame: nil, displayIdentifier: nil, pixelWidth: 24, pixelHeight: 12)
        let item = try fixture.shelf.stashScreenshot(png: png, metadata: metadata)
        try FileManager.default.removeItem(at: item.url)
        try await #require(fixture.perform(.imagesToPDF, items: [item])).value
        #expect(fixture.shelf.items.count == 2)
        #expect(fixture.shelf.items[0] == item)
        #expect(try fixture.shelf.screenshotData(id: item.id) == png)
        #expect(try Data(contentsOf: item.url) == png)
    }

    @Test(arguments: ["missing", "directory", "corrupt", "remote"])
    func inaccessibleOrInvalidImagesFailWithoutAddingAnOutput(_ failure: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var item = try fixture.image(width: 24)
        switch failure {
        case "missing": try FileManager.default.removeItem(at: item.url)
        case "directory":
            try FileManager.default.removeItem(at: item.url)
            try FileManager.default.createDirectory(at: item.url, withIntermediateDirectories: false)
        case "remote": item.url = URL(string: "https://example.invalid/image.png")!; item.bookmarkData = Data()
        default: try Data("invalid image".utf8).write(to: item.url)
        }
        let before = fixture.shelf.items
        let task = try #require(fixture.perform(.imagesToPDF, items: [item]))
        await task.value
        #expect(fixture.shelf.items == before)
        #expect(!fixture.actions.isProcessing)
        #expect(fixture.actions.message?.contains(AppLocalization.text("操作失败")) == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
    }

    @Test func failingConversionOrShelfCommitCleansStagingAndAllowsRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let item = try fixture.image(width: 24)
        let before = fixture.shelf.items
        let bytes = try Data(contentsOf: item.url)
        let failedTask = fixture.actions.perform(.imagesToPDF, items: [item], createQuickNote: { _ in false },
                                                 openStudio: { _, _ in throw ShelfContextActionError.studioUnavailable }, convertImages: { _, output in
                                                     try Data([1]).write(to: output)
                                                     throw CocoaError(.fileWriteOutOfSpace)
                                                 })
        let failed = try #require(failedTask)
        await failed.value
        #expect(fixture.shelf.items == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
        try FileManager.default.removeItem(at: fixture.storage)
        try FileManager.default.createDirectory(at: fixture.storage, withIntermediateDirectories: false)
        try await #require(fixture.perform(.imagesToPDF, items: [item])).value
        #expect(fixture.shelf.items == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
        try FileManager.default.removeItem(at: fixture.storage)
        try await #require(fixture.perform(.imagesToPDF, items: [item])).value
        #expect(fixture.shelf.items.count == 2)
        #expect(try Data(contentsOf: item.url) == bytes)
    }

    @Test func cancellationDuringPDFRejectsLateOutputAndDuplicateClicks() async throws {
        let fixture = try Fixture()
        let gate = Gate()
        defer { fixture.remove() }
        let item = try fixture.image(width: 24)
        let taskTask = fixture.actions.perform(.imagesToPDF, items: [item], createQuickNote: { _ in false },
                                               openStudio: { _, _ in throw ShelfContextActionError.studioUnavailable }, convertImages: { _, output in
                                                   gate.pause()
                                                   try Data([1]).write(to: output)
                                               })
        let task = try #require(taskTask)
        await gate.waitUntilPaused()
        #expect(fixture.perform(.imagesToPDF, items: [item]) == nil)
        fixture.actions.cancel()
        gate.resume()
        await task.value
        #expect(fixture.shelf.items == [item])
        #expect(fixture.actions.generatedItemID == nil)
        #expect(fixture.actions.message == AppLocalization.text("已取消操作"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
        #expect(!fixture.actions.isProcessing)
    }

    @Test func cancelledBeforeTaskStartsHasNoOutputOrExternalRequest() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let item = try fixture.image(width: 24)
        let taskTask = fixture.actions.perform(.imagesToPDF, items: [item], createQuickNote: { _ in false },
                                               openStudio: { _, _ in throw ShelfContextActionError.studioUnavailable }, convertImages: { _, _ in Issue.record("Cancelled work must not start conversion") })
        let task = try #require(taskTask)
        fixture.actions.cancel()
        await task.value
        #expect(fixture.shelf.items == [item])
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
        #expect(fixture.actions.message == AppLocalization.text("已取消操作"))
    }

    @Test func OCRUsesExistingFormatterAndCreatesOneOrderedQuickNote() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.image(width: 24)
        let second = try fixture.image(width: 36)
        var note: String?
        let taskTask = fixture.actions.perform(.recognizeToQuickNote, items: [second, first],
                                               createQuickNote: { note = $0; return true }, openStudio: { _, _ in throw ShelfContextActionError.studioUnavailable }, recognizeImage: { image, _ in
                                                   #expect(Self.isOffMainThread())
                                                   return [.init(text: "Text \(image.width)", boundingBox: .init(x: 0, y: 0.2, width: 1, height: 0.2))]
                                               })
        let task = try #require(taskTask)
        await task.value
        #expect(note == "Text 36\n\nText 24")
        #expect(fixture.shelf.items == [first, second])
        #expect(fixture.actions.message == AppLocalization.text("已创建随记"))
    }

    @Test(arguments: ["empty second", "worker failure", "notes denied"])
    func OCRFailureNeverCreatesAPartialNoteAndAllowsRetry(_ failure: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.image(width: 24)
        let second = try fixture.image(width: 36)
        var attempts = 0
        let taskTask = fixture.actions.perform(.recognizeToQuickNote, items: [first, second],
                                               createQuickNote: { _ in attempts += 1; return false }, openStudio: { _, _ in throw ShelfContextActionError.studioUnavailable }, recognizeImage: { image, _ in
                                                   if failure == "worker failure" { throw CocoaError(.fileReadCorruptFile) }
                                                   return failure == "empty second" && image.width == 36 ? []
                                                       : [.init(text: "result", boundingBox: .init(x: 0, y: 0, width: 1, height: 1))]
                                               })
        let task = try #require(taskTask)
        await task.value
        #expect(attempts == (failure == "notes denied" ? 1 : 0))
        #expect(fixture.shelf.items == [first, second])
        #expect(!fixture.actions.isProcessing)
        #expect(fixture.actions.message?.hasPrefix(AppLocalization.text("操作失败")) == true)
    }

    @Test func cancellingOCRReachesTheVisionOperationAndNeverWritesLateText() async throws {
        let fixture = try Fixture()
        let gate = Gate()
        defer { fixture.remove() }
        let item = try fixture.image(width: 24)
        var written = false
        let taskTask = fixture.actions.perform(.recognizeToQuickNote, items: [item],
                                               createQuickNote: { _ in written = true; return true }, openStudio: { _, _ in throw ShelfContextActionError.studioUnavailable }, recognizeImage: { _, operation in
                                                   gate.pause()
                                                   #expect(throws: CancellationError.self) { try operation.checkCancellation() }
                                                   return [.init(text: "late text", boundingBox: .init(x: 0, y: 0, width: 1, height: 1))]
                                               })
        let task = try #require(taskTask)
        await gate.waitUntilPaused()
        fixture.actions.cancel()
        gate.resume()
        await task.value
        #expect(!written && fixture.shelf.items == [item])
        #expect(fixture.actions.message == AppLocalization.text("已取消操作"))
    }

    @Test func committingNotesDisablesCancellationUntilTheSystemResultArrives() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let item = try fixture.image(width: 24)
        let taskTask = fixture.actions.perform(.recognizeToQuickNote, items: [item], createQuickNote: { _ in
            #expect(fixture.actions.isProcessing && !fixture.actions.isCancellable)
            fixture.actions.cancel()
            return true
        }, openStudio: { _, _ in throw ShelfContextActionError.studioUnavailable }, recognizeImage: { _, _ in
            [.init(text: "result", boundingBox: .init(x: 0, y: 0, width: 1, height: 1))]
        })
        let task = try #require(taskTask)
        await task.value
        #expect(fixture.actions.message == AppLocalization.text("已创建随记"))
    }

    @Test(arguments: [true, false])
    func videoHandoffPreservesInputOrderAndReportsUnavailableStudio(_ accepts: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.file("first.mp4", bytes: Data([1]))
        let second = try fixture.file("second.mp4", bytes: Data([2]))
        var handedOff: [URL] = []
        let taskTask = fixture.actions.perform(.editVideo, items: [second, first], createQuickNote: { _ in false },
                                               openStudio: { urls, libraryOnly in
                                                   handedOff = urls
                                                   #expect(!libraryOnly)
                                                   if !accepts { throw ShelfContextActionError.studioUnavailable }
                                               })
        let task = try #require(taskTask)
        await task.value
        #expect(handedOff.map { $0.resolvingSymlinksInPath() } == [second.url, first.url].map { $0.resolvingSymlinksInPath() })
        #expect(fixture.shelf.items == [first, second])
        #expect(fixture.actions.message == (accepts ? AppLocalization.text("已发送到录屏工作室")
                : AppLocalization.text("操作失败：%@", ShelfContextActionError.studioUnavailable.localizedDescription)))
    }

    @Test func ZIPContainsSelectedFilesAndFoldersInSelectionOrderWithoutCopyingSources() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.file("first.txt", bytes: Data("first".utf8))
        let folder = fixture.root.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let child = folder.appendingPathComponent("child.txt")
        try Data("child".utf8).write(to: child)
        #expect(fixture.shelf.add([folder]) == 1)
        let directory = try #require(fixture.shelf.items.last)
        try await #require(fixture.perform(.compressFiles, items: [directory, first, first])).value
        let output = try #require(fixture.shelf.items.last)
        #expect(output.isManaged && output.url.pathExtension == "zip")
        #expect(fixture.shelf.items.count == 3 && fixture.actions.generatedItemID == output.id)
        let listing = try await Self.unzip(output.url, arguments: ["-Z1"], in: fixture.root)
        #expect(String(decoding: listing, as: UTF8.self).split(separator: "\n") == ["Folder/", "Folder/child.txt", "first.txt"])
        #expect(try await Self.unzip(output.url, arguments: ["-p"], entries: ["Folder/child.txt"], in: fixture.root) == Data("child".utf8))
        #expect(try Data(contentsOf: first.url) == Data("first".utf8))
        #expect(try Data(contentsOf: child) == Data("child".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
        #expect(FileShelfStore(storageURL: fixture.storage).items == fixture.shelf.items)
    }

    @Test(arguments: ["-option.txt", "space name.txt", "中文.txt", "line\nbreak.txt"])
    func ZIPTreatsUntrustedFilenamesAsSingleArguments(_ name: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let item = try fixture.file(name, bytes: Data("selected".utf8))
        let other = try fixture.file("other.txt", bytes: Data("other".utf8))
        try await #require(fixture.perform(.compressFiles, items: [item, other])).value
        let output = try #require(fixture.shelf.items.last)
        #expect(output.url.pathExtension == "zip")
        #expect(try await Self.unzip(output.url, arguments: ["-p"], entries: [name], in: fixture.root) == Data("selected".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
    }

    @Test func leadingHyphenSingleFileUsesTheSafeSystemZIPPath() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let item = try fixture.file("-option.txt", bytes: Data("selected".utf8))
        let oldOutput = fixture.stage.appendingPathComponent("ditto.zip")
        #expect(await AppModel.zipArchiveError(source: item.url, destination: oldOutput) != nil,
                "The old ditto path treats a leading hyphen as an option")
        #expect(!FileManager.default.fileExists(atPath: oldOutput.path))
        try await #require(fixture.perform(.compressFiles, items: [item])).value
        let output = try #require(fixture.shelf.items.last)
        #expect(output.isManaged && output.url.pathExtension == "zip")
        #expect(try await Self.unzip(output.url, arguments: ["-p"], entries: [item.displayName], in: fixture.root) == Data("selected".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
    }

    @Test func ZIPRejectsSameNamesAndTopLevelLinksWithoutLeakingFolderNamesOrFollowingTargets() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.file("same.txt", bytes: Data("first".utf8))
        let parent = fixture.root.appendingPathComponent("PrivateParent", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let second = parent.appendingPathComponent("SAME.txt")
        try Data("second".utf8).write(to: second)
        #expect(fixture.shelf.add([second]) == 1)
        let item = try #require(fixture.shelf.items.last)
        try await #require(fixture.perform(.compressFiles, items: [first, item])).value
        #expect(fixture.shelf.items.count == 2 && fixture.actions.generatedItemID == nil)
        #expect(fixture.actions.message?.contains("SAME.txt") == true)
        #expect(fixture.actions.message?.contains("PrivateParent") == false)
        let link = fixture.root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first.url)
        let archive = fixture.stage.appendingPathComponent("link.zip")
        #expect(await AppModel.zipArchiveError(sources: [link], destination: archive) != nil)
        #expect(!FileManager.default.fileExists(atPath: archive.path))
        #expect(try Data(contentsOf: first.url) == Data("first".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
    }

    @Test func ZIPStoresNestedLinksWithoutReadingTheirOutsideTarget() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let privateFile = try fixture.file("private.txt", bytes: Data("outside secret".utf8))
        let other = try fixture.file("selected.txt", bytes: Data("selected".utf8))
        let folder = fixture.root.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: privateFile.url)
        #expect(fixture.shelf.add([folder]) == 1)
        let directory = try #require(fixture.shelf.items.last)
        try await #require(fixture.perform(.compressFiles, items: [directory, other])).value
        let output = try #require(fixture.shelf.items.last)
        let linkBytes = try await Self.unzip(output.url, arguments: ["-p"], entries: ["Folder/link"], in: fixture.root)
        #expect(linkBytes == Data(privateFile.url.path.utf8))
        #expect(linkBytes != Data("outside secret".utf8))
        let listing = String(decoding: try await Self.unzip(output.url, arguments: ["-Z1"], in: fixture.root), as: UTF8.self)
        #expect(!listing.contains("private.txt"))
    }

    @Test(arguments: ["timeout", "permission", "cancel", "missing second"])
    func ZIPRunnerFailuresRemovePartialArchiveAndNeverChangeSources(_ failure: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.file("first.txt", bytes: Data("first".utf8))
        let second = try fixture.file("second.txt", bytes: Data("second".utf8))
        let destination = fixture.stage.appendingPathComponent("partial.zip")
        let root = fixture.root
        let secondURL = second.url
        let error = await AppModel.zipArchiveError(sources: [first.url, second.url], destination: destination) { arguments, parent in
            #expect(parent.standardizedFileURL.path == root.standardizedFileURL.path)
            #expect(arguments[4] == "--")
            try Data("partial".utf8).write(to: destination)
            if failure == "missing second" {
                if arguments.last == "./first.txt" {
                    try FileManager.default.removeItem(at: secondURL)
                    return .init(status: 0, standardOutput: Data(), standardError: "", didTimeout: false)
                }
                throw CocoaError(.fileReadNoSuchFile)
            }
            if failure == "cancel" { throw CancellationError() }
            return .init(status: 1, standardOutput: Data(), standardError: failure == "permission" ? "permission denied" : "",
                         didTimeout: failure == "timeout")
        }
        #expect(error != nil)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try Data(contentsOf: first.url) == Data("first".utf8))
        if failure != "missing second" { #expect(try Data(contentsOf: second.url) == Data("second".utf8)) }
    }

    @Test func ZIPRejectsExistingOutputsAndDestinationsInsideSelectedFolders() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let item = try fixture.file("source.txt", bytes: Data("source".utf8))
        let existing = fixture.stage.appendingPathComponent("existing.zip")
        try Data("existing".utf8).write(to: existing)
        #expect(await AppModel.zipArchiveError(sources: [item.url], destination: existing) != nil)
        #expect(try Data(contentsOf: existing) == Data("existing".utf8))
        #expect(await AppModel.zipArchiveError(sources: [item.url], destination: item.url) != nil)
        #expect(try Data(contentsOf: item.url) == Data("source".utf8))
        let nested = fixture.root.appendingPathComponent("inside.zip")
        #expect(await AppModel.zipArchiveError(sources: [fixture.root], destination: nested) != nil)
        #expect(!FileManager.default.fileExists(atPath: nested.path))
    }

    @Test(arguments: [false, true])
    func ZIPFailureOrCancellationRejectsLateOutputAndCleansStaging(_ cancel: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let item = try fixture.file("source.txt", bytes: Data("source".utf8))
        let started = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish(); resume.continuation.finish() }
        let pending = fixture.actions.perform(.compressFiles, items: [item], createQuickNote: { _ in false },
                                              openStudio: { _, _ in }, archiveFiles: { _, output in
                                                  try Data("partial".utf8).write(to: output)
                                                  started.continuation.yield()
                                                  for await _ in resume.stream { break }
                                                  if !cancel { throw CocoaError(.fileWriteOutOfSpace) }
                                              })
        let task = try #require(pending)
        for await _ in started.stream { break }
        #expect(fixture.perform(.compressFiles, items: [item]) == nil)
        if cancel { fixture.actions.cancel() }
        resume.continuation.yield()
        await task.value
        #expect(fixture.shelf.items == [item] && fixture.actions.generatedItemID == nil)
        #expect(!fixture.actions.isProcessing)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
        #expect(cancel ? fixture.actions.message == AppLocalization.text("已取消操作") : fixture.actions.message?.contains(AppLocalization.text("操作失败")) == true)
    }

    @Test func missingFileInBatchStopsBeforeArchivingAndPreservesSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.file("valid.txt", bytes: Data([1]))
        let second = try fixture.file("missing.txt", bytes: Data([2]))
        try FileManager.default.removeItem(at: second.url)
        let pending = fixture.actions.perform(.compressFiles, items: [first, second], createQuickNote: { _ in false },
                                              openStudio: { _, _ in }, archiveFiles: { _, _ in
                                                  Issue.record("Preflight must reject the missing file before ZIP starts")
                                              })
        try await #require(pending).value
        #expect(fixture.shelf.items == [first, second])
        #expect(fixture.actions.message?.contains(second.displayName) == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.stage.path).isEmpty)
    }

    @Test(arguments: [ShelfContextAction.resizeImages, .convertImages])
    func imageToolsReceiveOnlySelectedInputsInOrderAndResolveMovedBookmarks(_ action: ShelfContextAction) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.image(width: 24)
        let second = try fixture.image(width: 36)
        let moved = fixture.root.appendingPathComponent("moved.png")
        try FileManager.default.moveItem(at: first.url, to: moved)
        var received: [URL] = []
        var operation: ImageToolOperation?
        let pending = fixture.actions.perform(action, items: [second, first, second], createQuickNote: { _ in false },
                                              openStudio: { _, _ in }, openImageTools: { urls, selectedOperation in
                                                  received = urls; operation = selectedOperation
                                              })
        try await #require(pending).value
        #expect(received.map { $0.resolvingSymlinksInPath() } == [second.url, moved].map { $0.resolvingSymlinksInPath() })
        #expect(operation == (action == .resizeImages ? .resize : .convert))
        #expect(fixture.shelf.items == [first, second] && fixture.actions.message == nil)
    }

    @Test func studioLibraryAcceptsMixedMediaWaitsForCompletionAndPropagatesPermissionDenial() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let image = try fixture.image(width: 24)
        let video = try fixture.file("clip.mp4", bytes: Data([1]))
        let audio = try fixture.file("sound.wav", bytes: Data([2]))
        let unknown = try fixture.file("unknown.bin", bytes: Data([3]))
        #expect(ShelfContextAction.importToStudioLibrary.supports([audio, image, video]))
        #expect(!ShelfContextAction.importToStudioLibrary.supports([image, unknown]))
        let started = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish(); resume.continuation.finish() }
        let pending = fixture.actions.perform(.importToStudioLibrary, items: [audio, image, video],
                                              createQuickNote: { _ in false }, openStudio: { urls, libraryOnly in
                                                  #expect(libraryOnly)
                                                  #expect(urls.map(\.lastPathComponent) == ["sound.wav", "image-24.png", "clip.mp4"])
                                                  started.continuation.yield()
                                                  for await _ in resume.stream { break }
                                                  throw CocoaError(.fileReadNoPermission)
                                              })
        let task = try #require(pending)
        for await _ in started.stream { break }
        #expect(fixture.actions.isProcessing && fixture.actions.message == AppLocalization.text("正在处理…"))
        resume.continuation.yield()
        await task.value
        #expect(fixture.actions.message == AppLocalization.text("操作失败：%@", CocoaError(.fileReadNoPermission).localizedDescription))
        #expect(fixture.shelf.items == [image, video, audio, unknown])
    }

    private nonisolated static func unzip(_ url: URL, arguments: [String], entries: [String] = [], in directory: URL) async throws -> Data {
        let result = try await AIAgentProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
                                                        arguments: arguments + [url.path] + entries, workingDirectoryURL: directory)
        try #require(result.status == 0)
        return result.standardOutput
    }

    private nonisolated static func isOffMainThread() -> Bool { !Thread.isMainThread }

    @MainActor private final class Fixture {
        let root: URL
        let stage: URL
        let storage: URL
        let shelf: FileShelfStore
        let actions: ShelfContextActions

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-action-test-" + UUID().uuidString)
            stage = root.appendingPathComponent("temporary")
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            storage = root.appendingPathComponent("shelf.json")
            shelf = FileShelfStore(storageURL: storage)
            actions = ShelfContextActions(shelf: shelf, temporaryDirectory: stage)
        }

        func image(width: Int) throws -> FileShelfItem {
            try file("image-\(width).png", bytes: ShelfContextActionTests.Fixture.png(width: width))
        }

        func file(_ name: String, bytes: Data) throws -> FileShelfItem {
            let url = root.appendingPathComponent(name)
            try bytes.write(to: url)
            #expect(shelf.add([url]) == 1)
            return try #require(shelf.items.last)
        }

        func perform(_ action: ShelfContextAction, items: [FileShelfItem]) -> Task<Void, Never>? {
            actions.perform(action, items: items, createQuickNote: { _ in false }, openStudio: { _, _ in throw ShelfContextActionError.studioUnavailable })
        }

        func remove() { actions.cancel(); try? FileManager.default.removeItem(at: root) }

        nonisolated static func png(width: Int) throws -> Data {
            let context = try #require(CGContext(data: nil, width: width, height: 12, bitsPerComponent: 8,
                                                 bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: 12))
            let data = NSMutableData()
            let writer = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(writer, try #require(context.makeImage()), nil)
            #expect(CGImageDestinationFinalize(writer))
            return data as Data
        }
    }

    private final class Gate: @unchecked Sendable {
        private let condition = NSCondition()
        private var paused = false
        private var resumed = false
        private var waiter: CheckedContinuation<Void, Never>?
        func pause() {
            condition.lock()
            paused = true
            waiter?.resume(); waiter = nil
            while !resumed { condition.wait() }
            condition.unlock()
        }
        func waitUntilPaused() async {
            await withCheckedContinuation { continuation in
                condition.lock()
                if paused { continuation.resume() } else { waiter = continuation }
                condition.unlock()
            }
        }
        func resume() { condition.lock(); resumed = true; condition.broadcast(); condition.unlock() }
    }
}
