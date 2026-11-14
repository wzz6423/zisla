import AppKit
import Foundation
import QuartzCore
import SwiftUI

struct IslandParticleLogo: View {
    var side: CGFloat
    var time: TimeInterval? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let time {
                Self.rendering(side: side, time: time, reduceMotion: reduceMotion)
            } else {
                AnimatedParticleLogo(reduceMotion: reduceMotion)
                    .frame(width: side, height: side)
            }
        }
        .accessibilityHidden(true)
    }

    static func rendering(side: CGFloat, time: TimeInterval, reduceMotion: Bool) -> some View {
        Canvas { context, size in
            for particle in IslandParticleLogoRenderer.renderedParticles(
                size: size, time: time, reduceMotion: reduceMotion
            ) {
                context.fill(Path(ellipseIn: CGRect(
                    x: particle.center.x - particle.radius, y: particle.center.y - particle.radius,
                    width: particle.radius * 2, height: particle.radius * 2
                )), with: .color(.white.opacity(0.9)))
            }
        }
        .frame(width: side, height: side)
    }
}

private struct AnimatedParticleLogo: NSViewRepresentable {
    var reduceMotion: Bool

    func makeNSView(context: Context) -> ParticleLogoView {
        ParticleLogoView(reduceMotion: reduceMotion)
    }

    func updateNSView(_ view: ParticleLogoView, context: Context) {
        view.reduceMotion = reduceMotion
    }

    static func dismantleNSView(_ view: ParticleLogoView, coordinator: ()) {
        view.stopAnimation()
    }
}

@MainActor
final class ParticleLogoView: NSView {
    var reduceMotion: Bool {
        didSet {
            guard oldValue != reduceMotion else { return }
            updateAnimation()
            drawFrame()
        }
    }
    private var displayLink: CADisplayLink?

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
        drawFrame()
    }

    override func layout() {
        super.layout()
        drawFrame()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        drawFrame()
    }

    private func updateAnimation() {
        stopAnimation()
        guard let window, !reduceMotion else { return }
        let link = window.displayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) { drawFrame() }

    func drawFrame(at time: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let renderer = ImageRenderer(content: IslandParticleLogo.rendering(
            side: min(bounds.width, bounds.height), time: time, reduceMotion: reduceMotion
        ).frame(width: bounds.width, height: bounds.height))
        renderer.scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = renderer.scale
        layer?.contents = renderer.cgImage
        CATransaction.commit()
    }
}

enum IslandParticleLogoRenderer {
    struct RenderedParticle: Equatable {
        let center: CGPoint
        let radius: CGFloat
    }

    static func renderedParticles(size: CGSize, time: TimeInterval, reduceMotion: Bool) -> [RenderedParticle] {
        let side = min(size.width, size.height)
        guard side > 0 else { return [] }
        let scale = side / 580
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        return targets.enumerated().map { index, target in
            let phase = Double(index)
            let dx = reduceMotion ? 0 : sin(time * 0.4 + phase * 0.1) * 2.5
            let dy = reduceMotion ? 0 : cos(time * 0.25 + phase * 0.15) * 2.5
            return RenderedParticle(
                center: CGPoint(x: origin.x + (target.x + dx) * scale,
                                y: origin.y + (target.y + dy) * scale),
                radius: 6.5 * scale
            )
        }
    }

    // Fixed vector targets use the website mark's dark-pixel sampling at 16px spacing,
    // cropped into a centered 580px square; no image is decoded or drawn at runtime.
    private static let targets: [CGPoint] = [
        CGPoint(x: 306, y: 23), CGPoint(x: 322, y: 23), CGPoint(x: 370, y: 23),
        CGPoint(x: 402, y: 23), CGPoint(x: 306, y: 39), CGPoint(x: 322, y: 39),
        CGPoint(x: 386, y: 39), CGPoint(x: 402, y: 39), CGPoint(x: 306, y: 55),
        CGPoint(x: 386, y: 55), CGPoint(x: 146, y: 103), CGPoint(x: 162, y: 103),
        CGPoint(x: 178, y: 103), CGPoint(x: 194, y: 103), CGPoint(x: 210, y: 103),
        CGPoint(x: 226, y: 103), CGPoint(x: 242, y: 103), CGPoint(x: 258, y: 103),
        CGPoint(x: 274, y: 103), CGPoint(x: 290, y: 103), CGPoint(x: 306, y: 103),
        CGPoint(x: 322, y: 103), CGPoint(x: 338, y: 103), CGPoint(x: 354, y: 103),
        CGPoint(x: 370, y: 103), CGPoint(x: 386, y: 103), CGPoint(x: 402, y: 103),
        CGPoint(x: 418, y: 103), CGPoint(x: 434, y: 103), CGPoint(x: 130, y: 119),
        CGPoint(x: 146, y: 119), CGPoint(x: 162, y: 119), CGPoint(x: 178, y: 119),
        CGPoint(x: 194, y: 119), CGPoint(x: 210, y: 119), CGPoint(x: 226, y: 119),
        CGPoint(x: 242, y: 119), CGPoint(x: 258, y: 119), CGPoint(x: 274, y: 119),
        CGPoint(x: 290, y: 119), CGPoint(x: 306, y: 119), CGPoint(x: 322, y: 119),
        CGPoint(x: 338, y: 119), CGPoint(x: 354, y: 119), CGPoint(x: 370, y: 119),
        CGPoint(x: 386, y: 119), CGPoint(x: 402, y: 119), CGPoint(x: 418, y: 119),
        CGPoint(x: 434, y: 119), CGPoint(x: 450, y: 119), CGPoint(x: 466, y: 119),
        CGPoint(x: 146, y: 135), CGPoint(x: 162, y: 135), CGPoint(x: 178, y: 135),
        CGPoint(x: 194, y: 135), CGPoint(x: 210, y: 135), CGPoint(x: 226, y: 135),
        CGPoint(x: 242, y: 135), CGPoint(x: 258, y: 135), CGPoint(x: 274, y: 135),
        CGPoint(x: 290, y: 135), CGPoint(x: 306, y: 135), CGPoint(x: 322, y: 135),
        CGPoint(x: 338, y: 135), CGPoint(x: 354, y: 135), CGPoint(x: 370, y: 135),
        CGPoint(x: 386, y: 135), CGPoint(x: 402, y: 135), CGPoint(x: 418, y: 135),
        CGPoint(x: 434, y: 135), CGPoint(x: 450, y: 135), CGPoint(x: 466, y: 135),
        CGPoint(x: 146, y: 151), CGPoint(x: 162, y: 151), CGPoint(x: 178, y: 151),
        CGPoint(x: 194, y: 151), CGPoint(x: 210, y: 151), CGPoint(x: 226, y: 151),
        CGPoint(x: 242, y: 151), CGPoint(x: 258, y: 151), CGPoint(x: 274, y: 151),
        CGPoint(x: 290, y: 151), CGPoint(x: 306, y: 151), CGPoint(x: 322, y: 151),
        CGPoint(x: 338, y: 151), CGPoint(x: 354, y: 151), CGPoint(x: 370, y: 151),
        CGPoint(x: 386, y: 151), CGPoint(x: 402, y: 151), CGPoint(x: 418, y: 151),
        CGPoint(x: 434, y: 151), CGPoint(x: 450, y: 151), CGPoint(x: 402, y: 167),
        CGPoint(x: 418, y: 167), CGPoint(x: 434, y: 167), CGPoint(x: 386, y: 183),
        CGPoint(x: 402, y: 183), CGPoint(x: 418, y: 183), CGPoint(x: 434, y: 183),
        CGPoint(x: 354, y: 199), CGPoint(x: 370, y: 199), CGPoint(x: 386, y: 199),
        CGPoint(x: 402, y: 199), CGPoint(x: 418, y: 199), CGPoint(x: 354, y: 215),
        CGPoint(x: 370, y: 215), CGPoint(x: 386, y: 215), CGPoint(x: 402, y: 215),
        CGPoint(x: 322, y: 231), CGPoint(x: 338, y: 231), CGPoint(x: 354, y: 231),
        CGPoint(x: 370, y: 231), CGPoint(x: 386, y: 231), CGPoint(x: 306, y: 247),
        CGPoint(x: 322, y: 247), CGPoint(x: 338, y: 247), CGPoint(x: 354, y: 247),
        CGPoint(x: 370, y: 247), CGPoint(x: 274, y: 263), CGPoint(x: 290, y: 263),
        CGPoint(x: 306, y: 263), CGPoint(x: 322, y: 263), CGPoint(x: 338, y: 263),
        CGPoint(x: 274, y: 279), CGPoint(x: 290, y: 279), CGPoint(x: 306, y: 279),
        CGPoint(x: 322, y: 279), CGPoint(x: 338, y: 279), CGPoint(x: 242, y: 295),
        CGPoint(x: 258, y: 295), CGPoint(x: 274, y: 295), CGPoint(x: 290, y: 295),
        CGPoint(x: 306, y: 295), CGPoint(x: 226, y: 311), CGPoint(x: 242, y: 311),
        CGPoint(x: 258, y: 311), CGPoint(x: 274, y: 311), CGPoint(x: 290, y: 311),
        CGPoint(x: 194, y: 327), CGPoint(x: 210, y: 327), CGPoint(x: 226, y: 327),
        CGPoint(x: 242, y: 327), CGPoint(x: 258, y: 327), CGPoint(x: 274, y: 327),
        CGPoint(x: 194, y: 343), CGPoint(x: 210, y: 343), CGPoint(x: 226, y: 343),
        CGPoint(x: 242, y: 343), CGPoint(x: 258, y: 343), CGPoint(x: 162, y: 359),
        CGPoint(x: 178, y: 359), CGPoint(x: 194, y: 359), CGPoint(x: 210, y: 359),
        CGPoint(x: 226, y: 359), CGPoint(x: 242, y: 359), CGPoint(x: 146, y: 375),
        CGPoint(x: 162, y: 375), CGPoint(x: 178, y: 375), CGPoint(x: 194, y: 375),
        CGPoint(x: 210, y: 375), CGPoint(x: 226, y: 375), CGPoint(x: 130, y: 391),
        CGPoint(x: 146, y: 391), CGPoint(x: 162, y: 391), CGPoint(x: 178, y: 391),
        CGPoint(x: 194, y: 391), CGPoint(x: 210, y: 391), CGPoint(x: 114, y: 407),
        CGPoint(x: 130, y: 407), CGPoint(x: 146, y: 407), CGPoint(x: 162, y: 407),
        CGPoint(x: 178, y: 407), CGPoint(x: 194, y: 407), CGPoint(x: 98, y: 423),
        CGPoint(x: 114, y: 423), CGPoint(x: 130, y: 423), CGPoint(x: 146, y: 423),
        CGPoint(x: 162, y: 423), CGPoint(x: 178, y: 423), CGPoint(x: 82, y: 439),
        CGPoint(x: 98, y: 439), CGPoint(x: 114, y: 439), CGPoint(x: 130, y: 439),
        CGPoint(x: 146, y: 439), CGPoint(x: 162, y: 439), CGPoint(x: 178, y: 439),
        CGPoint(x: 66, y: 455), CGPoint(x: 82, y: 455), CGPoint(x: 98, y: 455),
        CGPoint(x: 114, y: 455), CGPoint(x: 130, y: 455), CGPoint(x: 146, y: 455),
        CGPoint(x: 162, y: 455), CGPoint(x: 498, y: 455), CGPoint(x: 514, y: 455),
        CGPoint(x: 82, y: 471), CGPoint(x: 98, y: 471), CGPoint(x: 114, y: 471),
        CGPoint(x: 130, y: 471), CGPoint(x: 146, y: 471), CGPoint(x: 450, y: 471),
        CGPoint(x: 466, y: 471), CGPoint(x: 482, y: 471), CGPoint(x: 514, y: 471),
        CGPoint(x: 66, y: 487), CGPoint(x: 82, y: 487), CGPoint(x: 98, y: 487),
        CGPoint(x: 114, y: 487), CGPoint(x: 130, y: 487), CGPoint(x: 146, y: 487),
        CGPoint(x: 402, y: 487), CGPoint(x: 418, y: 487), CGPoint(x: 434, y: 487),
        CGPoint(x: 450, y: 487), CGPoint(x: 466, y: 487), CGPoint(x: 482, y: 487),
        CGPoint(x: 66, y: 503), CGPoint(x: 82, y: 503), CGPoint(x: 98, y: 503),
        CGPoint(x: 114, y: 503), CGPoint(x: 130, y: 503), CGPoint(x: 146, y: 503),
        CGPoint(x: 306, y: 503), CGPoint(x: 354, y: 503), CGPoint(x: 370, y: 503),
        CGPoint(x: 386, y: 503), CGPoint(x: 402, y: 503), CGPoint(x: 418, y: 503),
        CGPoint(x: 434, y: 503), CGPoint(x: 82, y: 519), CGPoint(x: 98, y: 519),
        CGPoint(x: 114, y: 519), CGPoint(x: 130, y: 519), CGPoint(x: 146, y: 519),
        CGPoint(x: 162, y: 519), CGPoint(x: 178, y: 519), CGPoint(x: 194, y: 519),
        CGPoint(x: 210, y: 519), CGPoint(x: 226, y: 519), CGPoint(x: 242, y: 519),
        CGPoint(x: 258, y: 519), CGPoint(x: 274, y: 519), CGPoint(x: 290, y: 519),
        CGPoint(x: 306, y: 519), CGPoint(x: 322, y: 519), CGPoint(x: 338, y: 519),
        CGPoint(x: 354, y: 519), CGPoint(x: 370, y: 519), CGPoint(x: 386, y: 519),
        CGPoint(x: 402, y: 519), CGPoint(x: 418, y: 519), CGPoint(x: 82, y: 535),
        CGPoint(x: 98, y: 535), CGPoint(x: 114, y: 535), CGPoint(x: 130, y: 535),
        CGPoint(x: 146, y: 535), CGPoint(x: 162, y: 535), CGPoint(x: 178, y: 535),
        CGPoint(x: 194, y: 535), CGPoint(x: 210, y: 535), CGPoint(x: 226, y: 535),
        CGPoint(x: 242, y: 535), CGPoint(x: 258, y: 535), CGPoint(x: 274, y: 535),
        CGPoint(x: 290, y: 535), CGPoint(x: 306, y: 535), CGPoint(x: 322, y: 535),
        CGPoint(x: 338, y: 535), CGPoint(x: 354, y: 535), CGPoint(x: 98, y: 551),
        CGPoint(x: 114, y: 551), CGPoint(x: 130, y: 551), CGPoint(x: 146, y: 551),
        CGPoint(x: 162, y: 551), CGPoint(x: 178, y: 551), CGPoint(x: 194, y: 551),
        CGPoint(x: 210, y: 551), CGPoint(x: 226, y: 551), CGPoint(x: 242, y: 551),
        CGPoint(x: 258, y: 551), CGPoint(x: 274, y: 551),
    ]
}
