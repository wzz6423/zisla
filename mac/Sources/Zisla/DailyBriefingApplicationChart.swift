import SwiftUI
import ZislaCore

struct DailyBriefingApplicationChart: View {
    struct Row: Identifiable, Equatable {
        enum ID: Hashable {
            case application(String)
            case other
        }

        let id: ID
        let name: String
        let seconds: TimeInterval
    }

    let applications: [String: DailyBriefingApplication]
    let language: AppLanguage
    let accent: Color
    let ink: Color
    let formatDuration: (TimeInterval) -> String

    var body: some View {
        let rows = Self.rows(for: applications, language: language)
        if let maximumSeconds = rows.map(\.seconds).max() {
            VStack(alignment: .leading, spacing: 18) {
                Text(AppLocalization.string("应用使用时间", language: language))
                    .font(.system(size: 18, weight: .semibold))
                VStack(spacing: 12) {
                    ForEach(rows) { row in
                        VStack(spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(row.name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text(formatDuration(row.seconds)).monospacedDigit().fixedSize()
                            }
                            .font(.system(size: 17))
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(ink.opacity(0.07))
                                    Capsule().fill(accent)
                                        .frame(width: geometry.size.width * (row.seconds / maximumSeconds))
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                }
            }
            .foregroundStyle(ink)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        }
    }

    static func rows(for applications: [String: DailyBriefingApplication], language: AppLanguage) -> [Row] {
        let sorted = applications.filter { $0.value.seconds.isFinite && $0.value.seconds > 0 }.sorted {
            if $0.value.seconds == $1.value.seconds { return $0.key < $1.key }
            return $0.value.seconds > $1.value.seconds
        }
        var rows = sorted.prefix(8).map { id, application in
            let name = application.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return Row(id: .application(id), name: name.isEmpty ? id : name, seconds: application.seconds)
        }
        let remaining = sorted.dropFirst(8)
        if !remaining.isEmpty {
            // Finite archived values can still overflow when combined.
            let seconds = remaining.reduce(0) { min(Double.greatestFiniteMagnitude, $0 + $1.value.seconds) }
            rows.append(Row(id: .other, name: AppLocalization.string("其他应用", language: language), seconds: seconds))
        }
        return rows
    }
}
