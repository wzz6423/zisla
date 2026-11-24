import AppKit
import KeyboardKit
import SwiftUI
import ZislaCore
import ZislaKit

struct KeyboardSoundModuleView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Self.content(
            summary: model.keyboardSound.typingStatsSummary,
            voiceStatistics: model.settingsStore.settings.voiceInputEnabled
                ? model.voiceHistory.statistics : nil
        )
        .task(id: model.settingsStore.settings.keyboardTypingStatsEnabled) {
            guard model.settingsStore.settings.keyboardTypingStatsEnabled else { return }
            await model.keyboardSound.refreshTypingStats()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5), tolerance: .milliseconds(750))
                } catch {
                    return
                }
                await model.keyboardSound.refreshTypingStats()
            }
        }
    }

    static func content(
        summary: KeyboardTypingStatsSummary?,
        voiceStatistics: VoiceHistoryStatistics?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool = LegacyAppDataMigration.isDebugBuild
    ) -> some View {
        Group {
            if let summary, !(isDebugBuild && environment["ZISLA_DEBUG_IGNORE_KEYBOARD_STATS"] == "1") {
                DashboardScrollView(summary: summary, voiceStatistics: voiceStatistics)
                    .thinScrollChrome()
            } else {
                EmptyState(
                    symbol: "chart.xyaxis.line",
                    title: AppLocalization.text("暂无可显示的输入统计")
                )
            }
        }
    }

    private struct DashboardScrollView: NSViewRepresentable {
        let summary: KeyboardTypingStatsSummary
        let voiceStatistics: VoiceHistoryStatistics?

        func makeNSView(context: Context) -> NSScrollView {
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.horizontalScrollElasticity = .none
            let hosting = NSHostingView(rootView: content)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            scroll.documentView = hosting
            hosting.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
            return scroll
        }

        func updateNSView(_ scroll: NSScrollView, context: Context) {
            let hosting = scroll.documentView as! NSHostingView<AnyView>
            hosting.rootView = content
        }

        private var content: AnyView {
            AnyView(KeyboardTypingStatsDashboardView(summary: summary, voiceStatistics: voiceStatistics)
                .padding(12))
        }
    }
}
