import AppKit
import SwiftUI
import Testing
@testable import Zisla

@MainActor
struct FirstLaunchOnboardingBackdropTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func nativeBackdropRemainsActiveBehindWindow(colorScheme: ColorScheme) {
        let view = FirstLaunchOnboardingBackdropView(frame: .zero)
        view.configure(material: .hudWindow, colorScheme: colorScheme, reduceTransparency: false)

        #expect(view.effectView.blendingMode == .behindWindow)
        #expect(view.effectView.state == .active)
        #expect(view.effectView.material == .hudWindow)
        #expect(!view.effectView.isHidden)
        #expect(!view.isOpaque)
        #expect(view.layer?.backgroundColor == nil)
        #expect(view.window == nil)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func reducedTransparencyCanBeEnabledAndRestored(colorScheme: ColorScheme) throws {
        let view = FirstLaunchOnboardingBackdropView(frame: .zero)
        view.configure(material: .hudWindow, colorScheme: colorScheme, reduceTransparency: false)
        view.configure(material: .hudWindow, colorScheme: colorScheme, reduceTransparency: true)

        #expect(view.effectView.isHidden)
        #expect(view.isOpaque)
        let fallback = try #require(view.layer?.backgroundColor)
        #expect(fallback.alpha == 1)
        var expected: CGColor?
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            expected = NSColor.windowBackgroundColor.cgColor
        }
        #expect(fallback == expected)

        view.configure(material: .hudWindow, colorScheme: colorScheme, reduceTransparency: false)
        #expect(!view.effectView.isHidden)
        #expect(!view.isOpaque)
        #expect(view.layer?.backgroundColor == nil)
        #expect(view.effectView.blendingMode == .behindWindow)
        #expect(view.effectView.state == .active)
        #expect(view.window == nil)
    }

    @Test(arguments: [false, true])
    func appearanceAndNavigationMaterialUpdateOnReusedView(reduceTransparency: Bool) throws {
        let view = FirstLaunchOnboardingBackdropView(frame: .zero)
        view.configure(material: .hudWindow, colorScheme: .light, reduceTransparency: reduceTransparency)
        #expect(view.effectView.appearance?.name == .aqua)
        let lightFallback = view.layer?.backgroundColor

        view.configure(material: .popover, colorScheme: .dark, reduceTransparency: reduceTransparency)
        #expect(view.appearance?.name == .darkAqua)
        #expect(view.effectView.appearance?.name == .darkAqua)
        #expect(view.effectView.material == .popover)
        #expect(view.effectView.state == .active)
        #expect(view.effectView.blendingMode == .behindWindow)
        #expect(view.effectView.isHidden == reduceTransparency)
        if reduceTransparency {
            let darkFallback = try #require(view.layer?.backgroundColor)
            #expect(darkFallback != lightFallback)
            #expect(darkFallback.alpha == 1)
        } else {
            #expect(view.layer?.backgroundColor == nil)
        }

        view.configure(material: .hudWindow, colorScheme: .light, reduceTransparency: reduceTransparency)
        #expect(view.effectView.appearance?.name == .aqua)
        #expect(view.effectView.material == .hudWindow)
        #expect(view.layer?.backgroundColor == lightFallback)
    }

    @Test(arguments: [false, true])
    func backdropDoesNotCapturePointerOrKeyboard(reduceTransparency: Bool) {
        let view = FirstLaunchOnboardingBackdropView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.configure(material: .hudWindow, colorScheme: .light, reduceTransparency: reduceTransparency)

        #expect(view.hitTest(CGPoint(x: 400, y: 300)) == nil)
        #expect(view.hitTest(CGPoint(x: 0, y: 0)) == nil)
        #expect(!view.acceptsFirstResponder)
        #expect(!view.isAccessibilityElement())
        #expect(!view.effectView.isAccessibilityElement())
        #expect(view.window == nil)
    }
}
