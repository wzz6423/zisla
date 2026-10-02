import Combine
import Darwin
import Foundation

public struct SignificantEnergyProcess: Equatable, Sendable {
    public let bundleIdentifier: String
    public let responsibleBundleIdentifier: String
    public let displayName: String

    public init(
        bundleIdentifier: String,
        responsibleBundleIdentifier: String,
        displayName: String
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.responsibleBundleIdentifier = responsibleBundleIdentifier
        self.displayName = displayName
    }
}

public enum SignificantEnergyUnavailableReason: Error, Equatable, Sendable {
    case unsupported
    case permissionDenied
    case invalidResponse
    case readFailed
}

public enum SignificantEnergyState: Equatable, Sendable {
    case idle
    case loading
    case available([SignificantEnergyProcess])
    case unavailable(SignificantEnergyUnavailableReason)
}

@MainActor
public final class SignificantEnergyMonitor: ObservableObject {
    @Published public private(set) var state: SignificantEnergyState = .idle

    private let reader: @Sendable () async throws -> [SignificantEnergyProcess]
    private let refreshEvents: AnyPublisher<Date, Never>
    private var timer: AnyCancellable?
    private var refreshTask: Task<Void, Never>?
    private var refreshID: UUID?

    public convenience init() {
        self.init(reader: { try await NativeSignificantEnergyReader.read() })
    }

    init(
        reader: @escaping @Sendable () async throws -> [SignificantEnergyProcess],
        refreshEvents: AnyPublisher<Date, Never> = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .eraseToAnyPublisher()
    ) {
        self.reader = reader
        self.refreshEvents = refreshEvents
    }

    isolated deinit {
        timer?.cancel()
        refreshTask?.cancel()
    }

    public func start() {
        guard timer == nil else { return }
        timer = refreshEvents.sink { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    @discardableResult
    public func refresh() -> Task<Void, Never> {
        if let refreshTask { return refreshTask }
        let requestID = UUID()
        refreshID = requestID
        if case .idle = state { state = .loading }

        let task = Task { [weak self, reader] in
            let result: SignificantEnergyState
            do {
                result = .available(try await reader())
            } catch let reason as SignificantEnergyUnavailableReason {
                result = .unavailable(reason)
            } catch {
                result = .unavailable(.readFailed)
            }
            guard let self, self.refreshID == requestID else { return }
            self.refreshTask = nil
            self.refreshID = nil
            if !Task.isCancelled {
                self.state = result
            } else if case .loading = self.state {
                self.state = .idle
            }
        }
        refreshTask = task
        return task
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
        state = .idle
    }
}

enum NativeSignificantEnergyReader {
    // The floating-point threshold is part of Control Center's native ABI; omitting it makes results depend on register contents.
    private typealias Query = @convention(c) (UInt64, Double, UInt64) -> Unmanaged<NSDictionary>?

    static func read() async throws -> [SignificantEnergyProcess] {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let processes = try autoreleasepool {
                guard let handle = dlopen("/usr/lib/libsystemstats.dylib", RTLD_NOW | RTLD_LOCAL) else {
                    throw SignificantEnergyUnavailableReason.unsupported
                }
                defer { dlclose(handle) }
                guard let symbol = dlsym(handle, "systemstats_get_top_coalitions") else {
                    throw SignificantEnergyUnavailableReason.unsupported
                }
                let query = unsafeBitCast(symbol, to: Query.self)
                // Control Center uses a 120-second window, an integrated threshold of 120 * 500, and five coalitions.
                guard let payload = query(120, 60_000, 5)?.takeUnretainedValue() else {
                    throw SignificantEnergyUnavailableReason.readFailed
                }
                return try parse(payload)
            }
            try Task.checkCancellation()
            return processes
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static func parse(_ payload: NSDictionary) throws -> [SignificantEnergyProcess] {
        guard let identifiers = payload["bundle_identifiers"] as? [String],
              let responsibleIdentifiers = payload["responsible_bundle_identifiers"] as? [String],
              let names = payload["display_names"] as? [String],
              identifiers.count == responsibleIdentifiers.count,
              identifiers.count == names.count else {
            throw SignificantEnergyUnavailableReason.invalidResponse
        }

        return try identifiers.indices.map { index in
            let identifier = identifiers[index]
            let responsibleIdentifier = responsibleIdentifiers[index]
            let name = names[index]
            guard identifier != "REDACTED", responsibleIdentifier != "REDACTED", name != "REDACTED" else {
                throw SignificantEnergyUnavailableReason.permissionDenied
            }
            guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SignificantEnergyUnavailableReason.invalidResponse
            }
            return SignificantEnergyProcess(
                bundleIdentifier: identifier,
                responsibleBundleIdentifier: responsibleIdentifier,
                displayName: name.isEmpty ? identifier : name
            )
        }
    }
}
