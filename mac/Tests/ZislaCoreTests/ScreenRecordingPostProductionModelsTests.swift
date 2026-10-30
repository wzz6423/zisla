import Foundation
import Testing
@testable import ZislaCore

struct ScreenRecordingPostProductionModelsTests {
    private func project() -> ScreenRecordingProject {
        ScreenRecordingProject(name: "Demo", videoFile: "screen.mp4", cameraFile: "camera.mp4",
            microphoneFile: "microphone.wav", duration: 1, width: 64, height: 48)
    }

    @Test func legacyProjectsKeepBothAudioSourcesAndCameraVisible() throws {
        var source = project()
        source.edits.showCamera = false
        source.edits.screenAudioVolume = 0.25
        source.edits.microphoneVolume = 0
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        var edits = try #require(object["edits"] as? [String: Any])
        for key in ["showCamera", "screenAudioVolume", "microphoneVolume"] { edits.removeValue(forKey: key) }
        object["edits"] = edits

        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self,
            from: JSONSerialization.data(withJSONObject: object))

        try decoded.validate()
        #expect(decoded.version == ScreenRecordingProject.currentVersion)
        #expect(decoded.edits.showCamera == nil)
        #expect(decoded.edits.effectiveShowCamera)
        #expect(decoded.edits.effectiveScreenAudioVolume == 1)
        #expect(decoded.edits.effectiveMicrophoneVolume == 1)
    }

    @Test(arguments: [0.0, 0.125, 1.0])
    func independentVolumesAndHiddenCameraRoundTripWithoutLosingMedia(_ volume: Double) throws {
        var source = project()
        source.edits.screenAudioVolume = volume
        source.edits.microphoneVolume = 1 - volume
        source.edits.showCamera = false
        try source.validate()

        let decoded = try JSONDecoder().decode(ScreenRecordingProject.self, from: JSONEncoder().encode(source))

        #expect(decoded == source)
        #expect(decoded.edits.effectiveScreenAudioVolume == volume)
        #expect(decoded.edits.effectiveMicrophoneVolume == 1 - volume)
        #expect(!decoded.edits.effectiveShowCamera)
        #expect(decoded.cameraFile == "camera.mp4")
        #expect(decoded.microphoneFile == "microphone.wav")
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -0.001, 1.000_001])
    func invalidAudioLevelsAreRejectedForEachSource(_ volume: Double) {
        for path in [\RecordingEdits.screenAudioVolume, \RecordingEdits.microphoneVolume] {
            var source = project()
            source.edits[keyPath: path] = volume
            #expect(throws: ScreenRecordingProjectError.invalidProject) { try source.validate() }
        }
    }
}
