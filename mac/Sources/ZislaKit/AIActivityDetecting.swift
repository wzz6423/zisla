import Foundation
import ZislaCore

/// Structured AI session activity detector.
public protocol AIActivityDetecting {
    func activeTasks() throws -> [AIProgressTask]
}

/// Extracts completed token usage from local session logs.
public protocol AIUsageDetecting {
    func usageSamples() throws -> [AIUsageSample]
}

extension CodexSessionActivityDetector: AIActivityDetecting {}
