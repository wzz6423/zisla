import SwiftUI
import ZislaCore

struct FirstLaunchGreetingTimeline {
    struct Frame {
        let language: AppLanguage
        let progress: CGFloat
        let opacity: Double
    }

    let languages: [AppLanguage]
    let wordDuration: TimeInterval = 2.4

    init(preferredLanguage: AppLanguage) {
        languages = FirstLaunchOnboardingSession.greetingLanguages
    }

    func frame(at elapsed: TimeInterval) -> Frame {
        let duration = Double(languages.count) * wordDuration
        var position = elapsed.truncatingRemainder(dividingBy: duration)
        // Multiplication can round an exact cycle boundary away from a zero remainder.
        if elapsed == (elapsed / duration).rounded() * duration { position = 0 }
        let index = (0..<(languages.count - 1)).first {
            position < Double($0 + 1) * wordDuration
        } ?? (languages.count - 1)
        let phase = max(0, (position - Double(index) * wordDuration) / wordDuration)
        return Frame(
            language: languages[index],
            progress: CGFloat(min(1, phase / 0.68)),
            opacity: Double(Self.smoothProgress(CGFloat((1 - phase) / 0.13)))
        )
    }

    static func smoothProgress(_ progress: CGFloat) -> CGFloat {
        let value = min(1, max(0, progress))
        return value * value * (3 - 2 * value)
    }

}

struct FirstLaunchGreetingAnimation: View {
    let timeline: FirstLaunchGreetingTimeline
    let startedAt: Date?
    let preferredLanguage: AppLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if !reduceMotion, let startedAt {
                TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                    let frame = timeline.frame(at: context.date.timeIntervalSince(startedAt))
                    greeting(frame)
                        .opacity(frame.opacity)
                }
            } else {
                greeting(.init(language: preferredLanguage, progress: 1, opacity: 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AppLocalization.string("onboarding.hello", language: preferredLanguage)))
    }

    private func greeting(_ frame: FirstLaunchGreetingTimeline.Frame) -> some View {
        let colors: [Color] = contrast == .increased ? [.primary, .primary] : [.accentColor, .zislaInfo, .accentColor]
        let artwork = FirstLaunchGreetingArtwork.artwork(for: frame.language)
        return Canvas { context, size in
            let strokes = artwork.fittedStrokes(in: size)
            for (index, stroke) in strokes.enumerated() {
                let progress = artwork.strokeProgress(at: frame.progress, index: index)
                context.stroke(
                    stroke.trimmedPath(from: 0, to: progress),
                    with: .linearGradient(
                        Gradient(colors: colors),
                        startPoint: CGPoint(x: 0, y: size.height * (1 - frame.progress)),
                        endPoint: CGPoint(x: size.width, y: size.height * frame.progress)
                    ),
                    style: StrokeStyle(
                        lineWidth: artwork.fittedLineWidth(in: size, baseWidth: contrast == .increased ? 6 : 5),
                        lineCap: .round, lineJoin: .round
                    )
                )
            }
        }
    }
}

struct FirstLaunchFeatureIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<9) { index in
                        Capsule()
                            .frame(width: 3, height: expanded ? CGFloat([12, 20, 28, 16, 32, 24, 14, 22, 10][index]) : 6)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5).delay(Double(index) * 0.06), value: expanded)
                    }
                }
                Image(systemName: "calendar")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(width: expanded ? 210 : 112, height: 52)
            .background(.black, in: RoundedRectangle(cornerRadius: 22))
            .animation(reduceMotion ? nil : ZislaMotion.surfaceResize, value: expanded)
            HStack(spacing: 22) {
                ForEach(["doc.on.clipboard", "crop", "waveform"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(width: 44, height: 36)
                        .background(Color.fillControl, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .opacity(expanded ? 1 : 0)
            .offset(y: expanded ? 0 : -8)
            .animation(reduceMotion ? nil : ZislaMotion.settingsPageSwitch.delay(0.15), value: expanded)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onAppear { expanded = true }
        .accessibilityHidden(true)
    }
}
