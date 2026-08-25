import AppKit
import CoreGraphics
import Testing

@testable import ZislaKit

private final class SpyView: NSView {
    var onWindowChanged: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            onWindowChanged?()
        }
    }
}

struct OverlayCoordinatorVoiceRecordingTests {
    @Test @MainActor
    func voiceRecordingBlocksExpansionAndClearsPointerHold() throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .seconds(10))
        defer { coordinator.stop() }
        var visibilityEvents: [Bool] = []
        coordinator.onVisibilityChanged = { visibilityEvents.append($0) }
        coordinator.start()
        coordinator.updateScreens([Self.screen], repositionVisiblePanel: false)
        let point = CGPoint(x: 720, y: 450)
        coordinator.showExpanded(at: point)

        coordinator.setVoiceRecording(true, at: point)
        let panel = try #require(contentView.window as? IslandPanel)
        let eventsAtRecordingStart = visibilityEvents
        coordinator.showExpanded(at: point)
        coordinator.setPinned(true)
        coordinator.setDragging(true)
        coordinator.setTransientInteractionVisible(true)
        coordinator.handlePointer(at: point)

        #expect(visibilityEvents == eventsAtRecordingStart)
        #expect(!panel.isPinned)
        #expect(panel.ignoresMouseEvents)

        coordinator.setVoiceRecording(false)

        #expect(visibilityEvents.last == false)
        #expect(panel.ignoresMouseEvents)
    }

    @Test @MainActor
    func voiceRecordingReleaseCollapsesImmediately() throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .seconds(10))
        defer { coordinator.stop() }
        var visibilityEvents: [Bool] = []
        coordinator.onVisibilityChanged = { visibilityEvents.append($0) }
        coordinator.updateScreens([Self.screen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))

        coordinator.setVoiceRecording(true)
        coordinator.setVoiceRecording(false)

        #expect(visibilityEvents == [true, false])
        let panel = try #require(contentView.window as? IslandPanel)
        #expect(panel.ignoresMouseEvents)
    }

    @Test @MainActor
    func voiceRecordingStaysNonInteractiveButKeepsGlassActive() throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        defer { coordinator.stop() }
        coordinator.updateScreens([Self.screen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setAllowsKeyWindow(true)
        coordinator.setKeepsNativeGlassActive(true)

        coordinator.setVoiceRecording(true)
        coordinator.updateExpandedSize(CGSize(width: 280, height: 58))

        let panel = try #require(contentView.window as? IslandPanel)
        #expect(panel.isVisible)
        // Recording remains noninteractive and does not take the key window for its content.
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.allowsKeyWindow)
        // It retains glass eligibility without actually becoming the key window.
        #expect(panel.allowsNativeGlassActivation)
        #expect(panel.keepsNativeGlassActive)
        #expect(panel.canBecomeKey)
        #expect(!panel.isKeyWindow)
        #expect(panel.avoidsAppActivation)
    }

    @Test @MainActor
    func voiceRecordingStartsOnTheScreenContainingThePointer() throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        defer { coordinator.stop() }
        coordinator.updateScreens([Self.screen, Self.rightScreen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        #expect(coordinator.activeDisplayID == Self.screen.displayID)

        coordinator.setVoiceRecording(true, at: CGPoint(x: 1_900, y: 450))

        #expect(coordinator.activeDisplayID == Self.rightScreen.displayID)
        let panel = try #require(contentView.window as? IslandPanel)
        let expectedFrame = try #require(
            coordinator.layouts.first { $0.displayID == Self.rightScreen.displayID }
        ).expandedFrame
        #expect(panel.isVisible)
        #expect(panel.frame == expectedFrame)
    }

    @Test @MainActor
    func voiceRecordingHidesEveryPersistentPetPanelUntilRecordingEnds() throws {
        var petViews: [CGDirectDisplayID: NSView] = [:]
        let coordinator = OverlayCoordinator(
            contentView: NSView(),
            collapseDelay: .zero,
            persistentContentViewProvider: { layout in
                let view = NSView()
                petViews[layout.displayID] = view
                return view
            },
            persistentPanelFrameProvider: { CollapsedPetLayout.frame(for: $0) }
        )
        defer { coordinator.stop() }
        coordinator.updateScreens([Self.screen, Self.rightScreen], repositionVisiblePanel: false)

        let firstPetView = try #require(petViews[Self.screen.displayID])
        let firstPetPanel = try #require(firstPetView.window as? IslandPanel)
        let originalFrame = firstPetPanel.frame

        coordinator.setVoiceRecording(true, at: CGPoint(x: 1_900, y: 450))
        coordinator.updateExpandedSize(CGSize(width: 280, height: 58))
        coordinator.updateScreens([Self.screen, Self.rightScreen], repositionVisiblePanel: false)

        #expect(firstPetView.window === firstPetPanel)
        #expect(!firstPetPanel.isVisible)
        #expect(firstPetPanel.frame == originalFrame)
        #expect(coordinator.persistentPanelDisplayIDs.isEmpty)

        coordinator.setVoiceRecording(false)

        #expect(firstPetPanel.isVisible)
        #expect(coordinator.persistentPanelDisplayIDs == [Self.screen.displayID, Self.rightScreen.displayID])
    }

    @Test @MainActor
    func voiceRecordingRestoresPersistentPanelsWithoutReplacingThem() throws {
        var petViews: [CGDirectDisplayID: NSView] = [:]
        let coordinator = OverlayCoordinator(
            contentView: NSView(),
            collapseDelay: .zero,
            persistentContentViewProvider: { layout in
                let view = NSView()
                petViews[layout.displayID] = view
                return view
            },
            persistentPanelFrameProvider: { CollapsedPetLayout.frame(for: $0) }
        )
        defer { coordinator.stop() }
        coordinator.updateScreens([Self.screen, Self.rightScreen], repositionVisiblePanel: false)

        let firstPetView = try #require(petViews[Self.screen.displayID])
        let firstPetPanel = try #require(firstPetView.window as? IslandPanel)
        let firstPetFrame = firstPetPanel.frame

        // Verify the initial state.
        #expect(firstPetPanel.isVisible)
        #expect(coordinator.persistentPanelDisplayIDs == [Self.screen.displayID, Self.rightScreen.displayID])

        // Start recording on the second display.
        coordinator.setVoiceRecording(true, at: CGPoint(x: 1_900, y: 450))
        coordinator.updateScreens([Self.screen, Self.rightScreen], repositionVisiblePanel: false)

        // Recording owns the island slot, so every persistent panel must be hidden.
        #expect(firstPetView.window === firstPetPanel, "面板实例不应被替换")
        #expect(!firstPetPanel.isVisible, "录音期间收起态面板应隐藏")
        #expect(firstPetPanel.frame == firstPetFrame, "面板 frame 不应改变")
        #expect(coordinator.persistentPanelDisplayIDs.isEmpty, "录音期间不应显示持久面板")

        coordinator.setVoiceRecording(false)

        #expect(firstPetView.window === firstPetPanel, "结束录音后应复用原面板")
        #expect(firstPetPanel.isVisible, "结束录音后收起态面板应恢复")
        #expect(firstPetPanel.frame == firstPetFrame, "恢复时面板 frame 不应改变")
        #expect(coordinator.persistentPanelDisplayIDs == [Self.screen.displayID, Self.rightScreen.displayID])
    }

    private static let screen = ScreenSnapshot(
        displayID: 9_101,
        frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
    )

    private static let rightScreen = ScreenSnapshot(
        displayID: 9_102,
        frame: CGRect(x: 1_440, y: 0, width: 1_440, height: 900),
        visibleFrame: CGRect(x: 1_440, y: 0, width: 1_440, height: 875)
    )

    @Test @MainActor
    func prewarmingMountsTheIslandPanelWithoutShowingIt() throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        defer { coordinator.stop() }
        var collapsedSizes: [CGSize] = []
        coordinator.onCollapsedSizeChanged = { collapsedSizes.append($0) }
        coordinator.start()
        coordinator.updateScreens([Self.screen], repositionVisiblePanel: false)

        coordinator.prewarmPanel()

        let panel = try #require(contentView.window as? IslandPanel)
        let layout = try #require(coordinator.layouts.first)
        #expect(!panel.isVisible)
        #expect(panel.ignoresMouseEvents)
        #expect(panel.frame == layout.expandedFrame)
        // The recording surface sizes itself from these, so they must be known before the first take.
        #expect(collapsedSizes == [layout.collapsedFrame.size])

        coordinator.prewarmPanel()

        #expect(contentView.window === panel)
    }

    @Test @MainActor
    func recordingReusesThePrewarmedPanelInsteadOfMountingANewOne() throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        defer { coordinator.stop() }
        coordinator.start()
        coordinator.updateScreens([Self.screen], repositionVisiblePanel: false)
        coordinator.prewarmPanel()
        let prewarmed = try #require(contentView.window as? IslandPanel)

        coordinator.setVoiceRecording(true, at: CGPoint(x: 720, y: 450))
        coordinator.updateExpandedSize(CGSize(width: 280, height: 58))

        let recordingLayout = try #require(coordinator.layouts.first)
        #expect(contentView.window === prewarmed)
        #expect(prewarmed.isVisible)
        #expect(prewarmed.frame == recordingLayout.expandedFrame)
    }

    @Test @MainActor
    func selectingTheActiveDisplayReportsItsCollapsedMetrics() throws {
        let coordinator = OverlayCoordinator(contentView: NSView(), collapseDelay: .zero)
        defer { coordinator.stop() }
        var collapsedSizes: [CGSize] = []
        var notchFlags: [Bool] = []
        coordinator.onCollapsedSizeChanged = { collapsedSizes.append($0) }
        coordinator.onActiveDisplayHasPhysicalNotchChanged = { notchFlags.append($0) }
        coordinator.updateScreens([Self.screen, Self.rightScreen], repositionVisiblePanel: false)

        coordinator.selectActiveDisplay(at: CGPoint(x: 1_900, y: 450))

        let layout = try #require(
            coordinator.layouts.first { $0.displayID == Self.rightScreen.displayID }
        )
        #expect(collapsedSizes == [layout.collapsedFrame.size])
        #expect(notchFlags == [layout.topology.hasPhysicalNotch])
    }
}
