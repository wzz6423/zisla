import Foundation
import Testing
@testable import ZislaCore

struct ScreenRecordingModelsTests {
    private func project() -> ScreenRecordingProject {
        .init(name: "Demo", videoFile: "screen.mp4", duration: 12, width: 1_920, height: 1_080)
    }

    @Test(arguments: [false, true])
    func newProjectPreservesFullSourceAndRoundTrips(fromRecording: Bool) throws {
        let source = fromRecording
            ? ScreenRecordingProject(result: .init(videoFile: "screen.mp4", duration: 12, width: 1_920, height: 1_080), name: "Demo")
            : project()
        try source.validate()
        #expect(source.outputDuration == 12)
        #expect(source.edits.padding == 0, "New projects must fill their original canvas without background margins")
        #expect(source.edits.cornerRadius == 0, "New projects must preserve square video corners")
        #expect(source.edits.shadow == 0, "New projects must start without a video shadow")
        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(source))
        #expect(decoded == source)
    }

    @Test(arguments: [(0.06, 0.02, 0.3), (0.3, 0.2, 1.0)])
    func savedProjectPreservesExplicitCanvasEffects(padding: Double, cornerRadius: Double, shadow: Double) throws {
        var source = project()
        source.edits.padding = padding
        source.edits.cornerRadius = cornerRadius
        source.edits.shadow = shadow
        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(source))
        try decoded.validate()
        #expect(decoded == source, "Reopening a saved project must preserve its explicit canvas effects")
    }

    @Test
    func cameraAspectRatiosRoundTripAndLegacyDefaultsFollowTheShape() throws {
        #expect(RecordingCameraAspectRatio.allCases.map(\.title) == ["1:1", "4:3", "16:9"])
        #expect(RecordingCameraAspectRatio.square.ratio == 1)
        #expect(RecordingCameraAspectRatio.standard.ratio == 4.0 / 3)
        #expect(RecordingCameraAspectRatio.widescreen.ratio == 16.0 / 9)

        var source = project()
        source.edits.cameraAspectRatio = .widescreen
        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(source))
        #expect(decoded.edits.cameraAspectRatio == .widescreen)
        #expect(decoded.edits.effectiveCameraAspectRatio == .widescreen)

        source.edits.cameraAspectRatio = nil
        source.edits.cameraRound = false
        let legacy = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(ScreenRecordingProject.self, from: legacy)
        #expect(restored.edits.effectiveCameraAspectRatio == .standard)
    }

    @Test(arguments: [false, true])
    func legacyProjectWithoutCameraCornerRadiusKeepsItsDefaultRounding(round: Bool) throws {
        var source = project()
        source.edits.cameraRound = round
        source.edits.cameraCornerRadius = 0.3
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        var edits = try #require(legacy["edits"] as? [String: Any])
        edits.removeValue(forKey: "cameraCornerRadius")
        legacy["edits"] = edits
        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONSerialization.data(withJSONObject: legacy))
        try decoded.validate()
        #expect(decoded.version == source.version)
        #expect(decoded.edits.cameraCornerRadius == nil)
        #expect(decoded.edits.effectiveCameraCornerRadius == (round ? 0.5 : 0.1))
    }

    @Test(arguments: [false, true])
    func cameraBorderChoiceRoundTripsWithoutChangingOtherEffects(_ border: Bool) throws {
        var source = project()
        source.edits.cameraBorder = border
        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(source))
        try decoded.validate()
        #expect(decoded == source)
        #expect(decoded.edits.effectiveCameraBorder == border)
    }

    @Test
    func newAndLegacyProjectsHaveNoCameraBorder() throws {
        let source = project()
        #expect(!source.edits.effectiveCameraBorder)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        var edits = try #require(legacy["edits"] as? [String: Any])
        edits.removeValue(forKey: "cameraBorder")
        legacy["edits"] = edits
        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONSerialization.data(withJSONObject: legacy))
        try decoded.validate()
        #expect(decoded.edits.cameraBorder == nil)
        #expect(!decoded.edits.effectiveCameraBorder)
    }

    @Test(arguments: [0.0, 0.125, 0.5], [false, true])
    func cameraCornerRadiusRoundTripsAtItsBoundaries(_ radius: Double, round: Bool) throws {
        var source = project()
        source.edits.cameraRound = round
        source.edits.cameraCornerRadius = radius
        try source.validate()
        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(source))
        #expect(decoded == source)
        #expect(decoded.edits.effectiveCameraCornerRadius == radius)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -0.001, 0.500_001])
    func refusesNonFiniteAndOutOfRangeCameraCornerRadius(_ radius: Double) {
        for round in [false, true] {
            var source = project()
            source.edits.cameraRound = round
            source.edits.cameraCornerRadius = radius
            #expect(throws: ScreenRecordingProjectError.invalidProject) { try source.validate() }
        }
    }

    @Test(arguments: RecordingCameraAspectRatio.allCases, [false, true])
    func explicitCameraRadiusOverridesTheLegacyShapeWithoutChangingItsAspectRatio(
        ratio: RecordingCameraAspectRatio, round: Bool
    ) {
        var edits = RecordingEdits(cameraRound: round, cameraAspectRatio: ratio)
        for radius in [0.0, 0.2, 0.5] {
            edits.cameraCornerRadius = radius
            #expect(edits.effectiveCameraCornerRadius == radius,
                    "An explicit radius must work even when a saved project still carries its circular flag")
            #expect(edits.effectiveCameraAspectRatio == ratio)
        }
        edits.cameraCornerRadius = nil
        #expect(edits.effectiveCameraCornerRadius == (round && ratio == .square ? 0.5 : 0.1))
    }

    @Test func timelineCanReorderAndRepeatSourceAtDifferentSpeeds() throws {
        var source = project()
        source.edits.segments = [.init(start: 8, end: 12, speed: 2), .init(start: 0, end: 4), .init(start: 0, end: 4)]
        try source.validate()
        #expect(source.outputDuration == 10)
        source.edits.segments = []
        try source.validate()
        #expect(source.outputDuration == 0)
    }

    @Test(arguments: ["../secret", "/tmp/media", "sub/video.mp4", "..", "", "a\\b", "a\0b"])
    func refusesUnsafeMediaReferences(_ path: String) {
        var source = project()
        source.videoFile = path
        #expect(throws: ScreenRecordingProjectError.unsafeMediaPath) { try source.validate() }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, 0, -1])
    func refusesInvalidDuration(_ duration: Double) {
        var source = project()
        source.duration = duration
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try source.validate() }
    }

    @Test func refusesOutOfBoundsEditsAndFutureVersion() {
        var source = project()
        source.edits.crop = .init(x: 0.9, y: 0, width: 0.2, height: 1)
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try source.validate() }
        source = project()
        source.edits.segments[0].speed = 0
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try source.validate() }
        source = project()
        source.version += 1
        #expect(throws: ScreenRecordingProjectError.unsupportedVersion) { try source.validate() }
    }

    @Test func shortcutsAreSequentialUniqueAndDoNotCollideWithExistingDefaults() {
        let actions = RecordingShortcutAction.allCases
        #expect(actions.map(\.rawValue) == Array(1...9))
        #expect(Set(actions.map { $0.hotkey.keyCode }).count == 9)
        for action in actions {
            #expect(action.hotkey.carbonModifiers == 0x1200)
            #expect(action.hotkey.keyDisplayName == String(action.rawValue))
            #expect(!action.hotkey.conflicts(with: ScreenshotHotkeyDefaults.capture))
            #expect(!action.hotkey.conflicts(with: ScreenshotHotkeyDefaults.longCapture))
            #expect(!action.hotkey.conflicts(with: .optionSpace))
        }
    }

    @Test func recordingSettingsMigrateAndPersistCustomShortcuts() throws {
        let legacy = try JSONDecoder().decode(FeatureSettings.self, from: Data("{}".utf8))
        #expect(legacy.screenRecordingEnabled)
        #expect(legacy.screenRecordingHotkeys.isEmpty)
        var configured = legacy
        configured.screenRecordingEnabled = false
        configured.screenRecordingHotkeys = ["1": .commandShiftV, "unknown": .optionSpace]
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(configured))
        #expect(!decoded.screenRecordingEnabled)
        #expect(decoded.screenRecordingHotkey(for: .display) == .commandShiftV)
        #expect(decoded.screenRecordingHotkey(for: .export) == RecordingShortcutAction.export.hotkey)
        #expect(decoded.screenRecordingHotkeys["unknown"] == nil)
    }

    @Test func recordingShortcutConflictsFollowEnabledFeaturesAndPhysicalKeys() {
        var settings = FeatureSettings.default
        let shortcut = RecordingShortcutAction.display.hotkey
        #expect(settings.recordingShortcutConflict(for: shortcut, excluding: .display) == nil)
        #expect(settings.recordingShortcutConflict(for: shortcut) == RecordingShortcutAction.display.title)
        settings.screenRecordingHotkeys["2"] = shortcut
        #expect(settings.recordingShortcutConflict(for: shortcut, excluding: .display) == RecordingShortcutAction.window.title)
        settings.screenRecordingHotkeys = [:]
        settings.screenshotHotkey = shortcut
        #expect(settings.recordingShortcutConflict(for: shortcut, excluding: .display) == "截图")
        settings.screenshotEnabled = false
        settings.voiceInputHotkeyPreset = shortcut
        #expect(settings.recordingShortcutConflict(for: shortcut, excluding: .display) == "语音输入")
        settings.voiceInputEnabled = false
        settings.clipboardAssistantTriggerConfiguration = .hotkey(shortcut)
        #expect(settings.recordingShortcutConflict(for: shortcut, excluding: .display) == "快速触发快捷键")
        settings.clipboardAssistantTriggerConfiguration = .none
        settings.clipboardAssistantDismissConfiguration = .hotkey(shortcut)
        #expect(settings.recordingShortcutConflict(for: shortcut, excluding: .display) == "关闭弹窗快捷键")
        settings.clipboardAssistantEnabled = false
        #expect(settings.recordingShortcutConflict(for: shortcut, excluding: .display) == nil)
        settings.screenRecordingEnabled = false
        #expect(settings.recordingShortcutConflict(for: shortcut) == nil)
    }

    @Test func fixedSeedEditsRoundTripWithBoundedTimes() throws {
        var seed: UInt64 = 0xF0B24B0A
        for _ in 0..<64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let start = Double(seed % 10_000) / 1_000
            let end = min(12, start + 0.1 + Double((seed >> 17) % 1_000) / 1_000)
            var source = project()
            source.edits.segments = [.init(start: start, end: end, speed: 0.1 + Double((seed >> 31) % 790) / 100)]
            try source.validate()
            let restored = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(source))
            #expect(restored == source)
            #expect(restored.outputDuration > 0)
        }
    }
}
