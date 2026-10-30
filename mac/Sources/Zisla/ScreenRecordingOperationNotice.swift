import ZislaCore
import ZislaKit

enum ScreenRecordingOperationNotice {
    static let prefix = "screen-recording-operation-"

    static func progressText(for notice: IslandNotice) -> String {
        switch notice.kind {
        case .success: AppLocalization.text("已完成")
        case .error, .warning: AppLocalization.text("失败")
        case .info:
            if let progress = notice.progress {
                "\(Int((progress * 100).rounded()))%"
            } else {
                AppLocalization.text("进行中")
            }
        }
    }
}

extension SideNoticeQueue {
    var screenRecordingOperations: [IslandNotice] {
        (left + right).filter { $0.id.hasPrefix(ScreenRecordingOperationNotice.prefix) }
    }
}
