import Foundation
import Testing
import ZislaCore
@testable import Zisla

struct HeadphoneMonitoringLifecycleTests {
    @Test
    func defaultMonitorReadsBatteryWithoutSideNotices() {
        let options = SystemMonitorHeadphoneOptions()
        #expect(options.showsBatteryLevels)
        #expect(!options.replacesNetworkIcon)
        #expect(!options.usesVolumeColor)
        let policy = AppModel.headphoneMonitoringPolicy(
            sideNoticesEnabled: false, systemMonitorEnabled: true, options: options
        )
        #expect(policy.audioOutputEnabled)
        #expect(policy.batteryMonitoringEnabled)
    }

    @Test
    func allSettingCombinationsKeepAudioAndBatteryGatesIndependent() {
        for sideNotices in [false, true] {
            for monitor in [false, true] {
                for battery in [false, true] {
                    for replacement in [false, true] {
                        for volumeColor in [false, true] {
                            for networkPriority in [false, true] {
                                let options = SystemMonitorHeadphoneOptions(
                                    replacesNetworkIcon: replacement,
                                    prioritizesNetworkErrors: networkPriority,
                                    usesVolumeColor: volumeColor,
                                    showsBatteryLevels: battery
                                )
                                let policy = AppModel.headphoneMonitoringPolicy(
                                    sideNoticesEnabled: sideNotices,
                                    systemMonitorEnabled: monitor,
                                    options: options
                                )
                                #expect(policy.audioOutputEnabled == (sideNotices || (monitor && (battery || replacement || volumeColor))))
                                #expect(policy.batteryMonitoringEnabled == (monitor && (battery || replacement)))
                            }
                        }
                    }
                }
            }
        }
    }

    @Test
    func settingsLifecycleUsesPolicyWithoutExpandingFocusModeOrShutdown() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/AppModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(source.contains("options: settings.systemMonitorMenuBarHeadphoneOptions"))
        #expect(source.contains("audioOutput.setHeadphoneBatteryMonitoringEnabled(headphonePolicy.batteryMonitoringEnabled)"))
        #expect(source.contains("if headphonePolicy.audioOutputEnabled {\n      audioOutput.start()\n    } else {\n      audioOutput.stop()"))
        #expect(source.contains("if settings.sideNoticesEnabled {\n      focusMode.start()\n    } else {\n      focusMode.stop()"))
        #expect(source.contains("media.stop()\n    audioOutput.stop()\n    calendar.stop()"))
    }
}
