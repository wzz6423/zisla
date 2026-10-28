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
    @Published var recordingCameraRound = false
    @Published var recordingCameraAspectRatio: RecordingCameraAspectRatio = .square
    @Published var recordingCameraCornerRadius = 0.5
    @Published var recordingCameraBorder = false
    @Published var recordingCameraSize = 0.25
    @Published var exportConfiguration = RecordingExportConfiguration()
    @Published private(set) var project: ScreenRecordingProject?
    @Published private(set) var directory: URL?
    @Published var player: AVPlayer?
    @Published private(set) var preview: NSImage?
    @Published private(set) var canvasPreview: CGImage?
    @Published private(set) var multitrackPreviewScene: RecordingMultitrackPreviewScene?
    @Published var selectedTimelineClipID: String?
    @Published private(set) var selectedMediaAssetID: UUID?
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
    private let presentExportPanel: (NSSavePanel, @escaping (URL?) -> Void) -> Void
    private var outputPanel: NSSavePanel?
    private let notices: SideNoticeQueue
    private let writeProjectFiles: @Sendable (ScreenRecordingProject, URL, URL?) throws -> Void
    private var outputNotice: IslandNotice?
    private let aiCompletion: ((ScreenRecordingProject, String, AIModelConfigurationReference?) async throws -> String)?
    private(set) var previewTask: Task<Void, Never>?
    private(set) var operationTask: Task<Void, Never>?
    private var playerObserver: Any?
    private var timelineObserver: Any?
    private var undoHistory: [ScreenRecordingProject] = []
    private var redoHistory: [ScreenRecordingProject] = []
    private var previewRevision = 0
    private var projectRevision = 0
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
         presentExportPanel: @escaping (NSSavePanel, @escaping (URL?) -> Void) -> Void = { panel, completion in
             panel.begin { response in completion(response == .OK ? panel.url : nil) }
         },
         notices: SideNoticeQueue? = nil,
         writeProjectFiles: @escaping @Sendable (ScreenRecordingProject, URL, URL?) throws -> Void = {
             project, directory, destination in
             let store = ScreenRecordingProjectStore(root: directory)
             if let destination { try store.copy(project, from: directory, to: destination) }
             else { try store.save(project, in: directory) }
         },
         aiCompletion: ((ScreenRecordingProject, String, AIModelConfigurationReference?) async throws -> String)? = nil,
         onError: ((String) -> Void)? = nil) {
        self.appModel = appModel
        self.capture = capture
        self.exporter = exporter
        self.transcriber = transcriber
        self.outputDirectoryStore = outputDirectoryStore
        self.presentExportPanel = presentExportPanel
        self.notices = notices ?? appModel?.notices ?? SideNoticeQueue()
        self.writeProjectFiles = writeProjectFiles
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
        exporter.$progress.sink { [weak self] progress in
            guard let self, var notice = outputNotice else { return }
            notice.progress = progress
            outputNotice = notice
            self.notices.updateIfPresent(notice)
        }.store(in: &cancellables)
    }

    var isRecording: Bool { capture.phase.isActive || isStarting || isStopping || isCancelling }
    var captureProgressMessage: String {
        AppLocalization.text(isStopping ? "正在保存录屏" : "正在准备录制")
    }
    var canEdit: Bool { project != nil && !isRecording && !isBusy && !isChoosingFile && !exporter.isExporting }
    var canUndo: Bool { !undoHistory.isEmpty && canEdit }
    var canRedo: Bool { !redoHistory.isEmpty && canEdit }
    var timeline: RecordingMultitrackTimeline? { project.map(RecordingMultitrackTimeline.migrating) }
    var mediaAssets: [RecordingMediaAsset] { timeline?.assets.filter { $0.isHiddenFromLibrary != true } ?? [] }
    var selectedTimelineClip: RecordingTimelineClip? { timeline?.clips.first { $0.id == selectedTimelineClipID } }
    var selectedRemovedMediaAsset: RecordingMediaAsset? {
        let id = selectedTimelineClip?.content.assetID
        return timeline?.assets.first { $0.id == id && $0.isHiddenFromLibrary == true }
    }
    var sourceDuration: Double { timeline?.assets.first { $0.id == selectedMediaAssetID }?.duration ?? project?.duration ?? 0 }
    var canExport: Bool { canEdit && (project?.outputDuration ?? 0) > 0 }
    var overlayTime: Double { project?.timeline == nil ? currentTime : playbackTime }
    var overlayDuration: Double { project?.timeline == nil ? project?.duration ?? 0 : project?.outputDuration ?? 0 }
    var canGenerateCaptions: Bool {
        canEdit && (project?.timeline == nil || timeline?.assets.contains { $0.id == selectedMediaAssetID && $0.kind != .image } == true)
    }

    func timelineClipTitle(_ clip: RecordingTimelineClip) -> String {
        switch clip.content {
        case let .annotation(id):
            let annotation = project?.edits.annotations?.first { $0.id == id }
            return annotation?.text.isEmpty == false ? annotation!.text : AppLocalization.text(annotation?.kind.title ?? "文字标注")
        case let .caption(id): return project?.captions.first { $0.id == id }?.text ?? AppLocalization.text("字幕")
        default: return timeline?.assets.first { $0.id == clip.content.assetID }?.name ?? AppLocalization.text(clip.content.trackKind.title)
        }
    }
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
                if let project, let directory {
                    let missingMedia = project.mediaFiles.contains { name in
                        guard case let .failure(error as CocoaError) = Result(catching: {
                            try projectStore.mediaURL(name, in: directory)
                        }) else { return false }
                        return error.code == .fileReadNoSuchFile
                    }
                    if missingMedia { clearProject() }
                }
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
                recording.edits.cameraBorder = recordingCameraBorder
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
        panel.allowedContentTypes = [.movie, .video, .image, .audio]
        panel.allowsMultipleSelection = true
        isChoosingFile = true
        panel.begin { [weak self] response in
            guard let self else { return }
            self.isChoosingFile = false
            guard response == .OK else { return }
            self.importMedia(panel.urls)
        }
    }

    func importMedia(_ urls: [URL]) {
        commitPendingCanvasText?()
        guard !urls.isEmpty, !isRecording, !isBusy, !isChoosingFile, !exporter.isExporting else { return }
        let original = project
        let originalDirectory = directory
        let store = projectStore
        let revision = projectRevision
        isBusy = true
        errorMessage = nil
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if projectRevision == revision { isBusy = false; operationTask = nil }
            }
            var prepared: RecordingMediaImportResult?
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try await RecordingMediaImporter.prepare(urls: urls, project: original, directory: originalDirectory, store: store)
                }
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                prepared = result
                try Task.checkCancellation()
                guard project == original, directory == originalDirectory else { result.discard(); return }
                if original == nil {
                    try store.save(result.project, in: result.directory)
                    install(result.project, directory: result.directory)
                } else {
                    isBusy = false
                    update { $0 = result.project }
                    guard project == result.project else { result.discard(); return }
                }
                prepared = nil
            } catch {
                prepared?.discard()
                guard projectRevision == revision else { return }
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
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
        commitPendingCanvasText?()
        guard canEdit, let project, let directory else { return }
        saveProject(project, from: directory, to: nil)
    }

    func saveCopy() {
        commitPendingCanvasText?()
        guard canEdit, let project, let directory else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.fileName(project.name, extension: ScreenRecordingProjectStore.projectExtension)
        panel.directoryURL = recordingOutputDirectory
        panel.allowedContentTypes = [.init(filenameExtension: ScreenRecordingProjectStore.projectExtension) ?? .directory]
        panel.canCreateDirectories = true
        outputPanel = panel
        isChoosingFile = true
        presentExportPanel(panel) { [weak self, weak panel] url in
            guard let self, let panel, self.outputPanel === panel else { return }
            self.outputPanel = nil
            self.isChoosingFile = false
            guard let url else { return }
            self.saveProject(project, from: directory, to: url)
        }
    }

    private func saveProject(_ project: ScreenRecordingProject, from directory: URL, to destination: URL?) {
        beginOutputNotice(title: AppLocalization.text(destination == nil ? "保存录屏项目" : "项目另存为"),
                          destination: destination ?? directory, symbol: "square.and.arrow.down")
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { isBusy = false; operationTask = nil }
            do {
                try await writeProject(project, from: directory, to: destination)
                guard outputNotice != nil else { return }
                isDirty = false
                if let destination { self.directory = destination; refreshPreview() }
                finishOutputNotice()
            } catch { finishOutputNotice(error: error) }
        }
    }

    func export() {
        commitPendingCanvasText?()
        guard canExport, let project, let directory else { return }
        let panel = NSSavePanel()
        panel.title = AppLocalization.text("导出设置")
        panel.prompt = AppLocalization.text("导出录屏")
        panel.nameFieldStringValue = Self.fileName(project.name, extension: exportConfiguration.format.fileExtension)
        panel.directoryURL = recordingOutputDirectory
        panel.canCreateDirectories = true
        let settings = ScreenRecordingExportSettings(configuration: exportConfiguration, panel: panel, duration: project.outputDuration)
        let accessory = NSHostingView(rootView: ScreenRecordingExportSettingsView(settings: settings))
        accessory.frame.size = accessory.fittingSize
        panel.accessoryView = accessory
        outputPanel = panel
        isChoosingFile = true
        presentExportPanel(panel) { [weak self, weak panel] url in
            guard let self, let panel, self.outputPanel === panel else { return }
            self.outputPanel = nil
            panel.accessoryView = nil
            panel.delegate = nil
            self.isChoosingFile = false
            guard let url else { return }
            guard settings.canConfirm else { self.errorMessage = settings.validationMessage; return }
            let configuration = settings.configuration
            self.exportConfiguration = configuration
            self.beginOutputNotice(title: AppLocalization.text(configuration.format.isAudioOnly ? "导出音频" : "导出录屏"),
                destination: url, symbol: configuration.format.isAudioOnly ? "waveform" : configuration.format == .livePhoto ? "livephoto" : "film")
            self.operationTask = Task { [weak self] in
                guard let self else { return }
                defer { isBusy = false; operationTask = nil }
                do {
                    try await writeProject(project, from: directory, to: nil)
                    guard outputNotice != nil else { return }
                    isDirty = false
                    try await exporter.export(project: project, directory: directory, to: url, configuration: configuration)
                    finishOutputNotice()
                } catch { finishOutputNotice(error: error) }
            }
        }
    }

    private func writeProject(_ project: ScreenRecordingProject, from directory: URL, to destination: URL?) async throws {
        try Task.checkCancellation()
        let write = writeProjectFiles
        let worker = Task.detached(priority: .userInitiated) { try write(project, directory, destination) }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }

    private func beginOutputNotice(title: String, destination: URL, symbol: String) {
        isBusy = true
        errorMessage = nil
        notices.removeAll(withIDPrefix: ScreenRecordingOperationNotice.prefix)
        let notice = IslandNotice(id: ScreenRecordingOperationNotice.prefix + UUID().uuidString,
            title: title, detail: destination.lastPathComponent, side: .left, symbolName: symbol)
        outputNotice = notice
        notices.enqueue(notice, expiresAfter: nil)
    }

    private func finishOutputNotice(error: Error? = nil) {
        guard var notice = outputNotice else { return }
        outputNotice = nil
        if error is CancellationError {
            notices.remove(id: notice.id)
            return
        }
        if let error {
            notice.kind = .error
            notice.progress = nil
            notice.detail = error.localizedDescription
            errorMessage = error.localizedDescription
        } else {
            notice.kind = .success
            errorMessage = nil
        }
        notices.enqueue(notice, expiresAfter: 3)
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
        Self.synchronizeTimelineOverlays(original: original, replacement: &replacement)
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

    private static func synchronizeTimelineOverlays(original: ScreenRecordingProject,
                                                    replacement: inout ScreenRecordingProject) {
        guard var timeline = replacement.timeline else { return }
        let annotations = Set((replacement.edits.annotations ?? []).map(\.id))
        let captions = Set(replacement.captions.map(\.id))
        timeline.clips.removeAll {
            switch $0.content {
            case let .annotation(id): !annotations.contains(id)
            case let .caption(id): !captions.contains(id)
            default: false
            }
        }
        let oldAnnotations = Dictionary(uniqueKeysWithValues: (original.edits.annotations ?? []).map { ($0.id, $0) })
        let oldCaptions = Dictionary(uniqueKeysWithValues: original.captions.map { ($0.id, $0) })
        let indices = Dictionary(grouping: timeline.clips.indices, by: { timeline.clips[$0].content })
        for annotation in replacement.edits.annotations ?? [] {
            let previous = oldAnnotations[annotation.id]
            synchronize(.annotation(annotation.id), start: annotation.start, end: annotation.end,
                isNew: previous == nil, changed: previous.map { $0.start != annotation.start || $0.end != annotation.end } ?? false,
                matching: indices[.annotation(annotation.id)] ?? [], timeline: &timeline)
        }
        for caption in replacement.captions {
            let previous = oldCaptions[caption.id]
            synchronize(.caption(caption.id), start: caption.start, end: caption.end,
                isNew: previous == nil, changed: previous.map { $0.start != caption.start || $0.end != caption.end } ?? false,
                matching: indices[.caption(caption.id)] ?? [], timeline: &timeline)
        }
        replacement.timeline = timeline
    }

    private static func synchronize(_ content: RecordingTimelineContent, start: Double, end: Double,
                                    isNew: Bool, changed: Bool, matching: [Int], timeline: inout RecordingMultitrackTimeline) {
        if matching.isEmpty && isNew {
            let track = timeline.clips.first(where: {
                switch $0.content {
                case .annotation, .caption: true
                default: false
                }
            })?.trackID ?? timeline.addTrack()
            timeline.clips.append(.init(trackID: track, content: content, start: start, sourceEnd: end - start))
        } else if changed {
            for index in matching {
                timeline.clips[index].start = start
                timeline.clips[index].sourceStart = 0
                timeline.clips[index].sourceEnd = end - start
                timeline.clips[index].speed = 1
            }
        }
    }

    func selectMediaAsset(_ id: UUID) {
        guard let asset = timeline?.assets.first(where: { $0.id == id }) else { return }
        selectedMediaAssetID = id
        if asset.kind != .image, let directory { installSourcePlayer(file: asset.file, directory: directory) }
        else {
            if let playerObserver { player?.removeTimeObserver(playerObserver); self.playerObserver = nil }
            player?.pause()
            player = nil
        }
    }

    func selectTimelineClip(_ id: String) {
        guard let clip = timeline?.clips.first(where: { $0.id == id }) else { return }
        selectedTimelineClipID = id
        if let assetID = clip.content.assetID, selectedMediaAssetID != assetID { selectMediaAsset(assetID) }
        seekTimeline(to: clip.start)
    }

    func removeMediaAsset(_ id: UUID) {
        update { project in
            var timeline = RecordingMultitrackTimeline.migrating(project)
            guard let index = timeline.assets.firstIndex(where: { $0.id == id }) else { return }
            timeline.assets[index].isHiddenFromLibrary = true
            project.version = ScreenRecordingProject.currentVersion
            project.timeline = timeline
        }
    }

    func restoreMediaAsset(_ id: UUID) {
        guard let directory else { return }
        update { project in
            guard var timeline = project.timeline,
                  let index = timeline.assets.firstIndex(where: { $0.id == id && $0.isHiddenFromLibrary == true }) else { return }
            do {
                _ = try projectStore.mediaURL(timeline.assets[index].file, in: directory)
                timeline.assets[index].isHiddenFromLibrary = nil
                project.timeline = timeline
                errorMessage = nil
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func selectCanvasTimelineContent(_ content: RecordingTimelineContent) {
        guard project?.timeline != nil, selectedTimelineClip?.content != content else { return }
        let matching = timeline?.clips.filter { $0.content == content } ?? []
        selectedTimelineClipID = (matching.first { $0.contains(playbackTime) } ?? matching.first)?.id
    }

    func seekOverlay(_ content: RecordingTimelineContent, sourceStart: Double) {
        if project?.timeline != nil {
            selectCanvasTimelineContent(content)
            if let clip = selectedTimelineClip, clip.content == content { seekTimeline(to: clip.start) }
        } else { seek(to: sourceStart) }
    }

    @discardableResult
    func addOverlayAnnotation(_ kind: RecordingAnnotationKind) -> UUID? {
        let start = overlayTime
        let end = min(overlayDuration, start + 2)
        guard start < end else { return nil }
        let annotation = RecordingAnnotation(kind: kind, start: start, end: end,
            text: kind == .text ? AppLocalization.text("文字标注") : "")
        update { $0.edits.annotations = ($0.edits.annotations ?? []) + [annotation] }
        return project?.edits.annotations?.contains(where: { $0.id == annotation.id }) == true ? annotation.id : nil
    }

    @discardableResult
    func addOverlayCaption() -> UUID? {
        let start = overlayTime
        let end = min(overlayDuration, start + 2)
        guard start < end else { return nil }
        let caption = RecordingCaption(start: start, end: end, text: AppLocalization.text("新字幕"))
        update { $0.captions.append(caption) }
        return project?.captions.contains(where: { $0.id == caption.id }) == true ? caption.id : nil
    }

    func addTimelineTrack(_ kind: RecordingTimelineTrackKind = .video) {
        update { project in
            var timeline = RecordingMultitrackTimeline.migrating(project)
            timeline.addTrack(kind)
            project.version = ScreenRecordingProject.currentVersion
            project.timeline = timeline
        }
    }

    @discardableResult
    func addAssetToTimeline(_ id: UUID, at time: Double? = nil, trackID: String? = nil) -> String? {
        var added: String?
        let start = time ?? playbackTime
        update { project in
            var timeline = RecordingMultitrackTimeline.migrating(project)
            guard let asset = timeline.assets.first(where: { $0.id == id }),
                  let clipID = timeline.addAssetClip(id, at: start, trackID: trackID),
                  let index = timeline.clips.firstIndex(where: { $0.id == clipID }) else { return }
            if asset.kind == .image {
                let crop = project.edits.crop ?? .init(x: 0, y: 0, width: 1, height: 1)
                let aspect = project.edits.canvasAspectRatio?.ratio
                    ?? (Double(project.width) * crop.width / (Double(project.height) * crop.height))
                let imageAspect = Double(asset.width) / Double(asset.height)
                let width = min(1, imageAspect / aspect)
                let height = min(1, aspect / imageAspect)
                timeline.clips[index].layout = .init(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
            } else if asset.file == project.videoFile, asset.id == project.id {
                timeline.clips[index].content = .recording(id)
            }
            project.version = ScreenRecordingProject.currentVersion
            project.timeline = timeline
            added = clipID
        }
        if let added, project?.timeline?.clips.contains(where: { $0.id == added }) == true { selectTimelineClip(added); return added }
        return nil
    }

    @discardableResult
    func addTimelineText() -> UUID? {
        let annotation = RecordingAnnotation(kind: .text, start: playbackTime, end: playbackTime + 2,
            text: AppLocalization.text("文字标注"))
        update { project in
            var timeline = RecordingMultitrackTimeline.migrating(project)
            let track = timeline.addTrack()
            let clip = RecordingTimelineClip(trackID: track, content: .annotation(annotation.id),
                start: annotation.start, sourceEnd: 2)
            timeline.clips.append(clip)
            project.edits.annotations = (project.edits.annotations ?? []) + [annotation]
            project.timeline = timeline
            project.version = ScreenRecordingProject.currentVersion
        }
        guard let clip = project?.timeline?.clips.first(where: { $0.content == .annotation(annotation.id) }) else { return nil }
        selectTimelineClip(clip.id)
        return annotation.id
    }

    func updateTimelineClip(_ id: String, _ change: (inout RecordingTimelineClip) -> Void) {
        update { project in
            var timeline = RecordingMultitrackTimeline.migrating(project)
            guard let index = timeline.clips.firstIndex(where: { $0.id == id }) else { return }
            change(&timeline.clips[index])
            project.version = ScreenRecordingProject.currentVersion
            project.timeline = timeline
        }
    }

    func moveTimelineClip(_ id: String, to time: Double, trackID: String? = nil) {
        updateTimelineClip(id) { clip in
            guard time.isFinite else { return }
            clip.start = max(0, time)
            if let trackID { clip.trackID = trackID }
        }
    }

    func updateTimelineTrack(_ id: String, _ change: (inout RecordingTimelineTrack) -> Void) {
        update { project in
            var timeline = RecordingMultitrackTimeline.migrating(project)
            guard let index = timeline.tracks.firstIndex(where: { $0.id == id }) else { return }
            change(&timeline.tracks[index])
            project.version = ScreenRecordingProject.currentVersion
            project.timeline = timeline
        }
    }

    func moveTimelineTrack(_ id: String, by distance: Int) {
        update { project in
            var timeline = RecordingMultitrackTimeline.migrating(project)
            guard let index = timeline.tracks.firstIndex(where: { $0.id == id }),
                  timeline.tracks.indices.contains(index + distance) else { return }
            let track = timeline.tracks.remove(at: index)
            timeline.tracks.insert(track, at: index + distance)
            project.version = ScreenRecordingProject.currentVersion
            project.timeline = timeline
        }
    }

    @discardableResult
    func splitTimelineClip(_ id: String, at time: Double) -> String? {
        var result: String?
        update { project in
            var timeline = RecordingMultitrackTimeline.migrating(project)
            guard let tailID = timeline.splitClip(id, at: time),
                  let index = timeline.clips.firstIndex(where: { $0.id == tailID }) else { return }
            Self.copyOverlay(for: &timeline.clips[index], project: &project)
            project.version = ScreenRecordingProject.currentVersion
            project.timeline = timeline
            result = tailID
        }
        return result.flatMap { id in project?.timeline?.clips.contains { $0.id == id } == true ? id : nil }
    }

    @discardableResult
    func duplicateTimelineClip(_ id: String) -> String? {
        let copyID = UUID().uuidString
        update { project in
            var timeline = RecordingMultitrackTimeline.migrating(project)
            guard var clip = timeline.clips.first(where: { $0.id == id }) else { return }
            clip.id = copyID
            clip.start = clip.end
            Self.copyOverlay(for: &clip, project: &project)
            timeline.clips.append(clip)
            project.version = ScreenRecordingProject.currentVersion
            project.timeline = timeline
        }
        return project?.timeline?.clips.contains { $0.id == copyID } == true ? copyID : nil
    }

    private static func copyOverlay(for clip: inout RecordingTimelineClip, project: inout ScreenRecordingProject) {
        switch clip.content {
        case let .annotation(id):
            if var annotation = project.edits.annotations?.first(where: { $0.id == id }) {
                annotation.id = UUID()
                annotation.start = clip.start
                annotation.end = clip.end
                project.edits.annotations?.append(annotation)
                clip.content = .annotation(annotation.id)
            }
        case let .caption(id):
            if var caption = project.captions.first(where: { $0.id == id }) {
                caption.id = UUID()
                caption.start = clip.start
                caption.end = clip.end
                project.captions.append(caption)
                clip.content = .caption(caption.id)
            }
        default: break
        }
    }

    func deleteTimelineClip(_ id: String) {
        update { project in
            var timeline = RecordingMultitrackTimeline.migrating(project)
            guard let clip = timeline.clips.first(where: { $0.id == id }) else { return }
            timeline.clips.removeAll { $0.id == id }
            if !timeline.clips.contains(where: { $0.content == clip.content }) {
                if case let .annotation(id) = clip.content { project.edits.annotations?.removeAll { $0.id == id } }
                if case let .caption(id) = clip.content { project.captions.removeAll { $0.id == id } }
            }
            project.version = ScreenRecordingProject.currentVersion
            project.timeline = timeline
        }
        if selectedTimelineClipID == id { selectedTimelineClipID = timeline?.clips.first?.id }
    }

    func detachTimelineAudio(_ id: String, probe: @escaping ScreenRecordingAudioDetachment.AudioProbe = ScreenRecordingAudioDetachment.audioRanges) {
        commitPendingCanvasText?()
        guard canEdit, let snapshot = project, let folder = directory else { return }
        let revision = projectRevision
        isBusy = true
        errorMessage = nil
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if projectRevision == revision { isBusy = false; operationTask = nil }
            }
            do {
                let replacement = try await ScreenRecordingAudioDetachment.prepare(project: snapshot, directory: folder,
                    clipID: id, probe: probe)
                try Task.checkCancellation()
                guard project == snapshot, directory == folder, let replacement else { return }
                isBusy = false
                update { $0 = replacement }
            } catch {
                guard !Task.isCancelled, project == snapshot, directory == folder else { return }
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
        }
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
        if project.timeline != nil {
            guard start.isFinite, end.isFinite, start >= 0, end > start else { return }
            update { project in
                var timeline = project.timeline!
                var clips: [RecordingTimelineClip] = []
                for clip in timeline.clips {
                    guard clip.content.trackKind == .video, clip.start < end, clip.end > start else {
                        clips.append(clip)
                        continue
                    }
                    if clip.start < start {
                        var head = clip
                        head.sourceEnd = clip.sourceTime(at: start)
                        clips.append(head)
                    }
                    if clip.end > end {
                        var tail = clip
                        if clip.start < start { tail.id = UUID().uuidString }
                        tail.sourceStart = clip.sourceTime(at: end)
                        tail.start = end
                        clips.append(tail)
                    }
                }
                timeline.clips = clips
                project.timeline = timeline
            }
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: ["version": 1,
                "operations": [["type": "cut", "start": start, "end": end]]])
            let replacement = try ScreenRecordingAIEditor.apply(response: String(decoding: data, as: UTF8.self), to: project)
            update { $0 = replacement }
        } catch { errorMessage = error.localizedDescription }
    }

    func cutCaption(_ id: UUID) {
        guard let project, let caption = project.captions.first(where: { $0.id == id }) else { return }
        if project.timeline != nil {
            selectCanvasTimelineContent(.caption(id))
            if let clip = selectedTimelineClip, clip.content == .caption(id) { cut(start: clip.start, end: clip.end) }
        } else { cut(start: caption.start, end: caption.end) }
    }

    func seek(to time: Double) {
        guard time.isFinite else { return }
        if project?.timeline != nil { seekTimeline(to: time); return }
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
        if let timeline = project.timeline {
            playbackTime = min(max(0, time), timeline.duration)
            currentTime = playbackTime
            player?.pause()
            timelinePlayer?.pause()
            isShowingSourcePlayback = false
            isShowingTimelinePlayback = false
            refreshPreview()
            return
        }
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
        if player.rate == 0 {
            if !isShowingSourcePlayback, project?.timeline != nil {
                let clip = selectedTimelineClip
                currentTime = clip?.content.assetID == selectedMediaAssetID ? clip?.sourceStart ?? 0 : 0
                player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 60_000))
            }
            isShowingSourcePlayback = true
            player.play()
        } else { player.pause(); isShowingSourcePlayback = false; refreshPreview() }
    }

    func seekSource(to time: Double) {
        guard time.isFinite, let player else { return }
        currentTime = min(max(0, time), sourceDuration)
        player.pause()
        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 60_000))
        isShowingSourcePlayback = true
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
        guard canExport, let project, let directory else { return }
        let start = playbackTime < project.outputDuration ? playbackTime : 0
        isBusy = true
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { isBusy = false; operationTask = nil }
            do {
                let item = try await exporter.playbackItem(project: project, directory: directory)
                let timeline = project.timeline == nil ? try RecordingExportTimeline(project: project) : nil
                try Task.checkCancellation()
                guard self.project == project, self.directory == directory else { return }
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
                        if let slice = timeline?.slice(at: time.seconds) { currentTime = slice.sourceTime(at: time.seconds) }
                        else { currentTime = time.seconds }
                        if time.seconds >= project.outputDuration {
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
        guard canGenerateCaptions, let project, let directory else { return }
        let revision = projectRevision
        let media = project.timeline?.assets.first { $0.id == selectedMediaAssetID }
        let recording = media == nil || (media?.id == project.id && media?.file == project.videoFile)
        let sourceFile = recording ? project.microphoneFile ?? project.videoFile : media!.file
        let sourceDuration = media?.duration ?? project.duration
        let sourceClips = project.timeline?.clips.filter { $0.content.assetID == media?.id } ?? []
        let selected = selectedTimelineClip.flatMap { $0.content.assetID == media?.id ? $0 : nil }
        isBusy = true
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if projectRevision == revision { isBusy = false; operationTask = nil }
            }
            do {
                let audio = try projectStore.mediaURL(sourceFile, in: directory)
                let captions = try await transcriber.transcribe(url: audio, locale: subtitleLanguage.locale)
                try Task.checkCancellation()
                guard self.project == project, self.directory == directory else { return }
                let bounded = captions.compactMap { caption -> RecordingCaption? in
                    let end = min(caption.end, sourceDuration)
                    guard caption.start < end else { return nil }
                    return .init(id: caption.id, start: caption.start, end: end, text: caption.text)
                }
                let output: [RecordingCaption]
                if project.timeline != nil, !sourceClips.isEmpty {
                    let targets = selected.map { [$0] } ?? sourceClips
                    output = targets.flatMap { clip in
                        bounded.compactMap { caption -> RecordingCaption? in
                            let start = max(caption.start, clip.sourceStart)
                            let end = min(caption.end, clip.sourceEnd)
                            guard start < end else { return nil }
                            return .init(start: clip.start + (start - clip.sourceStart) / clip.speed,
                                end: clip.start + (end - clip.sourceStart) / clip.speed, text: caption.text)
                        }
                    }
                } else { output = bounded }
                isBusy = false
                update { $0.captions = output; $0.edits.showCaptions = true }
            } catch {
                guard projectRevision == revision else { return }
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
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
        if let timeline = project.timeline {
            let captions = Dictionary(uniqueKeysWithValues: project.captions.map { ($0.id, $0) })
            let visible = Set(timeline.tracks.filter { !$0.isHidden }.map(\.id))
            return timeline.clips.compactMap { clip in
                guard visible.contains(clip.trackID), case let .caption(id) = clip.content,
                      let caption = captions[id] else { return nil }
                return RecordingCaption(start: clip.start, end: clip.end, text: caption.text)
            }.sorted { $0.start < $1.start }
        }
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

    private func clearProject() {
        projectRevision += 1
        if isBusy {
            operationTask?.cancel()
            operationTask = nil
            isBusy = false
        }
        previewTask?.cancel()
        player?.pause()
        timelinePlayer?.pause()
        if let timelineObserver { timelinePlayer?.removeTimeObserver(timelineObserver); self.timelineObserver = nil }
        timelinePlayer = nil
        if let playerObserver { player?.removeTimeObserver(playerObserver); self.playerObserver = nil }
        player = nil
        project = nil
        directory = nil
        preview = nil
        canvasPreview = nil
        multitrackPreviewScene = nil
        selectedTimelineClipID = nil
        selectedMediaAssetID = nil
        undoHistory.removeAll()
        redoHistory.removeAll()
        isDirty = false
        currentTime = 0
        playbackTime = 0
        errorMessage = nil
        dismissAIEdit()
        isShowingSourcePlayback = false
        isShowingTimelinePlayback = false
    }

    func install(_ project: ScreenRecordingProject, directory: URL) {
        clearProject()
        self.project = project
        self.directory = directory
        selectedTimelineClipID = timeline?.clips.first?.id
        if let asset = timeline?.assets.first {
            selectedMediaAssetID = asset.id
            if asset.kind != .image { installSourcePlayer(file: asset.file, directory: directory) }
        }
        seekTimeline(to: 0)
    }

    private func installSourcePlayer(file: String, directory: URL) {
        player?.pause()
        if let playerObserver { player?.removeTimeObserver(playerObserver); self.playerObserver = nil }
        guard let url = try? projectStore.mediaURL(file, in: directory) else { player = nil; return }
        let player = AVPlayer(url: url)
        self.player = player
        playerObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.isShowingSourcePlayback else { return }
                self.currentTime = time.seconds
                if player.rate == 0 { self.isShowingSourcePlayback = false; self.refreshPreview() }
            }
        }
    }

    func refreshPreview() {
        previewRevision += 1
        let revision = previewRevision
        previewTask?.cancel()
        guard let project, let directory else { preview = nil; canvasPreview = nil; return }
        if project.timeline != nil {
            let time = playbackTime
            previewTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let scene = try await exporter.multitrackPreview(project: project, directory: directory, time: time)
                    let image = try scene.image(project: project)
                    guard !Task.isCancelled, revision == previewRevision else { return }
                    multitrackPreviewScene = scene
                    canvasPreview = image
                    preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                } catch {
                    guard !Task.isCancelled, revision == previewRevision else { return }
                    if errorMessage == nil { errorMessage = error.localizedDescription }
                }
            }
            return
        }
        multitrackPreviewScene = nil
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
        isChoosingFile = false
        outputPanel?.delegate = nil
        outputPanel?.accessoryView = nil
        outputPanel = nil
        if let outputNotice { notices.remove(id: outputNotice.id) }
        outputNotice = nil
        operationTask?.cancel()
        previewTask?.cancel()
        transcriber.cancel()
        exporter.cancel()
        player?.pause()
        timelinePlayer?.pause()
        if let playerObserver { player?.removeTimeObserver(playerObserver); self.playerObserver = nil }
        if let timelineObserver { timelinePlayer?.removeTimeObserver(timelineObserver); self.timelineObserver = nil }
        player = nil
        timelinePlayer = nil
    }

}

private enum ScreenRecordingStudioError: LocalizedError {
    case missingAIModel
    var errorDescription: String? { AppLocalization.text("请先选择已配置的 AI 模型") }
}
