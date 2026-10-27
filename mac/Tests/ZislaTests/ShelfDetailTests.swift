import AppKit
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ShelfDetailTests {
    @Test(arguments: [false, true], ["close", "hide", "remove"])
    func leavingScreenshotReleasesImageAndPreservesUnsavedNote(existing: Bool, action: String) throws {
        try withStore { store, _ in
            let screenshot = try stash(in: store)
            let note = try #require(store.addContextNote("saved", location: Self.location))
            let editor = ContextNoteShelfEditor()
            if existing { editor.open(note) }
            else { editor.begin(ContextNoteDraft(location: Self.location)) }
            let draft = try #require(editor.draft)
            draft.text = "unsaved changes"
            editor.hide()
            weak var image: NSImage?
            try autoreleasepool {
                try editor.openScreenshot(screenshot, in: store)
                image = editor.screenshot?.image
                #expect(image != nil)
                #expect(!editor.isPresented)
                switch action {
                case "close": editor.close()
                case "hide": editor.hide()
                default:
                    store.remove(id: screenshot.id)
                    editor.removed(screenshot.id)
                }
            }
            #expect(editor.screenshot == nil)
            #expect(image == nil)
            #expect(!editor.isPresented)
            if existing { editor.open(note) }
            else { #expect(editor.resumeNew()) }
            #expect(editor.draft === draft)
            #expect(editor.draft?.text == "unsaved changes")
            #expect(store.items.first { $0.id == note.id }?.text == "saved")
        }
    }

    @Test(arguments: [false, true])
    func enteringNoteReleasesScreenshot(existing: Bool) throws {
        try withStore { store, _ in
            let screenshot = try stash(in: store)
            let note = try #require(store.addContextNote("saved", location: Self.location))
            let editor = ContextNoteShelfEditor()
            weak var image: NSImage?
            try autoreleasepool {
                try editor.openScreenshot(screenshot, in: store)
                image = editor.screenshot?.image
                if existing { editor.open(note) }
                else { editor.begin(ContextNoteDraft(location: Self.location)) }
            }
            #expect(image == nil)
            #expect(editor.screenshot == nil)
            #expect(editor.isPresented)
        }
    }

    @Test
    func deletingHiddenNoteDoesNotCloseAnUnrelatedScreenshot() throws {
        try withStore { store, _ in
            let screenshot = try stash(in: store)
            let note = try #require(store.addContextNote("saved", location: Self.location))
            let editor = ContextNoteShelfEditor()
            editor.open(note)
            try editor.openScreenshot(screenshot, in: store)
            #expect(!editor.isPresented)
            store.remove(id: note.id)
            editor.removed(note.id)
            #expect(editor.screenshot?.id == screenshot.id)
            #expect(editor.draft == nil)
            #expect(editor.itemID == nil)
            #expect(!editor.isPresented)
        }
    }

    @Test(arguments: ["list", "note", "screenshot"], ["missing", "invalid image", "missing metadata"])
    func failedScreenshotReadKeepsTheCurrentPresentation(presentation: String, failure: String) throws {
        try withStore { store, directory in
            let screenshot = try stash(in: store)
            let editor = ContextNoteShelfEditor()
            if presentation == "note" { editor.begin(ContextNoteDraft(location: Self.location)) }
            else if presentation == "screenshot" { try editor.openScreenshot(screenshot, in: store) }
            let draft = editor.draft
            let image = editor.screenshot?.image
            let presented = editor.isPresented
            var unreadable = screenshot
            unreadable.id = UUID()
            if failure == "invalid image" {
                let database = ShelfScreenshotDatabase(directory: directory.appendingPathComponent("shelf.screenshots"))
                try database.insert(ShelfScreenshotRecord(id: unreadable.id, addedAt: Self.date, shelfOrder: 1,
                    metadata: Self.metadata, png: Data("not an image".utf8)))
            } else if failure == "missing metadata" {
                unreadable.screenshotMetadata = nil
            }
            #expect(throws: (any Error).self) { try editor.openScreenshot(unreadable, in: store) }
            #expect(editor.draft === draft)
            #expect(editor.screenshot?.image === image)
            #expect(editor.isPresented == presented)
            #expect(store.items == [screenshot])
        }
    }

    @Test
    func renderedDetailsShareTheirFrameAndDispatchRealControls() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let draft = ContextNoteDraft(location: Self.location, createdAt: Self.date)
        draft.text = "保留这次截图对应的评审记录，稍后继续编辑。"
        var noteActions: [String] = []
        let note = DetailHost(ContextNoteDetailView(draft: draft,
            onCopy: { noteActions.append("copy") }, onNavigate: { noteActions.append("navigate") },
            onSave: { noteActions.append("save") }, onClose: { noteActions.append("close") }, onCopyScreenshot: { _ in }))
        defer { note.panel.close() }
        await note.settle()
        try note.render(name: "note")
        let noteElements = note.elements()
        for label in ["复制", "前往记录位置", "保存", "关闭"] {
            let element = try #require(noteElements.first { $0.label == AppLocalization.text(label) && $0.role == .button })
            try note.click(element.frame)
        }
        #expect(noteActions == ["copy", "navigate", "save", "close"])
        #expect(note.panel.performKeyEquivalent(with: try saveEvent(in: note.panel)))
        #expect(noteActions.last == "save")
        #expect(noteActions.count == 5)

        var screenshotActions: [String] = []
        let screenshot = DetailHost(ShelfScreenshotDetailView(
            detail: ShelfScreenshotDetail(id: UUID(), metadata: Self.metadata, image: try makeImage()),
            onCopy: { screenshotActions.append("copy") }, onSave: { screenshotActions.append("save") },
            onClose: { screenshotActions.append("close") }))
        defer { screenshot.panel.close() }
        await screenshot.settle()
        try screenshot.render(name: "screenshot")
        let screenshotElements = screenshot.elements()
        #expect(!screenshotElements.contains { $0.label == AppLocalization.text("前往记录位置") })
        for label in ["保存", "关闭", "记录位置", "记录时间", "记录内容"] {
            let original = try #require(noteElements.first { $0.label == AppLocalization.text(label) })
            let reused = try #require(screenshotElements.first { $0.label == AppLocalization.text(label) })
            #expect(abs(original.frame.minX - reused.frame.minX) < 1)
            #expect(abs(original.frame.minY - reused.frame.minY) < 1)
            #expect(abs(original.frame.height - reused.frame.height) < 1)
        }
        for label in ["复制", "保存", "关闭"] {
            let element = try #require(screenshotElements.first { $0.label == AppLocalization.text(label) && $0.role == .button })
            try screenshot.click(element.frame)
        }
        #expect(screenshotActions == ["copy", "save", "close"])
        #expect(screenshot.panel.performKeyEquivalent(with: try saveEvent(in: screenshot.panel)))
        #expect(screenshotActions.last == "save")
        #expect(screenshotActions.count == 4)
        #expect(note.panel.attachedSheet == nil && screenshot.panel.attachedSheet == nil)
        #expect(note.host.bounds == screenshot.host.bounds)
        #expect(note.host.bounds.size == CGSize(width: 436, height: 270))
    }

    @Test
    func renderedNoteKeepsEditingValidationAndSaveFailure() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let draft = ContextNoteDraft(location: Self.location)
        var saves = 0
        let fixture = DetailHost(ContextNoteDetailView(draft: draft, onCopy: {}, onNavigate: {},
            onSave: { saves += 1; draft.error = "写入失败，请重试" }, onClose: {}, onCopyScreenshot: { _ in }))
        defer { fixture.panel.close() }
        await fixture.settle()
        let save = try #require(fixture.elements().first { $0.role == .button && $0.label == AppLocalization.text("保存") })
        #expect(save.isEnabled == false)
        let copy = try #require(fixture.elements().first { $0.role == .button && $0.label == AppLocalization.text("复制") })
        #expect(copy.isEnabled == false)
        draft.text = " "
        await fixture.settle()
        #expect(fixture.elements().first { $0.role == .button && $0.label == AppLocalization.text("保存") }?.isEnabled == false)
        #expect(fixture.elements().first { $0.role == .button && $0.label == AppLocalization.text("复制") }?.isEnabled == true)
        draft.text = "new unsaved text"
        await fixture.settle()
        let enabledSave = try #require(fixture.elements().first { $0.role == .button && $0.label == AppLocalization.text("保存") })
        #expect(enabledSave.isEnabled == true)
        try fixture.click(enabledSave.frame)
        await fixture.settle()
        #expect(saves == 1)
        #expect(draft.text == "new unsaved text")
        #expect(fixture.elements().contains { $0.label == "写入失败，请重试" })
        draft.text = "retry"
        await fixture.settle()
        #expect(draft.error == nil)
    }

    @Test(arguments: [false, true])
    func renderedNoteScreenshotOpensAndCopiesItsOriginalPNGThenCloses(useEscape: Bool) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let png = try ContextNoteScreenshotTestImage.make().png
        let draft = ContextNoteDraft(location: Self.location)
        draft.text = "Note with a screenshot"
        draft.captureScreenshot(from: .success(.window(11, processIdentifier: 42))) { _ in png }
        await draft.screenshotTask?.value
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        var copies: [Data] = []
        let fixture = DetailHost(ContextNoteDetailView(draft: draft, onCopy: {}, onNavigate: {}, onSave: {}, onClose: {},
            onCopyScreenshot: { data in
                copies.append(data)
                #expect(ClipboardHistoryPasteboard.write(.image(data), to: pasteboard))
            }), height: 520)
        defer { fixture.panel.close() }
        await fixture.settle()
        try fixture.render(name: "note-attachment")
        let copy = try #require(fixture.elements().first { $0.role == .button && $0.label == AppLocalization.text("复制截图") })
        try fixture.click(copy.frame)
        #expect(copies == [png])
        #expect(pasteboard.data(forType: .png) == png)
        #expect(pasteboard.canReadObject(forClasses: [NSImage.self], options: nil))
        let windows = Set(NSApp.windows.map(ObjectIdentifier.init))
        defer {
            for window in NSApp.windows where !windows.contains(ObjectIdentifier(window)) { window.close() }
        }
        let view = try #require(fixture.elements().first { $0.role == .button && $0.label == AppLocalization.text("查看截图") })
        #expect(view.frame.height <= 100 && view.frame.width > 0)
        try fixture.click(view.frame)
        await fixture.settle()
        let preview = try #require(NSApp.windows.first { !windows.contains(ObjectIdentifier($0)) && $0.isVisible })
        preview.isReleasedWhenClosed = false
        preview.setFrameOrigin(CGPoint(x: -100_000, y: -100_000))
        let content = try #require(preview.contentView)
        let image = try #require(fixture.elements(in: content).first { $0.role == .image && $0.label == AppLocalization.text("截图") })
        #expect(image.frame.width > 300 && image.frame.height > 100)
        #expect(abs(image.frame.width / image.frame.height - 2) < 0.01)
        #expect(preview.frame.contains(image.frame))
        let previewCopy = try #require(fixture.elements(in: content).first { $0.role == .button && $0.label == AppLocalization.text("复制截图") })
        try fixture.click(previewCopy.frame, in: preview)
        let commandC = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: preview.windowNumber, context: nil, characters: "c", charactersIgnoringModifiers: "c",
            isARepeat: false, keyCode: 8))
        #expect(preview.performKeyEquivalent(with: commandC))
        #expect(copies == [png, png, png])
        #expect(pasteboard.data(forType: .png) == png)
        if useEscape {
            let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: preview.windowNumber, context: nil, characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
            #expect(preview.performKeyEquivalent(with: escape))
        } else {
            let close = try #require(fixture.elements(in: content).first { $0.role == .button && $0.label == AppLocalization.text("关闭") })
            try fixture.click(close.frame, in: preview)
        }
        await fixture.settle()
        #expect(!preview.isVisible)
        #expect(draft.screenshot?.png == png && draft.text == "Note with a screenshot")
    }

    @Test
    func renderedCaptureDisablesSaveThenShowsFailureWithoutLosingText() async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let gate = ContextNoteScreenshotGate()
        let draft = ContextNoteDraft(location: Self.location)
        draft.text = "Keep the text even if the window closes"
        draft.captureScreenshot(from: .success(.window(11, processIdentifier: 42))) { _ in try await gate.capture() }
        let task = try #require(draft.screenshotTask)
        defer { draft.cancelScreenshotCapture(); gate.finish(.failure(CocoaError(.userCancelled))) }
        await gate.waitUntilStarted()
        var saves = 0
        let fixture = DetailHost(ContextNoteDetailView(draft: draft, onCopy: {}, onNavigate: {},
            onSave: { saves += 1 }, onClose: {}, onCopyScreenshot: { _ in }))
        defer { fixture.panel.close() }
        await fixture.settle()
        #expect(fixture.elements().first { $0.role == .button && $0.label == AppLocalization.text("保存") }?.isEnabled == false)
        _ = fixture.panel.performKeyEquivalent(with: try saveEvent(in: fixture.panel))
        #expect(saves == 0)
        gate.finish(.failure(ScreenshotCaptureError.windowUnavailable))
        await task.value
        await fixture.settle()
        #expect(fixture.elements().first { $0.role == .button && $0.label == AppLocalization.text("保存") }?.isEnabled == true)
        #expect(fixture.elements().contains { $0.label == draft.screenshotError })
        #expect(draft.text == "Keep the text even if the window closes")
    }

    private func withStore(_ body: (FileShelfStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-detail-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json")), directory)
    }

    private func stash(in store: FileShelfStore) throws -> FileShelfItem {
        let image = try makeImage()
        let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
        return try store.stashScreenshot(png: #require(bitmap.representation(using: .png, properties: [:])), metadata: Self.metadata)
    }

    private func makeImage() throws -> NSImage {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 160,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<160 {
            for x in 0..<320 {
                bitmap.setColor(NSColor(calibratedRed: CGFloat(x) / 320, green: CGFloat(y) / 160, blue: 0.3, alpha: 1), atX: x, y: y)
            }
        }
        let image = NSImage(size: CGSize(width: 320, height: 160))
        image.addRepresentation(bitmap)
        return image
    }

    private func saveEvent(in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1))
    }

    private static let date = Date(timeIntervalSince1970: 1_728_460_800)
    private static let location = ContextNoteLocation.window(bundleIdentifier: "test.review", applicationName: "评审应用", title: "截图方案")
    private static let metadata = ShelfScreenshotMetadata(
        source: ScreenshotSourceSnapshot(applicationName: "评审应用", bundleIdentifier: "test.review", processIdentifier: 42, capturedAt: date),
        isLongScreenshot: false, initialCaptureRect: CGRect(x: 10, y: 20, width: 320, height: 160),
        captureRect: CGRect(x: 10, y: 20, width: 320, height: 160), screenFrame: nil, displayIdentifier: nil,
        pixelWidth: 320, pixelHeight: 160)
}

@MainActor
private final class DetailHost<Content: View> {
    let panel: NSPanel
    let host: NSView

    init(_ content: Content, height: CGFloat = 270) {
        _ = NSApplication.shared
        panel = NSPanel(contentRect: CGRect(x: -100_000, y: -100_000, width: 436, height: height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: content.environment(\.locale, AppLocalization.currentLanguage.locale)
            .environment(\.colorScheme, .dark).background(Color.black))
        hosting.sizingOptions = []
        host = hosting
        panel.contentView = hosting
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(panel.frame) })
        panel.orderFrontRegardless()
    }

    func settle() async {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }

    struct Element {
        let label: String?
        let role: NSAccessibility.Role?
        let frame: CGRect
        let isEnabled: Bool?
    }

    func elements(in view: NSView? = nil) -> [Element] {
        var result: [Element] = []
        func visit(_ object: NSObject) {
            func value(_ key: String) -> Any? {
                object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
            }
            if let element = object as? any NSAccessibilityElementProtocol {
                let label = ["accessibilityTitle", "accessibilityLabel", "accessibilityValue"]
                    .compactMap { value($0) as? String }.first { !$0.isEmpty }
                let role = (value("accessibilityRole") as? String).map(NSAccessibility.Role.init(rawValue:))
                result.append(Element(label: label, role: role, frame: element.accessibilityFrame(),
                    isEnabled: value("isAccessibilityEnabled") as? Bool))
            }
            for child in value("accessibilityChildren") as? [NSObject] ?? [] { visit(child) }
        }
        for child in (view ?? host).accessibilityChildren() as? [NSObject] ?? [] { visit(child) }
        return result
    }

    func click(_ frame: CGRect, in window: NSWindow? = nil) throws {
        let window = window ?? panel
        let point = window.convertPoint(fromScreen: CGPoint(x: frame.midX, y: frame.midY))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
        }
    }

    func render(name: String) throws {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        if let directory = ProcessInfo.processInfo.environment["ZISLA_SHELF_DETAIL_RENDER_DIRECTORY"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        }
    }
}
