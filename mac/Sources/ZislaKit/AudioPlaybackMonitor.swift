import AppKit
import CoreAudio
import Darwin
import Foundation
import UniformTypeIdentifiers

public struct AudioPlaybackSource: Equatable, Identifiable, Sendable {
    public var id: String
    public var processIdentifiers: [pid_t]
    public var bundleIdentifier: String?
    public var applicationName: String
    public var iconData: Data?
    public var isFrontmost: Bool

    public init(
        id: String,
        processIdentifiers: [pid_t],
        bundleIdentifier: String?,
        applicationName: String,
        iconData: Data?,
        isFrontmost: Bool
    ) {
        self.id = id
        self.processIdentifiers = processIdentifiers
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.iconData = iconData
        self.isFrontmost = isFrontmost
    }
}

@MainActor
final class ApplicationIconDataCache {
    static let shared = ApplicationIconDataCache()
    static let didCacheIconNotification = Notification.Name("ApplicationIconDataCacheDidCacheIcon")

    private static let pixelSize = 128
    private static let pointSize = 64
    private let cache = NSCache<NSString, NSData>()
    private let genericIconData: [Data]
    private let waitForRetry: @MainActor () async throws -> Void
    private let applicationURL: @MainActor (String) -> URL?
    private let fileIcon: @MainActor (URL) -> NSImage?
    private let runningApplication: @MainActor (pid_t) -> (bundleIdentifier: String?, icon: NSImage?)?
    private var retries: [String: Task<Void, Never>] = [:]
    private var retryGeneration: UInt64 = 0

    init(
        genericIcons: [NSImage] = [
            NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"),
            NSWorkspace.shared.icon(for: .application),
            NSWorkspace.shared.icon(for: .applicationBundle),
        ].compactMap { $0 },
        waitForRetry: @escaping @MainActor () async throws -> Void = {
            try await Task.sleep(for: .seconds(1))
        },
        applicationURL: @escaping @MainActor (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        fileIcon: @escaping @MainActor (URL) -> NSImage? = {
            NSWorkspace.shared.icon(forFile: $0.path)
        },
        runningApplication: @escaping @MainActor (pid_t) -> (bundleIdentifier: String?, icon: NSImage?)? = { pid in
            guard let application = NSRunningApplication(processIdentifier: pid) else { return nil }
            return (application.bundleIdentifier, application.icon)
        }
    ) {
        genericIconData = genericIcons.compactMap { Self.renderPNG(from: $0) }
        self.waitForRetry = waitForRetry
        self.applicationURL = applicationURL
        self.fileIcon = fileIcon
        self.runningApplication = runningApplication
        cache.countLimit = 64
        cache.totalCostLimit = 2 * 1_024 * 1_024
    }

    deinit {
        for retry in retries.values { retry.cancel() }
    }

    func data(for cacheKey: String, load: @escaping @MainActor () -> [NSImage]) -> Data? {
        let key = cacheKey as NSString
        if let cached = cache.object(forKey: key) {
            return cached as Data
        }
        guard retries[cacheKey] == nil else { return nil }
        if let data = validData(from: load()) {
            cache.setObject(data as NSData, forKey: key, cost: data.count)
            return data
        }

        let waitForRetry = waitForRetry
        let generation = retryGeneration
        retries[cacheKey] = Task { [weak self] in
            defer {
                if self?.retryGeneration == generation { self?.retries[cacheKey] = nil }
            }
            while true {
                do {
                    try await waitForRetry()
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                if let data = self.validData(from: load()) {
                    self.cache.setObject(data as NSData, forKey: key, cost: data.count)
                    NotificationCenter.default.post(
                        name: Self.didCacheIconNotification,
                        object: self,
                        userInfo: ["cacheKey": cacheKey]
                    )
                    return
                }
            }
        }
        return nil
    }

    func data(
        forApplication cacheKey: String,
        bundleIdentifier: String?,
        processIdentifier: pid_t?,
        applicationURL fallbackURL: URL? = nil
    ) -> Data? {
        let applicationURL = applicationURL
        let fileIcon = fileIcon
        let runningApplication = runningApplication
        return data(for: cacheKey) {
            var images: [NSImage] = []
            if let url = bundleIdentifier.flatMap(applicationURL) ?? fallbackURL,
               let icon = fileIcon(url) {
                images.append(icon)
            }
            if let processIdentifier, let application = runningApplication(processIdentifier),
               bundleIdentifier == nil || application.bundleIdentifier == bundleIdentifier,
               let icon = application.icon {
                images.append(icon)
            }
            return images
        }
    }

    func cancelPendingRetries() {
        retryGeneration &+= 1
        for retry in retries.values { retry.cancel() }
        retries.removeAll()
    }

    private func validData(from images: [NSImage]) -> Data? {
        for image in images {
            if let data = Self.renderPNG(from: image), !genericIconData.contains(data) { return data }
        }
        return nil
    }

    private static func renderPNG(from image: NSImage) -> Data? {
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
        let targetRect = NSRect(x: 0, y: 0, width: pointSize, height: pointSize)
        bitmap.size = targetRect.size
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.clear(targetRect)
        image.draw(
            in: targetRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: nil
        )
        context.flushGraphics()
        guard let pixels = bitmap.bitmapData,
              stride(from: 3, to: bitmap.bytesPerRow * bitmap.pixelsHigh, by: 4)
                .contains(where: { pixels[$0] != 0 }) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

@MainActor
final class AudioPlaybackMonitor {
    private(set) var sources: [AudioPlaybackSource] = []
    var onSourcesChanged: (@MainActor ([AudioPlaybackSource]) -> Void)?

    var isSupported: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    private var isRunning = false
    private var observedProcesses: Set<AudioObjectID> = []
    private var applicationActivationObserver: NSObjectProtocol?
    private var preferredSourceID: String?

    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated {
            self?.refresh()
        }
    }

    func start() {
        guard !isRunning, #available(macOS 14.4, *) else { return }
        isRunning = true

        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        _ = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            .main,
            listener
        )
        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh()
                self.prioritizeSource(for: NSWorkspace.shared.frontmostApplication)
            }
        }
        refresh()
    }

    func stop() {
        guard isRunning, #available(macOS 14.4, *) else { return }
        isRunning = false

        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        _ = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            .main,
            listener
        )
        if let applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationActivationObserver)
            self.applicationActivationObserver = nil
        }
        for object in observedProcesses {
            removeListener(from: object)
        }
        observedProcesses.removeAll()
        preferredSourceID = nil
        updateSources([])
    }

    func refresh() {
        guard #available(macOS 14.4, *) else { return }
        let objects = Self.processList()
        if isRunning { rebuildListeners(for: Set(objects)) }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let activePIDs = objects.compactMap { object -> pid_t? in
            guard Self.isRunningOutput(object), let pid = Self.pid(of: object), pid != ownPID else {
                return nil
            }
            return pid
        }
        var resolved = Self.resolveSources(for: activePIDs)
        applyPreferredSource(to: &resolved)
        updateSources(resolved)
    }

    private func prioritizeSource(for application: NSRunningApplication?) {
        preferredSourceID = Self.sourceID(
            processIdentifier: application?.processIdentifier,
            bundleIdentifier: application?.bundleIdentifier,
            sources: sources
        )
        var resolved = sources
        applyPreferredSource(to: &resolved)
        updateSources(resolved)
    }

    nonisolated static func sourceID(
        processIdentifier: pid_t?,
        bundleIdentifier: String?,
        sources: [AudioPlaybackSource]
    ) -> String? {
        if let processIdentifier,
           let source = sources.first(where: {
               $0.processIdentifiers.contains(processIdentifier)
           })
        {
            return source.id
        }
        if let bundleIdentifier,
           let source = sources.first(where: { $0.bundleIdentifier == bundleIdentifier })
        {
            return source.id
        }
        return nil
    }

    private func applyPreferredSource(to resolved: inout [AudioPlaybackSource]) {
        if let preferredSourceID,
           resolved.contains(where: { $0.id == preferredSourceID }) {
            for index in resolved.indices {
                resolved[index].isFrontmost = resolved[index].id == preferredSourceID
            }
            resolved.sort {
                if $0.isFrontmost != $1.isFrontmost { return $0.isFrontmost }
                return $0.applicationName.localizedStandardCompare($1.applicationName)
                    == .orderedAscending
            }
        } else if preferredSourceID != nil {
            self.preferredSourceID = nil
        }
    }

    private func updateSources(_ next: [AudioPlaybackSource]) {
        guard next != sources else { return }
        sources = next
        onSourcesChanged?(next)
    }

    @available(macOS 14.4, *)
    private func rebuildListeners(for current: Set<AudioObjectID>) {
        for object in current.subtracting(observedProcesses) {
            var address = Self.address(kAudioProcessPropertyIsRunningOutput)
            guard AudioObjectHasProperty(object, &address) else { continue }
            if AudioObjectAddPropertyListenerBlock(object, &address, .main, listener) == noErr {
                observedProcesses.insert(object)
            }
        }
        for object in observedProcesses.subtracting(current) {
            removeListener(from: object)
            observedProcesses.remove(object)
        }
    }

    @available(macOS 14.4, *)
    private func removeListener(from object: AudioObjectID) {
        var address = Self.address(kAudioProcessPropertyIsRunningOutput)
        _ = AudioObjectRemovePropertyListenerBlock(object, &address, .main, listener)
    }

    @available(macOS 14.4, *)
    nonisolated private static func processList() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else {
            return []
        }
        return objects
    }

    nonisolated static func currentProcessObjectIDs() -> [AudioObjectID] {
        guard #available(macOS 14.4, *) else { return [] }
        return processObjectIDs(
            from: processList(),
            matching: ProcessInfo.processInfo.processIdentifier,
            processIdentifier: pid(of:)
        )
    }

    nonisolated static func processObjectIDs(
        from objects: [AudioObjectID],
        matching targetProcessIdentifier: pid_t,
        processIdentifier: (AudioObjectID) -> pid_t?
    ) -> [AudioObjectID] {
        objects.filter { processIdentifier($0) == targetProcessIdentifier }
    }

    @available(macOS 14.4, *)
    private static func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var address = Self.address(kAudioProcessPropertyIsRunningOutput)
        guard AudioObjectHasProperty(object, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
            && value != 0
    }

    @available(macOS 14.4, *)
    nonisolated private static func pid(of object: AudioObjectID) -> pid_t? {
        var address = Self.address(kAudioProcessPropertyPID)
        var value: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              value > 0 else { return nil }
        return value
    }

    private static func resolveSources(for pids: [pid_t]) -> [AudioPlaybackSource] {
        var grouped: [String: AudioPlaybackSource] = [:]
        for pid in Set(pids) {
            guard let source = source(for: pid) else { continue }
            if var existing = grouped[source.id] {
                existing.processIdentifiers.append(pid)
                existing.processIdentifiers.sort()
                existing.isFrontmost = existing.isFrontmost || source.isFrontmost
                if existing.iconData == nil { existing.iconData = source.iconData }
                grouped[source.id] = existing
            } else {
                grouped[source.id] = source
            }
        }
        return grouped.values.sorted {
            if $0.isFrontmost != $1.isFrontmost { return $0.isFrontmost }
            return $0.applicationName.localizedStandardCompare($1.applicationName) == .orderedAscending
        }
    }

    private static func source(for pid: pid_t) -> AudioPlaybackSource? {
        let running = NSRunningApplication(processIdentifier: pid)
        let executablePath = processPath(pid)
        let outerApplicationURL = executablePath.flatMap(applicationURL(in:))
        let bundle = outerApplicationURL.flatMap(Bundle.init(url:))
        let bundleIdentifier = bundle?.bundleIdentifier ?? running?.bundleIdentifier
        let applicationName = displayName(bundle: bundle)
            ?? running?.localizedName
            ?? processName(pid)
        guard let applicationName, !applicationName.isEmpty else { return nil }

        let id = bundleIdentifier ?? outerApplicationURL?.path ?? "pid:\(pid)"
        let frontmost = NSWorkspace.shared.frontmostApplication.map {
            $0.processIdentifier == pid
                || (bundleIdentifier != nil && $0.bundleIdentifier == bundleIdentifier)
        } ?? false
        return AudioPlaybackSource(
            id: id,
            processIdentifiers: [pid],
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            iconData: ApplicationIconDataCache.shared.data(
                forApplication: id,
                bundleIdentifier: bundleIdentifier,
                processIdentifier: pid,
                applicationURL: outerApplicationURL
            ),
            isFrontmost: frontmost
        )
    }

    private static func displayName(bundle: Bundle?) -> String? {
        bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
    }

    private static func processPath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return string(from: buffer)
    }

    private static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return string(from: buffer)
    }

    private static func string(from buffer: [CChar]) -> String {
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        return String(decoding: buffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func applicationURL(in executablePath: String) -> URL? {
        let components = URL(fileURLWithPath: executablePath).pathComponents
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else {
            return nil
        }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(components[...index])))
    }

    nonisolated private static func address(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
