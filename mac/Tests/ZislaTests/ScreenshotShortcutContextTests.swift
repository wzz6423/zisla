import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenshotShortcutContextTests {
    @Test
    func contextDistinguishesSelectionEditorsAndMultiplePinnedWindows() {
        #expect(ScreenshotHotkeyContext.shouldSuspend(selecting: true, editors: []))
        #expect(ScreenshotHotkeyContext.shouldSuspend(selecting: false, editors: [(false, false)]))
        #expect(!ScreenshotHotkeyContext.shouldSuspend(selecting: false, editors: [(true, false), (true, false)]))
        #expect(ScreenshotHotkeyContext.shouldSuspend(selecting: false, editors: [(true, true), (true, false)]))
        #expect(!ScreenshotHotkeyContext.shouldSuspend(selecting: false, editors: []))
    }

    @Test
    func olderPinnedEscapeRegistrationsYieldToSelectionAndEditorThenResumeTogether() throws {
        let suiteName = "Zisla.ScreenshotShortcutContext.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = FeatureSettingsStore(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let image = NSImage(size: CGSize(width: 40, height: 40))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 40).fill()
        image.unlockFocus()
        let pixels = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var closedEditors = 0
        let editors = (0..<3).map { _ in
            ScreenshotEditorWindowController(image: image, screenImage: image,
                screenCGImage: pixels, screen: nil,
                captureRect: CGRect(x: 0, y: 0, width: 40, height: 40),
                capturedApplication: nil, settingsStore: store, onStash: { _, _ in },
                onClose: { closedEditors += 1 })
        }
        defer { editors.forEach { $0.close() } }
        for editor in editors { editor.window?.alphaValue = 0 }
        let pinned = Array(editors.prefix(2))
        pinned.forEach { $0.setPinned(true) }
        let global = GlobalHotkeyManager()
        defer { global.unregister() }
        let flags = UInt32(controlKey | optionKey | cmdKey | shiftKey)
        let keys = [UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19)]
        let managers = pinned.map(\.pinnedEscapeHotkeyManager) + [global]
        var presses = 0
        for (manager, key) in zip(managers, keys) {
            #expect(manager.register(keyCode: key, modifiers: flags, action: { presses += 1 }) == .registered)
        }

        ScreenshotHotkeyContext.update(selecting: true, editors: pinned, globalManagers: [global])
        for (manager, key) in zip(managers, keys) {
            #expect(manager.isSuspended)
            #expect(!manager.hasActiveRegistration)
            #expect(try sendHotkeyPressed(keyCode: key, modifiers: flags) == eventNotHandledErr)
        }
        #expect(presses == 0)
        ScreenshotHotkeyContext.update(selecting: false, editors: editors, globalManagers: [global])
        #expect(managers.allSatisfy { $0.isSuspended })
        let currentWindow = try #require(editors[2].window as? ScreenshotEditorWindow)
        #expect(currentWindow.performKeyEquivalent(with: try event(window: currentWindow, key: "\u{1b}", code: 53)))
        #expect(closedEditors == 1)
        #expect(pinned.allSatisfy { $0.window?.contentView != nil })

        ScreenshotHotkeyContext.update(selecting: false, editors: pinned, globalManagers: [global])
        for (manager, key) in zip(managers, keys) {
            #expect(!manager.isSuspended)
            #expect(manager.hasActiveRegistration)
            #expect(try sendHotkeyPressed(keyCode: key, modifiers: flags) == noErr)
        }
        #expect(presses == 3)
    }

    @Test
    func focusedPinsAllowBothCaptureHotkeysAndSurviveSelectionAndEditorCancellation() async throws {
        let suiteName = "Zisla.ScreenshotShortcutContext.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = FeatureSettingsStore(defaults: defaults)
        defer {
            store.flushPendingChanges()
            defaults.removePersistentDomain(forName: suiteName)
        }
        var closedEditors = 0
        let pins = try (0..<2).map { index in
            try syntheticEditor(settingsStore: store, keyWindow: index == 0 ? true : nil,
                onClose: { closedEditors += 1 })
        }
        defer { pins.forEach { $0.close() } }
        for pin in pins {
            pin.setPinned(true)
            let hosting = try #require(pin.window?.contentView as? NSHostingView<ScreenshotPinnedImageView>)
            hosting.sizingOptions = []
            pin.setPinnedScale(1.4)
            pin.setPinnedOpacity(0.45)
        }
        let firstWindow = try #require(pins[0].window)
        let views = try pins.map { try #require($0.window?.contentView) }
        let frames = pins.map { $0.window?.frame }
        try #require(firstWindow.isKeyWindow)
        #expect(!firstWindow.isVisible, "Injected focus must not present a window")

        let image = try #require((views[0] as? NSHostingView<ScreenshotPinnedImageView>)?.rootView.image)
        let pixels = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let screen = try #require(NSScreen.screens.first)
        let capture = GlobalHotkeyManager()
        let longCapture = GlobalHotkeyManager()
        let globals = [capture, longCapture]
        let flags = UInt32(controlKey | optionKey | cmdKey | shiftKey)
        let captureKeys = [UInt32(kVK_F17), UInt32(kVK_F18)]
        let escapeKeys = [UInt32(kVK_F19), UInt32(kVK_F20)]
        defer {
            (globals + pins.map(\.pinnedEscapeHotkeyManager)).forEach { $0.unregister() }
        }
        for (pin, key) in zip(pins, escapeKeys) {
            let result = pin.pinnedEscapeHotkeyManager.register(keyCode: key, modifiers: flags,
                action: { [weak pin] in pin?.close() })
            #expect(result == .registered)
        }
        var panels: [ScreenshotSelectionPanel] = []
        let selection = ScreenshotSelectionController(
            captureScreen: { _ in (image, pixels, nil) },
            presentPanels: { panels = $0 },
            snapTargets: { _ in [] }
        )
        defer { selection.cancel() }
        selection.onSelectionWillPresent = {
            ScreenshotHotkeyContext.update(selecting: true, editors: pins, globalManagers: globals)
        }
        selection.onCancelled = {
            ScreenshotHotkeyContext.update(selecting: false, editors: pins, globalManagers: globals)
        }
        var captureTask: Task<Void, Never>?
        var requestedCapture: UInt32?
        for (manager, key) in zip(globals, captureKeys) {
            #expect(manager.register(keyCode: key, modifiers: flags, action: {
                requestedCapture = key
                captureTask = Task { await selection.start(on: [screen, screen]) }
            }) == .registered)
        }
        ScreenshotHotkeyContext.update(selecting: false, editors: pins, globalManagers: globals)
        #expect(globals.allSatisfy { !$0.isSuspended && $0.hasActiveRegistration },
            "Focused pins must leave both capture registrations active")
        #expect(pins.allSatisfy { $0.pinnedEscapeHotkeyManager.isSuspended },
            "Focused pins must keep global Escape from claiming the local cancel key")

        for key in captureKeys {
            captureTask = nil
            #expect(try sendHotkeyPressed(keyCode: key, modifiers: flags) == noErr)
            await (try #require(captureTask)).value
            #expect(requestedCapture == key)
            #expect(selection.selectionWindowCount == 2)
            #expect(globals.allSatisfy { $0.isSuspended && !$0.hasActiveRegistration })
            for escapeKey in escapeKeys {
                #expect(try sendHotkeyPressed(keyCode: escapeKey, modifiers: flags) == eventNotHandledErr)
            }
            let panel = try #require(panels.first)
            panel.cancelOperation(nil)
            #expect(selection.selectionWindowCount == 0)
            #expect(panels.allSatisfy { $0.contentView == nil && !$0.isVisible })
            #expect(globals.allSatisfy { !$0.isSuspended && $0.hasActiveRegistration })
        }

        let editor = try syntheticEditor(settingsStore: store, onClose: { closedEditors += 1 })
        defer { editor.close() }
        ScreenshotHotkeyContext.update(selecting: false, editors: pins + [editor], globalManagers: globals)
        #expect(globals.allSatisfy { $0.isSuspended && !$0.hasActiveRegistration },
            "A new unpinned editor must suspend capture even with older pins present")
        let editorWindow = try #require(editor.window as? ScreenshotEditorWindow)
        #expect(editorWindow.performKeyEquivalent(with: try event(window: editorWindow, key: "\u{1b}", code: 53)))
        ScreenshotHotkeyContext.update(selecting: false, editors: pins, globalManagers: globals)
        #expect(closedEditors == 1, "Escape must retire only the new editor")
        #expect(globals.allSatisfy { !$0.isSuspended && $0.hasActiveRegistration })
        for (index, pin) in pins.enumerated() {
            #expect(pin.isPinnedPresentation && pin.window?.contentView === views[index])
            #expect(pin.window?.frame == frames[index])
            #expect(pin.pinnedScale == 1.4 && pin.pinnedOpacity == 0.45)
        }
    }

    @Test(arguments: [
        (global: "capture", local: "pin", defaults: true),
        (global: "long", local: "stash", defaults: true),
        (global: "capture", local: "pin", defaults: false),
        (global: "capture", local: "stash", defaults: false),
        (global: "long", local: "pin", defaults: false),
        (global: "long", local: "stash", defaults: false),
    ])
    func pinnedLocalShortcutsYieldToConfiguredCaptureWithoutClosingOrStashing(
        global: String, local: String, defaults: Bool
    ) throws {
        let suiteName = "Zisla.ScreenshotShortcutContext.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        let store = FeatureSettingsStore(defaults: userDefaults)
        defer {
            store.flushPendingChanges()
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        if !defaults {
            store.settings.screenshotHotkey = .init(keyCode: UInt32(kVK_F17), carbonModifiers: 0x1B00, keyDisplayName: "F17")
            store.settings.screenshotLongHotkey = .init(keyCode: UInt32(kVK_F18), carbonModifiers: 0x1B00, keyDisplayName: "F18")
        }
        let hotkey = global == "capture" ? store.settings.screenshotHotkey : store.settings.screenshotLongHotkey
        if local == "pin" { store.settings.screenshotPinHotkey = hotkey }
        else { store.settings.screenshotStashHotkey = hotkey }
        var closeCount = 0
        var stashedImages: [Data] = []
        let controller = try syntheticEditor(settingsStore: store,
            onStash: { data, _ in stashedImages.append(data) }, onClose: { closeCount += 1 })
        defer { controller.close() }
        controller.setPinned(true)
        let window = try #require(controller.window as? ScreenshotEditorWindow)
        let view = try #require(window.contentView)
        let frame = window.frame
        let consumed = controller.performEditorShortcut(keyCode: hotkey.keyCode, modifiers: hotkey.carbonModifiers)
        #expect(!consumed)
        let eventFlags: NSEvent.ModifierFlags = defaults ? .control : [.control, .option, .command, .shift]
        #expect(!window.performKeyEquivalent(with: try event(window: window,
            key: hotkey.keyDisplayName, code: UInt16(hotkey.keyCode), flags: eventFlags)))
        #expect(controller.isPinnedPresentation && window.contentView === view)
        #expect(window.frame == frame)
        #expect(closeCount == 0 && stashedImages.isEmpty,
            "Capture shortcuts must preserve the pin even when no global registration is available")
    }

    @Test(arguments: [
        (context: "editor", action: "pin"), (context: "editor", action: "stash"),
        (context: "disabled", action: "pin"), (context: "disabled", action: "stash"),
        (context: "custom", action: "pin"), (context: "custom", action: "stash"),
    ])
    func editorDisabledAndNonconflictingLocalShortcutsKeepTheirExistingActions(context: String, action: String) throws {
        let suiteName = "Zisla.ScreenshotShortcutContext.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = FeatureSettingsStore(defaults: defaults)
        defer {
            store.flushPendingChanges()
            defaults.removePersistentDomain(forName: suiteName)
        }
        if context == "disabled" { store.settings.screenshotEnabled = false }
        if context == "custom" {
            store.settings.screenshotHotkey = .init(keyCode: UInt32(kVK_F17), carbonModifiers: 0x1B00, keyDisplayName: "F17")
            store.settings.screenshotLongHotkey = .init(keyCode: UInt32(kVK_F18), carbonModifiers: 0x1B00, keyDisplayName: "F18")
        }
        var closeCount = 0
        var stashedImages: [Data] = []
        let controller = try syntheticEditor(settingsStore: store,
            onStash: { data, _ in stashedImages.append(data) }, onClose: { closeCount += 1 })
        defer { controller.close() }
        if context != "editor" { controller.setPinned(true) }
        let window = try #require(controller.window as? ScreenshotEditorWindow)
        let hotkey = action == "pin" ? store.settings.screenshotPinHotkey : store.settings.screenshotStashHotkey
        #expect(window.performKeyEquivalent(with: try event(window: window,
            key: hotkey.keyDisplayName, code: UInt16(hotkey.keyCode), flags: .control)))
        if action == "pin" && context == "editor" {
            #expect(controller.isPinnedPresentation && window.contentView != nil)
            #expect(closeCount == 0 && stashedImages.isEmpty)
        } else {
            #expect(closeCount == 1 && window.contentView == nil)
            #expect(stashedImages.count == (action == "stash" ? 1 : 0))
            if let data = stashedImages.first { #expect(NSImage(data: data)?.size == CGSize(width: 40, height: 40)) }
        }
    }

    @Test
    func recordingAndUnavailableCaptureRegistrationsNeverFallBackToClosingPins() throws {
        let suiteName = "Zisla.ScreenshotShortcutContext.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = FeatureSettingsStore(defaults: defaults)
        defer {
            store.flushPendingChanges()
            defaults.removePersistentDomain(forName: suiteName)
        }
        let hotkey = VoiceInputHotkeyPreset(keyCode: UInt32(kVK_F17), carbonModifiers: 0x1B00, keyDisplayName: "F17")
        store.settings.screenshotHotkey = hotkey
        store.settings.screenshotPinHotkey = hotkey
        let controller = try syntheticEditor(settingsStore: store, keyWindow: true)
        defer { controller.close() }
        controller.setPinned(true)
        let window = try #require(controller.window)
        let content = try #require(window.contentView)
        try #require(window.isKeyWindow)
        let capture = GlobalHotkeyManager()
        let occupied = GlobalHotkeyManager()
        defer { capture.unregister(); occupied.unregister() }
        var requestedCapture = false
        #expect(capture.register(keyCode: hotkey.keyCode, modifiers: hotkey.carbonModifiers,
            action: { requestedCapture = true }) == .registered)
        let owner = GlobalHotkeyManager.beginRecording()
        defer { GlobalHotkeyManager.endRecording(owner) }
        ScreenshotHotkeyContext.update(selecting: false, editors: [controller], globalManagers: [capture])
        #expect(capture.isSuspended && !capture.hasActiveRegistration)
        #expect(try sendHotkeyPressed(keyCode: hotkey.keyCode, modifiers: hotkey.carbonModifiers) == eventNotHandledErr)
        #expect(!controller.performEditorShortcut(keyCode: hotkey.keyCode, modifiers: hotkey.carbonModifiers))
        GlobalHotkeyManager.endRecording(owner)
        #expect(!capture.isSuspended && capture.hasActiveRegistration,
            "Finishing hotkey recording must restore capture despite the pin's focus")
        #expect(try sendHotkeyPressed(keyCode: hotkey.keyCode, modifiers: hotkey.carbonModifiers) == noErr)
        #expect(requestedCapture)
        capture.unregister()
        #expect(occupied.register(keyCode: hotkey.keyCode, modifiers: hotkey.carbonModifiers, action: {}) == .registered)
        #expect(capture.register(keyCode: hotkey.keyCode, modifiers: hotkey.carbonModifiers, action: {}) == .registrationFailed)
        #expect(!capture.hasActiveRegistration)
        #expect(!controller.performEditorShortcut(keyCode: hotkey.keyCode, modifiers: hotkey.carbonModifiers))
        #expect(!controller.performEditorShortcut(keyCode: UInt32.max, modifiers: hotkey.carbonModifiers))
        #expect(!controller.performEditorShortcut(keyCode: hotkey.keyCode, modifiers: UInt32(shiftKey)))
        #expect(controller.isPinnedPresentation && window.contentView === content)
    }

    @Test
    func localPinAndStashRouteToExistingActionsAndFailureKeepsContext() throws {
        let suiteName = "Zisla.ScreenshotShortcutContext.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = FeatureSettingsStore(defaults: defaults)
        store.settings.screenshotStashHotkey = .init(keyCode: UInt32(kVK_F16), carbonModifiers: 0x1000, keyDisplayName: "F16")
        defer {
            store.flushPendingChanges()
            defaults.removePersistentDomain(forName: suiteName)
        }
        let image = NSImage(size: CGSize(width: 40, height: 40))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 40).fill()
        image.unlockFocus()
        let pixels = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var fails = true
        var closeCount = 0
        var stashCount = 0
        let controller = ScreenshotEditorWindowController(image: image, screenImage: image,
            screenCGImage: pixels, screen: nil, captureRect: CGRect(x: 0, y: 0, width: 40, height: 40),
            capturedApplication: nil, settingsStore: store, onStash: { _, _ in
                if fails { throw ShortcutStashError() }
                stashCount += 1
            }, onClose: { closeCount += 1 })
        defer { controller.close() }
        let window = try #require(controller.window as? ScreenshotEditorWindow)
        window.alphaValue = 0
        let hosting = try #require(window.contentView as? NSHostingView<AppLanguageEnvironment<ScreenshotEditorView>>)
        let model = hosting.rootView.content.model
        let draft = ScreenshotAnnotation(kind: .text, rect: CGRect(x: 1, y: 1, width: 30, height: 20))
        model.add(draft)
        model.beginTextDraft(id: draft.id, text: "快捷键文字", isNew: true)
        let stash = try event(window: window, key: "F16", code: UInt16(kVK_F16), flags: .control)
        #expect(window.performKeyEquivalent(with: stash))
        #expect(closeCount == 0)
        #expect(model.statusMessage == "暂存快捷键错误")
        #expect(model.annotations.first?.text == "快捷键文字")
        #expect(ScreenshotHotkeyContext.shouldSuspend(selecting: false, editors: [(controller.isPinnedPresentation, false)]))
        var contextChanges = 0
        controller.onHotkeyContextChanged = { contextChanges += 1 }
        #expect(window.performKeyEquivalent(with: try event(window: window, key: "1", code: 18, flags: .control)))
        #expect(controller.isPinnedPresentation)
        #expect(contextChanges > 0)
        #expect(!ScreenshotHotkeyContext.shouldSuspend(selecting: false, editors: [(controller.isPinnedPresentation, false)]))
        fails = false
        #expect(window.performKeyEquivalent(with: stash))
        #expect(closeCount == 1)
        #expect(stashCount == 1)
    }

    @Test
    func textEnterCommitsBeforeCopyAndFixedActionsUseTheActualWindowRoutes() throws {
        let window = ScreenshotEditorWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.alphaValue = 0
        let text = NSTextView()
        window.contentView = text
        #expect(window.makeFirstResponder(text))
        var actions: [String] = []
        window.onConfirm = { actions.append("copy") }
        window.onCommitText = { actions.append("commit") }
        window.onSave = { actions.append("save") }
        window.onUndo = { actions.append("undo") }
        window.onRedo = { actions.append("redo") }
        #expect(window.performKeyEquivalent(with: try event(window: window, key: "\r", code: 36)))
        #expect(actions == ["commit"])
        #expect(window.performKeyEquivalent(with: try event(window: window, key: "\r", code: 36)))
        #expect(window.performKeyEquivalent(with: try event(window: window, key: "s", code: 1, flags: .command)))
        #expect(window.performKeyEquivalent(with: try event(window: window, key: "z", code: 6, flags: .command)))
        #expect(window.performKeyEquivalent(with: try event(window: window, key: "z", code: 6, flags: [.command, .shift])))
        #expect(actions == ["commit", "copy", "save", "undo", "redo"])
        #expect(ScreenshotEditorWindow.fixedShortcuts.map(\.displayName) == ["Enter", "⌘S", "⌘Z", "⌘⇧Z"])
    }

    @Test(arguments: [UInt16(36), UInt16(76)])
    func textEnterThroughWindowDispatchCommitsWithoutInsertingANewline(keyCode: UInt16) throws {
        let window = ScreenshotEditorWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        defer { window.close() }
        let text = NSTextView()
        text.string = "annotation"
        window.contentView = text
        #expect(window.makeFirstResponder(text))
        var actions: [String] = []
        window.onCommitText = { actions.append("commit") }
        window.onConfirm = { actions.append("copy") }

        window.sendEvent(try event(window: window, key: "\r", code: keyCode))
        #expect(actions == ["commit"])
        #expect(text.string == "annotation")
        window.sendEvent(try event(window: window, key: "\r", code: keyCode))
        #expect(actions == ["commit", "copy"])
    }

    @Test(arguments: [true, false])
    func textEnterLeavesMarkedTextAndSingleLineFieldEditorsWithTheirNativeResponder(markedText: Bool) throws {
        let window = ScreenshotEditorWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        defer { window.close() }
        let text = ShortcutInputTextView()
        text.markedText = markedText
        text.isFieldEditor = !markedText
        window.contentView = text
        #expect(window.makeFirstResponder(text))
        var imageActions = 0
        window.onCommitText = { imageActions += 1 }
        window.onConfirm = { imageActions += 1 }
        let enter = try event(window: window, key: "\r", code: 36)

        #expect(!window.performKeyEquivalent(with: enter))
        window.sendEvent(enter)
        #expect(text.receivedKeys == [36])
        #expect(imageActions == 0)
        #expect(window.firstResponder === text)
    }

    @Test
    func voiceAndQuickTriggerRecordingCannotClaimEditorShortcutsFromTheOtherSettingsPages() {
        var settings = FeatureSettings.default
        let custom = VoiceInputHotkeyPreset(keyCode: 15, carbonModifiers: 0x0800, keyDisplayName: "R")
        settings.screenshotStashHotkey = custom
        #expect(SettingsView.conflictingScreenshotAction(forGlobalHotkey: custom, in: settings) == .stash)
        settings.screenshotStashHotkey = ScreenshotHotkeyDefaults.stash
        settings.screenshotEditorLongHotkey = custom
        #expect(SettingsView.conflictingScreenshotAction(forGlobalHotkey: custom, in: settings) == .editorLongCapture)
        settings.screenshotEnabled = false
        #expect(SettingsView.conflictingScreenshotAction(forGlobalHotkey: custom, in: settings) == nil)
    }

    @Test(arguments: ["success", "escape", "focus", "close", "remove"])
    func recordingSuspendsGlobalManagersAndAlwaysReleases(exit: String) throws {
        _ = NSApplication.shared
        let manager = GlobalHotkeyManager()
        #expect(manager.register(keyCode: 64, modifiers: 0x1B00, action: {}) == .registered)
        defer { manager.unregister() }
        let window = SettingsWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.alphaValue = 0
        let recorder = HotkeyRecorderButton(hotkey: ScreenshotHotkeyDefaults.capture, locale: Locale(identifier: "zh-Hans"))
        window.contentView = recorder
        let mouse = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        recorder.mouseDown(with: mouse)
        defer { recorder.stopRecording() }
        #expect(recorder.isRecording)
        #expect(manager.isSuspended)
        #expect(!manager.hasActiveRegistration)
        var recorded: VoiceInputHotkeyPreset?
        recorder.onRecord = { recorded = $0 }
        switch exit {
        case "success":
            #expect(window.performKeyEquivalent(with: try event(window: window, key: "1", code: 18, flags: .control)))
            #expect(recorded?.keyCode == 18)
        case "escape":
            recorder.cancelOperation(nil)
            _ = window.performKeyEquivalent(with: try event(window: window, key: "c", code: 8, flags: .command))
        case "focus": NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        case "close": NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        default: window.contentView = nil
        }
        #expect(!recorder.isRecording)
        #expect(!manager.isSuspended)
        #expect(manager.hasActiveRegistration)
        #expect(!GlobalHotkeyManager.isRecordingHotkeys)
    }

    @Test
    func allConfiguredToolsAndEditorLongCaptureRouteThroughWindowEvents() throws {
        let suiteName = "Zisla.ScreenshotShortcutContext.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = FeatureSettingsStore(defaults: defaults)
        defer {
            store.flushPendingChanges()
            defaults.removePersistentDomain(forName: suiteName)
        }
        let image = NSImage(size: CGSize(width: 40, height: 40))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 40).fill()
        image.unlockFocus()
        let pixels = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let controller = ScreenshotEditorWindowController(image: image, screenImage: image,
            screenCGImage: pixels, screen: nil, captureRect: CGRect(x: 0, y: 0, width: 40, height: 40),
            capturedApplication: nil, settingsStore: store, onStash: { _, _ in }, onClose: {})
        defer { controller.close() }
        let window = try #require(controller.window as? ScreenshotEditorWindow)
        window.alphaValue = 0
        let hosting = try #require(window.contentView as? NSHostingView<AppLanguageEnvironment<ScreenshotEditorView>>)
        let model = hosting.rootView.content.model
        for tool in ScreenshotTool.allCases {
            let hotkey = try #require(store.settings.screenshotToolHotkeys[tool.rawValue])
            #expect(window.performKeyEquivalent(with: try event(window: window, key: hotkey.keyDisplayName,
                code: UInt16(hotkey.keyCode), flags: .control)))
            #expect(model.tool == tool)
        }
        store.settings.screenshotToolHotkeys["rectangle"] = .init(keyCode: 15, carbonModifiers: 0x0800, keyDisplayName: "R")
        #expect(window.performKeyEquivalent(with: try event(window: window, key: "r", code: 15, flags: .option)))
        #expect(model.tool == .rectangle)
        let longCaptureHotkey = store.settings.screenshotEditorLongHotkey
        #expect(window.performKeyEquivalent(with: try event(window: window,
            key: longCaptureHotkey.keyDisplayName, code: UInt16(longCaptureHotkey.keyCode), flags: .control)))
        if NSScreen.screens.isEmpty {
            #expect(model.statusMessage == AppLocalization.text("找不到显示器"))
        } else {
            #expect(model.isLongCapturePreviewing)
            #expect(model.statusMessage == AppLocalization.text("请滚动页面，停止后自动拼接"))
            #expect(window.performKeyEquivalent(with: try event(window: window,
                key: longCaptureHotkey.keyDisplayName, code: UInt16(longCaptureHotkey.keyCode), flags: .control)))
            #expect(model.isLongCapturePreviewing)
        }
        // Close before the asynchronous capture task can request screen access or read the display.
        controller.close()
    }

    private func event(window: NSWindow, key: String, code: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: key,
            charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
    }

    private func syntheticEditor(
        settingsStore: FeatureSettingsStore,
        keyWindow: Bool? = nil,
        onStash: @escaping (Data, ShelfScreenshotMetadata) throws -> Void = { _, _ in },
        onClose: @escaping () -> Void = {}
    ) throws -> ScreenshotEditorWindowController {
        let context = try #require(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8,
            bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        let pixels = try #require(context.makeImage())
        let image = NSImage(cgImage: pixels, size: CGSize(width: 40, height: 40))
        let controller = ScreenshotEditorWindowController(image: image, screenImage: image,
            screenCGImage: pixels, screen: nil, captureRect: CGRect(x: 0, y: 0, width: 40, height: 40),
            capturedApplication: nil, settingsStore: settingsStore, onStash: onStash,
            writeImageToPasteboard: { _ in false }, presentSavePanel: { _, _ in }, onClose: onClose)
        controller.window?.alphaValue = 0
        if let keyWindow {
            let original = try #require(controller.window)
            let replacement = ShortcutContextKeyWindow(contentRect: original.frame,
                styleMask: .borderless, backing: .buffered, defer: false)
            replacement.reportsKeyWindow = keyWindow
            replacement.isReleasedWhenClosed = false
            replacement.alphaValue = 0
            replacement.contentView = original.contentView
            replacement.delegate = controller
            original.delegate = nil
            controller.window = replacement
            original.close()
        }
        return controller
    }

    private func sendHotkeyPressed(keyCode: UInt32, modifiers: UInt32) throws -> OSStatus {
        var createdEvent: EventRef?
        #expect(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
            0, 0, &createdEvent) == noErr)
        let event = try #require(createdEvent)
        defer { ReleaseEvent(event) }
        var hotkeyID = EventHotKeyID(signature: OSType(0x4F524254), id: (keyCode << 16) | (modifiers & 0xFFFF))
        #expect(withUnsafePointer(to: &hotkeyID) { pointer in
            SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                MemoryLayout<EventHotKeyID>.size, pointer)
        } == noErr)
        return SendEventToEventTarget(event, GetApplicationEventTarget())
    }
}

@MainActor
private final class ShortcutContextKeyWindow: NSWindow {
    var reportsKeyWindow = false
    override var isKeyWindow: Bool { reportsKeyWindow }
}

private struct ShortcutStashError: LocalizedError {
    var errorDescription: String? { "暂存快捷键错误" }
}

@MainActor
private final class ShortcutInputTextView: NSTextView {
    var markedText = false
    var receivedKeys: [UInt16] = []

    override func hasMarkedText() -> Bool { markedText }

    override func keyDown(with event: NSEvent) {
        receivedKeys.append(event.keyCode)
    }
}
