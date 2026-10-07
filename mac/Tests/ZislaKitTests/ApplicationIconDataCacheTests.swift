import AppKit
import Testing

@testable import ZislaKit

@MainActor
struct ApplicationIconDataCacheTests {
    @Test
    func keepsSuccessfulIconWhenTheNextLoadIsUnavailable() throws {
        let cache = ApplicationIconDataCache(genericIcons: [])
        let image = try #require(makeImage(pixelSize: 64))
        let expectedValue = cache.data(for: "app", load: { [image] })
        let expected = try #require(expectedValue)

        #expect(cache.data(for: "app", load: { [] }) == expected)
    }

    @Test
    func genericPlaceholderDoesNotMaskAValidCandidate() throws {
        let placeholder = try #require(makeInsetImage())
        let image = try #require(makeImage(pixelSize: 64))
        let cache = ApplicationIconDataCache(genericIcons: [placeholder])
        let expectedValue = cache.data(for: "expected", load: { [image] })
        let expected = try #require(expectedValue)

        #expect(cache.data(for: "app", load: { [placeholder, image] }) == expected)
        #expect(cache.data(for: "app", load: { [placeholder] }) == expected)
    }

    @Test(arguments: [false, true])
    func blankCandidateDoesNotMaskAValidFallback(hasRepresentation: Bool) throws {
        let blank = NSImage(size: NSSize(width: 64, height: 64))
        if hasRepresentation {
            blank.addRepresentation(try #require(makeBitmap(pixelSize: 64)))
        }
        let image = try #require(makeImage(pixelSize: 64))
        let cache = ApplicationIconDataCache(genericIcons: [])
        let expectedValue = cache.data(for: "expected", load: { [image] })
        let expected = try #require(expectedValue)

        #expect(cache.data(for: "app", load: { [blank, image] }) == expected)
    }

    @Test(.timeLimit(.minutes(1)), arguments: IconLoadFailure.allCases)
    func retriesInvalidOrUnavailableIconsWithoutPoisoningCache(failure: IconLoadFailure) async throws {
        let clock = ApplicationIconRetryClock()
        let placeholder = try #require(makeInsetImage())
        let image = try #require(makeImage(pixelSize: 64))
        let cache = ApplicationIconDataCache(
            genericIcons: [placeholder],
            waitForRetry: { try await clock.wait() }
        )
        defer { cache.cancelPendingRetries() }
        let expectedValue = cache.data(for: "expected", load: { [image] })
        let expected = try #require(expectedValue)
        var images: [NSImage] = []
        switch failure {
        case .unavailable: break
        case .undrawable: images = [NSImage(size: NSSize(width: 64, height: 64))]
        case .transparent:
            let blank = NSImage(size: NSSize(width: 64, height: 64))
            blank.addRepresentation(try #require(makeBitmap(pixelSize: 64)))
            images = [blank]
        case .placeholder: images = [placeholder]
        }
        var changes: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: ApplicationIconDataCache.didCacheIconNotification,
            object: cache,
            queue: .main
        ) { notification in
            let key = notification.userInfo?["cacheKey"] as? String ?? ""
            MainActor.assumeIsolated { changes.append(key) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        var loadCount = 0

        let initial = cache.data(for: "app", load: { loadCount += 1; return images })
        try #require(initial == nil)
        await clock.scheduled(1)
        #expect(cache.data(for: "app", load: { [image] }) == nil)
        #expect(loadCount == 1)
        try clock.advance()
        await clock.completed(1)
        try #require(clock.scheduledCount == 2)
        #expect(loadCount == 2)
        #expect(changes.isEmpty)

        images = [image]
        try clock.advance()
        await clock.completed(2)
        #expect(changes == ["app"])
        #expect(cache.data(for: "app", load: { [] }) == expected)
        #expect(loadCount == 3)
        #expect(clock.scheduledCount == 2)
    }

    @Test
    func keepsDifferentApplicationsSeparate() throws {
        let cache = ApplicationIconDataCache(genericIcons: [])
        let first = try #require(makeImage(pixelSize: 64))
        let second = try #require(makeInsetImage())
        let firstDataValue = cache.data(for: "first", load: { [first] })
        let firstData = try #require(firstDataValue)
        let secondDataValue = cache.data(for: "second", load: { [second] })
        let secondData = try #require(secondDataValue)

        #expect(firstData != secondData)
        #expect(cache.data(for: "first", load: { [] }) == firstData)
        #expect(cache.data(for: "second", load: { [first] }) == secondData)
        #expect(cache.data(for: "uncached", load: { [] }) == nil)
        cache.cancelPendingRetries()
    }

    @Test
    func prefersOfficialBundleIconOverProcessIcon() throws {
        let expectedImage = try #require(makeImage(pixelSize: 64))
        let helperImage = try #require(makeInsetImage())
        let officialURL = URL(fileURLWithPath: "/fake/Player.app")
        let helperURL = URL(fileURLWithPath: "/fake/Helper.app")
        let cache = ApplicationIconDataCache(
            genericIcons: [],
            applicationURL: { bundle in bundle == "test.player" ? officialURL : nil },
            fileIcon: { url in url == officialURL ? expectedImage : helperImage },
            runningApplication: { _ in ("test.player", helperImage) }
        )
        let expectedValue = cache.data(for: "expected", load: { [expectedImage] })
        let expected = try #require(expectedValue)
        let data = cache.data(
            forApplication: "test.player",
            bundleIdentifier: "test.player",
            processIdentifier: 42,
            applicationURL: helperURL
        )

        #expect(data == expected)
    }

    @Test(arguments: [false, true])
    func fallsBackWhenTheOfficialBundleIconIsUnavailable(isPlaceholder: Bool) throws {
        let placeholder = try #require(makeInsetImage())
        let image = try #require(makeImage(pixelSize: 64))
        let cache = ApplicationIconDataCache(
            genericIcons: [placeholder],
            applicationURL: { _ in URL(fileURLWithPath: "/fake/Player.app") },
            fileIcon: { _ in isPlaceholder ? placeholder : nil },
            runningApplication: { pid in pid == 42 ? ("test.player", image) : nil }
        )
        let expectedValue = cache.data(for: "expected", load: { [image] })
        let expected = try #require(expectedValue)

        #expect(cache.data(
            forApplication: "test.player",
            bundleIdentifier: "test.player",
            processIdentifier: 42
        ) == expected)
    }

    @Test
    func loadsOuterApplicationWhenBundleLookupIsUnavailable() throws {
        let image = try #require(makeImage(pixelSize: 64))
        let outerURL = URL(fileURLWithPath: "/fake/Outer.app")
        let cache = ApplicationIconDataCache(
            genericIcons: [],
            applicationURL: { _ in nil },
            fileIcon: { url in url == outerURL ? image : nil },
            runningApplication: { _ in nil }
        )
        let expectedValue = cache.data(for: "expected", load: { [image] })
        let expected = try #require(expectedValue)

        #expect(cache.data(
            forApplication: "path:/fake/Outer.app",
            bundleIdentifier: nil,
            processIdentifier: 42,
            applicationURL: outerURL
        ) == expected)
    }

    @Test(.timeLimit(.minutes(1)))
    func rechecksApplicationLocationAfterTransientFailure() async throws {
        let clock = ApplicationIconRetryClock()
        let image = try #require(makeImage(pixelSize: 64))
        var available = false
        let cache = ApplicationIconDataCache(
            genericIcons: [],
            waitForRetry: { try await clock.wait() },
            applicationURL: { _ in available ? URL(fileURLWithPath: "/fake/Player.app") : nil },
            fileIcon: { _ in image },
            runningApplication: { _ in nil }
        )
        defer { cache.cancelPendingRetries() }
        let expectedValue = cache.data(for: "expected", load: { [image] })
        let expected = try #require(expectedValue)
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(
            forName: ApplicationIconDataCache.didCacheIconNotification,
            object: cache,
            queue: .main
        ) { _ in MainActor.assumeIsolated { notifications += 1 } }
        defer { NotificationCenter.default.removeObserver(observer) }

        #expect(cache.data(forApplication: "test.player", bundleIdentifier: "test.player", processIdentifier: 42) == nil)
        await clock.scheduled(1)
        available = true
        try clock.advance()
        await clock.completed(1)

        #expect(notifications == 1)
        #expect(cache.data(for: "test.player", load: { [] }) == expected)
    }

    @Test
    func acceptsProcessIconWhenNoBundleIdentifierIsAvailable() throws {
        let image = try #require(makeImage(pixelSize: 64))
        let cache = ApplicationIconDataCache(
            genericIcons: [],
            runningApplication: { pid in pid == 42 ? (nil, image) : nil }
        )
        let expectedValue = cache.data(for: "expected", load: { [image] })
        let expected = try #require(expectedValue)

        #expect(cache.data(
            forApplication: "pid:42",
            bundleIdentifier: nil,
            processIdentifier: 42
        ) == expected)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsAProcessIdentifierReusedByAnotherApplicationDuringRetry() async throws {
        let clock = ApplicationIconRetryClock()
        let image = try #require(makeImage(pixelSize: 64))
        var application: (bundleIdentifier: String?, icon: NSImage?)? = ("test.player", nil)
        let cache = ApplicationIconDataCache(
            genericIcons: [],
            waitForRetry: { try await clock.wait() },
            applicationURL: { _ in nil },
            runningApplication: { _ in application }
        )
        defer { cache.cancelPendingRetries() }
        let expectedValue = cache.data(for: "expected", load: { [image] })
        let expected = try #require(expectedValue)

        let initial = cache.data(
            forApplication: "test.player",
            bundleIdentifier: "test.player",
            processIdentifier: 42
        )
        try #require(initial == nil)
        await clock.scheduled(1)
        application = ("test.other", image)
        try clock.advance()
        await clock.completed(1)
        try #require(clock.scheduledCount == 2)
        #expect(cache.data(for: "test.player", load: { [image] }) == nil)

        application = ("test.player", image)
        try clock.advance()
        await clock.completed(2)
        #expect(cache.data(for: "test.player", load: { [] }) == expected)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingRetriesPreservesSuccessfulValuesAndAllowsImmediateReload() async throws {
        let clock = ApplicationIconRetryClock(honorsCancellation: false)
        let image = try #require(makeImage(pixelSize: 64))
        let cache = ApplicationIconDataCache(genericIcons: [], waitForRetry: { try await clock.wait() })
        defer { cache.cancelPendingRetries() }
        let expectedValue = cache.data(for: "successful", load: { [image] })
        let expected = try #require(expectedValue)
        var reloads = 0

        #expect(cache.data(for: "pending", load: { reloads += 1; return [] }) == nil)
        await clock.scheduled(1)
        cache.cancelPendingRetries()
        #expect(cache.data(for: "pending", load: { [image] }) == expected)
        #expect(cache.data(for: "successful", load: { [] }) == expected)
        try clock.advance()
        await clock.completed(1)

        #expect(clock.cancellationCount == 1)
        #expect(reloads == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func failedRetryWaitAllowsAFreshLoad() async throws {
        let clock = ApplicationIconRetryClock()
        let image = try #require(makeImage(pixelSize: 64))
        let cache = ApplicationIconDataCache(genericIcons: [], waitForRetry: { try await clock.wait() })
        defer { cache.cancelPendingRetries() }
        let expectedValue = cache.data(for: "expected", load: { [image] })
        let expected = try #require(expectedValue)

        #expect(cache.data(for: "app", load: { [] }) == nil)
        await clock.scheduled(1)
        try clock.advance(throwing: CancellationError())
        await clock.completed(1)
        #expect(cache.data(for: "app", load: { [image] }) == expected)
    }

    @Test(.timeLimit(.minutes(1)))
    func lateCancelledRetryCannotClearOrOverwriteNewRetry() async throws {
        let clock = ApplicationIconRetryClock(honorsCancellation: false)
        let image = try #require(makeImage(pixelSize: 64))
        let staleImage = try #require(makeInsetImage())
        let cache = ApplicationIconDataCache(genericIcons: [], waitForRetry: { try await clock.wait() })
        defer { cache.cancelPendingRetries() }
        let expectedValue = cache.data(for: "expected", load: { [image] })
        let expected = try #require(expectedValue)
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(
            forName: ApplicationIconDataCache.didCacheIconNotification,
            object: cache,
            queue: .main
        ) { _ in MainActor.assumeIsolated { notifications += 1 } }
        defer { NotificationCenter.default.removeObserver(observer) }
        var staleImages: [NSImage] = []
        var newImages: [NSImage] = []
        var staleLoads = 0
        var newLoads = 0

        #expect(cache.data(for: "app", load: { staleLoads += 1; return staleImages }) == nil)
        await clock.scheduled(1)
        cache.cancelPendingRetries()
        #expect(cache.data(for: "app", load: { newLoads += 1; return newImages }) == nil)
        await clock.scheduled(2)
        try #require(newLoads == 1)
        staleImages = [staleImage]
        try clock.advance()
        await clock.completed(1)
        #expect(staleLoads == 1)
        #expect(clock.cancellationCount == 1)
        #expect(notifications == 0)
        #expect(cache.data(for: "app", load: { [staleImage] }) == nil)
        #expect(newLoads == 1)

        newImages = [image]
        try clock.advance()
        await clock.completed(2)
        #expect(notifications == 1)
        #expect(cache.data(for: "app", load: { [] }) == expected)
        #expect(newLoads == 2)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func releasesAndCancelsTheCacheWithAPendingRetry(afterFailure: Bool) async throws {
        let clock = ApplicationIconRetryClock(honorsCancellation: false)
        var cache: ApplicationIconDataCache? = ApplicationIconDataCache(
            genericIcons: [],
            waitForRetry: { try await clock.wait() },
            applicationURL: { _ in nil },
            runningApplication: { _ in nil }
        )
        weak var released = cache

        #expect(cache?.data(
            forApplication: "test.player",
            bundleIdentifier: "test.player",
            processIdentifier: 42
        ) == nil)
        await clock.scheduled(1)
        if afterFailure {
            try clock.advance()
            await clock.scheduled(2)
        }
        cache = nil
        #expect(released == nil)
        try clock.advance()
        await clock.completed(afterFailure ? 2 : 1)
        #expect(clock.cancellationCount == 1)
    }

    @Test
    func preservesFaintBlackPixels() throws {
        let bitmap = try #require(makeBitmap(pixelSize: 128))
        for y in 0..<128 {
            for x in 0..<128 {
                bitmap.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1.0 / 255), atX: x, y: y)
            }
        }
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        let cache = ApplicationIconDataCache(genericIcons: [])
        let dataValue = cache.data(for: "faint", load: { [image] })
        let data = try #require(dataValue)
        let rendered = try #require(NSBitmapImageRep(data: data))

        #expect((rendered.colorAt(x: 64, y: 64)?.alphaComponent ?? 0) > 0)
    }

    @Test
    func rendersOneBoundedPNGAndReusesIt() throws {
        let cache = ApplicationIconDataCache(genericIcons: [])
        let image = try #require(makeImage(pixelSize: 512))
        let firstValue = cache.data(for: "app", load: { [image] })
        let first = try #require(firstValue)
        let secondValue = cache.data(for: "app", load: { [image] })
        let second = try #require(secondValue)
        let representation = try #require(NSBitmapImageRep(data: first))

        #expect(representation.pixelsWide == 128)
        #expect(representation.pixelsHigh == 128)
        #expect(representation.size == NSSize(width: 64, height: 64))
        #expect(first == second)
        #expect(first.count < 128 * 128 * 4)
    }

    @Test(arguments: [64, 128, 512])
    func renderedIconFillsTheEntireRetinaCanvas(sourcePixelSize: Int) throws {
        let image = try #require(makeImage(pixelSize: sourcePixelSize))
        let cache = ApplicationIconDataCache(genericIcons: [])
        let dataValue = cache.data(for: "app", load: { [image] })
        let data = try #require(dataValue)
        let representation = try #require(NSBitmapImageRep(data: data))
        var opaquePixels = 0
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                if let color = representation.colorAt(x: x, y: y), color.alphaComponent > 0.99 {
                    opaquePixels += 1
                }
            }
        }

        #expect(representation.pixelsWide == 128)
        #expect(representation.pixelsHigh == 128)
        #expect(opaquePixels == 128 * 128)
    }

    @Test
    func preservesTransparentInsetsAtRetinaScale() throws {
        let image = try #require(makeInsetImage())
        let cache = ApplicationIconDataCache(genericIcons: [])
        let dataValue = cache.data(for: "app", load: { [image] })
        let data = try #require(dataValue)
        let representation = try #require(NSBitmapImageRep(data: data))
        let bounds = try #require(opaqueBounds(in: representation))

        #expect((31...33).contains(Int(bounds.minX)))
        #expect((31...33).contains(Int(bounds.minY)))
        #expect((62...66).contains(Int(bounds.width)))
        #expect((62...66).contains(Int(bounds.height)))
    }

    private func makeImage(pixelSize: Int) -> NSImage? {
        guard let bitmap = makeBitmap(pixelSize: pixelSize) else { return nil }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()
        context.flushGraphics()

        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func makeBitmap(pixelSize: Int) -> NSBitmapImageRep? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: pixelSize, height: pixelSize)
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        return bitmap
    }

    private func makeInsetImage() -> NSImage? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 64,
            pixelsHigh: 64,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: 64, height: 64)
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor(deviceRed: 1, green: 0, blue: 0.5, alpha: 1).setFill()
        NSRect(x: 16, y: 16, width: 32, height: 32).fill()
        context.flushGraphics()

        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func opaqueBounds(in representation: NSBitmapImageRep) -> NSRect? {
        var minX = representation.pixelsWide
        var minY = representation.pixelsHigh
        var maxX = -1
        var maxY = -1
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                guard let color = representation.colorAt(x: x, y: y), color.alphaComponent > 0.99 else {
                    continue
                }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return NSRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }
}

enum IconLoadFailure: CaseIterable, Sendable {
    case unavailable
    case undrawable
    case transparent
    case placeholder
}

@MainActor
final class ApplicationIconRetryClock {
    private let honorsCancellation: Bool
    private var pending: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var scheduledWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cancellationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var completedWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var scheduledCount = 0
    private(set) var cancellationCount = 0
    private var completedCount = 0

    init(honorsCancellation: Bool = true) {
        self.honorsCancellation = honorsCancellation
    }

    func wait() async throws {
        let id = scheduledCount
        defer {
            completedCount += 1
            resume(&completedWaiters, count: completedCount)
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                scheduledCount += 1
                resume(&scheduledWaiters, count: scheduledCount)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cancellationCount += 1
                self.resume(&self.cancellationWaiters, count: self.cancellationCount)
                if self.honorsCancellation {
                    self.pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
                }
            }
        }
    }

    func scheduled(_ count: Int) async {
        if scheduledCount >= count { return }
        await withCheckedContinuation { scheduledWaiters.append((count, $0)) }
    }

    func cancelled(_ count: Int) async {
        if cancellationCount >= count { return }
        await withCheckedContinuation { cancellationWaiters.append((count, $0)) }
    }

    func completed(_ count: Int) async {
        if completedCount >= count { return }
        await withCheckedContinuation { completedWaiters.append((count, $0)) }
    }

    func advance(throwing error: (any Error)? = nil) throws {
        let id = try #require(pending.keys.min())
        if let error {
            pending.removeValue(forKey: id)?.resume(throwing: error)
        } else {
            pending.removeValue(forKey: id)?.resume()
        }
    }

    private func resume(_ waiters: inout [(Int, CheckedContinuation<Void, Never>)], count: Int) {
        for (expected, continuation) in waiters where expected <= count { continuation.resume() }
        waiters.removeAll { $0.0 <= count }
    }
}
