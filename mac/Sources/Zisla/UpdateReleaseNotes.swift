@preconcurrency import Foundation
import Combine
import Sparkle
import ZislaCore

struct UpdateRelease: Codable, Equatable, Sendable {
    let version: String
    let build: String
    let tagName: String

    init(version: String, build: String, tagName: String) {
        self.version = version
        self.build = build
        self.tagName = tagName
    }

    init(item: SUAppcastItem) {
        version = item.displayVersionString
        build = item.versionString
        let components = item.fileURL?.pathComponents ?? []
        if let download = components.firstIndex(of: "download"), download + 1 < components.count {
            tagName = components[download + 1]
        } else {
            tagName = version.hasPrefix("v") ? version : "v\(version)"
        }
    }
}

struct UpdateReleaseNotes: Codable, Equatable, Sendable {
    let markdown: String
    let releaseURL: URL
}

enum UpdateReleaseNotesClientError: Error, Equatable {
    case invalidTag
    case invalidResponse
    case malformedRelease
    case httpStatus(Int)
}

struct UpdateReleaseNotesClient: Sendable {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 15
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetch(tagName: String, preference: UpdateFeedPreference) async throws -> UpdateReleaseNotes {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.+")
        guard !tagName.isEmpty, tagName != ".", tagName != "..",
              tagName.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw UpdateReleaseNotesClientError.invalidTag
        }
        let endpoints = SparkleFeedPair(
            gitee: URL(string: "https://gitee.com/api/v5/repos/wzz6423/zisla/releases/tags/\(tagName)")!,
            github: URL(string: "https://api.github.com/repos/wzz6423/zisla/releases/tags/\(tagName)")!
        )
        var fallback = UpdateFeedFallbackState()
        while true {
            try Task.checkCancellation()
            let endpoint = endpoints.url(for: fallback.source, preference: preference)
            do {
                var request = URLRequest(url: endpoint)
                request.timeoutInterval = 10
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("zisla-macOS", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse else {
                    throw UpdateReleaseNotesClientError.invalidResponse
                }
                guard response.statusCode == 200 else {
                    throw UpdateReleaseNotesClientError.httpStatus(response.statusCode)
                }
                guard data.count <= 1_048_576,
                      let payload = try? JSONDecoder().decode(Payload.self, from: data),
                      payload.tagName == tagName, payload.draft != true,
                      let markdown = payload.body,
                      !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw UpdateReleaseNotesClientError.malformedRelease
                }
                let host = endpoint.host == "gitee.com" ? "gitee.com" : "github.com"
                return UpdateReleaseNotes(
                    markdown: markdown,
                    releaseURL: URL(string: "https://\(host)/wzz6423/zisla/releases/tag/\(tagName)")!
                )
            } catch {
                try Task.checkCancellation()
                if (error as? URLError)?.code == .cancelled { throw error }
                guard fallback.finishCheck(failed: true) else { throw error }
            }
        }
    }

    private struct Payload: Decodable {
        let tagName: String
        let body: String?
        let draft: Bool?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body, draft
        }
    }
}

@MainActor
final class UpdateReleaseNotesModel: ObservableObject {
    let release: UpdateRelease
    let preference: UpdateFeedPreference
    @Published private(set) var notes: UpdateReleaseNotes?
    @Published private(set) var loadFailed = false
    var onNotesLoaded: ((UpdateReleaseNotes) -> Void)?
    private let client: UpdateReleaseNotesClient

    init(
        release: UpdateRelease,
        preference: UpdateFeedPreference,
        notes: UpdateReleaseNotes? = nil,
        client: UpdateReleaseNotesClient = UpdateReleaseNotesClient()
    ) {
        self.release = release
        self.preference = preference
        self.notes = notes
        self.client = client
    }

    func load() async {
        guard notes == nil else { return }
        loadFailed = false
        do {
            let loaded = try await client.fetch(tagName: release.tagName, preference: preference)
            try Task.checkCancellation()
            notes = loaded
            onNotesLoaded?(loaded)
        } catch {
            guard !Task.isCancelled else { return }
            loadFailed = true
        }
    }
}

@MainActor
final class UpdateReleaseNotesStore {
    static let defaultsKey = "zisla.pending-update-release-notes"
    static let lastBuildKey = "zisla.release-notes.last-launched-build"
    private let defaults: UserDefaults

    struct InstalledRelease: Codable, Equatable {
        let release: UpdateRelease
        let githubFirst: Bool?
        let notes: UpdateReleaseNotes?

        var preference: UpdateFeedPreference? { githubFirst.map { $0 ? .githubFirst : .giteeFirst } }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func record(_ release: UpdateRelease, preference: UpdateFeedPreference, notes: UpdateReleaseNotes?) {
        let record = InstalledRelease(release: release, githubFirst: preference == .githubFirst, notes: notes)
        defaults.set(try! JSONEncoder().encode(record), forKey: Self.defaultsKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    func updateNotes(_ notes: UpdateReleaseNotes, for release: UpdateRelease) {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let pending = try? JSONDecoder().decode(InstalledRelease.self, from: data),
              pending.release == release else { return }
        let updated = InstalledRelease(release: release, githubFirst: pending.githubFirst, notes: notes)
        defaults.set(try! JSONEncoder().encode(updated), forKey: Self.defaultsKey)
    }

    func takeInstalledRelease(version: String, build: String, hasExistingInstallation: Bool = false) -> InstalledRelease? {
        let previousBuild = defaults.string(forKey: Self.lastBuildKey)
        defaults.set(build, forKey: Self.lastBuildKey)
        if let data = defaults.data(forKey: Self.defaultsKey),
           let record = try? JSONDecoder().decode(InstalledRelease.self, from: data) {
            if record.release.version == version, record.release.build == build {
                clear()
                return record
            }
            if record.release.build == build { return nil }
        } else if defaults.object(forKey: Self.defaultsKey) != nil {
            clear()
        }
        let didUpgrade = previousBuild.map {
            SUStandardVersionComparator.default.compareVersion($0, toVersion: build) == .orderedAscending
        } ?? hasExistingInstallation
        guard didUpgrade else { return nil }
        clear()
        return InstalledRelease(
            release: UpdateRelease(version: version, build: build, tagName: version.hasPrefix("v") ? version : "v\(version)"),
            githubFirst: nil,
            notes: nil
        )
    }
}
