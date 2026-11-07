import Foundation
import Testing
@testable import ZislaCore

struct ScreenRecordingPortraitProjectTests {
    private func project() -> ScreenRecordingProject {
        .init(name: "Portrait", videoFile: "screen.mp4", cameraFile: "camera.mp4", microphoneFile: "microphone.mp4",
            duration: 2, width: 320, height: 240)
    }

    @Test func legacyProjectsKeepEffectsOffAndUseExistingMedia() throws {
        let original = project()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var edits = try #require(json["edits"] as? [String: Any])
        for key in ["portraitEffects", "voiceEffects"] { edits.removeValue(forKey: key) }
        json["edits"] = edits
        for key in ["rawCameraFile", "rawMicrophoneFile"] { json.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONSerialization.data(withJSONObject: json))
        try restored.validate()
        #expect(restored.edits.portraitEffects == nil && restored.edits.voiceEffects == nil)
        #expect(restored.editingCameraFile == "camera.mp4" && restored.editingMicrophoneFile == "microphone.mp4")
        #expect(restored == original)
    }

    @Test func captureResultsKeepBothOriginalsAndAuthoredEffectsAcrossSaveAndMigration() throws {
        let result = ScreenRecordingResult(videoFile: "screen.mp4", cameraFile: "camera.mp4", microphoneFile: "microphone.mp4",
            duration: 2, width: 320, height: 240, rawCameraFile: "camera-original.mp4", rawMicrophoneFile: "mic-original.mp4",
            portraitEffects: .init(smoothing: 0.4, brightening: 0.3, faceSlimming: 0.2, bodySlimming: 0.1),
            voiceEffects: .init(preset: .warm, amount: 0.7))
        var source = ScreenRecordingProject(result: result, name: "Portrait")
        source.timeline = .migrating(source)
        source.timeline?.clips[0].portraitEffects = .init(bodySlimming: 0.5)
        source.timeline?.clips[0].voiceEffects = .init(preset: .bright, amount: 1)
        try source.validate()
        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(source))
        #expect(decoded == source)
        #expect(decoded.editingCameraFile == "camera-original.mp4" && decoded.editingMicrophoneFile == "mic-original.mp4")
        #expect(Set(decoded.mediaFiles) == ["screen.mp4", "camera.mp4", "microphone.mp4", "camera-original.mp4", "mic-original.mp4"])
        #expect(decoded.outputDuration == 2)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -0.01, 1.01])
    func projectAndClipRejectInvalidEffectStrengths(_ strength: Double) {
        for clip in [false, true] {
            for voice in [false, true] {
                var source = project()
                if clip {
                    source.timeline = .migrating(source)
                    if voice { source.timeline?.clips[0].voiceEffects = .init(preset: .warm, amount: strength) }
                    else { source.timeline?.clips[0].portraitEffects = .init(smoothing: strength) }
                } else {
                    if voice { source.edits.voiceEffects = .init(preset: .warm, amount: strength) }
                    else { source.edits.portraitEffects = .init(smoothing: strength) }
                }
                #expect(throws: ScreenRecordingProjectError.invalidProject) { try source.validate() }
            }
        }
    }

    @Test func unsafeOriginalPathsAndOrphanedOriginalsAreRejected() {
        for path in ["../camera.mp4", "/tmp/camera.mp4", "bad\\camera.mp4", "", "camera\0.mp4"] {
            for camera in [false, true] {
                var source = project()
                if camera { source.rawCameraFile = path } else { source.rawMicrophoneFile = path }
                #expect(throws: ScreenRecordingProjectError.unsafeMediaPath) { try source.validate() }
            }
        }
        var source = project()
        source.cameraFile = nil
        source.rawCameraFile = "camera-original.mp4"
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try source.validate() }
        source = project()
        source.microphoneFile = nil
        source.rawMicrophoneFile = "mic-original.mp4"
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try source.validate() }
    }
}
