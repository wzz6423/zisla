import AppKit
import AVFoundation
import Combine
import CoreImage
import SwiftUI
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit

@MainActor
final class ScreenRecordingStudioModel: ObservableObject {
    let capture: ScreenRecordingService
    let exporter: ScreenRecordingExporter
    let transcriber: ScreenRecordingTranscriber
    var projectStore: ScreenRecordingProjectStore { ScreenRecordingProjectStore(root: recordingOutputDirectory) }
    @Published private(set) var recordingOutputDirectory: URL
    @Published var configuration = RecordingCaptureConfiguration()
    @Published var recordingCameraRound = true
    @Published var recordingCameraAspectRatio: RecordingCameraAspectRatio = .square
    @Published var recordingCameraCornerRadius = 0.1
    @Published var recordingCameraSize = 0.25
    @Published var exportConfiguration = RecordingExportConfiguration()
    @Published private(set) var project: ScreenRecordingProject?
    @Published private(set) var directory: URL?
    @Published var player: AVPlayer?
    @Published private(set) var preview: NSImage?
    @Published private(set) var canvasPreview: CGImage?
    @Published private(set) var currentTime = 0.0
    @Published private(set) var playbackTime = 0.0
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false
    @Published private(set) var isChoosingFile = false
    @Published private(set) var isStarting = false
    @Published private(set) var isStopping = false
    @Published private(set) var isCancelling = false
    @Published private(set) var isDirty = false
    @Published var selectedAIModel: AIModelConfigurationReference?
    @Published var aiInstruction = ""
    @Published private(set) var pendingAIProject: ScreenRecordingProject?
    private var pendingAIBase: ScreenRecordingProject?
    @Published private(set) var isShowingSourcePlayback = false
    @Published private(set) var isShowingTimelinePlayback = false
    private var timelinePlayer: AVPlayer?
    @Published var subtitleLanguage: AppLanguage = .simplifiedChinese
    private let appModel: AppModel?
    private let outputDirectoryStore: ScreenRecordingOutputDirectoryStore
    private let renderPreview: (ScreenRecordingProject, URL, Double) async throws -> CGImage
    private let presentExportPanel: (NSSavePanel, @escaping (NSApplication.ModalResponse) -> Void) -> Void
    private let aiCompletion: ((ScreenRecordingProject, String, AIModelConfigurationReference?) async throws -> String)?
    private(set) var previewTask: Task<Void, Never>?
    private(set) var operationTask: Task<Void, Never>?
    private var playerObserver: Any?
    private var timelineObserver: Any?
    private var undoHistory: [ScreenRecordingProject] = []
    private var redoHistory: [ScreenRecordingProject] = []
    private var previewRevision = 0
    private let previewContext = CIContext(options: [.cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    private var recordingDirectory: URL?
    private var cancellables: Set<AnyCancellable> = []
    var hideWindow: (() -> Void)?
    var showWindow: (() -> Void)?
    var commitPendingCanvasText: (() -> Void)?

    init(appModel: AppModel? = nil, capture: ScreenRecordingService = ScreenRecordingService(),
         exporter: ScreenRecordingExporter = ScreenRecordingExporter(),
         transcriber: ScreenRecordingTranscriber = ScreenRecordingTranscriber(),
         projectStore: ScreenRecordingProjectStore? = nil,
         outputDirectoryStore: ScreenRecordingOutputDirectoryStore = ScreenRecordingOutputDirectoryStore(),
         renderPreview: ((ScreenRecordingProject, URL, Double) async throws -> CGImage)? = nil,
         presentExportPanel: @escaping (NSSavePanel, @escaping (NSApplication.ModalResponse) -> Void) -> Void = {
             panel, completion in panel.begin(completionHandler: completion)
         },
         aiCompletion: ((ScreenRecordingProject, String, AIModelConfigurationReference?) async throws -> String)? = nil,
         onError: ((String) -> Void)? = nil) {
        self.appModel = appModel
        self.capture = capture
        self.exporter = exporter
        self.transcriber = transcriber
        self.outputDirectoryStore = outputDirectoryStore
        self.presentExportPanel = presentExportPanel
        self.recordingOutputDirectory = projectStore?.root ?? outputDirectoryStore.directory
        self.renderPreview = renderPreview ?? { project, directory, time in
            try await exporter.preview(project: project, directory: directory, sourceTime: time,
                maximumSize: CGSize(width: 1_200, height: 800))
        }
        self.aiCompletion = aiCompletion ?? appModel.map { appModel in
            { project, instruction, reference in
                guard let target = try AppModel.voicePostProcessingTarget(for: reference, store: appModel.aiAgent.store) else {
                    throw ScreenRecordingStudioError.missingAIModel
                }
                switch target {
                case let .http(endpoint, protocolKind, model, apiKey, effort, localInference, localThinkingEnabled):
                    return try await AIChatClient().complete(endpoint: endpoint, protocolKind: protocolKind,
                        model: model, systemPrompt: ScreenRecordingAIEditor.systemPrompt(project: project),
                        messages: [.init(role: .user, content: instruction)], apiKey: apiKey, effort: effort,
                        localInference: localInference, localThinkingEnabled: localThinkingEnabled).content
                case let .cliProfile(accountID, model):
                    return try await appModel.aiAgent.completeWithCLIProfile(accountID: accountID,
                        systemPrompt: ScreenRecordingAIEditor.systemPrompt(project: project),
                        messages: [.init(role: .user, content: instruction)], model: model)
                }
            }
        }
        selectedAIModel = appModel?.settingsStore.settings.voiceModelConfiguration
        subtitleLanguage = appModel?.languageStore.language ?? .simplifiedChinese
        let notifyError = onError ?? { [weak appModel] message in appModel?.transientMessage = message }
        $errorMessage.removeDuplicates().compactMap { $0 }
            .sink(receiveValue: notifyError).store(in: &cancellables)
        capture.$phase.combineLatest(capture.$elapsed)
            .sink { [weak self] _, _ in self?.objectWillChange.send() }.store(in: &cancellables)
        capture.$errorMessage.sink { [weak self] error in
            if let error { self?.errorMessage = error }
        }.store(in: &cancellables)
        capture.$cameraPreviewState.sink { [weak self] state in
            switch state {
            case .preparing: self?.errorMessage = nil
            case let .failed(message): self?.errorMessage = message
            default: break
            }
        }.store(in: &cancellables)
        exporter.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var isRecording: Bool { capture.phase.isActive || isStarting || isStopping || isCancelling }
    var captureProgressMessage: String {
        AppLocalization.text(isStopping ? "正在保存录屏" : "正在准备录制")
    }
    var canEdit: Bool { project != nil && !isRecording && !isBusy && !isChoosingFile && !exporter.isExporting }
    var canUndo: Bool { !undoHistory.isEmpty && canEdit }
    var canRedo: Bool { !redoHistory.isEmpty && canEdit }
    var availableSources: [RecordingCaptureSource] {
        capture.sources.filter { $0.mode == (configuration.mode == .region ? .display : configuration.mode) }
    }
    var aiModels: [(reference: AIModelConfigurationReference, title: String)] {
        guard let appModel else { return [] }
        let local = appModel.aiAgent.store.state.localModels.filter(\.isEnabled).map { configuration in
            let reference = AIModelConfigurationReference.local(configuration.id)
            return (reference, AppLocalization.text("本地 · %@", appModel.voiceModelConfigurationTitle(reference)))
        }
        let remote = appModel.aiAgent.store.state.channels.filter(\.isEnabled).map { channel in
            let reference = AIModelConfigurationReference.channel(channel.id)
            return (reference, AppLocalization.text("远端 · %@", appModel.voiceModelConfigurationTitle(reference)))
        }
        return local + remote
    }

    func loadSources() async {
        guard !isRecording else { return }
        do {
            try await capture.loadSources()
            guard !isRecording else { return }
            if !availableSources.contains(where: { $0.id == configuration.sourceID }) {
                configuration.sourceID = availableSources.first?.id ?? 0
                configuration.region = nil
            }
            errorMessage = nil
        } catch {
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    func requestScreenAccess() {
        _ = CGRequestScreenCaptureAccess()
        Task { await loadSources() }
    }

    func chooseRecordingOutputDirectory() {
        guard !isRecording, !isBusy, !isChoosingFile, !exporter.isExporting else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = recordingOutputDirectory
        panel.message = AppLocalization.text("选择录屏保存目录")
        isChoosingFile = true
        panel.begin { [weak self] response in
            guard let self else { return }
            self.isChoosingFile = false
            guard response == .OK, let url = panel.url else { return }
            do { try self.setRecordingOutputDirectory(url); self.errorMessage = nil }
            catch { self.errorMessage = error.localizedDescription }
        }
    }

    func setRecordingOutputDirectory(_ url: URL) throws {
        guard !isRecording, !isBusy, !exporter.isExporting else { return }
        try outputDirectoryStore.setDirectory(url)
        recordingOutputDirectory = outputDirectoryStore.directory
    }

    func selectMode(_ mode: RecordingCaptureMode) {
        guard !isRecording else { return }
        configuration.mode = mode
        configuration.sourceID = availableSources.first?.id ?? 0
        configuration.region = nil
    }

    func setRecordingCameraAspectRatio(_ ratio: RecordingCameraAspectRatio) {
        recordingCameraAspectRatio = ratio
        if ratio != .square { recordingCameraRound = false }
    }

    func start() {
        commitPendingCanvasText?()
        guard !isRecording, !isBusy, !isChoosingFile, !exporter.isExporting else { return }
        if configuration.mode == .region, configuration.region == nil { return }
        isStarting = true
        errorMessage = nil
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { isStarting = false; operationTask = nil; showWindow?() }
            do {
                if isDirty { try save() }
                let target = try projectStore.createDirectory()
                recordingDirectory = target
                hideWindow?()
                try await capture.start(configuration: configuration, directory: target)
            } catch {
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
                if let target = recordingDirectory,
                   (try? FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty) == true {
                    try? FileManager.default.removeItem(at: target)
                }
                recordingDirectory = nil
            }
        }
    }

    func pause() { Task { await capture.togglePause() } }

    func stop() {
        if isStarting { cancelOperation(); return }
        guard capture.phase.isActive, !isStopping, !isCancelling else { return }
        isStopping = true
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { isStopping = false; operationTask = nil; showWindow?() }
            do {
                let result = try await capture.stop()
                try Task.checkCancellation()
                guard let target = recordingDirectory else { throw ScreenRecordingProjectError.invalidProject }
                let date = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
                var recording = ScreenRecordingProject(result: result, name: AppLocalization.text("录屏 %@", date))
                recording.edits.cameraRound = recordingCameraRound
                recording.edits.cameraAspectRatio = recordingCameraAspectRatio
                recording.edits.cameraCornerRadius = recordingCameraCornerRadius
                recording.edits.cameraSize = recordingCameraSize
                install(recording, directory: target)
                isDirty = true
                recordingDirectory = nil
                try save()
            } catch {
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
        }
    }

    func cancelOperation() {
        operationTask?.cancel()
        transcriber.cancel()
        exporter.cancel()
        if isRecording && !isCancelling {
            isCancelling = true
            Task { [weak self] in
                guard let self else { return }
                defer { isCancelling = false; showWindow?() }
                await capture.cancel()
                await operationTask?.value
                if let target = recordingDirectory {
                    do { try FileManager.default.removeItem(at: target) }
                    catch { errorMessage = error.localizedDescription }
                }
                recordingDirectory = nil
                isStarting = false
                isStopping = false
            }
        }
    }

    func openProject() {
        commitPendingCanvasText?()
        guard !isRecording, !isBusy, !isChoosingFile, !exporter.isExporting else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.directory, .json]
        panel.message = AppLocalization.text("选择录屏项目")
        isChoosingFile = true
        panel.begin { [weak self] response in
            guard let self else { return }
            self.isChoosingFile = false
            guard response == .OK, let url = panel.url else { return }
            do {
                if self.isDirty { try self.save() }
                let folder = url.lastPathComponent == ScreenRecordingProjectStore.manifestName
                    ? url.deletingLastPathComponent() : url
                let project = try self.projectStore.load(from: folder)
                self.install(project, directory: folder)
            } catch { self.errorMessage = error.localizedDescription }
        }
    }

    func importVideo() {
        commitPendingCanvasText?()
        guard !isRecording, !isBusy, !isChoosingFile, !exporter.isExporting else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video]
        isChoosingFile = true
        panel.begin { [weak self] response in
            guard let self else { return }
            self.isChoosingFile = false
            guard response == .OK, let url = panel.url else { return }
            self.isBusy = true
            self.operationTask = Task { [weak self] in
                guard let self else { return }
                var imported: URL?
                defer { isBusy = false; operationTask = nil }
                do {
                    if isDirty { try save() }
                    let asset = AVURLAsset(url: url)
                    let duration = try await asset.load(.duration).seconds
                    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                        throw ScreenRecordingExportError.unavailableMedia
                    }
                    let size = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let dimensions = CGRect(origin: .zero, size: size).applying(transform).size
                    let name = "source." + url.pathExtension
                    let candidate = ScreenRecordingProject(name: url.deletingPathExtension().lastPathComponent,
                        videoFile: name, duration: duration, width: Int(abs(dimensions.width)), height: Int(abs(dimensions.height)))
                    try candidate.validate()
                    try Task.checkCancellation()
                    let folder = try projectStore.createDirectory()
                    imported = folder
                    try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(name))
                    try Task.checkCancellation()
                    try projectStore.save(candidate, in: folder)
                    install(candidate, directory: folder)
                    imported = nil
                } catch {
                    if let imported { try? FileManager.default.removeItem(at: imported) }
                    if !(error is CancellationError) { errorMessage = error.localizedDescription }
                }
            }
        }
    }

    func save() throws {
        commitPendingCanvasText?()
        guard let project, let directory else { return }
        try projectStore.save(project, in: directory)
        isDirty = false
    }

    func saveProject() {
        guard !isRecording, !isBusy, !isChoosingFile else { return }
        do { try save(); errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }

    func saveCopy() {
        commitPendingCanvasText?()
        guard canEdit, let project, let directory else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.fileName(project.name, extension: ScreenRecordingProjectStore.projectExtension)
        panel.directoryURL = recordingOutputDirectory
        panel.allowedContentTypes = [.init(filenameExtension: ScreenRecordingProjectStore.projectExtension) ?? .directory]
        panel.canCreateDirectories = true
        isChoosingFile = true
        panel.begin { [weak self] response in
            guard let self else { return }
            self.isChoosingFile = false
            guard response == .OK, let url = panel.url else { return }
            do {
                try self.projectStore.copy(project, from: directory, to: url)
                self.directory = url
                self.isDirty = false
                self.refreshPreview()
            } catch { self.errorMessage = error.localizedDescription }
        }
    }

    func export() {
        commitPendingCanvasText?()
        guard canEdit, let project, let directory else { return }
        let configuration = exportConfiguration
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.fileName(project.name, extension: configuration.format.rawValue)
        panel.directoryURL = recordingOutputDirectory
        panel.allowedContentTypes = [configuration.format == .gif ? .gif : .mpeg4Movie]
        panel.canCreateDirectories = true
        isChoosingFile = true
        presentExportPanel(panel) { [weak self] response in
            guard let self else { return }
            self.isChoosingFile = false
            guard response == .OK, let url = panel.url else { return }
            self.isBusy = true
            self.operationTask = Task { [weak self] in
                guard let self else { return }
                defer { isBusy = false; operationTask = nil }
                do {
                    try save()
                    try await exporter.export(project: project, directory: directory, to: url, configuration: configuration)
                    errorMessage = nil
                } catch { if !(error is CancellationError) { errorMessage = error.localizedDescription } }
            }
        }
    }

    static func fileName(_ name: String, extension fileExtension: String) -> String {
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        var stem = String(name.map { character in
            character.unicodeScalars.contains(where: invalid.contains) ? Character("-") : character
        })
        while stem.utf8.count + fileExtension.utf8.count + 1 > 255 { stem.removeLast() }
        return (stem.isEmpty ? AppLocalization.text("录屏") : stem) + "." + fileExtension
    }

    func update(_ change: (inout ScreenRecordingProject) -> Void) {
        commitPendingCanvasText?()
        guard canEdit, let original = project else { return }
        var replacement = original
        change(&replacement)
        guard replacement != original else { return }
        do {
            try replacement.validate()
            undoHistory.append(original)
            if undoHistory.count > 50 { undoHistory.removeFirst() }
            redoHistory.removeAll()
            project = replacement
            dismissAIEdit()
            isDirty = true
            seekTimeline(to: playbackTime)
        } catch { errorMessage = error.localizedDescription }
    }

    func undo() {
        commitPendingCanvasText?()
        guard canUndo, let original = project, let previous = undoHistory.popLast() else { return }
        redoHistory.append(original)
        project = previous
        dismissAIEdit()
        isDirty = true
        seekTimeline(to: playbackTime)
    }

    func redo() {
        commitPendingCanvasText?()
        guard canRedo, let original = project, let next = redoHistory.popLast() else { return }
        undoHistory.append(original)
        project = next
        dismissAIEdit()
        isDirty = true
        seekTimeline(to: playbackTime)
    }

    func split(at time: Double, segmentID: UUID? = nil) {
        update { project in
            guard let index = project.edits.segments.firstIndex(where: {
                (segmentID == nil || $0.id == segmentID) && time > $0.start + 0.001 && time < $0.end - 0.001
            }) else { return }
            let segment = project.edits.segments[index]
            project.edits.segments.replaceSubrange(index...index, with: [
                .init(id: segment.id, start: segment.start, end: time, speed: segment.speed),
                .init(start: time, end: segment.end, speed: segment.speed),
            ])
        }
    }

    func timelineSplitTarget(at outputTime: Double) -> ScreenRecordingTimelineStripGeometry.Target? {
        guard canEdit, let project,
              let timeline = try? RecordingExportTimeline(project: project),
              let slice = timeline.slice(at: outputTime) else { return nil }
        let sourceTime = slice.sourceTime(at: outputTime)
        guard sourceTime > slice.sourceStart + 0.001, sourceTime < slice.sourceEnd - 0.001 else { return nil }
        return .init(segmentID: project.edits.segments[slice.index].id, sourceTime: sourceTime, outputTime: outputTime)
    }

    @discardableResult
    func splitTimeline(at outputTime: Double) -> UUID? {
        guard let target = timelineSplitTarget(at: outputTime) else { return nil }
        let original = project?.edits.segments
        split(at: target.sourceTime, segmentID: target.segmentID)
        return project?.edits.segments != original ? target.segmentID : nil
    }

    func moveSegment(_ id: UUID, to destination: Int) {
        update { project in
            guard let index = project.edits.segments.firstIndex(where: { $0.id == id }),
                  project.edits.segments.indices.contains(destination) else { return }
            let segment = project.edits.segments.remove(at: index)
            project.edits.segments.insert(segment, at: destination)
        }
    }

    @discardableResult
    func duplicateSegment(_ id: UUID) -> UUID? {
        let copyID = UUID()
        update { project in
            guard let index = project.edits.segments.firstIndex(where: { $0.id == id }) else { return }
            var segment = project.edits.segments[index]
            segment.id = copyID
            project.edits.segments.insert(segment, at: index + 1)
        }
        return project?.edits.segments.contains(where: { $0.id == copyID }) == true ? copyID : nil
    }

    @discardableResult
    func deleteSegment(_ id: UUID) -> UUID? {
        guard canEdit, let project, let index = project.edits.segments.firstIndex(where: { $0.id == id }) else { return nil }
        let nextID = index + 1 < project.edits.segments.count ? project.edits.segments[index + 1].id
            : project.edits.segments.prefix(index).last?.id
        update { $0.edits.segments.remove(at: index) }
        return nextID
    }

    func cut(start: Double, end: Double) {
        commitPendingCanvasText?()
        guard let project, canEdit else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: ["version": 1,
                "operations": [["type": "cut", "start": start, "end": end]]])
            let replacement = try ScreenRecordingAIEditor.apply(response: String(decoding: data, as: UTF8.self), to: project)
            update { $0 = replacement }
        } catch { errorMessage = error.localizedDescription }
    }

    func seek(to time: Double) {
        guard time.isFinite else { return }
        commitPendingCanvasText?()
        guard let project else { return }
        currentTime = min(max(0, time), project.duration)
        if let timeline = try? RecordingExportTimeline(project: project),
           let slice = timeline.slices.first(where: { currentTime >= $0.sourceStart && currentTime <= $0.sourceEnd }) {
            playbackTime = slice.outputStart + (currentTime - slice.sourceStart) / slice.speed
        } else { playbackTime = 0 }
        player?.pause()
        timelinePlayer?.pause()
        isShowingSourcePlayback = false
        isShowingTimelinePlayback = false
        player?.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
        refreshPreview()
    }

    func seekTimeline(to time: Double) {
        guard time.isFinite else { return }
        commitPendingCanvasText?()
        guard let project else { return }
        if project.edits.segments.isEmpty { seek(to: currentTime); return }
        guard let timeline = try? RecordingExportTimeline(project: project) else { return }
        let output = min(max(0, time), timeline.duration)
        let source = timeline.slice(at: output).map { $0.sourceTime(at: output) }
            ?? timeline.slices.last!.sourceEnd
        seek(to: source)
        playbackTime = output
    }

    func playSource() {
        commitPendingCanvasText?()
        guard let player else { return }
        timelinePlayer?.pause()
        isShowingTimelinePlayback = false
        if player.rate == 0 { isShowingSourcePlayback = true; player.play() }
        else { player.pause(); isShowingSourcePlayback = false; refreshPreview() }
    }

    var activePlayer: AVPlayer? { isShowingTimelinePlayback ? timelinePlayer : player }

    func playTimeline() {
        commitPendingCanvasText?()
        if isShowingTimelinePlayback {
            timelinePlayer?.pause()
            isShowingTimelinePlayback = false
            refreshPreview()
            return
        }
        guard canEdit, let project, let directory else { return }
        let start = playbackTime < project.outputDuration ? playbackTime : 0
        isBusy = true
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { isBusy = false; operationTask = nil }
            do {
                let item = try await exporter.playbackItem(project: project, directory: directory)
                let timeline = try RecordingExportTimeline(project: project)
                try Task.checkCancellation()
                player?.pause()
                isShowingSourcePlayback = false
                if let timelineObserver { timelinePlayer?.removeTimeObserver(timelineObserver); self.timelineObserver = nil }
                let player = AVPlayer(playerItem: item)
                timelinePlayer = player
                playbackTime = start
                timelineObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
                    Task { @MainActor [weak self] in
                        guard let self, isShowingTimelinePlayback else { return }
                        playbackTime = time.seconds
                        if let slice = timeline.slice(at: time.seconds) { currentTime = slice.sourceTime(at: time.seconds) }
                        if time.seconds >= timeline.duration {
                            isShowingTimelinePlayback = false
                            playbackTime = 0
                            refreshPreview()
                        }
                    }
                }
                if start > 0 {
                    await player.seek(to: CMTime(seconds: start, preferredTimescale: 60_000),
                                      toleranceBefore: .zero, toleranceAfter: .zero)
                    try Task.checkCancellation()
                }
                isShowingTimelinePlayback = true
                player.play()
            } catch { if !(error is CancellationError) { errorMessage = error.localizedDescription } }
        }
    }

    func generateCaptions() {
        commitPendingCanvasText?()
        guard canEdit, let project, let directory else { return }
        isBusy = true
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { isBusy = false; operationTask = nil }
            do {
                let audio = try projectStore.mediaURL(project.microphoneFile ?? project.videoFile, in: directory)
                let captions = try await transcriber.transcribe(url: audio, locale: subtitleLanguage.locale)
                try Task.checkCancellation()
                let selected = captions.compactMap { caption -> RecordingCaption? in
                    let end = min(caption.end, project.duration)
                    guard caption.start < end else { return nil }
                    return .init(id: caption.id, start: caption.start, end: end, text: caption.text)
                }
                isBusy = false
                update { $0.captions = selected; $0.edits.showCaptions = true }
            } catch { if !(error is CancellationError) { errorMessage = error.localizedDescription } }
        }
    }

    func exportSubtitles() {
        commitPendingCanvasText?()
        guard canEdit, let project else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = Self.fileName(project.name, extension: "srt")
        panel.directoryURL = recordingOutputDirectory
        isChoosingFile = true
        panel.begin { [weak self] response in
            guard let self else { return }
            self.isChoosingFile = false
            guard response == .OK, let url = panel.url else { return }
            do {
                let captions = Self.outputCaptions(project)
                try ScreenRecordingCaptionFormatter.exportSRT(captions: captions).write(to: url, atomically: true, encoding: .utf8)
            } catch { self.errorMessage = error.localizedDescription }
        }
    }

    static func outputCaptions(_ project: ScreenRecordingProject) -> [RecordingCaption] {
        var output = [RecordingCaption]()
        var offset = 0.0
        for segment in project.edits.segments {
            for caption in project.captions {
                let start = max(segment.start, caption.start)
                let end = min(segment.end, caption.end)
                if start < end {
                    output.append(.init(start: offset + (start - segment.start) / segment.speed,
                        end: offset + (end - segment.start) / segment.speed, text: caption.text))
                }
            }
            offset += segment.outputDuration
        }
        return output.sorted { $0.start < $1.start }
    }

    func requestAIEdit() {
        commitPendingCanvasText?()
        guard canEdit, let project, let aiCompletion,
              !aiInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            isBusy = true
            dismissAIEdit()
            let instruction = aiInstruction
            let reference = selectedAIModel
            operationTask = Task { [weak self] in
                guard let self else { return }
                defer { isBusy = false; operationTask = nil }
                do {
                    let response = try await aiCompletion(project, instruction, reference)
                    try Task.checkCancellation()
                    pendingAIProject = try ScreenRecordingAIEditor.apply(response: response, to: project)
                    pendingAIBase = project
                } catch { if !(error is CancellationError) { errorMessage = error.localizedDescription } }
            }
    }

    func applyAIEdit() {
        commitPendingCanvasText?()
        guard let pending = pendingAIProject, pendingAIBase == project, canEdit else { return }
        update { $0 = pending }
        dismissAIEdit()
    }

    func dismissAIEdit() { pendingAIProject = nil; pendingAIBase = nil }

    func install(_ project: ScreenRecordingProject, directory: URL) {
        player?.pause()
        timelinePlayer?.pause()
        if let timelineObserver { timelinePlayer?.removeTimeObserver(timelineObserver); self.timelineObserver = nil }
        timelinePlayer = nil
        if let playerObserver { player?.removeTimeObserver(playerObserver); self.playerObserver = nil }
        self.project = project
        self.directory = directory
        preview = nil
        canvasPreview = nil
        undoHistory.removeAll()
        redoHistory.removeAll()
        isDirty = false
        currentTime = 0
        playbackTime = 0
        errorMessage = nil
        dismissAIEdit()
        isShowingSourcePlayback = false
        isShowingTimelinePlayback = false
        let player = AVPlayer(url: directory.appendingPathComponent(project.videoFile))
        self.player = player
        playerObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.isShowingSourcePlayback else { return }
                self.currentTime = time.seconds
                if player.rate == 0 { self.isShowingSourcePlayback = false; self.refreshPreview() }
            }
        }
        seekTimeline(to: 0)
    }

    func refreshPreview() {
        previewRevision += 1
        let revision = previewRevision
        previewTask?.cancel()
        guard let project, let directory else { preview = nil; canvasPreview = nil; return }
        var baseProject = project
        baseProject.edits.annotations = []
        baseProject.edits.showCaptions = false
        let time = currentTime
        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await renderPreview(baseProject, directory, time)
                guard !Task.isCancelled, revision == previewRevision else { return }
                let composed = try RecordingExportRenderer.composedPreview(base: image, project: project,
                    sourceTime: time, context: previewContext)
                canvasPreview = image
                preview = NSImage(cgImage: composed, size: NSSize(width: composed.width, height: composed.height))
            } catch {
                guard !Task.isCancelled, revision == previewRevision else { return }
                if errorMessage == nil { errorMessage = error.localizedDescription }
            }
        }
    }

    func reportCanvasRenderingFailure(_ error: Error) {
        if errorMessage == nil { errorMessage = error.localizedDescription }
    }

    func prepareToClose() -> Bool {
        commitPendingCanvasText?()
        if isRecording || isBusy || isChoosingFile || exporter.isExporting {
            errorMessage = AppLocalization.text("请先停止录制或取消操作再关闭工作室")
            return false
        }
        do {
            if isDirty { try save() }
            player?.pause()
            timelinePlayer?.pause()
            isShowingSourcePlayback = false
            isShowingTimelinePlayback = false
            return true
        }
        catch { errorMessage = error.localizedDescription; return false }
    }

    func shutdown() {
        commitPendingCanvasText = nil
        operationTask?.cancel()
        previewTask?.cancel()
        transcriber.cancel()
        exporter.cancel()
        player?.pause()
        timelinePlayer?.pause()
        if let playerObserver { player?.removeTimeObserver(playerObserver); self.playerObserver = nil }
        if let timelineObserver { timelinePlayer?.removeTimeObserver(timelineObserver); self.timelineObserver = nil }
    }

}

private enum ScreenRecordingStudioError: LocalizedError {
    case missingAIModel
    var errorDescription: String? { AppLocalization.text("请先选择已配置的 AI 模型") }
}
