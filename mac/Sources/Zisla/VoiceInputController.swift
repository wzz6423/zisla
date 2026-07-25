import AppKit
import AVFoundation
import Combine
import ZislaKit
import Speech

/// 用户显式点击后才申请麦克风与语音识别权限；录音内容只交给系统识别器，不写入 Zisla 状态文件。
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
    private var authorizationPromptHost: NSWindow?

    func toggle() {
        if isRecording || isPreparing {
            stop()
        } else {
            requestPermissionsAndStart()
        }
    }

    /// 按住说话模式：按下快捷键时开始录音。
    func start() {
        guard !isRecording, !isPreparing else { return }
        requestPermissionsAndStart()
    }

    func stop() {
        pendingStartID = nil
        isPreparing = false
        dismissAuthorizationPromptHost()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
        isRecording = false
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
                    self.finishPendingStart(with: "未获得语音识别权限")
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
                    self.finishPendingStart(with: "未获得麦克风权限")
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

    // 系统授权完成回调可能在任意队列执行，不能继承控制器的主 actor 隔离。
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
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
            self.engine = engine
            self.request = request
            pendingStartID = nil
            isPreparing = false
            isRecording = true
            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result { self?.transcript = result.bestTranscription.formattedString }
                    if let error { self?.errorDescription = error.localizedDescription }
                    if error != nil || result?.isFinal == true { self?.stop() }
                }
            }
        } catch {
            input.removeTap(onBus: 0)
            finishPendingStart(with: error.localizedDescription)
        }
    }
}
