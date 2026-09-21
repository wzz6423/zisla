import Foundation
import Testing
import ZislaCore

@testable import Zisla

@MainActor
struct UpdateFeedResolverTests {
    @Test(arguments: ["CN", "US", nil])
    func settingsChangesPreserveManualCheckAndShareMirrorOrder(countryCode: String?) async throws {
        let gate = LookupGate()
        let resolver = UpdateFeedResolver { await gate.load() }
        let preference = UpdateFeedPreference(countryCode: countryCode)
        let feeds = SparkleFeedPair(
            gitee: try #require(URL(string: "https://gitee.example/appcast.xml")),
            github: try #require(URL(string: "https://github.example/appcast.xml"))
        )
        var applied: [String] = []
        var primaryURLs: [URL] = []
        let request = resolver.resolve(manual: true) {
            applied.append("manual")
            primaryURLs.append(feeds.url(for: .primary, preference: $0))
        }
        await gate.waitUntilStarted()
        resolver.resolve(manual: false) { _ in applied.append("stale-settings") }
        resolver.resolve(manual: false) {
            applied.append("latest-settings")
            primaryURLs.append(feeds.url(for: .primary, preference: $0))
        }

        #expect(applied.isEmpty)
        gate.release(preference)
        await request?.value

        let expectedURL = countryCode == "US" ? feeds.github : feeds.gitee
        #expect(applied == ["latest-settings", "manual"])
        #expect(primaryURLs == [expectedURL, expectedURL])
        #expect(gate.requests == 1)
    }

    @Test
    func disablingAutomaticChecksPreservesPendingManualCheck() async {
        let gate = LookupGate()
        let resolver = UpdateFeedResolver { await gate.load() }
        var applied: [String] = []
        let request = resolver.resolve(manual: false) { _ in applied.append("automatic") }
        await gate.waitUntilStarted()
        resolver.resolve(manual: true) { _ in applied.append("manual") }

        resolver.cancelAutomaticConfiguration()
        gate.release(.githubFirst)
        await request?.value

        #expect(applied == ["manual"])
    }

    @Test
    func disablingAutomaticChecksAloneCannotStartAnUpdateAfterLookup() async {
        let gate = LookupGate()
        let resolver = UpdateFeedResolver { await gate.load() }
        var configured = false
        let request = resolver.resolve(manual: false) { _ in configured = true }
        await gate.waitUntilStarted()
        resolver.cancelAutomaticConfiguration()

        gate.release(.githubFirst)
        await request?.value

        #expect(!configured)
    }

    @Test
    func repeatedManualRequestsCoalesceAndLaterChecksUseCachedPreference() async {
        let gate = LookupGate()
        let resolver = UpdateFeedResolver { await gate.load() }
        var applied: [UpdateFeedPreference] = []
        var replacedRequestRan = false
        let request = resolver.resolve(manual: true) { _ in replacedRequestRan = true }
        await gate.waitUntilStarted()
        resolver.resolve(manual: true) { applied.append($0) }
        gate.release(.githubFirst)
        await request?.value
        #expect(applied == [.githubFirst])
        #expect(!replacedRequestRan)

        resolver.resolve(manual: false) { applied.append($0) }
        resolver.resolve(manual: true) { applied.append($0) }

        #expect(applied == [.githubFirst, .githubFirst, .githubFirst])
        #expect(gate.requests == 1)
    }

    @Test(arguments: [false, true])
    func completedOrCancelledRequestsReleaseCallbackCaptures(cancelled: Bool) async {
        let gate = LookupGate()
        let resolver = UpdateFeedResolver { await gate.load() }
        var capture: NSObject? = NSObject()
        weak var releasedCapture = capture
        let request = resolver.resolve(manual: true) { [capture] _ in _ = capture }
        resolver.resolve(manual: false) { [capture] _ in _ = capture }
        capture = nil
        #expect(releasedCapture != nil)
        if cancelled { resolver.cancel() }

        gate.release(.githubFirst)
        await request?.value

        #expect(releasedCapture == nil)
    }

    @Test
    func cancelledLookupCannotApplyOrOverwriteAReplacementLookup() async {
        let oldGate = LookupGate()
        let newGate = LookupGate()
        var gate = oldGate
        let resolver = UpdateFeedResolver { await gate.load() }
        var applied: [UpdateFeedPreference] = []
        let oldRequest = resolver.resolve(manual: true) { applied.append($0) }
        await oldGate.waitUntilStarted()
        resolver.cancel()

        gate = newGate
        let newRequest = resolver.resolve(manual: false) { applied.append($0) }
        newGate.release(.githubFirst)
        await newRequest?.value
        oldGate.release(.giteeFirst)
        await oldRequest?.value

        #expect(applied == [.githubFirst])
        #expect(resolver.preference == .githubFirst)
    }
}

@MainActor
private final class LookupGate {
    private var result: UpdateFeedPreference?
    private var continuation: CheckedContinuation<UpdateFeedPreference, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var requests = 0

    func load() async -> UpdateFeedPreference {
        requests += 1
        started?.resume()
        started = nil
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if requests > 0 { return }
        await withCheckedContinuation { started = $0 }
    }

    func release(_ preference: UpdateFeedPreference) {
        result = preference
        continuation?.resume(returning: preference)
        continuation = nil
    }
}
