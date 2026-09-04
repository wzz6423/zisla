import Foundation
import Testing
import ZislaKit

@testable import Zisla

struct BatteryModuleTests {
    @Test
    func batteryModuleIsImmediatelyRightOfSystemMonitor() throws {
        let systemIndex = try #require(IslandModule.allCases.firstIndex(of: .system))
        let batteryIndex = IslandModule.allCases.index(after: systemIndex)
        let batteryModule = try #require(
            batteryIndex < IslandModule.allCases.endIndex
                ? IslandModule.allCases[batteryIndex]
                : nil
        )
        #expect(batteryModule == .battery)
        #expect(IslandModule.battery.layout == IslandModuleLayout.battery)
    }

    @Test
    func onBatteryPowerFlowsFromBatteryToMac() {
        let snapshot = BatterySnapshot(
            level: 0.59,
            isCharging: false,
            isPluggedIn: false,
            isCharged: false,
            timeRemainingMinutes: 180,
            powerWatts: 5.62,
            batteryFlowWatts: -5.62
        )

        let presentation = LocalPowerFlowPresentation(battery: snapshot)

        #expect(presentation.mode == .onBattery)
        #expect(presentation.topology == .batteryToMac)
        #expect(presentation.systemWatts == 5.62)
        #expect(presentation.batteryRoute == .supplying)
        #expect(!presentation.inputIsRated)
    }

    @Test
    func pluggedInPowerSplitsBetweenBatteryAndMac() {
        let snapshot = BatterySnapshot(
            level: 0.39,
            isCharging: true,
            isPluggedIn: true,
            isCharged: false,
            timeRemainingMinutes: 42,
            powerWatts: 61.2,
            adapterWatts: 84.9,
            adapterRatedWatts: 85,
            systemLoadWatts: 23.7,
            batteryFlowWatts: 61.2
        )

        let presentation = LocalPowerFlowPresentation(battery: snapshot)

        #expect(presentation.mode == .pluggedIn)
        #expect(presentation.topology == .adapterSplit)
        #expect(presentation.inputWatts == 84.9)
        #expect(presentation.batteryWatts == 61.2)
        #expect(presentation.systemWatts == 23.7)
        #expect(presentation.batteryRoute == .charging)
        #expect(!presentation.inputIsRated)
    }

    @Test
    func adapterRatingIsLabeledAsFallbackInsteadOfLiveInput() {
        let snapshot = BatterySnapshot(
            level: 0.87,
            isCharging: false,
            isPluggedIn: true,
            isCharged: false,
            timeRemainingMinutes: nil,
            adapterRatedWatts: 85
        )

        let presentation = LocalPowerFlowPresentation(battery: snapshot)

        #expect(presentation.inputWatts == 85)
        #expect(presentation.inputIsRated)
        #expect(presentation.batteryWatts == nil)
        #expect(presentation.batteryRoute == .unavailable)
        #expect(presentation.topology == .adapterToMac)
    }

    @Test
    func weakAdapterAndBatteryMergeIntoMac() {
        let snapshot = BatterySnapshot(
            level: 0.38,
            isCharging: false,
            isPluggedIn: true,
            isCharged: false,
            timeRemainingMinutes: nil,
            powerWatts: 20,
            adapterWatts: 30,
            adapterRatedWatts: 35,
            systemLoadWatts: 50,
            batteryFlowWatts: -20
        )

        let presentation = LocalPowerFlowPresentation(battery: snapshot)

        #expect(presentation.topology == .adapterAndBatteryMerge)
        #expect(presentation.inputWatts == 30)
        #expect(presentation.batteryWatts == 20)
        #expect(presentation.systemWatts == 50)
        #expect(presentation.batteryRoute == .supplying)
    }

    @Test
    func zeroBatteryFlowUsesAdapterPassThrough() {
        let snapshot = BatterySnapshot(
            level: 1,
            isCharging: false,
            isPluggedIn: true,
            isCharged: true,
            timeRemainingMinutes: nil,
            powerWatts: 0,
            adapterWatts: 23.7,
            systemLoadWatts: 23.7,
            batteryFlowWatts: 0
        )

        let presentation = LocalPowerFlowPresentation(battery: snapshot)

        #expect(presentation.topology == .adapterToMac)
        #expect(presentation.batteryWatts == 0)
        #expect(presentation.batteryRoute == .idle)
    }

    @Test
    func displaysBatteryHistoryWhileRunningOnBattery() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = BatterySnapshot(
            level: 0.59,
            isCharging: false,
            isPluggedIn: false,
            isCharged: false,
            timeRemainingMinutes: 180
        )

        let presentation = BatteryHistoryPresentation(
            battery: snapshot,
            lastFullyChargedAt: now.addingTimeInterval(-2 * 3_600 - 5 * 60),
            lastUnpluggedAt: now.addingTimeInterval(-65 * 60),
            now: now
        )

        #expect(presentation.text == "上次充满 2小时5分，已脱电使用 1小时5分")
    }

    @Test
    func hidesBatteryHistoryWhileChargingOnly() {
        let now = Date(timeIntervalSince1970: 11_000)
        let history = (
            lastFullyChargedAt: now.addingTimeInterval(-7_200),
            lastUnpluggedAt: now.addingTimeInterval(-3_600)
        )

        let charging = BatterySnapshot(
            level: 0.8,
            isCharging: true,
            isPluggedIn: true,
            isCharged: false,
            timeRemainingMinutes: 30
        )
        let pluggedIn = BatterySnapshot(
            level: 1,
            isCharging: false,
            isPluggedIn: true,
            isCharged: true,
            timeRemainingMinutes: nil
        )

        #expect(
            BatteryHistoryPresentation(
                battery: charging,
                lastFullyChargedAt: history.lastFullyChargedAt,
                lastUnpluggedAt: history.lastUnpluggedAt,
                now: now
            ).text == nil
        )
        #expect(
            BatteryHistoryPresentation(
                battery: pluggedIn,
                lastFullyChargedAt: history.lastFullyChargedAt,
                lastUnpluggedAt: history.lastUnpluggedAt,
                now: now
            ).text == "上次充满 2小时0分，已脱电使用 1小时0分"
        )
    }

    @Test
    func displaysAvailableBatteryHistoryWhenTimestampIsMissing() {
        let now = Date(timeIntervalSince1970: 12_000)
        let snapshot = BatterySnapshot(
            level: 0.5,
            isCharging: false,
            isPluggedIn: false,
            isCharged: false,
            timeRemainingMinutes: 120
        )

        let onlyUnplugged = BatteryHistoryPresentation(
            battery: snapshot,
            lastFullyChargedAt: nil,
            lastUnpluggedAt: now.addingTimeInterval(-60),
            now: now
        )
        let onlyFullyCharged = BatteryHistoryPresentation(
            battery: snapshot,
            lastFullyChargedAt: now.addingTimeInterval(-60),
            lastUnpluggedAt: nil,
            now: now
        )
        let noHistory = BatteryHistoryPresentation(
            battery: snapshot,
            lastFullyChargedAt: nil,
            lastUnpluggedAt: nil,
            now: now
        )

        #expect(onlyUnplugged.text == "已脱电使用 1分钟")
        #expect(onlyFullyCharged.text == "上次充满 1分钟")
        #expect(noHistory.text == nil)
    }
}
