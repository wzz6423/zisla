import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
@testable import Zisla
@testable import ZislaKit

@MainActor
struct ContextNoteTests {
    @MainActor
    private final class Fixture {
        let directory: URL
        let defaults: UserDefaults
        let name = "context-note-\(UUID())"
        let settings: FeatureSettingsStore
        let shelf: FileShelfStore
        let location = ContextNoteLocation.window(bundleIdentifier: "test.editor", applicationName: "Editor", title: "Document")
        var observation: ContextNoteObservation
        var controller: ContextNoteController!
        var presented = 0
        var presentedPoints: [CGPoint] = []
        var failedCaptures = 0
        var failurePoints: [CGPoint] = []
        var saved: [FileShelfItem] = []
        var savedPoints: [CGPoint] = []
        var reminders: [UUID] = []
        var reminderPoints: [CGPoint] = []
        var acceptsReminder = true
        var busy = false
        var buttons = 0
        var modifiers: NSEvent.ModifierFlags = .command
        var pressedKeys: Set<CGKeyCode> = [55]
        var nextShake = 0.0

        init(enabled: Bool = true, parentEnabled: Bool = true) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("context-note-ui-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defaults = try #require(UserDefaults(suiteName: name))
            settings = FeatureSettingsStore(defaults: defaults)
            settings.settings.contextNotesEnabled = enabled
            settings.settings.clipboardAssistantEnabled = parentEnabled
            shelf = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
            observation = .location(location)
            controller = ContextNoteController(
                settingsStore: settings, languageStore: AppLanguageStore(defaults: defaults), shelf: shelf,
                captureLocation: { [unowned self] _ in observation },
                currentLocation: { [unowned self] _ in observation },
                canInteract: { [unowned self] in !busy },
                onReminder: { [unowned self] item, point in
                    if acceptsReminder { reminders.append(item.id); reminderPoints.append(point) }
                    return acceptsReminder
                },
                onCaptureFailure: { [unowned self] point in failedCaptures += 1; failurePoints.append(point) },
                onSaved: { [unowned self] item, point in
                    #expect(shelf.items.contains(item))
                    #expect(controller.draft == nil)
                    saved.append(item)
                    savedPoints.append(point)
                },
                pressedMouseButtons: { [unowned self] in buttons },
                modifierFlags: { [unowned self] in modifiers },
                keyIsPressed: { [unowned self] in pressedKeys.contains($0) },
                windowPresenter: { [unowned self] _, point, _ in presented += 1; presentedPoints.append(point) }
            )
        }

        func shake(vertical: Bool = false, interval: Double = 0.1, interaction: PointerEdgeMonitor.Interaction = .moved) {
            let start = nextShake
            nextShake += max(3, interval * 8)
            for index in 0..<6 {
                let offset = index.isMultiple(of: 2) ? 100.0 : 180.0
                controller.handlePointer(at: CGPoint(x: vertical ? 100 : offset, y: vertical ? offset : 100),
                                         interaction: interaction, timestamp: start + Double(index) * interval)
            }
        }

        func close() {
            controller.stop()
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test
    func deliberateHorizontalShakeOpensOnlyOnePersistentDraft() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.shake(vertical: true)
        fixture.shake(interval: 1)
        #expect(fixture.controller.draft == nil)
        fixture.shake()
        let draft = try #require(fixture.controller.draft)
        draft.text = "unsaved"
        fixture.controller.handlePointer(at: CGPoint(x: 5000, y: 5000), interaction: .moved, timestamp: 2)
        fixture.shake()
        fixture.observation = .location(.desktop(displayID: "elsewhere", displayName: "Elsewhere"))
        fixture.controller.checkForReturn(at: .zero)
        #expect(fixture.controller.draft === draft)
        #expect(draft.text == "unsaved")
        #expect(draft.location == fixture.location)
        #expect(fixture.presented == 1)
    }

    @Test
    func naturalShakeThroughPointerThrottlePresentsAnEditableDraft() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        var throttle = PointerEdgeEventThrottle()
        for index in 0...105 {
            let time = Double(index) / 125
            guard throttle.shouldEmit(eventType: .mouseMoved, timestamp: time) else { continue }
            let angle = Double.pi * time / 0.16
            fixture.controller.handlePointer(
                at: CGPoint(x: 600 + 15 * cos(angle), y: 400 + 60 * sin(angle)),
                interaction: .moved, timestamp: time
            )
        }
        let draft = try #require(fixture.controller.draft)
        #expect(fixture.presented == 1)
        #expect(draft.location == fixture.location)
        #expect(draft.text.isEmpty)
        draft.text = "Keep the current location"
        fixture.controller.save()
        #expect(fixture.saved.first?.text == "Keep the current location")
        #expect(fixture.saved.first?.noteLocation == fixture.location)
    }

    @Test(arguments: [NSEvent.ModifierFlags(), .option, .control, .shift, [.command, .shift]])
    func unmodifiedAndWrongShortcutShakesDoNotOpenNotes(modifiers: NSEvent.ModifierFlags) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.modifiers = modifiers
        fixture.shake()
        #expect(fixture.presented == 0)
        #expect(fixture.controller.draft == nil)
        fixture.modifiers = .command
        fixture.shake()
        #expect(fixture.presented == 1)
    }

    @Test(arguments: [CGKeyCode(55), 54])
    func defaultCommandAcceptsEitherSide(key: CGKeyCode) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.pressedKeys = [key]
        fixture.shake()
        #expect(fixture.presented == 1)
    }

    @Test
    func customShortcutRequiresItsKeyAndModifiersAndTakesEffectImmediately() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.settings.settings.contextNoteHoldHotkey = .controlSpace
        fixture.shake()
        fixture.modifiers = .control
        fixture.pressedKeys = [59]
        fixture.shake()
        #expect(fixture.presented == 0)
        fixture.pressedKeys.insert(49)
        fixture.shake()
        #expect(fixture.presented == 1)
    }

    @Test
    func customModifierRespectsTheRecordedSide() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.settings.settings.contextNoteHoldHotkey = VoiceInputHotkeyPreset(
            keyCode: 61, carbonModifiers: 0x0800, keyDisplayName: "R⌥", modifierSides: [.rightOption]
        )
        fixture.modifiers = .option
        fixture.pressedKeys = [58]
        fixture.shake()
        #expect(fixture.presented == 0)
        fixture.pressedKeys = [61]
        fixture.shake()
        #expect(fixture.presented == 1)
    }

    @Test
    func customShortcutSurvivesSettingsReloadAndResetRestoresCommand() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.settings.settings.contextNoteHoldHotkey = .controlSpace
        fixture.settings.flushPendingChanges()
        let restored = FeatureSettingsStore(defaults: fixture.defaults)
        #expect(restored.settings.contextNoteHoldHotkey == .controlSpace)
        restored.settings.contextNoteHoldHotkey = FeatureSettings.default.contextNoteHoldHotkey
        restored.flushPendingChanges()
        #expect(FeatureSettingsStore(defaults: fixture.defaults).settings.contextNoteHoldHotkey.carbonModifiers == 0x0100)
    }

    @Test(arguments: [NSEvent.EventType.flagsChanged, .keyUp, .keyDown])
    func keyTransitionsWithoutMouseMovementDiscardIncompleteShakes(type: NSEvent.EventType) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        for (index, x) in [0.0, 80, 0, 80].enumerated() {
            fixture.controller.handlePointer(at: CGPoint(x: x, y: 0), interaction: .moved, timestamp: Double(index) * 0.1)
        }
        #expect(fixture.presented == 0)
        fixture.controller.handleKeyboardEvent(type: type, isRepeat: false)
        fixture.controller.handlePointer(at: .zero, interaction: .moved, timestamp: 0.4)
        #expect(fixture.presented == 0)
        fixture.nextShake = 1
        fixture.shake()
        #expect(fixture.presented == 1)
    }

    @Test
    func releasingTheShortcutDuringMovementDiscardsProgressEvenWithoutAKeyEvent() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        for (index, x) in [0.0, 80, 0, 80].enumerated() {
            fixture.controller.handlePointer(at: CGPoint(x: x, y: 0), interaction: .moved, timestamp: Double(index) * 0.1)
        }
        fixture.modifiers = []
        fixture.controller.handlePointer(at: .zero, interaction: .moved, timestamp: 0.35)
        fixture.modifiers = .command
        fixture.controller.handlePointer(at: .zero, interaction: .moved, timestamp: 0.4)
        #expect(fixture.presented == 0)
    }

    @Test
    func changingTheShortcutCannotCompleteThePreviousKeysGesture() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        for (index, x) in [0.0, 80, 0, 80].enumerated() {
            fixture.controller.handlePointer(at: CGPoint(x: x, y: 0), interaction: .moved, timestamp: Double(index) * 0.1)
        }
        fixture.settings.settings.contextNoteHoldHotkey = VoiceInputHotkeyPreset(
            keyCode: 58, carbonModifiers: 0x0800, keyDisplayName: "Option"
        )
        fixture.modifiers = .option
        fixture.pressedKeys = [58]
        fixture.controller.handlePointer(at: .zero, interaction: .moved, timestamp: 0.4)
        #expect(fixture.presented == 0)
        fixture.nextShake = 1
        fixture.shake()
        #expect(fixture.presented == 1)
    }

    @Test
    func holdingARepeatingCombinationStillAllowsShakingAndReleaseKeepsTheDraft() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.settings.settings.contextNoteHoldHotkey = .controlSpace
        fixture.modifiers = .control
        fixture.pressedKeys = [49, 59]
        for (index, x) in [0.0, 80, 0, 80, 0].enumerated() {
            fixture.controller.handleKeyboardEvent(type: .keyDown, isRepeat: true)
            fixture.controller.handlePointer(at: CGPoint(x: x, y: 0), interaction: .moved, timestamp: Double(index) * 0.1)
        }
        let draft = try #require(fixture.controller.draft)
        draft.text = "Keep after releasing the shortcut"
        fixture.modifiers = []
        fixture.pressedKeys = []
        fixture.controller.handlePointer(at: .zero, interaction: .moved, timestamp: 0.5)
        #expect(fixture.controller.draft === draft)
        #expect(draft.text == "Keep after releasing the shortcut")
    }

    @Test(arguments: [false, true], [false, true])
    func featureRequiresBothQuickActionAndNoteSwitches(enabled: Bool, parent: Bool) throws {
        let fixture = try Fixture(enabled: enabled, parentEnabled: parent)
        defer { fixture.close() }
        fixture.shake()
        #expect((fixture.controller.draft != nil) == (enabled && parent))
    }

    @Test
    func draggingPressedButtonsAndBusyInteractionsDoNotOpenNotes() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.shake(interaction: .dragging(hasSupportedPayload: true))
        fixture.buttons = 1
        fixture.shake()
        fixture.buttons = 0
        fixture.busy = true
        fixture.shake()
        #expect(fixture.presented == 0)
        #expect(fixture.controller.draft == nil)
    }

    @Test
    func successfulSaveNotifiesOnceAfterPersistenceAndSuppressesAnImmediateReminder() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.shake()
        fixture.controller.draft?.text = "Remember"
        fixture.controller.handlePointer(at: CGPoint(x: -5000, y: 2000), interaction: .moved, timestamp: 1)
        let date = Date(timeIntervalSince1970: 1234)
        fixture.controller.save(at: date)
        fixture.controller.save(at: date)
        #expect(fixture.saved.count == 1)
        #expect(fixture.saved.first?.addedAt == date)
        #expect(fixture.saved.first?.noteLocation == fixture.location)
        #expect(fixture.savedPoints == fixture.presentedPoints)
        fixture.controller.checkForReturn(at: .zero)
        #expect(fixture.reminders.isEmpty)
        fixture.observation = .ignored
        fixture.controller.checkForReturn(at: .zero)
        fixture.observation = .unavailable
        fixture.controller.checkForReturn(at: .zero)
        fixture.observation = .location(fixture.location)
        fixture.controller.checkForReturn(at: .zero)
        #expect(fixture.reminders.isEmpty)
        fixture.observation = .location(.desktop(displayID: "other", displayName: "Other"))
        fixture.controller.checkForReturn(at: .zero)
        fixture.observation = .location(fixture.location)
        let returnPoint = CGPoint(x: -1800, y: 400)
        fixture.controller.checkForReturn(at: returnPoint)
        fixture.controller.checkForReturn(at: .zero)
        #expect(fixture.reminders == fixture.saved.map(\.id))
        #expect(fixture.reminderPoints == [returnPoint])
    }

    @Test
    func emptySaveAndFailedWriteKeepDraftUntilRetryOrExplicitDiscard() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.shake()
        let draft = try #require(fixture.controller.draft)
        draft.text = "  "
        fixture.controller.save()
        #expect(fixture.controller.draft === draft)
        let index = fixture.directory.appendingPathComponent("shelf.json")
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        draft.text = "Do not lose this"
        fixture.controller.save()
        #expect(fixture.controller.draft === draft)
        #expect(draft.text == "Do not lose this")
        #expect(draft.error != nil)
        #expect(fixture.saved.isEmpty)
        try FileManager.default.removeItem(at: index)
        fixture.controller.save()
        #expect(fixture.saved.count == 1)
        #expect(fixture.controller.draft == nil)
        fixture.shake()
        fixture.controller.draft?.text = "Discard me"
        fixture.controller.discard()
        #expect(fixture.shelf.items.count == 1)
        #expect(fixture.saved.count == 1)
    }

    @Test
    func captureFailureShowsFeedbackAndOwnAppIsIgnored() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.observation = .unavailable
        fixture.shake()
        #expect(fixture.failedCaptures == 1)
        #expect(fixture.failurePoints == [CGPoint(x: 100, y: 100)])
        #expect(fixture.controller.draft == nil)
        fixture.observation = .ignored
        fixture.shake()
        #expect(fixture.failedCaptures == 1)
        #expect(fixture.presented == 0)
    }

    @Test
    func lockAndOverlappingScreenshotsPreserveDraftAndSuppressNewWork() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.controller.setScreenLocked(true)
        fixture.shake()
        #expect(fixture.controller.draft == nil)
        fixture.controller.setScreenLocked(false)
        fixture.shake()
        let draft = try #require(fixture.controller.draft)
        draft.text = "Keep"
        fixture.controller.setScreenshotActive(true)
        fixture.controller.setSystemScreenshotActive(true)
        fixture.controller.setScreenshotActive(false)
        fixture.shake()
        #expect(fixture.controller.draft === draft)
        #expect(draft.text == "Keep")
        fixture.controller.discard()
        fixture.shake()
        #expect(fixture.controller.draft == nil)
        fixture.controller.setSystemScreenshotActive(false)
        fixture.shake()
        #expect(fixture.controller.draft != nil)
        fixture.controller.stop()
        fixture.shake()
        #expect(fixture.controller.draft == nil)
    }

    @Test
    func latestNoteWaitsForAnAvailableQuickActionSlotAndDeletionRemovesReminder() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let latest = try #require(fixture.shelf.addContextNote("latest", location: fixture.location, addedAt: Date(timeIntervalSince1970: 100)))
        _ = fixture.shelf.addContextNote("older", location: fixture.location, addedAt: Date(timeIntervalSince1970: 1))
        fixture.acceptsReminder = false
        fixture.controller.checkForReturn(at: .zero)
        #expect(fixture.reminders.isEmpty)
        fixture.acceptsReminder = true
        fixture.controller.checkForReturn(at: .zero)
        #expect(fixture.reminders == [latest.id])
        fixture.shelf.removeAll()
        fixture.observation = .location(.desktop(displayID: "other", displayName: "Other"))
        fixture.controller.checkForReturn(at: .zero)
        fixture.observation = .location(fixture.location)
        fixture.controller.checkForReturn(at: .zero)
        #expect(fixture.reminders == [latest.id])
    }

    @Test
    func shelfButtonUsesTheContextBeforeIslandFocusEvenWhenShakeIsDisabled() throws {
        let fixture = try Fixture(enabled: false, parentEnabled: false)
        defer { fixture.close() }
        fixture.controller.prepareShelfCapture(at: .zero)
        fixture.observation = .ignored
        let date = Date(timeIntervalSince1970: 42)
        let draft = try #require(fixture.controller.makeShelfDraft(at: .zero, createdAt: date))
        #expect(draft.location == fixture.location)
        #expect(draft.createdAt == date)
        #expect(draft.text.isEmpty)
        #expect(fixture.shelf.items.isEmpty)
        #expect(fixture.controller.draft == nil)
        #expect(fixture.presented == 0)

        let next = ContextNoteLocation.desktop(displayID: "second", displayName: "Screen")
        fixture.observation = .location(next)
        #expect(fixture.controller.makeShelfDraft(at: .zero)?.location == next)
        fixture.observation = .unavailable
        #expect(fixture.controller.makeShelfDraft(at: .zero) == nil)
        fixture.observation = .ignored
        #expect(fixture.controller.makeShelfDraft(at: .zero) == nil)
    }

    @Test
    func aNewExpansionOrLockCannotReuseAnOldShelfContext() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.controller.prepareShelfCapture(at: .zero)
        fixture.observation = .ignored
        fixture.controller.prepareShelfCapture(at: .zero)
        #expect(fixture.controller.makeShelfDraft(at: .zero) == nil)
        fixture.observation = .location(fixture.location)
        fixture.controller.prepareShelfCapture(at: .zero)
        fixture.controller.setScreenLocked(true)
        #expect(fixture.controller.makeShelfDraft(at: .zero) == nil)
        fixture.controller.setScreenLocked(false)
        fixture.observation = .ignored
        #expect(fixture.controller.makeShelfDraft(at: .zero) == nil)
    }

    @Test
    func shelfSaveSuppressesImmediateReturnReminder() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let item = try #require(fixture.shelf.addContextNote("saved in island", location: fixture.location))
        fixture.controller.didSaveNote(item)
        fixture.controller.checkForReturn(at: .zero)
        #expect(fixture.reminders.isEmpty)
        fixture.observation = .location(.desktop(displayID: "other", displayName: "Other"))
        fixture.controller.checkForReturn(at: .zero)
        fixture.observation = .location(fixture.location)
        fixture.controller.checkForReturn(at: .zero)
        #expect(fixture.reminders == [item.id])
    }
}

@MainActor
struct ContextNotePresentationTests {
    @Test(arguments: IslandVisualStyle.allCases, IslandNotchBackground.allCases)
    func remindersUseExistingQuickActionAppearanceAndOpenTheirOwnNote(style: IslandVisualStyle, background: IslandNotchBackground) throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        var settings = FeatureSettings.default
        settings.contextNotesEnabled = true
        settings.islandVisualStyle = style
        settings.islandNotchBackground = background
        settings.clipboardAssistantDisplayDuration = .never
        settings.clipboardAssistantLightweightMode = true
        let item = FileShelfItem(id: UUID(), url: URL(fileURLWithPath: "/fixture/note"), addedAt: Date(), bookmarkData: Data(), text: "Remember", noteLocation: .desktop(displayID: "display", displayName: "Screen"))
        let point = CGPoint(x: -1200, y: 500)
        var screenRequests: [CGPoint] = []
        controller.screenAtPoint = { screenRequests.append($0); return nil }
        #expect(ContextNoteReminderPresenter.present(item, at: point, on: controller, settings: settings))
        _ = controller.rowLayout(for: try #require(controller.presentation.detection))
        #expect(screenRequests == [point])
        #expect(controller.presentation.visualStyle == style)
        #expect(controller.presentation.notchBackground == background)
        #expect(controller.isLightweightMode)
        #expect(controller.dismissalProgress(at: .distantFuture) == nil)
        #expect(controller.presentation.detection?.fullContent == "Remember")
        #expect(!ContextNoteReminderPresenter.present(item, at: .zero, on: controller, settings: settings))
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        controller.performCurrentAction()
        #expect(performed == [.showContextNote(item.id)])
        #expect(controller.presentation.detection == nil)
    }

    @Test
    func notesKeepTheShelfAvailableWhenFileTransfersAreDisabled() {
        var settings = FeatureSettings.default
        settings.fileShelfEnabled = false
        settings.contextNotesEnabled = true
        #expect(IslandModule.shelf.isEnabled(in: settings))
        settings.contextNotesEnabled = false
        #expect(!IslandModule.shelf.isEnabled(in: settings))
    }

    @Test(arguments: IslandVisualStyle.allCases, [LayoutDirection.leftToRight, .rightToLeft])
    func inputUsesTheConfiguredIslandInputMaterial(style: IslandVisualStyle, direction: LayoutDirection) throws {
        let name = "context-note-material-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        let settings = FeatureSettingsStore(defaults: defaults)
        settings.settings.islandVisualStyle = style
        defer { settings.flushPendingChanges(); defaults.removePersistentDomain(forName: name) }
        let draft = ContextNoteDraft(location: .desktop(displayID: "display", displayName: "Screen"))
        let locale = Locale(identifier: direction == .rightToLeft ? "ar" : "en")
        let host = NSHostingView(rootView: ContextNoteInputView(draft: draft, settingsStore: settings, onSave: {}, onDiscard: {})
            .environment(\.layoutDirection, direction).environment(\.locale, locale))
        let panel = ClipboardAssistantController.makeWindow(contentView: host, frame: CGRect(x: 0, y: 0, width: 360, height: 44))
        defer { panel.close() }
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        let views = descendants(host)
        let field = try #require(views.compactMap { $0 as? NSTextField }.first)
        #expect(field.usesSingleLineMode)
        #expect(field.alignment == (direction == .rightToLeft ? NSTextAlignment.right : .left))
        #expect(field.placeholderString == AppLocalization.string("在这里记点什么…", locale: locale))
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            #expect(!views.contains { $0 is NSVisualEffectView })
        } else if #available(macOS 26.0, *), style == .transparent {
            let glass = try #require(views.compactMap { $0 as? NSGlassEffectView }.first)
            #expect(glass.style == .clear)
            #expect(glass.tintColor == nil)
        } else {
            let effect = try #require(views.compactMap { $0 as? NSVisualEffectView }.first)
            #expect(effect.material == .sidebar)
            #expect(effect.blendingMode == .behindWindow)
        }
        #expect(!panel.isVisible)
    }

    @Test
    func inputKeyboardCommandsRespectCompositionAndModifiers() throws {
        let enter = #selector(NSResponder.insertNewline(_:))
        #expect(ContextNoteInputCommand.shouldSave(enter, hasMarkedText: false))
        #expect(!ContextNoteInputCommand.shouldSave(enter, hasMarkedText: true))
        #expect(!ContextNoteInputCommand.shouldSave(#selector(NSResponder.cancelOperation(_:)), hasMarkedText: false))
        for (flags, keyCode, expected) in [(NSEvent.ModifierFlags.command, UInt16(51), true), ([], 51, false), ([.command, .shift], 51, false), (.command, 36, false), ([], 53, true), (.command, 53, false), (.shift, 53, false)] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode))
            #expect(ContextNoteInputCommand.isDiscard(event) == expected)
        }
    }

    @Test
    func inputFitsEveryEdgeOfAnOffsetDisplay() {
        let visible = CGRect(x: -1920, y: -300, width: 1920, height: 1040)
        for x in stride(from: visible.minX, through: visible.maxX, by: 120) {
            for y in stride(from: visible.minY, through: visible.maxY, by: 130) {
                let frame = ContextNoteLayout.frame(near: CGPoint(x: x, y: y), in: visible)
                #expect(visible.insetBy(dx: 8, dy: 8).contains(frame))
                #expect(frame.size == CGSize(width: 360, height: 44))
            }
        }
    }
}

struct ContextNoteLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func everyNewVisibleStringExistsAndRendersInEveryLanguage(language: AppLanguage) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resource = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: resource), format: nil) as? [String: String])
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/ContextNoteViews.swift"), encoding: .utf8)
        let expression = try NSRegularExpression(pattern: #"App(?:LocalizedText|Localization\.(?:text|string))\("([^"]+)""#)
        let directKeys = expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
        let reusedKeys: Set<String> = ["复制", "关闭", "保存"]
        let indirectKeys: Set<String> = ["摇动鼠标记便签", "按住快捷键并左右摇动鼠标，在当前位置记录，返回时提醒", "便签快捷键", "默认按住 Command；可录制修饰键或组合键", "需要辅助功能权限来识别窗口和网页", "无法识别当前位置，请检查辅助功能权限", "查看便签", "前往记录位置", "无法前往记录位置，窗口或显示器可能已关闭", "记录便签", "已保存便签"]
        let keys = Set(directKeys).subtracting(reusedKeys).union(indirectKeys)
        #expect(keys.count == 19)
        for key in keys {
            let value = try #require(table[key], "Missing \(language.rawValue): \(key)")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
            if language != .simplifiedChinese && language != .traditionalChinese { #expect(value != key) }
        }
    }
}

struct ContextNoteHoldShortcutTests {
    @Test
    func recordedSidesAndPrimaryKeyMustAllBeHeld() {
        let hotkey = VoiceInputHotkeyPreset(keyCode: 49, carbonModifiers: 0x1800, keyDisplayName: "Space",
                                           modifierSides: [.leftControl, .rightOption])
        for (keys, expected) in [([49, 59, 61], true), ([49, 62, 61], false), ([59, 61], false), ([49, 59, 61, 58], false)] {
            #expect(ContextNoteHoldShortcut.isPressed(hotkey, modifiers: [.control, .option]) { keys.contains(Int($0)) } == expected)
        }
        #expect(!ContextNoteHoldShortcut.isPressed(hotkey, modifiers: .control) { [49, 59, 61].contains(Int($0)) })
    }

    @Test
    func malformedKeyCodesAndUnheldBareKeysAreRejected() {
        for code in [UInt32(65_536), UInt32.max] {
            let hotkey = VoiceInputHotkeyPreset(keyCode: code, carbonModifiers: 0, keyDisplayName: "Invalid")
            #expect(!ContextNoteHoldShortcut.isPressed(hotkey, modifiers: []) { _ in
                Issue.record("An invalid key must never reach the system key-state query")
                return true
            })
        }
        let bareKey = VoiceInputHotkeyPreset(keyCode: 0, carbonModifiers: 0, keyDisplayName: "A")
        #expect(!ContextNoteHoldShortcut.isPressed(bareKey, modifiers: []) { _ in false })
        #expect(ContextNoteHoldShortcut.isPressed(bareKey, modifiers: []) { $0 == 0 })
        let invalidModifier = VoiceInputHotkeyPreset(keyCode: 55, carbonModifiers: 0, keyDisplayName: "Command")
        #expect(!ContextNoteHoldShortcut.isPressed(invalidModifier, modifiers: []) { _ in true })
    }
}
