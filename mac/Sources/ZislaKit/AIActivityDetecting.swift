import Foundation
import ZislaCore

/// Structured AI session activity detector.
public protocol AIActivityDetecting {
    func activeTasks() throws -> [AIProgressTask]
    func taskUpdates() throws -> [AIProgressTask]
    var activityFileURLs: [URL] { get }
}

extension AIActivityDetecting {
    public func taskUpdates() throws -> [AIProgressTask] {
        try activeTasks()
    }

    public var activityFileURLs: [URL] { [] }
}

/// Extracts completed token usage from local session logs.
public protocol AIUsageDetecting {
    func usageSamples() throws -> [AIUsageSample]
}

extension CodexSessionActivityDetector: AIActivityDetecting {}
