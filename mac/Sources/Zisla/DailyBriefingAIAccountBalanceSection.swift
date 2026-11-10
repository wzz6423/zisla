import SwiftUI
import ZislaCore

struct DailyBriefingAIAccountBalanceSection: View {
    let balances: [AIAccountBalance]
    let language: AppLanguage
    let ink: Color

    var rows: [AIAccountBalance] { balances.filter { $0.severity != nil && !$0.isDebug } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.string("账户剩余额度", language: language)).font(.system(size: 18, weight: .semibold))
            ForEach(rows) { balance in
                HStack(alignment: .top, spacing: 18) {
                    Text(balance.providerTitle(language: language))
                        .font(.system(size: 14, weight: .medium)).frame(width: 150, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(balance.windows) { window in
                            Text(window.label(language: language) + " " + window.value(language: language))
                                .font(.system(size: 14)).foregroundStyle(window.severity == .normal ? ink : window.severity.balanceColor)
                        }
                        if let updatedAt = balance.updatedAt {
                            Text(AppLocalization.format("采样于 %@", locale: language.locale,
                                [updatedAt.formatted(.dateTime.year().month().day().hour().minute().locale(language.locale))]))
                                .font(.system(size: 11)).foregroundStyle(ink.opacity(0.65))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}
