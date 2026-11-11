import SwiftUI
import ZislaCore
import ZislaKit

struct ScenarioNotificationReviewView: View {
    @ObservedObject var queue: SideNoticeQueue
    let displayIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AppLocalizedText("场景通知回顾").font(.headline)
                Spacer()
                Button(AppLocalization.text("清空回顾")) {
                    queue.dismissScenarioReview(displayIdentifier: displayIdentifier)
                }
                .disabled(items.isEmpty)
                .accessibilityIdentifier("scenarioReview.clear")
            }
            if items.isEmpty {
                AppLocalizedText("没有延后提示").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(items.reversed()) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                if let detail = item.detail, !detail.isEmpty {
                                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                                }
                                Text(item.recordedAt, style: .time).font(.caption2).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var items: [ScenarioNotificationReviewItem] { queue.scenarioReview(displayIdentifier: displayIdentifier) }
}
