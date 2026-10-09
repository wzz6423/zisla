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
    func localPinAndStashRouteToExistingActionsAndFailureKeepsContext() throws {
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
        let stash = try event(window: window, key: "2", code: 19, flags: .control)
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
        #expect(window.performKeyEquivalent(with: try event(window: window, key: "0", code: 29, flags: .control)))
        if NSScreen.screens.isEmpty {
            #expect(model.statusMessage == AppLocalization.text("找不到显示器"))
        } else {
            #expect(model.isLongCapturePreviewing)
            #expect(model.statusMessage == AppLocalization.text("请滚动页面，停止后自动拼接"))
            #expect(window.performKeyEquivalent(with: try event(window: window, key: "0", code: 29, flags: .control)))
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
