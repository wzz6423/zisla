import AppKit
import CoreAudio
import Darwin
import Foundation

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
enum ApplicationIconDataCache {
    private static let pixelSize = 64
    private static let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 64
        cache.totalCostLimit = 2 * 1_024 * 1_024
        return cache
    }()

    static func data(for image: NSImage?, cacheKey: String) -> Data? {
        guard let image else { return nil }
        let key = cacheKey as NSString
        if let cached = cache.object(forKey: key) {
            return cached as Data
        }
        guard let data = renderPNG(from: image) else { return nil }
        cache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
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
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        let targetRect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        bitmap.size = targetRect.size
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
                let application = NSWorkspace.shared.frontmostApplication
                self.prioritizeSource(for: application)
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
        guard let application,
              let activatedSource = sources.first(where: {
                  $0.processIdentifiers.contains(application.processIdentifier)
                      || ($0.bundleIdentifier != nil
                          && $0.bundleIdentifier == application.bundleIdentifier)
              }) else { return }
        preferredSourceID = activatedSource.id
        var resolved = sources
        applyPreferredSource(to: &resolved)
        updateSources(resolved)
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
    private static func processList() -> [AudioObjectID] {
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
    private static func pid(of object: AudioObjectID) -> pid_t? {
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
        let icon = running?.icon
            ?? outerApplicationURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        let frontmost = NSWorkspace.shared.frontmostApplication.map {
            $0.processIdentifier == pid
                || (bundleIdentifier != nil && $0.bundleIdentifier == bundleIdentifier)
        } ?? false
        return AudioPlaybackSource(
            id: id,
            processIdentifiers: [pid],
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            iconData: ApplicationIconDataCache.data(for: icon, cacheKey: id),
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

    private static func address(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
