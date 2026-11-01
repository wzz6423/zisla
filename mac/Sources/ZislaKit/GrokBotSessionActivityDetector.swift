import AppKit
import CoreFoundation
import CryptoKit
import Darwin
import Foundation
import ZislaCore

/// Replica layout and Base32 encoding adapted from Vibe Replay (MIT); see ThirdPartyLicenses.
public final class GrokBotSessionActivityDetector: AIActivityDetecting {
    public let dataDirectory: URL
    public let maxSessions: Int
    private let isApplicationRunning: (Int32) -> Bool
    private let now: () -> Date
    private var watchedFiles: [URL] = []

    public init(
        dataDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Grok Bot", isDirectory: true),
        maxSessions: Int = 4,
        isApplicationRunning: @escaping (Int32) -> Bool = { pid in
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.anysphere.sand")
                .contains { $0.processIdentifier == pid }
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.dataDirectory = dataDirectory
        self.maxSessions = max(1, maxSessions)
        self.isApplicationRunning = isApplicationRunning
        self.now = now
    }

    public var activityFileURLs: [URL] { watchedFiles }

    public func activeTasks() throws -> [AIProgressTask] {
        watchedFiles = []
        let root = open(dataDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { return [] }
        defer { close(root) }
        watchedFiles.append(dataDirectory)
        guard let runtime = readJSON("desktop-status.json", directory: root, url: dataDirectory),
              Self.number(runtime["version"]) == 1,
              Self.isTrue(runtime["signedIn"]),
              let rawPID = Self.number(runtime["pid"]), rawPID.rounded() == rawPID,
              rawPID > 0, rawPID <= Double(Int32.max),
              isApplicationRunning(Int32(rawPID)),
              let startedAt = Self.timestamp(runtime["startedAtMs"]) else { return [] }
        let currentTime = now()
        guard startedAt <= currentTime else { return [] }
        let persistence = openat(root, "sand-client-persistence", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard persistence >= 0 else { return [] }
        defer { close(persistence) }
        let directory = dataDirectory.appendingPathComponent("sand-client-persistence", isDirectory: true)
        watchedFiles.append(directory)
        guard let accountValue = readSlice("sand.client.slice.client-meta.account-slot", schema: 1,
                directory: persistence, url: directory) as? String, !accountValue.isEmpty,
              let account = accountValue.addingPercentEncoding(withAllowedCharacters:
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'()")) else { return [] }
        let prefix = "sand.client.slice.account.\(account.replacingOccurrences(of: ".", with: "%2E"))"
        guard let roster = readSlice(prefix + ".roster.last-roster", schema: 4,
                directory: persistence, url: directory) as? [String: Any],
              let rows = roster["rows"] as? [[String: Any]] else { return [] }
        let candidates = rows.filter {
            ($0["id"] as? String).flatMap(UUID.init(uuidString:)) != nil
                && !Self.isTrue($0["isHiddenFromSidebar"])
                && !Self.isTrue($0["isRemovedFromSidebar"])
        }.sorted {
            (Self.number($0["lastActivityAt"]) ?? Self.number($0["updatedAt"]) ?? 0)
                > (Self.number($1["lastActivityAt"]) ?? Self.number($1["updatedAt"]) ?? 0)
        }
        var tasks: [String: AIProgressTask] = [:]
        for row in candidates.prefix(12) {
            let id = row["id"] as! String
            guard let replica = readSlice(prefix + ".transcript.replicas." + id, schema: 1,
                    directory: persistence, url: directory) as? [String: Any],
                  let persistedAt = Self.timestamp(replica["persistedAt"]),
                  persistedAt >= startedAt, persistedAt <= currentTime,
                  currentTime.timeIntervalSince(persistedAt) <= 30 * 60,
                  let entries = replica["entries"] as? [[String: Any]],
                  let message = Self.latestMessage(in: entries),
                  let timestamp = Self.timestamp(message["timestampMs"]), timestamp <= currentTime,
                  currentTime.timeIntervalSince(timestamp) <= 30 * 60,
                  Self.isStreamingReply(message) else { continue }
            let taskID = "grok-bot-session-" + DesktopAIStorage.identity([accountValue, id])
            tasks[taskID] = AIProgressTask(
                id: taskID, provider: .grokBot,
                title: (row["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Grok Bot",
                progress: nil, status: .running, updatedAt: persistedAt, startedAt: timestamp
            )
        }
        return Array(tasks.values.sorted {
            $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id < $1.id
        }.prefix(maxSessions))
    }

    private static func latestMessage(in entries: [[String: Any]]) -> [String: Any]? {
        let messages = entries.filter {
            $0["kind"] as? String == "message" || $0["kind"] as? String == "send-message"
        }
        guard messages.allSatisfy({
            if $0["seq"] == nil { return true }
            guard let sequence = number($0["seq"]) else { return false }
            return sequence >= 0 && sequence.rounded() == sequence
        }) else { return nil }
        return messages.max {
            let first = number($0["seq"]) ?? 9_007_199_254_740_991
            let second = number($1["seq"]) ?? 9_007_199_254_740_991
            if first != second { return first < second }
            return (number($0["timestampMs"]) ?? 0) < (number($1["timestampMs"]) ?? 0)
        }
    }

    private static func isStreamingReply(_ entry: [String: Any]) -> Bool {
        if entry["kind"] as? String == "message" {
            return entry["role"] as? String == "assistant" && isTrue(entry["isStreaming"])
        }
        return (entry["message"] as? [String: Any])?["type"] as? String == "text" && isTrue(entry["streaming"])
    }

    private func readSlice(_ key: String, schema: Double, directory: Int32, url: URL) -> Any? {
        let encoded = Self.base32(Array(key.utf8)) + ".blob"
        let framed = encoded.utf8.count > 240
        let name = framed ? Self.base32(Array(SHA256.hash(data: Data(key.utf8)))) + ".kblob" : encoded
        guard let document = readJSON(name, directory: directory, url: url, framedKey: framed ? key : nil),
              Self.number(document["schemaVersion"]) == schema else { return nil }
        return document["value"]
    }

    private func readJSON(_ name: String, directory: Int32, url: URL, framedKey: String? = nil) -> [String: Any]? {
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_size >= 0, metadata.st_size <= 8 * 1_024 * 1_024 else { return nil }
        watchedFiles.append(url.appendingPathComponent(name))
        var data = Data(count: Int(metadata.st_size))
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeMutableBytes {
                read(descriptor, $0.baseAddress!.advanced(by: offset), $0.count - offset)
            }
            guard count > 0 else { return nil }
            offset += count
        }
        if let framedKey {
            guard let newline = data.firstIndex(of: 10),
                  (try? JSONSerialization.jsonObject(with: data[..<newline], options: [.fragmentsAllowed])) as? String == framedKey else { return nil }
            data = data[data.index(after: newline)...]
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func timestamp(_ value: Any?) -> Date? {
        guard number(value) != nil else { return nil }
        return DesktopAIStorage.milliseconds(value)
    }

    private static func isTrue(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

    private static func base32(_ bytes: [UInt8]) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var bits = 0
        var value: UInt32 = 0
        var output = ""
        for byte in bytes {
            value = (value << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                output.append(alphabet[Int((value >> (bits - 5)) & 31)])
                bits -= 5
            }
        }
        if bits > 0 { output.append(alphabet[Int((value << (5 - bits)) & 31)]) }
        return output
    }
}
