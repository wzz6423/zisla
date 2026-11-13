import Combine
import Foundation

public enum SaveLocation: String, CaseIterable, Identifiable, Sendable {
    case download
    case pdfTools
    case imageTools
    case screenshot
    case recording
    case quickActions
    case dailyBriefing

    public var id: Self { self }

    public var title: String {
        switch self {
        case .download: "下载"
        case .pdfTools: "PDF 工具"
        case .imageTools: "图片工具"
        case .screenshot: "截图"
        case .recording: "录屏"
        case .quickActions: "快捷操作"
        case .dailyBriefing: "每日简报"
        }
    }

    public var symbol: String {
        switch self {
        case .download: "arrow.down.circle.fill"
        case .pdfTools: "doc.text.fill"
        case .imageTools: "photo.stack.fill"
        case .screenshot: "camera.viewfinder"
        case .recording: "record.circle"
        case .quickActions: "sparkles.rectangle.stack"
        case .dailyBriefing: "doc.richtext"
        }
    }

    var defaultDirectory: URL {
        switch self {
        case .download: AppPaths.downloads
        case .pdfTools: AppPaths.downloads.appendingPathComponent("pdf", isDirectory: true)
        case .imageTools, .screenshot: AppPaths.downloads.appendingPathComponent("picture", isDirectory: true)
        case .recording: AppPaths.downloads.appendingPathComponent("video", isDirectory: true)
        case .quickActions: AppPaths.downloads.appendingPathComponent("quick", isDirectory: true)
        case .dailyBriefing: AppPaths.downloads.appendingPathComponent("daily", isDirectory: true)
        }
    }

    var bookmarkKey: String {
        self == .download ? "download-directory-bookmark" : "save-location-\(rawValue)-bookmark"
    }

    var pathKey: String? {
        self == .download ? nil : "save-location-\(rawValue)-path"
    }
}

@MainActor
public final class SaveLocationStore: ObservableObject {
    @Published public private(set) var directories: [SaveLocation: URL]
    private let stores: [SaveLocation: ScreenRecordingOutputDirectoryStore]

    public init(defaults: UserDefaults = .standard) {
        let download = ScreenRecordingOutputDirectoryStore(defaults: defaults,
            bookmarkKey: SaveLocation.download.bookmarkKey, pathKey: nil)
        var stores: [SaveLocation: ScreenRecordingOutputDirectoryStore] = [.download: download]
        for location in SaveLocation.allCases where location != .download {
            let pathKey = location.pathKey!
            if defaults.object(forKey: location.bookmarkKey) == nil,
               defaults.object(forKey: pathKey) == nil {
                // Preserve inherited bookmarks while keeping later download changes independent.
                if let bookmark = defaults.data(forKey: SaveLocation.download.bookmarkKey) {
                    defaults.set(bookmark, forKey: location.bookmarkKey)
                    defaults.set(download.directory.path, forKey: pathKey)
                } else {
                    defaults.set(location.defaultDirectory.path, forKey: pathKey)
                }
            }
            stores[location] = ScreenRecordingOutputDirectoryStore(defaults: defaults,
                bookmarkKey: location.bookmarkKey, pathKey: pathKey)
        }
        self.stores = stores
        directories = stores.mapValues(\.directory)
    }

    public subscript(location: SaveLocation) -> URL { directories[location]! }

    public func setDirectory(_ url: URL, for location: SaveLocation) throws {
        let store = stores[location]!
        try store.setDirectory(url)
        directories[location] = store.directory
    }
}
