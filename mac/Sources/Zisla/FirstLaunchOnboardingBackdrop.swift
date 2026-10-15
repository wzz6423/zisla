import AppKit
import SwiftUI

struct FirstLaunchOnboardingBackdrop: NSViewRepresentable {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> FirstLaunchOnboardingBackdropView {
        let view = FirstLaunchOnboardingBackdropView(frame: .zero)
        view.configure(material: material, colorScheme: colorScheme, reduceTransparency: reduceTransparency)
        return view
    }

    func updateNSView(_ nsView: FirstLaunchOnboardingBackdropView, context: Context) {
        nsView.configure(material: material, colorScheme: colorScheme, reduceTransparency: reduceTransparency)
    }
}

final class FirstLaunchOnboardingBackdropView: NSView {
    let effectView = NSVisualEffectView()
    private var reduceTransparency = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        effectView.frame = bounds
        effectView.autoresizingMask = [.width, .height]
        effectView.setAccessibilityElement(false)
        addSubview(effectView)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { reduceTransparency }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(
        material: NSVisualEffectView.Material,
        colorScheme: ColorScheme,
        reduceTransparency: Bool
    ) {
        self.reduceTransparency = reduceTransparency
        appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        effectView.appearance = appearance
        effectView.material = material
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isHidden = reduceTransparency
        // Resolve the opaque fallback against the same appearance as SwiftUI's text.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = reduceTransparency ? NSColor.windowBackgroundColor.cgColor : nil
        }
    }
}
