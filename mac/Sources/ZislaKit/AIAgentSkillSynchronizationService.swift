import Foundation
import ZislaCore

public enum AIAgentSkillSynchronizationMode: Sendable {
    case symbolicLink
    case fileCopy
}

public enum AIAgentSkillSynchronizationError: LocalizedError {
    case destinationIsNotManaged(String)

    public var errorDescription: String? {
        switch self {
        case let .destinationIsNotManaged(path):
            AppLocalization.text("目标目录不是由 Zisla 管理，已保留原内容：%@", path)
        }
    }
}

public struct AIAgentSkillSynchronizationService {
    private let fileManager: FileManager
    private let markerFileName = ".zisla-skill-sync"
    private let legacyManagedDirectoryName = "zisla-managed"

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func ensureManagedDirectory(at managedDirectory: URL) throws {
        try fileManager.createDirectory(
            at: managedDirectory,
            withIntermediateDirectories: true
        )
    }

    public func synchronize(
        managedDirectory: URL,
        to destination: URL,
        mode: AIAgentSkillSynchronizationMode,
        backupRoot: URL? = nil
    ) throws {
        try validateDirectories(managedDirectory: managedDirectory, destination: destination)
        try ensureManagedDirectory(at: managedDirectory)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let destinationExists = itemExists(at: destination)
        let destinationIsManaged = isManagedDestination(destination, managedDirectory: managedDirectory)
        if destinationExists, !destinationIsManaged, backupRoot == nil {
            throw AIAgentSkillSynchronizationError.destinationIsNotManaged(destination.path)
        }

        let staging = managedDirectory.deletingLastPathComponent()
            .appendingPathComponent(".zisla-skill-sync-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let previous = staging.appendingPathComponent("previous")
        defer {
            // Keep the original available if restoring it fails.
            if !itemExists(at: previous) {
                try? fileManager.removeItem(at: staging)
            }
        }
        let imports = staging.appendingPathComponent("imports", isDirectory: true)
        try fileManager.createDirectory(at: imports, withIntermediateDirectories: true)
        if destinationExists, !destinationIsManaged {
            // Resolve links while every original root is still in place.
            try importDirectoryContents(
                from: destination.resolvingSymlinksInPath(),
                into: imports,
                managedDirectory: managedDirectory
            )
        }
        let importedItems = try fileManager.contentsOfDirectory(at: imports, includingPropertiesForKeys: nil)
        let replacement = staging.appendingPathComponent("replacement")
        switch mode {
        case .symbolicLink:
            try fileManager.createSymbolicLink(at: replacement, withDestinationURL: managedDirectory)
        case .fileCopy:
            try copySnapshot(from: managedDirectory, to: replacement)
            for item in importedItems {
                try fileManager.copyItem(at: item, to: replacement.appendingPathComponent(item.lastPathComponent))
            }
            try Data(managedDirectory.path.utf8).write(
                to: replacement.appendingPathComponent(markerFileName),
                options: .atomic
            )
        }

        let backup: URL?
        if !destinationExists {
            backup = nil
        } else if !destinationIsManaged, let backupRoot {
            backup = try moveDestinationToBackup(destination, backupRoot: backupRoot)
        } else {
            backup = previous
            try fileManager.moveItem(at: destination, to: previous)
        }
        var installedItems: [URL] = []
        do {
            for item in importedItems {
                let managedItem = managedDirectory.appendingPathComponent(item.lastPathComponent)
                try fileManager.moveItem(at: item, to: managedItem)
                installedItems.append(managedItem)
            }
            try fileManager.moveItem(at: replacement, to: destination)
        } catch {
            if itemExists(at: destination) {
                try fileManager.removeItem(at: destination)
            }
            if let backup {
                try fileManager.moveItem(at: backup, to: destination)
            }
            for item in installedItems {
                try fileManager.removeItem(at: item)
            }
            throw error
        }
        if itemExists(at: previous) {
            try fileManager.removeItem(at: previous)
        }
    }

    public func disable(
        at destination: URL,
        managedDirectory: URL,
        backupRoot: URL? = nil
    ) throws {
        try validateDirectories(managedDirectory: managedDirectory, destination: destination)
        guard isManagedDestination(destination, managedDirectory: managedDirectory) else { return }
        if !isManagedLink(destination, managedDirectory: managedDirectory), let backupRoot {
            _ = try moveDestinationToBackup(destination, backupRoot: backupRoot)
        } else {
            try fileManager.removeItem(at: destination)
        }
    }

    private func isManagedDestination(
        _ destination: URL,
        managedDirectory: URL
    ) -> Bool {
        if (try? fileManager.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            return isManagedLink(destination, managedDirectory: managedDirectory)
        }
        return (try? String(
            contentsOf: destination.appendingPathComponent(markerFileName),
            encoding: .utf8
        )) == managedDirectory.path
    }

    private func moveDestinationToBackup(_ destination: URL, backupRoot: URL) throws -> URL {
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let owner = destination.deletingLastPathComponent().lastPathComponent
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let prefix = owner.isEmpty ? destination.lastPathComponent : "\(owner)-\(destination.lastPathComponent)"
        let backup = backupRoot.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try fileManager.moveItem(at: destination, to: backup)
        return backup
    }

    private func importDirectoryContents(from source: URL, into staging: URL, managedDirectory: URL) throws {
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            guard item.lastPathComponent != markerFileName else { continue }
            if item.lastPathComponent == legacyManagedDirectoryName {
                if isManagedLink(item, managedDirectory: managedDirectory) {
                    continue
                }
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    try importDirectoryContents(from: item, into: staging, managedDirectory: managedDirectory)
                    continue
                }
            }
            let managedItem = managedDirectory.appendingPathComponent(item.lastPathComponent)
            let stagedItem = staging.appendingPathComponent(item.lastPathComponent)
            guard !itemExists(at: managedItem), !itemExists(at: stagedItem) else { continue }
            try copySnapshot(from: item, to: stagedItem)
        }
    }

    private func copySnapshot(from source: URL, to destination: URL, ancestors: Set<URL> = []) throws {
        let resolvedSource = source.resolvingSymlinksInPath().standardizedFileURL
        let destinationPath = destination.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(destination.lastPathComponent)
        guard !ancestors.contains(resolvedSource),
              !destinationPath.pathComponents.starts(with: resolvedSource.pathComponents) else {
            throw POSIXError(.ELOOP, userInfo: [NSFilePathErrorKey: source.path])
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedSource.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: source.path])
        }
        try fileManager.copyItem(at: resolvedSource, to: destination)
        if isDirectory.boolValue {
            try materializeCopiedLinks(
                from: resolvedSource,
                to: destination,
                ancestors: ancestors.union([resolvedSource])
            )
        }
    }

    private func materializeCopiedLinks(from source: URL, to destination: URL, ancestors: Set<URL>) throws {
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey]) {
            let copiedItem = destination.appendingPathComponent(item.lastPathComponent)
            if (try? fileManager.destinationOfSymbolicLink(atPath: item.path)) != nil {
                try fileManager.removeItem(at: copiedItem)
                try copySnapshot(from: item, to: copiedItem, ancestors: ancestors)
            } else if try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                try materializeCopiedLinks(
                    from: item,
                    to: copiedItem,
                    ancestors: ancestors
                )
            }
        }
    }

    private func validateDirectories(managedDirectory: URL, destination: URL) throws {
        let managedPath = resolvedDirectory(managedDirectory)
        let destinationPath = resolvedDirectory(destination)
        let linkTarget = try? fileManager.destinationOfSymbolicLink(atPath: destination.path)
        let linksDirectlyToManaged = linkTarget.map {
            URL(fileURLWithPath: $0, relativeTo: destination.deletingLastPathComponent())
                .standardizedFileURL.path == managedDirectory.standardizedFileURL.path
        } ?? false
        guard managedDirectory.standardizedFileURL.path != destination.standardizedFileURL.path,
              (managedPath.path == destinationPath.path && linksDirectlyToManaged)
                || (!managedPath.pathComponents.starts(with: destinationPath.pathComponents)
                    && !destinationPath.pathComponents.starts(with: managedPath.pathComponents)) else {
            throw AIAgentSkillSynchronizationError.destinationIsNotManaged(destination.path)
        }
    }

    private func resolvedDirectory(_ directory: URL) -> URL {
        // Resolve existing parents even when the final directory does not exist yet.
        directory.pathComponents.dropFirst().reduce(URL(fileURLWithPath: "/", isDirectory: true)) {
            $0.appendingPathComponent($1).resolvingSymlinksInPath()
        }.standardizedFileURL
    }

    private func isManagedLink(_ item: URL, managedDirectory: URL) -> Bool {
        guard let target = try? fileManager.destinationOfSymbolicLink(atPath: item.path) else {
            return false
        }
        return URL(fileURLWithPath: target, relativeTo: item.deletingLastPathComponent())
            .resolvingSymlinksInPath()
            .standardizedFileURL == managedDirectory.resolvingSymlinksInPath().standardizedFileURL
    }

    private func itemExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
            || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}
