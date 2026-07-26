import Foundation
import ZislaCore

/// Infers recently active tasks from WorkBuddy Desktop's session index.
public final class WorkBuddySessionActivityDetector: AIActivityDetecting {
    private struct SessionIndex: Decodable {
        var sessions: [SessionRecord]
    }

    private struct SessionRecord: Decodable {
        var conversationID: String
        var startedAt: String
        var resumedAt: String

        enum CodingKeys: String, CodingKey {
            case conversationID = "conversationId"
            case startedAt
            case resumedAt
        }
    }

    public let sessionsURL: URL
    public let recencyThreshold: TimeInterval

    private let now: () -> Date

    public init(
        sessionsURL: URL? = nil,
        recencyThreshold: TimeInterval = 30 * 60,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.sessionsURL = sessionsURL ?? Self.defaultSessionsURL(
            home: fileManager.homeDirectoryForCurrentUser
        )
        self.recencyThreshold = max(0, recencyThreshold)
        self.now = now
    }

    public func activeTasks() throws -> [AIProgressTask] {
        guard let data = try? Data(contentsOf: sessionsURL),
              let index = try? JSONDecoder().decode(SessionIndex.self, from: data) else {
            return []
        }

        let earliestActivity = now().addingTimeInterval(-recencyThreshold)
        return index.sessions.compactMap { session in
            let conversationID = session.conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !conversationID.isEmpty,
                  let startedAt = Self.parseDate(session.startedAt),
                  let resumedAt = Self.parseDate(session.resumedAt) else {
                return nil
            }
            let updatedAt = max(startedAt, resumedAt)
            guard updatedAt > earliestActivity else { return nil }

            return AIProgressTask(
                id: Self.taskID(forConversationID: conversationID),
                provider: .harness,
                title: "WorkBuddy",
                detail: "Desktop",
                progress: nil,
                status: .running,
                updatedAt: updatedAt,
                sessionURL: Self.sessionURL(for: conversationID),
                effort: nil,
                startedAt: startedAt
            )
        }
        .sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public static func taskID(forConversationID conversationID: String) -> String {
        "workbuddy-session-\(conversationID)"
    }

    public static func defaultSessionsURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(".workbuddy/app/sessions.json")
    }

    private static func sessionURL(for conversationID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "workbuddy"
        components.host = "chat"
        components.path = "/\(conversationID)"
        return components.url
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
