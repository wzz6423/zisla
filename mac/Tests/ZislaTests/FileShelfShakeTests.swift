import AppKit
import Foundation
import SwiftUI
import Testing
import XCTest
import ZislaCore
import ZislaKit

@testable import Zisla

struct FileShelfShakeSessionTests {
    @Test(arguments: [(false, true), (true, false), (false, false)])
    func requiresBothALiveDragAndFiles(flags: (Bool, Bool)) {
        var session = FileShelfShakeSession()
        for index in 0..<12 {
            let triggered = session.record(CGPoint(x: index.isMultiple(of: 2) ? 0 : 50, y: 0),
                                           at: Double(index) * 0.1, changeCount: 1,
                                           hasSupportedPayload: flags.0, hasFilePayload: flags.1)
            #expect(!triggered)
        }
    }

    @Test
    func differentDragsCannotCombineTheirReversals() {
        var session = FileShelfShakeSession()
        for index in 0..<8 {
            let triggered = session.record(CGPoint(x: index.isMultiple(of: 2) ? 0 : 50, y: 0),
                                           at: Double(index) * 0.1, changeCount: index / 4,
                                           hasSupportedPayload: true, hasFilePayload: true)
            #expect(!triggered)
        }
    }

    @Test
    func invalidPayloadDiscardsAPartialShake() {
        var session = FileShelfShakeSession()
        for index in 0..<8 {
            let triggered = session.record(CGPoint(x: index.isMultiple(of: 2) ? 0 : 50, y: 0),
                                           at: Double(index) * 0.1, changeCount: 1,
                                           hasSupportedPayload: index != 3, hasFilePayload: true)
            #expect(!triggered)
        }
    }
}

struct FileShelfShakeLayoutTests {
    @Test
    func appearsBesideThePointerAndFlipsAtTheRightEdge() {
        let screen = CGRect(x: 0, y: 24, width: 1_440, height: 850)
        let central = FileShelfShakeLayout.frame(near: CGPoint(x: 600, y: 400), in: screen)
        #expect(central.minX == 628)
        #expect(central.midY == 400)
        #expect(central.size == FileShelfShakeLayout.size)
        let edge = FileShelfShakeLayout.frame(near: CGPoint(x: 1_430, y: 400), in: screen)
        #expect(edge.maxX == 1_402)
        #expect(screen.contains(edge))
    }

    @Test
    func staysWithinEveryEdgeOnAnOffsetDisplay() {
        let screen = CGRect(x: -1_920, y: -300, width: 1_920, height: 1_040)
        for x in stride(from: screen.minX, through: screen.maxX, by: 240) {
            for y in stride(from: screen.minY, through: screen.maxY, by: 130) {
                let frame = FileShelfShakeLayout.frame(near: CGPoint(x: x, y: y), in: screen)
                #expect(screen.insetBy(dx: 8, dy: 8).contains(frame))
                #expect(frame.size == FileShelfShakeLayout.size)
            }
        }
    }

    @Test
    func scalesToASmallVisibleFrame() {
        let screen = CGRect(x: 100, y: 100, width: 160, height: 120)
        let frame = FileShelfShakeLayout.frame(near: CGPoint(x: 180, y: 160), in: screen)
        #expect(frame == screen.insetBy(dx: 8, dy: 8))
    }

    @Test @MainActor
    func nativePanelAcceptsDropsWithoutTakingKeyboardFocus() {
        let panel = FileShelfShakeController.makeWindow(contentView: NSView(), frame: CGRect(origin: .zero, size: FileShelfShakeLayout.size))
        defer { panel.close() }
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.avoidsAppActivation)
        #expect(!panel.ignoresMouseEvents)
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level.rawValue > NSWindow.Level.normal.rawValue)
        #expect(panel.level.rawValue < CGWindowLevelForKey(.draggingWindow))
    }
}

struct FileShelfShakeViewTests {
    @Test(arguments: AppLanguage.allCases) @MainActor
    func floatingWindowProvidesTwoSeparateDropTargets(language: AppLanguage) throws {
        let name = "zisla-shake-targets-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let settings = FeatureSettingsStore(defaults: defaults)
        defer {
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: name)
        }
        var shared: [TransferDropItem] = []
        var received: [FileShelfDropItem] = []
        var sharingAnchor: NSView?
        let host = NSHostingView(rootView: FileShelfShakeView(settingsStore: settings, onItems: { received = $0 }, onShare: {
            shared = $0
            sharingAnchor = $1
        })
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        host.sizingOptions = []
        let panel = FileShelfShakeController.makeWindow(contentView: host, frame: CGRect(origin: .zero, size: FileShelfShakeLayout.size))
        defer { panel.close() }
        host.layoutSubtreeIfNeeded()
        let targets = descendants(of: host).compactMap { $0 as? ShelfDropHostingView }.sorted {
            $0.convert($0.bounds, to: host).minX < $1.convert($1.bounds, to: host).minX
        }
        try #require(targets.count == 2, "Sharing and the shelf need independent native drop targets.")
        let left = targets[0].convert(targets[0].bounds, to: host)
        let right = targets[1].convert(targets[1].bounds, to: host)
        #expect(left.width == 220 && right.width == 220)
        #expect(right.minX - left.maxX == 8)
        #expect(left.height == 144 && right.height == 144)
        #expect(targets[0].registeredDraggedTypes == [.fileURL])
        #expect(Set(targets[1].registeredDraggedTypes) == Set(TransferPasteboard.shelfDropTypes))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try (0..<2).map { index in
            let file = directory.appendingPathComponent("file-\(index).txt")
            try Data("original \(index)".utf8).write(to: file)
            return file.standardizedFileURL
        }
        let pasteboard = NSPasteboard(name: .init(name))
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects(files.map { $0 as NSURL })
        let drag = DragInfo(pasteboard: pasteboard)
        #expect(targets[0].draggingEntered(drag) == .copy)
        #expect(targets[0].performDragOperation(drag))
        #expect(shared == files.map(TransferDropItem.file))
        #expect(sharingAnchor === targets[0])
        #expect(sharingAnchor?.window === panel)
        #expect(received.isEmpty)
        shared = []
        #expect(targets[1].draggingEntered(drag) == .copy)
        #expect(targets[1].performDragOperation(drag))
        #expect(shared.isEmpty)
        #expect(received.compactMap { item -> TransferPasteboardPayload? in
            if case .content(let payload) = item { return payload }
            return nil
        } == files.map(TransferPasteboardPayload.file))
        for (index, file) in files.enumerated() {
            #expect(try String(contentsOf: file, encoding: .utf8) == "original \(index)")
        }

        received = []
        for value in [nil, "https://example.invalid/file", directory.appendingPathComponent("missing.txt").absoluteString] {
            pasteboard.clearContents()
            if let value { pasteboard.setString(value, forType: .fileURL) }
            #expect(!targets[0].performDragOperation(drag))
            #expect(!targets[1].performDragOperation(drag))
            #expect(shared.isEmpty && received.isEmpty)
        }
        pasteboard.clearContents()
        pasteboard.setString("plain text", forType: .string)
        #expect(targets[0].draggingEntered(drag).isEmpty)
        #expect(targets[1].draggingEntered(drag) == .copy)
        #expect(!targets[0].performDragOperation(drag))
        #expect(shared.isEmpty && received.isEmpty)
        #expect(!panel.isVisible)
    }

    @Test @MainActor
    func floatingTargetUsesTheSelectedIslandMaterial() throws {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let name = "zisla-shake-material-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let settings = FeatureSettingsStore(defaults: defaults)
        defer {
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: name)
        }
        for style in IslandVisualStyle.allCases {
            settings.settings.islandVisualStyle = style
            let host = NSHostingView(rootView: FileShelfShakeView(settingsStore: settings, onItems: { _ in }, onShare: { _, _ in }))
            let panel = FileShelfShakeController.makeWindow(contentView: host, frame: CGRect(origin: .zero, size: FileShelfShakeLayout.size))
            defer { panel.close() }
            host.layoutSubtreeIfNeeded()
            let views = descendants(of: host)
            if reduceTransparency {
                #expect(!views.contains { $0 is NSVisualEffectView })
                if #available(macOS 26.0, *) { #expect(!views.contains { $0 is NSGlassEffectView }) }
            } else if #available(macOS 26.0, *), style == .transparent {
                let glass = try #require(views.compactMap { $0 as? NSGlassEffectView }.first)
                #expect(glass.style == .clear)
                #expect(glass.tintColor == nil)
            } else {
                #expect(views.contains { $0 is NSVisualEffectView })
            }
        }
    }

    @Test @MainActor
    func frostedFloatingTargetKeepsTheDesktopShielded() throws {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let name = "zisla-shake-opacity-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let settings = FeatureSettingsStore(defaults: defaults)
        defer {
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: name)
        }
        settings.settings.islandVisualStyle = .frosted
        let host = NSHostingView(rootView: FileShelfShakeView(settingsStore: settings, onItems: { _ in }, onShare: { _, _ in }))
        let panel = FileShelfShakeController.makeWindow(contentView: host, frame: CGRect(origin: .zero, size: FileShelfShakeLayout.size))
        defer { panel.close() }
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let pixel = try #require(bitmap.colorAt(x: Int(12 * scale), y: Int(72 * scale)))
        if reduceTransparency {
            #expect(pixel.alphaComponent > 0.99, "Reduced transparency must give the standalone target an opaque backing.")
        } else {
            #expect(pixel.alphaComponent > 0.9, "Frosted glass must strongly shield the desktop behind this standalone target.")
        }
        #expect(!panel.isVisible)
    }

    @Test(arguments: IslandVisualStyle.allCases, [false, true]) @MainActor
    func standaloneBackingIsDenseOnlyWhenItsMaterialNeedsIt(style: IslandVisualStyle, reduceTransparency: Bool) throws {
        let host = NSHostingView(rootView: FileShelfShakeView.standaloneBacking(style: style, reduceTransparency: reduceTransparency))
        host.frame = CGRect(origin: .zero, size: FileShelfShakeLayout.size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let pixel = try #require(bitmap.colorAt(x: Int(12 * scale), y: Int(72 * scale)))
        if reduceTransparency {
            #expect(pixel.alphaComponent > 0.99, "Both styles must become opaque when transparency is reduced.")
        } else if style == .frosted {
            #expect(pixel.alphaComponent > 0.87, "The standalone frosted material needs a dense backing.")
            #expect(pixel.alphaComponent < 0.9, "Frosted mode must retain some translucency.")
        } else {
            #expect(pixel.alphaComponent == 0, "Liquid glass must not gain a dark backing.")
        }
        let corner = try #require(bitmap.colorAt(x: 0, y: 0))
        #expect(corner.alphaComponent == 0, "The backing must stay inside the rounded panel.")
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor
    private final class DragInfo: NSObject, NSDraggingInfo {
        let draggingPasteboard: NSPasteboard
        var draggingDestinationWindow: NSWindow? { nil }
        var draggingSourceOperationMask: NSDragOperation { .copy }
        var draggingLocation: NSPoint { .zero }
        var draggedImageLocation: NSPoint { .zero }
        nonisolated var draggedImage: NSImage? { nil }
        var draggingSource: Any? { nil }
        var draggingSequenceNumber: Int { 1 }
        var draggingFormation: NSDraggingFormation = .none
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 0
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }

        init(pasteboard: NSPasteboard) { draggingPasteboard = pasteboard }
        func slideDraggedImage(to screenPoint: NSPoint) {}
        nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
        func resetSpringLoading() {}
        func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass],
                                    searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    }
}

@MainActor
struct IslandGlassStandaloneSurfaceTests {
    @Test(arguments: [false, true])
    func frostedInputBlursTheCorrectBackdrop(isStandalone: Bool) throws {
        let host = NSHostingView(rootView: Group {
            if isStandalone {
                Color.clear.islandGlassSurface(.input, cornerRadius: 14, isStandalone: true)
            } else {
                Color.clear.islandGlassSurface(.input, cornerRadius: 14)
            }
        }
            .environment(\.islandVisualStyle, .frosted)
            .environment(\.colorScheme, .dark))
        let panel = FileShelfShakeController.makeWindow(contentView: host, frame: CGRect(x: 0, y: 0, width: 360, height: 44))
        defer { panel.close() }
        host.layoutSubtreeIfNeeded()
        let effects = descendants(of: host).compactMap { $0 as? NSVisualEffectView }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            #expect(effects.isEmpty)
        } else {
            let effect = try #require(effects.first)
            #expect(effect.material == .sidebar)
            #expect(effect.blendingMode == (isStandalone ? .behindWindow : .withinWindow))
        }
        let bitmap = try render(host)
        let alpha = try color(bitmap, at: CGPoint(x: 180, y: 22), in: host.bounds.size).alphaComponent
        #expect(isStandalone ? alpha > 0.9 : alpha < 0.6)
        #expect(!panel.isVisible)
    }

    @Test(arguments: [false, true])
    func liquidInputPreservesNativeGlassAndAppliesTheStandaloneCrown(isStandalone: Bool) throws {
        let host = NSHostingView(rootView: Color.clear
            .islandGlassSurface(.input, cornerRadius: 14, isStandalone: isStandalone)
            .environment(\.islandVisualStyle, .transparent))
        host.frame = CGRect(x: 0, y: 0, width: 360, height: 44)
        host.layoutSubtreeIfNeeded()
        let views = descendants(of: host)
        if #available(macOS 26.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let glass = try #require(views.compactMap { $0 as? NSGlassEffectView }.first)
            #expect(glass.style == .clear)
            #expect(glass.tintColor == nil)
            #expect(glass.cornerRadius == 14)
            // Hide only the native shell so its opaque offscreen cache cannot mask the crown.
            glass.alphaValue = 0
            let bitmap = try render(host)
            let top = try color(bitmap, at: CGPoint(x: 180, y: 6), in: host.bounds.size).alphaComponent
            let middle = try color(bitmap, at: CGPoint(x: 180, y: 15), in: host.bounds.size).alphaComponent
            let lower = try color(bitmap, at: CGPoint(x: 180, y: 31), in: host.bounds.size).alphaComponent
            let bottom = try color(bitmap, at: CGPoint(x: 180, y: 43), in: host.bounds.size).alphaComponent
            #expect(isStandalone ? top > 0.99 : top < 0.97)
            #expect(isStandalone ? middle > 0.75 : middle < 0.7)
            #expect(isStandalone ? lower > 0.24 : lower < 0.18)
            #expect(bottom == 0)
        }
        #expect(host.window == nil)
    }

    @Test(arguments: IslandVisualStyle.allCases, [false, true])
    func standaloneInputBackingPreservesLiquidGlassAndAccessibility(style: IslandVisualStyle, reduceTransparency: Bool) throws {
        let host = NSHostingView(rootView: IslandGlassStandaloneBacking(
            shape: IslandSurfaceGeometry.moduleContentShape(cornerRadius: 14),
            visualStyle: style,
            reduceTransparency: reduceTransparency
        ))
        host.frame = CGRect(x: 0, y: 0, width: 360, height: 44)
        let bitmap = try render(host)
        let pixel = try color(bitmap, at: CGPoint(x: 180, y: 22), in: host.bounds.size)
        let alpha = pixel.alphaComponent
        if reduceTransparency {
            #expect(alpha > 0.99)
        } else if style == .frosted {
            #expect(alpha > 0.89 && alpha < 0.91)
        } else {
            #expect(alpha == 0)
        }
        if reduceTransparency || style == .frosted {
            let tint = try #require(pixel.usingColorSpace(.sRGB))
            #expect(tint.redComponent < 0.01 && tint.greenComponent < 0.01 && tint.blueComponent < 0.01)
        }
        let corner = try color(bitmap, at: .zero, in: host.bounds.size)
        #expect(corner.alphaComponent == 0)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func render(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private func color(_ bitmap: NSBitmapImageRep, at point: CGPoint, in size: CGSize) throws -> NSColor {
        let scale = CGFloat(bitmap.pixelsWide) / size.width
        return try #require(bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)))
    }
}

@Suite(.serialized)
@MainActor
struct FileShelfShakeControllerTests {
    @Test
    func sharingKeepsTheAnchorAliveUntilThePickerEnds() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.files()
        fixture.shake()
        let timer = try #require(fixture.controller.releaseTimer)
        fixture.controller.handlePointer(at: .zero, interaction: .dragEnded)
        let dismissal = try #require(fixture.controller.dismissTask)
        try await fixture.waitForDismissalSleep()
        let anchor = NSView()
        let items: [TransferDropItem] = [.file(URL(fileURLWithPath: "/tmp/share.txt"))]
        fixture.controller.share(items, from: anchor, forChangeCount: fixture.pasteboard.changeCount)
        #expect(fixture.sharedItems == items)
        #expect(fixture.sharingAnchor === anchor)
        #expect(fixture.receivedCount == 0)
        #expect(fixture.controller.isPresented && fixture.controller.isSharing)
        #expect(!timer.isValid && fixture.controller.releaseTimer == nil)
        #expect(dismissal.isCancelled && fixture.controller.dismissTask == nil)

        fixture.controller.handlePointer(at: .zero, interaction: .moved)
        fixture.controller.handlePointer(at: .zero, interaction: .dragEnded)
        fixture.controller.share(items, from: NSView(), forChangeCount: fixture.pasteboard.changeCount)
        fixture.controller.receive([.content(.text("duplicate"))], forChangeCount: fixture.pasteboard.changeCount)
        #expect(fixture.controller.dismissTask == nil)
        #expect(fixture.sharedItems == items && fixture.sharingAnchor === anchor)
        #expect(fixture.receivedCount == 0)
        await fixture.gate.release()
        await dismissal.value
        #expect(fixture.controller.isPresented)
        fixture.controller.sharingDidEnd()
        #expect(!fixture.controller.isPresented && !fixture.controller.isSharing)
        #expect(fixture.controller.releaseTimer == nil && fixture.controller.dismissTask == nil)
    }

    @Test
    func staleAndDisabledSharingCallbacksCannotAffectTheCurrentDrag() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.files()
        fixture.shake()
        let oldChangeCount = fixture.pasteboard.changeCount
        fixture.files()
        fixture.shake(start: 2)
        let items: [TransferDropItem] = [.file(URL(fileURLWithPath: "/tmp/share.txt"))]
        fixture.controller.share(items, from: NSView(), forChangeCount: oldChangeCount)
        fixture.controller.sharingDidEnd()
        #expect(fixture.sharedItems.isEmpty)
        #expect(fixture.controller.isPresented && !fixture.controller.isSharing)
        fixture.settings.settings.fileShelfShakeEnabled = false
        fixture.controller.share(items, from: NSView(), forChangeCount: fixture.pasteboard.changeCount)
        #expect(fixture.sharedItems.isEmpty)
        #expect(!fixture.controller.isPresented && !fixture.controller.isSharing)
    }

    @Test
    func sharingRequiresTheCompletedShakePresentation() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.files()
        fixture.controller.handlePointer(at: .zero, interaction: .dragging(hasSupportedPayload: true), timestamp: 0)
        fixture.controller.share([.file(URL(fileURLWithPath: "/tmp/share.txt"))], from: NSView(), forChangeCount: fixture.pasteboard.changeCount)
        #expect(fixture.sharedItems.isEmpty)
        #expect(!fixture.controller.isPresented && !fixture.controller.isSharing)
    }

    @Test(arguments: ["lock", "screenshot", "disable", "display", "stop"])
    func sharingReleasesTheFloatingWindowWhenItsEnvironmentChanges(change: String) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.files()
        fixture.shake()
        fixture.controller.share([.file(URL(fileURLWithPath: "/tmp/share.txt"))], from: NSView(), forChangeCount: fixture.pasteboard.changeCount)
        switch change {
        case "lock": fixture.controller.setScreenLocked(true)
        case "screenshot": fixture.controller.setScreenshotActive(true)
        case "disable": fixture.settings.settings.fileShelfEnabled = false
        case "display": NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        default: fixture.controller.stop()
        }
        #expect(!fixture.controller.isPresented && !fixture.controller.isSharing)
        #expect(fixture.controller.releaseTimer == nil && fixture.controller.dismissTask == nil)
        #expect(fixture.receivedCount == 0)
    }

    @Test(arguments: [false, true], [false, true])
    func shakeRequiresBothSwitchesWhileShelfOnlyRequiresItsParent(shelfEnabled: Bool, shakeEnabled: Bool) throws {
        let fixture = try Fixture(settings: FeatureSettings(fileShelfEnabled: shelfEnabled, fileShelfShakeEnabled: shakeEnabled))
        defer { fixture.close() }
        #expect(IslandModule.shelf.isEnabled(in: fixture.settings.settings) == shelfEnabled)
        #expect(fixture.controller.isMonitoring == (shelfEnabled && shakeEnabled))
        fixture.files()
        fixture.shake()
        #expect(fixture.controller.isPresented == (shelfEnabled && shakeEnabled))
        #expect(fixture.presentedPoints.count == (shelfEnabled && shakeEnabled ? 1 : 0))
    }

    @Test
    func disablingShakeClosesTheTargetCancelsResourcesAndRejectsLateDrops() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.files()
        fixture.shake()
        let releaseTimer = try #require(fixture.controller.releaseTimer)
        fixture.controller.handlePointer(at: .zero, interaction: .dragEnded)
        let dismissal = try #require(fixture.controller.dismissTask)
        try await fixture.waitForDismissalSleep()
        fixture.settings.settings.fileShelfShakeEnabled = false
        #expect(fixture.settings.settings.fileShelfEnabled)
        #expect(IslandModule.shelf.isEnabled(in: fixture.settings.settings))
        #expect(!fixture.controller.isMonitoring)
        #expect(!fixture.controller.isPresented)
        #expect(!releaseTimer.isValid)
        #expect(fixture.controller.releaseTimer == nil)
        #expect(dismissal.isCancelled)
        #expect(fixture.controller.dismissTask == nil)
        fixture.controller.receive([.content(.text("late callback"))], forChangeCount: fixture.pasteboard.changeCount)
        #expect(fixture.receivedCount == 0)
        fixture.settings.settings.fileShelfShakeEnabled = true
        #expect(fixture.controller.isMonitoring)
        fixture.shake(start: 2)
        #expect(fixture.controller.isPresented)
        await fixture.gate.release()
        await dismissal.value
        #expect(fixture.controller.isPresented)
    }

    @Test
    func reEnablingShelfPreservesTheShakeOptOut() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.settings.settings.fileShelfShakeEnabled = false
        fixture.settings.settings.fileShelfEnabled = false
        fixture.settings.settings.fileShelfEnabled = true
        #expect(!fixture.settings.settings.fileShelfShakeEnabled)
        #expect(IslandModule.shelf.isEnabled(in: fixture.settings.settings))
        #expect(!fixture.controller.isMonitoring)
        fixture.files()
        fixture.shake()
        #expect(!fixture.controller.isPresented)
        fixture.settings.settings.fileShelfEnabled = false
        fixture.settings.settings.fileShelfShakeEnabled = true
        #expect(!fixture.controller.isMonitoring)
        fixture.settings.settings.fileShelfEnabled = true
        #expect(fixture.controller.isMonitoring)
        fixture.shake(start: 2)
        #expect(fixture.controller.isPresented)
    }

    @Test
    func onlyFileDragsOpenOneStationaryWindow() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.pasteboard.setString("plain text", forType: .string)
        fixture.shake()
        #expect(!fixture.controller.isPresented)
        fixture.files()
        fixture.shake(supported: false)
        #expect(!fixture.controller.isPresented)
        fixture.shake()
        #expect(fixture.controller.isPresented)
        #expect(fixture.presentedPoints.count == 1)
        let originalPoint = fixture.presentedPoints.first
        fixture.shake(start: 2)
        #expect(fixture.presentedPoints == [originalPoint!])
    }

    @Test
    func filePromisesCanRevealTheTargetWithoutAFileURL() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let promiseType = try #require(NSFilePromiseReceiver.readableDraggedTypes.first)
        fixture.pasteboard.declareTypes([.init(promiseType)], owner: nil)
        fixture.shake()
        #expect(fixture.controller.isPresented)
    }

    @Test
    func newDragAndOrdinaryMovementClearThePreviousTarget() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.files()
        fixture.shake()
        fixture.files()
        fixture.controller.handlePointer(at: .zero, interaction: .dragging(hasSupportedPayload: true), timestamp: 1)
        #expect(!fixture.controller.isPresented)
        fixture.shake(start: 2)
        #expect(fixture.controller.isPresented)
        fixture.controller.handlePointer(at: .zero, interaction: .moved)
        let dismissal = try #require(fixture.controller.dismissTask)
        try await fixture.waitForDismissalSleep()
        await fixture.gate.release()
        await dismissal.value
        #expect(!fixture.controller.isPresented)
    }

    @Test
    func featureSwitchLockAndScreenshotStopMonitoringAndRejectLateDrops() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.files()
        fixture.shake()
        let releaseTimer = try #require(fixture.controller.releaseTimer)
        fixture.settings.settings.fileShelfEnabled = false
        #expect(!releaseTimer.isValid)
        #expect(!fixture.controller.isMonitoring)
        #expect(!fixture.controller.isPresented)
        fixture.controller.receive([.content(.text("late callback"))], forChangeCount: fixture.pasteboard.changeCount)
        #expect(fixture.receivedCount == 0)
        fixture.settings.settings.fileShelfEnabled = true
        #expect(fixture.controller.isMonitoring)
        fixture.shake(start: 1)
        fixture.controller.setScreenLocked(true)
        #expect(!fixture.controller.isPresented)
        #expect(!fixture.controller.isMonitoring)
        fixture.controller.setScreenshotActive(true)
        fixture.controller.setScreenLocked(false)
        #expect(!fixture.controller.isMonitoring)
        fixture.controller.setScreenshotActive(false)
        #expect(fixture.controller.isMonitoring)
        fixture.shake(start: 2)
        #expect(fixture.controller.isPresented)
        fixture.controller.stop()
        #expect(!fixture.controller.isMonitoring)
        #expect(!fixture.controller.isPresented)
        fixture.settings.settings.fileShelfEnabled = false
        fixture.settings.settings.fileShelfEnabled = true
        #expect(!fixture.controller.isMonitoring)
    }

    @Test
    func mouseUpLeavesTimeForTheNativeDropCallback() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.files()
        fixture.shake()
        fixture.controller.handlePointer(at: .zero, interaction: .dragEnded)
        let dismissal = try #require(fixture.controller.dismissTask)
        try await fixture.waitForDismissalSleep()
        #expect(fixture.controller.isPresented)
        fixture.controller.handlePointer(at: .zero, interaction: .moved)
        #expect(fixture.controller.isPresented)
        fixture.controller.receive([.content(.text("drop received"))], forChangeCount: fixture.pasteboard.changeCount)
        #expect(fixture.receivedCount == 1)
        #expect(!fixture.controller.isPresented)
        await fixture.gate.release()
        await dismissal.value
    }

    @Test
    func aMissedMouseUpStillDismissesTheTarget() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.files()
        fixture.shake()
        fixture.buttons = 0
        try await fixture.waitForDismissalSleep()
        let dismissal = try #require(fixture.controller.dismissTask)
        await fixture.gate.release()
        await dismissal.value
        #expect(!fixture.controller.isPresented)
        #expect(fixture.controller.dismissTask == nil)
    }

    @Test
    func cancelledDismissalCannotCloseANewDrag() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.files()
        fixture.shake()
        fixture.controller.handlePointer(at: .zero, interaction: .dragEnded)
        let oldDismissal = try #require(fixture.controller.dismissTask)
        try await fixture.waitForDismissalSleep()
        fixture.files()
        fixture.shake(start: 2)
        await fixture.gate.release()
        await oldDismissal.value
        #expect(fixture.controller.isPresented)
        #expect(fixture.presentedPoints.count == 2)
    }

    @Test
    func aLateDropFromAnOldWindowCannotAffectTheNewDrag() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.files()
        fixture.shake()
        let oldChangeCount = fixture.pasteboard.changeCount
        fixture.controller.handlePointer(at: .zero, interaction: .dragEnded)
        fixture.files()
        fixture.shake(start: 2)
        fixture.controller.receive([.content(.text("stale"))], forChangeCount: oldChangeCount)
        #expect(fixture.receivedCount == 0)
        #expect(fixture.controller.isPresented)
        fixture.controller.receive([.content(.text("current"))], forChangeCount: fixture.pasteboard.changeCount)
        #expect(fixture.receivedCount == 1)
        #expect(!fixture.controller.isPresented)
    }

    @Test
    func displayChangesDismissTheTarget() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.files()
        fixture.shake()
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(!fixture.controller.isPresented)
    }

    @Test
    func receivedFilesUseTheExistingStoreWithoutMovingTheOriginals() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-shake-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try (0..<3).map { index in
            let url = directory.appendingPathComponent("file-\(index).txt")
            try Data("original \(index)".utf8).write(to: url)
            return url
        }
        let store = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        fixture.onItems = { items in store.receive(items) { #expect($0 == 3) } }
        fixture.files()
        fixture.shake()
        fixture.controller.receive(files.map { .content(.file($0)) }, forChangeCount: fixture.pasteboard.changeCount)
        #expect(store.items.map(\.url) == files)
        for (index, url) in files.enumerated() {
            #expect(try String(contentsOf: url, encoding: .utf8) == "original \(index)")
        }
        #expect(!fixture.controller.isPresented)
        let restored = FileShelfStore(storageURL: directory.appendingPathComponent("shelf.json"))
        #expect(restored.items.map(\.url) == files)
    }

    @MainActor
    private final class Fixture {
        let name = "zisla-shake-tests-\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: FeatureSettingsStore
        let pasteboard: NSPasteboard
        let gate = DismissalGate()
        var controller: FileShelfShakeController!
        var presentedPoints: [CGPoint] = []
        var receivedCount = 0
        var sharedItems: [TransferDropItem] = []
        var sharingAnchor: NSView?
        var buttons = 1
        var onItems: (([FileShelfDropItem]) -> Void)?

        init(settings initialSettings: FeatureSettings = .default) throws {
            defaults = try #require(UserDefaults(suiteName: name))
            settings = FeatureSettingsStore(defaults: defaults)
            settings.settings = initialSettings
            pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
            controller = FileShelfShakeController(
                settingsStore: settings,
                languageStore: AppLanguageStore(defaults: defaults),
                dragPasteboard: pasteboard,
                windowPresenter: { [weak self] _, point in self?.presentedPoints.append(point) },
                dismissSleeper: { [gate] in await gate.sleep(for: $0) },
                pressedMouseButtons: { [weak self] in self?.buttons ?? 0 },
                onItems: { [weak self] items in
                    self?.receivedCount += items.count
                    self?.onItems?(items)
                },
                onShare: { [weak self] items, anchor in
                    self?.sharedItems += items
                    self?.sharingAnchor = anchor
                }
            )
        }

        func files() {
            pasteboard.clearContents()
            pasteboard.setString("file:///tmp/shake-fixture.txt", forType: .fileURL)
        }

        func shake(start: TimeInterval = 0, supported: Bool = true) {
            for index in 0..<5 {
                controller.handlePointer(
                    at: CGPoint(x: index.isMultiple(of: 2) ? 600 : 650, y: 400),
                    interaction: .dragging(hasSupportedPayload: supported),
                    timestamp: start + Double(index) * 0.1
                )
            }
        }

        func waitForDismissalSleep() async throws {
            let result = await XCTWaiter.fulfillment(of: [gate.started], timeout: 5)
            if result != .completed { await gate.release() }
            try #require(result == .completed)
            #expect(await gate.durations == [.milliseconds(200)])
        }

        func close() {
            controller.stop()
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: name)
            pasteboard.releaseGlobally()
        }
    }
}
