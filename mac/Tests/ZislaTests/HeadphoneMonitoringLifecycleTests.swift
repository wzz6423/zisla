import Foundation
import Testing
import ZislaCore
@testable import Zisla

struct HeadphoneMonitoringLifecycleTests {
    @Test
    func defaultMonitorDoesNotStartAudioOrBatteryMonitoring() {
        let options = SystemMonitorHeadphoneOptions()
        #expect(!options.replacesNetworkIcon)
        #expect(!options.usesVolumeColor)
        let policy = AppModel.headphoneMonitoringPolicy(
            sideNoticesEnabled: false, systemMonitorEnabled: true, options: options
        )
        #expect(!policy)
    }

    @Test
    func allSettingCombinationsEnableOnlyRequiredAudioMonitoring() {
        for sideNotices in [false, true] {
            for monitor in [false, true] {
                for replacement in [false, true] {
                    for volumeColor in [false, true] {
                        for networkPriority in [false, true] {
                            let options = SystemMonitorHeadphoneOptions(
                                replacesNetworkIcon: replacement,
                                prioritizesNetworkErrors: networkPriority,
                                usesVolumeColor: volumeColor
                            )
                            let policy = AppModel.headphoneMonitoringPolicy(
                                sideNoticesEnabled: sideNotices,
                                systemMonitorEnabled: monitor,
                                options: options
                            )
                            #expect(policy == (sideNotices || (monitor && (replacement || volumeColor))))
                        }
                    }
                }
            }
        }
    }

}
