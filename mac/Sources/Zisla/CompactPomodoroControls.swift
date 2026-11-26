import SwiftUI
import ZislaCore
import ZislaKit

struct CompactPomodoroControls: View {
    @EnvironmentObject private var pomodoro: PomodoroService
    @Environment(\.locale) private var locale
    let edge: IslandEdge
    var notice: IslandNotice? = nil

    private var timerID: UUID? { notice?.metadata?["timerID"].flatMap(UUID.init(uuidString:)) }
    private var phase: PomodoroPhase {
        timerID.flatMap { id in pomodoro.countdowns.first { $0.id == id }?.engine.phase } ?? pomodoro.phase
    }
    private var identifier: String { timerID.map { "countdown.\($0.uuidString)" } ?? "pomodoro" }
    private var groupMembers: [String]? { notice?.metadata?["timerIDs"]?.components(separatedBy: ",") }

    var body: some View {
        let toggleTitle = AppLocalization.string(phase == .running ? "暂停" : "继续", locale: locale)
        let cancelTitle = AppLocalization.string("取消", locale: locale)
        let row = edge.isVertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
        row {
            IconButton(symbol: phase == .running ? "pause.fill" : "play.fill",
                       help: toggleTitle, size: .compact, action: {
                           if let groupMembers { pomodoro.toggleCountdownGroup(groupMembers) }
                           else if let timerID { pomodoro.toggleCountdown(id: timerID) }
                           else { pomodoro.toggleStartPause() }
                       })
                       .accessibilityLabel(toggleTitle)
                       .accessibilityIdentifier("\(identifier).toggleStartPause")
            IconButton(symbol: "xmark", help: cancelTitle, size: .compact, action: {
                if let groupMembers { pomodoro.cancelCountdownGroup(groupMembers) }
                else if let timerID { pomodoro.cancelCountdown(id: timerID) }
                else { pomodoro.reset() }
            })
            .accessibilityLabel(cancelTitle)
            .accessibilityIdentifier(timerID.map { "countdown.\($0.uuidString).cancel" } ?? "pomodoro.reset")
        }
    }
}

struct CompactCountdownText: View {
    let name: String
    let clock: String
    let edge: IslandEdge
    let length: CGFloat
    let thickness: CGFloat

    var body: some View {
        Group {
            if edge.isVertical {
                let clockLength = CGFloat(CompactPillStatusPresentation.verticalTextRows(
                    clock, availableWidth: thickness, availableHeight: CompactPillStatusPresentation.maximumTextLength
                ).count) * 14
                let nameLength = max(0, length - clockLength - 6)
                VStack(spacing: 6) {
                    if !name.isEmpty && nameLength >= 14 {
                        VerticalStatusText(text: name, availableWidth: thickness, availableHeight: nameLength)
                            .frame(width: thickness, height: nameLength)
                            .accessibilityIdentifier("countdown.name")
                    }
                    VerticalStatusText(text: clock, availableWidth: thickness, availableHeight: clockLength)
                        .frame(width: thickness, height: clockLength)
                        .accessibilityIdentifier("countdown.time")
                }
            } else {
                HStack(spacing: 6) {
                    if !name.isEmpty {
                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityIdentifier("countdown.name")
                    }
                    Text(clock)
                        .monospacedDigit()
                        .fixedSize()
                        .accessibilityIdentifier("countdown.time")
                }
                .font(.system(size: 11, weight: .semibold))
            }
        }
        .frame(width: edge.isVertical ? thickness : length,
               height: edge.isVertical ? length : thickness, alignment: edge.isVertical ? .top : .leading)
    }
}

struct CompactPomodoroControlRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> CompactPomodoroControlRegionView {
        CompactPomodoroControlRegionView()
    }

    func updateNSView(_ view: CompactPomodoroControlRegionView, context: Context) {
        view.pixelAlignmentInset = 0.5 / context.environment.displayScale
    }
}

final class CompactPomodoroControlRegionView: NSView {
    var pixelAlignmentInset: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
