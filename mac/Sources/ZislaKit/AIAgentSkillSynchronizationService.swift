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
        try ensureManagedDirectory(at: managedDirectory)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let backup = try prepareDestination(
            destination,
            managedDirectory: managedDirectory,
            backupRoot: backupRoot
        )

        do {
            switch mode {
            case .symbolicLink:
                try fileManager.createSymbolicLink(at: destination, withDestinationURL: managedDirectory)
            case .fileCopy:
                try fileManager.copyItem(at: managedDirectory, to: destination)
                try Data(managedDirectory.path.utf8).write(
                    to: destination.appendingPathComponent(markerFileName),
                    options: .atomic
                )
            }
        } catch {
            if let backup {
                try? fileManager.removeItem(at: destination)
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    public func disable(
        at destination: URL,
        managedDirectory: URL,
        backupRoot: URL? = nil
    ) throws {
        _ = try prepareDestination(
            destination,
            managedDirectory: managedDirectory,
            backupRoot: backupRoot,
            preservesUnmanagedDestination: true
        )
    }

    private func prepareDestination(
        _ destination: URL,
        managedDirectory: URL,
        backupRoot: URL?,
        preservesUnmanagedDestination: Bool = false
    ) throws -> URL? {
        let linkTarget = try? fileManager.destinationOfSymbolicLink(atPath: destination.path)
        guard itemExists(at: destination) else {
            return nil
        }

        if let linkTarget {
            let targetURL = URL(fileURLWithPath: linkTarget, relativeTo: destination.deletingLastPathComponent())
                .resolvingSymlinksInPath()
                .standardizedFileURL
            if targetURL == managedDirectory.resolvingSymlinksInPath().standardizedFileURL {
                try fileManager.removeItem(at: destination)
                return nil
            }
        } else {
            let markerContents = try? String(
                contentsOf: destination.appendingPathComponent(markerFileName),
                encoding: .utf8
            )
            if markerContents == managedDirectory.path {
                if preservesUnmanagedDestination, let backupRoot {
                    return try moveDestinationToBackup(destination, backupRoot: backupRoot)
                }
                try fileManager.removeItem(at: destination)
                return nil
            }
        }

        if preservesUnmanagedDestination {
            return nil
        }
        guard let backupRoot else {
            throw AIAgentSkillSynchronizationError.destinationIsNotManaged(destination.path)
        }
        return try takeOverUnmanagedDirectory(
            destination,
            linkTarget: linkTarget,
            managedDirectory: managedDirectory,
            backupRoot: backupRoot
        )
    }

    private func takeOverUnmanagedDirectory(
        _ destination: URL,
        linkTarget: String?,
        managedDirectory: URL,
        backupRoot: URL
    ) throws -> URL {
        let importSource = linkTarget.map {
            URL(fileURLWithPath: $0, relativeTo: destination.deletingLastPathComponent())
                .standardizedFileURL
        }

        let backup = try moveDestinationToBackup(destination, backupRoot: backupRoot)
        do {
            let source = importSource ?? backup
            try importDirectoryContents(from: source, into: managedDirectory)
        } catch {
            try? fileManager.moveItem(at: backup, to: destination)
            throw error
        }
        return backup
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

    private func importDirectoryContents(from source: URL, into managedDirectory: URL) throws {
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            guard item.lastPathComponent != markerFileName else { continue }
            if item.lastPathComponent == legacyManagedDirectoryName {
                if isManagedLink(item, managedDirectory: managedDirectory) {
                    continue
                }
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    try importDirectoryContents(from: item, into: managedDirectory)
                    continue
                }
            }
            let managedItem = managedDirectory.appendingPathComponent(item.lastPathComponent)
            guard !itemExists(at: managedItem) else { continue }
            try fileManager.copyItem(at: item, to: managedItem)
        }
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
