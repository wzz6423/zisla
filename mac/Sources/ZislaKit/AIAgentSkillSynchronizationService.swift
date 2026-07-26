import Foundation

public enum AIAgentSkillSynchronizationMode: Sendable {
    case symbolicLink
    case fileCopy
}

public enum AIAgentSkillSynchronizationError: LocalizedError {
    case destinationIsNotManaged(String)

    public var errorDescription: String? {
        switch self {
        case let .destinationIsNotManaged(path):
            "目标目录不是由 Zisla 管理，已保留原内容：\(path)"
        }
    }
}

public struct AIAgentSkillSynchronizationService {
    private let fileManager: FileManager
    private let markerFileName = ".zisla-skill-sync"

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
        mode: AIAgentSkillSynchronizationMode
    ) throws {
        try ensureManagedDirectory(at: managedDirectory)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try removeDestinationIfPresent(destination, managedDirectory: managedDirectory)

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
    }

    public func disable(at destination: URL, managedDirectory: URL) throws {
        try removeDestinationIfPresent(destination, managedDirectory: managedDirectory)
    }

    private func removeDestinationIfPresent(_ destination: URL, managedDirectory: URL) throws {
        let values = try? destination.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard fileManager.fileExists(atPath: destination.path) || values?.isSymbolicLink == true else {
            return
        }

        if values?.isSymbolicLink == true {
            let target = try fileManager.destinationOfSymbolicLink(atPath: destination.path)
            let targetURL = URL(fileURLWithPath: target, relativeTo: destination.deletingLastPathComponent())
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard targetURL == managedDirectory.resolvingSymlinksInPath().standardizedFileURL else {
                throw AIAgentSkillSynchronizationError.destinationIsNotManaged(destination.path)
            }
        } else {
            let marker = destination.appendingPathComponent(markerFileName)
            let markerContents = try? String(contentsOf: marker, encoding: .utf8)
            guard markerContents == managedDirectory.path else {
                throw AIAgentSkillSynchronizationError.destinationIsNotManaged(destination.path)
            }
        }
        try fileManager.removeItem(at: destination)
    }
}
