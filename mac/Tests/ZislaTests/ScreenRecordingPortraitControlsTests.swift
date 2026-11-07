import AppKit
import AVFoundation
import CoreImage
import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct ScreenRecordingPortraitControlsTests {
    @Test(arguments: [false, true])
    func originalTracksAndEffectsSurviveSaveReopenCopyAndRejectMissingOrEscapedOriginals(_ escaped: Bool) throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        var project = fixture.project()
        project.cameraFile = "camera.mp4"
        project.microphoneFile = "mic.wav"
        project.rawCameraFile = "camera-original.mp4"
        project.rawMicrophoneFile = "mic-original.wav"
        project.edits.portraitEffects = .init(brightening: 0.4)
        project.edits.voiceEffects = .init(preset: .warm, amount: 0.7)
        project.timeline = .migrating(project)
        project.timeline?.clips[0].voiceEffects = .init(preset: .bright, amount: 0.5)
        for (index, file) in project.mediaFiles.enumerated() {
            try Data([UInt8(index + 1)]).write(to: fixture.directory.appendingPathComponent(file))
        }
        try fixture.store.save(project, in: fixture.directory)
        #expect(try fixture.store.load(from: fixture.directory) == project)
        let copy = fixture.root.appendingPathComponent("copy.zisla-recording")
        try fixture.store.copy(project, from: fixture.directory, to: copy)
        #expect(try fixture.store.load(from: copy) == project)
        for file in project.mediaFiles {
            #expect(try Data(contentsOf: copy.appendingPathComponent(file)) == Data(contentsOf: fixture.directory.appendingPathComponent(file)))
        }
        let manifest = fixture.directory.appendingPathComponent("project.json")
        let before = try Data(contentsOf: manifest)
        let raw = fixture.directory.appendingPathComponent("mic-original.wav")
        try FileManager.default.removeItem(at: raw)
        let outside = fixture.root.appendingPathComponent("outside.wav")
        if escaped {
            try Data([99]).write(to: outside)
            try FileManager.default.createSymbolicLink(at: raw, withDestinationURL: outside)
        }
        #expect(throws: Error.self) { try fixture.store.save(project, in: fixture.directory) }
        #expect(throws: Error.self) { try fixture.store.load(from: fixture.directory) }
        let failed = fixture.root.appendingPathComponent("failed-copy.zisla-recording")
        #expect(throws: Error.self) { try fixture.store.copy(project, from: fixture.directory, to: failed) }
        #expect(!FileManager.default.fileExists(atPath: failed.path))
        #expect(try Data(contentsOf: manifest) == before)
        if escaped { #expect(try Data(contentsOf: outside) == Data([99])) }
    }

    @Test func projectEffectsAndPerClipOverridesSupportUndoAndKeepOtherClipsUntouched() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        var project = fixture.project()
        project.cameraFile = "camera.mp4"
        project.microphoneFile = "mic.mp4"
        project.edits.portraitEffects = .init(smoothing: 0.3)
        project.edits.voiceEffects = .init(preset: .warm, amount: 0.5)
        project.timeline = .migrating(project)
        let first = try #require(project.timeline?.clips.first)
        var second = first
        second.id = "second"
        second.start = 2
        project.timeline?.clips.append(second)
        model.install(project, directory: fixture.directory)
        let controls = ScreenRecordingPortraitControls(model: model, target: .clip(first.id), showsPortrait: true, showsVoice: true)
        #expect(controls.portrait == project.edits.portraitEffects && controls.voice == project.edits.voiceEffects)
        controls.setPortrait(.init(bodySlimming: 0.6))
        #expect(model.timeline?.clips[0].portraitEffects == .init(bodySlimming: 0.6))
        #expect(model.timeline?.clips[1] == second)
        #expect(model.canUndo && model.isDirty)
        model.undo()
        #expect(model.project == project)
        model.redo()
        controls.setVoice(.init(preset: .broadcast, amount: 0.8))
        #expect(model.timeline?.clips[0].voiceEffects == .init(preset: .broadcast, amount: 0.8))
        #expect(model.project?.edits.voiceEffects == project.edits.voiceEffects)
        controls.setPortrait(.init())
        controls.setVoice(.init())
        #expect(!controls.portrait.isEnabled && !controls.voice.isEnabled, "Reset must override inherited project effects")
        let valid = model.project
        controls.setPortrait(.init(smoothing: .nan))
        #expect(model.project == valid && model.errorMessage != nil)
        #expect(model.project?.rawCameraFile == nil && model.project?.cameraFile == "camera.mp4")
    }

    @Test func captureControlsKeepSettingsOutOfTheEditedProjectAndRejectInvalidStrengths() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        let original = fixture.project()
        model.install(original, directory: fixture.directory)
        let controls = ScreenRecordingPortraitControls(model: model, target: .capture, showsPortrait: true, showsVoice: true)
        controls.setPortrait(.init(smoothing: 0.4, bodySlimming: 0.2))
        controls.setVoice(.init(preset: .natural, amount: 0.6))
        #expect(model.configuration.portraitEffects == .init(smoothing: 0.4, bodySlimming: 0.2))
        #expect(model.configuration.voiceEffects == .init(preset: .natural, amount: 0.6))
        let configuration = model.configuration
        controls.setPortrait(.init(brightening: 2))
        controls.setVoice(.init(preset: .warm, amount: -.infinity))
        #expect(model.configuration == configuration)
        #expect(model.project == original && !model.isDirty && !model.canUndo)
    }

    @Test(arguments: AppLanguage.allCases)
    func portraitKeysAreTranslatedInEveryLanguage(_ language: AppLanguage) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let paths = ["Sources/Zisla/ScreenRecordingPortraitControls.swift", "Sources/Zisla/ScreenRecordingCaptureBar.swift",
            "Sources/Zisla/ScreenRecordingEffectsView.swift", "Sources/Zisla/ScreenRecordingMultitrackClipInspector.swift"]
        var keys: Set<String> = ["磨皮", "提亮", "瘦脸", "瘦身"]
        let expression = try NSRegularExpression(pattern: #"AppLocalization\.text\("([^"]+)""#)
        for path in paths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            for match in expression.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                if let range = Range(match.range(at: 1), in: source) { keys.insert(String(source[range])) }
            }
        }
        keys.formUnion(RecordingVoicePreset.allCases.map(\.title))
        let url = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
        let englishURL = root.appendingPathComponent("Resources/Localization/en.lproj/Localizable.strings")
        let english = try #require(NSDictionary(contentsOf: englishURL) as? [String: String])
        let effectKeys: Set<String> = ["人像效果", "磨皮", "提亮", "瘦脸", "瘦身", "美声", "效果强度", "恢复原始效果"]
        for key in keys {
            let value = try #require(table[key], "\(language.rawValue) must translate \(key)")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            if effectKeys.contains(key), language != .english, language != .simplifiedChinese {
                #expect(value != english[key], "\(language.rawValue) must not copy the English effect label")
            }
        }
        #expect(AppLocalization.string("磨皮", locale: AppLanguage.english.locale) == "Skin Smoothing")
        #expect(AppLocalization.string("美声", locale: AppLanguage.arabic.locale) == "تحسين الصوت")
    }

    @Test func processedPreviewUsesTheSameCropMirroringBorderAndResetPath() throws {
        let view = ScreenRecordingCameraPreviewView(frame: .init(x: 0, y: 0, width: 240, height: 200))
        defer { view.detach() }
        let image = try #require(CIContext().createCGImage(CIImage(color: .red), from: .init(x: 0, y: 0, width: 64, height: 48)))
        view.update(session: nil, state: .running, configuration: .init(cameraMirrored: true, cameraCornerRadius: 0.25, cameraBorder: true))
        view.update(image: image)
        view.layoutSubtreeIfNeeded()
        let camera = try #require(view.layer?.sublayers?.first)
        let original = try #require(camera.sublayers?.first)
        let processed = try #require(camera.sublayers?.last)
        #expect(original.isHidden && !processed.isHidden && processed.contents != nil)
        #expect(processed.frame == camera.bounds && processed.affineTransform().a == -1)
        #expect(camera.cornerRadius == 45 && camera.borderWidth == 1.8)
        view.update(session: nil, state: .running, configuration: .init(cameraMirrored: false))
        #expect(processed.affineTransform().a == 1)
        view.update(image: nil)
        #expect(!original.isHidden && processed.isHidden && processed.contents == nil)
    }

    @Test func clipControlsOnlyOfferEffectsSupportedByItsActualMedia() throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        var project = fixture.project()
        project.timeline = .migrating(project)
        model.install(project, directory: fixture.directory)
        let inspector = ScreenRecordingMultitrackClipInspector(model: model)
        let clip = try #require(model.timeline?.clips.first)
        #expect(inspector.effectsAvailability(clip).portrait == false && inspector.effectsAvailability(clip).voice == false)
        model.update { $0.cameraFile = "camera.mp4"; $0.microphoneFile = "mic.mp4" }
        #expect(inspector.effectsAvailability(clip).portrait && inspector.effectsAvailability(clip).voice)
        let asset = RecordingMediaAsset(name: "Silent video", file: "silent.mp4", kind: .video, duration: 2, width: 64, height: 48)
        model.update { $0.timeline?.assets.append(asset) }
        let video = RecordingTimelineClip(trackID: clip.trackID, content: .video(asset.id), start: 0, sourceEnd: 2)
        #expect(inspector.effectsAvailability(video).portrait && !inspector.effectsAvailability(video).voice)
        let image = RecordingTimelineClip(trackID: clip.trackID, content: .image(asset.id), start: 0, sourceEnd: 2)
        #expect(inspector.effectsAvailability(image).portrait && !inspector.effectsAvailability(image).voice)
        let audio = RecordingTimelineClip(trackID: clip.trackID, content: .audio(asset.id), start: 0, sourceEnd: 2)
        #expect(!inspector.effectsAvailability(audio).portrait && inspector.effectsAvailability(audio).voice)
    }
}
