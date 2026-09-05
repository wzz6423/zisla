import AppKit
@preconcurrency import AVFoundation
import Combine
import CoreMedia
import ZislaCore
import ZislaKit
import Speech

/// Microphone and speech recognition permissions are requested only after the user explicitly taps.
@MainActor
final class VoiceInputController: ObservableObject {
    private static let maximumSystemDictationFormatRetries = 2

    @Published private(set) var isRecording = false
    @Published private(set) var isPreparing = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorDescription: String?
    /// Whether the recognition service is still processing a final result after recording has stopped.
    private var isFinalizingTranscript = false

    /// Drives the in-island recording surface. Presentation must not wait for `isRecording`:
    /// permission round-trips and the dictation engine's first-run setup take up to a second, so the
    /// surface would appear long after the keypress that asked for it.
    var isCapturingInput: Bool { isPreparing || isRecording }

    /// `isCapturingInput` as a publisher for the panel-sizing pipeline. Both assignments that hand
    /// preparation over to recording keep the combined value true, so it never dips mid-take.
    var isCapturingInputPublisher: AnyPublisher<Bool, Never> {
        $isPreparing
            .combineLatest($isRecording)
            .map { $0 || $1 }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private var recognizer: SFSpeechRecognizer?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var pendingStartID: UUID?
    private var recordingID: UUID?
    private var recordingStartedAt: Date?
    private var recordingFileURL: URL?
    private var recordingFile: AVAudioFile?
    private var tapInstalled = false
    private var finalizationTask: Task<Void, Never>?
    private var authorizationPromptHost: NSWindow?
    private var contextualStrings: [String] = []
    private var systemDictationSegments: [DictationTranscriptSegment] = []
    private var systemDictationSession: (any DictationSession)?

    var onRecordingWillStart: (() -> Void)?
    var onTranscriptCompleted: ((VoiceRecordingResult) -> Void)?

    func setContextualStrings(_ strings: [String]) {
        var seen = Set<String>()
        contextualStrings = strings.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func toggle() {
        if isRecording || isPreparing || isFinalizingTranscript {
            stop()
        } else {
            start()
        }
    }

    /// Push-to-talk mode: recording starts when the shortcut key is pressed.
    func start() {
        guard !isRecording, !isPreparing else { return }
        // The previous take may still be waiting for its final result; deliver it now instead of
        // swallowing this keypress for the whole finalization window.
        if let recordingID { finishRecording(recordingID: recordingID) }
        let startID = UUID()
        pendingStartID = startID
        isPreparing = true
        onRecordingWillStart?()
        requestPermissionsAndStart(startID: startID)
    }

    func stop() {
        pendingStartID = nil
        isPreparing = false
        dismissAuthorizationPromptHost()
        guard let recordingID, isRecording else { return }
        stopAudioInput(for: recordingID)
    }

    func cancel() {
        pendingStartID = nil
        isPreparing = false
        dismissAuthorizationPromptHost()
        clearRecordingResources(deleteAudioFile: true)
    }

    private func requestPermissionsAndStart(startID: UUID) {
        guard pendingStartID == startID else { return }
        errorDescription = nil
        // The island surface is already on screen at this point, and the recognizers only reset the
        // transcript once they are live — leaving the previous take's text on display until then.
        transcript = ""
        // Already-granted permissions still cost two async TCC round-trips before capture can begin,
        // which delays the first words of a take; go straight to the microphone check instead.
        guard SFSpeechRecognizer.authorizationStatus() != .authorized else {
            requestMicrophoneAccess(startID: startID)
            return
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            presentAuthorizationPromptHost()
        }
        Self.requestSpeechAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.pendingStartID == startID else { return }
                self.dismissAuthorizationPromptHost()
                guard status == .authorized else {
                    self.finishPendingStart(
                        with: AppLocalization.text("未获得语音识别权限。请在系统设置的“隐私与安全性 > 语音识别”中允许 zisla。")
                    )
                    return
                }
                self.requestMicrophoneAccess(startID: startID)
            }
        }
    }

    private func requestMicrophoneAccess(startID: UUID) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) != .authorized else {
            startRecording(startID: startID)
            return
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            presentAuthorizationPromptHost()
        }
        Self.requestAudioAccess { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.pendingStartID == startID else { return }
                self.dismissAuthorizationPromptHost()
                guard granted else {
                    self.finishPendingStart(
                        with: AppLocalization.text("未获得麦克风权限。请在系统设置的“隐私与安全性 > 麦克风”中允许 zisla。")
                    )
                    return
                }
                self.startRecording(startID: startID)
            }
        }
    }

    private func finishPendingStart(with errorDescription: String) {
        pendingStartID = nil
        isPreparing = false
        dismissAuthorizationPromptHost()
        self.errorDescription = errorDescription
    }

    private func presentAuthorizationPromptHost() {
        dismissAuthorizationPromptHost()
        authorizationPromptHost = WindowPlacement.authorizationPromptHost()
    }

    private func dismissAuthorizationPromptHost() {
        authorizationPromptHost?.orderOut(nil)
        authorizationPromptHost?.close()
        authorizationPromptHost = nil
    }

    // System authorization callbacks may fire on any queue and cannot inherit the controller's main-actor isolation.
    nonisolated private static func requestSpeechAuthorization(
        _ completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization(completion)
    }

    nonisolated private static func requestAudioAccess(
        _ completion: @escaping @Sendable (Bool) -> Void
    ) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    nonisolated static func makeAudioTapHandler(
        recordingFile: AVAudioFile,
        recordingID: UUID,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onWriteFailure: @escaping @Sendable (UUID, Error) -> Void
    ) -> AVAudioNodeTapBlock {
        // AVAudioEngine invokes tap blocks on a realtime queue, outside MainActor isolation.
        return { buffer, _ in
            onBuffer(buffer)
            do {
                try recordingFile.write(from: buffer)
            } catch {
                onWriteFailure(recordingID, error)
            }
        }
    }

    nonisolated static func audioTapFormatNeedsRefresh(
        preparedFormat: AVAudioFormat,
        liveFormat: AVAudioFormat
    ) -> Bool {
        preparedFormat.sampleRate != liveFormat.sampleRate
            || preparedFormat.channelCount != liveFormat.channelCount
            || preparedFormat.commonFormat != liveFormat.commonFormat
            || preparedFormat.isInterleaved != liveFormat.isInterleaved
    }

    nonisolated private static func installAudioTap(
        on input: AVAudioInputNode,
        recordingFile: AVAudioFile,
        recordingID: UUID,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onWriteFailure: @escaping @Sendable (UUID, Error) -> Void
    ) {
        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            // The input device can change while dictation prepares asynchronously. Passing a cached
            // format here makes AVFAudio raise an Objective-C exception instead of returning an error.
            format: nil,
            block: makeAudioTapHandler(
                recordingFile: recordingFile,
                recordingID: recordingID,
                onBuffer: onBuffer,
                onWriteFailure: onWriteFailure
            )
        )
    }

    private func startRecording(startID: UUID) {
        guard pendingStartID == startID else { return }
        if #available(macOS 26.0, *) {
            startSystemDictationRecording(startID: startID)
        } else {
            startLegacyRecording(startID: startID)
        }
    }

    @available(macOS 26.0, *)
    private func startSystemDictationRecording(startID: UUID, formatRetryCount: Int = 0) {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let preparedFormat = input.outputFormat(forBus: 0)
        guard preparedFormat.sampleRate > 0, preparedFormat.channelCount > 0 else {
            finishPendingStart(with: AppLocalization.text("未检测到可用的麦克风输入"))
            return
        }

        let recordingID = UUID()
        let contextualStrings = self.contextualStrings
        Task { [weak self] in
            do {
                let session = try await SystemDictationSession(
                    sourceFormat: preparedFormat,
                    contextualStrings: contextualStrings,
                    onResult: { [weak self] range, text in
                        Task { @MainActor [weak self] in
                            self?.receiveSystemDictationResult(
                                text,
                                range: range,
                                recordingID: recordingID
                            )
                        }
                    },
                    onError: { [weak self] error in
                        Task { @MainActor [weak self] in
                            self?.failSystemDictation(recordingID: recordingID, error: error)
                        }
                    }
                )
                guard let self, self.pendingStartID == startID else {
                    session.cancel()
                    return
                }
                self.beginSystemDictationRecording(
                    startID: startID,
                    recordingID: recordingID,
                    engine: engine,
                    input: input,
                    preparedFormat: preparedFormat,
                    formatRetryCount: formatRetryCount,
                    session: session
                )
            } catch {
                guard let self, self.pendingStartID == startID else { return }
                self.startLegacyRecording(startID: startID)
            }
        }
    }

    @available(macOS 26.0, *)
    private func beginSystemDictationRecording(
        startID: UUID,
        recordingID: UUID,
        engine: AVAudioEngine,
        input: AVAudioInputNode,
        preparedFormat: AVAudioFormat,
        formatRetryCount: Int,
        session: SystemDictationSession
    ) {
        guard pendingStartID == startID else {
            session.cancel()
            return
        }
        let liveFormat = input.outputFormat(forBus: 0)
        guard liveFormat.sampleRate > 0, liveFormat.channelCount > 0 else {
            session.cancel()
            finishPendingStart(with: AppLocalization.text("未检测到可用的麦克风输入"))
            return
        }
        if Self.audioTapFormatNeedsRefresh(
            preparedFormat: preparedFormat,
            liveFormat: liveFormat
        ) {
            session.cancel()
            if formatRetryCount < Self.maximumSystemDictationFormatRetries {
                startSystemDictationRecording(
                    startID: startID,
                    formatRetryCount: formatRetryCount + 1
                )
            } else {
                startLegacyRecording(startID: startID)
            }
            return
        }
        let recordingFile: AVAudioFile
        let recordingFileURL: URL
        do {
            (recordingFileURL, recordingFile) = try makeRecordingFile(
                recordingID: recordingID,
                format: liveFormat
            )
        } catch {
            session.cancel()
            finishPendingStart(with: AppLocalization.text("无法保存录音：%@", error.localizedDescription))
            return
        }

        transcript = ""
        systemDictationSegments = []
        self.engine = engine
        self.recordingID = recordingID
        self.recordingStartedAt = Date()
        self.recordingFileURL = recordingFileURL
        self.recordingFile = recordingFile
        systemDictationSession = session
        Self.installAudioTap(
            on: input,
            recordingFile: recordingFile,
            recordingID: recordingID,
            onBuffer: { session.append($0) }
        ) { [weak self] recordingID, error in
            Task { @MainActor [weak self] in
                self?.failRecordingWrite(recordingID: recordingID, error: error)
            }
        }
        tapInstalled = true
        do {
            engine.prepare()
            try engine.start()
            finishPreparingIntoRecording()
        } catch {
            clearRecordingResources(deleteAudioFile: true)
            finishPendingStart(with: error.localizedDescription)
        }
    }

    private func startLegacyRecording(startID: UUID) {
        guard pendingStartID == startID else { return }
        let recognizer = SFSpeechRecognizer(locale: Locale.autoupdatingCurrent)
        guard recognizer?.isAvailable == true else {
            finishPendingStart(with: AppLocalization.text("当前语音识别不可用"))
            return
        }

        transcript = ""
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.contextualStrings = contextualStrings
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            finishPendingStart(with: AppLocalization.text("未检测到可用的麦克风输入"))
            return
        }
        let recordingID = UUID()
        let recordingFile: AVAudioFile
        let recordingFileURL: URL
        do {
            (recordingFileURL, recordingFile) = try makeRecordingFile(
                recordingID: recordingID,
                format: format
            )
        } catch {
            finishPendingStart(with: AppLocalization.text("无法保存录音：%@", error.localizedDescription))
            return
        }
        let task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.recordingID == recordingID else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finishRecording(recordingID: recordingID)
                        return
                    }
                }
                if let error {
                    // Once endAudio() has been called the recognizer reports end-of-stream as an error;
                    // only a failure that interrupts an active take is worth surfacing.
                    if self.isRecording {
                        self.errorDescription = error.localizedDescription
                    }
                    self.finishRecording(recordingID: recordingID)
                }
            }
        }
        let requestAppender = LegacyRecognitionRequestAppender(request: request)
        Self.installAudioTap(
            on: input,
            recordingFile: recordingFile,
            recordingID: recordingID,
            onBuffer: { requestAppender.append($0) }
        ) { [weak self] recordingID, error in
            Task { @MainActor [weak self] in
                self?.failRecordingWrite(recordingID: recordingID, error: error)
            }
        }
        tapInstalled = true
        self.engine = engine
        self.recognizer = recognizer
        self.request = request
        self.task = task
        self.recordingID = recordingID
        self.recordingStartedAt = Date()
        self.recordingFileURL = recordingFileURL
        self.recordingFile = recordingFile
        do {
            engine.prepare()
            try engine.start()
            finishPreparingIntoRecording()
        } catch {
            clearRecordingResources(deleteAudioFile: true)
            finishPendingStart(with: error.localizedDescription)
        }
    }

    /// Hands preparation over to a live take. `isRecording` rises before `isPreparing` clears so
    /// `isCapturingInput` never dips to false in between, which would tear the island surface down
    /// and rebuild it in the middle of a take.
    private func finishPreparingIntoRecording() {
        pendingStartID = nil
        isRecording = true
        isPreparing = false
    }

    private func makeRecordingFile(
        recordingID: UUID,
        format: AVAudioFormat
    ) throws -> (URL, AVAudioFile) {
        let url = AppPaths.voiceRecordings
            .appendingPathComponent("\(recordingID.uuidString).caf", isDirectory: false)
        do {
            try FileManager.default.createDirectory(
                at: AppPaths.voiceRecordings,
                withIntermediateDirectories: true
            )
            return (url, try AVAudioFile(forWriting: url, settings: format.settings))
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func receiveSystemDictationResult(
        _ text: String,
        range: CMTimeRange,
        recordingID: UUID
    ) {
        guard self.recordingID == recordingID else { return }
        // Progressive dictation revises earlier time ranges, so replace overlaps before rendering.
        systemDictationSegments.removeAll { segment in
            CMTimeCompare(CMTimeRangeGetEnd(segment.range), range.start) > 0
                && CMTimeCompare(CMTimeRangeGetEnd(range), segment.range.start) > 0
        }
        systemDictationSegments.append(.init(range: range, text: text))
        systemDictationSegments.sort {
            CMTimeCompare($0.range.start, $1.range.start) < 0
        }
        transcript = systemDictationSegments.map(\.text).joined()
    }

    private func failSystemDictation(recordingID: UUID, error: Error) {
        guard self.recordingID == recordingID else { return }
        if isRecording {
            errorDescription = error.localizedDescription
        }
        finishRecording(recordingID: recordingID)
    }

    private func stopAudioInput(for recordingID: UUID) {
        guard self.recordingID == recordingID else { return }
        stopAudioCapture()
        isFinalizingTranscript = true
        finalizationTask?.cancel()
        if let session = systemDictationSession {
            finalizationTask = Task { [weak self, session] in
                do {
                    try await session.finalizeAndFinish()
                    guard !Task.isCancelled else { return }
                    self?.finishRecording(recordingID: recordingID)
                } catch is CancellationError {
                    return
                } catch {
                    self?.failSystemDictation(recordingID: recordingID, error: error)
                }
            }
            return
        }
        finalizationTask = Task { [weak self] in
            // Server-side recognition needs a couple of seconds after endAudio() to return the final
            // transcription, which fixes punctuation and homophones; a shorter wait delivers the partial one.
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.finishRecording(recordingID: recordingID)
        }
    }

    private func stopAudioCapture() {
        guard tapInstalled || isRecording else { return }
        if tapInstalled {
            engine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine?.stop()
        request?.endAudio()
        systemDictationSession?.finishInput()
        isRecording = false
    }

    private func finishRecording(recordingID: UUID) {
        guard self.recordingID == recordingID else { return }
        stopAudioCapture()
        isFinalizingTranscript = false
        let completedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt = recordingStartedAt ?? Date()
        let fallbackDuration = max(0, Date().timeIntervalSince(createdAt))
        let recordedDuration = recordingFile.map {
            guard $0.fileFormat.sampleRate > 0 else { return fallbackDuration }
            return Double($0.length) / $0.fileFormat.sampleRate
        } ?? fallbackDuration
        guard let recordingFileURL else {
            clearRecordingResources(deleteAudioFile: true)
            errorDescription = AppLocalization.text("录音文件未能保存")
            return
        }
        clearRecordingResources(deleteAudioFile: false)
        onTranscriptCompleted?(VoiceRecordingResult(
            id: recordingID,
            audioFileURL: recordingFileURL,
            transcript: completedTranscript,
            duration: recordedDuration,
            createdAt: createdAt
        ))
    }

    private func failRecordingWrite(recordingID: UUID, error: Error) {
        guard self.recordingID == recordingID else { return }
        errorDescription = AppLocalization.text("无法保存录音：%@", error.localizedDescription)
        clearRecordingResources(deleteAudioFile: true)
    }

    private func clearRecordingResources(deleteAudioFile: Bool) {
        let fileURL = recordingFileURL
        finalizationTask?.cancel()
        finalizationTask = nil
        stopAudioCapture()
        task?.cancel()
        systemDictationSession?.cancel()
        systemDictationSession = nil
        engine = nil
        recognizer = nil
        request = nil
        task = nil
        recordingFile = nil
        recordingFileURL = nil
        recordingStartedAt = nil
        recordingID = nil
        isRecording = false
        isFinalizingTranscript = false
        systemDictationSegments = []
        if deleteAudioFile, let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}

private struct DictationTranscriptSegment {
    let range: CMTimeRange
    let text: String
}

private protocol DictationSession: AnyObject, Sendable {
    func finishInput()
    func finalizeAndFinish() async throws
    func cancel()
}

private final class LegacyRecognitionRequestAppender: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }
}

@available(macOS 26.0, *)
private final class SystemDictationSession: DictationSession, @unchecked Sendable {
    private enum SessionError: Error {
        case unsupportedLocale
        case incompatibleAudioFormat
        case audioConverterUnavailable
        case audioConversionFailed
    }

    private let analyzer: SpeechAnalyzer
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let onError: @Sendable (Error) -> Void
    private var resultsTask: Task<Void, Never>?

    init(
        sourceFormat: AVAudioFormat,
        contextualStrings: [String],
        onResult: @escaping @Sendable (CMTimeRange, String) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async throws {
        guard let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: Locale.autoupdatingCurrent
        ) else {
            throw SessionError.unsupportedLocale
        }

        let transcriber = DictationTranscriber(
            locale: locale,
            preset: .progressiveShortDictation
        )
        let modules: [any SpeechModule] = [transcriber]
        guard let outputFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules,
            considering: sourceFormat
        ) else {
            throw SessionError.incompatibleAudioFormat
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
            throw SessionError.audioConverterUnavailable
        }

        let stream = AsyncStream.makeStream(of: AnalyzerInput.self)
        let context = AnalysisContext()
        context.contextualStrings[.general] = contextualStrings
        let analyzer = SpeechAnalyzer(modules: modules)
        try await analyzer.setContext(context)
        try await analyzer.prepareToAnalyze(in: outputFormat)
        try await analyzer.start(inputSequence: stream.stream)

        self.analyzer = analyzer
        inputContinuation = stream.continuation
        self.converter = converter
        self.outputFormat = outputFormat
        self.onError = onError
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { return }
                    onResult(result.range, String(result.text.characters))
                }
            } catch is CancellationError {
                return
            } catch {
                onError(error)
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        do {
            let outputFrameCapacity = AVAudioFrameCount(max(
                1,
                Int(ceil(Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate)) + 1
            ))
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCapacity
            ) else {
                throw SessionError.audioConversionFailed
            }

            let inputProvider = AudioBufferInputProvider(buffer: buffer)
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
                guard let inputBuffer = inputProvider.nextBuffer() else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                inputStatus.pointee = .haveData
                return inputBuffer
            }
            if status == .error {
                throw conversionError ?? SessionError.audioConversionFailed
            }
            if outputBuffer.frameLength > 0 {
                inputContinuation.yield(AnalyzerInput(buffer: outputBuffer))
            }
        } catch {
            onError(error)
        }
    }

    func finishInput() {
        inputContinuation.finish()
    }

    func finalizeAndFinish() async throws {
        inputContinuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
    }

    func cancel() {
        inputContinuation.finish()
        resultsTask?.cancel()
        Task { [analyzer] in
            await analyzer.cancelAndFinishNow()
        }
    }
}

private final class AudioBufferInputProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func nextBuffer() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        defer { buffer = nil }
        return buffer
    }
}
