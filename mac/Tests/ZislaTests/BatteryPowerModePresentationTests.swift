import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct BatteryPowerModePresentationTests {
    @Test
    func initialLoadDoesNotInventAnAutomaticSelection() {
        let presentation = BatteryPowerModePresentation(
            currentMode: nil, powerSource: nil, supportedModes: [], isChanging: false, error: nil
        )
        #expect(presentation.titleKey == "电源模式")
        #expect(presentation.messageKey == "正在读取电源模式…")
        #expect(presentation.isBusy)
        #expect(!presentation.canSelect)
    }

    @Test(arguments: [BatteryPowerSource.battery, .powerAdapter])
    func unsupportedSourceIsDistinctFromLoading(source: BatteryPowerSource) {
        let presentation = BatteryPowerModePresentation(
            currentMode: nil, powerSource: source, supportedModes: [], isChanging: false, error: nil
        )
        #expect(presentation.titleKey == "电源模式")
        #expect(presentation.messageKey == "当前供电方式不支持切换电源模式。")
        #expect(!presentation.isBusy)
        #expect(!presentation.canSelect)
    }

    @Test(arguments: BatteryPowerMode.allCases)
    func verifiedModesHaveDistinctLabelsAndAllowSelection(mode: BatteryPowerMode) {
        let presentation = BatteryPowerModePresentation(
            currentMode: mode, powerSource: .powerAdapter, supportedModes: BatteryPowerMode.allCases,
            isChanging: false, error: nil
        )
        let labels: [BatteryPowerMode: String] = [.automatic: "自动", .lowPower: "低能耗模式", .highPower: "高能耗模式"]
        #expect(presentation.titleKey == labels[mode])
        #expect(presentation.messageKey == nil)
        #expect(!presentation.isBusy)
        #expect(presentation.canSelect)
    }

    @Test
    func authorizationKeepsTheLastVerifiedModeAndDisablesAnotherSubmission() {
        let presentation = BatteryPowerModePresentation(
            currentMode: .automatic, powerSource: .battery, supportedModes: BatteryPowerMode.allCases,
            isChanging: true, error: nil
        )
        #expect(presentation.titleKey == "自动")
        #expect(presentation.messageKey == "正在切换电源模式…")
        #expect(presentation.isBusy)
        #expect(!presentation.canSelect)
    }

    @Test
    func failuresExplainTheActualOutcomeAndRequireRefreshBeforeAnotherSelection() {
        let messages: [(BatteryPowerModeError, String)] = [
            (.stateUnavailable, "无法读取电源模式，请重试。"),
            (.unsupportedMode, "当前供电方式不支持切换电源模式。"),
            (.authorizationCancelled, "电源模式授权已取消。"),
            (.authorizationDenied, "未获得切换电源模式的授权。"),
            (.changeFailed, "无法切换电源模式，请重试。"),
            (.verificationFailed, "无法确认电源模式已更改，请重试。"),
            (.timedOut, "电源模式操作超时，请重试。"),
        ]
        for (error, message) in messages {
            for mode in [BatteryPowerMode?.none, .some(.lowPower)] {
                let presentation = BatteryPowerModePresentation(
                    currentMode: mode, powerSource: mode == nil ? nil : .battery,
                    supportedModes: mode == nil ? [] : BatteryPowerMode.allCases,
                    isChanging: false, error: error
                )
                #expect(presentation.titleKey == (mode == nil ? "电源模式" : "低能耗模式"))
                #expect(presentation.messageKey == message)
                #expect(!presentation.isBusy)
                #expect(!presentation.canSelect)
            }
        }
    }

    @Test
    func unsupportedAndBusyModesCannotBeSelected() {
        let limited = BatteryPowerModePresentation(
            currentMode: .automatic, powerSource: .battery,
            supportedModes: [.automatic, .lowPower], isChanging: false, error: nil
        )
        #expect(limited.canSelect(.automatic))
        #expect(limited.canSelect(.lowPower))
        #expect(!limited.canSelect(.highPower))
        let busy = BatteryPowerModePresentation(
            currentMode: .automatic, powerSource: .powerAdapter,
            supportedModes: BatteryPowerMode.allCases, isChanging: true, error: nil
        )
        #expect(BatteryPowerMode.allCases.allSatisfy { !busy.canSelect($0) })
    }

    @Test(arguments: AppLanguage.allCases) @MainActor
    func allThreeModesRenderOnOneRowInEveryLanguage(language: AppLanguage) throws {
        let presentation = BatteryPowerModePresentation(
            currentMode: .automatic, powerSource: .powerAdapter,
            supportedModes: BatteryPowerMode.allCases, isChanging: false, error: nil
        )
        let renderer = ImageRenderer(content: BatteryPowerModeButton.modeButtons(
            currentMode: .automatic, presentation: presentation, select: { _ in }
        ).environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.height <= 52, "All modes must remain in a single compact row")
        #expect(image.width > 100, "The modes must be visible without opening a menu")
    }

}
