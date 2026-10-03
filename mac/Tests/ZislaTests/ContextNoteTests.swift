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
        var failedCaptures = 0
        var saved: [FileShelfItem] = []
        var reminders: [UUID] = []
        var acceptsReminder = true
        var busy = false
        var buttons = 0
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
                onReminder: { [unowned self] item in
                    if acceptsReminder { reminders.append(item.id) }
                    return acceptsReminder
                },
                onCaptureFailure: { [unowned self] in failedCaptures += 1 },
                onSaved: { [unowned self] item in
                    #expect(shelf.items.contains(item))
                    #expect(controller.draft == nil)
                    saved.append(item)
                },
                pressedMouseButtons: { [unowned self] in buttons },
                windowPresenter: { [unowned self] _, _, _ in presented += 1 }
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
        let date = Date(timeIntervalSince1970: 1234)
        fixture.controller.save(at: date)
        fixture.controller.save(at: date)
        #expect(fixture.saved.count == 1)
        #expect(fixture.saved.first?.addedAt == date)
        #expect(fixture.saved.first?.noteLocation == fixture.location)
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
        fixture.controller.checkForReturn(at: .zero)
        fixture.controller.checkForReturn(at: .zero)
        #expect(fixture.reminders == fixture.saved.map(\.id))
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
    func remindersUseExistingQuickActionAppearanceAndOpenTheirOwnNote(style: IslandVisualStyle, background: IslandNotchBackground) {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        var settings = FeatureSettings.default
        settings.contextNotesEnabled = true
        settings.islandVisualStyle = style
        settings.islandNotchBackground = background
        settings.clipboardAssistantDisplayDuration = .never
        settings.clipboardAssistantLightweightMode = true
        let item = FileShelfItem(id: UUID(), url: URL(fileURLWithPath: "/fixture/note"), addedAt: Date(), bookmarkData: Data(), text: "Remember", noteLocation: .desktop(displayID: "display", displayName: "Screen"))
        #expect(ContextNoteReminderPresenter.present(item, on: controller, settings: settings))
        #expect(controller.presentation.visualStyle == style)
        #expect(controller.presentation.notchBackground == background)
        #expect(controller.isLightweightMode)
        #expect(controller.dismissalProgress(at: .distantFuture) == nil)
        #expect(controller.presentation.detection?.fullContent == "Remember")
        #expect(!ContextNoteReminderPresenter.present(item, on: controller, settings: settings))
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
        let indirectKeys: Set<String> = ["摇动鼠标记便签", "快速左右摇动鼠标，在当前位置记录，返回时提醒", "需要辅助功能权限来识别窗口和网页", "无法识别当前位置，请检查辅助功能权限", "查看便签", "前往记录位置", "无法前往记录位置，窗口或显示器可能已关闭", "记录便签", "已保存便签"]
        let keys = Set(directKeys).subtracting(reusedKeys).union(indirectKeys)
        #expect(keys.count == 17)
        for key in keys {
            let value = try #require(table[key], "Missing \(language.rawValue): \(key)")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
            if language != .simplifiedChinese && language != .traditionalChinese { #expect(value != key) }
        }
    }
}
