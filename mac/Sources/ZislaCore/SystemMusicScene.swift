import Foundation

public enum SystemMusicScene: String, CaseIterable, Identifiable, Sendable, Equatable {
    case sleep
    case focus
    case relax
    case balance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sleep: "安睡助眠"
        case .focus: "提升效率"
        case .relax: "放松减压"
        case .balance: "平衡身心"
        }
    }

    public var searchTerm: String {
        switch self {
        case .sleep: "睡眠音乐"
        case .focus: "专注音乐"
        case .relax: "放松音乐"
        case .balance: "冥想音乐"
        }
    }

    public var symbol: String {
        switch self {
        case .sleep: "moon.stars.fill"
        case .focus: "scope"
        case .relax: "leaf.fill"
        case .balance: "figure.mind.and.body"
        }
    }

    public var searchURL: URL? {
        var components = URLComponents()
        components.scheme = "music"
        components.host = "music.apple.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "term", value: searchTerm)]
        return components.url
    }
}
