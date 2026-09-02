import KeyboardKit
import SwiftUI

struct KeyboardSoundModuleView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let summary = model.keyboardSound.typingStatsSummary {
                    KeyboardTypingStatsDashboardView(summary: summary)
                } else {
                    Label("暂无可显示的输入统计", systemImage: "chart.xyaxis.line")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
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
}
