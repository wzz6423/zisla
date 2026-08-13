import SwiftUI
import ZislaCore

/// 点阵思考球表示的 AI 活动。
enum ThinkingOrbState: String, CaseIterable, Sendable {
    case working
    case searching
    case solving
    case listening
    case connecting
    case weaving
    case composing
    case breathing
    case shaping

    static func forTask(_ task: AIProgressTask) -> Self {
        // 同一任务保持同一动效，避免视图刷新时随机切换。
        let index = Int(UInt(bitPattern: task.id.hashValue) % UInt(allCases.count))
        return allCases[index]
    }

    var accessibilityLabel: String {
        switch self {
        case .working: "正在工作"
        case .searching: "正在搜索"
        case .solving: "正在解决问题"
        case .listening: "正在聆听"
        case .connecting: "正在连接"
        case .weaving: "正在组织信息"
        case .composing: "正在生成内容"
        case .breathing: "正在等待操作"
        case .shaping: "AI 状态异常"
        }
    }
}

enum ThinkingOrbTheme: Sendable {
    case auto
    case dark
    case light
}

/// 纯 SwiftUI 点阵指示器，用于 AI 工作和其他不确定进度状态。
///
/// 使用单个 Canvas 和 TimelineView 动画时钟，保证 20pt 内联版本开销可控，同时让 64pt 版本具备足够的点数；
/// 每种模式都由确定性数学轨迹生成，状态切换不会引入随机跳变。
struct ThinkingOrbView: View {
    var state: ThinkingOrbState = .working
    var size: CGFloat = 64
    var theme: ThinkingOrbTheme = .auto
    var speed: Double = 1
    var paused = false
    var tint: Color?
    var accessibilityLabel: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(
        state: ThinkingOrbState = .working,
        size: CGFloat = 64,
        theme: ThinkingOrbTheme = .auto,
        speed: Double = 1,
        paused: Bool = false,
        tint: Color? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.state = state
        self.size = size
        self.theme = theme
        self.speed = speed
        self.paused = paused
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        let side = max(1, size)
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion || paused
            )
        ) { timeline in
            Canvas(rendersAsynchronously: true) { context, canvasSize in
                let time = reduceMotion || paused
                    ? 0
                    : timeline.date.timeIntervalSinceReferenceDate * max(0, speed)
                ThinkingOrbRenderer.draw(
                    state: state,
                    into: &context,
                    size: canvasSize,
                    time: time,
                    ink: inkColor,
                    isLarge: side >= 40
                )
            }
            .frame(width: side, height: side)
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel ?? state.accessibilityLabel))
        .accessibilityAddTraits(.isImage)
    }

    private var inkColor: Color {
        if let tint { return tint }
        switch theme {
        case .dark:
            return .white
        case .light:
            return .black
        case .auto:
            return colorScheme == .dark ? .white : .black
        }
    }
}

private enum ThinkingOrbRenderer {
    private struct Dot {
        var point: CGPoint
        var radius: CGFloat
        var opacity: Double
        var depth: CGFloat = 0
    }

    private struct Line {
        var start: CGPoint
        var end: CGPoint
        var opacity: Double
    }

    private static let tau = Double.pi * 2

    static func draw(
        state: ThinkingOrbState,
        into context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        ink: Color,
        isLarge: Bool
    ) {
        let side = min(size.width, size.height)
        guard side > 0 else { return }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = side * 0.39
        let dotScale = isLarge ? 1 : 0.96
        let dotFloor = isLarge ? 0.72 : 0.78
        var dots: [Dot] = []
        var lines: [Line] = []

        switch state {
        case .working:
            working(dots: &dots, center: center, radius: radius, time: time, scale: dotScale)
        case .searching:
            searching(dots: &dots, center: center, radius: radius, time: time, scale: dotScale)
        case .solving:
            solving(dots: &dots, center: center, radius: radius, time: time, scale: dotScale)
        case .listening:
            listening(dots: &dots, center: center, radius: radius, time: time, scale: dotScale)
        case .connecting:
            connecting(
                dots: &dots,
                lines: &lines,
                center: center,
                radius: radius,
                time: time,
                scale: dotScale
            )
        case .weaving:
            weaving(dots: &dots, center: center, radius: radius, time: time, scale: dotScale)
        case .composing:
            composing(dots: &dots, center: center, radius: radius, time: time, scale: dotScale)
        case .breathing:
            breathing(dots: &dots, center: center, radius: radius, time: time, scale: dotScale)
        case .shaping:
            shaping(dots: &dots, center: center, radius: radius, time: time, scale: dotScale)
        }

        for line in lines {
            var path = Path()
            path.move(to: line.start)
            path.addLine(to: line.end)
            context.stroke(
                path,
                with: .color(ink.opacity(line.opacity)),
                style: StrokeStyle(lineWidth: max(0.45, side * 0.011), lineCap: .round)
            )
        }

        // 按深度绘制，让朝向前方的点覆盖较暗的后方点。
        for dot in dots.sorted(by: { $0.depth < $1.depth }) {
            let radius = max(side * 0.012 * dotScale * dotFloor, dot.radius)
            let rect = CGRect(
                x: dot.point.x - radius,
                y: dot.point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(ink.opacity(dot.opacity)))
        }
    }

    private static func working(
        dots: inout [Dot],
        center: CGPoint,
        radius: CGFloat,
        time: TimeInterval,
        scale: CGFloat
    ) {
        let count = 34
        let rotation = time * 0.84
        for index in 0..<count {
            let progress = Double(index) / Double(count)
            let angle = progress * tau + rotation
            let orbit = radius * (0.60 + 0.27 * sin(progress * tau * 2.0 + 0.4))
            let x = cos(angle) * orbit
            let y = sin(angle) * orbit * 0.42
            let z = sin(angle)
            dots.append(
                Dot(
                    point: CGPoint(x: center.x + x, y: center.y + y),
                    radius: radius * (0.018 + 0.014 * max(0, z)) * scale,
                    opacity: 0.22 + 0.70 * Double((z + 1) / 2),
                    depth: z
                )
            )
        }

        for orbitIndex in 0..<3 {
            let orbitAngle = Double(orbitIndex) * 1.95 + rotation * (orbitIndex.isMultiple(of: 2) ? 0.7 : -0.55)
            let cosOrbit = cos(orbitAngle)
            let sinOrbit = sin(orbitAngle)
            for index in 0..<9 {
                let progress = Double(index) / 9
                let angle = progress * tau + orbitAngle * 0.8
                let x = cos(angle) * radius * 0.72
                let y = sin(angle) * radius * 0.72 * 0.38
                let rotatedX = x * cosOrbit - y * sinOrbit
                let rotatedY = x * sinOrbit + y * cosOrbit
                let depth = sin(angle + orbitAngle)
                dots.append(
                    Dot(
                        point: CGPoint(x: center.x + rotatedX, y: center.y + rotatedY),
                        radius: radius * 0.018 * scale,
                        opacity: 0.18 + 0.48 * Double((depth + 1) / 2),
                        depth: depth - 0.1
                    )
                )
            }
        }
    }

    private static func searching(
        dots: inout [Dot],
        center: CGPoint,
        radius: CGFloat,
        time: TimeInterval,
        scale: CGFloat
    ) {
        let meridian = sin(time * 1.65)
        let latitudes: [CGFloat] = [-0.82, -0.54, -0.25, 0, 0.25, 0.54, 0.82]
        for latitude in latitudes {
            let rowRadius = sqrt(max(0, 1 - latitude * latitude))
            let count = 8 + Int(rowRadius * 8)
            for index in 0..<count {
                let longitude = (Double(index) / Double(count)) * tau
                let x = cos(longitude) * rowRadius
                let y = latitude
                let visible = x * x + y * y <= 1.01
                guard visible else { continue }
                let scanDistance = abs(x - meridian * 0.88)
                let scan = max(0, 1 - scanDistance * 2.7)
                dots.append(
                    Dot(
                        point: CGPoint(x: center.x + x * radius, y: center.y + y * radius),
                        radius: radius * (0.014 + 0.020 * scan) * scale,
                        opacity: 0.18 + 0.62 * scan + 0.16 * max(0, x),
                        depth: x
                    )
                )
            }
        }
    }

    private static func solving(
        dots: inout [Dot],
        center: CGPoint,
        radius: CGFloat,
        time: TimeInterval,
        scale: CGFloat
    ) {
        let columns = 8
        let rows = 8
        let phase = time * 1.25
        for row in 0..<rows {
            for column in 0..<columns {
                let u = CGFloat(column) / CGFloat(columns - 1) * 2 - 1
                let v = CGFloat(row) / CGFloat(rows - 1) * 2 - 1
                let scramble = sin(phase + Double(row) * 1.7 + Double(column) * 0.83)
                let settle = min(1, max(0, 0.5 + 0.5 * sin(phase * 0.48)))
                let x = u * (0.76 + (1 - settle) * 0.16 * CGFloat(scramble))
                let y = v * (0.76 + (1 - settle) * 0.12 * CGFloat(cos(phase + Double(column))))
                let distance = sqrt(x * x + y * y)
                guard distance <= 1.02 else { continue }
                let pulse = 0.72 + 0.28 * sin(phase * 1.7 + Double(row + column))
                dots.append(
                    Dot(
                        point: CGPoint(x: center.x + x * radius, y: center.y + y * radius),
                        radius: radius * 0.025 * (0.7 + 0.3 * pulse) * scale,
                        opacity: 0.28 + 0.62 * Double(pulse),
                        depth: CGFloat(distance)
                    )
                )
            }
        }
    }

    private static func listening(
        dots: inout [Dot],
        center: CGPoint,
        radius: CGFloat,
        time: TimeInterval,
        scale: CGFloat
    ) {
        let rings = 7
        for ring in 0..<rings {
            let phase = Double(ring) * 0.72
            let ringRadius = radius * (0.25 + CGFloat(ring) * 0.095)
            let count = 8 + ring * 2
            for index in 0..<count {
                let progress = Double(index) / Double(count)
                let angle = progress * tau + time * (0.38 + Double(ring) * 0.04) + phase
                let wave = sin(time * 3.3 - Double(ring) * 0.55 + progress * tau * 2.4)
                let y = sin(angle) * ringRadius * (0.36 + 0.16 * wave)
                let x = cos(angle) * ringRadius
                dots.append(
                    Dot(
                        point: CGPoint(x: center.x + x, y: center.y + y),
                        radius: radius * (0.015 + 0.011 * max(0, wave)) * scale,
                        opacity: 0.22 + 0.58 * Double((wave + 1) / 2),
                        depth: CGFloat(ring)
                    )
                )
            }
        }
    }

    private static func connecting(
        dots: inout [Dot],
        lines: inout [Line],
        center: CGPoint,
        radius: CGFloat,
        time: TimeInterval,
        scale: CGFloat
    ) {
        let count = 16
        var points: [CGPoint] = []
        for index in 0..<count {
            let angle = Double(index) / Double(count) * tau
            let wobble = 0.78 + 0.12 * sin(time * 0.9 + Double(index) * 1.4)
            let point = CGPoint(
                x: center.x + cos(angle + time * 0.16) * radius * wobble,
                y: center.y + sin(angle + time * 0.16) * radius * wobble
            )
            points.append(point)
            dots.append(
                Dot(
                    point: point,
                    radius: radius * 0.028 * scale,
                    opacity: 0.52 + 0.40 * (0.5 + 0.5 * sin(time * 1.7 + Double(index))),
                    depth: CGFloat(index)
                )
            )
        }

        for index in 0..<count {
            let next = (index + 1) % count
            let pulse = 0.5 + 0.5 * sin(time * 2.2 - Double(index) * 0.7)
            lines.append(Line(start: points[index], end: points[next], opacity: 0.10 + 0.30 * pulse))
            if index.isMultiple(of: 3) {
                let across = (index + count / 2) % count
                lines.append(Line(start: points[index], end: points[across], opacity: 0.06 + 0.17 * pulse))
            }
        }
    }

    private static func weaving(
        dots: inout [Dot],
        center: CGPoint,
        radius: CGFloat,
        time: TimeInterval,
        scale: CGFloat
    ) {
        let strands = 3
        for strand in 0..<strands {
            let phase = Double(strand) * tau / Double(strands)
            for index in 0..<20 {
                let progress = Double(index) / 19
                let x = (progress * 2 - 1) * radius * 0.92
                let y = sin(progress * tau * 1.35 + time * 1.45 + phase) * radius * 0.30
                let z = sin(progress * tau * 1.35 + time * 1.45 + phase + Double.pi / 2)
                dots.append(
                    Dot(
                        point: CGPoint(x: center.x + x, y: center.y + y),
                        radius: radius * (0.017 + 0.015 * max(0, z)) * scale,
                        opacity: 0.24 + 0.65 * Double((z + 1) / 2),
                        depth: CGFloat(z)
                    )
                )
            }
        }
    }

    private static func composing(
        dots: inout [Dot],
        center: CGPoint,
        radius: CGFloat,
        time: TimeInterval,
        scale: CGFloat
    ) {
        let rows = 5
        let columns = 24
        for row in 0..<rows {
            let rowPhase = Double(row) * 0.74
            for column in 0..<columns {
                let progress = Double(column) / Double(columns - 1)
                let x = (progress * 2 - 1) * radius
                let wave = sin(progress * tau * 1.4 + time * 1.15 + rowPhase)
                let y = (Double(row) - 2) * radius * 0.17 + wave * radius * 0.075
                let highlight = 0.5 + 0.5 * sin(time * 2 + progress * tau * 2 - rowPhase)
                dots.append(
                    Dot(
                        point: CGPoint(x: center.x + x, y: center.y + y),
                        radius: radius * (0.012 + 0.014 * CGFloat(highlight)) * scale,
                        opacity: 0.20 + 0.58 * highlight,
                        depth: CGFloat(row)
                    )
                )
            }
        }
    }

    private static func breathing(
        dots: inout [Dot],
        center: CGPoint,
        radius: CGFloat,
        time: TimeInterval,
        scale: CGFloat
    ) {
        let breath = 0.86 + 0.12 * sin(time * 1.05)
        let count = 42
        for index in 0..<count {
            let progress = Double(index) / Double(count)
            let angle = progress * tau
            let ringRadius = radius * CGFloat(breath + 0.04 * sin(progress * tau * 3 + time * 0.8))
            let pulse = 0.5 + 0.5 * sin(time * 1.4 + progress * tau)
            dots.append(
                Dot(
                    point: CGPoint(
                        x: center.x + cos(angle) * ringRadius,
                        y: center.y + sin(angle) * ringRadius
                    ),
                    radius: radius * (0.015 + 0.017 * CGFloat(pulse)) * scale,
                    opacity: 0.24 + 0.62 * pulse,
                    depth: CGFloat(pulse)
                )
            )
        }
    }

    private static func shaping(
        dots: inout [Dot],
        center: CGPoint,
        radius: CGFloat,
        time: TimeInterval,
        scale: CGFloat
    ) {
        let cycle = (time / 3.2).truncatingRemainder(dividingBy: 3)
        let phase = cycle < 1 ? cycle : cycle < 2 ? cycle - 1 : cycle - 2
        let fromShape = cycle < 1 ? 0 : cycle < 2 ? 1 : 2
        let toShape = cycle < 1 ? 1 : cycle < 2 ? 2 : 0
        let count = 36
        for index in 0..<count {
            let progress = Double(index) / Double(count)
            let from = shapePoint(shape: fromShape, progress: progress)
            let to = shapePoint(shape: toShape, progress: progress)
            let point = CGPoint(
                x: center.x + radius * lerp(from.x, to.x, phase),
                y: center.y + radius * lerp(from.y, to.y, phase)
            )
            let pulse = 0.5 + 0.5 * sin(time * 2.1 + progress * tau)
            dots.append(
                Dot(
                    point: point,
                    radius: radius * (0.015 + 0.016 * CGFloat(pulse)) * scale,
                    opacity: 0.28 + 0.60 * pulse,
                    depth: CGFloat(pulse)
                )
            )
        }
    }

    private static func shapePoint(shape: Int, progress: Double) -> CGPoint {
        switch shape {
        case 1:
            let side = progress * 3
            if side < 1 {
                return CGPoint(x: -0.02 + side * 0.88, y: -0.82 + side * 1.52)
            }
            if side < 2 {
                return CGPoint(x: 0.86 - (side - 1) * 1.72, y: 0.70)
            }
            return CGPoint(x: -0.86 + (side - 2) * 0.88, y: 0.70 - (side - 2) * 1.52)
        case 2:
            let side = progress * 4
            switch side {
            case 0..<1: return CGPoint(x: -0.82 + side * 1.64, y: -0.72)
            case 1..<2: return CGPoint(x: 0.82, y: -0.72 + (side - 1) * 1.44)
            case 2..<3: return CGPoint(x: 0.82 - (side - 2) * 1.64, y: 0.72)
            default: return CGPoint(x: -0.82, y: 0.72 - (side - 3) * 1.44)
            }
        default:
            let angle = progress * tau - Double.pi / 2
            return CGPoint(x: cos(angle) * 0.86, y: sin(angle) * 0.86)
        }
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ progress: Double) -> CGFloat {
        a + (b - a) * CGFloat(progress)
    }
}
