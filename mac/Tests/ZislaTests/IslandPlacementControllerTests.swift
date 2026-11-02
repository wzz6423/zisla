import AppKit
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct IslandPlacementControllerTests {
    @Test(arguments: IslandEdge.allCases)
    func draggingClampsThePreviewBeforeMouseRelease(edge: IslandEdge) throws {
        let fixture = Fixture()
        fixture.show(initial: IslandPlacement(mode: .custom, edge: edge))
        let initial = try #require(fixture.controller.previewFrame)
        #expect(fixture.controller.beginDragging(at: CGPoint(x: initial.midX, y: initial.midY)))
        let screen = fixture.screens[0].frame
        let target: CGPoint
        switch edge {
        case .top: target = CGPoint(x: screen.midX, y: screen.maxY - 212)
        case .bottom: target = CGPoint(x: screen.midX, y: screen.minY + 212)
        case .left: target = CGPoint(x: screen.minX + 212, y: screen.midY)
        case .right: target = CGPoint(x: screen.maxX - 212, y: screen.midY)
        }
        fixture.controller.drag(to: target)
        let limited = try #require(fixture.controller.previewFrame)
        switch edge {
        case .top: #expect(screen.maxY - limited.maxY == 72)
        case .bottom: #expect(limited.minY - screen.minY == 72)
        case .left: #expect(limited.minX - screen.minX == 72)
        case .right: #expect(screen.maxX - limited.maxX == 72)
        }
        #expect(fixture.committed.isEmpty)
        fixture.controller.endDragging(at: target)
        #expect(fixture.controller.previewFrame == limited)
        fixture.controller.confirm()
        let saved = try #require(fixture.committed.first)
        fixture.show(initial: saved)
        #expect(fixture.controller.previewFrame == limited)
        fixture.controller.cancel()
        #expect(fixture.observer == nil)
    }

    @Test(arguments: IslandEdge.allCases)
    func draggingKeepsTheGripAndFollowsEveryAllowedGap(edge: IslandEdge) throws {
        for thickness: CGFloat in [24, 32, 40] {
            let fixture = Fixture()
            let configuration = ScreenLayoutConfiguration(pillSize: CGSize(width: 80, height: thickness))
            fixture.show(initial: IslandPlacement(mode: .custom, edge: edge), configuration: configuration)
            let initial = try #require(fixture.controller.previewFrame)
            let gripOffset = edge.isVertical ? CGPoint(x: thickness / 4, y: 0)
                : CGPoint(x: 0, y: thickness / 4)
            #expect(fixture.controller.beginDragging(at: CGPoint(x: initial.midX + gripOffset.x,
                y: initial.midY + gripOffset.y)))
            let screen = fixture.screens[0].frame
            for requestedGap: CGFloat in [0, 8, 28, thickness * 3, thickness * 3 + 40, 28] {
                let center: CGPoint
                switch edge {
                case .top: center = CGPoint(x: screen.midX + 50, y: screen.maxY - requestedGap - thickness / 2)
                case .bottom: center = CGPoint(x: screen.midX + 50, y: screen.minY + requestedGap + thickness / 2)
                case .left: center = CGPoint(x: screen.minX + requestedGap + thickness / 2, y: screen.midY + 50)
                case .right: center = CGPoint(x: screen.maxX - requestedGap - thickness / 2, y: screen.midY + 50)
                }
                fixture.controller.drag(to: CGPoint(x: center.x + gripOffset.x, y: center.y + gripOffset.y))
                let actual = try #require(fixture.controller.previewFrame)
                let expectedGap = min(thickness * 3, max(8, requestedGap))
                switch edge {
                case .top: #expect(screen.maxY - actual.maxY == expectedGap)
                case .bottom: #expect(actual.minY - screen.minY == expectedGap)
                case .left: #expect(actual.minX - screen.minX == expectedGap)
                case .right: #expect(screen.maxX - actual.maxX == expectedGap)
                }
                #expect((edge.isVertical ? actual.midY : actual.midX) == (edge.isVertical ? center.y : center.x))
                #expect(fixture.controller.selection?.inwardDistance == (expectedGap == 8 ? 0 : Double(expectedGap)))
                #expect(fixture.committed.isEmpty)
            }
            fixture.controller.cancel()
            #expect(fixture.committed.isEmpty && fixture.cancelled == 1)
            #expect(fixture.observer == nil && fixture.controller.windowCount == 0)
        }
    }

    @Test
    func draggingUpdatesOnlyTheDraftUntilConfirmation() throws {
        let fixture = Fixture()
        fixture.show(initial: IslandPlacement(mode: .custom, edge: .top))
        let original = try #require(fixture.controller.previewFrame)
        #expect(fixture.controller.beginDragging(at: CGPoint(x: original.midX, y: original.midY)))
        let destination = CGPoint(x: fixture.screens[0].frame.minX + 40, y: fixture.screens[0].frame.midY)
        fixture.controller.drag(to: destination)
        let dragged = try #require(fixture.controller.previewFrame)
        #expect(dragged.midX == destination.x)
        #expect(fixture.committed.isEmpty)
        fixture.controller.endDragging(at: destination)
        let snapped = try #require(fixture.controller.previewFrame)
        #expect(snapped.minX == fixture.screens[0].frame.minX + 28)
        #expect(snapped.size == CGSize(width: 24, height: 24))
        #expect(fixture.committed.isEmpty)

        fixture.controller.confirm()
        #expect(fixture.committed == [IslandPlacement(mode: .custom, edge: .left, offset: 0.5, inwardDistance: 28)])
        #expect(fixture.cancelled == 0)
        #expect(!fixture.controller.isSelecting)
        #expect(fixture.controller.windowCount == 0)
        #expect(fixture.observer == nil)
        #expect(fixture.presented.allSatisfy { $0.contentView == nil && !$0.isVisible })
    }

    @Test
    func releasingAtTheCenterKeepsTheDraftAtTheMaximumInwardDistance() throws {
        let fixture = Fixture()
        fixture.show(initial: IslandPlacement(mode: .custom, edge: .bottom))
        let frame = try #require(fixture.controller.previewFrame)
        #expect(fixture.controller.beginDragging(at: CGPoint(x: frame.midX, y: frame.midY)))
        let center = CGPoint(x: fixture.screens[0].frame.midX, y: fixture.screens[0].frame.midY)
        fixture.controller.endDragging(at: center)
        #expect(fixture.controller.selection?.edge == .bottom)
        #expect(fixture.controller.previewFrame?.minY == fixture.screens[0].frame.minY + 72)
        #expect(fixture.controller.selection?.inwardDistance == 72)
        fixture.controller.cancel()
    }

    @Test
    func escapeCancelsWithoutSavingAndRepeatedFinishDoesNothing() throws {
        let fixture = Fixture()
        fixture.show()
        let window = try #require(fixture.presented.first as? IslandPlacementWindow)
        window.keyDown(with: try keyEvent(code: 53, characters: "\u{1b}", window: window))
        fixture.controller.confirm()
        fixture.controller.cancel()

        #expect(fixture.committed.isEmpty)
        #expect(fixture.cancelled == 1)
        #expect(fixture.controller.windowCount == 0)
        #expect(fixture.observer == nil)
    }

    @Test
    func returnCommitsOnceAndCancelOperationKeepsTheSavedValue() throws {
        let fixture = Fixture()
        fixture.show(initial: IslandPlacement(mode: .custom, edge: .right, offset: 0.7, inwardDistance: 36))
        let window = try #require(fixture.presented.first as? IslandPlacementWindow)
        window.keyDown(with: try keyEvent(code: 36, characters: "\r", window: window))
        window.cancelOperation(nil)
        fixture.controller.confirm()
        #expect(fixture.committed == [IslandPlacement(mode: .custom, edge: .right, offset: 0.7, inwardDistance: 36)])
        #expect(fixture.cancelled == 0)
    }

    @Test
    func dragCanCrossIntoAnExternalScreenWithNegativeCoordinates() throws {
        let fixture = Fixture()
        fixture.screens.append(ScreenSnapshot(displayID: 2,
            frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1056)))
        fixture.show()
        #expect(fixture.controller.windowCount == 2)
        let frame = try #require(fixture.controller.previewFrame)
        #expect(fixture.controller.beginDragging(at: CGPoint(x: frame.midX, y: frame.midY)))
        fixture.controller.endDragging(at: CGPoint(x: -1800, y: -190))
        #expect(fixture.controller.selectedDisplayID == 2)
        #expect(fixture.controller.selection == IslandPlacement(mode: .custom, edge: .bottom, offset: 0.0625))
        #expect(fixture.controller.previewFrame?.minY == -192)
        fixture.controller.cancel()
    }

    @Test
    func draggingKeepsTheOriginalGripPointAndIgnoresBackgroundClicks() throws {
        let fixture = Fixture()
        fixture.show()
        let frame = try #require(fixture.controller.previewFrame)
        #expect(!fixture.controller.beginDragging(at: CGPoint(x: frame.midX, y: frame.minY - 200)))
        fixture.controller.drag(to: .zero)
        #expect(fixture.controller.previewFrame == frame)
        let grip = CGPoint(x: frame.midX + frame.width / 4, y: frame.midY)
        #expect(fixture.controller.beginDragging(at: grip))
        fixture.controller.drag(to: CGPoint(x: grip.x + 100, y: grip.y - 100))
        #expect(fixture.controller.previewFrame?.midX == frame.midX + 100)
        #expect(fixture.controller.previewFrame?.maxY == fixture.screens[0].frame.maxY - 72)
        #expect(fixture.controller.selection?.inwardDistance == 72)
        fixture.controller.cancel()
    }

    @Test
    func displayRemovalCancelsButScreenReorderingDoesNot() {
        let fixture = Fixture()
        fixture.screens.append(ScreenSnapshot(displayID: 2,
            frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1056)))
        fixture.show()
        fixture.screens.reverse()
        fixture.observer?()
        #expect(fixture.controller.isSelecting)
        fixture.screens.removeLast()
        fixture.observer?()
        #expect(!fixture.controller.isSelecting)
        #expect(fixture.cancelled == 1)
        #expect(fixture.committed.isEmpty)
        #expect(fixture.controller.windowCount == 0)
        #expect(fixture.observer == nil)
    }

    @Test
    func displayResolutionChangeCancelsTheStalePlacementSession() {
        let fixture = Fixture()
        fixture.show()
        fixture.screens[0].frame.size.width = 800
        fixture.observer?()
        #expect(fixture.cancelled == 1)
        #expect(fixture.committed.isEmpty)
        #expect(fixture.controller.windowCount == 0)
    }

    @Test
    func reservedScreenRegionChangeCancelsTheStalePlacementSession() {
        let fixture = Fixture()
        fixture.show()
        fixture.screens[0].safeAreaInsets.top = 44
        fixture.observer?()
        #expect(fixture.cancelled == 1)
        #expect(fixture.committed.isEmpty)
        #expect(!fixture.controller.isSelecting)
        #expect(fixture.controller.windowCount == 0)
        #expect(fixture.observer == nil)
    }

    @Test
    func cameraPlacementStartsASeparateTopCenterDraft() {
        let fixture = Fixture()
        fixture.show(initial: IslandPlacement(mode: .camera, edge: .right, offset: 0.1, inwardDistance: 64))
        #expect(fixture.controller.selection == IslandPlacement(mode: .custom, edge: .top, offset: 0.5))
        #expect(fixture.committed.isEmpty)
        fixture.controller.cancel()
    }

    @Test
    func confirmationDuringDraggingCommitsThePreviewedInwardDistance() throws {
        let fixture = Fixture()
        fixture.show()
        let frame = try #require(fixture.controller.previewFrame)
        #expect(fixture.controller.beginDragging(at: CGPoint(x: frame.midX, y: frame.midY)))
        fixture.controller.drag(to: CGPoint(x: fixture.screens[0].frame.maxX - 40, y: 450))
        fixture.controller.confirm()
        #expect(fixture.committed == [IslandPlacement(mode: .custom, edge: .right, offset: 0.5, inwardDistance: 28)])
        #expect(!fixture.controller.isSelecting)
        #expect(fixture.controller.windowCount == 0)
        #expect(fixture.observer == nil)
    }

    @Test
    func startingWithNoScreensCancelsWithoutAllocatingWindows() {
        let fixture = Fixture()
        fixture.screens = []
        fixture.show()
        #expect(fixture.cancelled == 1)
        #expect(fixture.controller.windowCount == 0)
        #expect(!fixture.controller.isSelecting)
        #expect(fixture.observer == nil)
        #expect(fixture.presented.isEmpty)
    }

    @Test
    func replacingTheSelectionCancelsThePreviousDraftAndKeepsOneSession() {
        let fixture = Fixture()
        fixture.show()
        fixture.show(initial: IslandPlacement(mode: .custom, edge: .left))
        #expect(fixture.cancelled == 1)
        #expect(fixture.controller.windowCount == 1)
        #expect(fixture.controller.selection?.edge == .left)
        #expect(fixture.presented[0].contentView == nil)
        fixture.controller.cancel()
        #expect(fixture.cancelled == 2)
        #expect(fixture.observer == nil)
    }

    @Test
    func deinitializationClosesWindowsAndRemovesObservation() {
        var presented: [NSWindow] = []
        var observationRemoved = false
        autoreleasepool {
            let controller = IslandPlacementController(dependencies: .init(
                screens: { [Fixture.screen] },
                pointerLocation: { CGPoint(x: Fixture.screen.frame.midX, y: Fixture.screen.frame.midY) },
                presentWindow: { window, _ in presented.append(window) },
                observeScreens: { _ in NSObject() },
                removeObserver: { _ in observationRemoved = true }
            ))
            controller.show(initialPlacement: IslandPlacement(), completion: { _ in }, onCancel: {})
            #expect(controller.windowCount == 1)
        }
        #expect(observationRemoved)
        #expect(presented.allSatisfy { $0.contentView == nil && !$0.isVisible })
    }

    @Test
    func appKitCancelOperationClosesTheSelectionWithoutCommitting() throws {
        let fixture = Fixture()
        fixture.show(initial: IslandPlacement(mode: .custom, edge: .left))
        let window = try #require(fixture.presented.first as? IslandPlacementWindow)
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
            object: window, queue: .main) { [weak fixture] _ in
            MainActor.assumeIsolated { fixture?.closedWindowCount += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        window.cancelOperation(nil)
        #expect(fixture.committed.isEmpty)
        #expect(fixture.cancelled == 1)
        #expect(fixture.closedWindowCount == 1)
        #expect(!fixture.controller.isSelecting)
        #expect(fixture.controller.windowCount == 0)
        #expect(fixture.observer == nil)
        window.cancelOperation(nil)
        #expect(fixture.cancelled == 1 && fixture.closedWindowCount == 1)
    }

    private func keyEvent(code: UInt16, characters: String, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    @MainActor
    private final class Fixture {
        static let screen = ScreenSnapshot(displayID: 1,
            frame: CGRect(x: 20000, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 20000, y: 0, width: 1440, height: 876))
        var screens = [Fixture.screen]
        var presented: [NSWindow] = []
        var committed: [IslandPlacement] = []
        var cancelled = 0
        var closedWindowCount = 0
        var observer: (@MainActor () -> Void)?
        lazy var controller = IslandPlacementController(dependencies: .init(
            screens: { [unowned self] in screens },
            pointerLocation: { CGPoint(x: Self.screen.frame.midX, y: Self.screen.frame.midY) },
            presentWindow: { [unowned self] window, _ in presented.append(window) },
            observeScreens: { [unowned self] action in observer = action; return NSObject() },
            removeObserver: { [weak self] _ in self?.observer = nil }
        ))

        func show(initial: IslandPlacement = IslandPlacement(),
                  configuration: ScreenLayoutConfiguration = ScreenLayoutConfiguration()) {
            controller.show(initialPlacement: initial, configuration: configuration,
                completion: { [unowned self] in committed.append($0) },
                onCancel: { [unowned self] in cancelled += 1 })
        }
    }
}
