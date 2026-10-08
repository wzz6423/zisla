import Foundation
import ZislaCore

/// WorkBuddy AI uses the same indexed session schema as the legacy desktop client, but owns
/// a separate data root and URL scheme. Do not infer activity from transcript file mtime or
/// import `session_usage.used`: that field is context-window occupancy, not billed token usage.
public final class WorkBuddyAISessionActivityDetector: AIActivityDetecting {
    public let databaseURL: URL
    private let detector: WorkBuddySessionActivityDetector

    public init(
        databaseURL: URL? = nil,
        recencyThreshold: TimeInterval = 30 * 60,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        let url = databaseURL ?? Self.defaultDatabaseURL(home: fileManager.homeDirectoryForCurrentUser)
        self.databaseURL = url
        self.detector = WorkBuddySessionActivityDetector(
            databaseURL: url,
            recencyThreshold: recencyThreshold,
            now: now,
            fileManager: fileManager,
            provider: .workbuddy,
            sourceName: "WorkBuddy AI",
            urlScheme: "workbuddy-ai",
            taskIDPrefix: "workbuddy-ai-session-"
        )
    }

    public static func defaultDatabaseURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".workbuddy-ai/workbuddy.db", isDirectory: false)
    }

    public var activityFileURLs: [URL] { detector.activityFileURLs }

    public func activeTasks() throws -> [AIProgressTask] { try detector.activeTasks() }
}
