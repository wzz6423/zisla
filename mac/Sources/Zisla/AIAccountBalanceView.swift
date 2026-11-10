import SwiftUI
import ZislaCore
import ZislaKit

extension AIAccountQuotaSeverity {
    var balanceColor: Color {
        switch self { case .normal: .primary; case .warning: .yellow; case .critical: .red; case .exhausted: .gray }
    }
}

struct AIAccountBalanceSection: View {
    let balances: [AIAccountBalance]
    let displayedProviders: Set<AIProvider>
    let language: AppLanguage

    var displayedBalances: [AIAccountBalance] {
        balances.compactMap { balance in
            var row = balance
            row.providers = row.providers.filter { displayedProviders.contains($0) }
            return row.providers.isEmpty ? nil : row
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AppLocalization.string("账户剩余额度", language: language), systemImage: "gauge.with.dots.needle.67percent")
                .font(.system(size: 11, weight: .semibold))
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(displayedBalances) { balance in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(balance.providerTitle(language: language))
                                .font(.system(size: 11, weight: .semibold))
                            Spacer(minLength: 8)
                            if balance.status != .available {
                                Text(AppLocalization.string(balance.status.title, language: language))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        if balance.status == .available {
                            ForEach(balance.windows) { window in
                                ViewThatFits(in: .horizontal) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        quotaIdentity(window).fixedSize()
                                        quotaValue(window)
                                        quotaProgress(window)
                                        Spacer(minLength: 0)
                                        quotaReset(window).fixedSize()
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        quotaIdentity(window).fixedSize(horizontal: false, vertical: true)
                                        HStack(spacing: 8) { quotaValue(window); quotaProgress(window) }
                                        quotaReset(window).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        if let detail = balance.detailKey {
                            Text(AppLocalization.string(detail, language: language)).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
    }

    private func quotaIdentity(_ window: AIAccountQuotaWindow) -> some View {
        Text(window.label(language: language)).font(.system(size: 10)).foregroundStyle(.secondary)
    }

    private func quotaValue(_ window: AIAccountQuotaWindow) -> some View {
        Text(window.value(language: language)).font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit().foregroundStyle(window.severity.balanceColor).fixedSize()
    }

    @ViewBuilder private func quotaProgress(_ window: AIAccountQuotaWindow) -> some View {
        if let fraction = window.remainingPercent {
            ProgressView(value: fraction, total: 100).tint(window.severity.balanceColor).frame(maxWidth: 100)
        }
    }

    @ViewBuilder private func quotaReset(_ window: AIAccountQuotaWindow) -> some View {
        if let reset = window.resetsAt {
            Text(AppLocalization.format("%@ 重置", locale: language.locale,
                [reset.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute().locale(language.locale))]))
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

struct CompactAIAccountBalanceBar: View {
    let notice: IslandNotice
    let height: CGFloat
    var centerInset: CGFloat = 0
    var edge: IslandEdge = .top
    @Environment(\.layoutDirection) private var direction

    private var lines: [String] { (0..<2).compactMap { notice.metadata?["quotaLine\($0)"] } }
    private var severity: AIAccountQuotaSeverity {
        AIAccountQuotaSeverity(rawValue: Int(notice.metadata?["quotaSeverity"] ?? "") ?? 0) ?? .normal
    }

    var body: some View {
        GeometryReader { geometry in
            let title = notice.metadata?["quotaProvider"] ?? notice.title
            if !edge.isVertical, centerInset > 0 {
                let center = min(centerInset, geometry.size.width)
                let sideWidth = max(0, (geometry.size.width - center) / 2)
                HStack(spacing: 0) {
                    Text(verbatim: title).font(.system(size: 10, weight: .semibold))
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.horizontal, 12).frame(width: sideWidth, alignment: .leading)
                        .environment(\.layoutDirection, direction)
                    Spacer(minLength: 0).frame(width: center)
                    horizontalValues.padding(.horizontal, 12).frame(width: sideWidth, alignment: .trailing)
                        .environment(\.layoutDirection, direction)
                }
                .environment(\.layoutDirection, .leftToRight)
                .frame(width: geometry.size.width, height: geometry.size.height)
            } else if edge.isVertical {
                let contentHeight = max(0, geometry.size.height - 24)
                let titleHeight = contentHeight * 0.25
                let valueHeight = max(0, contentHeight - titleHeight - 8)
                VStack(spacing: 8) {
                    VerticalStatusText(text: title, availableWidth: height - 8,
                        availableHeight: titleHeight)
                        .frame(height: titleHeight)
                    HStack(alignment: .top, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            VerticalStatusText(text: line, availableWidth: (height - 8) / CGFloat(max(1, lines.count)),
                                availableHeight: valueHeight)
                                .foregroundStyle(severity.balanceColor)
                        }
                    }
                    .frame(height: valueHeight)
                }
                .padding(.vertical, 12).frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                HStack(spacing: 8) {
                    Text(verbatim: title).font(.system(size: 10, weight: .semibold))
                        .lineLimit(1).truncationMode(.tail).frame(maxWidth: geometry.size.width * 0.35, alignment: .leading)
                    horizontalValues.frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 12).frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .frame(height: edge.isVertical ? nil : height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.title + " " + lines.joined(separator: " "))
        .help(notice.title + " " + lines.joined(separator: " "))
    }

    private var horizontalValues: some View {
        VStack(alignment: .trailing, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).font(.system(size: lines.count > 1 ? 9 : 11, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail).foregroundStyle(severity.balanceColor)
            }
        }
    }
}
