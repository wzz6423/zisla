import Foundation
import ZislaCore

public enum ClaudeCodeVSCodeSettingsError: LocalizedError, Sendable {
    case invalidSettings

    public var errorDescription: String? {
        switch self {
        case .invalidSettings: "VS Code settings.json 不是可安全更新的 JSON"
        }
    }
}

/// Updates only the two settings that Zisla owns and restores their previous values when disabled.
public struct ClaudeCodeVSCodeSettingsService: Sendable {
    public let settingsURL: URL

    public init(settingsURL: URL? = nil) {
        self.settingsURL = settingsURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Code/User/settings.json")
    }

    public func reconcile(
        configuration: Data?,
        enhancements: AgentApplicationEnhancements
    ) throws -> AgentApplicationEnhancements {
        var settings = try loadSettings()
        var updated = enhancements
        var snapshot = updated.claudeCodeVSCodeSettingsSnapshot

        if enhancements.claudeCodeVSCodeFollowsProvider || enhancements.skipsClaudeCodeOnboarding {
            if snapshot == nil {
                snapshot = ClaudeCodeVSCodeSettingsSnapshot(
                    environmentVariables: environmentVariables(in: settings),
                    hideOnboarding: settings["claudeCode.hideOnboarding"] as? Bool
                )
            }
        }

        if enhancements.claudeCodeVSCodeFollowsProvider {
            restoreManagedEnvironmentVariables(in: &settings, snapshot: &snapshot)
            let environment = providerEnvironment(from: configuration)
            if !environment.isEmpty {
                var current = environmentVariables(in: settings) ?? [:]
                for (name, value) in environment {
                    current[name] = value
                }
                setEnvironmentVariables(current, in: &settings)
                snapshot?.managedEnvironmentVariableNames = environment.keys.sorted()
            }
        } else {
            restoreManagedEnvironmentVariables(in: &settings, snapshot: &snapshot)
        }

        if enhancements.skipsClaudeCodeOnboarding {
            if settings["claudeCode.hideOnboarding"] as? Bool != true {
                settings["claudeCode.hideOnboarding"] = true
            }
            snapshot?.managesOnboarding = true
        } else if snapshot?.managesOnboarding == true {
            if let original = snapshot?.hideOnboarding {
                settings["claudeCode.hideOnboarding"] = original
            } else {
                settings.removeValue(forKey: "claudeCode.hideOnboarding")
            }
            snapshot?.managesOnboarding = false
        }

        if snapshot?.managedEnvironmentVariableNames.isEmpty == true,
           snapshot?.managesOnboarding == false {
            snapshot = nil
        }
        updated.claudeCodeVSCodeSettingsSnapshot = snapshot
        try save(settings)
        return updated
    }

    private func loadSettings() throws -> [String: Any] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard !data.isEmpty else { return [:] }
        guard let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeCodeVSCodeSettingsError.invalidSettings
        }
        return settings
    }

    private func save(_ settings: [String: Any]) throws {
        let manager = FileManager.default
        let parent = settingsURL.deletingLastPathComponent()
        if !manager.fileExists(atPath: parent.path) {
            try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    private func environmentVariables(in settings: [String: Any]) -> [String: String]? {
        guard let raw = settings["claudeCode.environmentVariables"] else { return nil }
        guard let values = raw as? [[String: Any]] else { return nil }
        var result: [String: String] = [:]
        for value in values {
            guard let name = value["name"] as? String,
                  let content = value["value"] as? String,
                  !name.isEmpty else {
                continue
            }
            result[name] = content
        }
        return result
    }

    private func setEnvironmentVariables(_ values: [String: String], in settings: inout [String: Any]) {
        settings["claudeCode.environmentVariables"] = values.keys.sorted().map {
            ["name": $0, "value": values[$0] ?? ""]
        }
    }

    private func restoreManagedEnvironmentVariables(
        in settings: inout [String: Any],
        snapshot: inout ClaudeCodeVSCodeSettingsSnapshot?
    ) {
        guard let currentSnapshot = snapshot,
              !currentSnapshot.managedEnvironmentVariableNames.isEmpty else {
            return
        }
        var current = environmentVariables(in: settings) ?? [:]
        for name in currentSnapshot.managedEnvironmentVariableNames {
            if let original = currentSnapshot.environmentVariables?[name] {
                current[name] = original
            } else {
                current.removeValue(forKey: name)
            }
        }
        if current.isEmpty, currentSnapshot.environmentVariables == nil {
            settings.removeValue(forKey: "claudeCode.environmentVariables")
        } else {
            setEnvironmentVariables(current, in: &settings)
        }
        snapshot?.managedEnvironmentVariableNames = []
    }

    private func providerEnvironment(from configuration: Data?) -> [String: String] {
        guard let configuration,
              let root = try? JSONSerialization.jsonObject(with: configuration) as? [String: Any] else {
            return [:]
        }
        let candidates = ["env", "environment", "environmentVariables"]
        var values: [String: String] = [:]
        for key in candidates {
            if let dictionary = root[key] as? [String: String] {
                values.merge(dictionary, uniquingKeysWith: { _, new in new })
            } else if let array = root[key] as? [[String: Any]] {
                for item in array {
                    if let name = item["name"] as? String, let value = item["value"] as? String {
                        values[name] = value
                    }
                }
            }
        }
        return values.filter { name, _ in
            name.hasPrefix("ANTHROPIC_") && !isSensitiveEnvironmentVariable(name)
        }
    }

    private func isSensitiveEnvironmentVariable(_ name: String) -> Bool {
        let uppercased = name.uppercased()
        return uppercased.contains("KEY")
            || uppercased.contains("TOKEN")
            || uppercased.contains("SECRET")
            || uppercased.contains("PASSWORD")
    }
}

/// Imports local Codex transcripts into Zisla without mutating any file under ~/.codex.
public struct CodexSessionHistoryImporter: Sendable {
    public let sessionsDirectory: URL
    public let sessionIndexURL: URL
    public let maxRolloutFiles: Int

    public init(
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        sessionIndexURL: URL? = nil,
        maxRolloutFiles: Int = 1_000
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.sessionIndexURL = sessionIndexURL
            ?? sessionsDirectory.deletingLastPathComponent().appendingPathComponent("session_index.jsonl")
        self.maxRolloutFiles = max(1, maxRolloutFiles)
    }

    public func importThreads() -> [AgentChatThread] {
        let titlesBySessionID = sessionTitlesByID()
        return rolloutURLs().compactMap { url in
            importThread(from: url, titlesBySessionID: titlesBySessionID)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func rolloutURLs() -> [URL] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: sessionsDirectory.path),
              let enumerator = manager.enumerator(
                at: sessionsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        var candidates: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"),
                  url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true else {
                continue
            }
            candidates.append((url, values.contentModificationDate ?? .distantPast))
        }
        return candidates
            .sorted { lhs, rhs in
                lhs.modifiedAt == rhs.modifiedAt ? lhs.url.path < rhs.url.path : lhs.modifiedAt > rhs.modifiedAt
            }
            .prefix(maxRolloutFiles)
            .map(\.url)
    }

    private func importThread(from url: URL, titlesBySessionID: [String: String]) -> AgentChatThread? {
        guard let data = try? Data(contentsOf: url),
              let body = String(data: data, encoding: .utf8) else {
            return nil
        }
        var sessionID: String?
        var messages: [AgentChatMessage] = []
        var firstTimestamp: Date?
        var lastTimestamp: Date?

        for line in body.split(whereSeparator: \.isNewline) {
            guard let root = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = root["type"] as? String,
                  let payload = root["payload"] as? [String: Any] else {
                continue
            }
            let timestamp = date(from: root["timestamp"])
            if let timestamp {
                firstTimestamp = min(firstTimestamp ?? timestamp, timestamp)
                lastTimestamp = max(lastTimestamp ?? timestamp, timestamp)
            }
            if type == "session_meta" {
                sessionID = payload["id"] as? String
                continue
            }
            if type == "event_msg", payload["type"] as? String == "user_message" {
                append(
                    role: .user,
                    content: text(from: payload["message"]) ?? text(from: payload["text_elements"]) ?? "",
                    timestamp: timestamp,
                    to: &messages
                )
            } else if type == "response_item", payload["type"] as? String == "message" {
                let role = (payload["role"] as? String).flatMap(AgentChatRole.init(rawValue:))
                if role == .user || role == .assistant {
                    append(
                        role: role ?? .assistant,
                        content: text(from: payload["content"]) ?? "",
                        timestamp: timestamp,
                        to: &messages
                    )
                }
            }
        }

        guard let sessionID, !sessionID.isEmpty, !messages.isEmpty else { return nil }
        let title = titlesBySessionID[sessionID]
            ?? messages.first(where: { $0.role == .user })?.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(40)
                .description
            ?? "Codex"
        return AgentChatThread(
            title: title.isEmpty ? "Codex" : title,
            cliKind: .codex,
            externalHistoryID: "codex:\(sessionID)",
            messages: messages,
            createdAt: firstTimestamp ?? messages.first?.createdAt ?? Date(),
            updatedAt: lastTimestamp ?? messages.last?.createdAt ?? Date()
        )
    }

    private func sessionTitlesByID() -> [String: String] {
        guard let data = try? Data(contentsOf: sessionIndexURL),
              let body = String(data: data, encoding: .utf8) else {
            return [:]
        }
        var titles: [String: String] = [:]
        for line in body.split(whereSeparator: \.isNewline) {
            guard let root = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = root["id"] as? String,
                  let title = root["thread_name"] as? String else {
                continue
            }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { titles[id] = trimmed }
        }
        return titles
    }

    private func append(
        role: AgentChatRole,
        content: String,
        timestamp: Date?,
        to messages: inout [AgentChatMessage]
    ) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let previous = messages.last, previous.role == role, previous.content == trimmed {
            return
        }
        messages.append(AgentChatMessage(role: role, content: trimmed, createdAt: timestamp ?? Date()))
    }

    private func text(from value: Any?) -> String? {
        if let value = value as? String { return value }
        if let values = value as? [Any] {
            let text = values.compactMap { item -> String? in
                if let value = item as? String { return value }
                if let dictionary = item as? [String: Any] { return dictionary["text"] as? String }
                return nil
            }.joined()
            return text.isEmpty ? nil : text
        }
        if let dictionary = value as? [String: Any] { return dictionary["text"] as? String }
        return nil
    }

    private func date(from value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
