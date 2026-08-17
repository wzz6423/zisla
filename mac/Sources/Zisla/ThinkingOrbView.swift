import SwiftUI
import ZislaCore

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

    static let taskStates: [Self] = [
        .working,
        .searching,
        .solving,
        .listening,
        .connecting,
        .weaving,
        .composing,
        .breathing,
        .shaping,
    ]

    static func forTask(_ task: AIProgressTask) -> Self {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in task.id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return taskStates[Int(hash % UInt64(taskStates.count))]
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
        case .shaping: "AI 正在工作"
        }
    }
}

enum ThinkingOrbTheme: Sendable {
    case auto
    case dark
    case light
}

struct ThinkingOrbView: View {
    var state: ThinkingOrbState = .working
    var size: CGFloat = 20
    var theme: ThinkingOrbTheme = .auto
    var speed: Double = 1
    var paused = false
    var tint: Color?
    var accessibilityLabel: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(
        state: ThinkingOrbState = .working,
        size: CGFloat = 20,
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
                    ink: inkColor
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
