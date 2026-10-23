import Foundation
import Sparkle
import Testing
import ZislaCore

@testable import Zisla

@Suite(.serialized)
struct UpdateReleaseNotesClientTests {
    @Test(arguments: [UpdateFeedPreference.giteeFirst, .githubFirst])
    func readsThePackageTagFromThePreferredMirror(preference: UpdateFeedPreference) async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        ReleaseNotesURLProtocol.responses = [.success(payload())]
        let notes = try await UpdateReleaseNotesClient(session: session).fetch(tagName: "v1.2.3", preference: preference)

        #expect(notes.markdown == "## Changes\n\n- Fixed updates")
        #expect(notes.releaseURL.host == (preference == .giteeFirst ? "gitee.com" : "github.com"))
        #expect(ReleaseNotesURLProtocol.requests.count == 1)
        #expect(ReleaseNotesURLProtocol.requests[0].url?.path.hasSuffix("/releases/tags/v1.2.3") == true)
        #expect(ReleaseNotesURLProtocol.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test(arguments: [UpdateFeedPreference.giteeFirst, .githubFirst])
    func fallsBackOnceOnNetworkAndMetadataFailures(preference: UpdateFeedPreference) async throws {
        for failure in [
            ReleaseNotesURLProtocol.Response.failure(URLError(.timedOut)),
            .http(429, Data()),
            .success(Data("broken json".utf8)),
            .success(payload(tag: "v9.9.9")),
            .success(payload(body: " \n ")),
            .success(payload(draft: true)),
            .success(payload(body: String(repeating: "a", count: 1_048_577))),
            .nonHTTP,
        ] {
            let session = makeSession()
            defer { session.invalidateAndCancel() }
            ReleaseNotesURLProtocol.responses = [failure, .success(payload())]
            let notes = try await UpdateReleaseNotesClient(session: session).fetch(tagName: "v1.2.3", preference: preference)

            let expected = preference == .giteeFirst ? ["gitee.com", "api.github.com"] : ["api.github.com", "gitee.com"]
            #expect(ReleaseNotesURLProtocol.requests.map(\.url?.host) == expected)
            #expect(notes.releaseURL.host == (preference == .giteeFirst ? "github.com" : "gitee.com"))
        }
    }

    @Test
    func stopsAfterBothMirrorsFail() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        ReleaseNotesURLProtocol.responses = [.http(503, Data()), .http(404, Data())]
        await #expect(throws: UpdateReleaseNotesClientError.httpStatus(404)) {
            try await UpdateReleaseNotesClient(session: session).fetch(tagName: "v1.2.3", preference: .giteeFirst)
        }
        #expect(ReleaseNotesURLProtocol.requests.count == 2)
    }

    @Test
    func cancellationDoesNotStartTheFallback() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        ReleaseNotesURLProtocol.responses = [.failure(URLError(.cancelled))]
        do {
            _ = try await UpdateReleaseNotesClient(session: session).fetch(tagName: "v1.2.3", preference: .giteeFirst)
            Issue.record("A cancelled request must not return release notes")
        } catch {
            #expect((error as? URLError)?.code == .cancelled)
        }
        #expect(ReleaseNotesURLProtocol.requests.count == 1)
    }

    @Test(arguments: ["", ".", "..", "v1/../v2", "v1\n2"])
    func rejectsInvalidTagsWithoutRequests(tag: String) async {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        await #expect(throws: UpdateReleaseNotesClientError.invalidTag) {
            try await UpdateReleaseNotesClient(session: session).fetch(tagName: tag, preference: .giteeFirst)
        }
        #expect(ReleaseNotesURLProtocol.requests.isEmpty)
    }

    @Test
    func previewNotesUseTheExactVersionTag() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        ReleaseNotesURLProtocol.responses = [.success(payload(tag: "v1.2.3-preview.2"))]
        _ = try await UpdateReleaseNotesClient(session: session).fetch(tagName: "v1.2.3-preview.2", preference: .githubFirst)
        #expect(ReleaseNotesURLProtocol.requests[0].url?.lastPathComponent == "v1.2.3-preview.2")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ZISLA_RUN_NETWORK_UPDATE_TESTS"] == "1"))
    func readsPublishedNotesWithTheProductionClient() async throws {
        for preference in [UpdateFeedPreference.giteeFirst, .githubFirst] {
            let notes = try await UpdateReleaseNotesClient().fetch(tagName: "v0.1.19", preference: preference)
            #expect(notes.markdown.contains("## zisla 0.1.19"))
            #expect(notes.releaseURL.lastPathComponent == "v0.1.19")
        }
    }

    @Test
    func malformedPayloadsAlwaysUseTheSameBoundedFallback() async throws {
        var seed: UInt64 = 0x52E1EA5E
        for length in 0..<32 {
            let bytes = (0..<length).map { _ -> UInt8 in
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                return UInt8(truncatingIfNeeded: seed >> 32)
            }
            let session = makeSession()
            defer { session.invalidateAndCancel() }
            ReleaseNotesURLProtocol.responses = [.success(Data(bytes)), .success(payload())]
            let notes = try await UpdateReleaseNotesClient(session: session).fetch(tagName: "v1.2.3", preference: .giteeFirst)
            #expect(notes.markdown == "## Changes\n\n- Fixed updates")
            #expect(ReleaseNotesURLProtocol.requests.count == 2)
        }
    }

    @Test
    @MainActor
    func loadingFailureCanBeRetriedAndLoadedNotesAreReusedOffline() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        ReleaseNotesURLProtocol.responses = [.http(503, Data()), .http(503, Data()), .success(payload())]
        let model = UpdateReleaseNotesModel(
            release: UpdateRelease(version: "1.2.3", build: "23", tagName: "v1.2.3"),
            preference: .githubFirst,
            client: UpdateReleaseNotesClient(session: session)
        )
        var published: [UpdateReleaseNotes] = []
        model.onNotesLoaded = { published.append($0) }
        await model.load()
        #expect(model.loadFailed)
        #expect(model.notes == nil)
        #expect(published.isEmpty)
        await model.load()
        #expect(!model.loadFailed)
        #expect(model.notes?.markdown == "## Changes\n\n- Fixed updates")
        #expect(published == [try #require(model.notes)])
        await model.load()
        #expect(ReleaseNotesURLProtocol.requests.count == 3)
        #expect(published.count == 1)

        let offline = UpdateReleaseNotesModel(
            release: model.release,
            preference: model.preference,
            notes: model.notes,
            client: UpdateReleaseNotesClient(session: session)
        )
        await offline.load()
        #expect(offline.notes == model.notes)
        #expect(ReleaseNotesURLProtocol.requests.count == 3)
    }

    @Test
    @MainActor
    func cancelledModelsNeverPublishNotesOrAnError() async {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        ReleaseNotesURLProtocol.responses = [.success(payload())]
        let model = UpdateReleaseNotesModel(
            release: UpdateRelease(version: "1.2.3", build: "23", tagName: "v1.2.3"),
            preference: .githubFirst,
            client: UpdateReleaseNotesClient(session: session)
        )
        let task = Task { await model.load() }
        task.cancel()
        await task.value
        #expect(model.notes == nil)
        #expect(!model.loadFailed)
        #expect(ReleaseNotesURLProtocol.requests.isEmpty)
    }

    private func makeSession() -> URLSession {
        ReleaseNotesURLProtocol.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseNotesURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func payload(tag: String = "v1.2.3", body: String = "## Changes\n\n- Fixed updates", draft: Bool = false) -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "body": body, "draft": draft])
    }
}

@Suite(.serialized)
@MainActor
struct UpdateReleaseNotesStoreTests {
    @Test
    func onlyTheInstalledBuildConsumesTheRecordAndOnlyOnce() throws {
        let suite = "zisla-release-notes-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateReleaseNotesStore(defaults: defaults)
        let release = UpdateRelease(version: "1.2.3", build: "23", tagName: "v1.2.3")
        let notes = UpdateReleaseNotes(markdown: "# What's new", releaseURL: URL(string: "https://github.com/wzz6423/zisla/releases/tag/v1.2.3")!)
        store.record(release, preference: .githubFirst, notes: notes)

        #expect(store.takeInstalledRelease(version: "1.2.2", build: "22") == nil)
        #expect(store.takeInstalledRelease(version: "1.2.3", build: "22") == nil)
        #expect(store.takeInstalledRelease(version: "1.2.4", build: "23") == nil)
        let installed = try #require(UpdateReleaseNotesStore(defaults: defaults).takeInstalledRelease(version: "1.2.3", build: "23"))
        #expect(installed.release == release)
        #expect(installed.notes == notes)
        #expect(installed.preference == .githubFirst)
        #expect(store.takeInstalledRelease(version: "1.2.3", build: "23") == nil)
    }

    @Test
    func aFreshInstallAndCorruptRecordDoNotReportAnUpdate() throws {
        let suite = "zisla-release-notes-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateReleaseNotesStore(defaults: defaults)
        #expect(store.takeInstalledRelease(version: "1.2.3", build: "23") == nil)
        defaults.set(Data("corrupt".utf8), forKey: UpdateReleaseNotesStore.defaultsKey)
        #expect(store.takeInstalledRelease(version: "1.2.3", build: "23") == nil)
        #expect(defaults.object(forKey: UpdateReleaseNotesStore.defaultsKey) == nil)
    }

    @Test
    func theFirstUpgradeFromAnOlderAppShowsNotesOnceAndFirstInstallsDoNot() throws {
        let suite = "zisla-release-notes-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateReleaseNotesStore(defaults: defaults)
        let upgraded = try #require(store.takeInstalledRelease(version: "1.2.3", build: "23", hasExistingInstallation: true))
        #expect(upgraded.release.tagName == "v1.2.3")
        #expect(upgraded.preference == nil)
        #expect(store.takeInstalledRelease(version: "1.2.3", build: "23", hasExistingInstallation: true) == nil)
    }

    @Test
    func manualUpgradesShowNotesButDowngradesAndOrdinaryRelaunchesDoNot() throws {
        let suite = "zisla-release-notes-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateReleaseNotesStore(defaults: defaults)
        #expect(store.takeInstalledRelease(version: "1.2.3", build: "23") == nil)
        #expect(store.takeInstalledRelease(version: "1.2.3", build: "23", hasExistingInstallation: true) == nil)
        #expect(store.takeInstalledRelease(version: "1.2.4", build: "24")?.release.tagName == "v1.2.4")
        #expect(store.takeInstalledRelease(version: "1.2.3", build: "23") == nil)
    }

    @Test
    func skippedUpdatesClearTheirPendingNotes() throws {
        let suite = "zisla-release-notes-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateReleaseNotesStore(defaults: defaults)
        store.record(UpdateRelease(version: "1.2.3", build: "23", tagName: "v1.2.3"), preference: .giteeFirst, notes: nil)
        store.clear()
        #expect(store.takeInstalledRelease(version: "1.2.3", build: "23") == nil)
    }

    @Test
    func lateNotesOnlyUpdateTheMatchingPendingRelease() throws {
        let suite = "zisla-release-notes-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateReleaseNotesStore(defaults: defaults)
        let release = UpdateRelease(version: "1.2.3", build: "23", tagName: "v1.2.3")
        let notes = UpdateReleaseNotes(markdown: "Late notes", releaseURL: URL(string: "https://gitee.com/wzz6423/zisla/releases/tag/v1.2.3")!)
        store.updateNotes(notes, for: release)
        #expect(defaults.object(forKey: UpdateReleaseNotesStore.defaultsKey) == nil)
        store.record(release, preference: .giteeFirst, notes: nil)
        store.updateNotes(notes, for: UpdateRelease(version: "1.2.2", build: "22", tagName: "v1.2.2"))
        let data = try #require(defaults.data(forKey: UpdateReleaseNotesStore.defaultsKey))
        #expect(try JSONDecoder().decode(UpdateReleaseNotesStore.InstalledRelease.self, from: data).notes == nil)
        store.updateNotes(notes, for: release)
        #expect(store.takeInstalledRelease(version: "1.2.3", build: "23")?.notes == notes)
    }

    @Test
    func usesTheDownloadTagInsteadOfAPermanentFeedTag() throws {
        let item = try #require(SUAppcastItem(dictionary: [
            "sparkle:version": "23",
            "sparkle:shortVersionString": "1.2.3",
            "enclosure": ["url": "https://gitee.com/wzz6423/zisla/releases/download/v1.2.3-preview.2/zisla.zip", "length": "1"],
        ]))
        #expect(UpdateRelease(item: item).tagName == "v1.2.3-preview.2")
    }

    @Test(arguments: ["1.2.3", "v1.2.3", "1.2.3+build.4"])
    func informationalUpdatesUseTheirVersionTag(version: String) throws {
        let item = try #require(SUAppcastItem(dictionary: [
            "sparkle:version": "23",
            "sparkle:shortVersionString": version,
            "link": "https://github.com/wzz6423/zisla/releases",
        ]))
        #expect(UpdateRelease(item: item).tagName == (version.hasPrefix("v") ? version : "v\(version)"))
    }

    @Test
    func extractionCallbackRecordsNotesBeforeAnUpdateCanInstallOnQuit() throws {
        let suite = "zisla-release-notes-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateReleaseNotesStore(defaults: defaults)
        let driver = SparkleStandardUserDriver(hostBundle: .main, shouldSuppressUpdaterError: { true }, releaseNotesStore: store)
        driver.feedPreference = .githubFirst
        let url = try #require(URL(string: "https://gitee.example/appcast.xml"))
        let delegate = SparkleFeedDelegate(feeds: SparkleFeedPair(gitee: url, github: url))
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: delegate)
        delegate.onUpdatePrepared = { driver.recordPendingUpdate($0) }
        let item = try #require(SUAppcastItem(dictionary: [
            "sparkle:version": "23",
            "sparkle:shortVersionString": "1.2.3",
            "enclosure": ["url": "https://github.com/wzz6423/zisla/releases/download/v1.2.3/zisla.zip", "length": "1"],
        ]))
        delegate.updater(updater, didExtractUpdate: item)
        let installed = try #require(store.takeInstalledRelease(version: "1.2.3", build: "23"))
        #expect(installed.preference == .githubFirst)
        #expect(installed.release.tagName == "v1.2.3")
        #expect(installed.notes == nil)
    }
}

private final class ReleaseNotesURLProtocol: URLProtocol, @unchecked Sendable {
    enum Response {
        case http(Int, Data)
        case failure(URLError)
        case nonHTTP

        static func success(_ data: Data) -> Self { .http(200, data) }
    }

    nonisolated(unsafe) static var responses: [Response] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        switch Self.responses.isEmpty ? .http(404, Data()) : Self.responses.removeFirst() {
        case let .http(status, data):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        case .nonHTTP:
            client?.urlProtocol(self, didReceive: URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil), cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
