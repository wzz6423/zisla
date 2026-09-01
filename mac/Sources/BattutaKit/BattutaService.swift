import Foundation
import AVFAudio

/// 简化的 Battuta 服务，为 Zisla 提供键盘和鼠标音效功能
@MainActor
public final class BattutaService: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var errorMessage: String?

    private let audioEngine: KeyboardAudioEngine
    private let keyboardMonitor: KeyboardMonitor

    public init() {
        self.audioEngine = KeyboardAudioEngine()
        self.keyboardMonitor = KeyboardMonitor()
    }

    /// 启动键盘/鼠标监听和音频引擎
    public func start(
        keyboardEnabled: Bool,
        playsReleaseSound: Bool,
        pointerEnabled: Bool,
        playsPointerReleaseSound: Bool,
        pitchVariation: Bool,
        keyboardVolume: Double,
        pointerVolume: Double
    ) {
        let interest = KeyboardMonitor.EventInterest(
            keyboardPresses: keyboardEnabled,
            keyboardReleases: keyboardEnabled && playsReleaseSound,
            pointerPresses: pointerEnabled,
            pointerReleases: pointerEnabled && playsPointerReleaseSound
        )

        guard !interest.isEmpty else {
            stop()
            return
        }

        audioEngine.setKeyboardPlaybackGain(keyboardVolume)
        audioEngine.setPointerPlaybackGain(pointerVolume)

        let started = keyboardMonitor.start(interest: interest) { [weak self] event in
            guard let self else { return }
            self.handle(
                event,
                keyboardEnabled: keyboardEnabled,
                playsReleaseSound: playsReleaseSound,
                pointerEnabled: pointerEnabled,
                playsPointerReleaseSound: playsPointerReleaseSound,
                pitchVariation: pitchVariation,
                keyboardVolume: keyboardVolume,
                pointerVolume: pointerVolume
            )
        }

        if started {
            isRunning = true
            errorMessage = nil
        } else {
            isRunning = false
            errorMessage = "无法启动键盘监听，请检查输入监控权限"
        }
    }

    /// 停止监听
    public func stop() {
        keyboardMonitor.stop()
        isRunning = false
    }

    /// 加载键盘音色
    public func loadProfile(_ profileID: String) {
        if let profile = SwitchProfile(rawValue: profileID) {
            audioEngine.load(profile: profile)
        }
    }

    /// 加载鼠标音色
    public func loadPointerProfile(_ profileID: String) -> Bool {
        if let profile = PointerSoundProfile(rawValue: profileID) {
            return audioEngine.load(pointerProfile: profile)
        }
        return false
    }

    /// 预览按键音效
    public func previewKeySound(volume: Double, pitchVariation: Bool) {
        audioEngine.play(
            keyCode: 0,
            phase: .press,
            volume: volume,
            pitchVariation: pitchVariation
        )
        Task {
            try? await Task.sleep(for: .milliseconds(75))
            audioEngine.play(
                keyCode: 0,
                phase: .release,
                volume: volume,
                pitchVariation: pitchVariation
            )
        }
    }

    /// 预览鼠标音效
    public func previewPointerSound(volume: Double, pitchVariation: Bool) {
        audioEngine.play(
            pointerButton: .primary,
            phase: .press,
            volume: volume,
            pitchVariation: pitchVariation
        )
        Task {
            try? await Task.sleep(for: .milliseconds(75))
            audioEngine.play(
                pointerButton: .primary,
                phase: .release,
                volume: volume,
                pitchVariation: pitchVariation
            )
        }
    }

    private func handle(
        _ event: GlobalInputEvent,
        keyboardEnabled: Bool,
        playsReleaseSound: Bool,
        pointerEnabled: Bool,
        playsPointerReleaseSound: Bool,
        pitchVariation: Bool,
        keyboardVolume: Double,
        pointerVolume: Double
    ) {
        switch event {
        case .keyboard(let keyboardEvent):
            guard keyboardEnabled else { return }
            let shouldPlay = !(keyboardEvent.kind == .keyDown && keyboardEvent.isRepeat)
                && !(keyboardEvent.kind == .keyUp && !playsReleaseSound)

            if shouldPlay {
                let phase: KeySoundPhase = keyboardEvent.kind == .keyDown ? .press : .release
                audioEngine.play(
                    keyCode: keyboardEvent.keyCode,
                    phase: phase,
                    volume: keyboardVolume,
                    pitchVariation: pitchVariation
                )
            }

        case .pointer(let pointerEvent):
            guard pointerEnabled else { return }
            if pointerEvent.phase == .release && !playsPointerReleaseSound { return }

            audioEngine.play(
                pointerButton: pointerEvent.button,
                phase: pointerEvent.phase,
                volume: pointerVolume,
                pitchVariation: pitchVariation
            )
        }
    }
}
