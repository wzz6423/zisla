import Foundation
import Testing
@testable import ZislaCore

struct ScreenRecordingModelsTests {
    private func project() -> ScreenRecordingProject {
        .init(name: "Demo", videoFile: "screen.mp4", duration: 12, width: 1_920, height: 1_080)
    }

    @Test func newProjectPreservesFullSourceAndRoundTrips() throws {
        let source = project()
        try source.validate()
        #expect(source.outputDuration == 12)
        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(source))
        #expect(decoded == source)
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
