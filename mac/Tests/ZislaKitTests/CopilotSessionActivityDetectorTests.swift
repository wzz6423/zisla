import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct CopilotSessionActivityDetectorTests {
    @Test
    func detectsActiveVSCodeTranscriptWithoutInventingADeepLink() throws {
        let root = temporaryRoot("copilot-vscode")
        defer { try? FileManager.default.removeItem(at: root) }
        let transcriptURL = root
            .appendingPathComponent("workspace/chatSessions", isDirectory: true)
            .appendingPathComponent("session-vscode.jsonl")
        try FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeLines([
            #"{"timestamp":"2026-07-26T01:00:00.000Z","type":"session.start","data":{"sessionId":"session-vscode","startTime":"2026-07-26T01:00:00.000Z"}}"#,
            #"{"timestamp":"2026-07-26T01:00:01.000Z","type":"user.message","data":{"content":"run tests"}}"#,
            #"{"timestamp":"2026-07-26T01:00:02.000Z","type":"assistant.turn_start","data":{"turnId":"turn-1"}}"#,
        ], to: transcriptURL)

        let detector = CopilotSessionActivityDetector(
            workspaceStorageDirectories: [root],
            cliSessionStateDirectory: root.appendingPathComponent("missing-cli")
        )
        let task = try #require(detector.activeTasks().first)

        #expect(task.id == CopilotSessionActivityDetector.vsCodeTaskID(forSessionID: "session-vscode"))
        #expect(task.provider == .copilot)
        #expect(task.title == "GitHub Copilot (VS Code)")
        #expect(task.status == .running)
        #expect(task.sessionURL == nil)
    }

    @Test
    func completedVSCodeTranscriptIsNotActive() throws {
        let root = temporaryRoot("copilot-vscode-complete")
        defer { try? FileManager.default.removeItem(at: root) }
        let transcriptURL = root
            .appendingPathComponent("workspace/chatSessions", isDirectory: true)
            .appendingPathComponent("session-complete.jsonl")
        try FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeLines([
            #"{"timestamp":"2026-07-26T01:00:00.000Z","type":"session.start","data":{"sessionId":"session-complete"}}"#,
            #"{"timestamp":"2026-07-26T01:00:01.000Z","type":"user.message","data":{"content":"done"}}"#,
            #"{"timestamp":"2026-07-26T01:00:02.000Z","type":"assistant.turn_end","data":{"turnId":"turn-1"}}"#,
        ], to: transcriptURL)

        let detector = CopilotSessionActivityDetector(
            workspaceStorageDirectories: [root],
            cliSessionStateDirectory: root.appendingPathComponent("missing-cli")
        )
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test
    func detectsCopilotCLISessionWithoutADeepLink() throws {
        let root = temporaryRoot("copilot-cli")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionDirectory = root.appendingPathComponent("session-cli", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let state = """
        id: session-cli
        cwd: /tmp/project
        created_at: 2026-07-26T01:00:00.000Z
        updated_at: 2026-07-26T01:00:03.000Z
        """
        try state.write(
            to: sessionDirectory.appendingPathComponent("workspace.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let detector = CopilotSessionActivityDetector(
            workspaceStorageDirectories: [root.appendingPathComponent("missing-workspace")],
            cliSessionStateDirectory: root
        )
        let task = try #require(detector.activeTasks().first)

        #expect(task.id == CopilotSessionActivityDetector.cliTaskID(forSessionID: "session-cli"))
        #expect(task.provider == .copilot)
        #expect(task.title == "GitHub Copilot CLI")
        #expect(task.detail == "/tmp/project")
        #expect(task.status == .running)
        #expect(task.sessionURL == nil)
    }

    private func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func writeLines(_ lines: [String], to url: URL) throws {
        try lines.joined(separator: "\n").appending("\n").write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
    }
}
