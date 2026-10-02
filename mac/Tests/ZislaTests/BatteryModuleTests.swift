import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct BatteryModuleTests {
    @Test
    func batteryTrendKeepsOnlyContinuousPowerReadingsWithoutFillingMissingValues() {
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = [12.0, nil, 4.0, 8.0].enumerated().map { index, watts in
            BatteryTrendSample(date: start.addingTimeInterval(Double(index) * 5), level: 0.6, systemPowerWatts: watts)
        }
        let trend = BatteryTrendPresentation(samples: samples)
        #expect(trend.levels == [0.6, 0.6, 0.6, 0.6])
        #expect(trend.powerSamples == Array(samples.suffix(2)))
        #expect(trend.powerScale == 8)
        #expect(trend.powerLevels == [0.5, 1])
        let unavailable = BatteryTrendPresentation(samples: Array(samples.prefix(2)))
        #expect(unavailable.powerSamples.isEmpty)
        #expect(unavailable.powerLevels.isEmpty)
    }

    @Test
    func emptyAndZeroPowerTrendsStayFinite() {
        let empty = BatteryTrendPresentation(samples: [])
        #expect(empty.levels.isEmpty)
        #expect(empty.powerLevels.isEmpty)
        let idle = BatteryTrendPresentation(samples: [
            BatteryTrendSample(date: .distantPast, level: 1, systemPowerWatts: 0),
        ])
        #expect(idle.powerLevels == [0])
        #expect(idle.powerScale == 1)
    }

    @Test
    func batteryIsReachableThroughSystemMonitorWithoutSeparateNavigation() {
        var settings = FeatureSettings.default
        settings.systemMonitorEnabled = false
        settings.batteryMonitorEnabled = true
        let modules = IslandModule.enabledOrder(settings)
        #expect(modules.contains(.system))
        #expect(!modules.contains(.battery))
    }

    @Test
    func configuredModuleOrderControlsVisibleNavigationOrder() {
        var settings = FeatureSettings.default
        settings.moduleOrder = [.mail, .dashboard, .battery]

        #expect(Array(IslandModule.enabledOrder(settings).prefix(3)) == [
            .mail,
            .dashboard,
            .system,
        ])
    }

    @Test
    func groupedTallModuleLayoutsShareHeights() {
        let tallModules: [IslandModule] = [
            .quickNotes, .keyboardSound, .mail, .system, .battery, .pdf,
        ]

        for module in tallModules {
            #expect(module.layout == IslandModuleLayout.system)
        }

        #expect(IslandModuleLayout.system.islandSize.height == 546)
        #expect(IslandModuleLayout.system.panelSize.height == 550)
        #expect(IslandModuleLayout.resolved(for: .battery, dashboardCardCount: 0) == IslandModuleLayout.system)
    }

    @Test
    func aiModuleUsesItsCompactHeightWithoutChangingCPUHeight() {
        #expect(IslandModule.aiMonitor.layout == IslandModuleLayout.ai)
        #expect(IslandModuleLayout.ai.islandSize.height == 495)
        #expect(IslandModuleLayout.ai.panelSize.height == 499)
        #expect(IslandModuleLayout.ai.islandSize.height < IslandModuleLayout.system.islandSize.height)
        #expect(IslandModuleLayout.system.islandSize.height == 546)
        #expect(IslandModuleLayout.system.panelSize.height == 550)
    }

    @Test(arguments: [false, true]) @MainActor
    func lowPowerModeOverridesFullBatteryIconTint(isCharging: Bool) {
        let snapshot = BatterySnapshot(
            level: 1,
            isCharging: isCharging,
            isPluggedIn: true,
            isCharged: !isCharging,
            timeRemainingMinutes: nil,
            isLowPowerMode: true
        )

        #expect(BatteryDetailView.batteryLevelTint(
            snapshot.level, isLowPowerMode: snapshot.isLowPowerMode
        ) == .yellow)
    }

    @Test(arguments: [0.0, 0.149, 0.15, 0.299], [false, true]) @MainActor
    func lowPowerModeOverridesLowBatteryIconTint(level: Double, isCharging: Bool) {
        let snapshot = BatterySnapshot(
            level: level,
            isCharging: isCharging,
            isPluggedIn: isCharging,
            isCharged: false,
            timeRemainingMinutes: nil,
            isLowPowerMode: true
        )

        #expect(BatteryDetailView.batteryLevelTint(
            snapshot.level, isLowPowerMode: snapshot.isLowPowerMode
        ) == .yellow)
    }

    @Test(arguments: [
        (level: 0.0, tint: Color.zislaError),
        (level: 0.149, tint: Color.zislaError),
        (level: 0.15, tint: Color.zislaWarning),
        (level: 0.299, tint: Color.zislaWarning),
        (level: 0.30, tint: Color.zislaSuccess),
        (level: 1.0, tint: Color.zislaSuccess),
    ], [false, true]) @MainActor
    func nonLowPowerModePreservesBatteryLevelTint(sample: (level: Double, tint: Color), isCharging: Bool) {
        let snapshot = BatterySnapshot(
            level: sample.level,
            isCharging: isCharging,
            isPluggedIn: isCharging,
            isCharged: sample.level == 1 && !isCharging,
            timeRemainingMinutes: nil
        )

        #expect(BatteryDetailView.batteryLevelTint(
            snapshot.level, isLowPowerMode: snapshot.isLowPowerMode
        ) == sample.tint)
        #expect(BatteryDetailView.batteryLevelTint(snapshot.level) == sample.tint)
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
            systemLoadWatts: 5.62,
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
        #expect(presentation.systemWatts == snapshot.systemPowerWatts)
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
        #expect(presentation.systemWatts == nil)
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
            lastUnpluggedAt: now.addingTimeInterval(-65 * 60),
            now: now
        )

        #expect(presentation.text == "已脱电使用 1小时5分")
    }

    @Test
    func hidesBatteryHistoryWheneverExternalPowerIsConnected() {
        let now = Date(timeIntervalSince1970: 11_000)
        let lastUnpluggedAt = now.addingTimeInterval(-3_600)

        let charging = BatterySnapshot(
            level: 0.8,
            isCharging: true,
            isPluggedIn: true,
            isCharged: false,
            timeRemainingMinutes: 30
        )
        let pluggedInAndFull = BatterySnapshot(
            level: 1,
            isCharging: false,
            isPluggedIn: true,
            isCharged: true,
            timeRemainingMinutes: nil
        )

        #expect(
            BatteryHistoryPresentation(
                battery: charging,
                lastUnpluggedAt: lastUnpluggedAt,
                now: now
            ).text == nil
        )
        #expect(
            BatteryHistoryPresentation(
                battery: pluggedInAndFull,
                lastUnpluggedAt: lastUnpluggedAt,
                now: now
            ).text == nil
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
            lastUnpluggedAt: now.addingTimeInterval(-60),
            now: now
        )
        let noHistory = BatteryHistoryPresentation(
            battery: snapshot,
            lastUnpluggedAt: nil,
            now: now
        )

        #expect(onlyUnplugged.text == "已脱电使用 1分钟")
        #expect(noHistory.text == nil)
    }
}
