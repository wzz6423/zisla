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
        voiceStatistics: VoiceHistoryStatistics?
    ) -> some View {
        Group {
            if let summary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        KeyboardTypingStatsDashboardView(
                            summary: summary,
                            voiceStatistics: voiceStatistics
                        )
                    }
                    .padding(12)
                }
                .thinScrollChrome()
            } else {
                EmptyState(
                    symbol: "chart.xyaxis.line",
                    title: AppLocalization.text("暂无可显示的输入统计")
                )
            }
        }
    }
}
