import Foundation
import SQLite3
import ZislaCore

/// A complete retained-session inventory is required before treating a workspace as orphaned.
struct AISessionWorkspaceCleanup: Sendable {
    struct Root: Sendable {
        var url: URL
        var provider: AIProvider
    }

    private struct Session: Sendable {
        var provider: AIProvider
        var id: String
        var directory: String?
        var days: Set<String>
    }

    private enum InventoryError: Error {
        case unavailable
    }

    let roots: [Root]
    private let documentsRoot: URL
    private let workspaceDiscoveryFailed: Bool
    private let storageRoots: [URL]
    private var sessions: [Session] = []
    private var verifiedProviders: Set<AIProvider> = []
    private let referenceDate: Date
    private let fileManager: any SystemMonitorFileManaging
    private let environment: [String: String]
    private static let metadataByteLimit = 256 * 1024
    private static let maximumInventoryFiles = 20_000

    init(
        fileManager: any SystemMonitorFileManaging,
        referenceDate: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        checking urls: [URL]? = nil
    ) {
        self.fileManager = fileManager
        self.referenceDate = referenceDate
        self.environment = environment.filter { ["CODEX_HOME", "QWEN_HOME"].contains($0.key) }
        let home = fileManager.homeDirectoryForCurrentUser()
        storageRoots = [
            ".codex", ".claude/projects", ".gemini/tmp", ".grok/sessions", ".kimi-code/sessions", ".qwen/projects",
            ".copilot/session-state", ".pi/agent/sessions", ".zcode/cli/db/db.sqlite", ".zcode/v2/tasks-index.sqlite",
            ".workbuddy/workbuddy.db", ".workbuddy-ai/workbuddy.db", ".local/share/opencode", ".local/share/muse/sessions",
            "Library/Caches/com.google.GeminiMacOS/Gemini", "Library/Application Support/Delta",
            "Library/Application Support/Zed/threads",
            "Library/Application Support/Code/User/workspaceStorage", "Library/Application Support/Code - Insiders/User/workspaceStorage",
            "Library/Application Support/VSCodium/User/workspaceStorage", "Library/Application Support/Cursor/User/globalStorage/state.vscdb",
            "Library/Application Support/Cursor/User/workspaceStorage",
            "Library/Application Support/Windsurf/User/workspaceStorage",
        ].map { home.appendingPathComponent($0, isDirectory: true) }
            + ["CODEX_HOME", "QWEN_HOME"]
                .compactMap { key in environment[key].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil } }
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Documents", isDirectory: true)
        documentsRoot = documents
        let discoveredChildren = try? fileManager.contentsOfDirectory(at: documents, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        workspaceDiscoveryFailed = discoveredChildren == nil
        let children = discoveredChildren ?? []
        roots = children.compactMap { child in
            guard let provider = Self.provider(forDirectoryName: child.lastPathComponent),
                  child.deletingLastPathComponent().standardizedFileURL.path == documents.standardizedFileURL.path,
                  SystemMonitorPathSafety.isURL(child, withinAllowedRoots: [home]) else { return nil }
            return Root(url: child.standardizedFileURL, provider: provider)
        }
        guard !roots.isEmpty else { return }
        if let urls, !urls.contains(where: overlapsWorkspaceRoot) { return }

        for provider in AIProvider.allCases {
            var inventory: [Session] = []
            do {
                if try retainedSessions(for: provider, home: home, into: &inventory) {
                    verifiedProviders.insert(provider)
                }
            } catch {
                // An incomplete inventory cannot establish deletion for this provider.
            }
            sessions.append(contentsOf: inventory)
        }
    }

    static func provider(forDirectoryName name: String) -> AIProvider? {
        switch name.lowercased() {
        case "claude code": .claude
        case "deepseek", "deepseek harness", "dsh": .harness
        default: AIProvider(token: name) ?? AIProvider.allCases.first {
            AIMascotLibrary.providerDisplayName(for: $0).caseInsensitiveCompare(name) == .orderedSame
        }
        }
    }

    func candidates() -> [DiskCleanupCandidate] {
        roots.flatMap { root -> [DiskCleanupCandidate] in
            guard let children = try? fileManager.contentsOfDirectory(
                      at: root.url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []
                  ) else { return [] }
            return children.compactMap { child in
                guard child.deletingLastPathComponent().standardizedFileURL.path == root.url.path,
                      Self.workspaceDay(child.lastPathComponent) != nil || UUID(uuidString: child.lastPathComponent) != nil,
                      !isSymbolicLink(root.url), !isSymbolicLink(child), isDirectory(child) else { return nil }
                guard canTrashWorkspace(child, in: root) else { return nil }
                return DiskCleanupCandidate(
                    url: child.standardizedFileURL,
                    kind: .aiSessionWorkspace,
                    byteSize: SystemDiskCleanup.allocatedByteSize(of: child, fileManager: fileManager),
                    displayName: root.url.lastPathComponent + "/" + child.lastPathComponent,
                    detail: AppLocalization.text("对应会话已删除；清理前请确认目录中的文件"),
                    safetyLevel: .requiresManualReview,
                    source: root.url.lastPathComponent
                )
            }
        }
    }

    func overlapsWorkspaceRoot(_ url: URL) -> Bool {
        if workspaceDiscoveryFailed,
           SystemMonitorPathSafety.isURL(url, withinAllowedRoots: [documentsRoot])
            || SystemMonitorPathSafety.isURL(documentsRoot, withinAllowedRoots: [url]) { return true }
        return roots.contains {
            SystemMonitorPathSafety.isURL(url, withinAllowedRoots: [$0.url])
                || SystemMonitorPathSafety.isURL($0.url, withinAllowedRoots: [url])
        }
    }

    func canTrash(_ url: URL, wholeWorkspaceOnly: Bool = false) -> Bool {
        if workspaceDiscoveryFailed, overlapsWorkspaceRoot(url) { return false }
        guard !overlapsSessionStorage(url) else { return false }
        for root in roots {
            if SystemMonitorPathSafety.isURL(root.url, withinAllowedRoots: [url]) { return false }
            guard SystemMonitorPathSafety.isURL(url, withinAllowedRoots: [root.url]) else { continue }
            let components = SystemMonitorPathSafety.standardizedPath(url)
                .dropFirst(SystemMonitorPathSafety.standardizedPath(root.url).count + 1).split(separator: "/")
            guard let first = components.first, !wholeWorkspaceOnly || components.count == 1 else { return false }
            let workspace = root.url.appendingPathComponent(String(first), isDirectory: true)
            return canTrashWorkspace(workspace, in: root)
        }
        return !wholeWorkspaceOnly
    }

    func filterCandidates(_ candidates: [DiskCleanupCandidate]) -> [DiskCleanupCandidate] {
        candidates.filter {
            !overlapsSessionStorage($0.url)
                && ($0.kind == .aiSessionWorkspace || !overlapsWorkspaceRoot($0.url))
        }
    }

    private func overlapsSessionStorage(_ url: URL) -> Bool {
        storageRoots.contains {
            SystemMonitorPathSafety.isURL(url, withinAllowedRoots: [$0])
                || SystemMonitorPathSafety.isURL($0, withinAllowedRoots: [url])
        }
    }

    private func canTrashWorkspace(_ url: URL, in root: Root) -> Bool {
        guard verifiedProviders.contains(root.provider),
              url.standardizedFileURL.deletingLastPathComponent().path == root.url.path,
              !isSymbolicLink(root.url), !isSymbolicLink(url),
              SystemMonitorPathSafety.isURL(url, withinAllowedRoots: [root.url]),
              isDirectory(url) else { return false }
        let day = Self.workspaceDay(url.lastPathComponent)
        let isSessionID = UUID(uuidString: url.lastPathComponent) != nil
        guard day != nil || isSessionID else { return false }
        if let day, day >= Self.day(referenceDate, timeZone: .current) { return false }
        if isSessionID {
            guard let created = try? fileManager.attributesOfItem(atPath: url.path)[.creationDate] as? Date,
                  Self.day(created, timeZone: .current) < Self.day(referenceDate, timeZone: .current) else { return false }
        }

        return !sessions.contains { session in
            if let directory = session.directory {
                let sessionURL = URL(fileURLWithPath: directory)
                if SystemMonitorPathSafety.isURL(sessionURL, withinAllowedRoots: [url]) { return true }
            }
            guard session.provider == root.provider else { return false }
            if let day, session.days.contains(day) { return true }
            return session.id.lowercased() == url.lastPathComponent.lowercased()
        }
    }

    static func workspaceDay(_ name: String) -> String? {
        let value: String
        if name.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            value = name
        } else if name.range(of: #"^temp_\d{8}_\d+$"#, options: .regularExpression) != nil {
            let compact = Array(name.dropFirst(5).prefix(8))
            value = String(compact[0..<4]) + "-" + String(compact[4..<6]) + "-" + String(compact[6..<8])
        } else { return nil }
        guard let date = try? Date.ISO8601FormatStyle().parse(value + "T00:00:00Z"),
              day(date, timeZone: .gmt) == value else { return nil }
        return value
    }

    private static func day(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    private func session(provider: AIProvider, id: String, directory: String?, timestamp: Any?, milliseconds: Bool = false) throws -> Session {
        // Some tools persist sessions without a workspace as an empty cwd.
        let directory = directory.flatMap { $0.isEmpty ? nil : $0 }
        if let directory, !directory.hasPrefix("/") { throw InventoryError.unavailable }
        let date: Date?
        if let number = timestamp as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
           number.doubleValue > 0, number.doubleValue <= (milliseconds ? 253_402_300_799_999 : 253_402_300_799) {
            date = Date(timeIntervalSince1970: number.doubleValue / (milliseconds ? 1000 : 1))
        } else if let text = timestamp as? String,
                  let parsed = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
                    ?? (try? Date.ISO8601FormatStyle().parse(text)) {
            date = parsed
        } else { date = nil }
        return Session(provider: provider, id: id, directory: directory.map {
            SystemMonitorPathSafety.standardizedPath(URL(fileURLWithPath: $0))
        }, days: date.map { [Self.day($0, timeZone: .current), Self.day($0, timeZone: .gmt)] } ?? [])
    }

    private func retainedSessions(for provider: AIProvider, home: URL, into result: inout [Session]) throws -> Bool {
        var available = false
        var complete = true
        func directory(_ path: String, override: String? = nil) -> URL {
            if let override, let value = environment[override], value.hasPrefix("/") {
                return URL(fileURLWithPath: value, isDirectory: true)
            }
            return home.appendingPathComponent(path, isDirectory: true)
        }
        func logs(_ root: URL, matching: (URL) -> Bool) {
            guard fileManager.fileExists(atPath: root.path) else { return }
            available = true
            do {
                for file in try inventoryFiles(at: root, matching: matching) {
                    do {
                        result.append(try metadataSession(at: file, provider: provider))
                    } catch {
                        // Other valid records still protect workspaces shared with another tool.
                        complete = false
                    }
                }
            } catch {
                complete = false
            }
        }
        func database(_ url: URL, sql: String, milliseconds: Bool = true) {
            guard fileManager.fileExists(atPath: url.path) else { return }
            available = true
            do {
                for row in try databaseRows(at: url, sql: sql) {
                    do {
                        result.append(try session(provider: provider, id: row["id"] as? String ?? "", directory: row["cwd"] as? String, timestamp: row["created"], milliseconds: milliseconds))
                    } catch {
                        complete = false
                    }
                }
            } catch {
                complete = false
            }
        }

        switch provider {
        case .codex:
            let root = directory(".codex", override: "CODEX_HOME")
            if fileManager.fileExists(atPath: root.path) {
                for file in try children(root) where file.lastPathComponent.range(of: #"^state_\d+\.sqlite$"#, options: .regularExpression) != nil {
                    database(file, sql: "SELECT id, cwd, created_at AS created FROM threads", milliseconds: false)
                }
            }
            if available { break }
            for folder in ["sessions", "archived_sessions"] {
                logs(root.appendingPathComponent(folder)) { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
                // Cold rollouts still represent retained sessions; do not infer deletion from compression.
                if fileManager.fileExists(atPath: root.appendingPathComponent(folder).path),
                   !(try inventoryFiles(at: root.appendingPathComponent(folder), matching: { $0.lastPathComponent.hasSuffix(".jsonl.zst") })).isEmpty {
                    complete = false
                }
            }
        case .claude:
            logs(directory(".claude/projects")) { $0.pathExtension == "jsonl" }
        case .gemini:
            logs(directory(".gemini/tmp")) {
                $0.lastPathComponent.hasPrefix("session-") && ["json", "jsonl"].contains($0.pathExtension)
            }
            let root = home.appendingPathComponent("Library/Caches/com.google.GeminiMacOS/Gemini")
            for file in try inventoryFiles(at: root, matching: { $0.lastPathComponent.hasPrefix("ChatInfo") && $0.pathExtension == "store" }) {
                database(file, sql: "SELECT ZCHATUUID AS id, MIN(ZCREATEDTIME) + 978307200 AS created FROM ZCHATMESSAGESTOREDMODEL GROUP BY ZCHATUUID", milliseconds: false)
            }
        case .grok:
            let root = directory(".grok/sessions")
            logs(root) { $0.lastPathComponent == "summary.json" }
            let events = try inventoryFiles(at: root, matching: { $0.lastPathComponent == "events.jsonl" })
            if events.contains(where: { !fileManager.fileExists(atPath: $0.deletingLastPathComponent().appendingPathComponent("summary.json").path) }) {
                throw InventoryError.unavailable
            }
        case .copilot:
            let root = directory(".copilot").appendingPathComponent("session-state")
            if fileManager.fileExists(atPath: root.path) { available = true }
            do {
                let events = try inventoryFiles(at: root, matching: { $0.lastPathComponent == "events.jsonl" })
                if events.contains(where: { !fileManager.fileExists(atPath: $0.deletingLastPathComponent().appendingPathComponent("workspace.yaml").path) }) {
                    complete = false
                }
            } catch {
                complete = false
            }
            do {
                for file in try inventoryFiles(at: root, matching: { $0.lastPathComponent == "workspace.yaml" }) {
                    do {
                        guard let data = fileManager.readPrefix(at: file, maximumBytes: Self.metadataByteLimit),
                              let text = String(data: data, encoding: .utf8) else { throw InventoryError.unavailable }
                        var values: [String: String] = [:]
                        for line in text.split(whereSeparator: \.isNewline) {
                            guard let separator = line.firstIndex(of: ":") else { continue }
                            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            values[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        }
                        guard let cwd = values["cwd"] else { throw InventoryError.unavailable }
                        result.append(try session(provider: provider, id: values["id"] ?? "", directory: cwd, timestamp: values["created_at"]))
                    } catch {
                        complete = false
                    }
                }
            } catch {
                complete = false
            }
            for host in ["Code", "Code - Insiders", "VSCodium", "Cursor", "Windsurf"] {
                logs(home.appendingPathComponent("Library/Application Support/\(host)/User/workspaceStorage")) {
                    $0.deletingLastPathComponent().lastPathComponent == "chatSessions" && ["json", "jsonl"].contains($0.pathExtension)
                }
            }
        case .kimi:
            // The retained-state file has no reliable creation date or working directory.
            break
        case .qwen:
            logs(directory(".qwen", override: "QWEN_HOME").appendingPathComponent("projects")) { $0.pathExtension == "jsonl" }
        case .coder:
            for root in try children(home) where root.lastPathComponent.lowercased().hasPrefix(".qoder") {
                let projects = root.appendingPathComponent("projects")
                if fileManager.fileExists(atPath: projects.path) {
                    logs(projects) { $0.pathExtension == "jsonl" }
                } else {
                    // Activity segments may be rotated while their conversations remain retained.
                    complete = false
                }
            }
        case .zcode:
            database(ZCodeSessionActivityDetector.defaultDatabaseURL(home: home), sql: "SELECT id, directory AS cwd, time_created AS created FROM session")
            database(home.appendingPathComponent(".zcode/v2/tasks-index.sqlite"), sql: "SELECT task_id AS id, workspace_path AS cwd, created_at AS created FROM tasks WHERE deleted = 0")
        case .zed:
            database(ZedSessionActivityDetector.defaultDatabaseURL(home: home), sql: "SELECT id, created_at AS created FROM threads", milliseconds: false)
        case .opencode:
            let root = directory(".local/share/opencode")
            database(root.appendingPathComponent("opencode.db"), sql: "SELECT id, directory AS cwd, time_created AS created FROM session")
            logs(root.appendingPathComponent("storage/session")) { $0.pathExtension == "json" }
        case .pi:
            logs(directory(".pi/agent/sessions")) { $0.pathExtension == "jsonl" }
        case .delta:
            let root = DeltaSessionActivityDetector.defaultDataRoot(home: home)
            database(root.appendingPathComponent("data.sqlite"), sql: "SELECT id, created_at AS created FROM app_threads")
            for account in try children(root) where account.lastPathComponent.hasPrefix("user_") {
                database(account.appendingPathComponent("data.sqlite"), sql: "SELECT id, created_at AS created FROM app_threads")
            }
        case .workbuddy, .workbuddyAI:
            let url = provider == .workbuddy
                ? WorkBuddySessionActivityDetector.defaultDatabaseURL(home: home)
                : WorkBuddyAISessionActivityDetector.defaultDatabaseURL(home: home)
            database(url, sql: "SELECT id, cwd, created_at AS created FROM sessions WHERE deleted_at IS NULL")
        case .cursor:
            let root = CursorSessionActivityDetector.defaultUserDirectory(home: home)
            var databases = [root.appendingPathComponent("globalStorage/state.vscdb")]
            do {
                databases += try children(root.appendingPathComponent("workspaceStorage")).map { $0.appendingPathComponent("state.vscdb") }
            } catch {
                complete = false
            }
            for url in databases where fileManager.fileExists(atPath: url.path) {
                available = true
                do {
                    let tables = try databaseRows(at: url, sql: "SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0["name"] as? String }
                    let supported = ["cursorDiskKV", "composerHeaders", "ItemTable"].filter { tables.contains($0) }
                    guard !supported.isEmpty else { throw InventoryError.unavailable }
                    for table in supported {
                        let source: String
                        if table == "ItemTable" {
                            source = "ItemTable i, json_each(CASE WHEN json_type(i.value) = 'array' THEN i.value ELSE json_extract(i.value, '$.allComposers') END) c WHERE i.key IN ('composer.composerData', 'allComposers')"
                        } else {
                            source = "\(table) c" + (table == "cursorDiskKV" ? " WHERE key LIKE 'composerData:%'" : "")
                        }
                        database(url, sql: "SELECT json_extract(c.value, '$.composerId') AS id, json_extract(c.value, '$.createdAt') AS created, json_extract(c.value, '$.cwd') AS cwd FROM \(source)")
                    }
                } catch {
                    complete = false
                }
            }
        case .harness, .trae, .orca, .gpt, .doubao, .grokBot, .muse:
            // Activity logs and opaque or remote stores cannot establish permanent deletion.
            break
        }
        return available && complete && result.allSatisfy { !$0.id.isEmpty && !$0.days.isEmpty }
    }

    private func metadataSession(at url: URL, provider: AIProvider) throws -> Session {
        guard let data = fileManager.readPrefix(at: url, maximumBytes: Self.metadataByteLimit), !data.isEmpty else { throw InventoryError.unavailable }
        if provider == .copilot {
            let metadataData = url.pathExtension == "jsonl" ? Data(data.prefix { $0 != 0x0A }) : data
            guard let object = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] else { throw InventoryError.unavailable }
            let metadata = object["v"] as? [String: Any] ?? object["data"] as? [String: Any] ?? object
            let workspaceFile = url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("workspace.json")
            var cwd: String?
            if fileManager.fileExists(atPath: workspaceFile.path) {
                guard let bytes = fileManager.readPrefix(at: workspaceFile, maximumBytes: Self.metadataByteLimit),
                      let workspace = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw InventoryError.unavailable }
                if let folder = workspace["folder"] as? String, let folderURL = URL(string: folder), folderURL.isFileURL {
                    cwd = folderURL.path
                }
            }
            return try session(provider: provider, id: metadata["sessionId"] as? String ?? "", directory: cwd, timestamp: metadata["creationDate"] ?? metadata["startTime"], milliseconds: true)
        }
        if url.pathExtension == "json" {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw InventoryError.unavailable }
            let time = object["time"] as? [String: Any]
            let info = object["info"] as? [String: Any]
            let id = object["sessionId"] as? String ?? object["id"] as? String ?? info?["id"] as? String ?? url.deletingLastPathComponent().lastPathComponent
            return try session(
                provider: provider, id: id,
                directory: object["cwd"] as? String ?? object["directory"] as? String ?? info?["cwd"] as? String,
                timestamp: object["created_at"] ?? object["createdAt"] ?? object["startTime"] ?? time?["created"],
                milliseconds: provider == .opencode
            )
        }
        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { throw InventoryError.unavailable }
            let type = object["type"] as? String
            let metadata = type == "session_meta" ? object["payload"] as? [String: Any] : object
            guard let metadata else { throw InventoryError.unavailable }
            let cwd = metadata["cwd"] as? String
            guard cwd != nil || provider == .gemini || provider == .qwen else { continue }
            let id = metadata["id"] as? String ?? metadata["sessionId"] as? String
                ?? metadata["session_id"] as? String ?? url.deletingPathExtension().lastPathComponent
            return try session(provider: provider, id: id, directory: cwd, timestamp: metadata["startTime"] ?? metadata["timestamp"] ?? object["timestamp"])
        }
        throw InventoryError.unavailable
    }

    private func children(_ root: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        try rejectSymbolicLinkParents(root)
        let children = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
        return children
    }

    private func inventoryFiles(at root: URL, matching: (URL) -> Bool) throws -> [URL] {
        var result: [URL] = []
        var remaining = Self.maximumInventoryFiles
        func visit(_ directory: URL, depth: Int) throws {
            for child in try children(directory) {
                remaining -= 1
                guard remaining >= 0,
                      child.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path else { throw InventoryError.unavailable }
                guard let type = try fileManager.attributesOfItem(atPath: child.path)[.type] as? FileAttributeType,
                      type != .typeSymbolicLink else { throw InventoryError.unavailable }
                if type == .typeDirectory {
                    guard depth > 0 else { throw InventoryError.unavailable }
                    try visit(child, depth: depth - 1)
                } else if matching(child) { result.append(child) }
            }
        }
        try visit(root, depth: 8)
        return result
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeDirectory
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
            || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func rejectSymbolicLinkParents(_ url: URL) throws {
        var component = url
        let homePath = fileManager.homeDirectoryForCurrentUser().standardizedFileURL.path
        while component.path != homePath && component.path != "/" {
            if ["/var", "/tmp"].contains(component.path),
               component.resolvingSymlinksInPath().path == "/private" + component.path { break }
            guard !isSymbolicLink(component) else { throw InventoryError.unavailable }
            component = component.deletingLastPathComponent()
        }
    }

    private func databaseRows(at url: URL, sql: String) throws -> [[String: Any]] {
        try rejectSymbolicLinkParents(url)
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let database else {
            sqlite3_close(database)
            throw InventoryError.unavailable
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw InventoryError.unavailable
        }
        defer { sqlite3_finalize(statement) }
        var rows: [[String: Any]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_DONE: return rows
            case SQLITE_ROW:
                guard rows.count < Self.maximumInventoryFiles else { throw InventoryError.unavailable }
                var row: [String: Any] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    let key = String(cString: sqlite3_column_name(statement, index))
                    switch sqlite3_column_type(statement, index) {
                    case SQLITE_INTEGER: row[key] = sqlite3_column_int64(statement, index)
                    case SQLITE_FLOAT: row[key] = sqlite3_column_double(statement, index)
                    case SQLITE_TEXT:
                        if let text = sqlite3_column_text(statement, index) { row[key] = String(cString: text) }
                    default: break
                    }
                }
                rows.append(row)
            default: throw InventoryError.unavailable
            }
        }
    }
}
