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
            opacity: min(1, (1 - phase) / 0.13)
        )
    }

    static func revealRect(in size: CGSize, progress: CGFloat, rightToLeft: Bool) -> CGRect {
        let width = size.width * min(1, max(0, progress))
        return CGRect(x: rightToLeft ? size.width - width : 0, y: 0, width: width, height: size.height)
    }
}

struct FirstLaunchGreetingArtwork {
    let strokes: [Path]
    let size: CGSize

    static func artwork(for language: AppLanguage) -> Self? {
        switch language {
        case .english: latin(capital: true)
        case .german: latin(capital: false)
        case .simplifiedChinese, .traditionalChinese: chinese
        default: nil
        }
    }

    func fittedStrokes(in available: CGSize) -> [Path] {
        let scale = min(available.width / size.width, available.height / size.height)
        let transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: (available.width - size.width * scale) / 2,
            ty: (available.height - size.height * scale) / 2
        )
        return strokes.map { $0.applying(transform) }
    }

    private static func latin(capital: Bool) -> Self {
        var strokes: [Path] = []
        if capital {
            strokes.append(Path { path in
                path.move(to: CGPoint(x: 24, y: 130))
                path.addCurve(to: CGPoint(x: 61, y: 27), control1: CGPoint(x: 18, y: 98), control2: CGPoint(x: 89, y: 14))
                path.addCurve(to: CGPoint(x: 40, y: 139), control1: CGPoint(x: 48, y: 44), control2: CGPoint(x: 43, y: 104))
            })
            strokes.append(Path { path in
                path.move(to: CGPoint(x: 31, y: 91))
                path.addCurve(to: CGPoint(x: 105, y: 75), control1: CGPoint(x: 57, y: 98), control2: CGPoint(x: 77, y: 60))
                path.move(to: CGPoint(x: 113, y: 25))
                path.addCurve(to: CGPoint(x: 102, y: 133), control1: CGPoint(x: 109, y: 59), control2: CGPoint(x: 81, y: 142))
                path.addQuadCurve(to: CGPoint(x: 135, y: 111), control: CGPoint(x: 113, y: 137))
            })
        } else {
            strokes.append(Path { path in
                path.move(to: CGPoint(x: 24, y: 128))
                path.addCurve(to: CGPoint(x: 69, y: 29), control1: CGPoint(x: 54, y: 103), control2: CGPoint(x: 88, y: 11))
                path.addCurve(to: CGPoint(x: 44, y: 137), control1: CGPoint(x: 45, y: 48), control2: CGPoint(x: 37, y: 126))
                path.addCurve(to: CGPoint(x: 101, y: 84), control1: CGPoint(x: 70, y: 71), control2: CGPoint(x: 119, y: 52))
                path.addCurve(to: CGPoint(x: 135, y: 112), control1: CGPoint(x: 84, y: 143), control2: CGPoint(x: 112, y: 148))
            })
        }
        strokes.append(Path { path in
            path.move(to: CGPoint(x: 134, y: 112))
            if capital {
                path.addCurve(to: CGPoint(x: 185, y: 88), control1: CGPoint(x: 183, y: 92), control2: CGPoint(x: 194, y: 66))
                path.addCurve(to: CGPoint(x: 208, y: 113), control1: CGPoint(x: 115, y: 172), control2: CGPoint(x: 187, y: 145))
            } else {
                path.addCurve(to: CGPoint(x: 185, y: 87), control1: CGPoint(x: 143, y: 66), control2: CGPoint(x: 185, y: 59))
                path.addCurve(to: CGPoint(x: 147, y: 133), control1: CGPoint(x: 175, y: 116), control2: CGPoint(x: 161, y: 145))
                path.addCurve(to: CGPoint(x: 187, y: 77), control1: CGPoint(x: 121, y: 117), control2: CGPoint(x: 156, y: 72))
                path.addCurve(to: CGPoint(x: 208, y: 113), control1: CGPoint(x: 162, y: 148), control2: CGPoint(x: 185, y: 145))
            }
        })
        for offset in [CGFloat(0), 66] {
            strokes.append(Path { path in
                path.move(to: CGPoint(x: 208 + offset, y: 113))
                path.addCurve(to: CGPoint(x: 250 + offset, y: 27), control1: CGPoint(x: 240 + offset, y: 69), control2: CGPoint(x: 278 + offset, y: 3))
                path.addCurve(to: CGPoint(x: 274 + offset, y: 113), control1: CGPoint(x: 193 + offset, y: 101), control2: CGPoint(x: 225 + offset, y: 169))
            })
        }
        strokes.append(Path { path in
            path.move(to: CGPoint(x: 340, y: 113))
            path.addCurve(to: CGPoint(x: 393, y: 79), control1: CGPoint(x: 346, y: 75), control2: CGPoint(x: 389, y: 64))
            path.addCurve(to: CGPoint(x: 347, y: 131), control1: CGPoint(x: 407, y: 98), control2: CGPoint(x: 370, y: 151))
            path.addCurve(to: CGPoint(x: 393, y: 79), control1: CGPoint(x: 331, y: 115), control2: CGPoint(x: 354, y: 72))
            path.addQuadCurve(to: CGPoint(x: 423, y: 104), control: CGPoint(x: 400, y: 114))
        })
        return Self(strokes: strokes, size: CGSize(width: 448, height: 174))
    }

    private static let chinese: Self = {
        let points: [[CGPoint]] = [
            [.init(x: 57, y: 28), .init(x: 37, y: 59), .init(x: 17, y: 79)],
            [.init(x: 38, y: 59), .init(x: 36, y: 141)],
            [.init(x: 98, y: 27), .init(x: 75, y: 67)],
            [.init(x: 89, y: 48), .init(x: 155, y: 46), .init(x: 141, y: 71)],
            [.init(x: 114, y: 66), .init(x: 113, y: 132), .init(x: 102, y: 141), .init(x: 91, y: 130)],
            [.init(x: 81, y: 90), .init(x: 62, y: 120)],
            [.init(x: 139, y: 89), .init(x: 163, y: 121)],
            [.init(x: 232, y: 37), .init(x: 220, y: 97), .init(x: 267, y: 132)],
            [.init(x: 269, y: 52), .init(x: 255, y: 102), .init(x: 214, y: 141)],
            [.init(x: 210, y: 86), .init(x: 283, y: 82)],
            [.init(x: 295, y: 45), .init(x: 354, y: 45), .init(x: 326, y: 69)],
            [.init(x: 324, y: 66), .init(x: 328, y: 82), .init(x: 327, y: 135), .init(x: 309, y: 144)],
            [.init(x: 288, y: 94), .init(x: 365, y: 87)],
        ]
        return Self(strokes: points.map { points in
            Path { path in
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
            }
        }, size: CGSize(width: 386, height: 174))
    }()
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
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let frame = timeline.frame(at: context.date.timeIntervalSince(startedAt))
                    greeting(frame)
                        .opacity(frame.opacity)
                }
            } else {
                text(preferredLanguage)
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AppLocalization.string("onboarding.hello", language: preferredLanguage)))
    }

    @ViewBuilder
    private func greeting(_ frame: FirstLaunchGreetingTimeline.Frame) -> some View {
        let colors: [Color] = contrast == .increased ? [.primary, .primary] : [.accentColor, .zislaInfo, .accentColor]
        if let artwork = FirstLaunchGreetingArtwork.artwork(for: frame.language) {
            Canvas { context, size in
                let strokes = artwork.fittedStrokes(in: size)
                for (index, stroke) in strokes.enumerated() {
                    let progress = min(1, max(0, frame.progress * CGFloat(strokes.count) - CGFloat(index)))
                    context.stroke(
                        stroke.trimmedPath(from: 0, to: progress),
                        with: .linearGradient(
                            Gradient(colors: colors),
                            startPoint: CGPoint(x: 0, y: size.height * (1 - frame.progress)),
                            endPoint: CGPoint(x: size.width, y: size.height * frame.progress)
                        ),
                        style: StrokeStyle(lineWidth: contrast == .increased ? 6 : 5, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        } else {
            // Keep native shaping for joined scripts and combining marks; reveal the whole line.
            text(frame.language)
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .mask {
                    GeometryReader { geometry in
                        Path(FirstLaunchGreetingTimeline.revealRect(
                            in: geometry.size, progress: frame.progress, rightToLeft: frame.language.isRightToLeft
                        ))
                    }
                }
        }
    }

    private func text(_ language: AppLanguage) -> some View {
        Text(AppLocalization.string("onboarding.hello", language: language))
            .font(.system(size: 76, weight: .light, design: .rounded))
            .minimumScaleFactor(0.3)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
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
