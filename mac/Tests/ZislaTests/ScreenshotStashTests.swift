import AppKit
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenshotStashTests {
    @Test(arguments: [false, true])
    func toolbarStashesFinalPNGIncludingDraftsAndLongCaptureWithoutCopying(isLong: Bool) throws {
        let defaultsName = "zisla-stash-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        let settingsStore = FeatureSettingsStore(defaults: defaults)
        defer {
            settingsStore.flushPendingChanges()
            defaults.removePersistentDomain(forName: defaultsName)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-editor-stash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let image = try makeImage()
        let pixels = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let source = ScreenshotSourceSnapshot(applicationName: "Capture source", bundleIdentifier: "test.capture",
            processIdentifier: 456, capturedAt: Date(timeIntervalSince1970: 42))
        var closeCount = 0
        var copyCount = 0
        let controller = ScreenshotEditorWindowController(image: image, screenImage: image, screenCGImage: pixels,
            screen: nil, captureRect: CGRect(x: 20, y: 30, width: 160, height: 80),
            capturedApplication: nil, settingsStore: settingsStore, sourceSnapshot: source,
            onStash: { data, metadata in try store.stashScreenshot(png: data, metadata: metadata) },
            writeImageToPasteboard: { _ in copyCount += 1; return true },
            onClose: { closeCount += 1 })
        defer { controller.close() }
        let window = try #require(controller.window)
        window.alphaValue = 0
        let hosting = try #require(window.contentView as? NSHostingView<AppLanguageEnvironment<ScreenshotEditorView>>)
        let editor = hosting.rootView.content
        if isLong {
            #expect(editor.model.append(image: image, direction: .vertical))
            editor.model.beginLongCapturePreview()
        }
        editor.model.add(ScreenshotAnnotation(kind: .mosaic, rect: CGRect(x: 0, y: 0, width: 30, height: 30)))
        editor.model.add(ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 40, y: 40, width: 80, height: 30)))
        let text = ScreenshotAnnotation(kind: .text, rect: CGRect(x: 5, y: 5, width: 100, height: 40), text: "")
        editor.model.add(text)
        editor.model.beginTextDraft(id: text.id, text: "未完成文字", isNew: true)
        // Keep the model alive to verify committed text and final dimensions after closing.
        editor.onStash()
        let expectedData = editor.model.pngData()
        let screenshot = try #require(store.items.first)
        #expect(try store.screenshotData(id: screenshot.id) == expectedData)
        #expect(editor.model.annotations.contains { $0.kind == .text && $0.text == "未完成文字" })
        #expect(screenshot.screenshotMetadata?.source == source)
        #expect(screenshot.screenshotMetadata?.isLongScreenshot == isLong)
        let dimensions = try FileShelfStore.screenshotDimensions(try store.screenshotData(id: screenshot.id))
        #expect(screenshot.screenshotMetadata?.pixelWidth == dimensions.width)
        #expect(screenshot.screenshotMetadata?.pixelHeight == dimensions.height)
        #expect(copyCount == 0)
        #expect(closeCount == 1)
        #expect(!controller.stashImage())
        #expect(store.items.count == 1)
    }

    @Test(arguments: [false, true])
    func stashFailurePreservesEditorAndPinAndSuccessfulRetryCloses(pinned: Bool) throws {
        let defaultsName = "zisla-stash-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        let settingsStore = FeatureSettingsStore(defaults: defaults)
        defer {
            settingsStore.flushPendingChanges()
            defaults.removePersistentDomain(forName: defaultsName)
        }
        let image = try makeImage()
        let pixels = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var fails = true
        var closeCount = 0
        var copyCount = 0
        var stashedData: Data?
        let controller = ScreenshotEditorWindowController(image: image, screenImage: image, screenCGImage: pixels,
            screen: nil, captureRect: CGRect(x: 0, y: 0, width: 160, height: 80), capturedApplication: nil,
            settingsStore: settingsStore,
            onStash: { data, _ in
                if fails { throw TestStashError() }
                stashedData = data
            },
            writeImageToPasteboard: { _ in copyCount += 1; return true },
            onClose: { closeCount += 1 })
        defer { controller.close() }
        let window = try #require(controller.window)
        window.alphaValue = 0
        let hosting = try #require(window.contentView as? NSHostingView<AppLanguageEnvironment<ScreenshotEditorView>>)
        let model = hosting.rootView.content.model
        let annotation = ScreenshotAnnotation(kind: .rectangle, rect: CGRect(x: 30, y: 20, width: 60, height: 30))
        model.add(annotation)
        if pinned { controller.setPinned(true) }
        let expected = try #require(model.pngData())
        #expect(!controller.stashImage())
        #expect(closeCount == 0)
        #expect(copyCount == 0)
        #expect(model.annotations == [annotation])
        #expect(model.statusMessage == "真实 SQLite 错误")
        #expect(controller.isPinnedPresentation == pinned)
        #expect(window.contentView != nil)
        fails = false
        #expect(controller.stashImage())
        #expect(stashedData == expected)
        #expect(closeCount == 1)
        #expect(copyCount == 0)
    }

    @Test
    func screenshotCardsSpanTwoColumnsWithoutChangingRegularCards() throws {
        let metadata = ShelfScreenshotMetadata(source: ScreenshotSourceSnapshot(applicationName: nil,
            bundleIdentifier: nil, processIdentifier: nil), isLongScreenshot: false,
            initialCaptureRect: .zero, captureRect: .zero, screenFrame: nil, displayIdentifier: nil,
            pixelWidth: 320, pixelHeight: 160)
        let item = FileShelfItem(id: UUID(), url: URL(fileURLWithPath: "/nonexistent.png"),
            addedAt: Date(), bookmarkData: Data(), screenshotMetadata: metadata)
        let host = NSHostingView(rootView: ShelfItemView(item: item, onOpen: {}, onCopy: {},
            onSave: {}, onSendToQuickNote: {}, onRemove: {}))
        #expect(host.fittingSize == CGSize(width: 140, height: 84))
        let frames = ShelfGridLayout.frames(columnSpans: [1, 2, 1, 2], width: 288)
        #expect(frames.map(\.width) == [66, 140, 66, 140])
        #expect(frames.map(\.minY) == [0, 0, 0, 92])
        #expect(frames[0].maxX + 8 == frames[1].minX)
        #expect(frames[1].maxX + 8 == frames[2].minX)
    }

    @Test
    func screenshotNativeContextMenuPreviewsCopiesSavesAndDeletesOnlyThisObject() throws {
        var actions: [String] = []
        let view = FileShelfDraggingView(frame: CGRect(x: 0, y: 0, width: 124, height: 48))
        view.payload = .file(URL(fileURLWithPath: "/synthetic-screenshot.png"))
        view.onOpen = { actions.append("preview") }
        view.onCopy = { actions.append("copy") }
        view.onSave = { actions.append("save") }
        view.onRemove = { actions.append("delete") }
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try #require(view.menu(for: event))
        #expect(menu.items.filter { !$0.isSeparatorItem }.map(\.title) ==
            ["预览", "复制", "保存", "移除"].map { AppLocalization.text($0) })
        for item in menu.items where !item.isSeparatorItem {
            let action = try #require(item.action)
            #expect(NSApp.sendAction(action, to: item.target, from: item))
        }
        #expect(actions == ["preview", "copy", "save", "delete"])
    }

    @Test(arguments: AppLanguage.allCases)
    func stagingLabelsFollowExistingLocalization(language: AppLanguage) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let tableURL = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        for key in ["暂存", "暂存截图", "预览", "无法打开截图数据库"] {
            let translation = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
            #expect(!translation.isEmpty)
            #expect(AppLocalization.string(key, language: language) == translation)
            if language != .simplifiedChinese { #expect(translation != key) }
        }
    }

    @Test
    func categoryCountsAndMetadataSearchKeepScreenshotsSeparateFromOrdinaryImagesAndNotes() {
        let metadata = ShelfScreenshotMetadata(source: ScreenshotSourceSnapshot(applicationName: "Original App",
            bundleIdentifier: "test.original", processIdentifier: 654, capturedAt: Date(timeIntervalSince1970: 42)),
            isLongScreenshot: false, initialCaptureRect: .zero, captureRect: .zero,
            screenFrame: nil, displayIdentifier: nil, pixelWidth: 320, pixelHeight: 160)
        let screenshot = FileShelfItem(id: UUID(), url: URL(fileURLWithPath: "/missing-cache.png"),
            addedAt: Date(), bookmarkData: Data(), screenshotMetadata: metadata)
        let text = FileShelfItem(id: UUID(), url: URL(fileURLWithPath: "/text.txt"),
            addedAt: Date(), bookmarkData: Data(), text: "ordinary")
        let note = FileShelfItem(id: UUID(), url: URL(fileURLWithPath: "/note.txt"),
            addedAt: Date(), bookmarkData: Data(), text: "note", noteLocation: .desktop(displayID: "test", displayName: "Test"))
        let items = [text, screenshot, note]
        #expect(FileShelfCategory.fileShelfCases.contains(.screenshot))
        #expect(!FileShelfCategory.clipboardCases.contains(.screenshot))
        #expect(!FileShelfCategory.clipboardCases.contains(.note))
        #expect(ShelfModuleView.categoryCount(for: .screenshot, in: items) == 1)
        #expect(ShelfModuleView.categoryCount(for: .all, in: items) == 3)
        #expect(ShelfModuleView.categoryCount(for: .image, in: items) == 0)
        #expect(ShelfModuleView.categoryCount(for: .note, in: items) == 1)
        #expect(ShelfModuleView.filteredItems(in: items, category: .screenshot, searchText: "") == [screenshot])
        #expect(ShelfModuleView.filteredItems(in: items, category: .all, searchText: "") == items)
        for query in ["ORIGINAL APP", "test.original", "654", "1970-01-01", "320×160"] {
            #expect(ShelfModuleView.filteredItems(in: items, category: .all, searchText: query) == [screenshot])
        }
        #expect(ShelfModuleView.filteredItems(in: items, category: .screenshot, searchText: "ordinary").isEmpty)
    }

    @Test
    func toolbarPlacesStashBetweenPinAndCopyInBothPresentationsAndCaptureSnapshotsSourceAtEntry() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let editorSource = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/ScreenshotEditorView.swift"), encoding: .utf8)
        let pin = try #require(editorSource.range(of: #"iconButton(model.isPinned ? "pin.fill""#))
        let stash = try #require(editorSource.range(of: #"iconButton("tray.and.arrow.down", title: AppLocalization.text("暂存"))"#))
        let copy = try #require(editorSource.range(of: #"iconButton("doc.on.doc", title: AppLocalization.text("复制"))"#))
        #expect(pin.lowerBound < stash.lowerBound && stash.lowerBound < copy.lowerBound)
        #expect(editorSource.components(separatedBy: "onStash: { [weak self] in self?.stashImage() }").count == 3)
        let appSource = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/ZislaApp.swift"), encoding: .utf8)
        let snapshot = try #require(appSource.range(of: "let sourceSnapshot = ScreenshotSourceSnapshot("))
        let presentation = try #require(appSource.range(of: "ScreenshotModalSession.dismissForSelectionPresentation()"))
        #expect(snapshot.lowerBound < presentation.lowerBound)
        #expect(appSource.contains("sourceSnapshot: sourceSnapshot"))
    }

    @Test
    func exportWritesTheDatabasePNGWithoutDependingOnCachedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-stash-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = try #require(ScreenshotEditorModel(image: makeImage()).pngData())
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        let item = try store.stashScreenshot(png: png, metadata: ShelfScreenshotMetadata(
            source: ScreenshotSourceSnapshot(applicationName: nil, bundleIdentifier: nil, processIdentifier: nil),
            isLongScreenshot: false, initialCaptureRect: .zero, captureRect: .zero, screenFrame: nil,
            displayIdentifier: nil, pixelWidth: 320, pixelHeight: 160))
        try FileManager.default.removeItem(at: item.url)
        let destination = directory.appendingPathComponent("chosen.png")
        try ScreenshotImageExport.writePNG(store.screenshotData(id: item.id), to: destination)
        #expect(try Data(contentsOf: destination) == png)
        #expect(store.items.count == 1)
        #expect(throws: (any Error).self) {
            try ScreenshotImageExport.writePNG(png, to: directory.appendingPathComponent("missing/chosen.png"))
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/AppModel.swift"), encoding: .utf8)
        #expect(source.contains("ScreenshotImageExport.presentSavePanel(for: try shelf.screenshotData(id: item.id))"))
    }

    private func makeImage() throws -> NSImage {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 160,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<160 {
            for x in 0..<320 { bitmap.setColor(NSColor(calibratedRed: CGFloat(x) / 320, green: CGFloat(y) / 160, blue: 0.3, alpha: 1), atX: x, y: y) }
        }
        let image = NSImage(size: CGSize(width: 160, height: 80))
        image.addRepresentation(bitmap)
        return image
    }
}

private struct TestStashError: LocalizedError {
    var errorDescription: String? { "真实 SQLite 错误" }
}
