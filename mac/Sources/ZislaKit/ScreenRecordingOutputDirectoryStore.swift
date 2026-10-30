import Foundation

@MainActor
public final class ScreenRecordingOutputDirectoryStore {
    public private(set) var directory: URL
    private let defaults: UserDefaults
    private static let bookmarkKey = "screen-recording-directory-bookmark"
    private static let pathKey = "screen-recording-directory-path"
    private var scopedDirectory: URL?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var stale = false
        if let bookmark = defaults.data(forKey: Self.bookmarkKey),
           let resolved = try? URL(resolvingBookmarkData: bookmark,
               options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
            directory = resolved.standardizedFileURL
        } else if let path = defaults.string(forKey: Self.pathKey), !path.isEmpty {
            directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        } else {
            directory = AppPaths.downloads
        }
        if directory.startAccessingSecurityScopedResource() { scopedDirectory = directory }
    }

    deinit { scopedDirectory?.stopAccessingSecurityScopedResource() }

    public func setDirectory(_ url: URL) throws {
        guard url.isFileURL else { throw CocoaError(.fileWriteInvalidFileName) }
        let directory = url.standardizedFileURL
        let accessing = directory.startAccessingSecurityScopedResource()
        do {
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            let bookmark = try directory.bookmarkData(options: .withSecurityScope,
                includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Self.bookmarkKey)
            defaults.set(directory.path, forKey: Self.pathKey)
            scopedDirectory?.stopAccessingSecurityScopedResource()
            scopedDirectory = accessing ? directory : nil
            self.directory = directory
        } catch {
            if accessing { directory.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
}
