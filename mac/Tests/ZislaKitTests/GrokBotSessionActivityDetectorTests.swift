import CryptoKit
import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct GrokBotSessionActivityDetectorTests {
    private let now = Date(timeIntervalSince1970: 1_910_000_000)
    private let agentID = "b0000001-aaaa-bbbb-cccc-000000000001"
    private let account = "fixture.account"

    @Test func publishesCurrentAccountStreamingRepliesWithoutConversationContents() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRuntime(at: root)
        try writeAccount(account, at: root)
        try writeRoster([row(agentID)], account: account, at: root)
        let replica = try writeReplica([entry(1, streaming: true)], agent: agentID, account: account, at: root)
        let before = try Data(contentsOf: replica)
        let detector = makeDetector(root)
        let tasks = try detector.activeTasks()
        let task = try #require(tasks.first)
        #expect(tasks.count == 1)
        #expect(task.provider == .grokBot && task.status == .running && task.title == "Fixture Bot")
        #expect(task.detail == nil && task.sessionURL == nil && task.progress == nil)
        #expect(!task.id.contains(account) && !task.id.contains(root.path))
        #expect(!String(describing: task).contains("private prompt"))
        #expect(task.updatedAt == now.addingTimeInterval(-1))
        #expect(task.startedAt == now.addingTimeInterval(-10))
        #expect(detector.activityFileURLs.contains(root))
        #expect(detector.activityFileURLs.contains(root.appendingPathComponent("sand-client-persistence")))
        #expect(detector.activityFileURLs.contains(replica))
        #expect(try Data(contentsOf: replica) == before)
    }

    @Test func removesFinishedRepliesAndIgnoresHistoricalStreamingBySequence() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRuntime(at: root)
        try writeAccount(account, at: root)
        try writeRoster([row(agentID)], account: account, at: root)
        try writeReplica([entry(1, streaming: true)], agent: agentID, account: account, at: root)
        let detector = makeDetector(root)
        #expect(try detector.activeTasks().count == 1)
        try writeReplica([entry(2, streaming: false), entry(1, streaming: true)], agent: agentID, account: account, at: root)
        #expect(try detector.activeTasks().isEmpty)
        try writeReplica([entry(1, streaming: true), entry(2, streaming: true, role: "user")],
            agent: agentID, account: account, at: root)
        #expect(try detector.activeTasks().isEmpty)
        try writeReplica([entry(1, streaming: true), ["kind": "send-message", "seq": 2,
            "timestampMs": milliseconds(-1), "message": ["type": "text", "content": "settled"]]],
            agent: agentID, account: account, at: root)
        #expect(try detector.activeTasks().isEmpty)
        try writeReplica([["kind": "send-message", "seq": 3, "timestampMs": milliseconds(-1),
            "streaming": true, "message": ["type": "text", "content": ""]]],
            agent: agentID, account: account, at: root)
        #expect(try detector.activeTasks().count == 1)
        try writeReplica([["kind": "send-message", "seq": 4, "timestampMs": milliseconds(-1),
            "streaming": true, "message": ["type": "attachment"]]],
            agent: agentID, account: account, at: root)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test func unsequencedRepliesAndEqualSequencesUseUpstreamTimestampOrder() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRuntime(at: root)
        try writeAccount(account, at: root)
        try writeRoster([row(agentID)], account: account, at: root)
        let detector = makeDetector(root)
        var streaming = entry(2, streaming: true)
        streaming.removeValue(forKey: "seq")
        try writeReplica([streaming, entry(1, streaming: false, offset: -20)],
            agent: agentID, account: account, at: root)
        #expect(try detector.activeTasks().count == 1)
        var finished = entry(3, streaming: false, offset: -1)
        finished.removeValue(forKey: "seq")
        try writeReplica([finished, streaming], agent: agentID, account: account, at: root)
        #expect(try detector.activeTasks().isEmpty)
        try writeReplica([entry(2, streaming: false, offset: -1), entry(2, streaming: true)],
            agent: agentID, account: account, at: root)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test func switchesAccountsAndClearsTasksOnLogoutAndApplicationExit() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRuntime(at: root)
        try writeAccount(account, at: root)
        try writeRoster([row(agentID)], account: account, at: root)
        try writeReplica([entry(1, streaming: true)], agent: agentID, account: account, at: root)
        let detector = makeDetector(root)
        let firstID = try #require(detector.activeTasks().first?.id)
        try writeAccount("other", at: root)
        #expect(try detector.activeTasks().isEmpty)
        try writeRoster([row(agentID, name: "Other Bot")], account: "other", at: root)
        try writeReplica([entry(1, streaming: true)], agent: agentID, account: "other", at: root)
        let otherTask = try #require(detector.activeTasks().first)
        #expect(otherTask.id != firstID && otherTask.title == "Other Bot")
        try writeRuntime(at: root, signedIn: false)
        #expect(try detector.activeTasks().isEmpty)
        try writeRuntime(at: root)
        #expect(try makeDetector(root, running: false).activeTasks().isEmpty)
        try writeAccount(nil, at: root)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test func rejectsStaleFutureAndPreviousProcessSnapshotsEvenWhenRosterIsRecent() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRuntime(at: root)
        try writeAccount(account, at: root)
        try writeRoster([row(agentID)], account: account, at: root)
        let detector = makeDetector(root)
        for savedOffset in [-2_000.0, -200, 1] {
            try writeReplica([entry(1, streaming: true, offset: savedOffset - 1)], agent: agentID,
                account: account, persistedAt: milliseconds(savedOffset), at: root)
            #expect(try detector.activeTasks().isEmpty, "Invalid persistedAt offset: \(savedOffset)")
        }
        try writeReplica([entry(1, streaming: true, offset: 1)], agent: agentID, account: account, at: root)
        #expect(try detector.activeTasks().isEmpty)
        try writeReplica([entry(1, streaming: true, offset: -2_000)], agent: agentID, account: account, at: root)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test func excludesHiddenAndMalformedRosterRowsAndReturnsNewestTasksWithinBudget() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRuntime(at: root)
        try writeAccount(account, at: root)
        let second = "b0000002-aaaa-bbbb-cccc-000000000002"
        let hidden = "b0000003-aaaa-bbbb-cccc-000000000003"
        var hiddenRow = row(hidden)
        hiddenRow["isHiddenFromSidebar"] = true
        try writeRoster([row(agentID), row(second), hiddenRow, row("../escape"), row("")], account: account, at: root)
        try writeReplica([entry(1, streaming: true)], agent: agentID, account: account, persistedAt: milliseconds(-2), at: root)
        try writeReplica([entry(1, streaming: true)], agent: second, account: account, at: root)
        try writeReplica([entry(1, streaming: true)], agent: hidden, account: account, at: root)
        try writeReplica([entry(1, streaming: true)], agent: "../escape", account: account, at: root)
        try writeReplica([entry(1, streaming: true)], agent: "", account: account, at: root)
        let detector = makeDetector(root, maxSessions: 1)
        #expect(try detector.activeTasks().count == 1)
        #expect(try detector.activeTasks().first?.id == "grok-bot-session-" + DesktopAIStorage.identity([account, second]))
        #expect(try makeDetector(root).activeTasks().count == 2)
        try writeRoster((1...14).map {
            ["id": String(format: "b0000001-aaaa-bbbb-cccc-%012d", $0), "name": "Bot \($0)",
             "updatedAt": milliseconds(-Double($0)), "isRemovedFromSidebar": $0 == 1]
        }, account: account, at: root)
        for index in 1...14 {
            try writeReplica([entry(1, streaming: true)],
                agent: String(format: "b0000001-aaaa-bbbb-cccc-%012d", index), account: account, at: root)
        }
        #expect(try makeDetector(root, maxSessions: 100).activeTasks().count == 12)
        #expect(try makeDetector(root, maxSessions: 100).activeTasks().allSatisfy { $0.title != "Bot 1" && $0.title != "Bot 14" })
        try writeRoster([row(agentID, name: "")], account: account, at: root)
        #expect(try makeDetector(root).activeTasks().first?.title == "Grok Bot")
    }

    @Test func corruptStoresRecoverOnNextScanAndUnknownSchemasProduceNoTasks() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("missing")
        #expect(try makeDetector(missing).activeTasks().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        try writeRuntime(at: root)
        try writeAccount(account, at: root)
        try writeRoster([row(agentID)], account: account, at: root)
        let replica = try writeReplica([entry(1, streaming: true)], agent: agentID, account: account, at: root)
        let detector = makeDetector(root)
        try Data("{".utf8).write(to: replica)
        #expect(try detector.activeTasks().isEmpty)
        try writeReplica([entry(1, streaming: true)], agent: agentID, account: account, at: root)
        #expect(try detector.activeTasks().count == 1)
        try writeSlice("sand.client.slice.account.fixture%2Eaccount.transcript.replicas.\(agentID)",
            value: ["entries": [entry(1, streaming: true)], "persistedAt": milliseconds(-1)], schema: 99, at: root)
        #expect(try detector.activeTasks().isEmpty)
        try writeRoster([row(agentID)], account: account, schema: 99, at: root)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test func rejectsMalformedStreamingFlagsSequencesClocksAndEnvelopeTypes() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRuntime(at: root)
        try writeAccount(account, at: root)
        try writeRoster([row(agentID)], account: account, at: root)
        let detector = makeDetector(root)
        let mutations: [[String: Any]] = [
            ["isStreaming": 1], ["isStreaming": "true"], ["role": "tool"], ["seq": true],
            ["seq": -1], ["seq": 1.5], ["timestampMs": true], ["timestampMs": 0],
        ]
        for mutation in mutations {
            try writeReplica([entry(1, streaming: true).merging(mutation) { _, new in new }],
                agent: agentID, account: account, at: root)
            #expect(try detector.activeTasks().isEmpty, "Invalid message fields: \(mutation.keys.sorted())")
        }
        try writeReplica([entry(1, streaming: true)], agent: agentID, account: account, persistedAt: true, at: root)
        #expect(try detector.activeTasks().isEmpty)
        for mutation in [["seq": true], ["seq": -1], ["timestampMs": "invalid"]] as [[String: Any]] {
            try writeReplica([entry(1, streaming: true), entry(2, streaming: false).merging(mutation) { _, new in new }],
                agent: agentID, account: account, at: root)
            #expect(try detector.activeTasks().isEmpty, "A malformed newer message must not revive an earlier streaming flag")
        }
        try writeReplica([entry(1, streaming: true)], agent: agentID, account: account, at: root)
        try writeRoster([], account: account, at: root)
        #expect(try detector.activeTasks().isEmpty)
        try writeAccount(account, schema: 99, at: root)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test func rejectsMissingInvalidAndMismatchedRuntimeMarkersWithoutReadingAccountStores() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeAccount(account, at: root)
        try writeRoster([row(agentID)], account: account, at: root)
        try writeReplica([entry(1, streaming: true)], agent: agentID, account: account, at: root)
        let detector = makeDetector(root)
        #expect(try detector.activeTasks().isEmpty)
        let runtime = root.appendingPathComponent("desktop-status.json")
        for mutation in [["pid": true], ["pid": 1.5], ["pid": -1], ["pid": 124],
            ["pid": Int64(Int32.max) + 1], ["signedIn": 1], ["version": 99], ["startedAtMs": milliseconds(1)]] as [[String: Any]] {
            let document: [String: Any] = ["version": 1, "pid": 123, "startedAtMs": milliseconds(-100), "signedIn": true]
            try JSONSerialization.data(withJSONObject: document.merging(mutation) { _, new in new }).write(to: runtime)
            #expect(try detector.activeTasks().isEmpty)
            #expect(detector.activityFileURLs.allSatisfy { !$0.path.contains("sand-client-persistence") })
        }
        try Data("not-json".utf8).write(to: runtime)
        #expect(try detector.activeTasks().isEmpty)
        try writeRuntime(at: root)
        #expect(try detector.activeTasks().count == 1)
    }

    @Test func refusesSymlinkedFilesAndDirectoriesAndOversizedReplicasWithoutWriting() throws {
        let root = try fixtureRoot()
        let outside = try fixtureRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try writeRuntime(at: root)
        try writeAccount(account, at: root)
        try writeRoster([row(agentID)], account: account, at: root)
        let replica = try writeReplica([entry(1, streaming: true)], agent: agentID, account: account, at: root)
        let external = outside.appendingPathComponent("external.json")
        let contents = try Data(contentsOf: replica)
        let rootLink = outside.appendingPathComponent("root-link")
        try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: root)
        #expect(try makeDetector(rootLink).activeTasks().isEmpty)
        try contents.write(to: external)
        try FileManager.default.removeItem(at: replica)
        try FileManager.default.createSymbolicLink(at: replica, withDestinationURL: external)
        let detector = makeDetector(root)
        #expect(try detector.activeTasks().isEmpty)
        #expect(!detector.activityFileURLs.contains(replica))
        #expect(try Data(contentsOf: external) == contents)
        try FileManager.default.removeItem(at: replica)
        try FileManager.default.createDirectory(at: replica, withIntermediateDirectories: false)
        #expect(try detector.activeTasks().isEmpty)
        #expect(!detector.activityFileURLs.contains(replica))
        try FileManager.default.removeItem(at: replica)
        var oversized = entry(1, streaming: true)
        oversized["content"] = String(repeating: "x", count: 8 * 1_024 * 1_024 + 1)
        try writeReplica([oversized], agent: agentID, account: account, at: root)
        #expect(try detector.activeTasks().isEmpty)
        try contents.write(to: replica)
        let persistence = root.appendingPathComponent("sand-client-persistence")
        try FileManager.default.moveItem(at: persistence, to: outside.appendingPathComponent("persistence"))
        try FileManager.default.createSymbolicLink(at: persistence, withDestinationURL: outside.appendingPathComponent("persistence"))
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test func supportsDigestFramedLongAccountKeysAndRejectsIncorrectFrame() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let longAccount = String(repeating: "a", count: 180)
        try writeRuntime(at: root)
        try writeAccount(longAccount, at: root)
        try writeRoster([row(agentID)], account: longAccount, at: root)
        let replica = try writeReplica([entry(1, streaming: true)], agent: agentID, account: longAccount, at: root)
        #expect(replica.pathExtension == "kblob")
        let detector = makeDetector(root)
        #expect(try detector.activeTasks().count == 1)
        let contents = String(decoding: try Data(contentsOf: replica), as: UTF8.self)
        let tail = try #require(contents.firstIndex(of: "\n"))
        try Data(("\"sand.client.slice.account.other.transcript.replicas.\(agentID)\"" + contents[tail...]).utf8).write(to: replica)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test func fixedSeedMalformedDocumentsNeverPublishTasksOrModifyStores() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRuntime(at: root)
        try writeAccount(account, at: root)
        try writeRoster([row(agentID)], account: account, at: root)
        let replica = try writeReplica([], agent: agentID, account: account, at: root)
        let detector = makeDetector(root)
        var seed: UInt64 = 0x4752_4f4b
        for _ in 0..<64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let data = Data((0..<Int(seed % 128 + 1)).map { UInt8(truncatingIfNeeded: seed >> ($0 % 8)) })
            try data.write(to: replica)
            #expect(try detector.activeTasks().isEmpty)
            #expect(try Data(contentsOf: replica) == data)
        }
        try writeReplica([entry(1, streaming: true)], agent: agentID, account: account, at: root)
        #expect(try detector.activeTasks().count == 1)
    }

    private func makeDetector(_ root: URL, running: Bool = true, maxSessions: Int = 4) -> GrokBotSessionActivityDetector {
        GrokBotSessionActivityDetector(dataDirectory: root, maxSessions: maxSessions,
            isApplicationRunning: { $0 == 123 && running }, now: { now })
    }

    private func milliseconds(_ offset: Double) -> Double { now.addingTimeInterval(offset).timeIntervalSince1970 * 1_000 }

    private func row(_ id: String, name: String = "Fixture Bot") -> [String: Any] {
        ["id": id, "name": name, "updatedAt": milliseconds(-1), "isHiddenFromSidebar": false]
    }

    private func entry(_ sequence: Int, streaming: Bool, role: String = "assistant", offset: Double = -10) -> [String: Any] {
        ["kind": "message", "seq": sequence, "timestampMs": milliseconds(offset), "role": role,
         "isStreaming": streaming, "content": "private prompt must not appear in task data"]
    }

    private func writeRuntime(at root: URL, signedIn: Bool = true) throws {
        let value: [String: Any] = ["version": 1, "pid": 123, "appVersion": "0.78.1",
            "startedAtMs": milliseconds(-100), "signedIn": signedIn]
        try JSONSerialization.data(withJSONObject: value).write(to: root.appendingPathComponent("desktop-status.json"))
    }

    private func writeAccount(_ value: String?, schema: Int = 1, at root: URL) throws {
        try writeSlice("sand.client.slice.client-meta.account-slot", value: value as Any? ?? NSNull(), schema: schema, at: root)
    }

    private func writeRoster(_ rows: [[String: Any]], account: String, schema: Int = 4, at root: URL) throws {
        try writeSlice("sand.client.slice.account.\(escaped(account)).roster.last-roster", value: ["rows": rows], schema: schema, at: root)
    }

    @discardableResult private func writeReplica(_ entries: [[String: Any]], agent: String, account: String,
        persistedAt: Any? = nil, at root: URL) throws -> URL {
        try writeSlice("sand.client.slice.account.\(escaped(account)).transcript.replicas.\(agent)",
            value: ["entries": entries, "persistedAt": persistedAt ?? milliseconds(-1),
                "epochHint": "fixture", "acceptedSequenceHint": 1], schema: 1, at: root)
    }

    @discardableResult private func writeSlice(_ key: String, value: Any, schema: Int, at root: URL) throws -> URL {
        let directory = root.appendingPathComponent("sand-client-persistence")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = base32(Array(key.utf8)) + ".blob"
        let long = encoded.utf8.count > 240
        let url = directory.appendingPathComponent(long ? base32(Array(SHA256.hash(data: Data(key.utf8)))) + ".kblob" : encoded)
        var data = Data()
        if long {
            data.append(try JSONSerialization.data(withJSONObject: key, options: [.fragmentsAllowed]))
            data.append(10)
        }
        data.append(try JSONSerialization.data(withJSONObject: ["schemaVersion": schema, "value": value]))
        try data.write(to: url)
        return url
    }

    private func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'()"))!
            .replacingOccurrences(of: ".", with: "%2E")
    }

    private func base32(_ bytes: [UInt8]) -> String {
        let bits = bytes.flatMap { byte in (0..<8).reversed().map { (byte >> $0) & 1 } }
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        return stride(from: 0, to: bits.count, by: 5).map { start in
            let index = (0..<5).reduce(0) { value, offset in
                value * 2 + (start + offset < bits.count ? Int(bits[start + offset]) : 0)
            }
            return String(alphabet[index])
        }.joined()
    }

    private func fixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-grok-bot-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
