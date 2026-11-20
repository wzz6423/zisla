#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
AUDIO_SOURCE="${1:-$ROOT/Sources/KeyboardKit/KeyboardAudioEngine.swift}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-keyboard-playback-tests.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

# Run the complete production class with native offline audio and isolated callback faults.
python3 - "$AUDIO_SOURCE" "$ROOT" "$TEST_ROOT" <<'PYTHON_SETUP'
from pathlib import Path
import json
import shutil
import sys

source, module, root = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
shutil.copyfile(source, root / 'KeyboardAudioEngine.swift')
for name in ['KeySound', 'SwitchProfile', 'SoundPack', 'SoundPackResolver', 'KeyboardLayout']:
    shutil.copyfile(module / 'Sources/KeyboardKit' / (name + '.swift'), root / (name + '.swift'))
fixture = root / 'Fixtures.bundle'
fixture.mkdir()
shutil.copytree(module / 'Resources/Keyboard/Audio/holypanda', fixture / 'Keyboard/Audio/holypanda')
(fixture / 'Info.plist').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.zisla.keyboard-playback-tests</string><key>CFBundleVersion</key><string>1</string></dict></plist>')
(root / 'Support.swift').write_text('import Foundation\nextension Bundle { static let module = Bundle(path: '
    + json.dumps(str(fixture)) + ''')! }
enum L10n {
    static func tr(_ key: String) -> String { key }
    static func format(_ format: String, _ arguments: CVarArg...) -> String {
        String(format: format, arguments: arguments)
    }
}
extension String { var localized: String { self } }
''')
(root / 'Probe.swift').write_text(r'''import AVFAudio
import Darwin
import Foundation
import ObjectiveC

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(87)
    }
}

final class CompletionBox: @unchecked Sendable {
    let call: (AVAudioPlayerNodeCompletionCallbackType) -> Void
    init(_ call: @escaping (AVAudioPlayerNodeCompletionCallbackType) -> Void) { self.call = call }
}

final class RenderFault: @unchecked Sendable {
    static let shared = RenderFault()
    var missing = false
    var completions: [CompletionBox] = []
}

extension AVAudioNode {
    @objc func zisla_renderTime() -> AVAudioTime? {
        if self is AVAudioOutputNode, RenderFault.shared.missing { return nil }
        return zisla_renderTime()
    }
}

extension AVAudioPlayerNode {
    @objc func zisla_schedule(
        _ buffer: AVAudioPCMBuffer, at when: AVAudioTime?, options: AVAudioPlayerNodeBufferOptions,
        completionCallbackType: AVAudioPlayerNodeCompletionCallbackType,
        completionHandler: ((AVAudioPlayerNodeCompletionCallbackType) -> Void)?
    ) {
        if let completionHandler { RenderFault.shared.completions.append(CompletionBox(completionHandler)) }
        zisla_schedule(buffer, at: when, options: options,
                       completionCallbackType: completionCallbackType, completionHandler: nil)
    }
}

final class OfflineEngine: AVAudioEngine, @unchecked Sendable {
    var changedChannels: AVAudioChannelCount?
    var failStart = false
    var onPause: (@Sendable () -> Void)?
    private var didEnableOffline = false
    var players: [AVAudioPlayerNode] = []
    var speeds: [AVAudioUnitVarispeed] = []
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

    override func attach(_ node: AVAudioNode) {
        super.attach(node)
        if let player = node as? AVAudioPlayerNode { players.append(player) }
        if let speed = node as? AVAudioUnitVarispeed { speeds.append(speed) }
    }
    override func prepare() {
        if !didEnableOffline {
            try! enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
            didEnableOffline = true
        }
        super.prepare()
    }
    override func start() throws {
        if failStart { throw NSError(domain: "ZislaAudioFault", code: 1) }
        if let channels = changedChannels {
            super.stop()
            disableManualRenderingMode()
            let changed = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: channels)!
            for index in players.indices {
                super.connect(speeds[index], to: mainMixerNode, format: changed)
                super.connect(players[index], to: speeds[index], format: changed)
            }
            try enableManualRenderingMode(.offline, format: changed, maximumFrameCount: 512)
        }
        try super.start()
    }
    override func pause() {
        super.pause()
        onPause?()
    }
    func restoreFormat() throws {
        super.stop()
        disableManualRenderingMode()
        changedChannels = nil
        for index in players.indices {
            super.connect(players[index], to: speeds[index], format: format)
            super.connect(speeds[index], to: mainMixerNode, format: format)
        }
        try enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
    }
    func render(quanta: Int = 64) throws -> Float {
        let buffer = AVAudioPCMBuffer(pcmFormat: manualRenderingFormat, frameCapacity: 512)!
        var peak: Float = 0
        for _ in 0..<quanta {
            let status = try renderOffline(512, to: buffer)
            require(status == .success, "Offline rendering must succeed")
            if let samples = buffer.floatChannelData {
                for channel in 0..<Int(buffer.format.channelCount) {
                    for frame in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[channel][frame])) }
                }
            }
        }
        return peak
    }
    func finish() {
        for player in players { player.stop() }
        super.stop()
    }
}

@main struct RegressionHarness {
    @MainActor static func main() async throws {
        alarm(20)
        NSSetUncaughtExceptionHandler { exception in
            FileHandle.standardError.write(Data("\(exception.name.rawValue): \(exception.reason ?? "")\n".utf8))
            exit(86)
        }
        guard let originalRender = class_getInstanceMethod(AVAudioNode.self, #selector(getter: AVAudioNode.lastRenderTime)),
              let injectedRender = class_getInstanceMethod(AVAudioNode.self, #selector(AVAudioNode.zisla_renderTime)) else {
            fatalError("Missing render time injection method")
        }
        guard let originalSchedule = class_getInstanceMethod(AVAudioPlayerNode.self, #selector(AVAudioPlayerNode.scheduleBuffer(_:at:options:completionCallbackType:completionHandler:))),
              let injectedSchedule = class_getInstanceMethod(AVAudioPlayerNode.self, #selector(AVAudioPlayerNode.zisla_schedule(_:at:options:completionCallbackType:completionHandler:))) else {
            fatalError("Missing native scheduling transport")
        }
        method_exchangeImplementations(originalRender, injectedRender)
        method_exchangeImplementations(originalSchedule, injectedSchedule)
        defer {
            method_exchangeImplementations(originalRender, injectedRender)
            method_exchangeImplementations(originalSchedule, injectedSchedule)
        }
        let mode = CommandLine.arguments.dropFirst().first ?? "--all"
        if mode == "--native-control" {
            let native = OfflineEngine()
            defer { native.finish() }
            let engine = KeyboardAudioEngine(voiceCount: 1, makeEngine: { native })
            require(engine.load(profile: .holyPanda), "Built-in keyboard fixture must load")
            engine.play(keyCode: 0, phase: .press, volume: 0.5, pitchVariation: false)
            native.stop()
            native.changedChannels = 2
            try native.start()
            let mono = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: 1)!
            buffer.frameLength = 1
            buffer.floatChannelData![0][0] = 0
            print("CONTROL: running=\(native.isRunning), renderTime=\(native.outputNode.lastRenderTime != nil), playerChannels=\(native.players[0].outputFormat(forBus: 0).channelCount), bufferChannels=\(buffer.format.channelCount)")
            native.players[0].scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in }
            fatalError("The native channel mismatch control must raise")
        }
        try await normalAndIdleRecovery()
        try await rejectedStartupAndRecovery()
        try await mismatchAndRecovery()
        try await failedStartAndRecovery()
        try await staleAndRepeatedCompletion()
        try await releaseAfterPendingPlayback()
        print("PASS: production keyboard playback covers first key, idle recovery, render and format faults, startup failure, stale completion, and cleanup")
    }

    @MainActor static func normalAndIdleRecovery() async throws {
        var creations = 0
        let engine = KeyboardAudioEngine(voiceCount: 1, makeEngine: { creations += 1; return OfflineEngine() })
        require(engine.load(profile: .holyPanda), "Built-in keyboard fixture must load")
        for gain: Double in [0, -1, .nan, .infinity] {
            engine.play(keyCode: 0, phase: .press, volume: gain, pitchVariation: false)
        }
        require(creations == 0, "Silent and invalid requests must not create an audio engine")
        let native = OfflineEngine()
        defer { native.finish() }
        let keyboard = KeyboardAudioEngine(voiceCount: 1, makeEngine: { native })
        require(keyboard.load(profile: .holyPanda), "Built-in keyboard fixture must load")
        keyboard.play(keyCode: 0, phase: .press, volume: 0.5, pitchVariation: false)
        require(native.players[0].isPlaying, "The first ready key must play immediately")
        require(try! native.render() > 0, "The first key must render non-silent PCM")
        await fire(RenderFault.shared.completions.last!)
        await drainMainQueue()
        await waitForPause(native, "Finished voices must pause the idle engine")
        keyboard.play(keyCode: 0, phase: .press, volume: 0.5, pitchVariation: false)
        require(native.isRunning, "A later key must resume the idle engine")
        require(try! native.render() > 0, "The first key after idle pause must render PCM")
        print("PASS: first key, silent input, idle pause, and resume")
    }

    @MainActor static func rejectedStartupAndRecovery() async throws {
        let native = OfflineEngine()
        defer { RenderFault.shared.missing = false; native.finish() }
        let engine = KeyboardAudioEngine(voiceCount: 1, makeEngine: { native })
        require(engine.load(profile: .holyPanda), "Built-in keyboard fixture must load")
        RenderFault.shared.missing = true
        let pendingCompletions = RenderFault.shared.completions.count
        engine.play(keyCode: 0, phase: .press, volume: 0.5, pitchVariation: true)
        engine.play(keyCode: 0, phase: .press, volume: 0.5, pitchVariation: true)
        require(!native.players[0].isPlaying, "Missing IO render cycle must not start playback")
        require(RenderFault.shared.completions.count == pendingCompletions, "Rejected playback must not enqueue a native buffer")
        let volume = native.players[0].volume
        let rate = native.speeds[0].rate
        engine.setKeyboardPlaybackGain(0.2)
        require(native.players[0].volume == volume, "Rejected playback must not mark a voice active")
        require(volume == 1 && rate == 1, "Rejected startup must restore the previous gain and rate")
        await waitForPause(native, "Rejected playback must eventually pause its newly started engine")
        RenderFault.shared.missing = false
        engine.play(keyCode: 0, phase: .press, volume: 0.5, pitchVariation: false)
        require(try! native.render() > 0, "A ready key after rejection must render PCM")
        print("PASS: missing IO render cycle, rollback, idle cleanup, and recovery")
    }

    @MainActor static func mismatchAndRecovery() async throws {
        for channels: AVAudioChannelCount in [2, 1] {
            let native = OfflineEngine()
            defer { native.finish() }
            let engine = KeyboardAudioEngine(voiceCount: 1, makeEngine: { native })
            require(engine.load(profile: .holyPanda), "Built-in keyboard fixture must load")
            native.changedChannels = channels
            let pendingCompletions = RenderFault.shared.completions.count
            engine.play(keyCode: 0, phase: .press, volume: 0.5, pitchVariation: false)
            require(!native.players[0].isPlaying, "A mismatched rate or channel layout must not play")
            require(RenderFault.shared.completions.count == pendingCompletions, "Mismatched playback must not enqueue a native buffer")
            require(try! native.render(quanta: 2) == 0, "Rejected playback must not queue audible PCM")
            require(native.players[0].volume == 1 && native.speeds[0].rate == 1, "Format rejection must restore voice controls")
            try native.restoreFormat()
            NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: native)
            await drainMainQueue()
            engine.play(keyCode: 0, phase: .press, volume: 0.5, pitchVariation: false)
            require(try! native.render() > 0, "A restored device format must render the next key")
        }
        print("PASS: native rate/channel mismatch is rejected and device configuration recovers")
    }

    @MainActor static func failedStartAndRecovery() async throws {
        let native = OfflineEngine()
        defer { native.finish() }
        let engine = KeyboardAudioEngine(voiceCount: 1, makeEngine: { native })
        require(engine.load(profile: .holyPanda), "Built-in keyboard fixture must load")
        native.failStart = true
        let pendingCompletions = RenderFault.shared.completions.count
        engine.play(keyCode: 0, phase: .press, volume: 0.5, pitchVariation: false)
        require(engine.engineError != nil, "Startup errors must remain observable")
        require(native.players[0].volume == 1 && native.speeds[0].rate == 1, "Failed startup must restore voice controls")
        require(!native.players[0].isPlaying && !native.isRunning, "Failed startup must not begin playback")
        require(RenderFault.shared.completions.count == pendingCompletions, "Failed startup must not enqueue a native buffer")
        native.failStart = false
        engine.play(keyCode: 0, phase: .press, volume: 0.5, pitchVariation: false)
        require(engine.engineError == nil, "A successful retry must clear the startup error")
        require(try! native.render() > 0, "A successful retry must render the next key")
        print("PASS: startup NSError, rollback, and retry")
    }

    @MainActor static func staleAndRepeatedCompletion() async throws {
        let native = OfflineEngine()
        defer { native.finish() }
        let engine = KeyboardAudioEngine(voiceCount: 1, makeEngine: { native })
        require(engine.load(profile: .holyPanda), "Built-in keyboard fixture must load")
        engine.play(keyCode: 0, phase: .press, volume: 0.5, pitchVariation: false)
        let oldCompletion = RenderFault.shared.completions.last!
        engine.play(keyCode: 1, phase: .press, volume: 0.7, pitchVariation: false)
        let secondCompletion = RenderFault.shared.completions.last!
        await fire(oldCompletion)
        await drainMainQueue()
        engine.setKeyboardPlaybackGain(0.3)
        require(native.players[0].volume == 0.3, "A stolen voice's old completion must not clear its current gain")
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: native)
        await drainMainQueue()
        engine.play(keyCode: 0, phase: .press, volume: 0.5, pitchVariation: false)
        let currentCompletion = RenderFault.shared.completions.last!
        await fire(secondCompletion)
        await drainMainQueue()
        engine.setKeyboardPlaybackGain(0.4)
        require(native.players[0].volume == 0.4, "A completion from the old device configuration must not clear the new voice")
        require(try! native.render() > 0, "Device reconfiguration must preserve audible key playback")
        await fire(currentCompletion)
        await fire(currentCompletion)
        await drainMainQueue()
        await waitForPause(native, "Repeated completion must leave voices idle and pause the engine")
        print("PASS: background, stale, stolen, and duplicate completion preserve voice lifecycle")
    }

    @MainActor static func releaseAfterPendingPlayback() async throws {
        var native: OfflineEngine? = OfflineEngine()
        var engine: KeyboardAudioEngine? = KeyboardAudioEngine(voiceCount: 1, makeEngine: { native! })
        weak var retainedEngine = engine
        weak var retainedNative = native
        require(engine!.load(profile: .holyPanda), "Built-in keyboard fixture must load")
        engine!.play(keyCode: 0, phase: .press, volume: 0.5, pitchVariation: false)
        let pendingCompletion = RenderFault.shared.completions.last!
        engine = nil
        native!.finish()
        await fire(pendingCompletion)
        await drainMainQueue()
        require(retainedEngine == nil, "Pending native completion must not retain the keyboard engine")
        native = nil
        await drainMainQueue()
        require(retainedNative == nil, "Released keyboard state must not retain its native audio engine")
        print("PASS: pending completion and engine resource release")
    }

    @MainActor static func fire(_ completion: CompletionBox) async {
        await withCheckedContinuation { completed in
            DispatchQueue.global().async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                completion.call(.dataPlayedBack)
                completed.resume()
            }
        }
    }

    @MainActor static func waitForPause(_ native: OfflineEngine, _ message: String) async {
        if !native.isRunning { return }
        let events = AsyncStream<Void>.makeStream()
        native.onPause = { events.continuation.yield() }
        defer { native.onPause = nil; events.continuation.finish() }
        let paused = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in events.stream { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        require(paused && !native.isRunning, message)
    }

    @MainActor static func drainMainQueue() async {
        await withCheckedContinuation { completed in DispatchQueue.main.async { completed.resume() } }
        await withCheckedContinuation { completed in DispatchQueue.main.async { completed.resume() } }
    }
}
''')
PYTHON_SETUP

xcrun swiftc -suppress-warnings -swift-version 6 -parse-as-library \
  -Xfrontend -enable-actor-data-race-checks -module-cache-path "$TEST_ROOT/ModuleCache" \
  "$TEST_ROOT"/*.swift -o "$TEST_ROOT/Probe"

python3 - "$TEST_ROOT/Probe" <<'PYTHON_RUN'
import subprocess
import sys

control = subprocess.run([sys.argv[1], '--native-control'], capture_output=True, text=True, timeout=25)
expected = 'com.apple.coreaudio.avfaudio: required condition is false: _outputFormat.channelCount == buffer.format.channelCount'
if control.returncode != 86 or expected not in control.stderr:
    sys.exit(f'Native channel mismatch control did not raise the expected AVFAudio exception (status {control.returncode})\n{control.stderr}')
sys.stdout.write(control.stdout)
print('PASS: native AVFAudio channel mismatch control raised the expected exception (status 86)')
result = subprocess.run([sys.argv[1]], capture_output=True, text=True, timeout=25)
sys.stdout.write(result.stdout)
sys.stderr.write(result.stderr)
if result.returncode:
    sys.exit(f'Production keyboard playback exited {result.returncode} (86=ObjC exception, 87=behavior assertion)')
PYTHON_RUN
