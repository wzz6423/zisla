import AppKit
import AVFoundation
import Combine
import ZislaKit
import Speech

/// Microphone and speech recognition permissions are requested only after the user explicitly taps; recorded audio is passed only to the system recognizer and is not written to Zisla state files.
@MainActor
final class VoiceInputController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPreparing = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorDescription: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var pendingStartID: UUID?
    private var recordingID: UUID?
    private var tapInstalled = false
    private var finalizationTask: Task<Void, Never>?
    private var authorizationPromptHost: NSWindow?

    var onTranscriptCompleted: ((String) -> Void)?

    func toggle() {
        if isRecording || isPreparing {
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
        requestPermissionsAndStart()
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
        clearRecordingResources()
    }

    private func requestPermissionsAndStart() {
        let startID = UUID()
        pendingStartID = startID
        isPreparing = true
        errorDescription = nil
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
                        with: "未获得语音识别权限。请在系统设置的“隐私与安全性 > 语音识别”中允许 zisla。"
                    )
                    return
                }
                self.requestMicrophoneAccess(startID: startID)
            }
        }
    }

    private func requestMicrophoneAccess(startID: UUID) {
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
                        with: "未获得麦克风权限。请在系统设置的“隐私与安全性 > 麦克风”中允许 zisla。"
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

    private func startRecording(startID: UUID) {
        guard pendingStartID == startID else { return }
        guard recognizer?.isAvailable == true else {
            finishPendingStart(with: "当前语音识别不可用")
            return
        }
        transcript = ""
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            finishPendingStart(with: "未检测到可用的麦克风输入")
            return
        }
        let recordingID = UUID()
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
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        tapInstalled = true
        do {
            engine.prepare()
            try engine.start()
            self.engine = engine
            self.request = request
            self.task = task
            self.recordingID = recordingID
            pendingStartID = nil
            isPreparing = false
            isRecording = true
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            request.endAudio()
            task?.cancel()
            finishPendingStart(with: error.localizedDescription)
        }
    }

    private func stopAudioInput(for recordingID: UUID) {
        guard self.recordingID == recordingID else { return }
        if tapInstalled {
            engine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine?.stop()
        request?.endAudio()
        isRecording = false
        finalizationTask?.cancel()
        finalizationTask = Task { [weak self] in
            // Server-side recognition needs a couple of seconds after endAudio() to return the final
            // transcription, which fixes punctuation and homophones; a shorter wait delivers the partial one.
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.finishRecording(recordingID: recordingID)
        }
    }

    private func finishRecording(recordingID: UUID) {
        guard self.recordingID == recordingID else { return }
        let completedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        clearRecordingResources()
        if !completedTranscript.isEmpty {
            onTranscriptCompleted?(completedTranscript)
        }
    }

    private func clearRecordingResources() {
        finalizationTask?.cancel()
        finalizationTask = nil
        if tapInstalled {
            engine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine?.stop()
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
        recordingID = nil
        isRecording = false
    }
}
