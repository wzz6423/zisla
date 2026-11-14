import SwiftUI
import ZislaCore
import ZislaKit

struct CompactPomodoroControls: View {
    @EnvironmentObject private var pomodoro: PomodoroService
    @Environment(\.locale) private var locale
    let edge: IslandEdge

    var body: some View {
        let toggleTitle = AppLocalization.string(pomodoro.phase == .running ? "暂停" : "继续", locale: locale)
        let resetTitle = AppLocalization.string("重置番茄钟", locale: locale)
        let row = edge.isVertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
        row {
            IconButton(symbol: pomodoro.phase == .running ? "pause.fill" : "play.fill",
                help: toggleTitle, size: .compact, action: pomodoro.toggleStartPause)
                .accessibilityLabel(toggleTitle)
                .accessibilityIdentifier("pomodoro.toggleStartPause")
            IconButton(symbol: "arrow.counterclockwise", help: resetTitle, size: .compact, action: pomodoro.reset)
                .accessibilityLabel(resetTitle)
                .accessibilityIdentifier("pomodoro.reset")
        }
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
}
