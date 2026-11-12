import Foundation

struct BrowserDownloadFileNameResolver: Sendable {
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var temporaryDirectory: URL = FileManager.default.temporaryDirectory

    func fileNames(for downloads: [URL: BrowserDownloadAgent]) -> [URL: String] {
        let temporaryDownloads = downloads.filter {
            $0.key.isFileURL && [.crdownload, .opdownload].contains(
                BrowserDownloadTempExtension(rawValue: $0.key.pathExtension.lowercased())
            )
        }
        let support = homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        var matches: [String: Set<String>] = [:]
        for agent in Set(temporaryDownloads.values) {
            let paths = temporaryDownloads.filter { $0.value == agent }.keys
            let quotedPaths = paths.map { "'\($0.path.replacingOccurrences(of: "'", with: "''"))'" }
            for rootPath in Self.profileRoots(for: agent) {
                let root = support.appendingPathComponent(rootPath, isDirectory: true)
                let profiles = (try? FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                )) ?? []
                for databaseURL in ([root] + profiles).map({ $0.appendingPathComponent("History") }) {
                    let rows = (try? downloadRows(at: databaseURL, sql: """
                        SELECT current_path, target_path FROM downloads
                        WHERE state = 0 AND current_path IN (\(quotedPaths.joined(separator: ",")))
                        """)) ?? []
                    for row in rows {
                        guard let currentPath = row["current_path"] as? String,
                            let targetPath = row["target_path"] as? String,
                            targetPath.hasPrefix("/"), targetPath != "/"
                        else { continue }
                        let target = URL(fileURLWithPath: targetPath)
                        guard BrowserDownloadTempExtension(rawValue: target.pathExtension.lowercased()) == nil
                        else { continue }
                        matches[currentPath, default: []].insert(target.lastPathComponent)
                    }
                }
            }
        }
        return temporaryDownloads.reduce(into: [URL: String]()) {
            if let names = matches[$1.key.path], names.count == 1 { $0[$1.key] = names.first }
        }
    }

    private func downloadRows(at source: URL, sql: String) throws -> [[String: Any]] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return [] }
        // Chromium keeps exclusive SQLite locks while running; query an isolated copy, including committed WAL pages.
        let temporary = temporaryDirectory.appendingPathComponent("zisla-download-name-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fileManager.removeItem(at: temporary) }
        let destination = temporary.appendingPathComponent("History")
        try fileManager.copyItem(at: source, to: destination)
        let wal = URL(fileURLWithPath: source.path + "-wal")
        if fileManager.fileExists(atPath: wal.path) {
            try fileManager.copyItem(at: wal, to: URL(fileURLWithPath: destination.path + "-wal"))
        }
        return DesktopAIStorage.rows(at: destination, sql: sql)
    }

    private static func profileRoots(for agent: BrowserDownloadAgent) -> [String] {
        switch agent {
        case .chrome: ["Google/Chrome", "Google/Chrome Beta", "Google/Chrome Canary"]
        case .edge: ["Microsoft Edge", "Microsoft Edge Beta"]
        case .brave: ["BraveSoftware/Brave-Browser", "BraveSoftware/Brave-Browser-Beta"]
        case .arc: ["Arc/User Data"]
        case .vivaldi: ["Vivaldi"]
        case .opera: ["com.operasoftware.Opera", "com.operasoftware.OperaGX"]
        default: []
        }
    }
}
