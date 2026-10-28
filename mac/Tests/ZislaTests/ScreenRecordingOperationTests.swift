import AppKit
import AVFoundation
import Combine
import CoreImage
import ImageIO
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ScreenRecordingOperationTests {
    enum Action: CaseIterable { case save, copy, export }

    @Test func savingPublishesBusyStateBeforeReturningToTheRunLoop() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.model.saveProject()

        #expect(fixture.model.isBusy, "Saving must yield the main actor so the island can show its pending state")
        #expect(fixture.notices.screenRecordingOperations.count == 1)
        #expect(fixture.notices.screenRecordingOperations.first?.progress == nil,
                "A manifest write has no measurable fraction and must not invent a percentage")
        await fixture.model.operationTask?.value
        #expect(!fixture.model.isBusy)
        #expect(fixture.notices.screenRecordingOperations.first?.kind == .success)
    }

    @Test(arguments: [Action.save, .copy])
    func projectWritesRunOffTheMainThreadKeepTheStudioOpenAndSavePendingEdits(_ action: Action) async throws {
        let fixture = try Fixture(write: { project, source, destination in
            #expect(!Thread.isMainThread, "File copies and JSON writes must not block the island or studio")
            try Self.write(project, source, destination)
        })
        defer { fixture.close() }
        fixture.model.commitPendingCanvasText = { [weak model = fixture.model] in
            model?.commitPendingCanvasText = nil
            model?.update { $0.name = "Edited" }
        }
        try fixture.perform(action)
        await fixture.model.operationTask?.value

        #expect(!fixture.model.isDirty && fixture.model.canEdit)
        #expect(fixture.hideCount == 0, "Saving must not automatically hide or close the studio")
        #expect(fixture.notices.screenRecordingOperations.count == 1)
        #expect(fixture.notices.screenRecordingOperations.first?.kind == .success)
        let saved = try fixture.store.load(from: #require(fixture.model.directory))
        #expect(saved.name == "Edited")
        if action == .copy {
            #expect(fixture.model.directory == fixture.destination)
            #expect(try fixture.store.load(from: fixture.directory).name == "Output")
        }
    }

    @Test(arguments: Action.allCases)
    func failedWritesKeepEditsAndOriginalFilesAndReportFailure(_ action: Action) async throws {
        let fixture = try Fixture(write: { _, _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        defer { fixture.close() }
        fixture.model.update { $0.name = "Unsaved" }
        let original = try Data(contentsOf: fixture.manifest)
        try fixture.perform(action)
        await fixture.model.operationTask?.value

        #expect(fixture.model.isDirty && fixture.model.canEdit)
        #expect(fixture.model.directory == fixture.directory)
        #expect(fixture.model.project?.name == "Unsaved")
        #expect(try Data(contentsOf: fixture.manifest) == original)
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        let notice = try #require(fixture.notices.screenRecordingOperations.first)
        #expect(notice.kind == .error && notice.progress == nil)
        #expect(notice.detail == fixture.model.errorMessage)
        #expect(fixture.hideCount == 0)
    }

    @Test(arguments: Action.allCases)
    func cancellationDuringStoragePreservesFilesAndRemovesOnlyItsProgress(_ action: Action) async throws {
        let gate = WriteGate()
        let fixture = try Fixture(write: { project, source, destination in
            gate.pause()
            try Self.write(project, source, destination)
        })
        defer { gate.resume(); fixture.close() }
        fixture.model.update { $0.name = "Unsaved" }
        let original = try Data(contentsOf: fixture.manifest)
        fixture.notices.enqueue(IslandNotice(id: "browser-download-test", title: "Download"), expiresAfter: nil)
        try fixture.perform(action)
        await gate.waitUntilPaused()
        #expect(fixture.model.isBusy && !fixture.model.canEdit)
        #expect(!fixture.model.prepareToClose())
        fixture.model.cancelOperation()
        gate.resume()
        await fixture.model.operationTask?.value

        #expect(fixture.model.isDirty && fixture.model.canEdit)
        #expect(fixture.model.directory == fixture.directory)
        #expect(try Data(contentsOf: fixture.manifest) == original)
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        #expect(fixture.notices.screenRecordingOperations.isEmpty)
        #expect(fixture.notices.right.map(\.id) == ["browser-download-test"])
        #expect(fixture.hideCount == 0)
    }

    @Test func cancellingBeforeStorageStartsDoesNotPersistTheSnapshot() async throws {
        let fixture = try Fixture(write: { project, source, destination in
            try Data([1]).write(to: source.appendingPathComponent("storage-started"))
            try Self.write(project, source, destination)
        })
        defer { fixture.close() }
        fixture.model.update { $0.name = "Unsaved" }
        fixture.model.saveProject()
        fixture.model.cancelOperation()
        await fixture.model.operationTask?.value

        #expect(fixture.model.isDirty)
        #expect(try fixture.store.load(from: fixture.directory).name == "Output")
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("storage-started").path),
                "Cancellation before a write starts must not admit storage work")
        #expect(fixture.notices.screenRecordingOperations.isEmpty)
        #expect(fixture.model.errorMessage == nil)
    }

    @Test(arguments: [false, true])
    func shutdownSuppressesLateStorageSuccessOrFailure(_ fails: Bool) async throws {
        let gate = WriteGate()
        let fixture = try Fixture(write: { _, _, _ in
            gate.pause()
            if fails { throw CocoaError(.fileWriteOutOfSpace) }
        })
        defer { gate.resume(); fixture.close() }
        fixture.model.update { $0.name = "Unsaved" }
        try fixture.perform(.copy)
        await gate.waitUntilPaused()
        let task = fixture.model.operationTask
        fixture.model.shutdown()
        #expect(fixture.notices.screenRecordingOperations.isEmpty)
        gate.resume()
        await task?.value

        #expect(fixture.notices.screenRecordingOperations.isEmpty, "A closed model must not resurrect its progress")
        #expect(fixture.model.directory == fixture.directory && fixture.model.isDirty)
        #expect(fixture.model.errorMessage == nil)
        #expect(!fixture.model.isBusy)
    }

    @Test func repeatedCommandsCannotStartAdditionalTasksWhileStorageIsPending() async throws {
        let gate = WriteGate()
        let fixture = try Fixture(write: { project, source, destination in
            gate.pause()
            try Self.write(project, source, destination)
        })
        defer { gate.resume(); fixture.close() }
        fixture.model.saveProject()
        await gate.waitUntilPaused()
        let noticeID = fixture.notices.screenRecordingOperations.first?.id
        fixture.model.saveProject()
        fixture.model.saveCopy()
        fixture.model.export()
        fixture.model.start()
        #expect(fixture.panel.count == 0)
        #expect(fixture.notices.screenRecordingOperations.map(\.id) == [noticeID].compactMap { $0 })
        #expect(!fixture.model.prepareToClose())
        gate.resume()
        await fixture.model.operationTask?.value
        #expect(fixture.model.errorMessage == nil)
        fixture.model.saveProject()
        #expect(fixture.notices.screenRecordingOperations.count == 1)
        #expect(fixture.notices.screenRecordingOperations.first?.id != noticeID)
        gate.resume()
        await fixture.model.operationTask?.value
        #expect(fixture.hideCount == 0)
    }

    @Test(arguments: [Action.copy, .export], [false, true])
    func cancelledFilePanelsAndResponsesAfterShutdownDoNotPublishOperations(_ action: Action, _ shutdown: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.selectedAction = action
        fixture.model.update { $0.name = "Unsaved" }
        if action == .copy { fixture.model.saveCopy() } else { fixture.model.export() }
        #expect(fixture.model.isChoosingFile)
        #expect(fixture.notices.screenRecordingOperations.isEmpty)
        if shutdown { fixture.model.shutdown() }
        try fixture.panel.respond(shutdown ? .OK : .cancel, destination: fixture.destination)
        await fixture.model.operationTask?.value

        #expect(fixture.notices.screenRecordingOperations.isEmpty)
        #expect(!fixture.model.isBusy && !fixture.model.isChoosingFile)
        #expect(fixture.model.directory == fixture.directory && fixture.model.isDirty)
        #expect(try fixture.store.load(from: fixture.directory).name == "Output")
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
    }

    @Test(arguments: [RecordingExportFormat.mp4, .gif])
    func exportingUsesEncoderProgressAndCompletesWithoutHidingTheStudio(_ format: RecordingExportFormat) async throws {
        let gate = WriteGate()
        let exporter = ScreenRecordingExporter { if $0 == .frame(2) { gate.pause() } }
        let fixture = try Fixture(exporter: exporter)
        defer { gate.resume(); fixture.close() }
        try await fixture.createVideo()
        fixture.model.exportConfiguration = .init(format: format, resolution: .source, frameRate: format == .gif ? 10 : 30)
        var fractions: [Double] = []
        let subscription = fixture.notices.$left.sink { notices in
            fractions += notices.filter { $0.kind == .info }.compactMap(\.progress)
        }
        defer { subscription.cancel() }
        try fixture.perform(.export)
        await gate.waitUntilPaused()

        let notice = try #require(fixture.notices.screenRecordingOperations.first)
        #expect(notice.progress == exporter.progress)
        let progress = try #require(notice.progress)
        #expect(progress > 0 && progress < 1)
        #expect(notice.kind == .info)
        gate.resume()
        await fixture.model.operationTask?.value

        #expect(fractions == fractions.sorted(), "Published encoder progress must not jump backwards")
        #expect(fractions.contains { $0 > 0 && $0 < 1 })
        #expect(fixture.notices.screenRecordingOperations.first?.kind == .success)
        #expect(fixture.notices.screenRecordingOperations.first?.progress == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.destination.path))
        #expect(fixture.hideCount == 0 && fixture.model.canEdit)
    }

    @Test(arguments: [false, true])
    func encoderCancellationAndFailurePreserveExistingOutputAndEndTheProgress(_ cancel: Bool) async throws {
        let gate = WriteGate()
        let exporter = ScreenRecordingExporter { checkpoint in
            if checkpoint == .frame(2) {
                gate.pause()
                if !cancel { throw CocoaError(.fileWriteOutOfSpace) }
            }
        }
        let fixture = try Fixture(exporter: exporter)
        defer { gate.resume(); fixture.close() }
        try await fixture.createVideo()
        fixture.model.exportConfiguration = .init(format: .gif, resolution: .source, frameRate: 10)
        let original = Data("existing export".utf8)
        try original.write(to: fixture.destination)
        try fixture.perform(.export)
        await gate.waitUntilPaused()
        if cancel { fixture.model.cancelOperation() }
        gate.resume()
        await fixture.model.operationTask?.value

        #expect(try Data(contentsOf: fixture.destination) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
            .allSatisfy { !$0.hasPrefix(".zisla-recording-export-") })
        if cancel {
            #expect(fixture.notices.screenRecordingOperations.isEmpty)
            #expect(fixture.model.errorMessage == nil)
        } else {
            #expect(fixture.notices.screenRecordingOperations.first?.kind == .error)
            #expect(fixture.notices.screenRecordingOperations.first?.progress == nil)
            #expect(fixture.model.errorMessage != nil)
        }
        #expect(fixture.model.canEdit && fixture.hideCount == 0)
    }

    @Test(arguments: [RecordingExportFormat.mp4, .gif])
    func outputEncodesTheResolutionAndFrameRateChosenInTheExportPanel(_ format: RecordingExportFormat) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try await fixture.createVideo()
        fixture.model.update { $0.edits.segments = [.init(start: 0, end: 0.2)] }
        fixture.model.exportConfiguration = .init(format: .mp4, resolution: .source, frameRate: 30)
        fixture.model.export()
        let panel = try #require(fixture.panel.current)
        let settings = try #require((panel.accessoryView as? NSHostingView<ScreenRecordingExportSettingsView>)?.rootView.settings)
        let configuration = RecordingExportConfiguration(format: format, resolution: .fullHD, frameRate: format == .gif ? 15 : 60)
        settings.configuration = configuration
        fixture.selectedAction = .export
        let destination = fixture.root.appendingPathComponent("Chosen settings." + format.rawValue)
        try fixture.panel.respond(.OK, destination: destination)
        #expect(fixture.model.exportConfiguration == configuration)
        #expect(fixture.notices.screenRecordingOperations.first?.detail == destination.lastPathComponent)
        await fixture.model.operationTask?.value

        #expect(fixture.notices.screenRecordingOperations.first?.kind == .success)
        #expect(fixture.model.canEdit && fixture.hideCount == 0)
        #expect(fixture.panel.count == 1, "Confirming the export settings must not open a second destination panel")
        if format == .mp4 {
            let asset = AVURLAsset(url: destination)
            let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
            #expect(try await track.load(.naturalSize) == CGSize(width: 1_920, height: 1_920))
            #expect(abs(try await track.load(.nominalFrameRate) - 60) < 0.01)
            #expect(abs(try await asset.load(.duration).seconds - 0.2) < 0.01)
        } else {
            let source = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
            #expect(CGImageSourceGetCount(source) == 3)
            let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(first.width == 1_920 && first.height == 1_920)
            let duration = (0..<CGImageSourceGetCount(source)).reduce(0.0) { duration, index in
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                return duration + (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0)
            }
            #expect(abs(duration - 0.2) < 0.001)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
            .allSatisfy { !$0.hasPrefix(".zisla-recording-export-") })
    }

    @Test func completedProgressExpiresFromTheSharedDashboardSource() async throws {
        let expiry = ExpiryGate()
        let notices = SideNoticeQueue(capacityPerSide: 1, expirySleeper: { duration in
            #expect(duration == .seconds(3))
            await expiry.wait()
        })
        let fixture = try Fixture(notices: notices)
        defer { fixture.close() }
        fixture.model.saveProject()
        await fixture.model.operationTask?.value
        #expect(notices.screenRecordingOperations.count == 1)
        await expiry.waitUntilEntered()
        await expiry.release()
        for await left in notices.$left.values {
            if left.isEmpty { break }
        }
        #expect(notices.screenRecordingOperations.isEmpty)
    }

    @Test func recordingOperationsUseTheCompactBarWithoutOrdinaryPopupRows() {
        let notice = IslandNotice(id: "screen-recording-operation-test", title: "Output", progress: 0.5)
        let presentation = SideNoticeLayoutEngine().presentation(for: [notice], compactWingsEnabled: false)
        #expect(presentation.ordinaryNotices.isEmpty, "Recording progress must not appear as an ordinary side popup")
        #expect(SideNoticePresenter.isCompactNotice(notice))
    }

    @Test func ordinaryNoticeOverflowAndOtherActivitiesDoNotEvictOrDuplicateRecordingProgress() {
        let queue = SideNoticeQueue(capacityPerSide: 1)
        defer { queue.removeAll() }
        let recording = IslandNotice(id: "screen-recording-operation-test", title: "Output", side: .left)
        queue.enqueue(recording, expiresAfter: nil)
        for id in ["browser-download-left", "ai-active-test", "ordinary-1", "ordinary-2", "ordinary-3"] {
            queue.enqueue(IslandNotice(id: id, title: id, side: .left), expiresAfter: nil)
        }
        #expect(queue.screenRecordingOperations == [recording])
        #expect(queue.left.map(\.id) == [recording.id, "browser-download-left", "ai-active-test", "ordinary-3"])
        #expect(SideNoticeLayoutEngine().presentation(for: queue.left, compactWingsEnabled: false)
            .ordinaryNotices.map(\.id) == ["ordinary-3"])
    }

    @Test func compactRecordingProgressYieldsToVoiceAndUrgentNoticesAndHonorsSettings() {
        let operation = IslandNotice(id: "screen-recording-operation-test", title: "Output", progress: 0.4)
        let browser = IslandNotice(id: "browser-download-left", title: "Download", progress: 0.7)
        var settings = FeatureSettings.default
        #expect(SideNoticeLayoutEngine.screenRecordingOperationNotice(for: [browser, operation], settings: settings) == operation)
        for id in ["voice-processing-left", "focus-transition-test"] {
            #expect(SideNoticeLayoutEngine.screenRecordingOperationNotice(
                for: [operation, IslandNotice(id: id, title: id)], settings: settings) == nil)
        }
        settings.sideNoticesEnabled = false
        #expect(SideNoticeLayoutEngine.screenRecordingOperationNotice(for: [operation], settings: settings) == nil)
    }

    @Test func aVoiceTaskOnAnotherDisplayDoesNotHideRecordingProgress() throws {
        let name = "zisla-output-display-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        let settings = FeatureSettingsStore(defaults: defaults)
        let notices = SideNoticeQueue()
        let downloads = BrowserDownloadMonitor(directories: [], eventPaths: [])
        let media = NowPlayingService(loadLyrics: { _, _, _ in
            Issue.record("Recording progress must not request lyrics")
            fatalError("Unexpected lyrics request")
        })
        let sweep = AIResultSweepController()
        defer {
            notices.removeAll(); downloads.stop(); media.stop(); sweep.cancel()
            settings.flushPendingChanges(); defaults.removePersistentDomain(forName: name)
        }
        let display = SideNoticeDisplayState()
        let notice = IslandNotice(id: "screen-recording-operation-test", title: "Output", progress: 0.5)
        notices.enqueue(notice, expiresAfter: nil)
        notices.enqueue(IslandNotice(id: "voice-processing-left", title: "Voice"), expiresAfter: nil)
        let view = CompactStatusBarView(queue: notices, displayState: display, media: media,
            browserDownloads: downloads, settingsStore: settings, resultSweep: sweep, onStatusHidden: {})
        #expect(view.recordingOperationNotice == nil)
        display.hidesVoiceProcessingIndicator = true
        #expect(view.recordingOperationNotice == notice,
                "View content must use the same display-scoped voice filtering as the compact panel frame")
    }

    @Test func taskStatusUsesRealFractionsAndTerminalLabels() {
        var notice = IslandNotice(id: "screen-recording-operation-test", title: "Output")
        #expect(ScreenRecordingOperationNotice.progressText(for: notice) == AppLocalization.text("进行中"))
        notice.progress = 0.426
        #expect(ScreenRecordingOperationNotice.progressText(for: notice) == "43%")
        notice.kind = .success
        #expect(ScreenRecordingOperationNotice.progressText(for: notice) == AppLocalization.text("已完成"))
        notice.kind = .error
        #expect(ScreenRecordingOperationNotice.progressText(for: notice) == AppLocalization.text("失败"))
    }

    @Test func emptyStudioDoesNotPublishAPhantomSave() {
        let queue = SideNoticeQueue()
        let model = ScreenRecordingStudioModel(notices: queue)
        defer { model.shutdown() }
        model.saveProject()
        model.saveCopy()
        model.export()
        #expect(queue.screenRecordingOperations.isEmpty)
        #expect(!model.isBusy && !model.isChoosingFile)
    }

    nonisolated private static func write(_ project: ScreenRecordingProject, _ source: URL, _ destination: URL?) throws {
        let store = ScreenRecordingProjectStore(root: source)
        if let destination { try store.copy(project, from: source, to: destination) }
        else { try store.save(project, in: source) }
    }

    @MainActor private final class Panel {
        var count = 0
        private(set) var current: NSSavePanel?
        private var completion: ((URL?) -> Void)?
        func present(_ panel: NSSavePanel, completion: @escaping (URL?) -> Void) {
            count += 1
            current = panel
            self.completion = completion
        }
        func respond(_ response: NSApplication.ModalResponse, destination: URL) throws {
            let completion = try #require(completion)
            completion(response == .OK ? destination : nil)
        }
    }

    @MainActor private final class Fixture {
        let root: URL
        let directory: URL
        let store: ScreenRecordingProjectStore
        let model: ScreenRecordingStudioModel
        let notices: SideNoticeQueue
        let panel = Panel()
        var hideCount = 0
        var selectedAction = Action.export
        var destination: URL {
            let fileExtension = selectedAction == .copy ? ScreenRecordingProjectStore.projectExtension
                : model.exportConfiguration.format.rawValue
            return root.appendingPathComponent("output.\(fileExtension)", isDirectory: selectedAction == .copy)
        }
        var manifest: URL { directory.appendingPathComponent(ScreenRecordingProjectStore.manifestName) }

        init(exporter: ScreenRecordingExporter = ScreenRecordingExporter(), notices: SideNoticeQueue = SideNoticeQueue(),
             write: (@Sendable (ScreenRecordingProject, URL, URL?) throws -> Void)? = nil) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-output-test-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            store = ScreenRecordingProjectStore(root: root)
            directory = try store.createDirectory()
            self.notices = notices
            try Data([1]).write(to: directory.appendingPathComponent("screen.mp4"))
            let project = ScreenRecordingProject(name: "Output", videoFile: "screen.mp4", duration: 1, width: 16, height: 16)
            try store.save(project, in: directory)
            let context = try #require(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let preview = try #require(context.makeImage())
            model = ScreenRecordingStudioModel(exporter: exporter, projectStore: store,
                renderPreview: { _, _, _ in preview }, presentExportPanel: panel.present,
                notices: notices, writeProjectFiles: write ?? ScreenRecordingOperationTests.write)
            model.hideWindow = { [weak self] in self?.hideCount += 1 }
            model.install(project, directory: directory)
        }

        func perform(_ action: Action) throws {
            selectedAction = action
            switch action {
            case .save: model.saveProject()
            case .copy: model.saveCopy(); try panel.respond(.OK, destination: destination)
            case .export: model.export(); try panel.respond(.OK, destination: destination)
            }
        }

        func close() { model.shutdown(); notices.removeAll(); try? FileManager.default.removeItem(at: root) }

        func createVideo() async throws {
            let url = directory.appendingPathComponent("screen.mp4")
            try FileManager.default.removeItem(at: url)
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16,
            ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16,
            ])
            writer.add(input)
            #expect(writer.startWriting())
            writer.startSession(atSourceTime: .zero)
            let context = CIContext()
            for frame in 0..<6 {
                while !input.isReadyForMoreMediaData { await Task.yield() }
                var buffer: CVPixelBuffer?
                #expect(CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer) == kCVReturnSuccess)
                context.render(CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16)),
                               to: try #require(buffer))
                #expect(adaptor.append(try #require(buffer), withPresentationTime: CMTime(value: Int64(frame), timescale: 6)))
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 600))
            await writer.finishWriting()
            #expect(writer.status == .completed)
        }
    }

    private final class WriteGate: @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var entered = false
        private var waiter: CheckedContinuation<Void, Never>?
        func pause() {
            let continuation = lock.withLock {
                entered = true
                defer { waiter = nil }
                return waiter
            }
            continuation?.resume()
            if !Thread.isMainThread { semaphore.wait() }
        }
        func waitUntilPaused() async {
            await withCheckedContinuation { continuation in
                let ready = lock.withLock {
                    if entered { return true }
                    waiter = continuation
                    return false
                }
                if ready { continuation.resume() }
            }
        }
        func resume() { semaphore.signal() }
    }

    private actor ExpiryGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var entered = false
        private var waiter: CheckedContinuation<Void, Never>?
        func wait() async {
            entered = true
            waiter?.resume()
            waiter = nil
            await withCheckedContinuation { continuation = $0 }
        }
        func waitUntilEntered() async {
            if entered { return }
            await withCheckedContinuation { waiter = $0 }
        }
        func release() { continuation?.resume(); continuation = nil }
    }
}
