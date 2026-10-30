import Foundation
import ZislaCore

enum RecordingMediaGrouping: String, CaseIterable, Identifiable {
    case none, type, importedAt, capturedAt
    var id: Self { self }

    var title: String {
        switch self {
        case .none: "不分组"
        case .type: "按类型"
        case .importedAt: "按导入时间"
        case .capturedAt: "按拍摄时间"
        }
    }
}

enum RecordingMediaTimeGranularity: String, CaseIterable, Identifiable {
    case hour, day, month, year
    var id: Self { self }

    var title: String {
        switch self {
        case .hour: "按小时"
        case .day: "按日"
        case .month: "按月"
        case .year: "按年"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .hour: .hour
        case .day: .day
        case .month: .month
        case .year: .year
        }
    }
}

struct RecordingMediaLibraryGroup: Identifiable {
    let id: String
    let title: String?
    let date: Date?
    let assets: [RecordingMediaAsset]
}

enum RecordingMediaLibraryGrouping {
    static func groups(assets: [RecordingMediaAsset], grouping: RecordingMediaGrouping,
                       granularity: RecordingMediaTimeGranularity, calendar: Calendar = .current) -> [RecordingMediaLibraryGroup] {
        switch grouping {
        case .none:
            return assets.isEmpty ? [] : [.init(id: "all", title: nil, date: nil, assets: assets)]
        case .type:
            return RecordingMediaKind.allCases.compactMap { kind in
                let matching = assets.filter { $0.kind == kind }
                guard !matching.isEmpty else { return nil }
                let title: String
                switch kind {
                case .video: title = "视频"
                case .image: title = "图片"
                case .audio: title = "音频"
                }
                return .init(id: kind.rawValue, title: title, date: nil, assets: matching)
            }
        case .importedAt, .capturedAt:
            var unknown: [RecordingMediaAsset] = []
            let known = Dictionary(grouping: assets.compactMap { asset -> (Date, RecordingMediaAsset)? in
                let date = grouping == .importedAt ? asset.importedAt : asset.capturedAt
                guard let date, let interval = calendar.dateInterval(of: granularity.component, for: date),
                      interval.contains(date) else {
                    unknown.append(asset)
                    return nil
                }
                return (interval.start, asset)
            }, by: { $0.0 })
            var result = known.keys.sorted(by: >).map { date in
                RecordingMediaLibraryGroup(id: String(date.timeIntervalSinceReferenceDate), title: nil, date: date,
                    assets: known[date]!.map { $0.1 })
            }
            if !unknown.isEmpty {
                result.append(.init(id: "unknown", title: grouping == .importedAt ? "未知导入时间" : "未知拍摄时间",
                    date: nil, assets: unknown))
            }
            return result
        }
    }
}
