import Foundation

struct AIAgentArtifactCleanup: Sendable {
    private let fileManager: any SystemMonitorFileManaging
    private let referenceDate: Date
    private let home: URL
    private let roots: [URL]
    static let backupMinAge: TimeInterval = 7 * 86400
    private static let maximumEntries = 20_000
    private static let maximumDepth = 16

    init(fileManager: any SystemMonitorFileManaging, referenceDate: Date = Date()) {
        self.fileManager = fileManager
        self.referenceDate = referenceDate
        home = fileManager.homeDirectoryForCurrentUser().standardizedFileURL
        roots = [
            ".gemini", ".claude", ".codex", ".grok", ".qwen", ".kimi-code", ".pi/agent", ".copilot",
            ".qoder", ".qoderwork", ".qoderworkcn", ".qoderwake", ".zcode", ".workbuddy", ".workbuddy-ai",
            ".trae", ".harnext", ".dsh", ".local/share/opencode", ".local/share/muse",
        ].map { fileManager.homeDirectoryForCurrentUser().appendingPathComponent($0, isDirectory: true) }
    }

    func candidates() -> [DiskCleanupCandidate] {
        var result: [DiskCleanupCandidate] = []
        for root in roots {
            guard !Task.isCancelled else { break }
            let tasks = root.appendingPathComponent("tasks", isDirectory: true)
            if let taskDirectories = children(of: tasks) {
                for task in taskDirectories {
                    if isEmptyTask(task) {
                        result.append(candidate(task, source: root))
                    } else if let contents = children(of: task) {
                        for backup in contents where Self.isBackupName(backup.lastPathComponent)
                            && validItem(backup, under: root) && matchesBackup(backup, minimumAge: nil) {
                            result.append(candidate(backup, source: root))
                        }
                    }
                }
            }
            if let contents = children(of: root) {
                for backup in contents where Self.isBackupName(backup.lastPathComponent) && matchesBackup(backup) {
                    result.append(candidate(backup, source: root))
                }
            }
            if root.lastPathComponent == ".claude", let histories = children(of: root.appendingPathComponent("file-history")) {
                for history in histories where matchesBackup(history) {
                    result.append(candidate(history, source: root))
                }
            }
        }
        return result
    }

    /// A non-nil result owns the path and must override coarser cleanup categories.
    func canTrash(_ url: URL) -> Bool? {
        let path = url.standardizedFileURL
        for root in roots {
            // Use the lexical path for ownership so a symlink cannot escape verification.
            if root.path == path.path || root.path.hasPrefix(path.path + "/") { return false }
            guard path.path.hasPrefix(root.path + "/") else { continue }
            let components = path.pathComponents.dropFirst(root.pathComponents.count)
            if components.first == "tasks" {
                guard validItem(path, under: root), let taskName = components.dropFirst().first else { return false }
                let task = root.appendingPathComponent("tasks").appendingPathComponent(taskName)
                if components.count == 2 { return isEmptyTask(task) }
                return components.count == 3 && Self.isBackupName(path.lastPathComponent)
                    && matchesBackup(path, minimumAge: nil)
            }
            if root.lastPathComponent == ".claude", components.first == "file-history" {
                return components.count == 2 && UUID(uuidString: path.lastPathComponent) != nil
                    && validItem(path, under: root) && matchesBackup(path)
            }
            if let name = components.first, Self.isBackupName(name) {
                return components.count == 1 && validItem(path, under: root) && matchesBackup(path)
            }
        }
        return nil
    }

    private func candidate(_ url: URL, source: URL) -> DiskCleanupCandidate {
        let url = url.standardizedFileURL
        return DiskCleanupCandidate(
            url: url.standardizedFileURL,
            kind: .temporaryFiles,
            byteSize: SystemDiskCleanup.allocatedByteSize(of: url, fileManager: fileManager),
            displayName: String(url.path.dropFirst(home.path.count + 1)),
            detail: url.path,
            source: source.lastPathComponent
        )
    }

    static func isBackupName(_ name: String) -> Bool {
        let name = name.lowercased()
        return ["backup", "backups", ".backup", ".backups"].contains(name)
            || name.hasSuffix(".bak") || name.hasSuffix(".backup") || name.hasSuffix("-backup")
    }

    static func isBackupFile(_ url: URL, home: URL) -> Bool {
        url.standardizedFileURL.pathComponents.dropFirst(home.pathComponents.count).contains(where: isBackupName)
    }

    private func validItem(_ url: URL, under root: URL) -> Bool {
        guard SystemMonitorPathSafety.isURL(url, withinAllowedRoots: [root]) else { return false }
        var item = url.standardizedFileURL
        while item.path != home.path {
            guard let type = try? fileManager.attributesOfItem(atPath: item.path)[.type] as? FileAttributeType,
                  type == .typeDirectory || type == .typeRegular else { return false }
            item.deleteLastPathComponent()
        }
        return true
    }

    private func children(of url: URL) -> [URL]? {
        guard validItem(url, under: home),
              let children = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
        else { return nil }
        guard children.count <= Self.maximumEntries else { return nil }
        guard children.allSatisfy({ $0.standardizedFileURL.deletingLastPathComponent().path == url.standardizedFileURL.path }) else { return nil }
        return children
    }

    private func isEmptyTask(_ url: URL) -> Bool {
        var remaining = Self.maximumEntries
        return treeMatches(url, empty: true, minimumAge: nil, depth: 0, remaining: &remaining)
    }

    private func matchesBackup(_ url: URL, minimumAge: TimeInterval? = Self.backupMinAge) -> Bool {
        var remaining = Self.maximumEntries
        return treeMatches(url, empty: false, minimumAge: minimumAge, depth: 0, remaining: &remaining)
    }

    private func treeMatches(_ url: URL, empty: Bool, minimumAge: TimeInterval?, depth: Int, remaining: inout Int) -> Bool {
        guard !Task.isCancelled, depth < Self.maximumDepth, remaining > 0,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType else { return false }
        remaining -= 1
        if let minimumAge {
            guard let modified = attributes[.modificationDate] as? Date,
                  referenceDate.timeIntervalSince(modified) >= minimumAge else { return false }
        }
        if type == .typeRegular { return !empty || depth > 0 && url.lastPathComponent == ".DS_Store" }
        guard type == .typeDirectory, let contents = children(of: url) else { return false }
        return contents.allSatisfy { treeMatches($0, empty: empty, minimumAge: minimumAge, depth: depth + 1, remaining: &remaining) }
    }
}
