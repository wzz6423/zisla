import Combine
import Darwin
import Foundation
import ObjectiveC.runtime

public struct FocusModePresentation: Equatable, Sendable {
    public var title: String
    public var symbolName: String

    public init(title: String, symbolName: String) {
        self.title = title
        self.symbolName = symbolName
    }
}

public struct FocusModeStatus: Equatable, Sendable {
    public var isActive: Bool
    public var identifier: String?
    public var displayName: String?

    public init(
        isActive: Bool,
        identifier: String? = nil,
        displayName: String? = nil
    ) {
        self.isActive = isActive
        self.identifier = Self.nonEmpty(identifier)
        self.displayName = Self.nonEmpty(displayName)
    }

    public static let inactive = FocusModeStatus(isActive: false)

    public var presentation: FocusModePresentation {
        let knownMode = Self.knownMode(for: identifier)
        return FocusModePresentation(
            title: displayName ?? knownMode?.title ?? "专注模式",
            symbolName: knownMode?.symbolName ?? "moon.fill"
        )
    }

    public func preservingMode(from previous: FocusModeStatus) -> FocusModeStatus {
        guard !isActive, identifier == nil, displayName == nil else { return self }
        return FocusModeStatus(
            isActive: false,
            identifier: previous.identifier,
            displayName: previous.displayName
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func knownMode(for identifier: String?) -> FocusModePresentation? {
        guard let identifier = identifier?.lowercased() else { return nil }
        let modes: [(token: String, title: String, symbolName: String)] = [
            ("work", "工作", "briefcase.fill"),
            ("personal", "个人", "person.fill"),
            ("sleep", "睡眠", "bed.double.fill"),
            ("fitness", "健身", "figure.run"),
            ("driving", "驾驶", "car.fill"),
            ("mindfulness", "正念", "brain.head.profile"),
            ("reading", "阅读", "book.fill"),
            ("gaming", "游戏", "gamecontroller.fill"),
            ("do-not-disturb", "勿扰", "moon.fill"),
            ("donotdisturb", "勿扰", "moon.fill"),
        ]
        guard let mode = modes.first(where: { identifier.contains($0.token) }) else { return nil }
        return FocusModePresentation(title: mode.title, symbolName: mode.symbolName)
    }
}

enum FocusModeStatusStore {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")

    static func decode(_ data: Data) throws -> FocusModeStatus {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let stores = root["data"] as? [[String: Any]]
        else {
            return .inactive
        }
        let records = stores.flatMap { $0["storeAssertionRecords"] as? [[String: Any]] ?? [] }
        let activeRecord = records.max { left, right in
            timestamp(in: left) < timestamp(in: right)
        }
        guard
            let details = activeRecord?["assertionDetails"] as? [String: Any],
            let identifier = details["assertionDetailsModeIdentifier"] as? String,
            !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .inactive
        }
        return FocusModeStatus(isActive: true, identifier: identifier)
    }

    static func load(from url: URL) async -> FocusModeStatus? {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decode(data)
        }.value
    }

    private static func timestamp(in record: [String: Any]) -> Double {
        (record["assertionStartDateTimestamp"] as? NSNumber)?.doubleValue ?? 0
    }
}

/// Monitors macOS Focus Mode through its local assertion store, with the private framework as a fallback.
@MainActor
public final class FocusModeMonitor: ObservableObject {
    @Published public private(set) var status = FocusModeStatus.inactive
    @Published public private(set) var isAvailable = false

    private let clientIdentifier: String
    private let statusStoreURL: URL
    private let storePollingInterval: Duration
    private var isRunning = false
    private var frameworkHandle: UnsafeMutableRawPointer?
    private var stateService: AnyObject?
    private var stateServiceClass: AnyClass?
    private var listener: FocusStateUpdateListener?
    private var storePollingTask: Task<Void, Never>?

    public init(clientIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.clientIdentifier = clientIdentifier ?? "dev.wzz.zisla"
        statusStoreURL = FocusModeStatusStore.defaultURL
        storePollingInterval = .seconds(1)
    }

    init(
        clientIdentifier: String,
        statusStoreURL: URL,
        storePollingInterval: Duration
    ) {
        self.clientIdentifier = clientIdentifier
        self.statusStoreURL = statusStoreURL
        self.storePollingInterval = storePollingInterval
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        if FileManager.default.isReadableFile(atPath: statusStoreURL.path) {
            startStoreMonitoring()
            return
        }

        guard let frameworkHandle = dlopen(
            "/System/Library/PrivateFrameworks/DoNotDisturb.framework/DoNotDisturb",
            RTLD_NOW | RTLD_LOCAL
        ) else {
            startStoreMonitoring()
            return
        }
        self.frameworkHandle = frameworkHandle

        guard let serviceClass = NSClassFromString("DNDStateService"),
              let service = makeStateService(serviceClass: serviceClass) else {
            releaseFramework()
            startStoreMonitoring()
            return
        }

        let listener = FocusStateUpdateListener(clientIdentifier: clientIdentifier) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.consume(status)
            }
        }
        guard add(listener, to: service, serviceClass: serviceClass) else {
            releaseFramework()
            startStoreMonitoring()
            return
        }

        stateService = service
        stateServiceClass = serviceClass
        self.listener = listener
        isAvailable = true
    }

    public func stop() {
        if let stateService, let stateServiceClass, let listener {
            remove(listener, from: stateService, serviceClass: stateServiceClass)
        }
        stateService = nil
        stateServiceClass = nil
        listener = nil
        storePollingTask?.cancel()
        storePollingTask = nil
        isAvailable = false
        isRunning = false
        releaseFramework()
    }

    private func consume(_ next: FocusModeStatus) {
        guard isRunning else { return }
        let resolved = next.preservingMode(from: status)
        guard status != resolved else { return }
        status = resolved
    }

    private func startStoreMonitoring() {
        isAvailable = FileManager.default.isReadableFile(atPath: statusStoreURL.path)
        startStorePolling()
    }

    private func startStorePolling() {
        let url = statusStoreURL
        let interval = storePollingInterval
        storePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                if let next = await FocusModeStatusStore.load(from: url) {
                    guard !Task.isCancelled else { return }
                    self?.consume(next)
                    self?.isAvailable = true
                }
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }

    private func releaseFramework() {
        if let frameworkHandle {
            dlclose(frameworkHandle)
            self.frameworkHandle = nil
        }
    }

    private func makeStateService(serviceClass: AnyClass) -> AnyObject? {
        let selector = NSSelectorFromString("_initWithClientIdentifier:")
        guard let instance = class_createInstance(serviceClass, 0) as AnyObject?,
              let implementation = class_getMethodImplementation(serviceClass, selector) else {
            return nil
        }
        typealias Initializer = @convention(c) (AnyObject, Selector, NSString) -> AnyObject?
        let initialize = unsafeBitCast(implementation, to: Initializer.self)
        return initialize(instance, selector, clientIdentifier as NSString)
    }

    private func add(
        _ listener: FocusStateUpdateListener,
        to service: AnyObject,
        serviceClass: AnyClass
    ) -> Bool {
        let selector = NSSelectorFromString("addStateUpdateListener:error:")
        guard let implementation = class_getMethodImplementation(serviceClass, selector) else {
            return false
        }
        typealias Add = @convention(c) (
            AnyObject,
            Selector,
            AnyObject,
            AutoreleasingUnsafeMutablePointer<NSError?>?
        ) -> Bool
        let add = unsafeBitCast(implementation, to: Add.self)
        var error: NSError?
        return add(service, selector, listener, &error)
    }

    private func remove(
        _ listener: FocusStateUpdateListener,
        from service: AnyObject,
        serviceClass: AnyClass
    ) {
        let selector = NSSelectorFromString("removeStateUpdateListener:error:")
        guard let implementation = class_getMethodImplementation(serviceClass, selector) else {
            return
        }
        typealias Remove = @convention(c) (
            AnyObject,
            Selector,
            AnyObject,
            AutoreleasingUnsafeMutablePointer<NSError?>?
        ) -> Bool
        let remove = unsafeBitCast(implementation, to: Remove.self)
        var error: NSError?
        _ = remove(service, selector, listener, &error)
    }
}

private final class FocusStateUpdateListener: NSObject {
    private let identifier: String
    private let onUpdate: (FocusModeStatus) -> Void

    init(clientIdentifier: String, onUpdate: @escaping (FocusModeStatus) -> Void) {
        identifier = clientIdentifier
        self.onUpdate = onUpdate
        super.init()
    }

    @objc var clientIdentifier: String { identifier }

    @objc(remoteService:didReceiveDoNotDisturbStateUpdate:)
    func remoteService(_ service: AnyObject, didReceiveDoNotDisturbStateUpdate update: AnyObject) {
        handle(update)
    }

    @objc(stateService:didReceiveDoNotDisturbStateUpdate:)
    func stateService(_ service: AnyObject, didReceiveDoNotDisturbStateUpdate update: AnyObject) {
        handle(update)
    }

    @objc(remoteService:didReceiveStateUpdate:)
    func remoteService(_ service: AnyObject, didReceiveStateUpdate update: AnyObject) {
        handle(update)
    }

    private func handle(_ update: AnyObject) {
        guard let status = Self.status(from: update) else { return }
        onUpdate(status)
    }

    fileprivate static func status(from update: AnyObject) -> FocusModeStatus? {
        let state = dynamicObject(update, for: "state") ?? update
        let stateObjects = [state, update]
        let modeObjects = stateObjects.compactMap {
            dynamicObject($0, for: "activeMode")
                ?? dynamicObject($0, for: "currentMode")
                ?? dynamicObject($0, for: "mode")
        }
        let allObjects = modeObjects + stateObjects
        let identifier = firstString(
            for: ["activeModeIdentifier", "modeIdentifier", "identifier"],
            in: allObjects
        )
        let displayName = firstString(
            for: ["displayName", "localizedName", "modeName", "name", "title"],
            in: modeObjects
        )
        let isActive = firstBool(for: ["isActive", "active", "enabled", "isEnabled"], in: stateObjects)
            ?? (identifier != nil || displayName != nil ? true : nil)
        guard let isActive else { return nil }
        return FocusModeStatus(
            isActive: isActive,
            identifier: identifier,
            displayName: displayName
        )
    }

    private static func firstString(for selectors: [String], in objects: [AnyObject]) -> String? {
        for object in objects {
            for selector in selectors {
                if let value = dynamicObject(object, for: selector) as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        return nil
    }

    private static func firstBool(for selectors: [String], in objects: [AnyObject]) -> Bool? {
        for object in objects {
            for selector in selectors {
                if let value = dynamicBool(object, for: selector) { return value }
            }
        }
        return nil
    }

    private static func dynamicObject(_ object: AnyObject, for selectorName: String) -> AnyObject? {
        (object as? NSObject)?.zislaDynamicObject(for: selectorName)
    }

    private static func dynamicBool(_ object: AnyObject, for selectorName: String) -> Bool? {
        (object as? NSObject)?.zislaDynamicBool(for: selectorName)
    }
}

private extension NSObject {
    func zislaDynamicObject(for selectorName: String) -> AnyObject? {
        let selector = NSSelectorFromString(selectorName)
        guard responds(to: selector),
              let implementation = class_getMethodImplementation(type(of: self), selector) else {
            return nil
        }
        typealias Getter = @convention(c) (AnyObject, Selector) -> AnyObject?
        let get = unsafeBitCast(implementation, to: Getter.self)
        return get(self, selector)
    }

    func zislaDynamicBool(for selectorName: String) -> Bool? {
        let selector = NSSelectorFromString(selectorName)
        guard responds(to: selector),
              let implementation = class_getMethodImplementation(type(of: self), selector) else {
            return nil
        }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let get = unsafeBitCast(implementation, to: Getter.self)
        return get(self, selector)
    }
}
