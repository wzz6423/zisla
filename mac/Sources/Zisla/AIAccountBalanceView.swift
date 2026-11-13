import SwiftUI
import ZislaCore
import ZislaKit

extension AIAccountQuotaSeverity {
    var balanceColor: Color {
        switch self { case .normal: .green; case .warning: .yellow; case .critical: .red; case .exhausted: .gray }
    }
}

struct AIAccountBalanceSection: View {
    let balances: [AIAccountBalance]
    let displayedProviders: Set<AIProvider>
    let monitoredProviders: Set<AIProvider>
    let language: AppLanguage

    var displayedBalances: [AIAccountBalance] {
        AIAccountBalanceCatalog.displayedBalances(balances, monitoredProviders: monitoredProviders,
            displayedProviders: displayedProviders)
    }

    var body: some View {
        if !displayedBalances.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label(AppLocalization.string("账户剩余额度", language: language), systemImage: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 11, weight: .semibold))
                AIAccountBalanceCardLayout(direction: language.isRightToLeft ? .rightToLeft : .leftToRight) {
                    ForEach(displayedBalances) { balance in
                        AIAccountBalanceCard(balance: balance, language: language)
                    }
                }
            }
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        }
    }
}

struct AIAccountBalanceCardLayout: Layout {
    var direction: LayoutDirection = .leftToRight
    private let spacing: CGFloat = 12

    private func columns(width: CGFloat) -> Int { min(3, max(1, Int((width + spacing) / (176 + spacing)))) }

    private func rowHeights(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        let count = columns(width: width)
        let cardWidth = max(0, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
        var heights: [CGFloat] = []
        for (index, subview) in subviews.enumerated() {
            if index % count == 0 { heights.append(0) }
            heights[index / count] = max(heights[index / count],
                subview.sizeThatFits(ProposedViewSize(width: cardWidth, height: nil)).height)
        }
        return heights
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 420
        let heights = rowHeights(width: width, subviews: subviews)
        return CGSize(width: width, height: heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = columns(width: bounds.width)
        let width = max(0, (bounds.width - CGFloat(count - 1) * spacing) / CGFloat(count))
        let heights = rowHeights(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let column = index % count
            if column == 0, index > 0 { y += heights[index / count - 1] + spacing }
            let x = CGFloat(column) * (width + spacing)
            subview.place(at: CGPoint(x: bounds.minX + (direction == .rightToLeft ? bounds.width - x - width : x), y: y),
                anchor: .topLeading, proposal: ProposedViewSize(width: width, height: heights[index / count]))
        }
    }
}

struct AIAccountBalanceCard: View {
    let balance: AIAccountBalance
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(balance.providerTitle(language: language))
                .font(.system(size: 11, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if balance.fiveHourWindow != nil || balance.weeklyWindow != nil {
                HStack(alignment: .center, spacing: 8) {
                    AIAccountQuotaRing(provider: balance.displayProvider,
                        fraction: balance.weeklyWindow?.remainingFraction,
                        severity: balance.weeklyWindow?.severity, diameter: 52,
                        innerFraction: balance.fiveHourWindow?.remainingFraction,
                        innerSeverity: balance.fiveHourWindow?.severity)
                    VStack(alignment: .leading, spacing: 8) {
                        if let window = balance.fiveHourWindow { quotaDetails(window, label: "5h") }
                        if let window = balance.weeklyWindow { quotaDetails(window, label: "7d") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(balance.windows.filter { $0.id != balance.fiveHourWindow?.id && $0.id != balance.weeklyWindow?.id }) { window in
                HStack(alignment: .center, spacing: 8) {
                    AIAccountQuotaRing(provider: balance.displayProvider, fraction: window.remainingFraction,
                        severity: window.severity, diameter: 42)
                    quotaDetails(window, label: window.label(language: language))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.fillCard, in: RoundedRectangle(cornerRadius: IslandSurfaceGeometry.moduleInnerCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: IslandSurfaceGeometry.moduleInnerCornerRadius)
                .strokeBorder(Color.strokeCard, lineWidth: 1)
        }
    }

    private func quotaDetails(_ window: AIAccountQuotaWindow, label: String) -> some View {
        let title = Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        let value = Text(window.value(language: language))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit().foregroundStyle(window.severity.balanceColor)
        var details = Text("\(title) \(value)")
        if let reset = window.resetsAt {
            let resetText = Text(AppLocalization.format("%@ 重置", locale: language.locale,
                [reset.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute().locale(language.locale))]))
                .font(.system(size: 9)).foregroundStyle(.secondary)
            details = Text("\(details) · \(resetText)")
        }
        return details.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AIAccountQuotaRing: View {
    let provider: AIProvider?
    let fraction: Double?
    let severity: AIAccountQuotaSeverity?
    let diameter: CGFloat
    var innerFraction: Double?
    var innerSeverity: AIAccountQuotaSeverity?

    var body: some View {
        ZStack {
            if let severity { arc(fraction: fraction, severity: severity, diameter: diameter) }
            if let innerSeverity { arc(fraction: innerFraction, severity: innerSeverity, diameter: diameter * 0.7) }
        }
        .overlay {
            if let provider {
                AIMascotView(identity: AIMascotIdentity(provider: provider, taskID: ""), size: diameter * (innerSeverity == nil ? 0.48 : 0.36))
            }
        }
        .frame(width: diameter, height: diameter)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private func arc(fraction: Double?, severity: AIAccountQuotaSeverity, diameter: CGFloat) -> some View {
        let width = self.diameter * 4 / 42
        return ZStack {
            Circle().stroke(severity.balanceColor.opacity(0.2), lineWidth: width)
            if let fraction, fraction > 0 {
                Circle().trim(from: 0, to: fraction)
                    .stroke(severity.balanceColor, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(width / 2 + 0.5)
        .frame(width: diameter, height: diameter)
    }
}

struct AIAccountBalanceProviderStatus: View {
    @ObservedObject var monitor: AIStateMonitor
    let provider: AIProvider
    let language: AppLanguage

    var status: AIAccountBalanceStatus {
        monitor.accountBalances.first { $0.providers.contains(provider) }?.status
            ?? AIAccountBalanceCatalog.placeholder(for: [provider]).status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AIAccountBalanceCatalog.providerName(provider))
            Text(AppLocalization.string(status.title, language: language))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompactAIAccountBalanceBar: View {
    let notice: IslandNotice
    let height: CGFloat
    var centerInset: CGFloat = 0
    var edge: IslandEdge = .top
    var leadingInset: CGFloat = CompactPillStatusPresentation.trailingInset
    @Environment(\.layoutDirection) private var direction

    private var lines: [String] { (0..<2).compactMap { notice.metadata?["quotaLine\($0)"] } }
    private var severity: AIAccountQuotaSeverity {
        AIAccountQuotaSeverity(rawValue: Int(notice.metadata?["quotaSeverity"] ?? "") ?? 0) ?? .normal
    }
    private var provider: AIProvider? { notice.metadata?["quotaProviderID"].flatMap(AIProvider.init(rawValue:)) }
    private var fraction: Double? { notice.metadata?["quotaRemainingFraction"].flatMap(Double.init) }
    private var ringDiameter: CGFloat { max(0, height - 8) }

    private var ring: some View {
        let hasCanonical = notice.metadata?["quota5hSeverity"] != nil || notice.metadata?["quota7dSeverity"] != nil
        return AIAccountQuotaRing(provider: provider,
            fraction: hasCanonical ? notice.metadata?["quota7dFraction"].flatMap(Double.init) : fraction,
            severity: hasCanonical ? quotaSeverity(key: "quota7dSeverity") : severity,
            diameter: ringDiameter, innerFraction: notice.metadata?["quota5hFraction"].flatMap(Double.init),
            innerSeverity: quotaSeverity(key: "quota5hSeverity"))
    }

    var body: some View {
        GeometryReader { geometry in
            if !edge.isVertical, centerInset > 0 {
                let center = min(centerInset, geometry.size.width)
                let sideWidth = max(0, (geometry.size.width - center) / 2)
                HStack(spacing: 0) {
                    ring.frame(width: sideWidth)
                    Spacer(minLength: 0).frame(width: center)
                    horizontalValues
                        .padding(.horizontal, CompactPillStatusPresentation.accountBalanceSideInset)
                        .frame(width: sideWidth)
                        .environment(\.layoutDirection, direction)
                }
                .environment(\.layoutDirection, .leftToRight)
                .frame(width: geometry.size.width, height: geometry.size.height)
            } else if edge.isVertical {
                let valueHeight = max(0, geometry.size.height - leadingInset
                    - CompactPillStatusPresentation.trailingInset - ringDiameter - 6)
                let valueWidth = max(0, (geometry.size.width - 8 - CGFloat(max(0, lines.count - 1)) * 2)
                    / CGFloat(max(1, lines.count)))
                VStack(spacing: 6) {
                    ring
                    HStack(alignment: .top, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            VerticalStatusText(text: line, availableWidth: valueWidth,
                                availableHeight: valueHeight, scrollsAutomatically: true)
                                .foregroundStyle((quotaSeverity(key: "quotaLineSeverity\(index)") ?? severity).balanceColor)
                        }
                    }
                    .environment(\.layoutDirection, direction)
                    .frame(height: valueHeight)
                    .id(notice.metadata?["quotaAccountID"])
                }
                .padding(.top, leadingInset).padding(.bottom, CompactPillStatusPresentation.trailingInset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            } else {
                HStack(spacing: 6) {
                    ring
                    horizontalValues
                        .environment(\.layoutDirection, direction)
                }
                .padding(.leading, leadingInset).padding(.trailing, CompactPillStatusPresentation.trailingInset)
                .environment(\.layoutDirection, .leftToRight)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
        }
        .frame(height: edge.isVertical ? nil : height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.title + " " + lines.joined(separator: " "))
        .help(notice.title + " " + lines.joined(separator: " "))
    }

    private var horizontalValues: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                MarqueeText(line, font: .system(size: lines.count > 1 ? 9 : 11).monospacedDigit(),
                    textColor: (quotaSeverity(key: "quotaLineSeverity\(index)") ?? severity).balanceColor,
                    fontWeight: lines.count > 1 ? .medium : .semibold,
                    pointsPerSecond: CompactPillStatusPresentation.accountBalanceScrollSpeed,
                    scrollDirection: direction == .rightToLeft ? .right : .left,
                    repeats: false,
                    viewportHeight: lines.count > 1 ? 11 : 16)
            }
        }
        .id(notice.metadata?["quotaAccountID"])
    }

    private func quotaSeverity(key: String) -> AIAccountQuotaSeverity? {
        notice.metadata?[key].flatMap(Int.init).flatMap(AIAccountQuotaSeverity.init(rawValue:))
    }
}
