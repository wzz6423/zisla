import Combine
import Darwin
import Foundation
import ObjectiveC.runtime
import ZislaCore

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
    public var symbolName: String?

    public init(
        isActive: Bool,
        identifier: String? = nil,
        displayName: String? = nil,
        symbolName: String? = nil
    ) {
        self.isActive = isActive
        self.identifier = Self.nonEmpty(identifier)
        self.displayName = Self.nonEmpty(displayName)
        self.symbolName = Self.nonEmpty(symbolName)
    }

    public static let inactive = FocusModeStatus(isActive: false)

    public var presentation: FocusModePresentation {
        let knownMode = Self.knownMode(for: identifier)
        return FocusModePresentation(
            title: displayName ?? knownMode?.title ?? "专注模式",
            symbolName: symbolName ?? knownMode?.symbolName ?? "moon.fill"
        )
    }

    public func preservingMode(from previous: FocusModeStatus) -> FocusModeStatus {
        guard !isActive, identifier == nil, displayName == nil else { return self }
        return FocusModeStatus(
            isActive: false,
            identifier: previous.identifier,
            displayName: previous.displayName,
            symbolName: previous.symbolName
        )
    }

    func preservingMissingPresentation(from previous: FocusModeStatus) -> FocusModeStatus {
        guard identifier != nil, identifier == previous.identifier else { return self }
        return FocusModeStatus(
            isActive: isActive,
            identifier: identifier,
            displayName: displayName ?? previous.displayName,
            symbolName: symbolName ?? previous.symbolName
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
            ("workout", AppLocalization.text("健身"), "figure.run"),
            ("work", AppLocalization.text("工作"), "briefcase.fill"),
            ("personal", AppLocalization.text("个人"), "person.fill"),
            ("sleep", AppLocalization.text("睡眠"), "bed.double.fill"),
            ("fitness", AppLocalization.text("健身"), "figure.run"),
            ("driving", AppLocalization.text("驾驶"), "car.fill"),
            ("mindfulness", AppLocalization.text("正念"), "brain.head.profile"),
            ("reading", AppLocalization.text("阅读"), "book.fill"),
            ("gaming", AppLocalization.text("游戏"), "gamecontroller.fill"),
            ("do-not-disturb", AppLocalization.text("勿扰"), "moon.fill"),
            ("donotdisturb", AppLocalization.text("勿扰"), "moon.fill"),
        ]
        let mode = modes.first {
            identifier == $0.token || identifier.hasSuffix(".\($0.token)")
        } ?? modes.first { identifier.contains($0.token) }
        guard let mode else { return nil }
        return FocusModePresentation(title: mode.title, symbolName: mode.symbolName)
    }
}

public struct FocusModeTransition: Equatable, Sendable {
    public let id: UUID
    public let status: FocusModeStatus

    public init(status: FocusModeStatus) {
        id = UUID()
        self.status = status
    }
}

fileprivate struct FocusModeStoreSnapshot: Equatable, Sendable {
    let status: FocusModeStatus
    let transitionToken: String?
    let transitionTimestamp: TimeInterval?
}

enum FocusModeStatusStore {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    private static let recentInvalidationMaximumAge: TimeInterval = 5

    static func decode(
        _ data: Data,
        currentTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) throws -> FocusModeStatus {
        try decodeSnapshot(data, currentTimestamp: currentTimestamp).status
    }

    fileprivate static func decodeSnapshot(
        _ data: Data,
        currentTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) throws -> FocusModeStoreSnapshot {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let stores = root["data"] as? [[String: Any]]
        else {
            return FocusModeStoreSnapshot(
                status: .inactive,
                transitionToken: nil,
                transitionTimestamp: nil
            )
        }

        let invalidatedAssertionIDs = Set(stores.flatMap { store in
            (store["storeInvalidationRecords"] as? [[String: Any]] ?? []).compactMap { record in
                (record["invalidationAssertion"] as? [String: Any])?["assertionUUID"] as? String
            }
        })
        let snapshotTimestamp = (root["header"] as? [String: Any]).flatMap {
            timestamp(in: $0, key: "timestamp")
        }
        let records = stores.flatMap { store -> [[String: Any]] in
            let globalInvalidationTimestamp = (store["storeInvalidationRequestRecords"] as? [[String: Any]] ?? [])
                .compactMap { request -> Double? in
                    guard
                        let predicate = request["invalidationRequestPredicate"] as? [String: Any],
                        predicate["invalidationPredicateType"] as? String == "any"
                    else {
                        return nil
                    }
                    return timestamp(in: request, key: "invalidationRequestDateTimestamp")
                }
                .max()

            return (store["storeAssertionRecords"] as? [[String: Any]] ?? []).filter { record in
                guard
                    let details = record["assertionDetails"] as? [String: Any],
                    let identifier = details["assertionDetailsModeIdentifier"] as? String,
                    !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    return false
                }
                if let assertionID = record["assertionUUID"] as? String,
                   invalidatedAssertionIDs.contains(assertionID) {
                    return false
                }
                if let endTimestamp = timestamp(in: details, key: "assertionDetailsUserVisibleEndDate"),
                   let snapshotTimestamp,
                   endTimestamp <= snapshotTimestamp {
                    return false
                }
                if let assertionStart = timestamp(in: record, key: "assertionStartDateTimestamp"),
                   let globalInvalidationTimestamp,
                   assertionStart < globalInvalidationTimestamp {
                    return false
                }
                return true
            }
        }
        let activeRecord = records.max { left, right in
            timestamp(in: left) < timestamp(in: right)
        }
        guard
            let details = activeRecord?["assertionDetails"] as? [String: Any],
            let identifier = details["assertionDetailsModeIdentifier"] as? String,
            !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            let invalidatedMode = stores
                .flatMap { $0["storeInvalidationRecords"] as? [[String: Any]] ?? [] }
                .compactMap { record -> (identifier: String, timestamp: Double, token: String)? in
                    guard
                        let details = (record["invalidationAssertion"] as? [String: Any])?["assertionDetails"] as? [String: Any],
                        let identifier = details["assertionDetailsModeIdentifier"] as? String,
                        let timestamp = timestamp(in: record, key: "invalidationDateTimestamp"),
                        currentTimestamp >= timestamp,
                        currentTimestamp - timestamp <= recentInvalidationMaximumAge
                    else {
                        return nil
                    }
                    let assertionID = (record["invalidationAssertion"] as? [String: Any])?["assertionUUID"] as? String
                    return (
                        identifier,
                        timestamp,
                        transitionToken(
                            prefix: "invalidation",
                            identifier: identifier,
                            timestamp: timestamp,
                            assertionID: assertionID
                        )
                    )
                }
                .max { $0.timestamp < $1.timestamp }
            if let invalidatedMode {
                return FocusModeStoreSnapshot(
                    status: FocusModeStatus(isActive: false, identifier: invalidatedMode.identifier),
                    transitionToken: invalidatedMode.token,
                    transitionTimestamp: invalidatedMode.timestamp
                )
            }
            return FocusModeStoreSnapshot(
                status: .inactive,
                transitionToken: nil,
                transitionTimestamp: nil
            )
        }
        return FocusModeStoreSnapshot(
            status: FocusModeStatus(isActive: true, identifier: identifier),
            transitionToken: transitionToken(
                prefix: "assertion",
                identifier: identifier,
                timestamp: timestamp(in: activeRecord ?? [:]),
                assertionID: activeRecord?["assertionUUID"] as? String
            ),
            transitionTimestamp: timestamp(in: activeRecord ?? [:])
        )
    }

    static func load(from url: URL) async -> FocusModeStatus? {
        await loadSnapshot(from: url)?.status
    }

    fileprivate static func loadSnapshot(from url: URL) async -> FocusModeStoreSnapshot? {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decodeSnapshot(data)
        }.value
    }

    private static func transitionToken(
        prefix: String,
        identifier: String,
        timestamp: Double,
        assertionID: String?
    ) -> String {
        "\(prefix):\(assertionID ?? identifier):\(timestamp)"
    }

    private static func timestamp(in record: [String: Any]) -> Double {
        timestamp(in: record, key: "assertionStartDateTimestamp") ?? 0
    }

    private static func timestamp(in record: [String: Any], key: String) -> Double? {
        (record[key] as? NSNumber)?.doubleValue
    }
}

/// Monitors macOS Focus Mode through its local assertion store and private state service.
@MainActor
public final class FocusModeMonitor: ObservableObject {
    @Published public private(set) var status = FocusModeStatus.inactive
    @Published public private(set) var latestTransition: FocusModeTransition?
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
    private var lastStoreTransitionToken: String?
    private var storeMonitoringStartedAt: TimeInterval?
    private var hasLoadedStoreSnapshot = false
    public init(clientIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.clientIdentifier = clientIdentifier ?? "dev.wzz.zisla"
        statusStoreURL = FocusModeStatusStore.defaultURL
        storePollingInterval = .milliseconds(250)
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
        storeMonitoringStartedAt = Date().timeIntervalSinceReferenceDate
        startStoreMonitoring()

        guard let frameworkHandle = dlopen(
            "/System/Library/PrivateFrameworks/DoNotDisturb.framework/DoNotDisturb",
            RTLD_NOW | RTLD_LOCAL
        ) else {
            return
        }
        self.frameworkHandle = frameworkHandle

        guard let serviceClass = NSClassFromString("DNDStateService"),
              let service = makeStateService(serviceClass: serviceClass) else {
            releaseFramework()
            return
        }

        let listener = FocusStateUpdateListener(clientIdentifier: clientIdentifier) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.consume(status)
            }
        }
        guard add(listener, to: service, serviceClass: serviceClass) else {
            releaseFramework()
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
        lastStoreTransitionToken = nil
        storeMonitoringStartedAt = nil
        hasLoadedStoreSnapshot = false
        isAvailable = false
        isRunning = false
        releaseFramework()
    }

    private func consume(_ next: FocusModeStatus) {
        guard isRunning else { return }
        let resolved = next
            .preservingMissingPresentation(from: status)
            .preservingMode(from: status)
        guard status != resolved else { return }
        status = resolved
    }

    private func consumeStoreSnapshot(_ snapshot: FocusModeStoreSnapshot) {
        let isInitialSnapshot = !hasLoadedStoreSnapshot
        let transitionOccurredAfterStart = snapshot.transitionTimestamp.map {
            $0 >= (storeMonitoringStartedAt ?? .greatestFiniteMagnitude)
        } ?? false
        let isNewTransition = (!isInitialSnapshot || transitionOccurredAfterStart)
            && snapshot.transitionToken != nil
            && snapshot.transitionToken != lastStoreTransitionToken
        consume(snapshot.status)
        lastStoreTransitionToken = snapshot.transitionToken
        hasLoadedStoreSnapshot = true
        if isNewTransition {
            publishTransition(snapshot.status)
        }
    }

    private func publishTransition(_ status: FocusModeStatus) {
        latestTransition = FocusModeTransition(status: status)
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
                if let snapshot = await FocusModeStatusStore.loadSnapshot(from: url) {
                    guard !Task.isCancelled else { return }
                    self?.consumeStoreSnapshot(snapshot)
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

final class FocusStateUpdateListener: NSObject {
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

    static func status(from update: AnyObject) -> FocusModeStatus? {
        let state = dynamicObject(update, for: "state") ?? update
        let stateObjects = [state, update]
        let modeObjects = stateObjects.flatMap { object -> [AnyObject] in
            var modes = [
                dynamicObject(object, for: "activeMode"),
                dynamicObject(object, for: "currentMode"),
                dynamicObject(object, for: "mode"),
            ].compactMap { $0 }
            if let configuration = dynamicObject(object, for: "activeModeConfiguration"),
               let mode = dynamicObject(configuration, for: "mode") {
                modes.append(mode)
            }
            return modes
        }
        let allObjects = modeObjects + stateObjects
        let identifier = firstString(
            for: ["activeModeIdentifier", "modeIdentifier", "identifier"],
            in: allObjects
        )
        let displayName = firstString(
            for: ["name", "displayName", "localizedName", "modeName", "title"],
            in: modeObjects
        )
        let symbolObjects = modeObjects + modeObjects.compactMap {
            dynamicObject($0, for: "symbolDescriptor")
        }
        let symbolName = firstString(
            for: ["symbolImageName", "systemImageName", "symbolName", "imageName"],
            in: symbolObjects
        )
        guard let isActive = firstBool(
            for: ["isActive", "active", "enabled", "isEnabled"],
            in: stateObjects
        ) else {
            return nil
        }
        return FocusModeStatus(
            isActive: isActive,
            identifier: identifier,
            displayName: displayName,
            symbolName: symbolName
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
