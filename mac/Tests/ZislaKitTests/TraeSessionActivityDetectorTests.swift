import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct TraeSessionActivityDetectorTests {
    @Test
    func detectsDoChatAsRunning() throws {
        let root = makeTraeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeTraeLog(
            under: root,
            dirName: "20260723T174155",
            fileName: "ai-agent_0_1784799715608_stdout.log",
            lines: [
                #"2026-07-23T17:41:55.981562+08:00  INFO ai_agent::bootstrap: [AI Agent Server] initializing"#,
                #"2026-07-23T20:08:01.801423+08:00  INFO process_ipc_request:route:chat:do_chat:dispatch: ai_agent::domain::chat: snapshot_handle is None trace_id="abc" session_id=6a61ffa1e2aa15b31f3a9b93 task_id=6a61ffa1e2aa15b31f3a9b97"#,
            ]
        )

        let task = try #require(TraeSessionActivityDetector(logsRoot: root).activeTasks().first)
        #expect(task.id == TraeSessionActivityDetector.taskID(forTaskID: "6a61ffa1e2aa15b31f3a9b97"))
        #expect(task.provider == .trae)
        #expect(task.title == "TRAE")
        #expect(task.status == .running)
        #expect(task.sessionURL?.absoluteString == "solo-cn://solo-deeplink.ai/teleport_session?sid=6a61ffa1e2aa15b31f3a9b93")
    }

    @Test
    func errorLineMarksErrorStatus() throws {
        let root = makeTraeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeTraeLog(
            under: root,
            dirName: "20260723T174155",
            fileName: "ai-agent_0_1784799715608_stdout.log",
            lines: [
                #"2026-07-23T20:08:01.801423+08:00  INFO process_ipc_request:route:chat:do_chat: ai_agent: started trace_id="t1" session_id=sess1 task_id=task1"#,
                #"2026-07-23T20:08:05.000000+08:00  ERROR process_ipc_request:route:chat:do_chat: ai_agent: failed trace_id="t1" session_id=sess1 task_id=task1"#,
            ]
        )

        let task = try #require(TraeSessionActivityDetector(logsRoot: root).activeTasks().first)
        #expect(task.status == .error)
    }

    @Test
    func ignoresLinesWithoutTaskID() throws {
        let root = makeTraeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeTraeLog(
            under: root,
            dirName: "20260723T174155",
            fileName: "ai-agent_0_1784799715608_stdout.log",
            lines: [
                #"2026-07-23T17:41:55.981562+08:00  INFO ai_agent::bootstrap: initializing boot config"#,
                #"2026-07-23T20:08:01.801423+08:00  INFO process_ipc_request:route:chat:do_chat: ai_agent: no task_id here trace_id="abc" session_id=sess1"#,
            ]
        )

        #expect(try TraeSessionActivityDetector(logsRoot: root).activeTasks().isEmpty)
    }

    @Test
    func handlesMissingDirectory() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-trae-missing-\(UUID().uuidString)")
        #expect(try TraeSessionActivityDetector(logsRoot: missing).activeTasks().isEmpty)
    }

    @Test
    func usesMostRecentLogDirectory() throws {
        let root = makeTraeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeTraeLog(
            under: root,
            dirName: "20260722T100000",
            fileName: "ai-agent_0_old_stdout.log",
            lines: [
                #"2026-07-22T10:00:00.000000+08:00  INFO process_ipc_request:route:chat:do_chat: ai_agent: old trace_id="old" session_id=old-sess task_id=old-task"#,
            ]
        )
        try writeTraeLog(
            under: root,
            dirName: "20260723T174155",
            fileName: "ai-agent_0_new_stdout.log",
            lines: [
                #"2026-07-23T20:08:01.801423+08:00  INFO process_ipc_request:route:chat:do_chat: ai_agent: new trace_id="new" session_id=new-sess task_id=new-task"#,
            ]
        )

        let tasks = try TraeSessionActivityDetector(logsRoot: root).activeTasks()
        #expect(tasks.count == 2)
        #expect(tasks[0].id == TraeSessionActivityDetector.taskID(forTaskID: "new-task"))
        #expect(tasks[1].id == TraeSessionActivityDetector.taskID(forTaskID: "old-task"))
    }
}

private func makeTraeTempRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-trae-\(UUID().uuidString)", isDirectory: true)
}

private func writeTraeLog(
    under root: URL,
    dirName: String,
    fileName: String,
    lines: [String]
) throws {
    let dir = root
        .appendingPathComponent(dirName, isDirectory: true)
        .appendingPathComponent("Modular", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(fileName)
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
}
