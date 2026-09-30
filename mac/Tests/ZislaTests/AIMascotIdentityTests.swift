import AppKit
import Combine
import Testing

@testable import Zisla
@testable import ZislaCore

@MainActor
struct AIMascotIdentityTests {
    @Test
    func distinguishesDeepSeekHarnessFromWorkBuddy() {
        #expect(AIMascotIdentity(
            provider: .harness,
            taskID: "dsh-session",
            title: "DeepSeek Harness"
        ) == .deepseekHarness)
        #expect(AIMascotIdentity(
            provider: .harness,
            taskID: "harnext-session",
            title: "harnext"
        ) == .harness)
    }

    @Test
    func recognizesDeepSeekHarnessUpdateNoticeID() {
        #expect(AIMascotIdentity(noticeID: "update-available-cli-dsh-left") == .deepseekHarness)
    }

    @Test
    func mapsZedProviderAndActivityNotice() {
        #expect(AIMascotIdentity(provider: .zed, taskID: "zed-thread-1") == .zed)
        #expect(AIMascotIdentity(noticeID: "ai-active-zed-zed-thread-1") == .zed)
    }

    @Test
    func distinguishesGeminiDesktopChatsFromCLISessions() {
        #expect(AIMascotIdentity(
            provider: .gemini,
            taskID: "gemini-desktop-chat-c1"
        ) == .geminiDesktop)
        #expect(AIMascotIdentity(provider: .gemini, taskID: "gemini-session-s1") == .gemini)
    }

    @Test
    func recognizesGeminiDesktopActivityNotice() {
        #expect(AIMascotIdentity(
            noticeID: "ai-active-gemini-gemini-desktop-chat-c1"
        ) == .geminiDesktop)
        #expect(AIMascotIdentity(noticeID: "ai-active-gemini-gemini-session-s1") == .gemini)
    }
}

@MainActor
struct AIMascotImageCacheTests {
    @Test
    func reusesSuccessfulImageAcrossSessions() throws {
        let cache = AIMascotImageCache()
        let expected = makeImage(size: 12)
        var loadCount = 0

        let image = cache.image(for: "provider|openai.svg", load: {
            loadCount += 1
            return expected
        })
        let loaded = try #require(image)

        let cached = cache.image(for: "provider|openai.svg", load: {
            loadCount += 1
            return nil
        })
        #expect(cached === loaded)
        #expect(loaded.size == expected.size)
        #expect(loadCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func recoversFromTransientLoadFailureAfterRetry() async throws {
        let clock = AIMascotRetryClock()
        let cache = AIMascotImageCache(waitForRetry: { try await clock.wait() })
        let expected = makeImage(size: 12)
        let state = AIMascotImageState()
        var loadCount = 0
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let observer = cache.objectWillChange.sink { continuation.yield(()) }
        defer { observer.cancel(); continuation.finish() }
        var iterator = changes.makeAsyncIterator()

        #expect(cache.image(for: "transient", load: {
            loadCount += 1
            return state.available ? expected : nil
        }) == nil)
        await clock.scheduled()

        #expect(cache.image(for: "transient", load: {
            loadCount += 1
            return expected
        }) == nil)
        #expect(loadCount == 1)

        state.available = true
        await clock.advance()
        await iterator.next()
        let image = cache.image(for: "transient", load: { nil })
        let recovered = try #require(image)

        #expect(recovered.size == expected.size)
        #expect(loadCount == 2)
        #expect(cache.image(for: "transient", load: { nil }) === recovered)
    }

    @Test(.timeLimit(.minutes(1)))
    func persistentFailureDoesNotPoisonFutureLoads() async throws {
        let clock = AIMascotRetryClock()
        let cache = AIMascotImageCache(waitForRetry: { try await clock.wait() })
        let expected = makeImage(size: 12)
        let state = AIMascotImageState()
        var loadCount = 0
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let observer = cache.objectWillChange.sink { continuation.yield(()) }
        defer { observer.cancel(); continuation.finish() }
        var iterator = changes.makeAsyncIterator()

        #expect(cache.image(for: "persistent", load: {
            loadCount += 1
            return state.available ? expected : nil
        }) == nil)
        await clock.advance()
        await clock.scheduled()
        #expect(loadCount == 2)
        await clock.advance()
        await clock.scheduled()
        #expect(loadCount == 3)

        state.available = true
        await clock.advance()
        await iterator.next()

        #expect(cache.image(for: "persistent", load: { nil })?.size == expected.size)
        #expect(loadCount == 4)
    }

    @Test
    func keepsDifferentSourcesSeparate() throws {
        let cache = AIMascotImageCache()
        let chatGPTImage = cache.image(for: "provider|openai.svg", load: { makeImage(size: 12) })
        let codexImage = cache.image(for: "provider|codex-color.svg", load: { makeImage(size: 24) })
        let chatGPT = try #require(chatGPTImage)
        let codex = try #require(codexImage)

        #expect(chatGPT !== codex)
        #expect(cache.image(for: "provider|openai.svg", load: { nil })?.size.width == 12)
        #expect(cache.image(for: "provider|codex-color.svg", load: { nil })?.size.width == 24)
    }

    @Test
    func reusesImageWhenBackingAssetChanges() throws {
        let cache = AIMascotImageCache()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-mascot-change-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(size: 12, to: url)

        let firstImage = cache.image(for: "changed", url: { url })
        let first = try #require(firstImage)
        #expect(first.size.width == 12)

        try writePNG(size: 24, to: url)
        let cachedImage = cache.image(for: "changed", url: { url })
        let cached = try #require(cachedImage)
        #expect(cached === first)
        #expect(cached.size.width == 12)
    }

    @Test
    func keepsLastGoodImageWhenBackingAssetVanishes() throws {
        let cache = AIMascotImageCache()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-mascot-vanish-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(size: 12, to: url)
        var resolutionCount = 0

        let firstImage = cache.image(for: "vanished", url: {
            resolutionCount += 1
            return url
        })
        let first = try #require(firstImage)
        try FileManager.default.removeItem(at: url)

        let cachedImage = cache.image(for: "vanished", url: {
            resolutionCount += 1
            return nil
        })
        let cached = try #require(cachedImage)
        let bitmap = try #require(cached.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let representation = NSBitmapImageRep(cgImage: bitmap)
        let color = try #require(representation.colorAt(x: 6, y: 6)?.usingColorSpace(.deviceRGB))

        #expect(cached === first)
        #expect(resolutionCount == 1)
        #expect(color.redComponent > 0.9)
        #expect(color.alphaComponent > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func resolvesUnavailableResourceOnRetry() async throws {
        let clock = AIMascotRetryClock()
        let cache = AIMascotImageCache(waitForRetry: { try await clock.wait() })
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-mascot-delayed-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let observer = cache.objectWillChange.sink { continuation.yield(()) }
        defer { observer.cancel(); continuation.finish() }
        var iterator = changes.makeAsyncIterator()

        #expect(cache.image(for: "delayed", url: {
            FileManager.default.fileExists(atPath: url.path) ? url : nil
        }) == nil)
        await clock.scheduled()
        try writePNG(size: 12, to: url)
        await clock.advance()
        await iterator.next()

        #expect(cache.image(for: "delayed", url: { nil })?.size.width == 12)
    }

    @Test(.timeLimit(.minutes(1)))
    func corruptResourceCanRecoverWithoutPoisoningCache() async throws {
        let clock = AIMascotRetryClock()
        let cache = AIMascotImageCache(waitForRetry: { try await clock.wait() })
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-mascot-corrupt-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("invalid image".utf8).write(to: url)
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let observer = cache.objectWillChange.sink { continuation.yield(()) }
        defer { observer.cancel(); continuation.finish() }
        var iterator = changes.makeAsyncIterator()

        #expect(cache.image(for: "corrupt", url: { url }) == nil)
        await clock.scheduled()
        try writePNG(size: 12, to: url)
        await clock.advance()
        await iterator.next()

        #expect(cache.image(for: "corrupt", url: { nil })?.size.width == 12)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsImageWithoutDrawableRepresentation() async throws {
        let clock = AIMascotRetryClock()
        let cache = AIMascotImageCache(waitForRetry: { try await clock.wait() })
        let state = AIMascotImageState(image: NSImage(size: NSSize(width: 12, height: 12)))
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let observer = cache.objectWillChange.sink { continuation.yield(()) }
        defer { observer.cancel(); continuation.finish() }
        var iterator = changes.makeAsyncIterator()

        #expect(cache.image(for: "undrawable", load: { state.image }) == nil)
        await clock.scheduled()
        state.image = makeImage(size: 12)
        await clock.advance()
        await iterator.next()

        #expect(cache.image(for: "undrawable", load: { nil })?.size.width == 12)
    }

    @Test(.timeLimit(.minutes(1)))
    func notifiesAllSameSourceObserversOnRecovery() async throws {
        let clock = AIMascotRetryClock()
        let cache = AIMascotImageCache(waitForRetry: { try await clock.wait() })
        let expected = makeImage(size: 12)
        let state = AIMascotImageState()
        var firstUpdates = 0
        var secondUpdates = 0
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let firstObserver = cache.objectWillChange.sink {
            firstUpdates += 1
            continuation.yield(())
        }
        let secondObserver = cache.objectWillChange.sink { secondUpdates += 1 }
        defer { firstObserver.cancel(); secondObserver.cancel(); continuation.finish() }
        var iterator = changes.makeAsyncIterator()

        #expect(cache.image(for: "shared", load: { state.available ? expected : nil }) == nil)
        await clock.scheduled()
        #expect(cache.image(for: "shared", load: { expected }) == nil)
        #expect(firstUpdates == 0)
        #expect(secondUpdates == 0)

        state.available = true
        await clock.advance()
        await iterator.next()
        let firstImage = cache.image(for: "shared", load: { nil })
        let secondImage = cache.image(for: "shared", load: { nil })
        let first = try #require(firstImage)
        let second = try #require(secondImage)

        #expect(first === second)
        #expect(firstUpdates == 1)
        #expect(secondUpdates == 1)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func cancelsPendingRetryWhenCacheIsReleased(afterFailedRetry: Bool) async {
        let clock = AIMascotRetryClock()
        var cache: AIMascotImageCache? = AIMascotImageCache(waitForRetry: { try await clock.wait() })
        let releasedCache = WeakAIMascotImageCacheReference(cache!)

        #expect(cache?.image(for: "cancelled", load: { nil }) == nil)
        await clock.scheduled()
        if afterFailedRetry {
            await clock.advance()
            await clock.scheduled()
        }
        cache = nil
        #expect(releasedCache.value == nil)
        await clock.cancelled()

        #expect(clock.cancellationCount == 1)
    }
}

@MainActor
private final class AIMascotImageState {
    var available: Bool
    var image: NSImage?

    init(available: Bool = false, image: NSImage? = nil) {
        self.available = available
        self.image = image
    }
}

@MainActor
private final class WeakAIMascotImageCacheReference {
    weak var value: AIMascotImageCache?

    init(_ value: AIMascotImageCache) {
        self.value = value
    }
}

@MainActor
private final class AIMascotRetryClock {
    private var pending: [CheckedContinuation<Void, any Error>] = []
    private var scheduleWaiter: CheckedContinuation<Void, Never>?
    private var cancellationWaiter: CheckedContinuation<Void, Never>?
    private(set) var cancellationCount = 0

    func wait() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.append(continuation)
                scheduleWaiter?.resume()
                scheduleWaiter = nil
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cancellationCount += 1
                let pending = self.pending
                self.pending.removeAll()
                for continuation in pending { continuation.resume(throwing: CancellationError()) }
                self.cancellationWaiter?.resume()
                self.cancellationWaiter = nil
            }
        }
    }

    func scheduled() async {
        if !pending.isEmpty { return }
        await withCheckedContinuation { scheduleWaiter = $0 }
    }

    func advance() async {
        await scheduled()
        pending.removeFirst().resume()
    }

    func cancelled() async {
        if cancellationCount > 0 { return }
        await withCheckedContinuation { cancellationWaiter = $0 }
    }
}

@MainActor
private func makeImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSColor.red.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: NSSize(width: size, height: size))).fill()
    image.unlockFocus()
    return image
}

@MainActor
private func writePNG(size: CGFloat, to url: URL) throws {
    let image = makeImage(size: size)
    guard let tiff = image.tiffRepresentation,
          let representation = NSBitmapImageRep(data: tiff),
          let data = representation.representation(using: .png, properties: [:]) else {
        throw AIMascotFixtureError.encodingFailed
    }
    try data.write(to: url)
}

private enum AIMascotFixtureError: Error {
    case encodingFailed
}
