import Foundation
import ZislaCore

/// 结构化 AI 会话活动检测器。
public protocol AIActivityDetecting {
    func activeTasks() throws -> [AIProgressTask]
}

/// 从本地会话记录提取已完成的 token 用量。
public protocol AIUsageDetecting {
    func usageSamples() throws -> [AIUsageSample]
}

extension CodexSessionActivityDetector: AIActivityDetecting {}
