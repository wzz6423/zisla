import AVFoundation
import AudioToolbox
import CoreMedia

protocol RecordingVoiceMonitorOutput: AnyObject {
    func start(format: AVAudioFormat) throws
    func append(_ buffer: AVAudioPCMBuffer, completion: @escaping @Sendable () -> Void) throws
    func stop()
}

final class RecordingVoiceMonitor: @unchecked Sendable {
    var isEnabled = false {
        didSet { if !isEnabled { releaseOutput() } }
    }

    private final class Backlog: @unchecked Sendable {
        private let lock = NSLock()
        private var tokens: Set<UUID> = []

        func reserve() -> UUID? {
            lock.lock()
            defer { lock.unlock() }
            guard tokens.count < 4 else { return nil }
            let token = UUID()
            tokens.insert(token)
            return token
        }

        func complete(_ token: UUID) {
            lock.lock()
            tokens.remove(token)
            lock.unlock()
        }
    }

    private let makeOutput: () -> any RecordingVoiceMonitorOutput
    private var output: (any RecordingVoiceMonitorOutput)?
    private var format: AVAudioFormat?
    private var playbackFormat: AVAudioFormat?
    private var converter: AudioConverterRef?
    private var backlog = Backlog()

    init(makeOutput: @escaping () -> any RecordingVoiceMonitorOutput = { RecordingVoiceMonitorEngine() }) {
        self.makeOutput = makeOutput
    }

    deinit { releaseOutput() }

    func append(_ sample: CMSampleBuffer) throws {
        guard isEnabled, sample.numSamples > 0 else { return }
        guard sample.numSamples <= Int(Int32.max), let description = sample.formatDescription else {
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: description)
        guard sourceFormat.commonFormat != .otherFormat else { throw ScreenRecordingCaptureError.writerUnavailable }
        if format?.isEqual(sourceFormat) != true {
            releaseOutput()
            guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | sourceFormat.channelCount) else {
                throw ScreenRecordingCaptureError.writerUnavailable
            }
            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceFormat.sampleRate,
                interleaved: false, channelLayout: layout)
            var converter: AudioConverterRef?
            guard AudioConverterNew(sourceFormat.streamDescription, targetFormat.streamDescription, &converter) == noErr,
                  let converter else { throw ScreenRecordingCaptureError.writerUnavailable }
            self.converter = converter
            let output = makeOutput()
            do { try output.start(format: targetFormat) }
            catch { output.stop(); releaseOutput(); throw error }
            self.output = output
            format = sourceFormat
            playbackFormat = targetFormat
        }
        let backlog = backlog
        guard let token = backlog.reserve() else { return }
        do {
            let frames = AVAudioFrameCount(sample.numSamples)
            guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames),
                  let result = AVAudioPCMBuffer(pcmFormat: playbackFormat!, frameCapacity: frames) else {
                throw ScreenRecordingCaptureError.writerUnavailable
            }
            source.frameLength = frames
            result.frameLength = frames
            guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(sample.numSamples),
                into: source.mutableAudioBufferList) == noErr,
                  AudioConverterConvertComplexBuffer(converter!, frames, source.audioBufferList,
                result.mutableAudioBufferList) == noErr else { throw ScreenRecordingCaptureError.writerUnavailable }
            try output!.append(result) { backlog.complete(token) }
        } catch {
            backlog.complete(token)
            throw error
        }
    }

    func stop() {
        isEnabled = false
    }

    private func releaseOutput() {
        output?.stop()
        output = nil
        format = nil
        playbackFormat = nil
        if let converter { AudioConverterDispose(converter) }
        converter = nil
        backlog = Backlog()
    }
}

private final class RecordingVoiceMonitorEngine: RecordingVoiceMonitorOutput {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    func start(format: AVAudioFormat) throws {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
    }

    func append(_ buffer: AVAudioPCMBuffer, completion: @escaping @Sendable () -> Void) throws {
        // Playing before the output's first IO cycle raises an Objective-C exception.
        guard engine.isRunning, engine.outputNode.lastRenderTime != nil else {
            completion()
            return
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in completion() }
        if !player.isPlaying { player.play() }
    }

    func stop() {
        player.stop()
        engine.stop()
    }
}
