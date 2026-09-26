import Carbon.HIToolbox
import Foundation
import Testing
import XCTest
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct ClipboardAssistantShortcutTests {
    @Test(arguments: [0, 1, 10, 11])
    func numberKeysFollowTheDisplayedActionsAndStopAtTen(count: Int) throws {
        let registry = Registry()
        let controller = makeController(registry)
        defer { controller.dismiss(animated: false) }
        let actions = Array(Self.actions.prefix(count))
        let detection = ClipboardAssistantDetection(kind: .text, title: "fixture", actions: actions)
        controller.present(detection, visualStyle: .transparent)
        #expect(registry.hotkeys.count == min(count, 10))
        for (index, action) in actions.enumerated() {
            #expect(controller.shortcutHint(for: action) == (index < 10 ? "⌘ \((index + 1) % 10)" : nil))
        }

        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        for index in 0..<min(count, 10) {
            controller.present(detection, visualStyle: .transparent)
            try registry.callback(keyCode: Self.keyCodes[index])()
            #expect(performed.last == actions[index])
            #expect(registry.hotkeys.isEmpty)
        }
        #expect(performed.count == min(count, 10))
    }

    @Test
    func configuredKeysOnlyRegisterWhileAPromptExists() {
        let registry = Registry()
        let controller = makeController(registry)
        #expect(registry.hotkeys.isEmpty)
        controller.present(Self.detection, visualStyle: .transparent)
        #expect(registry.hotkeys.count == 3)
        controller.dismiss()
        #expect(registry.hotkeys.isEmpty)
        controller.setTriggers(hotkey: ClipboardAssistantDefaults.triggerHotkey, mouseButton: nil)
        #expect(registry.hotkeys.isEmpty)
    }

    @Test
    func unconfiguredControllerDoesNotAcquireSystemShortcuts() {
        let registry = Registry()
        let controller = ClipboardAssistantController(
            windowPresenter: { _, _ in }, makeTriggerMonitor: { registry.makeMonitor() }
        )
        controller.displayDuration = .never
        controller.present(Self.detection, visualStyle: .transparent)
        defer { controller.dismiss(animated: false) }
        #expect(registry.hotkeys.isEmpty)
        #expect(controller.actionHotkeys.isEmpty)
    }

    @Test(arguments: [false, true])
    func customPrimaryShortcutKeepsItsMeaningWithoutRenumberingOthers(fails: Bool) throws {
        let registry = Registry()
        if fails { registry.failures[UInt32(kVK_ANSI_2)] = .registrationFailed }
        let controller = makeController(registry)
        controller.setTriggers(hotkey: Self.hotkey(UInt32(kVK_ANSI_2), "2"), mouseButton: nil)
        controller.present(Self.detection, visualStyle: .transparent)
        defer { controller.dismiss(animated: false) }
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }

        #expect(controller.shortcutHint(for: Self.actions[0]) == (fails ? "⌘ 1" : "⌘ 2 / ⌘ 1"))
        #expect(controller.shortcutHint(for: Self.actions[1]) == nil)
        #expect(controller.shortcutHint(for: Self.actions[2]) == "⌘ 3")
        #expect(registry.hotkeys.filter { $0.keyCode == UInt32(kVK_ANSI_2) }.count == (fails ? 0 : 1))
        try registry.callback(keyCode: UInt32(fails ? kVK_ANSI_1 : kVK_ANSI_2))()
        #expect(performed == [Self.actions[0]])
    }

    @Test
    func clearingPrimaryDisablesAllNumberKeysButPreservesMouseTrigger() throws {
        let registry = Registry()
        let controller = makeController(registry)
        controller.setTriggers(hotkey: ClipboardAssistantDefaults.triggerHotkey, mouseButton: 3)
        controller.present(Self.detection, visualStyle: .transparent)
        let previous = try registry.callback(keyCode: UInt32(kVK_ANSI_2))
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        controller.setTriggers(hotkey: nil, mouseButton: 3)

        #expect(registry.hotkeys.isEmpty)
        #expect(controller.actionHotkeys.isEmpty)
        previous()
        #expect(performed.isEmpty)
        let mouse = try #require(registry.bindings.values.first { $0.mouseButton == 3 })
        mouse.callback()
        #expect(performed == [Self.actions[0]])
        #expect(registry.bindings.isEmpty)
    }

    @Test(arguments: [false, true])
    func nonNumericCustomPrimaryPreservesAliasesAndUsesTheSettingsKeyNotation(modifierOnly: Bool) throws {
        let registry = Registry()
        let controller = makeController(registry)
        defer { controller.dismiss(animated: false) }
        let custom = modifierOnly
            ? VoiceInputHotkeyPreset(keyCode: UInt32(kVK_Option), carbonModifiers: UInt32(optionKey),
                                    keyDisplayName: "Option", modifierSides: [.leftOption])
            : Self.hotkey(UInt32(kVK_ANSI_N), "N")
        controller.setTriggers(hotkey: custom, mouseButton: nil)
        controller.present(Self.detection, visualStyle: .transparent)
        #expect(registry.hotkeys.count == 4)
        #expect(controller.shortcutHint(for: Self.actions[0]) == (modifierOnly ? "L⌥ ×2 / ⌘ 1" : "⌘ N / ⌘ 1"))
        #expect(controller.shortcutHint(for: Self.actions[1]) == "⌘ 2")
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        try registry.callback(keyCode: custom.keyCode)()
        controller.present(Self.detection, visualStyle: .transparent)
        try registry.callback(keyCode: UInt32(kVK_ANSI_1))()
        #expect(performed == [Self.actions[0], Self.actions[0]])
    }

    @Test
    func unavailableHotkeysAreNotAdvertisedAndAreRetriedOnTheNextPrompt() {
        let registry = Registry()
        registry.failures[UInt32(kVK_ANSI_1)] = .registrationFailed
        registry.failures[UInt32(kVK_ANSI_3)] = .registrationFailed
        let controller = makeController(registry)
        controller.present(Self.detection, visualStyle: .transparent)
        #expect(controller.shortcutHint(for: Self.actions[0]) == nil)
        #expect(controller.shortcutHint(for: Self.actions[1]) == "⌘ 2")
        #expect(controller.shortcutHint(for: Self.actions[2]) == nil)
        registry.failures = [:]
        controller.present(Self.detection, visualStyle: .transparent)
        #expect(controller.shortcutHint(for: Self.actions[0]) == "⌘ 1")
        #expect(controller.shortcutHint(for: Self.actions[2]) == "⌘ 3")
        controller.dismiss(animated: false)
    }

    @Test(arguments: ["replacement", "update", "reorder", "configuration"])
    func obsoleteCallbacksCannotPerformAnActionAfterRebinding(reason: String) throws {
        let registry = Registry()
        let controller = makeController(registry)
        var detection = Self.detection
        detection.actions = [.search("fixture"), .copyText("old"), .share]
        let generation = try #require(controller.present(detection, visualStyle: .transparent))
        let previous = try registry.callback(keyCode: UInt32(kVK_ANSI_2))
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        if reason == "update" {
            detection.actions[1] = .copyText("new")
            controller.updateDetection(detection, for: generation)
            controller.perform(.copyText("old"))
        } else if reason == "reorder" {
            detection.actions.swapAt(1, 2)
            controller.updateDetection(detection, for: generation)
        } else if reason == "replacement" {
            controller.present(detection, visualStyle: .transparent)
        } else {
            controller.setTriggers(hotkey: ClipboardAssistantDefaults.triggerHotkey, mouseButton: nil)
        }
        previous()
        #expect(performed.isEmpty)
        try registry.callback(keyCode: UInt32(kVK_ANSI_2))()
        #expect(performed == [detection.actions[1]])
        controller.dismiss(animated: false)
    }

    @Test
    func numberKeysUseTheFinalConfiguredOrder() throws {
        let registry = Registry()
        let controller = makeController(registry)
        let actions = ClipboardAssistantActionOrder.ordered(
            [.search("query"), .translate("query"), .share], for: .text,
            using: [.text: [.translate, .search, .share]]
        )
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        controller.present(.init(kind: .text, title: "fixture", actions: actions), visualStyle: .transparent)
        try registry.callback(keyCode: UInt32(kVK_ANSI_1))()
        #expect(performed == [.translate("query")])
    }

    @Test(arguments: ["dismiss", "systemScreenshot", "screenshot", "lock", "disabled", "share"])
    func suspendedPromptsReleaseBindingsAndRejectPendingCallbacks(reason: String) throws {
        let registry = Registry()
        let controller = makeController(registry)
        controller.setTriggers(hotkey: ClipboardAssistantDefaults.triggerHotkey, mouseButton: 3)
        var detection = Self.detection
        detection.actions.append(.share)
        controller.present(detection, visualStyle: .transparent)
        defer { controller.dismiss(animated: false) }
        let previous = try registry.callback(keyCode: UInt32(kVK_ANSI_2))
        let mouse = try #require(registry.bindings.values.first { $0.mouseButton == 3 }?.callback)
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        switch reason {
        case "systemScreenshot": controller.setSystemScreenshotActive(true)
        case "screenshot":
            controller.setScreenshotActive(true)
            controller.setScreenshotSelectionActive(true)
        case "lock": controller.setScreenLocked(true)
        case "disabled": controller.setTriggers(hotkey: nil, mouseButton: nil)
        case "share": controller.perform(.share)
        default: controller.dismiss()
        }
        #expect(registry.bindings.isEmpty)
        #expect(controller.actionHotkeys.isEmpty)
        previous()
        mouse()
        #expect(performed == (reason == "share" ? [.share] : []))
        if reason == "share" {
            controller.performCurrentAction()
            #expect(performed == [.share])
            #expect(controller.presentation.detection != nil)
        }
        if reason == "systemScreenshot" || reason == "screenshot" {
            controller.performCurrentAction()
            #expect(performed.isEmpty)
            controller.setScreenshotSelectionActive(false)
            controller.setScreenshotActive(false)
            controller.setSystemScreenshotActive(false)
            #expect(registry.hotkeys.count == 4)
            previous()
            #expect(performed.isEmpty)
            try registry.callback(keyCode: UInt32(kVK_ANSI_2))()
            #expect(performed == [Self.actions[1]])
        }
    }

    @Test(arguments: [false, true])
    func translationStatesPauseKeyboardAndMouseActions(fails: Bool) async throws {
        let registry = Registry()
        let controller = makeController(registry)
        controller.setTriggers(hotkey: ClipboardAssistantDefaults.triggerHotkey, mouseButton: 3)
        controller.present(Self.detection, visualStyle: .transparent)
        defer { controller.dismiss(animated: false) }
        let previous = try registry.callback(keyCode: UInt32(kVK_ANSI_2))
        let mouse = try #require(registry.bindings.values.first { $0.mouseButton == 3 }?.callback)
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        controller.translate("fixture", targetLanguage: "zh-CN", service: .init(providers: [{ _, _ in
            if fails { throw ClipboardTranslationError.unavailable }
            return "译文"
        }], waitForTimeout: {
            if fails { return }
            try await Task.sleep(for: .seconds(15))
        }), copyResult: { _ in false })
        #expect(controller.presentation.translation == .loading)
        #expect(registry.bindings.isEmpty)
        previous()
        mouse()
        controller.performCurrentAction()
        #expect(performed.isEmpty)
        let task = try #require(controller.translationTask)
        await task.value
        #expect(controller.presentation.translation == (fails ? .failed : .result(text: "译文", copied: nil)))
        #expect(controller.presentation.detection == Self.detection)
        #expect(controller.actionHotkeys.isEmpty)
        controller.performCurrentAction()
        #expect(performed.isEmpty)
    }

    @Test
    func dismissingViewStateCannotReacquireBindingsOrPerformActions() {
        let registry = Registry()
        let controller = makeController(registry)
        controller.present(Self.detection, visualStyle: .transparent)
        controller.dismiss()
        // The native fade retains its old view state until the animation completes.
        controller.presentation.detection = Self.detection
        controller.setTriggers(hotkey: ClipboardAssistantDefaults.triggerHotkey, mouseButton: 3)
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        controller.performCurrentAction()
        #expect(performed.isEmpty)
        #expect(registry.bindings.isEmpty)
        controller.present(Self.detection, visualStyle: .transparent)
        #expect(registry.hotkeys.count == 3)
        controller.dismiss(animated: false)
    }

    @Test
    func translationActionKeepsItsNewPresentationAfterPerformReturns() async throws {
        let registry = Registry()
        let controller = makeController(registry)
        defer { controller.dismiss(animated: false) }
        controller.present(.init(kind: .nonSystemLanguageText, title: "fixture", actions: [.autoTranslate("fixture")]),
                           visualStyle: .transparent)
        controller.onPerformAction = { [weak controller] _ in
            controller?.translate("fixture", targetLanguage: "zh-CN", service: .init(providers: [{ _, _ in "译文" }]),
                                  copyResult: { _ in false })
        }
        try registry.callback(keyCode: UInt32(kVK_ANSI_1))()
        #expect(controller.presentation.translation == .loading)
        #expect(registry.bindings.isEmpty)
        let task = try #require(controller.translationTask)
        await task.value
        #expect(controller.presentation.translation == .result(text: "译文", copied: nil))
        #expect(controller.presentation.detection != nil)
    }

    @Test(arguments: [false, true], [0, 3])
    func dismissShortcutClosesPromptsWithoutPerformingAnAction(custom: Bool, actionCount: Int) throws {
        let registry = Registry()
        let hotkey = custom ? Self.hotkey(UInt32(kVK_ANSI_D), "D") : ClipboardAssistantDefaults.dismissHotkey
        let controller = makeController(registry, dismissHotkey: hotkey)
        defer { controller.dismiss(animated: false) }
        #expect(registry.bindings.isEmpty, "关闭键只在存在弹窗时注册")
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        controller.present(.init(kind: .text, title: "fixture", actions: Array(Self.actions.prefix(actionCount))),
                           visualStyle: .transparent)
        try registry.callback(keyCode: hotkey.keyCode)()
        #expect(controller.presentation.detection == nil)
        #expect(performed.isEmpty)
        #expect(registry.bindings.isEmpty)
    }

    @Test(arguments: [false, true])
    func clearingEitherShortcutPreservesTheOtherAndTheMouseTrigger(clearDismiss: Bool) throws {
        let registry = Registry()
        let controller = makeController(registry, dismissHotkey: ClipboardAssistantDefaults.dismissHotkey)
        defer { controller.dismiss(animated: false) }
        controller.present(Self.detection, visualStyle: .transparent)
        let oldDismiss = try registry.callback(keyCode: UInt32(kVK_Delete))
        let oldAction = try registry.callback(keyCode: UInt32(kVK_ANSI_2))
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        controller.setTriggers(
            hotkey: clearDismiss ? ClipboardAssistantDefaults.triggerHotkey : nil,
            mouseButton: 3,
            dismissHotkey: clearDismiss ? nil : ClipboardAssistantDefaults.dismissHotkey
        )
        oldDismiss()
        oldAction()
        #expect(controller.presentation.detection == Self.detection)
        #expect(performed.isEmpty)
        #expect(registry.hotkeys.count == (clearDismiss ? 3 : 1))
        #expect(controller.actionHotkeys.isEmpty == !clearDismiss)
        let mouse = try #require(registry.bindings.values.first { $0.mouseButton == 3 }?.callback)
        mouse()
        #expect(performed == [Self.actions[0]])
        controller.present(Self.detection, visualStyle: .transparent)
        if clearDismiss {
            #expect(!registry.hotkeys.contains { $0.keyCode == UInt32(kVK_Delete) })
            try registry.callback(keyCode: UInt32(kVK_ANSI_2))()
            #expect(performed == [Self.actions[0], Self.actions[1]])
        } else {
            try registry.callback(keyCode: UInt32(kVK_Delete))()
            #expect(performed == [Self.actions[0]])
        }
        #expect(controller.presentation.detection == nil)
        #expect(registry.bindings.isEmpty)
    }

    @Test(arguments: ["replacement", "update", "configuration", "dismiss"])
    func obsoleteDismissCallbacksCannotCloseTheCurrentPrompt(reason: String) throws {
        let registry = Registry()
        let controller = makeController(registry, dismissHotkey: ClipboardAssistantDefaults.dismissHotkey)
        defer { controller.dismiss(animated: false) }
        let generation = try #require(controller.present(Self.detection, visualStyle: .transparent))
        let previous = try registry.callback(keyCode: UInt32(kVK_Delete))
        let current = ClipboardAssistantDetection(kind: .text, title: "current", actions: Self.detection.actions)
        switch reason {
        case "update": controller.updateDetection(current, for: generation)
        case "configuration":
            controller.setTriggers(hotkey: ClipboardAssistantDefaults.triggerHotkey, mouseButton: 3,
                                   dismissHotkey: ClipboardAssistantDefaults.dismissHotkey)
        default:
            if reason == "dismiss" { controller.dismiss(animated: false) }
            controller.present(current, visualStyle: .transparent)
        }
        previous()
        #expect(controller.presentation.detection == (reason == "configuration" ? Self.detection : current))
        try registry.callback(keyCode: UInt32(kVK_Delete))()
        #expect(controller.presentation.detection == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func dismissShortcutCancelsTranslationAndRejectsUncooperativeLateResults() async throws {
        let registry = Registry()
        let controller = makeController(registry, dismissHotkey: ClipboardAssistantDefaults.dismissHotkey)
        defer { controller.dismiss(animated: false) }
        controller.present(Self.detection, visualStyle: .transparent)
        let oldDismiss = try registry.callback(keyCode: UInt32(kVK_Delete))
        let gate = DismissTranslationGate()
        var copies: [String] = []
        controller.translate("fixture", targetLanguage: "zh-CN",
                             service: .init(providers: [{ _, _ in await gate.wait() }])) {
            copies.append($0)
            return true
        }
        let task = try #require(controller.translationTask)
        let generation = controller.presentation.translationGeneration
        let close = try registry.callback(keyCode: UInt32(kVK_Delete))
        #expect(await XCTWaiter.fulfillment(of: [gate.started], timeout: 3) == .completed)
        oldDismiss()
        #expect(controller.presentation.translation == .loading, "旧提示的关闭回调不能关闭新的翻译状态")
        #expect(registry.hotkeys == [ClipboardAssistantDefaults.dismissHotkey])
        close()
        #expect(task.isCancelled)
        #expect(controller.translationTask == nil)
        #expect(controller.presentation.detection == nil)
        #expect(registry.bindings.isEmpty)
        await task.value
        #expect(await XCTWaiter.fulfillment(of: [gate.cancelled], timeout: 3) == .completed)
        await gate.resolve("迟到译文")
        #expect(await XCTWaiter.fulfillment(of: [gate.returned], timeout: 3) == .completed)
        controller.translationWindowDidAppear(for: generation)
        controller.translationDidAppear(.result(text: "迟到译文", copied: nil), for: generation,
                                        rowWidth: 240, locale: Locale(identifier: "zh-Hans"))
        #expect(copies.isEmpty, "关闭后的迟到译文不得写入剪贴板")
        #expect(controller.presentation.translation == nil)
        #expect(controller.presentation.detection == nil)
        controller.present(Self.detection, visualStyle: .transparent)
        close()
        #expect(controller.presentation.detection == Self.detection)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["pendingResult", "visibleResult", "failed"])
    func dismissShortcutClosesFinalTranslationStatesAndInvalidatesDisplayCallbacks(state: String) async throws {
        let registry = Registry()
        let controller = makeController(registry, dismissHotkey: ClipboardAssistantDefaults.dismissHotkey)
        defer { controller.dismiss(animated: false) }
        controller.present(Self.detection, visualStyle: .transparent)
        let service = state == "failed"
            ? ClipboardTranslationService(providers: [], waitForTimeout: {})
            : ClipboardTranslationService(providers: [{ _, _ in "译文" }])
        var copies: [String] = []
        controller.translate("fixture", targetLanguage: "zh-CN", service: service) {
            copies.append($0)
            return true
        }
        let task = try #require(controller.translationTask)
        await task.value
        let generation = controller.presentation.translationGeneration
        let shown: ClipboardTranslationPresentation = state == "failed" ? .failed : .result(text: "译文", copied: nil)
        #expect(controller.presentation.translation == shown)
        if state == "visibleResult" {
            controller.translationWindowDidAppear(for: generation)
            controller.translationDidAppear(shown, for: generation, rowWidth: 240, locale: Locale(identifier: "zh-Hans"))
        }
        try registry.callback(keyCode: UInt32(kVK_Delete))()
        controller.translationWindowDidAppear(for: generation)
        controller.translationDidAppear(shown, for: generation, rowWidth: 240, locale: Locale(identifier: "zh-Hans"))
        #expect(copies == (state == "visibleResult" ? ["译文"] : []))
        #expect(controller.presentation.detection == nil)
        #expect(controller.presentation.translation == nil)
        #expect(registry.bindings.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func screenshotSessionsSuspendDismissAndRestoreOnlyTheCurrentBinding(system: Bool, translated: Bool) async throws {
        let registry = Registry()
        let controller = makeController(registry, dismissHotkey: ClipboardAssistantDefaults.dismissHotkey)
        defer { controller.dismiss(animated: false) }
        controller.present(Self.detection, visualStyle: .transparent)
        if translated {
            controller.translate("fixture", targetLanguage: "zh-CN", service: .init(providers: [{ _, _ in "译文" }]),
                                 copyResult: { _ in Issue.record("此测试未显示译文，不得复制"); return false })
            let task = try #require(controller.translationTask)
            await task.value
        }
        let previous = try registry.callback(keyCode: UInt32(kVK_Delete))
        if system {
            controller.setSystemScreenshotActive(true)
        } else {
            controller.setScreenshotActive(true)
            #expect(registry.bindings.isEmpty)
            controller.setScreenshotSelectionActive(true)
        }
        #expect(registry.bindings.isEmpty)
        previous()
        #expect(controller.presentation.detection == Self.detection)
        if system {
            controller.setSystemScreenshotActive(false)
        } else {
            controller.setScreenshotSelectionActive(false)
            #expect(registry.bindings.isEmpty)
            controller.setScreenshotActive(false)
        }
        previous()
        #expect(controller.presentation.detection == Self.detection)
        #expect(controller.presentation.translation == (translated ? .result(text: "译文", copied: nil) : nil))
        try registry.callback(keyCode: UInt32(kVK_Delete))()
        #expect(controller.presentation.detection == nil)
        #expect(registry.bindings.isEmpty)
    }

    @Test
    func lockingReleasesDismissAndDoesNotRestoreTheOldPromptOnUnlock() throws {
        let registry = Registry()
        let controller = makeController(registry, dismissHotkey: ClipboardAssistantDefaults.dismissHotkey)
        defer { controller.dismiss(animated: false) }
        controller.present(Self.detection, visualStyle: .transparent)
        let previous = try registry.callback(keyCode: UInt32(kVK_Delete))
        controller.setScreenLocked(true)
        #expect(registry.bindings.isEmpty)
        #expect(controller.presentation.detection == nil)
        #expect(controller.present(Self.detection, visualStyle: .transparent) == nil)
        controller.setScreenLocked(false)
        #expect(registry.bindings.isEmpty)
        #expect(controller.presentation.detection == nil)
        controller.present(Self.detection, visualStyle: .transparent)
        previous()
        #expect(controller.presentation.detection == Self.detection)
        try registry.callback(keyCode: UInt32(kVK_Delete))()
        #expect(controller.presentation.detection == nil)
    }

    @Test(arguments: [false, true])
    func dismissTakesPriorityOverConflictingPrimaryOrNumberedActions(primaryConflict: Bool) throws {
        let registry = Registry()
        let controller = makeController(registry)
        defer { controller.dismiss(animated: false) }
        let primary = primaryConflict ? Self.hotkey(UInt32(kVK_ANSI_N), "N") : ClipboardAssistantDefaults.triggerHotkey
        let close = primaryConflict ? Self.hotkey(UInt32(kVK_ANSI_N), "alternate label") : Self.hotkey(UInt32(kVK_ANSI_2), "2")
        controller.setTriggers(hotkey: primary, mouseButton: 3, dismissHotkey: close)
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        controller.present(Self.detection, visualStyle: .transparent)
        #expect(registry.hotkeys.filter { $0.conflicts(with: close) }.count == 1)
        #expect(controller.dismissShortcutFeedbackKey == Self.dismissConflictKey)
        #expect(controller.shortcutHint(for: Self.actions[0]) == "⌘ 1")
        #expect(controller.shortcutHint(for: Self.actions[1]) == (primaryConflict ? "⌘ 2" : nil))
        try registry.callback(keyCode: close.keyCode)()
        #expect(performed.isEmpty)
        #expect(controller.presentation.detection == nil)
        controller.present(Self.detection, visualStyle: .transparent)
        let mouse = try #require(registry.bindings.values.first { $0.mouseButton == 3 }?.callback)
        mouse()
        #expect(performed == [Self.actions[0]])
    }

    @Test(arguments: [GlobalHotkeyRegistrationResult.registrationFailed, .inputMonitoringPermissionRequired])
    func dismissRegistrationFailuresReportAfterAnAttemptAndRecoverOnTheNextPrompt(failure: GlobalHotkeyRegistrationResult) throws {
        let registry = Registry()
        registry.failures[UInt32(kVK_Delete)] = failure
        let controller = makeController(registry, dismissHotkey: ClipboardAssistantDefaults.dismissHotkey)
        defer { controller.dismiss(animated: false) }
        #expect(controller.dismissShortcutFeedbackKey == nil)
        #expect(SettingsView.clipboardAssistantDismissFeedbackKey(in: FeatureSettings(), registrationFeedback: nil) == nil)
        controller.present(Self.detection, visualStyle: .transparent)
        #expect(controller.dismissShortcutFeedbackKey == Self.dismissFailureKey)
        #expect(registry.hotkeys.count == 3)
        #expect(controller.shortcutHint(for: Self.actions[0]) == "⌘ 1")
        let hasPermission = controller.setTriggers(hotkey: ClipboardAssistantDefaults.triggerHotkey, mouseButton: nil,
                                                  dismissHotkey: ClipboardAssistantDefaults.dismissHotkey)
        #expect(hasPermission == (failure != .inputMonitoringPermissionRequired))
        registry.failures = [:]
        controller.present(Self.detection, visualStyle: .transparent)
        #expect(controller.dismissShortcutFeedbackKey == nil)
        try registry.callback(keyCode: UInt32(kVK_Delete))()
        #expect(controller.presentation.detection == nil)
    }

    @Test
    func settingsReportsPrimaryAndEveryNumberedConflictBeforeAPromptExists() {
        let primary = Self.hotkey(UInt32(kVK_ANSI_N), "N")
        for close in [primary] + Self.keyCodes.enumerated().map({ Self.hotkey($0.element, String(($0.offset + 1) % 10)) }) {
            let settings = FeatureSettings(
                clipboardAssistantTriggerConfiguration: .hotkey(primary),
                clipboardAssistantDismissConfiguration: .hotkey(close)
            )
            #expect(SettingsView.clipboardAssistantDismissFeedbackKey(in: settings, registrationFeedback: nil) == Self.dismissConflictKey)
            #expect(SettingsView.clipboardAssistantDismissFeedbackKey(in: settings, registrationFeedback: Self.dismissFailureKey) == Self.dismissFailureKey,
                    "实际注册失败优先于配置冲突提示，不能宣称关闭键已生效")
        }
    }

    @Test(arguments: ["disabled", "dismissCleared", "primaryCleared", "differentModifiers"])
    func settingsDoesNotWarnAboutInactiveOrNonconflictingDismissConfiguration(reason: String) {
        var settings = FeatureSettings(clipboardAssistantDismissConfiguration: .hotkey(Self.hotkey(UInt32(kVK_ANSI_2), "2")))
        switch reason {
        case "disabled": settings.clipboardAssistantEnabled = false
        case "dismissCleared": settings.clipboardAssistantDismissConfiguration = .none
        case "primaryCleared": settings.clipboardAssistantTriggerConfiguration = .none
        default:
            settings.clipboardAssistantDismissConfiguration = .hotkey(.init(
                keyCode: UInt32(kVK_ANSI_2), carbonModifiers: UInt32(cmdKey | shiftKey), keyDisplayName: "2"
            ))
        }
        let feedback = reason == "disabled" || reason == "dismissCleared" ? Self.dismissFailureKey : nil
        #expect(SettingsView.clipboardAssistantDismissFeedbackKey(in: settings, registrationFeedback: feedback) == nil)
    }

    @Test
    func dismissSettingsKeysAndPlaceholdersResolveInAllSeventeenLocales() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let keyPattern = try NSRegularExpression(pattern: "\"([^\"\\n]*(?:关闭弹窗快捷键|关闭当前弹窗)[^\"\\n]*)\"")
        var keys = Set<String>()
        for file in ["SettingsView.swift", "ClipboardAssistantWindowController.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/\(file)"), encoding: .utf8)
            for match in keyPattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                let range = try #require(Range(match.range(at: 1), in: source))
                keys.insert(String(source[range]))
            }
        }
        #expect(keys.count == 5)
        #expect(AppLanguage.allCases.count == 17)
        let placeholderPattern = try NSRegularExpression(pattern: #"%[0-9$.]*[a-zA-Z@]"#)
        func placeholders(_ text: String) -> [String] {
            placeholderPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range, in: text).map { String(text[$0]) }
            }.sorted()
        }
        for language in AppLanguage.allCases {
            let file = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: file) as? [String: String])
            for key in keys {
                let localized = try #require(table[key], "\(language.rawValue) 缺少关闭快捷键文案：\(key)")
                #expect(!localized.isEmpty)
                #expect(placeholders(localized) == placeholders(key), "\(language.rawValue) 的快捷键占位符不匹配")
                #expect(AppLocalization.string(key, locale: language.locale) == localized)
                if language != .simplifiedChinese {
                    #expect(localized != key, "\(language.rawValue) 没有翻译关闭快捷键文案：\(key)")
                }
            }
        }
        #expect(AppLocalization.string("关闭弹窗快捷键", locale: Locale(identifier: "en")) == "Dismiss Popup Shortcut")
        #expect(AppLocalization.string("关闭弹窗快捷键", locale: Locale(identifier: "ar")) == "اختصار إغلاق النافذة المنبثقة")
    }

    @Test
    func controllerLifetimeReleasesEveryRegistration() {
        let registry = Registry()
        do {
            let controller = makeController(registry, dismissHotkey: ClipboardAssistantDefaults.dismissHotkey)
            controller.present(Self.detection, visualStyle: .transparent)
            #expect(registry.hotkeys.count == 4)
        }
        #expect(registry.bindings.isEmpty)
    }

    @Test(arguments: [GlobalHotkeyRegistrationResult.registered, .registrationFailed, .inputMonitoringPermissionRequired])
    func monitorOnlyPublishesSuccessfulRegistrations(result: GlobalHotkeyRegistrationResult) {
        var active = false
        let monitor = ClipboardAssistantTriggerMonitor(registerHotkey: { _, _ in
            active = true
            return (result, { active = false })
        })
        let hotkey = ClipboardAssistantDefaults.triggerHotkey
        #expect(monitor.apply(hotkey: hotkey, mouseButton: nil, onTrigger: {}) == (result != .inputMonitoringPermissionRequired))
        #expect(monitor.registeredHotkey == (result == .registered ? hotkey : nil))
        monitor.stop()
        #expect(!active)
        #expect(monitor.registeredHotkey == nil)
    }

    @Test
    func monitorReplacesCallbackWhenAnIdenticalHotkeyIsReapplied() throws {
        var callback: (() -> Void)?
        var performed: [Int] = []
        let monitor = ClipboardAssistantTriggerMonitor(registerHotkey: { _, action in
            callback = action
            return (.registered, { callback = nil })
        })
        defer { monitor.stop() }
        monitor.apply(hotkey: ClipboardAssistantDefaults.triggerHotkey, mouseButton: nil) { performed.append(1) }
        monitor.apply(hotkey: ClipboardAssistantDefaults.triggerHotkey, mouseButton: nil) { performed.append(2) }
        let latestCallback = try #require(callback)
        latestCallback()
        #expect(performed == [2])
    }

    private func makeController(
        _ registry: Registry,
        dismissHotkey: VoiceInputHotkeyPreset? = nil
    ) -> ClipboardAssistantController {
        let controller = ClipboardAssistantController(
            windowPresenter: { _, _ in }, makeTriggerMonitor: { registry.makeMonitor() }
        )
        controller.displayDuration = .never
        controller.setTriggers(hotkey: ClipboardAssistantDefaults.triggerHotkey, mouseButton: nil, dismissHotkey: dismissHotkey)
        return controller
    }

    private static func hotkey(_ code: UInt32, _ name: String) -> VoiceInputHotkeyPreset {
        .init(keyCode: code, carbonModifiers: UInt32(cmdKey), keyDisplayName: name)
    }

    private static let keyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                   kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0].map(UInt32.init)
    private static let dismissConflictKey = "关闭弹窗快捷键与动作快捷键相同，当前优先关闭弹窗"
    private static let dismissFailureKey = "关闭弹窗快捷键未能启用，请检查快捷键冲突或输入监控权限"
    private static let actions: [ClipboardAssistantAction] = [
        .search("fixture"), .translate("fixture"), .copyText("fixture"), .copyFullExpression("fixture"),
        .composeMail("fixture@example.invalid"), .callPhone("123"), .copyEmoji("🙂"),
        .saveText("fixture"), .addToQuickNote, .sendToTeleprompter, .share,
    ]
    private static var detection: ClipboardAssistantDetection {
        .init(kind: .text, title: "fixture", actions: Array(actions.prefix(3)))
    }

    @MainActor
    private final class Registry {
        struct Binding {
            let hotkey: VoiceInputHotkeyPreset?
            let mouseButton: Int?
            let callback: () -> Void
        }
        var bindings: [UUID: Binding] = [:]
        var failures: [UInt32: GlobalHotkeyRegistrationResult] = [:]
        var hotkeys: [VoiceInputHotkeyPreset] { bindings.values.compactMap(\.hotkey) }
        func makeMonitor() -> any ClipboardAssistantTriggerRegistering { Monitor(registry: self) }
        func callback(keyCode: UInt32) throws -> () -> Void {
            try #require(bindings.values.first { $0.hotkey?.keyCode == keyCode }?.callback)
        }
    }

    private final class Monitor: ClipboardAssistantTriggerRegistering {
        let id = UUID()
        let registry: Registry
        private(set) var registeredHotkey: VoiceInputHotkeyPreset?
        init(registry: Registry) { self.registry = registry }
        func apply(hotkey: VoiceInputHotkeyPreset?, mouseButton: Int?, onTrigger: @escaping () -> Void) -> Bool {
            stop()
            let result = hotkey.flatMap { registry.failures[$0.keyCode] } ?? .registered
            registeredHotkey = result == .registered ? hotkey : nil
            if registeredHotkey != nil || mouseButton != nil {
                registry.bindings[id] = .init(hotkey: registeredHotkey, mouseButton: mouseButton, callback: onTrigger)
            }
            return result != .inputMonitoringPermissionRequired
        }
        func stop() {
            registry.bindings[id] = nil
            registeredHotkey = nil
        }
    }
}

private actor DismissTranslationGate {
    nonisolated let started = XCTestExpectation(description: "翻译请求已启动")
    nonisolated let cancelled = XCTestExpectation(description: "关闭快捷键取消翻译服务")
    nonisolated let returned = XCTestExpectation(description: "不配合取消的翻译服务已返回")
    private var continuation: CheckedContinuation<String, Never>?
    private var value: String?

    func wait() async -> String {
        started.fulfill()
        defer { returned.fulfill() }
        return await withTaskCancellationHandler {
            if let value { return value }
            return await withCheckedContinuation { continuation = $0 }
        } onCancel: {
            self.cancelled.fulfill()
        }
    }

    func resolve(_ value: String) {
        self.value = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}
