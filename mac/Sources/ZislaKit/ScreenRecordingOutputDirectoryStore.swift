import Foundation

@MainActor
public final class ScreenRecordingOutputDirectoryStore {
    public private(set) var directory: URL
    private let defaults: UserDefaults
    private let bookmarkKey: String
    private let pathKey: String?
    private var scopedDirectory: URL?

    public init(defaults: UserDefaults = .standard,
                bookmarkKey: String = "screen-recording-directory-bookmark",
                pathKey: String? = "screen-recording-directory-path") {
        self.defaults = defaults
        self.bookmarkKey = bookmarkKey
        self.pathKey = pathKey
        var stale = false
        if let bookmark = defaults.data(forKey: bookmarkKey),
           let resolved = try? URL(resolvingBookmarkData: bookmark,
               options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
            directory = resolved.standardizedFileURL
        } else if let pathKey, let path = defaults.string(forKey: pathKey), !path.isEmpty {
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
            defaults.set(bookmark, forKey: bookmarkKey)
            if let pathKey { defaults.set(directory.path, forKey: pathKey) }
            scopedDirectory?.stopAccessingSecurityScopedResource()
            scopedDirectory = accessing ? directory : nil
            self.directory = directory
        } catch {
            if accessing { directory.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
}
