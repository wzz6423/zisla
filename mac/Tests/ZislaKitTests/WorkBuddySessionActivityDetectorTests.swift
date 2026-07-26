import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct WorkBuddySessionActivityDetectorTests {
    @Test
    func detectsRecentDesktopSessionAndBuildsDeepLink() throws {
        let root = try makeWorkBuddyTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try writeSessionIndex(
            to: root,
            sessions: [
                [
                    "conversationId": "conversation-123",
                    "startedAt": "2027-01-15T08:00:00.000Z",
                    "resumedAt": "2027-01-15T08:20:00.000Z",
                ],
            ]
        )

        let task = try #require(WorkBuddySessionActivityDetector(
            sessionsURL: root.appendingPathComponent("sessions.json"),
            now: { now }
        ).activeTasks().first)

        #expect(task.id == WorkBuddySessionActivityDetector.taskID(forConversationID: "conversation-123"))
        #expect(task.provider == .harness)
        #expect(task.title == "WorkBuddy")
        #expect(task.detail == "Desktop")
        #expect(task.status == .running)
        #expect(task.sessionURL?.absoluteString == "workbuddy://chat/conversation-123")
        #expect(task.startedAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(task.updatedAt == Date(timeIntervalSince1970: 1_800_001_200))
    }

    @Test
    func ignoresStaleSessions() throws {
        let root = try makeWorkBuddyTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeSessionIndex(
            to: root,
            sessions: [
                [
                    "conversationId": "conversation-stale",
                    "startedAt": "2027-01-15T07:00:00Z",
                    "resumedAt": "2027-01-15T07:00:00Z",
                ],
            ]
        )

        let tasks = try WorkBuddySessionActivityDetector(
            sessionsURL: root.appendingPathComponent("sessions.json"),
            recencyThreshold: 30 * 60,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        ).activeTasks()

        #expect(tasks.isEmpty)
    }

    @Test
    func ignoresMissingOrInvalidSessionIndex() throws {
        let root = try makeWorkBuddyTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let missing = root.appendingPathComponent("sessions.json")
        #expect(try WorkBuddySessionActivityDetector(sessionsURL: missing).activeTasks().isEmpty)

        try Data("not json".utf8).write(to: missing)
        #expect(try WorkBuddySessionActivityDetector(sessionsURL: missing).activeTasks().isEmpty)
    }
}

private func makeWorkBuddyTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-workbuddy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeSessionIndex(to root: URL, sessions: [[String: String]]) throws {
    let data = try JSONSerialization.data(withJSONObject: ["sessions": sessions])
    try data.write(to: root.appendingPathComponent("sessions.json"))
}
