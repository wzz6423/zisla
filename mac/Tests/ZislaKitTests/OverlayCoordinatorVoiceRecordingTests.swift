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
        // 录音态不参与鼠标交互、不因内容需要而抢 key window……
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.allowsKeyWindow)
        // ……保留玻璃资格，但录音期间不实际成为 key window。
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
    func voiceRecordingOnAnotherScreenDoesNotMoveTheExistingPetPanel() throws {
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

        #expect(firstPetView.window === firstPetPanel)
        #expect(firstPetPanel.isVisible)
        #expect(firstPetPanel.frame == originalFrame)
        #expect(coordinator.persistentPanelDisplayIDs == [Self.screen.displayID])
    }

    @Test @MainActor
    func voiceRecordingDoesNotRescheduleUnchangedPersistentPanels() throws {
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

        // 验证初始状态
        #expect(firstPetPanel.isVisible)
        #expect(coordinator.persistentPanelDisplayIDs == [Self.screen.displayID, Self.rightScreen.displayID])

        // 在第二屏开始录音
        coordinator.setVoiceRecording(true, at: CGPoint(x: 1_900, y: 450))

        // 第一屏宠物应该保持可见，窗口实例和 frame 都不应改变
        #expect(firstPetView.window === firstPetPanel, "面板实例不应被替换")
        #expect(firstPetPanel.isVisible, "面板应保持可见")
        #expect(firstPetPanel.frame == firstPetFrame, "面板 frame 不应改变")
        #expect(coordinator.persistentPanelDisplayIDs == [Self.screen.displayID], "只有第一屏显示持久面板")
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
}
