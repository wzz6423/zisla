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
            let host = NSHostingView(rootView: FileShelfShakeView(settingsStore: settings, onItems: { _ in }))
            let panel = FileShelfShakeController.makeWindow(contentView: host, frame: CGRect(origin: .zero, size: FileShelfShakeLayout.size))
            defer { panel.close() }
            host.layoutSubtreeIfNeeded()
            let views = descendants(of: host)
            if reduceTransparency {
                #expect(!views.contains { $0 is NSVisualEffectView })
                if #available(macOS 26.0, *) { #expect(!views.contains { $0 is NSGlassEffectView }) }
            } else if #available(macOS 26.0, *), style == .transparent {
                #expect(views.contains { $0 is NSGlassEffectView })
            } else {
                #expect(views.contains { $0 is NSVisualEffectView })
            }
        }
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

@Suite(.serialized)
@MainActor
struct FileShelfShakeControllerTests {
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
