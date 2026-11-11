import Foundation
import Testing
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
struct AudioToolsModuleTests {
    @Test(arguments: [false, true], [false, true])
    func visibilityIsIndependentOfPDFAndDownload(audio: Bool, other: Bool) {
        var settings = FeatureSettings.default
        settings.audioToolsEnabled = audio
        settings.pdfToolsEnabled = other
        settings.downloaderEnabled = other
        #expect(SettingsSection.audioTools.group == .files)
        #expect(SettingsSection.audioTools.isVisible(settings: settings) == audio)
        #expect(SettingsSection.pdfTools.isVisible(settings: settings) == other)
        #expect(SettingsSection.allCases.filter { $0.group == .files } == [.pdfTools, .audioTools])
    }

    @Test(arguments: AudioToolOperation.allCases)
    func searchesAndNavigatesToEveryOperation(operation: AudioToolOperation) throws {
        for language in [AppLanguage.simplifiedChinese, .english, .arabic] {
            let query = AppLocalization.string(operation.title, language: language)
            let result = try #require(SettingsSearchIndex.results(for: query, settings: .default, locale: language.locale)
                .first { $0.section == .audioTools && $0.anchor == .audioOperation(operation) })
            let input = SettingsInput()
            input.select(result.section, searchTarget: result.anchor)
            #expect(input.selection == .audioTools)
            #expect(input.selectedAudioOperation == operation)
            input.select(.general)
            input.navigate(backward: true, settings: .default)
            #expect(input.selectedAudioOperation == operation)
            input.select(.audioTools)
            #expect(input.selectedAudioOperation == .convert)
        }
    }

    @Test
    func disabledAudioToolsHideTheirSearchItemsAndHistory() {
        var settings = FeatureSettings.default
        settings.audioToolsEnabled = false
        #expect(!SettingsSearchIndex.items(settings: settings).contains { $0.section == .audioTools })
        let input = SettingsInput()
        input.select(.audioTools, searchTarget: .audioOperation(.denoise))
        input.select(.features)
        input.navigate(backward: true, settings: settings)
        #expect(input.selection == .general)
    }

    @Test
    func exposesCommonOperationsAndBatchBoundaries() {
        #expect(AudioToolOperation.allCases.count == 27)
        #expect(AudioExportFormat.allCases.count == 11)
        #expect(AudioToolOperation.convert.exportsToDirectory(inputCount: 2))
        #expect(!AudioToolOperation.merge.exportsToDirectory(inputCount: 2))
        #expect(AudioToolOperation.split.exportsToDirectory(inputCount: 1))
        #expect(AudioToolOperation.splitChannels.exportsToDirectory(inputCount: 1))
        #expect(AudioToolOperation.generateTone.generatesAudio)
        #expect(!AudioToolOperation.extract.allowsMultipleInputs)
    }

    @Test
    func controllerKeepsInputsWhenInspectionFailsAndAllowsRetry() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        let controller = AudioToolsController(service: fixture.service)
        let missing = fixture.root.appendingPathComponent("missing.wav")
        controller.setInputs([missing])
        try await waitUntil { !controller.isInspecting }
        #expect(controller.failed)
        #expect(controller.inputURLs == [missing])
        #expect(controller.summaries.isEmpty)
        controller.setInputs([fixture.first, fixture.second])
        try await waitUntil { !controller.isInspecting }
        #expect(!controller.failed)
        #expect(controller.summaries.count == 2)
        controller.moveInput(at: 1, offset: -1)
        #expect(controller.inputURLs == [fixture.second, fixture.first])
        #expect(controller.summaries.map(\.duration) == [1, 2])
    }

    @Test
    func controllerCancellationRejectsStaleCompletion() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        let gate = ProbeGate()
        let service = AudioProcessingService(tools: { fixture.tools }, run: { _, _ in
            await gate.pause()
            return .init(status: 0, standardOutput: Data(ControllerFixture.json(duration: 2).utf8), standardError: "", didTimeout: false)
        })
        let controller = AudioToolsController(service: service)
        controller.setInputs([fixture.first])
        await gate.waitForStart()
        controller.setInputs([])
        await gate.release()
        for _ in 0..<8 { await Task.yield() }
        #expect(controller.inputURLs.isEmpty)
        #expect(controller.summaries.isEmpty)
        #expect(!controller.isInspecting)
        #expect(controller.message == nil)
    }

    private func waitUntil(_ ready: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while !ready(), clock.now < deadline { await Task.yield() }
        #expect(ready(), "Audio controller did not finish within the deterministic test budget")
    }
}

private struct ControllerFixture: Sendable {
    let root: URL
    var first: URL { root.appendingPathComponent("first.wav") }
    var second: URL { root.appendingPathComponent("second.wav") }
    var tools: AudioProcessingTools { .init(ffmpeg: URL(fileURLWithPath: "/fixture/ffmpeg"), ffprobe: URL(fileURLWithPath: "/fixture/ffprobe")) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AudioController-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
    }

    func clean() { try? FileManager.default.removeItem(at: root) }
    static func json(duration: Int) -> String {
        "{\"streams\":[{\"codec_name\":\"pcm\",\"sample_rate\":\"48000\",\"channels\":2,\"duration\":\"\(duration)\"}]}"
    }
    var service: AudioProcessingService {
        AudioProcessingService(tools: { tools }, run: { _, args in
            let index = try #require(args.firstIndex(of: "-i"))
            let duration = args[index + 1].hasSuffix("second.wav") ? 1 : 2
            return .init(status: 0, standardOutput: Data(Self.json(duration: duration).utf8), standardError: "", didTimeout: false)
        })
    }
}

private actor ProbeGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var started = false

    func pause() async {
        started = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { continuation = $0 }
    }
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { startContinuation = $0 }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}
