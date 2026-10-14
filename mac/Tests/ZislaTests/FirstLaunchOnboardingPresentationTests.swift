import AppKit
import Testing
import ZislaKit
@testable import Zisla

struct FirstLaunchOnboardingPresentationTests {
    @Test(arguments: [
        CGRect(x: -1920, y: -300, width: 1920, height: 1080),
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: -320, y: 100, width: 320, height: 240),
    ])
    func keepsAnchorLocalAcrossDisplayCoordinates(frame: CGRect) {
        let snapshot = ScreenSnapshot(
            displayID: 1, frame: frame,
            visibleFrame: frame.insetBy(dx: 0, dy: 24),
            menuBarHeightFallback: 24
        )
        let presentation = FirstLaunchOnboardingPresentation(screen: snapshot)
        let island = ScreenLayoutEngine().layout(for: snapshot).collapsedFrame
        #expect(presentation.anchorFrame.midX == island.midX - frame.minX)
        #expect(presentation.anchorFrame.midX == frame.width / 2)
        #expect(presentation.anchorFrame.minY == frame.maxY - island.maxY)
        #expect(presentation.anchorFrame.maxY <= presentation.topContentInset)
        #expect(presentation.topContentInset <= frame.height)
        #expect(CGRect(origin: .zero, size: frame.size).contains(presentation.anchorFrame))
        #expect(FirstLaunchOnboardingPresentation.readingWidth == 656)
    }

    @Test func physicalNotchKeepsArrowAndReadingContentBelowCamera() {
        let frame = CGRect(x: -1512, y: -200, width: 1512, height: 982)
        let snapshot = ScreenSnapshot(
            displayID: 2, frame: frame,
            visibleFrame: CGRect(x: -1512, y: -200, width: 1512, height: 944),
            safeAreaInsets: ScreenInsets(top: 38),
            auxiliaryTopLeftArea: CGRect(x: -1512, y: 744, width: 650, height: 38),
            auxiliaryTopRightArea: CGRect(x: -650, y: 744, width: 650, height: 38)
        )
        let presentation = FirstLaunchOnboardingPresentation(screen: snapshot)
        #expect(presentation.anchorFrame == CGRect(x: 650, y: 0, width: 212, height: 38))
        #expect(presentation.topContentInset == 110)
    }

    @Test @MainActor func borderlessWindowAcceptsKeyboardAndPreservesFullScreenBounds() {
        _ = NSApplication.shared
        let frame = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let window = FirstLaunchOnboardingWindow(
            contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        FirstLaunchOnboardingPresentation.configureHostWindow(window)
        defer { window.close() }
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
        #expect(window.level == .normal)
        #expect(window.canBecomeKey)
        #expect(window.canBecomeMain)
        #expect(!window.styleMask.contains(.titled))
        #expect(window.frame == frame)
        #expect(window.constrainFrameRect(frame, to: nil) == frame)
        #expect(!window.isVisible)
    }

    @Test @MainActor func inactiveTutorialDoesNotSwallowIslandReturn() throws {
        _ = NSApplication.shared
        let window = FirstLaunchOnboardingWindow(
            contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: true, keyCode: 36
        ))
        #expect(!window.performKeyEquivalent(with: event))
        #expect(!window.isVisible)
    }

    @Test(arguments: [false, true])
    func otherApplicationsAndPermissionPromptsRestoreOriginalOptions(requesting: Bool) {
        let original: NSApplication.PresentationOptions = [.autoHideToolbar]
        #expect(FirstLaunchOnboardingPresentation.presentationOptions(
            original: original, isActive: false, isKey: true, isRequesting: requesting
        ) == original)
        #expect(FirstLaunchOnboardingPresentation.presentationOptions(
            original: original, isActive: true, isKey: false, isRequesting: requesting
        ) == original)
        let active = FirstLaunchOnboardingPresentation.presentationOptions(
            original: original, isActive: true, isKey: true, isRequesting: requesting
        )
        #expect(active == (requesting ? original : original.union([.autoHideDock, .autoHideMenuBar])))
    }

    @Test func immersionReplacesConflictingHideOptionsOnlyWhileActive() {
        let original: NSApplication.PresentationOptions = [.hideDock, .hideMenuBar]
        let active = FirstLaunchOnboardingPresentation.presentationOptions(
            original: original, isActive: true, isKey: true, isRequesting: false
        )
        #expect(active == [.autoHideDock, .autoHideMenuBar])
        #expect(FirstLaunchOnboardingPresentation.presentationOptions(
            original: original, isActive: false, isKey: false, isRequesting: false
        ) == original)
    }
    @Test func repeatedReturnIsSuppressedOnlyInKeyTutorialWindow() {
        #expect(FirstLaunchOnboardingPresentation.suppressesRepeatedReturn(isKey: true, isRepeat: true, characters: "\r"))
        #expect(!FirstLaunchOnboardingPresentation.suppressesRepeatedReturn(isKey: false, isRepeat: true, characters: "\r"))
        #expect(!FirstLaunchOnboardingPresentation.suppressesRepeatedReturn(isKey: true, isRepeat: false, characters: "\r"))
        #expect(!FirstLaunchOnboardingPresentation.suppressesRepeatedReturn(isKey: true, isRepeat: true, characters: nil))
    }

}
