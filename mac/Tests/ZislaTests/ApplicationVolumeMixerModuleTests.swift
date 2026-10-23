import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct ApplicationVolumeMixerModuleTests {
    @Test(arguments: [false, true], [false, true])
    func moduleUsesOnlyVolumeToggle(pdfEnabled: Bool, volumeEnabled: Bool) {
        let settings = FeatureSettings(pdfToolsEnabled: pdfEnabled, volumeMixerEnabled: volumeEnabled)
        #expect(IslandModule.volumeMixer.isEnabled(in: settings) == volumeEnabled)
        #expect(IslandModule.enabledOrder(settings).contains(.volumeMixer) == volumeEnabled)
        #expect(!IslandModule.configuredOrder(settings).contains { $0.rawValue == "pdf" })
    }

    @Test
    func legacyPDFNavigationPositionResolvesToMixer() {
        var settings = FeatureSettings.default
        settings.moduleOrder = [.mail, .pdf, .dashboard, .volumeMixer]
        #expect(Array(IslandModule.configuredOrder(settings).prefix(3)) == [.mail, .volumeMixer, .dashboard])
        #expect(IslandModule.configuredOrder(settings).filter { $0 == .volumeMixer }.count == 1)
        #expect(IslandModule.volumeMixer.layout == IslandModuleLayout.system)
        #expect(!IslandModule.allCases.contains { $0.rawValue == "pdf" })
    }

    @Test(arguments: [
        (volume: 1.0, muted: false, controlled: false, error: nil as String?, expected: nil as String?),
        (volume: 0.4, muted: false, controlled: false, error: nil, expected: "等待应用音量控制生效"),
        (volume: 1.0, muted: true, controlled: false, error: nil, expected: "等待应用音量控制生效"),
        (volume: 0.4, muted: false, controlled: false, error: "denied", expected: "音量调整未生效"),
        (volume: 0.4, muted: false, controlled: true, error: "other application failed", expected: nil),
        (volume: 1.0, muted: false, controlled: false, error: "other application failed", expected: nil),
    ])
    func rowsDistinguishDefaultOutputFromPendingAndFailedControl(
        sample: (volume: Double, muted: Bool, controlled: Bool, error: String?, expected: String?)
    ) {
        let application = ApplicationVolumeApplication(
            id: "fixture.player", name: "Fixture Player", bundleIdentifier: "fixture.player",
            iconData: nil, volume: sample.volume, isMuted: sample.muted, isControlled: sample.controlled
        )
        #expect(ApplicationVolumeMixerModuleView.controlStatus(
            for: application, errorMessage: sample.error
        ) == sample.expected)
    }
}
